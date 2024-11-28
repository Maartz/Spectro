import Foundation
import PostgresKit
import SpectroCore

public class MigrationManager {
    private let spectro: Spectro
    private let fileManager: FileManager = .default
    private let migrationsPath = "Sources/Migrations"

    public init(spectro: Spectro) {
        self.spectro = spectro
    }

    public struct MigrationFile {
        let version: String
        let name: String
        let filePath: String
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
                    .map { rows -> [MigrationRecord] in
                        rows.map { row in
                            MigrationRecord(
                                version: try! row.decode(column: "version", as: String.self),
                                name: try! row.decode(column: "name", as: String.self),
                                appliedAt: try! row.decode(column: "applied_at", as: Date.self),
                                status: MigrationStatus(
                                    rawValue: try! row.decode(column: "status", as: String.self))
                                    ?? .failed
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
        debugPrint("Checking migrations directory:", migrationsPath)

        guard FileManager.default.fileExists(atPath: migrationsPath) else {
            debugPrint("Migrations directory not found")
            throw MigrationError.directoryNotFound(migrationsPath)
        }

        debugPrint("Reading directory contents")
        let files = try FileManager.default.contentsOfDirectory(atPath: migrationsPath)
        let swiftFiles = files.filter { $0.hasSuffix(".swift") }
        debugPrint("Found Swift files:", swiftFiles)

        return swiftFiles.compactMap { fileName -> MigrationFile? in
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
                filePath: "\(migrationsPath)/\(fileName)"
            )
            debugPrint("Created MigrationFile:", migrationFile)
            return migrationFile
        }.sorted { $0.version < $1.version }
    }

    public func getPendingMigrations() async throws -> [MigrationFile] {
        let discoveredMigrations = try discoverMigrations()
        let appliedMigrations = try await getMigrationStatus()

        let appliedVersions = Set(appliedMigrations.map(\.version))
        return discoveredMigrations.filter { !appliedVersions.contains($0.version) }
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

    public func runMigrations() async throws {
        try await ensureMigrationTableExists()

        let pendingMigrations = try await getPendingMigrations()

        for migration in pendingMigrations {
            try await withTransaction { conn in
                _ = migration
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
                        VALUES (\(bind: migration.version), \(bind: migration.name), \(bind: status.rawValue))
                        ON CONFLICT (version) 
                        DO UPDATE SET status = \(bind: status.rawValue), applied_at = CURRENT_TIMESTAMP
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
        try await withCheckedThrowingContinuation { continuation in
            db.raw(SQLQueryString.init(sql)).run().whenComplete { result in
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
