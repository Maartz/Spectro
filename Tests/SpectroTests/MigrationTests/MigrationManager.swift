import Foundation
import XCTest

@testable import Spectro
@testable import SpectroCore

final class MigrationManagerTests: XCTestCase {
    var spectro: Spectro!
    var manager: MigrationManager!

    override func setUp() async throws {
        spectro = try Spectro(username: "postgres", password: "postgres", database: "spectro_test")
        manager = spectro.migrationManager()
        let version = try await spectro.test()
        try setupTestMigrations()
    }

    override func tearDown() async throws {
        try await cleanTestDatabase()
        spectro.shutdown()
        try FileManager.default.removeItem(atPath: "Sources/Migrations")
    }

    private func cleanTestDatabase() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let future = spectro.pools.withConnection { conn in
                conn.sql().raw(
                    """
                        DO $$ 
                        BEGIN
                            DROP TABLE IF EXISTS schema_migrations;
                            IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'migration_status') THEN
                                DROP TYPE migration_status;
                            END IF;
                        END $$;
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

    private func setupTestMigrations() throws {
        let testMigrationsPath = "Sources/Migrations"

        if FileManager.default.fileExists(atPath: testMigrationsPath) {
        } else {
            try FileManager.default.createDirectory(
                atPath: testMigrationsPath,
                withIntermediateDirectories: true
            )
        }

        let migrations = [
            "1700000000_create_users.swift",
            "1700000001_add_user_email.swift",
        ]

        for migration in migrations {
            let path = "\(testMigrationsPath)/\(migration)"

            let content = """
                import Spectro
                struct Migration: SpectroMigration {
                    func up() -> String {
                        \"\"\"
                        CREATE TABLE IF NOT EXISTS user (
                            id SERIAL PRIMARY KEY,
                            username VARCHAR(50) NOT NULL,
                            email VARCHAR(100) UNIQUE NOT NULL,
                            password_hash TEXT NOT NULL,
                            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                        );
                        \"\"\"
                    }

                    func down() -> String {
                        \"\"\"
                        DROP TABLE IF EXISTS user
                        \"\"\"
                    }
                }
                """
            try content.write(
                toFile: path,
                atomically: true,
                encoding: .utf8
            )
        }
    }

    func testDiscoverMigrations() throws {
        let migrations = try manager.discoverMigrations()
        XCTAssertEqual(migrations.count, 2)
        XCTAssertEqual(migrations[0].version, "1700000000_create_users")
        XCTAssertEqual(migrations[1].version, "1700000001_add_user_email")
    }

    func testEnsureMigrationTableExists() async throws {
        try await manager.ensureMigrationTableExists()

        try await withCheckedThrowingContinuation { continuation in
            let future = spectro.pools.withConnection { conn in
                conn.sql().raw(
                    """
                        INSERT INTO schema_migrations (version, name, status)
                        VALUES ('test_version', 'test_name', 'pending')
                    """
                ).run()
            }

            future.whenComplete { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    func testGetMigrationStatusWithRecords() async throws {
        try await cleanTestDatabase()
        try setupTestMigrations()
        try await manager.ensureMigrationTableExists()

        try await withCheckedThrowingContinuation { continuation in
            let future = spectro.pools.withConnection { conn in
                conn.sql().raw(
                    """
                        INSERT INTO schema_migrations (version, name, status)
                        VALUES 
                            ('1700000000_first', 'first', 'completed'),
                            ('1700000001_second', 'second', 'pending')
                    """
                ).run()
            }

            future.whenComplete { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }

        let status = try await manager.getMigrationStatus()
        XCTAssertEqual(status.count, 2, "Should have two migrations")
        XCTAssertEqual(status[0].version, "1700000000_first")
        XCTAssertEqual(status[0].status, .completed)
        XCTAssertEqual(status[1].version, "1700000001_second")
        XCTAssertEqual(status[1].status, .pending)
    }

    func testDiscoverMigrationsInvalidFiles() async throws {
        let testMigrationsPath = "Sources/Migrations"
        try FileManager.default.createDirectory(
            atPath: testMigrationsPath,
            withIntermediateDirectories: true
        )

        let invalidFiles = [
            "invalid.swift",
            "no_timestamp.swift",
            "123456.swift",
            "-12345.swift",
            "99999999999_to_large.swift",
        ]

        for file in invalidFiles {
            try "".write(
                toFile: "\(testMigrationsPath)/\(file)",
                atomically: true,
                encoding: .utf8
            )
        }

        let migrations = try manager.discoverMigrations()
        XCTAssertEqual(migrations.count, 2, "Should not discover any invalid migrations")
    }

    func testDiscoverMigrationsValidFiles() async throws {
        let testMigrationsPath = "Sources/Migrations"
        try FileManager.default.createDirectory(
            atPath: testMigrationsPath,
            withIntermediateDirectories: true
        )

        let timestamp = Int(Date().timeIntervalSince1970)
        let validFiles = [
            "\(timestamp)_valid_migration.swift",
            "\(timestamp + 1)_valid_migration.swift",
        ]

        for file in validFiles {
            try "".write(
                toFile: "\(testMigrationsPath)/\(file)",
                atomically: true,
                encoding: .utf8
            )
        }

        let migrations = try manager.discoverMigrations()
        XCTAssertEqual(migrations.count, 4, "Should discover valid migrations")
    }

    func testGetPendingMigrationsPartial() async throws {
        try await manager.ensureMigrationTableExists()
        try await withCheckedThrowingContinuation { continuation in
            let future = spectro.pools.withConnection { conn in
                conn.sql().raw(
                    """
                        INSERT INTO schema_migrations (version, name, status)
                        VALUES ('1700000000_create_users', 'create_users', 'completed')
                    """
                ).run()
            }

            future.whenComplete { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }

        let pending = try await manager.getPendingMigrations()
        XCTAssertEqual(pending.count, 1, "Should have one pending migration")
        XCTAssertEqual(pending[0].version, "1700000001_add_user_email")
    }

    func testMigrationStatusTransitions() async throws {
        try await manager.ensureMigrationTableExists()

        for status in MigrationStatus.allCases {
            try await withCheckedThrowingContinuation { continuation in
                let future = spectro.pools.withConnection { conn in
                    conn.sql().raw(
                        """
                            INSERT INTO schema_migrations (version, name, status)
                            VALUES ('test_\(unsafeRaw: status.rawValue)', 'test', '\(unsafeRaw: status.rawValue)')
                        """
                    ).run()
                }

                future.whenComplete { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            }
        }

        let statuses = try await manager.getMigrationStatus()
        XCTAssertEqual(statuses.count, MigrationStatus.allCases.count)

        for (status, record) in zip(
            MigrationStatus.allCases.sorted { $0.rawValue < $1.rawValue }, statuses)
        {
            XCTAssertEqual(record.status, status)
        }
    }
}
