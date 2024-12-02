//
//  MigrationGenerator.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import Foundation
import Spectro
import SpectroCore

public struct MigrationGenerator {
    private let fileManager: FileManager = .default

    private let migrationManager: MigrationManager
    public init(migrationManager: MigrationManager) {
        self.migrationManager = migrationManager
    }

    public func generate(name: String) async throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let migrationName = name.snakeCase()
        let structName = "M\(timestamp)\(migrationName.pascalCase())"
        let fileName = "\(timestamp)_\(migrationName).swift"

        let content = """
            import SpectroKit

            struct \(structName): Migration {
                let version = "\(timestamp)_\(migrationName)"
                
                func up() -> String {
                    \"\"\"
                    -- Write your UP migration here
                    \"\"\"
                }
                
                func down() -> String {
                    \"\"\"
                    -- Write your DOWN migration here
                    \"\"\"
                }
            }
            """

        let migrationsPath = "Sources/Migrations"
        try fileManager.createDirectory(
            atPath: migrationsPath,
            withIntermediateDirectories: true
        )

        let filePath = "\(migrationsPath)/\(fileName)"

        guard !fileManager.fileExists(atPath: filePath) else {
            throw MigrationError.fileExists(filePath)
        }

        try content.write(
            toFile: filePath,
            atomically: true,
            encoding: .utf8
        )

        let migration = MigrationRecord(
            version: "\(timestamp)_\(migrationName)",
            name: migrationName,
            appliedAt: Date(),
            status: .pending
        )

        try await migrationManager.insertMigrationRecord(migration)
    }
}
