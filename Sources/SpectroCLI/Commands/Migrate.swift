//
//  Migrate.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import ArgumentParser
import Spectro

struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate"
    )

    @Option(name: .long, help: "Database Username")
    var username: String = "postgres"

    @Option(name: .long, help: "Database Password")
    var password: String = "postgres"

    @Option(name: .long, help: "Database Name")
    var database: String = "spectro_test"

    func run() async throws {
        let spectro = try Spectro(username: username, password: password, database: database)

        defer {
            spectro.shutdown()
        }

        let manager = spectro.migrationManager()
        try await manager.runMigrations()
    }
}
