import ArgumentParser
import NIOCore
import PostgresKit
@preconcurrency import Spectro
import SpectroCore

struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create", abstract: "Create a new database"
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
            database: "postgres" // Use postgres database for creating new databases
        )

        defer {
            Task {
                await spectro.shutdown()
            }
        }

        let databaseName = config.database
        let repo = spectro.repository()
        
        do {
            // Create database - PostgreSQL will error if it already exists
            let createQuery = "CREATE DATABASE \"\(databaseName)\""
            try await repo.executeRawSQL(createQuery)
            
            print("Database '\(databaseName)' created successfully")
        } catch {
            if let psqlError = error as? PSQLError,
                let serverInfo = psqlError.serverInfo,
                let message = serverInfo[.message],
                message.contains("already exists") {
                throw DatabaseError.alreadyExists(databaseName)
            } else {
                throw DatabaseError.createdFailed(String(reflecting: error))
            }
        }
    }
}