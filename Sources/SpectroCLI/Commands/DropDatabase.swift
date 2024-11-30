import ArgumentParser
import NIOCore
import PostgresKit
import Spectro
import SpectroCore

struct DropDatabase: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drop_db",
        abstract: "Drop an existing database"
    )

    @Option(name: .long, help: "Database Username")
    var username: String?

    @Option(name: .long, help: "Database Password")
    var password: String?

    @Option(name: .long, help: "Database Name")
    var database: String?

    func run() async throws {
        try ConfigurationManager.shared.loadEnvFile()
        var overrides: [String: String] = [:]
        if let username = username { overrides["username"] = username }
        if let password = password { overrides["password"] = password }
        if let database = database { overrides["database"] = database }

        let config = ConfigurationManager.shared.getDatabaseConfig(overrides: overrides)
        let spectro = try Spectro(
            hostname: config.hostname,
            port: config.port,
            username: config.username,
            password: config.password,
            database: "postgres"
        )

        defer { spectro.shutdown() }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let future = spectro.pools.withConnection { conn -> EventLoopFuture<Void> in
                conn.sql().raw("SELECT 1 FROM pg_database WHERE datname = \(bind: config.database)")
                    .first()
                    .flatMap { exists -> EventLoopFuture<Void> in
                        if exists == nil {
                            return conn.eventLoop.makeFailedFuture(
                                DatabaseError.doesNotExist(config.database))
                        }
                        return conn.sql().raw("DROP DATABASE \"\(config.database)\"").run()
                    }
            }

            future.whenComplete { result in
                switch result {
                case .success:
                    print("Database '\(config.database)' dropped successfully")
                    continuation.resume()
                case .failure(let error):
                    let dbError: Error
                    if let psqlError = error as? PSQLError,
                        let serverInfo = psqlError.serverInfo
                    {
                        if let message = serverInfo[.message],
                            message.contains("does not exist")
                        {
                            dbError = DatabaseError.doesNotExist(config.database)
                        } else {
                            dbError = DatabaseError.dropFailed(String(reflecting: error))
                        }
                    } else {
                        dbError = DatabaseError.dropFailed(String(reflecting: error))
                    }
                    continuation.resume(throwing: dbError)
                }
            }
        }
    }
}

