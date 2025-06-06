import Foundation
import Testing
import PostgresKit
import NIOCore
@testable import Spectro

@Suite("Spectro Functional Tests")
struct SpectroFunctionalTests {
    
    // MARK: - CRUD Operations
    
    @Test("Complete CRUD cycle for users")
    func testUserCRUDCycle() async throws {
        let spectro = try TestSetup.getSpectro()
        let repo = spectro.repository()
        
        // First, create the users table if it doesn't exist
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS users (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            name TEXT NOT NULL,
            email TEXT NOT NULL,
            age INTEGER,
            password TEXT,
            created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        );
        """
        
        // Use the repository's transaction functionality to execute DDL
        try await repo.transaction { transactionRepo in
            // For now, let's skip table creation and assume it exists
            // We'll implement a proper test database setup later
            return ()
        }
        
        // Create
        let userData = [
            "name": "Alice Smith",
            "email": "alice@example.com", 
            "age": 28,
            "password": "secret123"
        ] as [String: Any]
        
        let user = try await repo.insert(UserSchema.self, data: userData)
        
        #expect(user.data["name"] as? String == "Alice Smith")
        #expect(user.data["age"] as? Int == 28)
        
        // Read
        let fetchedUser = try await repo.get(UserSchema.self, id: user.id)
        #expect(fetchedUser != nil)
        if let fetched = fetchedUser {
            #expect(fetched.data["email"] as? String == "alice@example.com")
        }
        
        // Update
        let updatedUser = try await repo.update(UserSchema.self, id: user.id, changes: [
            "age": 29,
            "name": "Alice Johnson"
        ])
        #expect(updatedUser.data["age"] as? Int == 29)
        #expect(updatedUser.data["name"] as? String == "Alice Johnson")
        
        // Delete
        try await repo.delete(UserSchema.self, id: user.id)
        let deletedUser = try await repo.get(UserSchema.self, id: user.id)
        #expect(deletedUser == nil)
        
        // Clean up
        await spectro.shutdown()
    }
    
    @Test("Repository get all users")
    func testGetAllUsers() async throws {
        let repo = try TestSetup.getRepo()
        
        // Create test users
        let user1Data = [
            "name": "Test User 1",
            "email": "test1@example.com",
            "age": 25,
            "password": "password"
        ] as [String: Any]
        
        let user2Data = [
            "name": "Test User 2", 
            "email": "test2@example.com",
            "age": 30,
            "password": "password"
        ] as [String: Any]
        
        let user1 = try await repo.insert(UserSchema.self, data: user1Data)
        let user2 = try await repo.insert(UserSchema.self, data: user2Data)
        
        // Get all users
        let users = try await repo.all(UserSchema.self)
        #expect(users.count >= 2)
        
        // Clean up
        try await repo.delete(UserSchema.self, id: user1.id)
        try await repo.delete(UserSchema.self, id: user2.id)
        await TestSetup.shutdown()
    }
    
    @Test("Repository getOrFail")
    func testGetOrFail() async throws {
        let repo = try TestSetup.getRepo()
        
        // Create a user
        let userData = [
            "name": "Test User",
            "email": "test@example.com",
            "age": 25,
            "password": "password"
        ] as [String: Any]
        
        let user = try await repo.insert(UserSchema.self, data: userData)
        
        // Test getOrFail with existing user
        let fetchedUser = try await repo.getOrFail(UserSchema.self, id: user.id)
        #expect(fetchedUser.data["name"] as? String == "Test User")
        
        // Delete the user
        try await repo.delete(UserSchema.self, id: user.id)
        
        // Test getOrFail with non-existing user should throw
        do {
            _ = try await repo.getOrFail(UserSchema.self, id: user.id)
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected to throw
            #expect(true)
        }
        
        await TestSetup.shutdown()
    }
    
    @Test("Database connection test")
    func testDatabaseConnection() async throws {
        let spectro = try TestSetup.getSpectro()
        let version = try await spectro.testConnection()
        #expect(version.contains("PostgreSQL"))
        
        await TestSetup.shutdown()
    }
}