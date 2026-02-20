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
        PreloadQuery(
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
            let fk = foreignKey ?? conventionalForeignKey(for: parentType)
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

    // MARK: - Batch Loading

    private static func batchLoadHasMany<Related: Schema>(
        entities: [T],
        keyPath: WritableKeyPath<T, SpectroLazyRelation<[Related]>>,
        foreignKey: String,
        repo: GenericDatabaseRepo
    ) async throws -> [T] {
        let metadata = await SchemaRegistry.shared.register(T.self)
        guard let pkField = metadata.primaryKeyField else { return entities }

        let parentIds = entities.compactMap { extractUUID(from: $0, fieldName: pkField) }
        guard !parentIds.isEmpty else { return entities }

        let related: [Related] = try await batchFetch(
            relatedType: Related.self,
            whereColumn: foreignKey.snakeCase(),
            inIds: parentIds,
            repo: repo
        )

        // Group related entities by their FK value (points back to parent)
        var grouped: [UUID: [Related]] = [:]
        for r in related {
            if let fkVal = extractUUID(from: r, fieldName: foreignKey) {
                grouped[fkVal, default: []].append(r)
            }
        }

        return entities.map { entity in
            var e = entity
            let parentId = extractUUID(from: entity, fieldName: pkField)
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

        let parentIds = entities.compactMap { extractUUID(from: $0, fieldName: pkField) }
        guard !parentIds.isEmpty else { return entities }

        let related: [Related] = try await batchFetch(
            relatedType: Related.self,
            whereColumn: foreignKey.snakeCase(),
            inIds: parentIds,
            repo: repo
        )

        // HasOne: keep only the first match per parent
        var grouped: [UUID: Related] = [:]
        for r in related {
            if let fkVal = extractUUID(from: r, fieldName: foreignKey),
               grouped[fkVal] == nil {
                grouped[fkVal] = r
            }
        }

        return entities.map { entity in
            var e = entity
            let parentId = extractUUID(from: entity, fieldName: pkField)
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
        // Collect unique FK values from entities
        var seen = Set<UUID>()
        var relatedIds: [UUID] = []
        for entity in entities {
            if let fkVal = extractUUID(from: entity, fieldName: foreignKey), seen.insert(fkVal).inserted {
                relatedIds.append(fkVal)
            }
        }
        guard !relatedIds.isEmpty else { return entities }

        // Fetch related by primary key
        let relatedMeta = await SchemaRegistry.shared.register(Related.self)
        guard let relPK = relatedMeta.primaryKeyField else { return entities }

        let related: [Related] = try await batchFetch(
            relatedType: Related.self,
            whereColumn: relPK.snakeCase(),
            inIds: relatedIds,
            repo: repo
        )

        var index: [UUID: Related] = [:]
        for r in related {
            if let id = extractUUID(from: r, fieldName: relPK) { index[id] = r }
        }

        return entities.map { entity in
            var e = entity
            let fkVal = extractUUID(from: entity, fieldName: foreignKey)
            let loaded: Related? = fkVal.flatMap { index[$0] }
            e[keyPath: keyPath] = SpectroLazyRelation(
                loaded: loaded,
                relationshipInfo: entity[keyPath: keyPath].relationshipInfo
            )
            return e
        }
    }

    // MARK: - Shared Query Helper

    /// Execute `SELECT * FROM table WHERE column IN (ids)`.
    /// The column name is already snake_cased at the call sites above.
    private static func batchFetch<Related: Schema>(
        relatedType: Related.Type,
        whereColumn: String,
        inIds: [UUID],
        repo: GenericDatabaseRepo
    ) async throws -> [Related] {
        let placeholders = Array(repeating: "?", count: inIds.count).joined(separator: ", ")
        let params = inIds.map { PostgresData(uuid: $0) }
        let condition = QueryCondition(
            sql: "\"\(whereColumn)\" IN (\(placeholders))",
            parameters: params
        )
        return try await repo.query(relatedType).where { _ in condition }.all()
    }

    // MARK: - Helpers

    /// Extract a UUID from any @ID, @ForeignKey, or bare UUID property by name.
    static func extractUUID<S: Schema>(from entity: S, fieldName: String) -> UUID? {
        for child in Mirror(reflecting: entity).children {
            guard let label = child.label else { continue }
            let name = label.hasPrefix("_") ? String(label.dropFirst()) : label
            guard name == fieldName else { continue }
            if let v = child.value as? ID { return v.wrappedValue }
            if let v = child.value as? ForeignKey { return v.wrappedValue }
            if let v = child.value as? UUID { return v }
        }
        return nil
    }

    /// Convention-based FK: "User" → "userId", "BlogPost" → "blogPostId".
    static func conventionalForeignKey(for type: any Schema.Type) -> String {
        let name = String(describing: type)
        return name.prefix(1).lowercased() + name.dropFirst() + "Id"
    }
}
