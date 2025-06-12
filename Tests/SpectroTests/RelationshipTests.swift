import Testing
import Foundation
@testable import Spectro

@Suite("Relationship Loading Tests")
struct RelationshipTests {
    
    @Test("Can load HasMany relationships")
    func testHasManyRelationshipLoading() async throws {
        let spectro = try TestSetup.getSpectro()
        
        let repo = spectro.repository()
        
        // Create a user
        var user = User(name: "John Doe", email: "john-hasmany-\(UUID().uuidString)@example.com", age: 30)
        user = try await repo.insert(user)
        
        // Create posts for the user (user.id is now set correctly from DB)
        var post1 = Post()
        post1.title = "First Post"
        post1.content = "Content of first post"
        post1.userId = user.id  // Use the DB-assigned UUID
        post1 = try await repo.insert(post1)
        
        var post2 = Post()
        post2.title = "Second Post" 
        post2.content = "Content of second post"
        post2.userId = user.id  // Use the DB-assigned UUID
        post2 = try await repo.insert(post2)
        
        // Load posts for the user using relationship loader
        let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
        
        #expect(posts.count == 2)
        #expect(posts.contains { $0.title == "First Post" })
        #expect(posts.contains { $0.title == "Second Post" })
    }
    
    @Test("Can load HasOne relationships")
    func testHasOneRelationshipLoading() async throws {
        let spectro = try TestSetup.getSpectro()
        
        let repo = spectro.repository()
        
        // Create a user
        var user = User(name: "Jane Smith", email: "jane-hasone-\(UUID().uuidString)@example.com", age: 25)
        user = try await repo.insert(user)
        
        // Create a profile for the user (user.id is now set correctly from DB)
        var profile = Profile()
        profile.language = "es"
        profile.optInEmail = true
        profile.verified = true
        profile.userId = user.id  // Use the DB-assigned UUID
        profile = try await repo.insert(profile)
        
        // Load profile for the user using relationship loader
        let loadedProfile = try await user.loadHasOne(Profile.self, foreignKey: "userId", using: repo)
        
        #expect(loadedProfile != nil)
        #expect(loadedProfile?.language == "es")
        #expect(loadedProfile?.optInEmail == true)
        #expect(loadedProfile?.verified == true)
    }
    
    @Test("Can load BelongsTo relationships")
    func testBelongsToRelationshipLoading() async throws {
        let spectro = try TestSetup.getSpectro()
        
        let repo = spectro.repository()
        
        // Create a user
        var user = User(name: "Bob Wilson", email: "bob-belongsto-\(UUID().uuidString)@example.com", age: 35)
        user = try await repo.insert(user)
        
        // Create a post belonging to the user (user.id is now set correctly from DB)
        var post = Post()
        post.title = "Bob's Post"
        post.content = "This is Bob's first post"
        post.userId = user.id  // Use the DB-assigned UUID
        post = try await repo.insert(post)
        
        // Load user for the post using relationship loader
        let loadedUser = try await post.loadBelongsTo(User.self, foreignKey: "userId", using: repo)
        
        #expect(loadedUser != nil)
        #expect(loadedUser?.name == "Bob Wilson")
        #expect(loadedUser?.email == user.email)  // Compare with actual user email
        #expect(loadedUser?.age == 35)
    }
    
    @Test("HasMany returns empty array when no related records")
    func testHasManyWithNoRelatedRecords() async throws {
        let spectro = try TestSetup.getSpectro()
        
        let repo = spectro.repository()
        
        // Create a user with no posts
        var user = User(name: "Alice Brown", email: "alice-empty-\(UUID().uuidString)@example.com", age: 28)
        user = try await repo.insert(user)
        
        // Load posts for the user (should be empty)
        let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
        
        #expect(posts.isEmpty)
    }
    
    @Test("HasOne returns nil when no related record")
    func testHasOneWithNoRelatedRecord() async throws {
        let spectro = try TestSetup.getSpectro()
        
        let repo = spectro.repository()
        
        // Create a user with no profile
        var user = User(name: "Charlie Davis", email: "charlie-nil-\(UUID().uuidString)@example.com", age: 32)
        user = try await repo.insert(user)
        
        // Load profile for the user (should be nil)
        let profile = try await user.loadHasOne(Profile.self, foreignKey: "userId", using: repo)
        
        #expect(profile == nil)
    }
    
    @Test("BelongsTo returns nil when foreign key is invalid")
    func testBelongsToWithInvalidForeignKey() async throws {
        let spectro = try TestSetup.getSpectro()
        
        let repo = spectro.repository()
        
        // Create a user first, then create a post, then change the post's userId to invalid
        var user = User(name: "Test User", email: "test-invalid-\(UUID().uuidString)@example.com", age: 30)
        user = try await repo.insert(user)
        
        var post = Post()
        post.title = "Test Post"
        post.content = "Test content"
        post.userId = user.id  // Use the DB-assigned UUID
        post = try await repo.insert(post)
        
        // Now change to an invalid userId (this simulates an orphaned foreign key)
        post.userId = UUID()
        
        // Load user for the post (should be nil since the userId is now invalid)
        let loadedUser = try await post.loadBelongsTo(User.self, foreignKey: "userId", using: repo)
        
        #expect(loadedUser == nil)
    }
    
    @Test("Can load multiple relationship types for same entity")
    func testMultipleRelationshipTypes() async throws {
        let spectro = try TestSetup.getSpectro()
        
        let repo = spectro.repository()
        
        // Create a user
        var user = User(name: "David Lee", email: "david-multiple-\(UUID().uuidString)@example.com", age: 40)
        user = try await repo.insert(user)
        
        // Create posts for the user (user.id is now set correctly from DB)
        var post1 = Post()
        post1.title = "Post 1"
        post1.content = "First post content"
        post1.userId = user.id  // Use the DB-assigned UUID
        post1 = try await repo.insert(post1)
        
        var post2 = Post()
        post2.title = "Post 2"
        post2.content = "Second post content"
        post2.userId = user.id  // Use the DB-assigned UUID
        post2 = try await repo.insert(post2)
        
        // Create a profile for the user (user.id is now set correctly from DB)
        var profile = Profile()
        profile.language = "fr"
        profile.optInEmail = false
        profile.verified = false
        profile.userId = user.id  // Use the DB-assigned UUID
        profile = try await repo.insert(profile)
        
        // Load both relationships
        let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
        let loadedProfile = try await user.loadHasOne(Profile.self, foreignKey: "userId", using: repo)
        
        // Verify posts
        #expect(posts.count == 2)
        #expect(posts.contains { $0.title == "Post 1" })
        #expect(posts.contains { $0.title == "Post 2" })
        
        // Verify profile
        #expect(loadedProfile != nil)
        #expect(loadedProfile?.language == "fr")
        #expect(loadedProfile?.optInEmail == false)
    }
}