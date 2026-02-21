import Foundation
@preconcurrency import PostgresNIO

/// Core lazy relation type for relationship loading.
///
/// All state changes happen through value-copying (`withLoaded(_:)`), making
/// this type safe to pass across actor boundaries.
public struct SpectroLazyRelation<T: Sendable>: Sendable {

    /// Loading state for a lazy relationship.
    public enum LoadState: Sendable {
        case notLoaded
        case loading
        indirect case loaded(T)
        /// The relationship failed to load.
        ///
        /// The associated error is constrained to `Sendable` so `LoadState`
        /// itself remains `Sendable`. Wrap non-Sendable errors in a
        /// `Sendable` container before storing them here.
        case error(any Error & Sendable)
    }

    private let loadState: LoadState
    // internal so PreloadQuery can read the kind/foreignKey when injecting loaded data
    internal let relationshipInfo: RelationshipInfo

    // MARK: - Init

    public init(relationshipInfo: RelationshipInfo) {
        self.loadState = .notLoaded
        self.relationshipInfo = relationshipInfo
    }

    public init(loaded data: T, relationshipInfo: RelationshipInfo) {
        self.loadState = .loaded(data)
        self.relationshipInfo = relationshipInfo
    }

    public init() {
        self.loadState = .notLoaded
        self.relationshipInfo = RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .hasMany,
            foreignKey: ""
        )
    }

    // MARK: - State Access

    public var isLoaded: Bool {
        if case .loaded = loadState { return true }
        return false
    }

    public var value: T? {
        if case .loaded(let data) = loadState { return data }
        return nil
    }

    public var state: LoadState { loadState }

    // MARK: - Loading

    public func load(using repo: GenericDatabaseRepo) async throws -> T {
        if case .loaded(let data) = loadState { return data }

        switch relationshipInfo.kind {
        case .hasMany:    return try await loadHasMany(using: repo)
        case .hasOne:     return try await loadHasOne(using: repo)
        case .belongsTo:  return try await loadBelongsTo(using: repo)
        case .manyToMany: return try await loadManyToMany(using: repo)
        }
    }

    public func withLoaded(_ data: T) -> SpectroLazyRelation<T> {
        SpectroLazyRelation(loaded: data, relationshipInfo: relationshipInfo)
    }

    // MARK: - Private Loading Methods
    //
    // These methods cannot be fully implemented because SpectroLazyRelation<T>
    // erases the concrete Schema type into T (which is just Sendable). At
    // runtime we only have `relationshipInfo.relatedTypeName` as a String,
    // which is insufficient to construct a typed Query<Related>.
    //
    // Additionally, SpectroLazyRelation is a value type embedded in the
    // parent struct — it has no reference back to its parent entity, so it
    // cannot obtain the parent's primary key (needed for HasMany/HasOne) or
    // the foreign key value (needed for BelongsTo).
    //
    // Working alternatives:
    //   - Single-entity loading: use RelationshipLoader.loadHasMany/loadHasOne/loadBelongsTo
    //     or the Schema extension methods (entity.loadHasMany(Child.self, ...))
    //   - Batch loading (N+1 safe): use Query<T>.preload(\.$relationship)
    //
    // To make load(using:) work in the future, SpectroLazyRelation would need:
    //   1. A stored type-erased loader closure: `@Sendable (GenericDatabaseRepo) async throws -> T`
    //      captured at init time in the property wrapper when the concrete types are known.
    //   2. The parent entity's ID or FK value injected when the struct is created/hydrated
    //      from a database row (e.g., in SchemaMapper or build(from:)).

    private func loadHasMany(using repo: GenericDatabaseRepo) async throws -> T {
        throw SpectroError.notImplemented(
            "SpectroLazyRelation.load(using:) cannot resolve the concrete Schema type for '\(relationshipInfo.relatedTypeName)' at runtime. "
            + "Use the typed API instead: parent.loadHasMany(\(relationshipInfo.relatedTypeName).self, foreignKey: \"\(relationshipInfo.foreignKey ?? "<inferred>")\", using: repo) "
            + "or batch-load via Query<Parent>.preload(\\.$\(relationshipInfo.name))."
        )
    }

    private func loadHasOne(using repo: GenericDatabaseRepo) async throws -> T {
        throw SpectroError.notImplemented(
            "SpectroLazyRelation.load(using:) cannot resolve the concrete Schema type for '\(relationshipInfo.relatedTypeName)' at runtime. "
            + "Use the typed API instead: parent.loadHasOne(\(relationshipInfo.relatedTypeName).self, foreignKey: \"\(relationshipInfo.foreignKey ?? "<inferred>")\", using: repo) "
            + "or batch-load via Query<Parent>.preload(\\.$\(relationshipInfo.name))."
        )
    }

    private func loadBelongsTo(using repo: GenericDatabaseRepo) async throws -> T {
        throw SpectroError.notImplemented(
            "SpectroLazyRelation.load(using:) cannot resolve the concrete Schema type for '\(relationshipInfo.relatedTypeName)' at runtime. "
            + "Use the typed API instead: child.loadBelongsTo(\(relationshipInfo.relatedTypeName).self, foreignKey: \"\(relationshipInfo.foreignKey ?? "<inferred>")\", using: repo) "
            + "or batch-load via Query<Parent>.preload(\\.$\(relationshipInfo.name))."
        )
    }

    private func loadManyToMany(using repo: GenericDatabaseRepo) async throws -> T {
        throw SpectroError.notImplemented(
            "SpectroLazyRelation.load(using:) cannot resolve the concrete Schema type for '\(relationshipInfo.relatedTypeName)' at runtime. "
            + "Use batch-load via Query<Parent>.preload(\\.$\(relationshipInfo.name)) for many-to-many relationships."
        )
    }
}

// MARK: - Typed Loading (HasMany)
//
// These constrained extensions provide load(from:using:) which accepts the
// parent entity with its concrete type, enabling actual database queries.

extension SpectroLazyRelation where T == [any Schema] {
    public static var empty: SpectroLazyRelation<T> {
        SpectroLazyRelation(loaded: [], relationshipInfo: RelationshipInfo(
            name: "", relatedTypeName: "", kind: .hasMany, foreignKey: ""
        ))
    }
}

extension SpectroLazyRelation where T: Schema {
    public static var empty: SpectroLazyRelation<T?> {
        SpectroLazyRelation<T?>(loaded: nil, relationshipInfo: RelationshipInfo(
            name: "", relatedTypeName: String(describing: T.self), kind: .hasOne, foreignKey: ""
        ))
    }
}

// MARK: - Typed Load from Parent

extension SpectroLazyRelation {

    /// Load a has-many relationship given the parent entity.
    ///
    /// This method bridges to `RelationshipLoader.loadHasMany` using the
    /// concrete parent and child types so that a real database query can be
    /// executed.
    ///
    /// ```swift
    /// let posts = try await user.$posts.load(from: user, childType: Post.self, using: repo)
    /// ```
    public func load<Parent: Schema, Child: Schema>(
        from parent: Parent,
        childType: Child.Type,
        using repo: GenericDatabaseRepo
    ) async throws -> [Child] where T == [Child] {
        if case .loaded(let data) = loadState { return data }
        let fk = relationshipInfo.foreignKey
            ?? PreloadQuery<Parent>.conventionalForeignKey(for: Parent.self)
        return try await RelationshipLoader.loadHasMany(
            for: parent,
            relationship: relationshipInfo.name,
            childType: childType,
            foreignKey: fk,
            using: repo
        )
    }

    /// Load a has-one relationship given the parent entity.
    ///
    /// ```swift
    /// let profile = try await user.$profile.load(from: user, relatedType: Profile.self, using: repo)
    /// ```
    public func load<Parent: Schema, Related: Schema>(
        from parent: Parent,
        relatedType: Related.Type,
        using repo: GenericDatabaseRepo
    ) async throws -> Related? where T == Related? {
        if case .loaded(let data) = loadState { return data }

        switch relationshipInfo.kind {
        case .hasOne:
            let fk = relationshipInfo.foreignKey
                ?? PreloadQuery<Parent>.conventionalForeignKey(for: Parent.self)
            return try await RelationshipLoader.loadHasOne(
                for: parent,
                relationship: relationshipInfo.name,
                childType: relatedType,
                foreignKey: fk,
                using: repo
            )
        case .belongsTo:
            let fk = relationshipInfo.foreignKey
                ?? PreloadQuery<Related>.conventionalForeignKey(for: Related.self)
            return try await RelationshipLoader.loadBelongsTo(
                for: parent,
                relationship: relationshipInfo.name,
                parentType: relatedType,
                foreignKey: fk,
                using: repo
            )
        default:
            throw SpectroError.relationshipError(
                from: String(describing: Parent.self),
                to: String(describing: Related.self),
                reason: "Expected hasOne or belongsTo but got \(relationshipInfo.kind)"
            )
        }
    }
}
