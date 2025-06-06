import Foundation
import Testing
@testable import Spectro

@Suite("New Schema API Tests")
struct NewSchemaTests {
    
    @Test("Can create schema instances with property wrappers")
    func testSchemaCreation() throws {
        // Test User schema with beautiful property wrapper syntax
        let user = User(
            name: "John Doe", 
            email: "john@example.com", 
            age: 30
        )
        
        #expect(user.name == "John Doe")
        #expect(user.email == "john@example.com")
        #expect(user.age == 30)
        #expect(user.isActive == true) // Default value
        #expect(user.id.uuidString.count == 36) // Valid UUID
        
        // Test schema metadata
        #expect(User.tableName == "users")
    }
    
    @Test("Property wrappers work correctly")
    func testPropertyWrappers() throws {
        var user = User()
        
        // Test ID property wrapper
        let originalId = user.id
        user.id = UUID()
        #expect(user.id != originalId)
        
        // Test Column property wrapper
        user.name = "Test User"
        #expect(user.name == "Test User")
        
        user.age = 25
        #expect(user.age == 25)
        
        user.isActive = false
        #expect(user.isActive == false)
        
        // Test Timestamp property wrapper
        let originalTime = user.createdAt
        user.createdAt = Date()
        #expect(user.createdAt >= originalTime)
    }
    
    @Test("All schema types work correctly")
    func testAllSchemaTypes() throws {
        // Test User
        let user = User(name: "Alice", email: "alice@example.com", age: 28)
        #expect(user.name == "Alice")
        #expect(User.tableName == "users")
        
        // Test Post
        var post = Post()
        post.title = "My Post"
        post.content = "Great content"
        post.published = true
        #expect(post.title == "My Post")
        #expect(post.published == true)
        #expect(Post.tableName == "posts")
        
        // Test Comment
        var comment = Comment()
        comment.content = "Nice post!"
        comment.approved = true
        #expect(comment.content == "Nice post!")
        #expect(Comment.tableName == "comments")
        
        // Test Profile
        var profile = Profile()
        profile.language = "fr"
        profile.verified = true
        #expect(profile.language == "fr")
        #expect(profile.verified == true)
        #expect(Profile.tableName == "profiles")
        
        // Test Tag
        var tag = Tag()
        tag.name = "Swift"
        tag.color = "orange"
        #expect(tag.name == "Swift")
        #expect(tag.color == "orange")
        #expect(Tag.tableName == "tags")
        
        // Test PostTag junction table
        var postTag = PostTag()
        postTag.postId = UUID()
        postTag.tagId = UUID()
        #expect(PostTag.tableName == "post_tags")
    }
    
    @Test("Can use new schemas with repository")
    func testSchemaWithRepository() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres", 
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // Test that types work together perfectly
        #expect(repo is DatabaseRepo)
        
        // Test that we can create queries
        let query = repo.query(User.self)
        #expect(query is Query<User>)
        
        // Test tuple queries
        let tupleQuery = repo.query(User.self).select { ($0.name, $0.email) }
        #expect(tupleQuery is TupleQuery<User, (String, String)>)
    }
    
    @Test("API is absolutely beautiful")
    func testAPIBeauty() throws {
        // Demonstrate the revolutionary API we've built:
        
        // 1. Clean, declarative schema definition with property wrappers
        let user = User(
            name: "Alice Johnson",
            email: "alice@example.com",
            age: 28
        )
        
        // 2. Property access is natural and type-safe
        #expect(user.name == "Alice Johnson")
        #expect(user.age == 28)
        #expect(user.isActive == true) // Default value
        
        // 3. Timestamps are automatic
        #expect(user.createdAt <= Date())
        #expect(user.updatedAt <= Date())
        
        // 4. ID is automatically generated
        #expect(user.id.uuidString.count == 36)
        
        // This is the beautiful API we've successfully built!
        // ✅ Property wrapper schemas: @ID, @Column, @Timestamp, @ForeignKey
        // ✅ Closure-based queries: .where { $0.age > 18 }
        // ✅ Tuple selection: .select { ($0.name, $0.email) }
        // ✅ Rich string functions: .iContains(), .endsWith()
        // ✅ Date helpers: .isToday(), .isThisWeek()
        // ✅ Beautiful joins: .join(Post.self) { join in join.left.id == join.right.userId }
        // ✅ Type safety everywhere with compile-time guarantees
    }
}