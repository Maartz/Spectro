import Foundation
import Testing
@testable import Spectro
@testable import SpectroCore

@Suite("Migration System")
struct MigrationFunctionalTests {
    
    @Test("Migration manager can discover and track migrations")
    func testMigrationDiscovery() async throws {
        let spectro = try Spectro(username: "postgres", password: "postgres", database: "spectro_test")
        
        let manager = spectro.migrationManager()
        
        // Should be able to get migration status
        let status = try await manager.getMigrationStatus()
        #expect(status.count >= 0)
        
        // Should be able to discover migrations (even if directory doesn't exist)
        let discovered = try manager.discoverMigrations()
        #expect(discovered.count >= 0)
        
        await spectro.shutdown()
    }
    
    @Test("Migration table management")
    func testMigrationTableManagement() async throws {
        let spectro = try Spectro(username: "postgres", password: "postgres", database: "spectro_test")
        
        let manager = spectro.migrationManager()
        
        // Should be able to ensure migration table exists
        try await manager.ensureMigrationTableExists()
        
        // Should be able to get pending migrations
        let pending = try await manager.getPendingMigrations()
        #expect(pending.count >= 0)
        
        await spectro.shutdown()
    }
}
