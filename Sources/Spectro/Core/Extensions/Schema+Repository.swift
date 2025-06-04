//
//  Schema+Repository.swift
//  Spectro
//
//  Created by William MARTIN on 6/4/25.
//

import Foundation

// Global repository configuration
public enum RepositoryConfiguration {
    private static let lock = NSLock()
    
    nonisolated(unsafe) private static var _defaultRepo: (any Repo)?
    
    public static var defaultRepo: (any Repo)? {
        lock.withLock { _defaultRepo }
    }
    
    public static func configure(with repo: any Repo) {
        lock.withLock { _defaultRepo = repo }
    }
}

// Disable concurrency warnings for this specific case
@_spi(ForTestingOnly)
extension RepositoryConfiguration {
    static func reset() {
        lock.withLock { _defaultRepo = nil }
    }
}

// Extension to add repository methods to all schemas
extension Schema {
    // Repository access - can be overridden by specific schemas
    public static var repo: any Repo {
        get {
            guard let repo = RepositoryConfiguration.defaultRepo else {
                fatalError("Repository not configured. Call RepositoryConfiguration.configure(with:) before using schemas.")
            }
            return repo
        }
    }
    
    // MARK: - Query Methods
    
    /// Start a query for this schema
    public static func query() -> Query {
        Query.from(Self.self)
    }
    
    // MARK: - Repository Methods
    
    /// Fetch all records
    public static func all(_ queryBuilder: ((Query) -> Query)? = nil) async throws -> [Model] {
        try await repo.all(Self.self, query: queryBuilder)
    }
    
    /// Get a record by ID
    public static func get(_ id: UUID) async throws -> Model? {
        try await repo.get(Self.self, id)
    }
    
    /// Get a record by ID or throw if not found
    public static func getOrFail(_ id: UUID) async throws -> Model {
        try await repo.getOrFail(Self.self, id)
    }
    
    /// Insert a new record
    public static func insert(_ changes: [String: Any]) async throws -> Model {
        let changeset = Changeset(Self.self, changes)
        return try await repo.insert(changeset)
    }
    
    /// Create and insert a new record with a changeset
    public static func create(_ changeset: Changeset<Self>) async throws -> Model {
        try await repo.insert(changeset)
    }
    
    /// Build a changeset for this schema
    public static func changeset(_ changes: [String: Any]) -> Changeset<Self> {
        Changeset(Self.self, changes)
    }
}

// Query execution extensions for type-safe query operations
extension Schema {
    /// Execute a query built from this schema
    public static func execute(_ query: Query) async throws -> [Model] {
        guard query.schema == Self.self else {
            fatalError("Query schema type mismatch")
        }
        return try await repo.all(Self.self, query: { _ in query })
    }
    
    /// Execute a query and return first result
    public static func executeFirst(_ query: Query) async throws -> Model? {
        var limitedQuery = query
        limitedQuery.limit = 1
        let results = try await execute(limitedQuery)
        return results.first
    }
    
    /// Execute a query and return exactly one result
    public static func executeOne(_ query: Query) async throws -> Model {
        guard let result = try await executeFirst(query) else {
            throw RepositoryError.notFound("No \(schemaName) found matching query")
        }
        return result
    }
    
    /// Check if query has any results
    public static func executeExists(_ query: Query) async throws -> Bool {
        let result = try await executeFirst(query)
        return result != nil
    }
}

// Extension for model instances
extension SchemaModel {
    /// Update this model with changes
    public func update(_ changes: [String: Any]) async throws -> SchemaModel<S> {
        let changeset = Changeset(S.self, changes)
        return try await S.repo.update(self, changeset)
    }
    
    /// Delete this model
    public func delete() async throws {
        try await S.repo.delete(self)
    }
    
    /// Reload this model from the database
    public func reload() async throws -> SchemaModel<S> {
        try await S.repo.getOrFail(S.self, id)
    }
}