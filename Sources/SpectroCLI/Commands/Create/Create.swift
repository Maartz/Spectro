import ArgumentParser
import NIOCore
import PostgresKit
@preconcurrency import Spectro
import SpectroCore

struct Create: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new database")

    @Option(name: .long, help: "Database Username") var username: String?
    @Option(name: .long, help: "Database Password") var password: String?
    @Option(name: .long, help: "Database Name")     var database: String?

    func run() async throws {
        try await ConfigurationManager.shared.loadEnvFile()
        var overrides: [String: String] = [:]
        if let v = username { overrides["username"] = v }
        if let v = password { overrides["password"] = v }
        if let v = database { overrides["database"] = v }

        let config = await ConfigurationManager.shared.getDatabaseConfig(overrides: overrides)
        let spectro = try Spectro(
            hostname: config.hostname, port: config.port,
            username: config.username, password: config.password, database: "postgres"
        )

        let databaseName = config.database
        let repo = spectro.repository()
        do {
            try await repo.executeRawSQL("CREATE DATABASE \"\(databaseName)\"")
            print("Database '\(databaseName)' created successfully")
        } catch {
            await spectro.shutdown()
            if let psqlError = error as? PSQLError,
               let message = psqlError.serverInfo?[.message],
               message.contains("already exists") {
                throw DatabaseError.alreadyExists(databaseName)
            }
            throw DatabaseError.createdFailed(String(reflecting: error))
        }
        await spectro.shutdown()
    }
}
