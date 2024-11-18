//
//  Rollback.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import ArgumentParser

struct Rollback: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rollback"
    )
    
    @Option(help: "Number of migrations to rollback")
    var step: Int?
    
    func run() async throws {
        // Implementation coming soon
    }
}
