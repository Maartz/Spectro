import Foundation
import PostgresKit

/// Modern Swift ORM for PostgreSQL with implicit lazy relationships.
///
/// Spectro is a revolutionary ORM inspired by Elixir's Ecto, providing type-safe database
/// interactions with a dual-API approach and implicit lazy relationship loading that
/// prevents N+1 query issues by default.
///
/// ## Core Features
///
/// - **Implicit Lazy Relationships**: Relationships appear as normal Swift properties but are lazy by default
/// - **Type-Safe Query Builder**: Compose queries using closure syntax with compile-time validation
/// - **Property Wrapper DSL**: Define schemas using clean, declarative syntax
/// - **Ecto-Inspired Design**: Familiar patterns for developers coming from Elixir/Phoenix
/// - **Swift 6 Ready**: Full concurrency support with proper Sendable conformance
/// - **PostgreSQL Native**: Built specifically for PostgreSQL with full feature support
///
/// ## Quick Start
///
/// ```swift
/// // Connect to database
/// let spectro = try Spectro(
///     hostname: "localhost",
///     username: "postgres",
///     password: "password",
///     database: "myapp_dev"
/// )
///
/// // Get repository for database operations
/// let repo = spectro.repository()
///
/// // Define schema
/// public struct User: Schema, SchemaBuilder {
///     public static let tableName = "users"
///     @ID public var id: UUID
///     @Column public var name: String = ""
///     @Column public var email: String = ""
///     public init() {}
/// }
///
/// // Perform operations
/// let users = try await repo.query(User.self)
///     .where { $0.name.ilike("%john%") }
///     .orderBy { $0.createdAt }
///     .all()
/// ```
///
/// ## Relationship Loading
///
/// The key innovation in Spectro is its implicit lazy relationship system:
///
/// ```swift
/// // Relationships appear as normal properties but are lazy
/// public struct User: Schema {
///     @HasMany public var posts: [Post]  // Lazy by default
/// }
///
/// // Load explicitly when needed (no N+1 queries)
/// let user = try await repo.get(User.self, id: userId)
/// let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
///
/// // Or preload for efficiency
/// let users = try await repo.query(User.self)
///     .preload(\.$posts)
///     .all()
/// ```
///
/// ## Thread Safety
///
/// Spectro is fully thread-safe and designed for Swift 6 concurrency:
///
/// - All types conform to `Sendable`
/// - Safe for use across actors and tasks
/// - Connection pooling handles concurrent access
/// - Atomic operations prevent race conditions
///
/// ## Performance
///
/// Spectro is optimized for performance:
///
/// - **Lazy Loading**: No queries until explicitly requested
/// - **Batch Operations**: Efficient preloading prevents N+1 queries
/// - **Connection Pooling**: Optimal resource utilization
/// - **Query Optimization**: Type-safe queries compile to efficient SQL
///
/// ## Error Handling
///
/// Comprehensive error handling with specific error types:
///
/// ```swift
/// do {
///     let user = try await repo.get(User.self, id: userId)
/// } catch SpectroError.notFound(let schema, let id) {
///     print("User \(id) not found")
/// } catch SpectroError.queryExecutionFailed(let sql, let error) {
///     print("Query failed: \(sql)")
/// }
/// ```
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
    public func repository() -> GenericDatabaseRepo {
        GenericDatabaseRepo(connection: connection)
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
    public func transaction<T: Sendable>(_ work: @escaping @Sendable (any Repo) async throws -> T) async throws -> T {
        let repo = repository()
        return try await repo.transaction(work)
    }
    
    /// Get a single record by schema and ID
    public func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T? {
        try await repository().get(schema, id: id)
    }
    
    /// Get all records for a schema
    public func all<T: Schema>(_ schema: T.Type) async throws -> [T] {
        try await repository().all(schema)
    }
    
    /// Insert a new record
    public func insert<T: Schema>(_ instance: T) async throws -> T {
        try await repository().insert(instance)
    }
    
    /// Update an existing record
    public func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: Any]) async throws -> T {
        try await repository().update(schema, id: id, changes: changes)
    }
    
    /// Delete a record
    public func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws {
        try await repository().delete(schema, id: id)
    }
}
