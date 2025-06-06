import Foundation
import PostgresKit
import SpectroCore

public class MigrationManager {
  private let connection: DatabaseConnection
  private let migrationsPath: URL

  public init(connection: DatabaseConnection) {
    self.connection = connection
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    self.migrationsPath = currentDirectory.appendingPathComponent("Sources/Migrations")
  }

  public func ensureMigrationTableExists() async throws {
    // Create migration status enum type if it doesn't exist
    let createEnumSql = """
      DO $$ BEGIN
          CREATE TYPE migration_status AS ENUM ('pending', 'completed', 'failed');
      EXCEPTION WHEN duplicate_object THEN null; END $$;
    """
    
    try await connection.executeUpdate(sql: createEnumSql)
    
    // Create migrations table if it doesn't exist
    let createTableSql = """
      CREATE TABLE IF NOT EXISTS schema_migrations (
          version TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          applied_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
          status migration_status NOT NULL DEFAULT 'pending'
      );
    """
    
    try await connection.executeUpdate(sql: createTableSql)
  }

  public func getMigrationStatus() async throws -> [MigrationRecord] {
    let sql = """
      SELECT version, name, applied_at, status
      FROM schema_migrations
      ORDER BY version ASC
    """
    
    return try await connection.executeQuery(sql: sql) { row in
      let randomAccess = row.makeRandomAccess()
      
      guard let version = randomAccess[data: "version"].string else {
        throw SpectroError.resultDecodingFailed(column: "version", expectedType: "String")
      }
      
      guard let name = randomAccess[data: "name"].string else {
        throw SpectroError.resultDecodingFailed(column: "name", expectedType: "String")
      }
      
      guard let appliedAt = randomAccess[data: "applied_at"].date else {
        throw SpectroError.resultDecodingFailed(column: "applied_at", expectedType: "Date")
      }
      
      guard let statusString = randomAccess[data: "status"].string,
            let status = MigrationStatus(rawValue: statusString) else {
        throw SpectroError.resultDecodingFailed(column: "status", expectedType: "MigrationStatus")
      }
      
      return MigrationRecord(
        version: version,
        name: name,
        appliedAt: appliedAt,
        status: status
      )
    }
  }

  public func discoverMigrations() throws -> [MigrationFile] {
    guard FileManager.default.fileExists(atPath: migrationsPath.path) else {
      throw MigrationError.directoryNotFound(migrationsPath.path)
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: migrationsPath, includingPropertiesForKeys: nil
    )
    return files.filter { $0.pathExtension == "swift" }
      .compactMap { url in
        let name = url.lastPathComponent
        let parts = name.dropLast(6).split(separator: "_", maxSplits: 1)
        guard parts.count == 2,
          let ts = Double(parts[0]), ts > 0,
          ts < Date().timeIntervalSince1970 + 100 * 365 * 24 * 60 * 60
        else { return nil }
        return MigrationFile(
          version: "\(parts[0])_\(parts[1])",
          name: String(parts[1]),
          filePath: url
        )
      }
      .sorted { $0.version < $1.version }
  }

  public func getMigrationStatuses() async throws -> (
    discovered: [MigrationFile], statuses: [String: MigrationStatus]
  ) {
    let discovered = try discoverMigrations()
    let applied = try await getMigrationStatus()
    let statusMap = Dictionary(uniqueKeysWithValues: applied.map { ($0.version, $0.status) })
    return (discovered, statusMap)
  }

  public func getPendingMigrations() async throws -> [MigrationFile] {
    let (discovered, statuses) = try await getMigrationStatuses()
    return discovered.filter {
      statuses[$0.version] == nil || statuses[$0.version] == MigrationStatus.pending
    }
  }

  public func getAppliedMigrations() async throws -> [MigrationFile] {
    let (discovered, statuses) = try await getMigrationStatuses()
    return discovered.filter {
      statuses[$0.version] != MigrationStatus.pending
    }
  }

  private func withTransaction<T: Sendable>(
    _ operation: @Sendable @escaping (SQLDatabase) async throws -> T
  ) async throws -> T {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
      let future = spectro.pools.withConnection { conn in
        conn.sql().raw("BEGIN").run().flatMap { _ in
          let promise: EventLoopPromise<T> = conn.eventLoop.makePromise()
          Task {
            do {
              let val = try await operation(conn.sql())
              try await conn.sql().raw("COMMIT").run().get()
              promise.succeed(val)
            } catch {
              try await conn.sql().raw("ROLLBACK").run().get()
              promise.fail(error)
            }
          }
          return promise.futureResult
        }
      }
      future.whenComplete { result in
        switch result {
        case .success(let v): continuation.resume(returning: v)
        case .failure(let e): continuation.resume(throwing: e)
        }
      }
    }
  }

  public func runRollback() async throws {
    try await ensureMigrationTableExists()
    let applied = try await getAppliedMigrations()
    for migration in applied {
      let content = try loadMigrationContent(from: migration)
      try await withTransaction { db in
        let stmts = try SQLStatementParser.parse(content.down)
        for stmt in stmts {
          _ = try await db.raw(SQLQueryString(stmt)).run().get()
        }
        return ()
      }
      try await updateMigrationStatus(migration, status: .pending)
    }
  }

  public func runMigrations() async throws {
    try await ensureMigrationTableExists()
    let pending = try await getPendingMigrations()
    for migration in pending {
      let content = try loadMigrationContent(from: migration)
      try await withTransaction { db in
        let stmts = try SQLStatementParser.parse(content.up)
        for stmt in stmts {
          _ = try await db.raw(SQLQueryString(stmt)).run().get()
        }
        return ()
      }
      try await updateMigrationStatus(migration, status: .completed)
    }
  }

  private func updateMigrationStatus(
    _ migration: MigrationFile,
    status: MigrationStatus
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let future = spectro.pools.withConnection { conn in
        conn.sql().raw(
          """
          INSERT INTO schema_migrations (version, name, status)
          VALUES (\(bind: migration.version), \(bind: migration.name), \(bind: status.rawValue)::migration_status)
          ON CONFLICT(version)
            DO UPDATE SET status=\(bind: status.rawValue)::migration_status,
                          applied_at=CURRENT_TIMESTAMP;
          """
        ).run()
      }
      future.whenComplete { res in
        switch res {
        case .success: continuation.resume()
        case .failure(let e): continuation.resume(throwing: e)
        }
      }
    }
  }

  private func loadMigrationContent(from file: MigrationFile) throws -> (up: String, down: String) {
    let text = try String(contentsOf: file.filePath, encoding: .utf8)
    guard let upStart = text.range(of: "func up() -> String {")?.upperBound,
      let upEnd = text.range(of: "}", range: upStart..<text.endIndex)?.lowerBound,
      let downStart = text.range(of: "func down() -> String {")?.upperBound,
      let downEnd = text.range(of: "}", range: downStart..<text.endIndex)?.lowerBound
    else {
      throw MigrationError.invalidMigrationFile(file.version)
    }
    let upSQL = String(text[upStart..<upEnd])
      .replacingOccurrences(of: "\"\"\"", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let downSQL = String(text[downStart..<downEnd])
      .replacingOccurrences(of: "\"\"\"", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return (up: upSQL, down: downSQL)
  }

  private func noMigrationMessages() -> String {
    [
      "😎 All caught up, migrations are so yesterday.",
      "🎉 Nothing to migrate. I'm just here chilling.",
      "🛋️ No migrations left. Time for a coffee break!",
      "🙄 Everything's already migrated. What do you want from me?",
      "👌 No work for me. The database is as fresh as it gets.",
      "🎵 Migration-free and loving it, la la la!",
      "🤔 Nothing to migrate... Is this retirement?",
      "🥳 Zero migrations pending. Somebody give me a medal.",
      "🛑 Stop looking! It’s all done, smh.",
      "🌟 Perfectly migrated. Time to shine elsewhere!",
    ].randomElement()!
  }

  public func migrationCreatedMessages() -> String {
    [
      "📜 Boom! A fresh migration just dropped.",
      "✨ New migration, who dis?",
      "🛠️ Migration created. Time to make some database magic!",
      "🚀 New migration ready for takeoff!",
      "🎉 Migration created! The database gods smile upon us.",
      "🖋️ Another migration in the books. Roll tape!",
      "🗂️ New migration? It's like a database baby was born!",
      "🤓 Migration created. Time to flex my SQL muscles.",
      "🔨 Built a migration, and it's a masterpiece!",
      "🎵 Migration created... queue the epic soundtrack!",
    ].randomElement()!
  }

  public func migrationAppliedMessages() -> String {
    [
      "✅ Migration applied! The database feels brand new.",
      "🚀 Migration complete. All systems go!",
      "🎉 Migration applied successfully. Next stop: perfection!",
      "🛠️ Migration applied. The database gods approve.",
      "✨ Smooth as butter—migration applied flawlessly.",
      "🏗️ Migration done. The database is struttin' its stuff now.",
      "🤓 Migration applied! The schema leveled up.",
      "🎯 Migration hit the target! Bullseye!",
      "🔗 Migration applied... the chain is complete!",
      "🎵 Migration applied, database sings: 'We are the champions!'",
    ].randomElement()!
  }

  public func rollbackAppliedMessages() -> String {
    [
      "🔄 Rollback complete. Time to undo the oops!",
      "⏪ Rolling back... because sometimes we all need a do-over.",
      "🚧 Rollback done. Database says, 'Let’s pretend that never happened.'",
      "🛠️ Rollback successful. Erasing those regrets like a pro.",
      "🤦‍♂️ Rollback complete. Let's agree not to talk about this again.",
      "🕰️ Rollback done. Back to simpler times.",
      "❌ Migration rolled back. Database whispers, 'Nice try.'",
      "🙃 Rollback complete. Who’s counting mistakes anyway?",
      "🎬 Rollback finished. Rewind, reset, retry!",
      "🔙 Rollback done. Yesterday called and wants its schema back.",
    ].randomElement()!
  }

  public func getFormattedStatus() async throws -> String {
    // First get our migration data
    let (migrations, statuses) = try await getMigrationStatuses()

    // Build our result string before returning
    let result: String

    if migrations.isEmpty {
      result = formatEmptyStateMessage()
    } else {
      // Define our color palette for consistent usage
      let colors = TerminalColors(
        green: "\u{001B}[32m",
        yellow: "\u{001B}[33m",
        red: "\u{001B}[31m",
        reset: "\u{001B}[0m",
        dim: "\u{001B}[2m"
      )

      // Build our output line by line using dedicated formatting functions
      var lines: [String] = []

      // Add the header section
      lines.append(contentsOf: formatHeader(colors: colors))

      // Add each migration entry
      lines.append(
        contentsOf: formatMigrations(
          migrations: migrations,
          statuses: statuses,
          colors: colors
        )
      )

      // Add the summary section
      lines.append(
        contentsOf: formatSummary(
          migrations: migrations,
          statuses: statuses,
          colors: colors
        )
      )

      // Add helpful tips
      lines.append("")
      lines.append(
        colors.dim + "Tip: Use 'spectro migration --help' to see all available commands"
          + colors.reset
      )
      lines.append("")

      result = lines.joined(separator: "\n")
    }

    return result
  }

  private struct TerminalColors {
    let green: String
    let yellow: String
    let red: String
    let reset: String
    let dim: String
  }

  // Format the message shown when no migrations exist
  private func formatEmptyStateMessage() -> String {
    """
    Migration Status:
    No migrations found in Sources/Migrations directory.

    Quick Start:
    1. Create a new migration:
       spectro migration create <migration_name>
    2. Edit the migration file in Sources/Migrations
    3. Run migrations:
       spectro migration up
    """
  }

  // Format the header section of our status output
  private func formatHeader(colors: TerminalColors) -> [String] {
    if #available(macOS 12.0, *) {
      [
        "\nMigration Status:",
        "Location: Sources/Migrations",
        colors.dim
          + "Last checked: \(Date().formatted(date: .abbreviated, time: .standard))"
          + colors.reset,
        String(repeating: "-", count: 80),
        "Version".padding(toLength: 40, withPad: " ", startingAt: 0)
          + "Name".padding(toLength: 20, withPad: " ", startingAt: 0) + "Status",
        String(repeating: "-", count: 80),
      ]
    } else {
      [""]
    }
  }

  // Format the migrations list with status indicators
  private func formatMigrations(
    migrations: [MigrationFile],
    statuses: [String: MigrationStatus],
    colors: TerminalColors
  ) -> [String] {
    var lines: [String] = []

    for migration in migrations {
      let status = statuses[migration.version] ?? .pending
      let statusColor =
        status == .completed
        ? colors.green : status == .pending ? colors.yellow : colors.red

      let line =
        migration.version.padding(toLength: 40, withPad: " ", startingAt: 0)
        + migration.name.padding(toLength: 20, withPad: " ", startingAt: 0) + statusColor
        + status.rawValue.capitalized + colors.reset
      lines.append(line)

      // Add timestamp for completed migrations
      if status == .completed, let timestamp = try? getMigrationTimestamp(migration) {
        if #available(macOS 12.0, *) {
          lines.append(colors.dim + "  Applied: \(timestamp.formatted())" + colors.reset)
        } else {
          // Fallback on earlier versions
        }
      }
    }

    return lines
  }

  // Format the summary section with counts and helpful messages
  private func formatSummary(
    migrations: [MigrationFile],
    statuses: [String: MigrationStatus],
    colors: TerminalColors
  ) -> [String] {
    let pendingCount = migrations.filter {
      statuses[$0.version] == nil || statuses[$0.version] == .pending
    }.count
    let completedCount = migrations.filter { statuses[$0.version] == .completed }.count
    let failedCount = migrations.filter { statuses[$0.version] == .failed }.count

    var lines: [String] = ["", "Summary:", "Total migrations: \(migrations.count)"]

    // Add pending migrations status
    if pendingCount > 0 {
      lines.append(
        "Pending: " + colors.yellow + "\(pendingCount)" + colors.reset + colors.dim
          + " (run 'spectro migration up' to apply)" + colors.reset)
    } else {
      lines.append(
        "Pending: " + colors.green + "0" + colors.reset + colors.dim
          + " (database is up to date)" + colors.reset)
    }

    // Add completed migrations count
    lines.append("Completed: " + colors.green + "\(completedCount)" + colors.reset)

    // Add failed migrations status
    if failedCount > 0 {
      lines.append(
        "Failed: " + colors.red + "\(failedCount)" + colors.reset + colors.dim
          + " (check logs for details)" + colors.reset)
    } else {
      lines.append("Failed: " + colors.green + "0" + colors.reset)
    }

    return lines
  }

  public func insertMigrationRecord(_ record: MigrationRecord) async throws {
    try await ensureMigrationTableExists()

    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      let future: EventLoopFuture<Void> = spectro.pools.withConnection { conn in
        conn.sql().raw(
          """
          INSERT INTO schema_migrations (version, name, status)
          VALUES (\(bind: record.version), \(bind: record.name), \(bind: record.status.rawValue)::migration_status)
          ON CONFLICT (version) DO NOTHING;
          """
        ).run()
      }

      future.whenComplete { result in
        switch result {
        case .success:
          continuation.resume()
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func getMigrationTimestamp(_ migration: MigrationFile) throws -> Date? {
    // Implementation would query the database for the applied_at timestamp
    return nil
  }
}
