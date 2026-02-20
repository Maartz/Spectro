// @preconcurrency suppresses Sendable warnings originating in NIO/PostgresKit types
// that predate Swift 6. Remove when those packages gain full Sendable annotations.
@preconcurrency import NIOCore
@preconcurrency import PostgresKit
import Foundation
import NIOSSL

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

    // MARK: - Query Execution

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
                    try result.rows.map(resultMapper)
                }
            }
            future.whenComplete { result in
                switch result {
                case .success(let rows): continuation.resume(returning: rows)
                case .failure(let error): continuation.resume(throwing: SpectroError.queryExecutionFailed(sql: sql, error: error))
                }
            }
        }
    }

    public func executeUpdate(sql: String, parameters: [PostgresData] = []) async throws {
        guard !isShutdown else {
            throw SpectroError.connectionFailed(underlying: DatabaseConnectionError.connectionClosed)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let future: EventLoopFuture<Void> = pools.withConnection { connection in
                connection.query(sql, parameters).map { _ in }
            }
            future.whenComplete { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: SpectroError.queryExecutionFailed(sql: sql, error: error))
                }
            }
        }
    }

    public func execute(sql: String, parameters: [PostgresData] = []) async throws -> Int {
        guard !isShutdown else {
            throw SpectroError.connectionFailed(underlying: DatabaseConnectionError.connectionClosed)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let future: EventLoopFuture<Int> = pools.withConnection { connection in
                connection.query(sql, parameters).map { _ in 1 }
            }
            future.whenComplete { result in
                switch result {
                case .success(let count): continuation.resume(returning: count)
                case .failure(let error): continuation.resume(throwing: SpectroError.queryExecutionFailed(sql: sql, error: error))
                }
            }
        }
    }

    // MARK: - Transactions
    //
    // Uses EventLoop.makeFutureWithTask to bridge the async `work` closure into the
    // NIO EventLoopFuture chain on the same connection, avoiding the unstructured
    // Task { } pattern that caused actor-isolation violations under Swift 6.

    public func transaction<T: Sendable>(
        _ work: @escaping @Sendable (TransactionContext) async throws -> T
    ) async throws -> T {
        guard !isShutdown else {
            throw SpectroError.connectionFailed(underlying: DatabaseConnectionError.connectionClosed)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let future: EventLoopFuture<T> = pools.withConnection { connection in
                connection.query("BEGIN ISOLATION LEVEL READ COMMITTED").flatMap { _ in
                    let context = TransactionContext(connection: connection)

                    return connection.eventLoop.makeFutureWithTask {
                        try await work(context)
                    }
                    .flatMap { result in
                        connection.query("COMMIT").map { _ in result }
                    }
                    .flatMapError { error in
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

    // MARK: - Lifecycle

    public nonisolated var config: DatabaseConfiguration { configuration }

    public func shutdown() async {
        guard !isShutdown else { return }
        isShutdown = true
        pools.shutdown()
        do {
            try await eventLoopGroup.shutdownGracefully()
        } catch {
            // Best-effort shutdown; don't propagate
        }
    }

    // Note: no deinit — actors cannot safely read isolated state (isShutdown) in
    // deinit, and syncShutdownGracefully() would block the current thread. Call
    // shutdown() explicitly before releasing a DatabaseConnection.

    // MARK: - Health Check

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

// MARK: - DatabaseConfiguration

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

// MARK: - TransactionContext
//
// Marked @unchecked Sendable because PostgresConnection is not Sendable but is
// safe here: the connection is pinned to a single NIO EventLoop for the lifetime
// of the transaction closure, and TransactionContext instances never escape that
// scope. Remove when PostgresNIO gains Sendable conformance.

public struct TransactionContext: @unchecked Sendable {
    let connection: PostgresConnection

    init(connection: PostgresConnection) {
        self.connection = connection
    }

    public func query<T: Sendable>(
        _ sql: String,
        _ parameters: [PostgresData] = [],
        mapper: @Sendable @escaping (PostgresRow) throws -> T
    ) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let future = connection.query(sql, parameters).flatMapThrowing { result in
                try result.rows.map(mapper)
            }
            future.whenComplete { result in
                switch result {
                case .success(let rows): continuation.resume(returning: rows)
                case .failure(let error): continuation.resume(throwing: SpectroError.queryExecutionFailed(sql: sql, error: error))
                }
            }
        }
    }

    public func execute(_ sql: String, _ parameters: [PostgresData] = []) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let future = connection.query(sql, parameters).map { _ in }
            future.whenComplete { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: SpectroError.queryExecutionFailed(sql: sql, error: error))
                }
            }
        }
    }
}

// MARK: - Internal

private enum DatabaseConnectionError: Error {
    case connectionClosed
    case invalidConfiguration
}
