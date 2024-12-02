//
//  GenerateMigration.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import ArgumentParser
import Spectro

struct GenerateMigration: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migration"
    )

    @Argument(help: "Name of the migration")
    var name: String

    @Option(name: .long, help: "Database Username")
    var username: String?

    @Option(name: .long, help: "Database Password")
    var password: String?

    @Option(name: .long, help: "Database Name")
    var database: String?

    func run() async throws {  // Make this method async
        try ConfigurationManager.shared.loadEnvFile()

        var overrides: [String: String] = [:]
        if let username = username { overrides["username"] = username }
        if let password = password { overrides["password"] = password }
        if let database = database { overrides["database"] = database }
        let config = ConfigurationManager.shared.getDatabaseConfig(overrides: overrides)

        let spectro = try Spectro(
            hostname: config.hostname, port: config.port, username: config.username,
            password: config.password, database: config.database
        )

        defer {
            spectro.shutdown()
        }

        let migrationManager = MigrationManager(spectro: spectro)
        let migrationGenerator = MigrationGenerator(migrationManager: migrationManager)  // Pass migrationManager here

        do {
            try await migrationGenerator.generate(name: name)  // Use await here
            print(migrationManager.migrationCreatedMessages())
        } catch {
            print("Error: \(error)")
        }
    }

}
