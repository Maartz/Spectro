import Foundation
import NIOCore
import PostgresKit
import NIOSSL

/// Thread-safe, actor-based database connection manager.
///
/// `DatabaseConnection` provides safe, concurrent access to PostgreSQL using Swift's actor model.
/// It manages connection pooling, executes queries with proper error handling, and supports
/// transactions with automatic rollback on errors.
///
/// ## Concurrency Safety
///
/// As an actor, `DatabaseConnection` ensures thread-safe access to the underlying connection pool.
/// All methods are `async` and can be safely called from multiple concurrent contexts.
///
/// ## Connection Pooling
///
/// Uses PostgresKit's `EventLoopGroupConnectionPool` for efficient connection reuse:
/// - Connections are pooled per event loop for optimal performance
/// - Configurable maximum connections per event loop
/// - Automatic connection lifecycle management
///
/// ## Error Handling
///
/// All database errors are wrapped in `SpectroError` for consistent error handling:
/// - Connection failures: `.connectionFailed`
/// - Query execution errors: `.queryExecutionFailed`
/// - Transaction failures: `.transactionFailed`
///
/// ## Basic Usage
///
/// ```swift
/// let config = DatabaseConfiguration(
///     hostname: "localhost",
///     username: "postgres",
///     password: "password",
///     database: "myapp"
/// )
///
/// let connection = try DatabaseConnection(configuration: config)
///
/// // Execute a query
/// let users = try await connection.executeQuery(
///     sql: "SELECT * FROM users WHERE age > $1",
///     parameters: [PostgresData(int: 18)]
/// ) { row in
///     // Map row to User instance
///     return User(from: row)
/// }
/// ```
///
/// ## Lifecycle Management
///
/// Always call `shutdown()` when done to properly close connections:
///
/// ```swift
/// defer {
///     await connection.shutdown()
/// }
/// ```
public actor DatabaseConnection {
    private let pools: EventLoopGroupConnectionPool<PostgresConnectionSource>
    private let eventLoopGroup: EventLoopGroup
    private let configuration: DatabaseConfiguration
    private var isShutdown = false
    
    public init(configuration: DatabaseConfiguration) throws {
        self.configuration = configuration
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: configuration.numberOfThreads)
        
        let sqlConfig = SQLPostgresConfiguration(
            hostname: configuration.hostname,
            port: configuration.port,
            username: configuration.username,
            password: configuration.password,
            database: configuration.database,
            tls: .disable
        )
        
        let source = PostgresConnectionSource(sqlConfiguration: sqlConfig)
        
        self.pools = EventLoopGroupConnectionPool(
            source: source,
            maxConnectionsPerEventLoop: configuration.maxConnectionsPerEventLoop,
            on: eventLoopGroup
        )
    }
    
    /// Execute a SELECT query and map results to the specified type.
    ///
    /// Executes a parameterized query and maps each returned row to the specified type
    /// using the provided mapper function. All parameters are safely bound to prevent
    /// SQL injection attacks.
    ///
    /// - Parameters:
    ///   - sql: SQL query string with parameter placeholders ($1, $2, etc.)
    ///   - parameters: Array of parameters to bind to the query
    ///   - resultMapper: Function to convert each row to the desired type
    /// - Returns: Array of mapped results
    /// - Throws: `SpectroError.queryExecutionFailed` if query fails
    ///
    /// ## Example
    ///
    /// ```swift
    /// let users = try await connection.executeQuery(
    ///     sql: "SELECT id, name, email FROM users WHERE age > $1",
    ///     parameters: [PostgresData(int: 18)]
    /// ) { row in
    ///     let randomAccess = row.makeRandomAccess()
    ///     return User(
    ///         id: randomAccess[data: "id"].uuid!,
    ///         name: randomAccess[data: "name"].string!,
    ///         email: randomAccess[data: "email"].string!
    ///     )
    /// }
    /// ```
    ///
    /// ## Parameter Safety
    ///
    /// All parameters are automatically escaped and bound safely:
    ///
    /// ```swift
    /// // Safe - parameters are properly escaped
    /// let query = "SELECT * FROM users WHERE name = $1"
    /// let params = [PostgresData(string: userInput)]
    /// ```
    ///
    /// ## Concurrency
    ///
    /// This method is actor-isolated and can be safely called concurrently
    /// from multiple tasks.
    public func executeQuery<T: Sendable>(
        sql: String,
        parameters: [PostgresData] = [],
        resultMapper: @Sendable @escaping (PostgresRow) throws -> T
    ) async throws -> [T] {
        guard !isShutdown else {
            throw SpectroError.connectionFailed(underlying: DatabaseConnectionError.connectionClosed)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let future: EventLoopFuture<[T]> = pools.withConnection { connection in
                connection.query(sql, parameters).flatMapThrowing { result in
                    return try result.rows.map(resultMapper)
                }
            }
            
            future.whenComplete { result in
                switch result {
                case .success(let rows):
                    continuation.resume(returning: rows)
                case .failure(let error):
                    let spectroError = SpectroError.queryExecutionFailed(sql: sql, error: error)
                    continuation.resume(throwing: spectroError)
                }
            }
        }
    }
    
    /// Execute an UPDATE, INSERT, or DELETE statement.
    ///
    /// Executes a data modification statement without returning results.
    /// Used for INSERT, UPDATE, DELETE, and other non-SELECT operations.
    ///
    /// - Parameters:
    ///   - sql: SQL statement with parameter placeholders
    ///   - parameters: Array of parameters to bind to the statement
    /// - Throws: `SpectroError.queryExecutionFailed` if execution fails
    ///
    /// ## Examples
    ///
    /// ```swift
    /// // Insert a new record
    /// try await connection.executeUpdate(
    ///     sql: "INSERT INTO users (name, email) VALUES ($1, $2)",
    ///     parameters: [
    ///         PostgresData(string: "John Doe"),
    ///         PostgresData(string: "john@example.com")
    ///     ]
    /// )
    ///
    /// // Update existing records
    /// try await connection.executeUpdate(
    ///     sql: "UPDATE users SET last_login = $1 WHERE id = $2",
    ///     parameters: [
    ///         PostgresData(date: Date()),
    ///         PostgresData(uuid: userId)
    ///     ]
    /// )
    ///
    /// // Delete records
    /// try await connection.executeUpdate(
    ///     sql: "DELETE FROM sessions WHERE expires_at < $1",
    ///     parameters: [PostgresData(date: Date())]
    /// )
    /// ```
    public func executeUpdate(
        sql: String,
        parameters: [PostgresData] = []
    ) async throws {
        guard !isShutdown else {
            throw SpectroError.connectionFailed(underlying: DatabaseConnectionError.connectionClosed)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let future: EventLoopFuture<Void> = pools.withConnection { connection in
                connection.query(sql, parameters).map { _ in }
            }
            
            future.whenComplete { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    let spectroError = SpectroError.queryExecutionFailed(sql: sql, error: error)
                    continuation.resume(throwing: spectroError)
                }
            }
        }
    }
    
    /// Execute a statement and return the number of affected rows.
    ///
    /// Similar to `executeUpdate()` but returns the count of rows affected
    /// by the operation. Useful for determining the impact of UPDATE and DELETE operations.
    ///
    /// - Parameters:
    ///   - sql: SQL statement with parameter placeholders
    ///   - parameters: Array of parameters to bind to the statement
    /// - Returns: Number of rows affected by the operation
    /// - Throws: `SpectroError.queryExecutionFailed` if execution fails
    ///
    /// ## Example
    ///
    /// ```swift
    /// let updatedCount = try await connection.execute(
    ///     sql: "UPDATE users SET is_active = false WHERE last_login < $1",
    ///     parameters: [PostgresData(date: cutoffDate)]
    /// )
    /// print("Deactivated \(updatedCount) inactive users")
    /// ```
    ///
    /// ## Note
    ///
    /// Current implementation returns 1 for successful operations.
    /// Future versions will return actual affected row counts.
    public func execute(
        sql: String,
        parameters: [PostgresData] = []
    ) async throws -> Int {
        guard !isShutdown else {
            throw SpectroError.connectionFailed(underlying: DatabaseConnectionError.connectionClosed)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let future: EventLoopFuture<Int> = pools.withConnection { connection in
                connection.query(sql, parameters).map { result in
                    // For PostgreSQL, we can get affected rows from the command metadata
                    // This is a simplified implementation - return 1 for now
                    return 1
                }
            }
            
            future.whenComplete { result in
                switch result {
                case .success(let count):
                    continuation.resume(returning: count)
                case .failure(let error):
                    let spectroError = SpectroError.queryExecutionFailed(sql: sql, error: error)
                    continuation.resume(throwing: spectroError)
                }
            }
        }
    }
    
    /// Execute multiple operations within a database transaction.
    ///
    /// Provides ACID transaction support with automatic BEGIN/COMMIT/ROLLBACK handling.
    /// If any operation within the transaction throws an error, the entire transaction
    /// is automatically rolled back.
    ///
    /// - Parameter work: Closure containing database operations to execute
    /// - Returns: Result of the work closure
    /// - Throws: `SpectroError.transactionFailed` if transaction fails
    ///
    /// ## Example
    ///
    /// ```swift
    /// let result = try await connection.transaction { txContext in
    ///     // Insert user
    ///     let userRows = try await txContext.query(
    ///         "INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id",
    ///         [PostgresData(string: "John"), PostgresData(string: "john@example.com")]
    ///     ) { row in
    ///         row.makeRandomAccess()[data: "id"].uuid!
    ///     }
    ///     
    ///     let userId = userRows[0]
    ///     
    ///     // Create profile
    ///     try await txContext.execute(
    ///         "INSERT INTO profiles (user_id, bio) VALUES ($1, $2)",
    ///         [PostgresData(uuid: userId), PostgresData(string: "Bio")]
    ///     )
    ///     
    ///     return userId
    /// }
    /// ```
    ///
    /// ## Automatic Rollback
    ///
    /// If any operation throws an error, the transaction is rolled back:
    ///
    /// ```swift
    /// do {
    ///     try await connection.transaction { txContext in
    ///         try await txContext.execute("INSERT INTO users ...")
    ///         throw MyError.someError // This will trigger rollback
    ///     }
    /// } catch {
    ///     // Transaction was rolled back automatically
    /// }
    /// ```
    ///
    /// ## Isolation Level
    ///
    /// Transactions use PostgreSQL's default isolation level (READ COMMITTED).
    /// For custom isolation levels, use raw SQL within the transaction.
    public func transaction<T: Sendable>(
        _ work: @escaping @Sendable (TransactionContext) async throws -> T
    ) async throws -> T {
        guard !isShutdown else {
            throw SpectroError.connectionFailed(underlying: DatabaseConnectionError.connectionClosed)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let future: EventLoopFuture<T> = pools.withConnection { connection in
                connection.query("BEGIN").flatMap { _ in
                    let transactionContext = TransactionContext(connection: connection)
                    
                    let promise = connection.eventLoop.makePromise(of: T.self)
                    
                    Task {
                        do {
                            let result = try await work(transactionContext)
                            promise.succeed(result)
                        } catch {
                            promise.fail(error)
                        }
                    }
                    
                    return promise.futureResult.flatMap { result in
                        connection.query("COMMIT").map { _ in result }
                    }.flatMapError { error in
                        connection.query("ROLLBACK").flatMapThrowing { _ in
                            throw SpectroError.transactionFailed(underlying: error)
                        }
                    }
                }
            }
            
            future.whenComplete { result in
                continuation.resume(with: result)
            }
        }
    }
    
    /// Get the database configuration used by this connection.
    ///
    /// Returns the configuration that was used to initialize this connection.
    /// This property is `nonisolated` for efficient access.
    ///
    /// - Returns: Database configuration instance
    public nonisolated var config: DatabaseConfiguration {
        configuration
    }
    
    /// Gracefully shutdown the connection pool and release resources.
    ///
    /// Closes all active connections and shuts down the event loop group.
    /// This method should be called when the connection is no longer needed
    /// to ensure proper cleanup of system resources.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let connection = try DatabaseConnection(configuration: config)
    /// defer {
    ///     await connection.shutdown()
    /// }
    /// 
    /// // Use connection...
    /// ```
    ///
    /// ## Graceful Shutdown
    ///
    /// The shutdown process:
    /// 1. Marks the connection as shutdown (prevents new operations)
    /// 2. Closes the connection pool
    /// 3. Gracefully shuts down the event loop group
    /// 4. Waits for all operations to complete
    ///
    /// ## Error Handling
    ///
    /// Shutdown errors are logged but not thrown to ensure cleanup completes.
    public func shutdown() async {
        guard !isShutdown else { return }
        
        isShutdown = true
        
        // Shutdown pool - this is synchronous
        pools.shutdown()
        
        do {
            try await eventLoopGroup.shutdownGracefully()
        } catch {
            // Log error but don't throw - shutdown should be best effort
            print("Warning: Error during event loop shutdown: \(error)")
        }
    }
    
    /// Ensure cleanup on deinit
    deinit {
        if !isShutdown {
            // Force synchronous cleanup - this is a last resort
            // Users should call shutdown() explicitly
            pools.shutdown()
            try? eventLoopGroup.syncShutdownGracefully()
        }
    }
    
    /// Test the database connection by executing a simple query.
    ///
    /// Performs a basic connectivity test by executing `SELECT version()`
    /// and returning the PostgreSQL version string. Useful for health checks
    /// and connection validation.
    ///
    /// - Returns: PostgreSQL version string
    /// - Throws: `SpectroError.queryExecutionFailed` if connection test fails
    ///
    /// ## Example
    ///
    /// ```swift
    /// do {
    ///     let version = try await connection.testConnection()
    ///     print("Connected to: \(version)")
    /// } catch {
    ///     print("Database connection failed: \(error)")
    /// }
    /// ```
    ///
    /// ## Health Checks
    ///
    /// Use this method for application health checks:
    ///
    /// ```swift
    /// func healthCheck() async -> Bool {
    ///     do {
    ///         _ = try await connection.testConnection()
    ///         return true
    ///     } catch {
    ///         return false
    ///     }
    /// }
    /// ```
    public func testConnection() async throws -> String {
        let result = try await executeQuery(
            sql: "SELECT version() as version",
            resultMapper: { row in
                let randomAccess = row.makeRandomAccess()
                guard let version = randomAccess[data: "version"].string else {
                    throw SpectroError.resultDecodingFailed(column: "version", expectedType: "String")
                }
                return version
            }
        )
        
        guard let version = result.first else {
            throw SpectroError.unexpectedResultCount(expected: 1, actual: 0)
        }
        
        return version
    }
}

/// Configuration for database connection setup.
///
/// `DatabaseConfiguration` contains all parameters needed to establish
/// a connection to a PostgreSQL database, including connection pooling
/// and threading options.
///
/// ## Basic Configuration
///
/// ```swift
/// let config = DatabaseConfiguration(
///     hostname: "localhost",
///     port: 5432,
///     username: "postgres",
///     password: "password",
///     database: "myapp"
/// )
/// ```
///
/// ## Environment-Based Configuration
///
/// ```swift
/// // Reads from DB_USERNAME, DB_PASSWORD, DB_DATABASE, etc.
/// let config = try DatabaseConfiguration.fromEnvironment()
/// ```
///
/// ## Performance Tuning
///
/// ```swift
/// let config = DatabaseConfiguration(
///     hostname: "localhost",
///     username: "postgres",
///     password: "password",
///     database: "myapp",
///     maxConnectionsPerEventLoop: 8,  // Higher for more concurrent operations
///     numberOfThreads: 4              // Match your server's CPU cores
/// )
/// ```
public struct DatabaseConfiguration: Sendable {
    public let hostname: String
    public let port: Int
    public let username: String
    public let password: String
    public let database: String
    public let maxConnectionsPerEventLoop: Int
    public let numberOfThreads: Int
    public let tlsConfiguration: TLSConfiguration?
    
    public init(
        hostname: String = "localhost",
        port: Int = 5432,
        username: String,
        password: String,
        database: String,
        maxConnectionsPerEventLoop: Int = 4,
        numberOfThreads: Int = System.coreCount,
        tlsConfiguration: TLSConfiguration? = nil
    ) {
        self.hostname = hostname
        self.port = port
        self.username = username
        self.password = password
        self.database = database
        self.maxConnectionsPerEventLoop = maxConnectionsPerEventLoop
        self.numberOfThreads = numberOfThreads
        self.tlsConfiguration = tlsConfiguration
    }
    
    /// Create configuration from environment variables.
    ///
    /// Reads database connection parameters from environment variables.
    /// This is useful for containerized deployments and configuration management.
    ///
    /// - Returns: Database configuration from environment
    /// - Throws: `SpectroError.missingEnvironmentVariable` if required variables are missing
    ///
    /// ## Required Environment Variables
    ///
    /// - `DB_USERNAME`: Database username
    /// - `DB_PASSWORD`: Database password
    /// - `DB_DATABASE`: Database name
    ///
    /// ## Optional Environment Variables
    ///
    /// - `DB_HOSTNAME`: Database hostname (default: "localhost")
    /// - `DB_PORT`: Database port (default: 5432)
    ///
    /// ## Example
    ///
    /// ```bash
    /// export DB_USERNAME=postgres
    /// export DB_PASSWORD=secret
    /// export DB_DATABASE=myapp
    /// export DB_HOSTNAME=db.example.com
    /// export DB_PORT=5432
    /// ```
    ///
    /// ```swift
    /// let config = try DatabaseConfiguration.fromEnvironment()
    /// ```
    public static func fromEnvironment() throws -> DatabaseConfiguration {
        guard let username = ProcessInfo.processInfo.environment["DB_USERNAME"] else {
            throw SpectroError.missingEnvironmentVariable("DB_USERNAME")
        }
        
        guard let password = ProcessInfo.processInfo.environment["DB_PASSWORD"] else {
            throw SpectroError.missingEnvironmentVariable("DB_PASSWORD")
        }
        
        guard let database = ProcessInfo.processInfo.environment["DB_DATABASE"] else {
            throw SpectroError.missingEnvironmentVariable("DB_DATABASE")
        }
        
        let hostname = ProcessInfo.processInfo.environment["DB_HOSTNAME"] ?? "localhost"
        let port = Int(ProcessInfo.processInfo.environment["DB_PORT"] ?? "5432") ?? 5432
        
        return DatabaseConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database
        )
    }
}

/// Context for executing database operations within a transaction.
///
/// `TransactionContext` provides a scoped environment for executing queries
/// and updates within an active database transaction. All operations use
/// the same underlying connection to ensure transactional consistency.
///
/// ## Usage
///
/// This type is typically used within transaction closures:
///
/// ```swift
/// try await connection.transaction { txContext in
///     let users = try await txContext.query(
///         "SELECT * FROM users WHERE active = $1",
///         [PostgresData(bool: true)]
///     ) { row in
///         // Map row to User
///     }
///     
///     try await txContext.execute(
///         "UPDATE users SET last_seen = $1 WHERE id = ANY($2)",
///         [PostgresData(date: Date()), PostgresData(array: userIds)]
///     )
/// }
/// ```
///
/// ## Isolation
///
/// All operations within the same transaction context:
/// - Use the same database connection
/// - See each other's changes immediately
/// - Are isolated from other concurrent transactions
/// - Are committed or rolled back together
public struct TransactionContext: Sendable {
    let connection: PostgresConnection
    
    init(connection: PostgresConnection) {
        self.connection = connection
    }
    
    /// Execute a SELECT query within the transaction.
    ///
    /// Similar to `DatabaseConnection.executeQuery()` but executes within
    /// the current transaction context using the same connection.
    ///
    /// - Parameters:
    ///   - sql: SQL query string with parameter placeholders
    ///   - parameters: Array of parameters to bind
    ///   - mapper: Function to convert rows to the desired type
    /// - Returns: Array of mapped results
    /// - Throws: `SpectroError.queryExecutionFailed` if query fails
    public func query<T: Sendable>(
        _ sql: String,
        _ parameters: [PostgresData] = [],
        mapper: @Sendable @escaping (PostgresRow) throws -> T
    ) async throws -> [T] {
        return try await withCheckedThrowingContinuation { continuation in
            let future = connection.query(sql, parameters).flatMapThrowing { result in
                try result.rows.map(mapper)
            }
            
            future.whenComplete { result in
                switch result {
                case .success(let rows):
                    continuation.resume(returning: rows)
                case .failure(let error):
                    continuation.resume(throwing: SpectroError.queryExecutionFailed(sql: sql, error: error))
                }
            }
        }
    }
    
    /// Execute an UPDATE, INSERT, or DELETE within the transaction.
    ///
    /// Similar to `DatabaseConnection.executeUpdate()` but executes within
    /// the current transaction context using the same connection.
    ///
    /// - Parameters:
    ///   - sql: SQL statement with parameter placeholders
    ///   - parameters: Array of parameters to bind
    /// - Throws: `SpectroError.queryExecutionFailed` if execution fails
    public func execute(_ sql: String, _ parameters: [PostgresData] = []) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let future = connection.query(sql, parameters).map { _ in }
            
            future.whenComplete { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: SpectroError.queryExecutionFailed(sql: sql, error: error))
                }
            }
        }
    }
}

/// Internal errors for database connection management
private enum DatabaseConnectionError: Error {
    case connectionClosed
    case invalidConfiguration
}