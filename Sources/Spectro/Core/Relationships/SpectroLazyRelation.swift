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
        case loaded(T)
        /// The relationship failed to load.
        ///
        /// The associated error is constrained to `Sendable` so `LoadState`
        /// itself remains `Sendable`. Wrap non-Sendable errors in a
        /// `Sendable` container before storing them here.
        case error(any Error & Sendable)
    }

    private let loadState: LoadState
    private let relationshipInfo: RelationshipInfo

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
        case .hasMany:   return try await loadHasMany(using: repo)
        case .hasOne:    return try await loadHasOne(using: repo)
        case .belongsTo: return try await loadBelongsTo(using: repo)
        }
    }

    public func withLoaded(_ data: T) -> SpectroLazyRelation<T> {
        SpectroLazyRelation(loaded: data, relationshipInfo: relationshipInfo)
    }

    // MARK: - Private Loading Stubs

    private func loadHasMany(using repo: GenericDatabaseRepo) async throws -> T {
        throw SpectroError.notImplemented("HasMany loading — use RelationshipLoader.loadHasMany for now")
    }

    private func loadHasOne(using repo: GenericDatabaseRepo) async throws -> T {
        throw SpectroError.notImplemented("HasOne loading — use RelationshipLoader.loadHasOne for now")
    }

    private func loadBelongsTo(using repo: GenericDatabaseRepo) async throws -> T {
        throw SpectroError.notImplemented("BelongsTo loading — use RelationshipLoader.loadBelongsTo for now")
    }
}

// MARK: - Defaults

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

// MARK: - Batch Loader Stub

public struct RelationshipBatchLoader {
    public static func loadBatch<Parent: Schema, Related: Schema>(
        for entities: [Parent],
        relationship: String,
        relationshipType: RelationType,
        relatedType: Related.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> [UUID: [Related]] {
        // TODO: implement batch loading to prevent N+1 queries
        return [:]
    }
}
