//
//  Generate.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import ArgumentParser

struct Generate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        subcommands: [
            GenerateMigration.self
        ]
    )
}
