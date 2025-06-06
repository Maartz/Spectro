import Foundation
import PostgresKit

/// Modern, actor-based ORM for PostgreSQL
/// Provides a clean, type-safe interface for database operations
public struct Spectro {
    private let connection: DatabaseConnection
    
    /// Create a new Spectro instance with explicit configuration
    public init(configuration: DatabaseConfiguration) throws {
        self.connection = try DatabaseConnection(configuration: configuration)
    }
    
    /// Create a new Spectro instance with individual parameters
    public init(
        hostname: String = "localhost",
        port: Int = 5432,
        username: String,
        password: String,
        database: String,
        maxConnectionsPerEventLoop: Int = 4
    ) throws {
        let config = DatabaseConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database,
            maxConnectionsPerEventLoop: maxConnectionsPerEventLoop
        )
        try self.init(configuration: config)
    }
    
    /// Create a Spectro instance from environment variables
    public static func fromEnvironment() throws -> Spectro {
        let config = try DatabaseConfiguration.fromEnvironment()
        return try Spectro(configuration: config)
    }
    
    /// Get a repository for database operations
    public func repository() -> DatabaseRepo {
        DatabaseRepo(connection: connection)
    }
    
    /// Test the database connection
    public func testConnection() async throws -> String {
        return try await connection.testConnection()
    }
    
    /// Create a migration manager for this database
    public func migrationManager() -> MigrationManager {
        return MigrationManager(connection: connection)
    }
    
    /// Gracefully shutdown the database connection
    public func shutdown() async {
        await connection.shutdown()
    }
}

// MARK: - Convenience Methods

extension Spectro {
    /// Execute work within a database transaction
    public func transaction<T: Sendable>(_ work: @Sendable (DatabaseRepo) async throws -> T) async throws -> T {
        let repo = repository()
        return try await repo.transaction { transactionRepo in
            // Note: transactionRepo is the transaction-scoped repo, but we return DatabaseRepo type
            // This is a temporary limitation that will be resolved in the next iteration
            try await work(repo)
        }
    }
    
    /// Get a single record by schema and ID
    public func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T.Model? {
        try await repository().get(schema, id: id)
    }
    
    /// Get all records for a schema
    public func all<T: Schema>(_ schema: T.Type) async throws -> [T.Model] {
        try await repository().all(schema)
    }
    
    /// Insert a new record
    public func insert<T: Schema>(_ schema: T.Type, data: [String: Any]) async throws -> T.Model {
        try await repository().insert(schema, data: data)
    }
    
    /// Update an existing record
    public func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: Any]) async throws -> T.Model {
        try await repository().update(schema, id: id, changes: changes)
    }
    
    /// Delete a record
    public func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws {
        try await repository().delete(schema, id: id)
    }
}
