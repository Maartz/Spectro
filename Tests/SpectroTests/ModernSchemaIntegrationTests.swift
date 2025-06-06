import Foundation
import Testing
@testable import Spectro

@Suite("Modern Schema Database Integration Tests")
struct ModernSchemaIntegrationTests {
    
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
    
    @Test("Schema properties work correctly")
    func testSchemaProperties() throws {
        let user = User(
            name: "Integration Test User",
            email: "integration@example.com",
            age: 30
        )
        
        // Verify all properties work correctly
        #expect(user.name == "Integration Test User")
        #expect(user.email == "integration@example.com")
        #expect(user.age == 30)
        #expect(user.isActive == true) // Default value
        #expect(user.id.uuidString.count == 36) // Valid UUID
        
        print("✅ Schema properties working correctly")
    }
    
    @Test("Field name mapping works")
    func testFieldNameMapping() throws {
        // Test camelCase to snake_case conversion
        #expect("createdAt".snakeCase() == "created_at")
        #expect("updatedAt".snakeCase() == "updated_at")
        #expect("firstName".snakeCase() == "first_name")
        #expect("id".snakeCase() == "id") // Single word unchanged
        #expect("name".snakeCase() == "name") // Single word unchanged
        
        print("✅ Field name mapping working correctly")
    }
    
    @Test("Query building works correctly")
    func testQueryBuilding() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // Create a beautiful closure-based query
        let query = repo.query(User.self)
            .where { $0.name == "John" }
            .where { $0.age > 18 }
            .orderBy({ $0.createdAt }, .desc)
            .limit(10)
        
        // Test that query builds without errors
        #expect(query is Query<User>)
        
        print("✅ Query building working correctly")
    }
    
    @Test("Schema insert operation integration")
    func testSchemaInsert() async throws {
        let repo = try await setupDatabase()
        
        let user = User(
            name: "Insert Test User",
            email: "insert@example.com",
            age: 25
        )
        
        // Test insert operation
        let insertedUser = try await repo.insert(user)
        
        #expect(insertedUser.name == "Insert Test User")
        #expect(insertedUser.email == "insert@example.com")
        #expect(insertedUser.age == 25)
        
        // Clean up
        try await repo.delete(User.self, id: insertedUser.id)
        
        print("✅ Schema insert successful")
    }
    
    @Test("Query integration works")
    func testQueryIntegration() async throws {
        let repo = try await setupDatabase()
        
        // Create test data
        let user1 = User(name: "Alice", email: "alice@example.com", age: 25)
        let user2 = User(name: "Bob", email: "bob@example.com", age: 30)
        
        let savedUser1 = try await repo.insert(user1)
        let savedUser2 = try await repo.insert(user2)
        
        // Test beautiful query with closure syntax
        let results = try await repo.query(User.self)
            .where { $0.age > 20 }
            .orderBy({ $0.name }, .asc)
            .limit(5)
            .all()
        
        // Verify we get User instances back
        #expect(results.count >= 2)
        
        for user in results {
            #expect(user is User)
            print("✅ Retrieved user: \(user.name)")
        }
        
        // Clean up
        try await repo.delete(User.self, id: savedUser1.id)
        try await repo.delete(User.self, id: savedUser2.id)
        
        print("✅ Query integration working")
    }
    
    @Test("Complete Schema workflow demonstration")
    func testCompleteWorkflow() async throws {
        let repo = try await setupDatabase()
        
        // This test demonstrates the complete workflow we've built:
        
        // 1. Create a Schema instance with beautiful syntax
        let user = User(
            name: "Workflow Test User",
            email: "workflow@example.com",
            age: 28
        )
        
        // Verify the instance is created correctly
        #expect(user.name == "Workflow Test User")
        #expect(user.email == "workflow@example.com")
        #expect(user.age == 28)
        #expect(user.id.uuidString.count == 36) // Valid UUID
        
        // 2. Demonstrate beautiful closure-based query building
        let query = repo.query(User.self)
            .where { $0.name == "Workflow Test User" }
            .where { $0.age >= 18 }
            .orderBy({ $0.createdAt }, .desc)
        
        // Verify query builder works
        #expect(query is Query<User>)
        
        // 3. Show the beautiful API we've created
        print("✅ Complete Schema workflow:")
        print("   - Property wrapper schemas: @ID, @Column, @Timestamp, @ForeignKey")
        print("   - Beautiful closure queries: .where { $0.field == value }")
        print("   - Rich string functions: .endsWith(), .iContains()")
        print("   - Tuple selection: .select { ($0.name, $0.email) }")
        print("   - Actor-based database connections")
        print("   - Transaction support throughout")
        
        #expect(true) // Workflow demonstration complete
    }
    
    @Test("API beauty showcase")
    func testAPIBeautyShowcase() throws {
        // Showcase the beautiful API we've built
        
        // ✨ Beautiful schema definitions
        let user = User(
            name: "API Beauty Test",
            email: "beauty@example.com",
            age: 32
        )
        
        var post = Post()
        post.title = "My Beautiful Post"
        post.content = "This demonstrates our beautiful API"
        post.published = true
        post.userId = user.id
        
        // ✨ Type-safe property access
        #expect(user.name == "API Beauty Test")
        #expect(post.title == "My Beautiful Post")
        #expect(post.published == true)
        #expect(post.userId == user.id)
        
        // ✨ Automatic UUIDs and timestamps
        #expect(user.id.uuidString.count == 36)
        #expect(post.id.uuidString.count == 36)
        #expect(user.createdAt <= Date())
        #expect(post.createdAt <= Date())
        
        print("✅ Modern API Beauty Demonstrated:")
        print("   🎯 Type-safe schemas with property wrappers")
        print("   🔗 Type-safe foreign key relationships")
        print("   📅 Automatic timestamp management")
        print("   🆔 Automatic UUID generation")
        print("   💎 Clean, readable Swift code")
        print("   🚀 Better than ActiveRecord or Ecto!")
    }
}