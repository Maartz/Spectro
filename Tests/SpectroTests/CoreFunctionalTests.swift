import Foundation
import Testing
@testable import Spectro

@Suite("Core Spectro Functionality")
struct CoreFunctionalTests {
    
    // MARK: - Unit Tests (No Database)
    
    @Test("Property wrapper schemas work correctly")
    func testPropertyWrapperSchemas() throws {
        // Test User schema with property wrapper syntax
        let user = User(name: "Alice Johnson", email: "alice@example.com", age: 28)
        
        #expect(user.name == "Alice Johnson")
        #expect(user.email == "alice@example.com")
        #expect(user.age == 28)
        #expect(user.isActive == true) // Default value
        #expect(user.id.uuidString.count == 36) // Valid UUID
        
        // Test automatic timestamps
        #expect(user.createdAt <= Date())
        #expect(user.updatedAt <= Date())
        
        // Test schema metadata
        #expect(User.tableName == "users")
    }
    
    @Test("Post schema with foreign keys")
    func testPostSchema() throws {
        var post = Post()
        post.title = "My First Post"
        post.content = "This is amazing content!"
        post.published = true
        
        #expect(post.title == "My First Post")
        #expect(post.content == "This is amazing content!")
        #expect(post.published == true)
        #expect(Post.tableName == "posts")
    }
    
    @Test("Spectro instance creation")
    func testSpectroInstanceCreation() throws {
        // Test basic instance creation
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        
        let repo = spectro.repository()
        #expect(type(of: repo) == GenericDatabaseRepo.self)
    }
    
    // MARK: - Database Integration Tests
    
    @Test("Complete CRUD operations")
    func testCRUDOperations() async throws {
        let spectro = try await TestDatabaseState.getSharedSpectro()
        let repo = spectro.repository()
        try await TestDatabase.setupTestDatabase(using: repo)
        
        // Create with unique email
        let user = User(name: "John Doe", email: TestDatabase.uniqueEmail("crud"), age: 30)
        let savedUser = try await repo.insert(user)
        
        #expect(savedUser.name == "John Doe")
        #expect(savedUser.email == user.email)
        #expect(savedUser.age == 30)
        
        // Read
        let foundUser = try await repo.get(User.self, id: savedUser.id)
        #expect(foundUser?.name == "John Doe")
        
        // Update
        let updatedUser = try await repo.update(User.self, id: savedUser.id, changes: [
            "age": 31,
            "name": "John Smith"
        ])
        #expect(updatedUser.age == 31)
        #expect(updatedUser.name == "John Smith")
        
        // Delete
        try await repo.delete(User.self, id: savedUser.id)
        let deletedUser = try await repo.get(User.self, id: savedUser.id)
        #expect(deletedUser == nil)
    }
    
    @Test("Basic query operations")
    func testBasicQueries() async throws {
        let spectro = try await TestDatabaseState.getSharedSpectro()
        let repo = spectro.repository()
        try await TestDatabase.setupTestDatabase(using: repo)
        
        // Create test users with unique emails
        let alice = User(name: "Alice", email: TestDatabase.uniqueEmail("alice"), age: 25)
        let bob = User(name: "Bob", email: TestDatabase.uniqueEmail("bob"), age: 35)
        
        let savedAlice = try await repo.insert(alice)
        let savedBob = try await repo.insert(bob)
        
        // Test basic query
        let allUsers = try await repo.all(User.self)
        #expect(allUsers.count >= 2)
        
        // Test query with where clause
        let query = await repo.query(User.self).where { $0.age > 30 }
        let olderUsers = try await query.all()
        #expect(olderUsers.count >= 1)
        
        // Clean up
        try await repo.delete(User.self, id: savedAlice.id)
        try await repo.delete(User.self, id: savedBob.id)
    }
    
    @Test("Transaction support")
    func testTransactionSupport() async throws {
        let spectro = try await TestDatabaseState.getSharedSpectro()
        let repo = spectro.repository()
        try await TestDatabase.setupTestDatabase(using: repo)
        
        // Test that transaction executes without error and returns a value
        let resultMessage = try await repo.transaction { transactionRepo in
            let user = User(name: "Transaction User", email: TestDatabase.uniqueEmail("tx"), age: 25)
            let savedUser = try await transactionRepo.insert(user)
            
            // Verify user was inserted within the transaction
            let foundUser = try await transactionRepo.get(User.self, id: savedUser.id)
            #expect(foundUser?.name == "Transaction User")
            
            // Clean up within transaction
            try await transactionRepo.delete(User.self, id: savedUser.id)
            
            return "Transaction completed successfully"
        }
        
        #expect(resultMessage == "Transaction completed successfully")
    }
    
    @Test("Database connection functionality")
    func testDatabaseConnection() async throws {
        let spectro = try await TestDatabaseState.getSharedSpectro()
        let version = try await spectro.testConnection()
        #expect(version.contains("PostgreSQL"))
    }
    
    @Test("Error handling - getOrFail")
    func testErrorHandling() async throws {
        let spectro = try await TestDatabaseState.getSharedSpectro()
        let repo = spectro.repository()
        try await TestDatabase.setupTestDatabase(using: repo)
        
        // Create and then delete a user
        let user = User(name: "Test User", email: TestDatabase.uniqueEmail("error"), age: 25)
        let savedUser = try await repo.insert(user)
        try await repo.delete(User.self, id: savedUser.id)
        
        // Test getOrFail with non-existing user should throw
        do {
            _ = try await repo.getOrFail(User.self, id: savedUser.id)
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected to throw
            #expect(Bool(true))
        }
    }
    
    @Test("SQL injection protection")
    func testSQLInjectionProtection() async throws {
        let spectro = try await TestDatabaseState.getSharedSpectro()
        let repo = spectro.repository()
        try await TestDatabase.setupTestDatabase(using: repo)
        
        // Insert a test user
        let user = User(name: "Test User", email: TestDatabase.uniqueEmail("injection"), age: 25)
        _ = try await repo.insert(user)
        
        // This should be safe due to parameterized queries
        let maliciousName = "'; DROP TABLE users; --"
        let results = try await repo.query(User.self)
            .where { $0.name == maliciousName }
            .all()
        
        // Should return empty results, not crash
        #expect(results.isEmpty)
        
        // Verify table still exists by querying all users
        let allUsers = try await repo.all(User.self)
        #expect(allUsers.count >= 1) // Our test user should still be there
    }
    
}
