//
//  GenerateMigration.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import ArgumentParser

struct GenerateMigration: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migration"
    )
    
    @Argument(help: "Name of the migration")
    var name: String
    
    func run() throws {
        let generator = MigrationGenerator()
        try generator.generate(name: name)
    }
}
