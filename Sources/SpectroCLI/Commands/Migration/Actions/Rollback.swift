//
//  Rollback.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import ArgumentParser
import Logging
import PostgresKit
import Spectro

struct Rollback: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "down"
  )

  // TODO: Add a step option to rollback a specific number of migrations
  @Option(help: "Number of migrations to rollback")
  var step: Int?

  @Option(name: .long, help: "Database Username")
  var username: String?

  @Option(name: .long, help: "Database Password")
  var password: String?

  @Option(name: .long, help: "Database Name")
  var database: String?

  func run() async throws {
    try await ConfigurationManager.shared.loadEnvFile()
    var overrides: [String: String] = [:]
    if let username = username { overrides["username"] = username }
    if let password = password { overrides["password"] = password }
    if let database = database { overrides["database"] = database }

    let config = await ConfigurationManager.shared.getDatabaseConfig(overrides: overrides)
    let spectro = try await Spectro(
      hostname: config.hostname,
      port: config.port,
      username: config.username,
      password: config.password,
      database: config.database
    )

    defer {
      spectro.shutdown()
    }

    let manager = spectro.migrationManager()

    do {
      try await manager.runRollback()
      print(manager.rollbackAppliedMessages())
    } catch {
      print("Rollback failed with error:")
      print("Error description: \(error.localizedDescription)")
      print("Detailed error info: \(String(reflecting: error))")

      let logger = Logger(label: "PostgresErrorLogger")

      logger.error("❌ Operation failed!")
      logger.error("Error: \(error.localizedDescription)")
      logger.error("\n🔍 Debug details:")
      print(String(reflecting: error))

      logger.error("\n📝 Error type: \(type(of: error))")

      throw error
    }

  }
}
