import ArgumentParser
import NIOCore
import PostgresKit
import Spectro
import SpectroCore

struct Drop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "drop",
        abstract: "Drop an existing database"
    )

    @Option(name: .long, help: "Database Username")
    var username: String?

    @Option(name: .long, help: "Database Password")
    var password: String?

    @Option(name: .long, help: "Database Name")
    var database: String?

    func run() async throws {
        try await ConfigurationManager.shared.loadEnvFile()
        var overrides: [String: String] = [:]
        if let username = username { overrides["username"] = username }
        if let password = password { overrides["password"] = password }
        if let database = database { overrides["database"] = database }

        let config = await ConfigurationManager.shared.getDatabaseConfig(overrides: overrides)
        let spectro = try await Spectro(
            hostname: config.hostname,
            port: config.port,
            username: config.username,
            password: config.password,
            database: "postgres" // Use postgres database for dropping other databases
        )

        defer {
            Task {
                await spectro.shutdown()
            }
        }

        let databaseName = config.database
        let repo = spectro.repository()
        
        do {
            // Drop database - PostgreSQL will error if it doesn't exist
            let dropQuery = "DROP DATABASE \"\(databaseName)\""
            try await repo.executeRawSQL(dropQuery)
            
            print("Database '\(databaseName)' dropped successfully")
        } catch {
            if let psqlError = error as? PSQLError,
                let serverInfo = psqlError.serverInfo,
                let message = serverInfo[.message],
                message.contains("does not exist") {
                throw DatabaseError.doesNotExist(databaseName)
            } else {
                throw DatabaseError.dropFailed(String(reflecting: error))
            }
        }
    }
}