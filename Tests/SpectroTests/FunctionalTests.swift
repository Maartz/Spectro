import Foundation
import Testing
import PostgresKit
import NIOCore
@testable import Spectro

@Suite("Spectro Functional Tests")
struct SpectroFunctionalTests {
    
    // MARK: - Setup and Teardown
    
    /// Setup test database before running tests
    func setupDatabase() async throws -> DatabaseRepo {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        
        let repo = spectro.repository()
        try await TestDatabase.resetDatabase(using: repo)
        return repo
    }
    
    // MARK: - CRUD Operations with New Schema System
    
    @Test("Complete CRUD cycle with new Schema system")
    func testUserCRUDCycleNewSystem() async throws {
        let repo = try await setupDatabase()
        
        // Create using beautiful new API
        let user = User(name: "Alice Smith", email: "alice@example.com", age: 28)
        let savedUser = try await repo.insert(user)
        
        #expect(savedUser.name == "Alice Smith")
        #expect(savedUser.email == "alice@example.com")
        #expect(savedUser.age == 28)
        #expect(savedUser.isActive == true) // Default value
        
        // Read
        let fetchedUser = try await repo.get(User.self, id: savedUser.id)
        #expect(fetchedUser != nil)
        #expect(fetchedUser?.email == "alice@example.com")
        
        // Update
        let updatedUser = try await repo.update(User.self, id: savedUser.id, changes: [
            "age": 29,
            "name": "Alice Johnson"
        ])
        #expect(updatedUser.age == 29)
        #expect(updatedUser.name == "Alice Johnson")
        
        // Delete
        try await repo.delete(User.self, id: savedUser.id)
        let deletedUser = try await repo.get(User.self, id: savedUser.id)
        #expect(deletedUser == nil)
    }
    
    @Test("Repository get all users with new system")
    func testGetAllUsersNewSystem() async throws {
        let repo = try await setupDatabase()
        
        // Create test users with beautiful new API
        let user1 = User(name: "Test User 1", email: "test1@example.com", age: 25)
        let user2 = User(name: "Test User 2", email: "test2@example.com", age: 30)
        
        let savedUser1 = try await repo.insert(user1)
        let savedUser2 = try await repo.insert(user2)
        
        // Get all users
        let users = try await repo.all(User.self)
        #expect(users.count >= 2)
        
        // Test beautiful query syntax
        let youngUsers = try await repo.query(User.self)
            .where { $0.age < 30 }
            .orderBy { $0.name }
            .all()
        
        #expect(youngUsers.count >= 1)
        #expect(youngUsers.contains { $0.name == "Test User 1" })
        
        // Clean up
        try await repo.delete(User.self, id: savedUser1.id)
        try await repo.delete(User.self, id: savedUser2.id)
    }
    
    @Test("Repository getOrFail with new system")
    func testGetOrFailNewSystem() async throws {
        let repo = try await setupDatabase()
        
        // Create a user
        let user = User(name: "Test User", email: "test@example.com", age: 25)
        let savedUser = try await repo.insert(user)
        
        // Test getOrFail with existing user
        let fetchedUser = try await repo.getOrFail(User.self, id: savedUser.id)
        #expect(fetchedUser.name == "Test User")
        #expect(fetchedUser.email == "test@example.com")
        
        // Delete the user
        try await repo.delete(User.self, id: savedUser.id)
        
        // Test getOrFail with non-existing user should throw
        do {
            _ = try await repo.getOrFail(User.self, id: savedUser.id)
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected to throw
            #expect(true)
        }
    }
    
    @Test("Beautiful closure-based queries showcase")
    func testClosureBasedQueriesShowcase() async throws {
        let repo = try await setupDatabase()
        
        // Create diverse test data
        let users = [
            User(name: "Alice", email: "alice@company.com", age: 25),
            User(name: "Bob", email: "bob@startup.io", age: 35),
            User(name: "Charlie", email: "charlie@company.com", age: 45),
            User(name: "Diana", email: "diana@freelance.net", age: 28)
        ]
        
        var savedUserIds: [UUID] = []
        for user in users {
            let saved = try await repo.insert(user)
            savedUserIds.append(saved.id)
        }
        
        // Test rich string functions
        let companyUsers = try await repo.query(User.self)
            .where { $0.email.endsWith("@company.com") }
            .orderBy { $0.name }
            .all()
        
        #expect(companyUsers.count == 2)
        #expect(companyUsers[0].name == "Alice")
        #expect(companyUsers[1].name == "Charlie")
        
        // Test complex conditions with beautiful && syntax
        let experiencedCompanyUsers = try await repo.query(User.self)
            .where { $0.email.endsWith("@company.com") && $0.age > 30 }
            .all()
        
        #expect(experiencedCompanyUsers.count == 1)
        #expect(experiencedCompanyUsers[0].name == "Charlie")
        
        // Test case-insensitive search
        let alicelikes = try await repo.query(User.self)
            .where { $0.name.iContains("alice") }
            .all()
        
        #expect(alicelikes.count == 1)
        #expect(alicelikes[0].name == "Alice")
        
        // Test age ranges
        let youngProfessionals = try await repo.query(User.self)
            .where { $0.age.between(25, and: 35) }
            .orderBy({ $0.age }, .asc)
            .all()
        
        #expect(youngProfessionals.count == 3) // Alice, Diana, Bob
        #expect(youngProfessionals[0].age == 25) // Alice first
        
        // Clean up
        for userId in savedUserIds {
            try await repo.delete(User.self, id: userId)
        }
    }
    
    @Test("Database connection test")
    func testDatabaseConnection() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let version = try await spectro.testConnection()
        #expect(version.contains("PostgreSQL"))
    }
}