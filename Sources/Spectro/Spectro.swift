import Foundation
import PostgresKit

/// Swift ORM for PostgreSQL with property wrapper schemas and actor-based concurrency.
///
/// Spectro provides type-safe database interactions using property wrappers for schema definition
/// and closure-based query syntax. Built on PostgresNIO with full Swift 6 concurrency support.
///
/// ## Basic Usage
///
/// ```swift
/// // Create connection
/// let spectro = try await Spectro(
///     hostname: "localhost",
///     username: "postgres",
///     password: "password",
///     database: "myapp"
/// )
///
/// // Define schema
/// struct User: Schema, SchemaBuilder {
///     static let tableName = "users"
///     @ID var id: UUID
///     @Column var name: String = ""
///     @Column var email: String = ""
///     init() {}
///
///     static func build(from values: [String: Any]) -> User {
///         // Implementation...
///     }
/// }
///
/// // Perform operations
/// let repo = spectro.repository()
/// let users = try await repo.query(User.self)
///     .where { $0.age > 18 }
///     .orderBy { $0.createdAt }
///     .all()
/// ```
///
/// ## Architecture
///
/// - **Property Wrappers**: `@ID`, `@Column`, `@Timestamp`, `@ForeignKey` for schema definition
/// - **Relationships**: `@HasMany`, `@HasOne`, `@BelongsTo` with lazy loading
/// - **Repository Pattern**: Explicit data access through `GenericDatabaseRepo`
/// - **Query Builder**: Immutable, composable query construction
/// - **Actor-Based Connection**: Thread-safe database access
public struct Spectro {
    private let connection: DatabaseConnection
    
    /// Create a new Spectro instance with explicit configuration.
    ///
    /// - Parameter configuration: Database configuration parameters
    /// - Throws: `SpectroError.connectionFailed` if connection cannot be established
    public init(configuration: DatabaseConfiguration) throws {
        self.connection = try DatabaseConnection(configuration: configuration)
    }
    
    /// Create a new Spectro instance with individual parameters.
    ///
    /// - Parameters:
    ///   - hostname: Database server hostname (default: "localhost")
    ///   - port: Database server port (default: 5432)
    ///   - username: Database username
    ///   - password: Database password
    ///   - database: Database name
    ///   - maxConnectionsPerEventLoop: Maximum connections per event loop (default: 4)
    /// - Throws: `SpectroError.connectionFailed` if connection cannot be established
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
    
    /// Create a Spectro instance from environment variables.
    ///
    /// Expects the following environment variables:
    /// - `DB_HOST` or `DB_HOSTNAME`: Database hostname
    /// - `DB_PORT`: Database port
    /// - `DB_USER` or `DB_USERNAME`: Database username
    /// - `DB_PASSWORD`: Database password
    /// - `DB_NAME` or `DB_DATABASE`: Database name
    ///
    /// - Returns: Configured Spectro instance
    /// - Throws: `SpectroError.missingEnvironmentVariable` if required variables are missing
    public static func fromEnvironment() throws -> Spectro {
        let config = try DatabaseConfiguration.fromEnvironment()
        return try Spectro(configuration: config)
    }
    
    /// Get a repository for database operations.
    ///
    /// The repository provides access to CRUD operations, query building, and transactions.
    ///
    /// - Returns: Generic database repository instance
    public func repository() -> GenericDatabaseRepo {
        GenericDatabaseRepo(connection: connection)
    }
    
    /// Test the database connection.
    ///
    /// Executes a simple query to verify the connection is working.
    ///
    /// - Returns: PostgreSQL version string
    /// - Throws: `SpectroError.queryExecutionFailed` if connection test fails
    public func testConnection() async throws -> String {
        return try await connection.testConnection()
    }
    
    /// Create a migration manager for this database.
    ///
    /// The migration manager handles database schema migrations.
    ///
    /// - Returns: Migration manager instance
    public func migrationManager() -> MigrationManager {
        return MigrationManager(connection: connection)
    }
    
    /// Gracefully shutdown the database connection.
    ///
    /// Closes all open connections and releases resources. Should be called
    /// when the Spectro instance is no longer needed.
    public func shutdown() async {
        await connection.shutdown()
    }
}

// MARK: - Convenience Methods

extension Spectro {
    /// Execute work within a database transaction.
    ///
    /// Automatically handles transaction begin/commit/rollback.
    ///
    /// - Parameter work: Closure containing database operations
    /// - Returns: Result of the work closure
    /// - Throws: `SpectroError.transactionFailed` if transaction fails
    public func transaction<T: Sendable>(_ work: @escaping @Sendable (any Repo) async throws -> T) async throws -> T {
        let repo = repository()
        return try await repo.transaction(work)
    }
    
    /// Get a single record by schema and ID.
    ///
    /// - Parameters:
    ///   - schema: Schema type to query
    ///   - id: Primary key value
    /// - Returns: Found record or nil if not found
    /// - Throws: `SpectroError.queryExecutionFailed` if query fails
    public func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T? {
        try await repository().get(schema, id: id)
    }
    
    /// Get all records for a schema.
    ///
    /// - Parameter schema: Schema type to query
    /// - Returns: Array of all records
    /// - Throws: `SpectroError.queryExecutionFailed` if query fails
    public func all<T: Schema>(_ schema: T.Type) async throws -> [T] {
        try await repository().all(schema)
    }
    
    /// Insert a new record.
    ///
    /// - Parameter instance: Record to insert
    /// - Returns: Inserted record with generated ID and timestamps
    /// - Throws: `SpectroError.queryExecutionFailed` if insertion fails
    public func insert<T: Schema>(_ instance: T) async throws -> T {
        try await repository().insert(instance)
    }
    
    /// Update an existing record.
    ///
    /// - Parameters:
    ///   - schema: Schema type to update
    ///   - id: Primary key of record to update
    ///   - changes: Dictionary of field changes
    /// - Returns: Updated record
    /// - Throws: `SpectroError.notFound` if record doesn't exist
    public func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: Any]) async throws -> T {
        try await repository().update(schema, id: id, changes: changes)
    }
    
    /// Delete a record.
    ///
    /// - Parameters:
    ///   - schema: Schema type to delete from
    ///   - id: Primary key of record to delete
    /// - Throws: `SpectroError.notFound` if record doesn't exist
    public func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws {
        try await repository().delete(schema, id: id)
    }
}