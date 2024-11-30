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

    public struct MigrationFile {
        let version: String
        let name: String
        let filePath: URL
    }

    struct MigrationRecord {
        let version: String
        let name: String
        let appliedAt: Date
        let status: MigrationStatus
    }

    public func ensureMigrationTableExists() async throws {
        try await withCheckedThrowingContinuation { continuation in
            debugPrint("Creating migration_status enum and schema_migrations table")
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
                        debugPrint("Creating schema_migrations table")
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
            debugPrint("Getting migration status from database...")
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
                        debugPrint("Found \(rows.count) migration records")
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
                    debugPrint("Migration status retrieved")
                    continuation.resume(returning: records)
                case .failure(let error):
                    debugPrint("Failed to get migration status:", String(reflecting: error))
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func discoverMigrations() throws -> [MigrationFile] {
        debugPrint("Checking migrations directory:", migrationsPath)

        guard FileManager.default.fileExists(atPath: migrationsPath.path) else {
            debugPrint("Migrations directory not found")
            throw MigrationError.directoryNotFound(migrationsPath.path)
        }

        debugPrint("Reading directory contents")
        let files = try FileManager.default.contentsOfDirectory(
            at: migrationsPath, includingPropertiesForKeys: nil)

        let swiftFiles = files.filter { $0.pathExtension == "swift" }
        debugPrint("Found Swift files:", swiftFiles)

        return swiftFiles.compactMap { fileURL -> MigrationFile? in
            let fileName = fileURL.lastPathComponent
            debugPrint("Processing file:", fileName)
            let components = fileName.dropLast(6).split(separator: "_", maxSplits: 1)
            guard components.count == 2,
                let timestamp = components.first,
                let name = components.last,
                isValidUnixTimestamp(String(timestamp))
            else {
                debugPrint("Invalid migration file format:", fileName)
                return nil
            }

            debugPrint("TS: \(timestamp)")
            let migrationFile = MigrationFile(
                version: "\(timestamp)_\(name)",
                name: String(name),
                filePath: fileURL
            )
            debugPrint("Created MigrationFile:", migrationFile)
            return migrationFile
        }.sorted { $0.version < $1.version }
    }

    private func getMigrationStatuses() async throws -> (
        discovered: [MigrationFile], statuses: [String: MigrationStatus]
    ) {
        debugPrint("Discovering migrations...")
        let discoveredMigrations = try discoverMigrations()
        debugPrint("Discovered \(discoveredMigrations.count) migration files")

        let appliedMigrations = try await getMigrationStatus()
        debugPrint("Retrieved \(appliedMigrations.count) migration records")

        let migrationStatuses = Dictionary(
            uniqueKeysWithValues: appliedMigrations.map { ($0.version, $0.status) }
        )

        return (discoveredMigrations, migrationStatuses)
    }

    public func getPendingMigrations() async throws -> [MigrationFile] {
        debugPrint("Getting pending migrations...")
        do {
            let (migrations, statuses) = try await getMigrationStatuses()

            let pendingMigrations = migrations.filter { migration in
                if let status = statuses[migration.version] {
                    return status == .pending
                }
                return true  // Not in database means pending
            }

            debugPrint("Identified \(pendingMigrations.count) pending migrations")
            return pendingMigrations
        } catch {
            debugPrint("Failed to get pending migrations:", String(reflecting: error))
            throw error
        }
    }

    func getAppliedMigrations() async throws -> [MigrationFile] {
        debugPrint("Getting applied migrations...")
        let (migrations, statuses) = try await getMigrationStatuses()

        let appliedMigrations = migrations.filter { migration in
            if let status = statuses[migration.version] {
                return status != .pending
            }
            return false  // Not in database means not applied
        }

        debugPrint("Found \(appliedMigrations.count) applied migrations")
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
        debugPrint("Starting to rollback \(appliedMigrations.count) migrations")
        for migration in appliedMigrations {
            debugPrint("Rolling back migration:", migration.version)
            try await withTransaction { db in
                debugPrint("Loading migration content")
                let content = try self.loadMigrationContent(from: migration)
                debugPrint("Executing migration:", migration.version)
                try await self.executeMigration(content.down, on: db)
                debugPrint("Updating migration status to pending")
                try await self.updateMigrationStatus(migration, status: .pending)
                debugPrint("Migration rolled back")
                return ()
            }
        }
    }

    public func runMigrations() async throws {
        try await ensureMigrationTableExists()

        let pendingMigrations = try await getPendingMigrations()
        debugPrint("Starting to run \(pendingMigrations.count) pending migrations")

        for migration in pendingMigrations {
            debugPrint("Running migration:", migration.version)
            try await withTransaction { db in
                debugPrint("Loading migration content")
                let content = try self.loadMigrationContent(from: migration)
                debugPrint("Executing migration:", migration.version)
                try await self.executeMigration(content.up, on: db)
                debugPrint("Updating migration status to completed")
                try await self.updateMigrationStatus(migration, status: .completed)

                debugPrint("Migration completed")
                return ()
            }
        }
    }

    private func withTransaction<T>(_ operation: @escaping (SQLDatabase) async throws -> T)
        async throws -> T
    {
        try await withCheckedThrowingContinuation { continuation in
            debugPrint("Starting transaction")
            let future = spectro.pools.withConnection { conn in
                conn.sql().raw("BEGIN").run().flatMap { _ in
                    debugPrint("BEGIN executed")
                    let promise: EventLoopPromise<T> = conn.eventLoop.makePromise()

                    Task {
                        do {
                            debugPrint("Executing transaction operation")
                            let result = try await operation(conn.sql())
                            debugPrint("operation successful, commiting")
                            try await conn.sql().raw("COMMIT").run().get()
                            debugPrint("COMMIT sucessful")
                            promise.succeed(result)
                        } catch {
                            debugPrint("operation failed:", String(reflecting: error))
                            debugPrint("ROLLBACK")
                            try await conn.sql().raw("ROLLBACK").run().get()
                            debugPrint("ROLLBACK successful")
                            promise.fail(error)
                        }
                    }

                    return promise.futureResult
                }
            }

            future.whenComplete { result in
                switch result {
                case .success(let value):
                    debugPrint("Transaction completed")
                    continuation.resume(returning: value)
                case .failure(let error):
                    debugPrint("Transaction failed:", String(reflecting: error))
                    continuation.resume(throwing: error)
                }
            }
        }

    }

    private func updateMigrationStatus(_ migration: MigrationFile, status: MigrationStatus)
        async throws
    {
        debugPrint("Updating migration status for:", migration.version)
        debugPrint("Status:", status.rawValue)
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
        let statements = sql.components(separatedBy: ";\n").filter { !$0.isEmpty }.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
            .map { $0 + ";" }

        debugPrint("Executing \(statements.count) SQL statements")

        for (index, statement) in statements.enumerated() {
            debugPrint("Executing statement \(index + 1):", statement)

            try await withCheckedThrowingContinuation { continuation in
                let future = statements.enumerated().reduce(
                    db.raw(SQLQueryString(statements[0])).run()
                ) {
                    chain, next in

                    let (index, statement) = next
                    return chain.flatMap { _ -> EventLoopFuture<Void> in
                        debugPrint("Executing statement \(index + 1):")
                        return db.raw(SQLQueryString(statement)).run()
                    }

                }

                future.whenComplete { result in
                    switch result {
                    case .success:
                        debugPrint("All statements executed")
                        continuation.resume()
                    case .failure(let error):
                        debugPrint("All Statement failed:", String(reflecting: error))
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func loadMigrationContent(from file: MigrationFile) throws -> (up: String, down: String)
    {
        let content = try String(contentsOf: file.filePath, encoding: .utf8)
        debugPrint("Reading content from:", file.filePath.path)
        debugPrint("Content:", content)

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

        debugPrint("Up content:", upContent)
        debugPrint("Down content:", downContent)
        return (up: upContent, down: downContent)
    }
}
