import Foundation
@preconcurrency import PostgresNIO
import SpectroCore

/// Query that batch-loads relationships for a set of parent entities,
/// eliminating the N+1 query problem.
///
/// ## Usage
///
/// ```swift
/// // Load users with their posts in two queries total (not N+1)
/// let users = try await repo.query(User.self)
///     .where { $0.isActive == true }
///     .preload(\.$posts)            // FK inferred: "userId"
///     .preload(\.$profile)          // FK inferred: "userId"
///     .all()
///
/// // Override FK when it doesn't follow convention:
/// let posts = try await repo.query(Post.self)
///     .preload(\.$author, foreignKey: "authorId")
///     .all()
/// ```
public struct PreloadQuery<T: Schema>: Sendable {
    internal let baseQuery: Query<T>
    // Each preloader is a @Sendable closure that takes the current entities
    // and a repo, and returns updated entities with the relationship filled in.
    internal let preloaders: [@Sendable ([T], GenericDatabaseRepo) async throws -> [T]]

    internal init(
        baseQuery: Query<T>,
        preloaders: [@Sendable ([T], GenericDatabaseRepo) async throws -> [T]]
    ) {
        self.baseQuery = baseQuery
        self.preloaders = preloaders
    }

    // MARK: - Chaining Additional Preloads

    public func preload<Related: Schema>(
        _ keyPath: WritableKeyPath<T, SpectroLazyRelation<[Related]>>,
        foreignKey: String? = nil
    ) -> PreloadQuery<T> {
        // Detect if this is a many-to-many relationship by checking the temp instance
        let tempInstance = T()
        let kind = tempInstance[keyPath: keyPath].relationshipInfo.kind
        if kind == .manyToMany {
            return PreloadQuery(
                baseQuery: baseQuery,
                preloaders: preloaders + [Self.manyToManyPreloader(keyPath: keyPath, parentType: T.self)]
            )
        }
        return PreloadQuery(
            baseQuery: baseQuery,
            preloaders: preloaders + [Self.hasManyPreloader(keyPath: keyPath, foreignKey: foreignKey, parentType: T.self)]
        )
    }

    public func preload<Related: Schema>(
        _ keyPath: WritableKeyPath<T, SpectroLazyRelation<Related?>>,
        foreignKey: String? = nil
    ) -> PreloadQuery<T> {
        PreloadQuery(
            baseQuery: baseQuery,
            preloaders: preloaders + [Self.singlePreloader(keyPath: keyPath, foreignKey: foreignKey, parentType: T.self)]
        )
    }

    // MARK: - Query Chaining

    public func `where`(_ condition: (QueryBuilder<T>) -> QueryCondition) -> PreloadQuery<T> {
        PreloadQuery(baseQuery: baseQuery.where(condition), preloaders: preloaders)
    }

    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>, _ direction: OrderDirection = .asc) -> PreloadQuery<T> {
        PreloadQuery(baseQuery: baseQuery.orderBy(field, direction), preloaders: preloaders)
    }

    public func limit(_ count: Int) -> PreloadQuery<T> {
        PreloadQuery(baseQuery: baseQuery.limit(count), preloaders: preloaders)
    }

    public func offset(_ count: Int) -> PreloadQuery<T> {
        PreloadQuery(baseQuery: baseQuery.offset(count), preloaders: preloaders)
    }

    // MARK: - Execution

    public func all() async throws -> [T] {
        let entities = try await baseQuery.all()
        guard !entities.isEmpty, !preloaders.isEmpty else { return entities }
        let repo = GenericDatabaseRepo(connection: baseQuery.connection)
        var result = entities
        for preloader in preloaders {
            result = try await preloader(result, repo)
        }
        return result
    }

    public func first() async throws -> T? {
        try await limit(1).all().first
    }

    // MARK: - Preloader Factory Methods

    // WritableKeyPath has @unchecked Sendable from Swift stdlib but the Swift 6.2
    // checker doesn't always propagate it through generic parameters. Wrap in this
    // box so the closure can capture it without a Sendable diagnostic.
    private struct KPBox<Root, Value>: @unchecked Sendable {
        let value: WritableKeyPath<Root, Value>
    }

    /// Creates a preloader for a has-many relationship.
    /// FK is on the *related* table: `SELECT * FROM related WHERE fk IN (parentIds)`.
    static func hasManyPreloader<Related: Schema>(
        keyPath: WritableKeyPath<T, SpectroLazyRelation<[Related]>>,
        foreignKey: String?,
        parentType: T.Type
    ) -> @Sendable ([T], GenericDatabaseRepo) async throws -> [T] {
        let fk = foreignKey ?? conventionalForeignKey(for: parentType)
        let box = KPBox(value: keyPath)
        return { entities, repo in
            try await batchLoadHasMany(entities: entities, keyPath: box.value, foreignKey: fk, repo: repo)
        }
    }

    /// Creates a preloader for a has-one or belongs-to relationship.
    /// Reads `RelationshipInfo.kind` from a temporary instance to distinguish them.
    static func singlePreloader<Related: Schema>(
        keyPath: WritableKeyPath<T, SpectroLazyRelation<Related?>>,
        foreignKey: String?,
        parentType: T.Type
    ) -> @Sendable ([T], GenericDatabaseRepo) async throws -> [T] {
        let tempInstance = T()
        let kind = tempInstance[keyPath: keyPath].relationshipInfo.kind
        let box = KPBox(value: keyPath)

        switch kind {
        case .hasOne:
            let fk = foreignKey ?? conventionalForeignKey(for: parentType)
            return { entities, repo in
                try await batchLoadHasOne(entities: entities, keyPath: box.value, foreignKey: fk, repo: repo)
            }
        case .belongsTo:
            let fk = foreignKey ?? conventionalForeignKey(for: Related.self)
            return { entities, repo in
                try await batchLoadBelongsTo(entities: entities, keyPath: box.value, foreignKey: fk, repo: repo)
            }
        default:
            let fk = foreignKey ?? conventionalForeignKey(for: parentType)
            return { entities, repo in
                try await batchLoadHasOne(entities: entities, keyPath: box.value, foreignKey: fk, repo: repo)
            }
        }
    }

    /// Creates a preloader for a many-to-many relationship.
    /// Queries the junction table, then the related table, grouping results back to parents.
    static func manyToManyPreloader<Related: Schema>(
        keyPath: WritableKeyPath<T, SpectroLazyRelation<[Related]>>,
        parentType: T.Type
    ) -> @Sendable ([T], GenericDatabaseRepo) async throws -> [T] {
        let tempInstance = T()
        let relInfo = tempInstance[keyPath: keyPath].relationshipInfo
        let junctionTable = relInfo.junctionTable ?? ""
        let parentFK = (relInfo.parentForeignKey?.isEmpty == false)
            ? relInfo.parentForeignKey!
            : conventionalForeignKey(for: parentType)
        let relatedFK = (relInfo.relatedForeignKey?.isEmpty == false)
            ? relInfo.relatedForeignKey!
            : conventionalForeignKey(for: Related.self)
        let box = KPBox(value: keyPath)
        return { entities, repo in
            try await batchLoadManyToMany(
                entities: entities,
                keyPath: box.value,
                junctionTable: junctionTable,
                parentFK: parentFK,
                relatedFK: relatedFK,
                repo: repo
            )
        }
    }

    // MARK: - Batch Loading

    private static func batchLoadManyToMany<Related: Schema>(
        entities: [T],
        keyPath: WritableKeyPath<T, SpectroLazyRelation<[Related]>>,
        junctionTable: String,
        parentFK: String,
        relatedFK: String,
        repo: GenericDatabaseRepo
    ) async throws -> [T] {
        let metadata = await SchemaRegistry.shared.register(T.self)
        guard let pkField = metadata.primaryKeyField else { return entities }

        // Extract both AnyHashable keys (for dict grouping) and PostgresData (for SQL params)
        var parentKeys: [AnyHashable] = []
        var parentParams: [PostgresData] = []
        for entity in entities {
            if let key = extractPrimaryKey(from: entity, fieldName: pkField),
               let data = extractPrimaryKeyData(from: entity, fieldName: pkField) {
                parentKeys.append(key)
                parentParams.append(data)
            }
        }
        guard !parentKeys.isEmpty else { return entities }

        // Step 1: Query junction table for all rows matching parent IDs
        let junctionRows = try await batchFetchJunction(
            junctionTable: junctionTable,
            whereColumn: parentFK.snakeCase(),
            relatedColumn: relatedFK.snakeCase(),
            inParams: parentParams,
            repo: repo
        )

        // Build parent → [relatedId] mapping and collect unique related IDs
        var parentToRelatedIds: [AnyHashable: [AnyHashable]] = [:]
        var uniqueRelatedKeys = Set<AnyHashable>()
        var uniqueRelatedParams: [PostgresData] = []
        for (pId, rId, rData) in junctionRows {
            parentToRelatedIds[pId, default: []].append(rId)
            if uniqueRelatedKeys.insert(rId).inserted {
                uniqueRelatedParams.append(rData)
            }
        }

        guard !uniqueRelatedKeys.isEmpty else {
            // No junction rows found — return entities with empty arrays
            return entities.map { entity in
                var e = entity
                e[keyPath: keyPath] = SpectroLazyRelation(
                    loaded: [],
                    relationshipInfo: entity[keyPath: keyPath].relationshipInfo
                )
                return e
            }
        }

        // Step 2: Fetch related entities by their PK
        let relatedMeta = await SchemaRegistry.shared.register(Related.self)
        guard let relPK = relatedMeta.primaryKeyField else { return entities }

        let relatedEntities: [Related] = try await batchFetch(
            relatedType: Related.self,
            whereColumn: relPK.snakeCase(),
            inParams: uniqueRelatedParams,
            repo: repo
        )

        // Index related entities by PK
        var relatedIndex: [AnyHashable: Related] = [:]
        for r in relatedEntities {
            if let id = extractPrimaryKey(from: r, fieldName: relPK) {
                relatedIndex[id] = r
            }
        }

        // Step 3: Map results back to parent entities
        return entities.map { entity in
            var e = entity
            let parentId = extractPrimaryKey(from: entity, fieldName: pkField)
            let relatedIds = parentId.flatMap { parentToRelatedIds[$0] } ?? []
            let loaded = relatedIds.compactMap { relatedIndex[$0] }
            e[keyPath: keyPath] = SpectroLazyRelation(
                loaded: loaded,
                relationshipInfo: entity[keyPath: keyPath].relationshipInfo
            )
            return e
        }
    }

    private static func batchLoadHasMany<Related: Schema>(
        entities: [T],
        keyPath: WritableKeyPath<T, SpectroLazyRelation<[Related]>>,
        foreignKey: String,
        repo: GenericDatabaseRepo
    ) async throws -> [T] {
        let metadata = await SchemaRegistry.shared.register(T.self)
        guard let pkField = metadata.primaryKeyField else { return entities }

        // Extract both AnyHashable keys and PostgresData params in parallel
        var parentParams: [PostgresData] = []
        for entity in entities {
            if let data = extractPrimaryKeyData(from: entity, fieldName: pkField) {
                parentParams.append(data)
            }
        }
        guard !parentParams.isEmpty else { return entities }

        let related: [Related] = try await batchFetch(
            relatedType: Related.self,
            whereColumn: foreignKey.snakeCase(),
            inParams: parentParams,
            repo: repo
        )

        // Group related entities by their FK value (points back to parent)
        var grouped: [AnyHashable: [Related]] = [:]
        for r in related {
            if let fkVal = extractPrimaryKey(from: r, fieldName: foreignKey) {
                grouped[fkVal, default: []].append(r)
            }
        }

        return entities.map { entity in
            var e = entity
            let parentId = extractPrimaryKey(from: entity, fieldName: pkField)
            let loaded = parentId.flatMap { grouped[$0] } ?? []
            e[keyPath: keyPath] = SpectroLazyRelation(
                loaded: loaded,
                relationshipInfo: entity[keyPath: keyPath].relationshipInfo
            )
            return e
        }
    }

    private static func batchLoadHasOne<Related: Schema>(
        entities: [T],
        keyPath: WritableKeyPath<T, SpectroLazyRelation<Related?>>,
        foreignKey: String,
        repo: GenericDatabaseRepo
    ) async throws -> [T] {
        let metadata = await SchemaRegistry.shared.register(T.self)
        guard let pkField = metadata.primaryKeyField else { return entities }

        var parentParams: [PostgresData] = []
        for entity in entities {
            if let data = extractPrimaryKeyData(from: entity, fieldName: pkField) {
                parentParams.append(data)
            }
        }
        guard !parentParams.isEmpty else { return entities }

        let related: [Related] = try await batchFetch(
            relatedType: Related.self,
            whereColumn: foreignKey.snakeCase(),
            inParams: parentParams,
            repo: repo
        )

        // HasOne: keep only the first match per parent
        var grouped: [AnyHashable: Related] = [:]
        for r in related {
            if let fkVal = extractPrimaryKey(from: r, fieldName: foreignKey),
               grouped[fkVal] == nil {
                grouped[fkVal] = r
            }
        }

        return entities.map { entity in
            var e = entity
            let parentId = extractPrimaryKey(from: entity, fieldName: pkField)
            let loaded: Related? = parentId.flatMap { grouped[$0] }
            e[keyPath: keyPath] = SpectroLazyRelation(
                loaded: loaded,
                relationshipInfo: entity[keyPath: keyPath].relationshipInfo
            )
            return e
        }
    }

    private static func batchLoadBelongsTo<Related: Schema>(
        entities: [T],
        keyPath: WritableKeyPath<T, SpectroLazyRelation<Related?>>,
        foreignKey: String,      // Column on T that holds the related entity's ID
        repo: GenericDatabaseRepo
    ) async throws -> [T] {
        // Collect unique FK values from entities (both AnyHashable for keying and PostgresData for query)
        var seen = Set<AnyHashable>()
        var relatedParams: [PostgresData] = []
        for entity in entities {
            if let fkVal = extractPrimaryKey(from: entity, fieldName: foreignKey),
               seen.insert(fkVal).inserted,
               let fkData = extractPrimaryKeyData(from: entity, fieldName: foreignKey) {
                relatedParams.append(fkData)
            }
        }
        guard !relatedParams.isEmpty else { return entities }

        // Fetch related by primary key
        let relatedMeta = await SchemaRegistry.shared.register(Related.self)
        guard let relPK = relatedMeta.primaryKeyField else { return entities }

        let related: [Related] = try await batchFetch(
            relatedType: Related.self,
            whereColumn: relPK.snakeCase(),
            inParams: relatedParams,
            repo: repo
        )

        var index: [AnyHashable: Related] = [:]
        for r in related {
            if let id = extractPrimaryKey(from: r, fieldName: relPK) { index[id] = r }
        }

        return entities.map { entity in
            var e = entity
            let fkVal = extractPrimaryKey(from: entity, fieldName: foreignKey)
            let loaded: Related? = fkVal.flatMap { index[$0] }
            e[keyPath: keyPath] = SpectroLazyRelation(
                loaded: loaded,
                relationshipInfo: entity[keyPath: keyPath].relationshipInfo
            )
            return e
        }
    }

    // MARK: - Shared Query Helper

    /// Execute `SELECT * FROM table WHERE column IN (params)`.
    /// The column name is already snake_cased at the call sites above.
    /// Accepts pre-built `[PostgresData]` so callers can pass any PK type.
    private static func batchFetch<Related: Schema>(
        relatedType: Related.Type,
        whereColumn: String,
        inParams: [PostgresData],
        repo: GenericDatabaseRepo
    ) async throws -> [Related] {
        let placeholders = Array(repeating: "?", count: inParams.count).joined(separator: ", ")
        let condition = QueryCondition(
            sql: "\"\(whereColumn)\" IN (\(placeholders))",
            parameters: inParams
        )
        return try await repo.query(relatedType).where { _ in condition }.all()
    }

    /// Execute `SELECT parentFK, relatedFK FROM junction WHERE parentFK IN (params)`.
    /// Returns an array of (parentKey, relatedKey, relatedData) tuples from the junction table.
    /// The third element carries the `PostgresData` for the related ID so callers can pass it
    /// directly to `batchFetch` without lossy conversions.
    private static func batchFetchJunction(
        junctionTable: String,
        whereColumn: String,
        relatedColumn: String,
        inParams: [PostgresData],
        repo: GenericDatabaseRepo
    ) async throws -> [(AnyHashable, AnyHashable, PostgresData)] {
        let placeholders = (1...inParams.count).map { "$\($0)" }.joined(separator: ", ")
        let sql = """
            SELECT "\(whereColumn)", "\(relatedColumn)" FROM "\(junctionTable)" WHERE "\(whereColumn)" IN (\(placeholders))
            """

        let rows = try await repo.executeRawQuery(
            sql: sql,
            parameters: inParams
        )

        var result: [(AnyHashable, AnyHashable, PostgresData)] = []
        for row in rows {
            let ra = row.makeRandomAccess()
            let parentData = ra[data: whereColumn]
            let relatedData = ra[data: relatedColumn]
            if let parentKey = anyHashableFromPostgresData(parentData),
               let relatedKey = anyHashableFromPostgresData(relatedData) {
                result.append((parentKey, relatedKey, relatedData))
            }
        }
        return result
    }

    /// Extract an `AnyHashable` value from `PostgresData`, supporting UUID, Int, and String.
    private static func anyHashableFromPostgresData(_ data: PostgresData) -> AnyHashable? {
        if let v = data.uuid { return AnyHashable(v) }
        if let v = data.int { return AnyHashable(v) }
        if let v = data.string { return AnyHashable(v) }
        return nil
    }

    // MARK: - Helpers

    /// Extract a primary key value from any @ID, @ForeignKey, or bare UUID/Int/String property by name.
    /// Returns as `AnyHashable` for use as dictionary keys and `PostgresData` for query parameters.
    static func extractPrimaryKey<S: Schema>(from entity: S, fieldName: String) -> AnyHashable? {
        for child in Mirror(reflecting: entity).children {
            guard let label = child.label else { continue }
            let name = label.hasPrefix("_") ? String(label.dropFirst()) : label
            guard name == fieldName else { continue }
            if let v = child.value as? any PrimaryKeyWrapperProtocol { return v.primaryKeyHashable }
            if let v = child.value as? any ForeignKeyWrapperProtocol { return v.foreignKeyHashable }
            if let v = child.value as? UUID { return AnyHashable(v) }
            if let v = child.value as? Int { return AnyHashable(v) }
            if let v = child.value as? String { return AnyHashable(v) }
        }
        return nil
    }

    /// Extract `PostgresData` from any @ID, @ForeignKey, or bare UUID/Int/String property by name.
    static func extractPrimaryKeyData<S: Schema>(from entity: S, fieldName: String) -> PostgresData? {
        for child in Mirror(reflecting: entity).children {
            guard let label = child.label else { continue }
            let name = label.hasPrefix("_") ? String(label.dropFirst()) : label
            guard name == fieldName else { continue }
            if let v = child.value as? any PrimaryKeyWrapperProtocol { return v.primaryKeyPostgresData }
            if let v = child.value as? any ForeignKeyWrapperProtocol { return v.foreignKeyPostgresData }
            if let v = child.value as? UUID { return PostgresData(uuid: v) }
            if let v = child.value as? Int { return PostgresData(int: v) }
            if let v = child.value as? String { return PostgresData(string: v) }
        }
        return nil
    }

    /// Convention-based FK: "User" → "userId", "BlogPost" → "blogPostId".
    static func conventionalForeignKey(for type: any Schema.Type) -> String {
        let name = String(describing: type)
        return name.prefix(1).lowercased() + name.dropFirst() + "Id"
    }
}
