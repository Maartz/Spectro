//
//  Migrate.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import ArgumentParser
import Spectro
import PostgresKit
import Logging

struct Migrate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "up"
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
            database: config.database)

        defer {
            spectro.shutdown()
        }

        let manager = spectro.migrationManager()

        do {
            try await manager.runMigrations()
            print(manager.migrationAppliedMessages())
        } catch {
            print("Migration failed with error:")
            print("Error description: \(error.localizedDescription)")
            print("Detailed error info: \(String(reflecting: error))")

            let logger = Logger(label: "PostgresErrorLogger")

            if let psqlError = error as? PSQLError {
                logger.error("PostgreSQL Error Details:")

                if let serverInfo = psqlError.serverInfo {
                    if let message = serverInfo[.message] {
                        logger.error("Message: \(message)")
                    }
                    if let detail = serverInfo[.detail] {
                        logger.error("Detail: \(detail)")
                    }
                    if let hint = serverInfo[.hint] {
                        logger.error("Hint: \(hint)")
                    }
                    if let position = serverInfo[.position] {
                        logger.error("Position: \(position)")
                    }
                    if let internalPosition = serverInfo[.internalPosition] {
                        logger.error("Internal Position: \(internalPosition)")
                    }
                    if let internalQuery = serverInfo[.internalQuery] {
                        logger.error("Internal Query: \(internalQuery)")
                    }
                    if let schemaName = serverInfo[.schemaName] {
                        logger.error("Schema Name: \(schemaName)")
                    }
                    if let tableName = serverInfo[.tableName] {
                        logger.error("Table Name: \(tableName)")
                    }
                    if let columnName = serverInfo[.columnName] {
                        logger.error("Column Name: \(columnName)")
                    }
                    if let dataTypeName = serverInfo[.dataTypeName] {
                        logger.error("Data Type Name: \(dataTypeName)")
                    }
                    if let constraintName = serverInfo[.constraintName] {
                        logger.error("Constraint Name: \(constraintName)")
                    }
                    if let file = serverInfo[.file] {
                        logger.error("File: \(file)")
                    }
                    if let line = serverInfo[.line] {
                        logger.error("Line: \(line)")
                    }
                    if let routine = serverInfo[.routine] {
                        logger.error("Routine: \(routine)")
                    }
                }
            }

            throw error
        }
    }
}
