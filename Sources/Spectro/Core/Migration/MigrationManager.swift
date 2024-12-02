import Foundation
import PostgresKit
import SpectroCore

public class MigrationManager {
    private let spectro: Spectro
    private let fileManager: FileManager = .default
    private let migrationsPath: URL

    public init(spectro: Spectro) {
        self.spectro = spectro
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.migrationsPath = currentDirectory.appendingPathComponent("Sources/Migrations")
    }

    public func ensureMigrationTableExists() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let future = spectro.pools.withConnection { conn in
                conn.sql().raw(
                    """
                        DO $$ BEGIN
                            CREATE TYPE migration_status AS ENUM ('pending', 'completed', 'failed');
                        EXCEPTION
                            WHEN duplicate_object THEN null;
                        END $$;
                    """
                ).run()
                    .flatMap { _ -> EventLoopFuture<Void> in
                        return conn.sql().raw(
                            """
                                CREATE TABLE IF NOT EXISTS schema_migrations (
                                    version TEXT PRIMARY KEY,
                                    name TEXT NOT NULL,
                                    applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                                    status migration_status NOT NULL DEFAULT 'pending'
                                );
                            """
                        ).run()
                    }
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

    func getMigrationStatus() async throws -> [MigrationRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let future = spectro.pools.withConnection { conn in
                conn.sql()
                    .raw(
                        """
                            SELECT version, name, applied_at, status 
                            FROM schema_migrations 
                            ORDER BY version ASC
                        """
                    )
                    .all()
                    .flatMapThrowing { rows -> [MigrationRecord] in
                        return try rows.map { row in
                            try MigrationRecord(
                                version: row.decode(column: "version", as: String.self),
                                name: row.decode(column: "name", as: String.self),
                                appliedAt: row.decode(column: "applied_at", as: Date.self),
                                status: MigrationStatus(
                                    rawValue: row.decode(column: "status", as: String.self)
                                )
                            )
                        }
                    }
            }

            future.whenComplete { result in
                switch result {
                case .success(let records):
                    continuation.resume(returning: records)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func discoverMigrations() throws -> [MigrationFile] {

        guard FileManager.default.fileExists(atPath: migrationsPath.path) else {
            throw MigrationError.directoryNotFound(migrationsPath.path)
        }

        let files = try FileManager.default.contentsOfDirectory(
            at: migrationsPath, includingPropertiesForKeys: nil)

        let swiftFiles = files.filter { $0.pathExtension == "swift" }

        return swiftFiles.compactMap { fileURL -> MigrationFile? in
            let fileName = fileURL.lastPathComponent
            let components = fileName.dropLast(6).split(separator: "_", maxSplits: 1)
            guard components.count == 2,
                let timestamp = components.first,
                let name = components.last,
                isValidUnixTimestamp(String(timestamp))
            else {
                return nil
            }

            let migrationFile = MigrationFile(
                version: "\(timestamp)_\(name)",
                name: String(name),
                filePath: fileURL
            )
            return migrationFile
        }.sorted { $0.version < $1.version }
    }

    public func getMigrationStatuses() async throws -> (
        discovered: [MigrationFile], statuses: [String: MigrationStatus]
    ) {
        let discoveredMigrations = try discoverMigrations()
        let appliedMigrations = try await getMigrationStatus()
        let migrationStatuses = Dictionary(
            uniqueKeysWithValues: appliedMigrations.map { ($0.version, $0.status) }
        )
        return (discoveredMigrations, migrationStatuses)
    }

    func getPendingMigrations() async throws -> [MigrationFile] {
        do {
            let (migrations, statuses) = try await getMigrationStatuses()

            let pendingMigrations = migrations.filter { migration in
                if let status = statuses[migration.version] {
                    return status == .pending
                }
                return true  // Not in database means pending
            }
            return pendingMigrations
        } catch {
            throw error
        }
    }

    func getAppliedMigrations() async throws -> [MigrationFile] {
        let (migrations, statuses) = try await getMigrationStatuses()

        let appliedMigrations = migrations.filter { migration in
            if let status = statuses[migration.version] {
                return status != .pending
            }
            return false  // Not in database means not applied
        }
        return appliedMigrations
    }

    func isValidUnixTimestamp(_ timestamp: String) -> Bool {
        guard let timestampNumber = Double(timestamp), timestampNumber > 0 else {
            return false
        }

        let secondsSince1970 = Date().timeIntervalSince1970
        if timestampNumber < secondsSince1970 + 100 * 365 * 24 * 60 * 60 {  // 100 years in the future
            return true
        }

        return false
    }

    public func runRollback() async throws {
        try await ensureMigrationTableExists()
        let appliedMigrations = try await getAppliedMigrations()
        for migration in appliedMigrations {
            try await withTransaction { db in
                let content = try self.loadMigrationContent(from: migration)
                try await self.executeMigration(content.down, on: db)
                try await self.updateMigrationStatus(migration, status: .pending)
                return ()
            }
        }
    }

    public func runMigrations() async throws {
        try await ensureMigrationTableExists()

        let pendingMigrations = try await getPendingMigrations()
        if pendingMigrations.count == 0 {
            print(noMigrationMessages())
            return ()
        }

        for migration in pendingMigrations {
            try await withTransaction { db in
                let content = try self.loadMigrationContent(from: migration)
                try await self.executeMigration(content.up, on: db)
                try await self.updateMigrationStatus(migration, status: .completed)
                return ()
            }
        }

        if pendingMigrations.count == 1 {
            print("Sucessfully applied: 1 pending migration")
        }
        print("Sucessfully applied: \(pendingMigrations.count) pending migrations")
    }

    private func withTransaction<T>(_ operation: @escaping (SQLDatabase) async throws -> T)
        async throws -> T
    {
        try await withCheckedThrowingContinuation { continuation in
            let future = spectro.pools.withConnection { conn in
                conn.sql().raw("BEGIN").run().flatMap { _ in
                    let promise: EventLoopPromise<T> = conn.eventLoop.makePromise()

                    Task {
                        do {
                            let result = try await operation(conn.sql())
                            try await conn.sql().raw("COMMIT").run().get()
                            promise.succeed(result)
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
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

    }

    private func updateMigrationStatus(_ migration: MigrationFile, status: MigrationStatus)
        async throws
    {
        try await withCheckedThrowingContinuation { continuation in
            let future = spectro.pools.withConnection { conn in
                conn.sql().raw(
                    """
                        INSERT INTO schema_migrations (version, name, status)
                        VALUES (\(bind: migration.version), \(bind: migration.name), \(bind: status.rawValue)::migration_status)
                        ON CONFLICT (version) 
                        DO UPDATE SET status = \(bind: status.rawValue)::migration_status, applied_at = CURRENT_TIMESTAMP
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

    private func executeMigration(_ sql: String, on db: SQLDatabase) async throws {

        let statements = try SQLStatementParser.parse(sql)

        for _ in statements.enumerated() {
            try await withCheckedThrowingContinuation { continuation in
                let future = statements.enumerated().reduce(
                    db.raw(SQLQueryString(statements[0])).run()
                ) {
                    chain, next in

                    let (_, statement) = next
                    return chain.flatMap { _ -> EventLoopFuture<Void> in
                        return db.raw(SQLQueryString(statement)).run()
                    }

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

    private func loadMigrationContent(from file: MigrationFile) throws -> (up: String, down: String)
    {
        let content = try String(contentsOf: file.filePath, encoding: .utf8)
        guard let upStart = content.range(of: "func up() -> String {")?.upperBound,
            let upEnd = content.range(of: "}", range: upStart..<content.endIndex)?.lowerBound,
            let downStart = content.range(of: "func down() -> String {")?.upperBound,
            let downEnd = content.range(of: "}", range: downStart..<content.endIndex)?.lowerBound
        else {
            throw MigrationError.invalidMigrationFile(file.version)
        }

        let upContent = String(content[upStart..<upEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"\"\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let downContent = String(content[downStart..<downEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"\"\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (up: upContent, down: downContent)
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
        // This is just a placeholder - you'd need to implement the actual database query
        return nil
    }
}
