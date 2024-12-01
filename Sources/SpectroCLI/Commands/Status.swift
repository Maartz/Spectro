//
//  Status.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import ArgumentParser
import Foundation
import Spectro
import SpectroCore

public protocol MigrationManaging {
    func getMigrationStatuses() async throws -> (
        discovered: [MigrationFile], statuses: [String: MigrationStatus]
    )
}

extension MigrationManager: MigrationManaging {}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status", abstract: "Display the status of migrations"
    )

    var migrationManager: MigrationManager?

    init() {}

    init(migrationManager: MigrationManager) {
        self.migrationManager = migrationManager
    }

    mutating func run() async throws {
    }
}
