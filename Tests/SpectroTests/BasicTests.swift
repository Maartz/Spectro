import Foundation
import Testing
@testable import Spectro

@Suite("Basic Spectro Tests")
struct BasicSpectroTests {
    
    @Test("Can create Spectro instance")
    func testSpectroCreation() async throws {
        let spectro = try Spectro(
            hostname: "localhost",
            port: 5432, 
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        
        // Test that we can get a repository
        let repo = spectro.repository()
        
        // Just verify the types work
        #expect(repo is GenericDatabaseRepo)
        
        await spectro.shutdown()
    }
    
    @Test("Can test database connection")
    func testDatabaseConnection() async throws {
        let spectro = try Spectro(
            username: "postgres", 
            password: "postgres", 
            database: "spectro_test"
        )
        
        // This should connect to PostgreSQL and get version
        let version = try await spectro.testConnection()
        #expect(version.contains("PostgreSQL"))
        
        await spectro.shutdown()
    }
    
    @Test("Can create from configuration") 
    func testConfigurationCreation() async throws {
        let config = DatabaseConfiguration(
            hostname: "localhost",
            port: 5432,
            username: "postgres", 
            password: "postgres",
            database: "spectro_test"
        )
        
        let spectro = try Spectro(configuration: config)
        
        // Test connection
        let version = try await spectro.testConnection()
        #expect(version.contains("PostgreSQL"))
        
        await spectro.shutdown()
    }
}