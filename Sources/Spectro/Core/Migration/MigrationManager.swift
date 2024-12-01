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

    struct MigrationRecord {
        let version: String
        let name: String
        let appliedAt: Date
        let status: MigrationStatus
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

    func getMigrationStatuses() async throws -> (
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

        for migration in pendingMigrations {
            try await withTransaction { db in
                let content = try self.loadMigrationContent(from: migration)
                try await self.executeMigration(content.up, on: db)
                try await self.updateMigrationStatus(migration, status: .completed)
                return ()
            }
        }
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
}
