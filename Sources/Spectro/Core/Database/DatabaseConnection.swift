import Foundation
import NIOCore
import PostgresKit

/// Actor-based database connection manager
/// Replaces the global RepositoryConfiguration with thread-safe, isolated connection handling
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
            tls: configuration.tlsConfiguration
        )
        
        let source = PostgresConnectionSource(sqlConfiguration: sqlConfig)
        
        self.pools = EventLoopGroupConnectionPool(
            source: source,
            maxConnectionsPerEventLoop: configuration.maxConnectionsPerEventLoop,
            on: eventLoopGroup
        )
    }
    
    /// Execute a query with proper error handling
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
    
    /// Execute an update/insert/delete statement
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
    
    /// Execute work within a database transaction
    public func transaction<T: Sendable>(
        _ work: @Sendable (TransactionContext) async throws -> T
    ) async throws -> T {
        guard !isShutdown else {
            throw SpectroError.connectionFailed(underlying: DatabaseConnectionError.connectionClosed)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let future: EventLoopFuture<T> = pools.withConnection { connection in
                connection.sql().begin().flatMap { _ in
                    let transactionContext = TransactionContext(connection: connection)
                    
                    let workFuture = EventLoopFuture<T>.make(on: connection.eventLoop)
                    
                    Task {
                        do {
                            let result = try await work(transactionContext)
                            workFuture.succeed(result)
                        } catch {
                            workFuture.fail(error)
                        }
                    }
                    
                    return workFuture.flatMap { result in
                        connection.sql().commit().map { _ in result }
                    }.flatMapError { error in
                        connection.sql().rollback().flatMapThrowing { _ in
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
    
    /// Get the database configuration
    public nonisolated var config: DatabaseConfiguration {
        configuration
    }
    
    /// Gracefully shutdown the connection pool
    public func shutdown() async {
        guard !isShutdown else { return }
        
        isShutdown = true
        pools.shutdown()
        
        do {
            try await eventLoopGroup.shutdownGracefully()
        } catch {
            // Log error but don't throw - shutdown should be best effort
            print("Warning: Error during event loop shutdown: \(error)")
        }
    }
    
    /// Test the database connection
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

/// Database configuration for connection setup
public struct DatabaseConfiguration: Sendable {
    public let hostname: String
    public let port: Int
    public let username: String
    public let password: String
    public let database: String
    public let maxConnectionsPerEventLoop: Int
    public let numberOfThreads: Int
    public let tlsConfiguration: TLSConfiguration
    
    public init(
        hostname: String = "localhost",
        port: Int = 5432,
        username: String,
        password: String,
        database: String,
        maxConnectionsPerEventLoop: Int = 4,
        numberOfThreads: Int = System.coreCount,
        tlsConfiguration: TLSConfiguration = .disable
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
    
    /// Create configuration from environment variables
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

/// Transaction context for database operations within a transaction
public struct TransactionContext: Sendable {
    let connection: PostgresConnection
    
    init(connection: PostgresConnection) {
        self.connection = connection
    }
    
    /// Execute a query within the transaction
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
    
    /// Execute an update within the transaction
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