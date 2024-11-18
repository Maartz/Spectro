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
}
