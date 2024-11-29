import Foundation
import NIOCore
import PostgresKit

public final class Spectro {
    public let pools: EventLoopGroupConnectionPool<PostgresConnectionSource>
    private let eventLoop: EventLoopGroup

    public init(
        hostname: String = "localhost",
        port: Int = 5432,
        username: String,
        password: String,
        database: String
    ) throws {

        self.eventLoop = MultiThreadedEventLoopGroup(
            numberOfThreads: System.coreCount)

        let config = SQLPostgresConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database,
            tls: .disable
        )

        let source = PostgresConnectionSource(
            sqlConfiguration: config
        )

        self.pools = EventLoopGroupConnectionPool(
            source: source,
            maxConnectionsPerEventLoop: 1,
            on: eventLoop
        )
    }

    public func migrationManager() -> MigrationManager {
        return MigrationManager(spectro: self)
    }

    public func shutdown() {
        pools.shutdown()
        try? eventLoop.syncShutdownGracefully()
    }

    func test() async throws -> String {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<String, Error>) in
            let future: EventLoopFuture<String> = pools.withConnection { conn in
                conn.sql()
                    .raw("SELECT version() as ver;")
                    .first()
                    .map { row -> String in
                        guard let row = row,
                            let version = try? row.decode(
                                column: "ver", as: String.self)
                        else {
                            return "Version not found"
                        }
                        return version
                    }
            }

            future.whenComplete { result in
                switch result {
                case .success(let version):
                    continuation.resume(returning: version)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
