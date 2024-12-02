//
//  Migration.swift
//  SpectroCLI
//
//  Created by William MARTIN on 12/2/24.
//

import ArgumentParser

struct Migration: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migration",
        subcommands: [
            Migrate.self,
            Status.self,
            Rollback.self
        ]
    )
}
