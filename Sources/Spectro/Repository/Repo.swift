import Foundation

/// Core repository protocol for database operations
/// All operations are async and throw errors for proper error handling
public protocol Repo: Sendable {
    /// Get a single record by ID
    func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T?
    
    /// Get a single record by ID or throw if not found
    func getOrFail<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T
    
    /// Get all records for a schema
    func all<T: Schema>(_ schema: T.Type) async throws -> [T]
    
    /// Insert a new record
    func insert<T: Schema>(_ instance: T) async throws -> T
    
    /// Update an existing record by ID
    func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: Any]) async throws -> T
    
    /// Delete a record by ID
    func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws
    
    /// Execute operations within a transaction
    func transaction<T: Sendable>(_ work: @escaping @Sendable (Repo) async throws -> T) async throws -> T
}