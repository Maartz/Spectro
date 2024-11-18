//
//  MigrationGenerator.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import Foundation
import SpectroCore

public struct MigrationGenerator {
    private let fileManager: FileManager = .default

    public func generate(name: String) throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let migrationName = name.snakeCase()  // Clear usage here
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

        print("Created migration: \(fileName)")
    }
}
