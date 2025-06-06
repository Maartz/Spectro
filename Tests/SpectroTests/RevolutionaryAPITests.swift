import Foundation
import Testing
@testable import Spectro

@Suite("Spectro API Tests")
struct APITests {
    
    @Test("Property wrapper schemas work correctly")
    func testPropertyWrapperSchemas() throws {
        // Test User schema with beautiful property wrapper syntax
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
    
    @Test("CRUD operations with new Schema system")
    func testCRUDOperations() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        try await TestDatabase.setupTestDatabase(using: repo)
        
        // Create with unique email
        let user = User(name: "John Doe", email: TestDatabase.uniqueEmail("john"), age: 30)
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
    
    @Test("Beautiful closure-based queries")
    func testClosureBasedQueries() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        try await TestDatabase.resetDatabase(using: repo)
        
        // Create test users with unique emails
        let alice = User(name: "Alice", email: TestDatabase.uniqueEmail("alice"), age: 25)
        let bob = User(name: "Bob", email: TestDatabase.uniqueEmail("bob"), age: 35)
        let charlie = User(name: "Charlie", email: TestDatabase.uniqueEmail("charlie"), age: 45)
        
        let savedAlice = try await repo.insert(alice)
        let savedBob = try await repo.insert(bob)
        let savedCharlie = try await repo.insert(charlie)
        
        // Beautiful closure-based where syntax
        let activeUsers = try await repo.query(User.self)
            .where { $0.age > 20 }
            .orderBy { $0.name }
            .all()
        
        #expect(activeUsers.count >= 3)
        
        // Complex conditions with beautiful && syntax
        let powerUsers = try await repo.query(User.self)
            .where { $0.age.between(25, and: 50) }
            .orderBy({ $0.age }, .desc)
            .all()
        
        #expect(powerUsers.count >= 2)
        
        // Clean up
        try await repo.delete(User.self, id: savedAlice.id)
        try await repo.delete(User.self, id: savedBob.id)
        try await repo.delete(User.self, id: savedCharlie.id)
    }
    
    @Test("Revolutionary tuple-based field selection")
    func testTupleFieldSelection() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        try await TestDatabase.resetDatabase(using: repo)
        
        // Create test users with unique emails
        let alice = User(name: "Alice Johnson", email: TestDatabase.uniqueEmail("alice"), age: 28)
        let bob = User(name: "Bob Smith", email: TestDatabase.uniqueEmail("bob"), age: 32)
        
        let savedAlice = try await repo.insert(alice)
        let savedBob = try await repo.insert(bob)
        
        // REVOLUTIONARY: Single field selection (unwrapped)
        let userNames = try await repo.query(User.self)
            .select { $0.name }
            .where { $0.age > 25 }
            .orderBy { $0.name }
            .all()
        
        #expect(userNames.count == 2)
        // Note: This will be [String] when tuple mapping is fully implemented
        
        // REVOLUTIONARY: Two field tuple selection
        let userProfiles = try await repo.query(User.self)
            .select { ($0.name, $0.email) }
            .where { $0.isActive == true }
            .orderBy { $0.name }
            .all()
        
        #expect(userProfiles.count == 2)
        // Note: This will be [(String, String)] when tuple mapping is fully implemented
        
        // REVOLUTIONARY: Three field tuple selection
        let userDetails = try await repo.query(User.self)
            .select { ($0.name, $0.email, $0.age) }
            .where { $0.age.between(25, and: 35) }
            .all()
        
        #expect(userDetails.count == 2)
        // Note: This will be [(String, String, Int)] when tuple mapping is fully implemented
        
        // Clean up
        try await repo.delete(User.self, id: savedAlice.id)
        try await repo.delete(User.self, id: savedBob.id)
    }
    
    @Test("Rich string and date functions")
    func testRichStringAndDateFunctions() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        try await TestDatabase.resetDatabase(using: repo)
        
        // Create test users with various data
        let admin = User(name: "Administrator", email: TestDatabase.uniqueEmail("admin"), age: 30)
        let john = User(name: "John Doe", email: TestDatabase.uniqueEmail("john"), age: 25)
        let jane = User(name: "Jane Smith", email: TestDatabase.uniqueEmail("jane"), age: 35)
        
        let savedAdmin = try await repo.insert(admin)
        let savedJohn = try await repo.insert(john)
        let savedJane = try await repo.insert(jane)
        
        // Test basic queries
        let allUsers = try await repo.query(User.self)
            .select { ($0.name, $0.email) }
            .all()
        
        #expect(allUsers.count == 3) // admin, john, and jane
        
        let adminUsers = try await repo.query(User.self)
            .where { $0.name.iContains("admin") } // Case-insensitive
            .select { $0.name }
            .all()
        
        #expect(adminUsers.count == 1)
        
        let youngUsers = try await repo.query(User.self)
            .where { $0.age < 30 }
            .select { $0.name }
            .all()
        
        #expect(youngUsers.count == 1)
        
        // Test date functions (conceptual - would need real implementation)
        let recentUsers = try await repo.query(User.self)
            .where { $0.createdAt.isToday() }
            .count()
        
        #expect(recentUsers >= 3) // All our test users were created today
        
        // Test null handling
        let activeUsers = try await repo.query(User.self)
            .where { $0.name.isNotNull() && $0.email.isNotNull() }
            .count()
        
        #expect(activeUsers >= 3)
        
        // Clean up
        try await repo.delete(User.self, id: savedAdmin.id)
        try await repo.delete(User.self, id: savedJohn.id)
        try await repo.delete(User.self, id: savedJane.id)
    }
    
    @Test("Beautiful join syntax")
    func testJoinSyntax() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        try await TestDatabase.resetDatabase(using: repo)
        
        // Create test data
        let user = User(name: "Alice", email: TestDatabase.uniqueEmail("alice"), age: 30)
        let savedUser = try await repo.insert(user)
        
        var post = Post()
        post.title = "My Amazing Post"
        post.content = "This is fantastic content!"
        post.published = true
        post.userId = savedUser.id
        
        let savedPost = try await repo.insert(post)
        
        // Beautiful join syntax
        let usersWithPosts = try await repo.query(User.self)
            .join(Post.self) { join in
                join.left.id == join.right.userId
            }
            .where { $0.isActive == true }
            .all()
        
        #expect(usersWithPosts.count >= 1)
        
        // Left join - all users, optionally with posts
        let allUsersWithOptionalPosts = try await repo.query(User.self)
            .leftJoin(Post.self) { join in
                join.left.id == join.right.userId
            }
            .all()
        
        #expect(allUsersWithOptionalPosts.count >= 1)
        
        // Clean up
        try await repo.delete(Post.self, id: savedPost.id)
        try await repo.delete(User.self, id: savedUser.id)
    }
    
    @Test("Transaction support")
    func testTransactionSupport() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        try await TestDatabase.resetDatabase(using: repo)
        
        // Test successful transaction
        let (savedUser, savedPost) = try await repo.transaction { transactionRepo in
            let user = User(name: "Transaction User", email: TestDatabase.uniqueEmail("tx"), age: 25)
            let savedUser = try await transactionRepo.insert(user)
            
            var post = Post()
            post.title = "Transaction Post"
            post.content = "Created in transaction"
            post.userId = savedUser.id
            let savedPost = try await transactionRepo.insert(post)
            
            return (savedUser, savedPost)
        }
        
        // Verify both records exist
        let foundUser = try await repo.get(User.self, id: savedUser.id)
        let foundPost = try await repo.get(Post.self, id: savedPost.id)
        
        #expect(foundUser?.name == "Transaction User")
        #expect(foundPost?.title == "Transaction Post")
        
        // Clean up
        try await repo.delete(Post.self, id: savedPost.id)
        try await repo.delete(User.self, id: savedUser.id)
    }
}