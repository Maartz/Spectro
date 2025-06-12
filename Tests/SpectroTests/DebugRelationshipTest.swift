import Testing
import Foundation
@testable import Spectro

@Suite("Debug Relationship Loading")
struct DebugRelationshipTest {
    
    @Test("Debug HasMany relationship loading step by step")
    func debugHasManyRelationshipLoading() async throws {
        let spectro = try TestSetup.getSpectro()
        let repo = spectro.repository()
        
        // Create a user
        var user = User(name: "Debug User", email: "debug-\(UUID().uuidString)@example.com", age: 30)
        user = try await repo.insert(user)
        print("✅ Created user with ID: \(user.id)")
        
        // Create posts for the user (user.id is now set correctly from DB)
        var post1 = Post()
        post1.title = "Debug Post 1"
        post1.content = "Debug content 1"
        post1.userId = user.id  // Use the DB-assigned UUID
        post1 = try await repo.insert(post1)
        print("✅ Created post1 with title: '\(post1.title)', userId: \(post1.userId)")
        
        var post2 = Post()
        post2.title = "Debug Post 2"
        post2.content = "Debug content 2"  
        post2.userId = user.id  // Use the DB-assigned UUID
        post2 = try await repo.insert(post2)
        print("✅ Created post2 with title: '\(post2.title)', userId: \(post2.userId)")
        
        // Verify posts were created correctly
        let allPosts = try await repo.all(Post.self)
        print("📊 Total posts in database: \(allPosts.count)")
        for post in allPosts {
            print("  - Post: '\(post.title)' (userId: \(post.userId))")
        }
        
        // Try to load posts for the user
        print("🔍 Loading posts for user \(user.id)...")
        let loadedPosts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
        print("📝 Loaded \(loadedPosts.count) posts")
        for post in loadedPosts {
            print("  - Loaded post: '\(post.title)' (userId: \(post.userId))")
        }
        
        // Check what we expect
        print("🎯 Expected titles: ['Debug Post 1', 'Debug Post 2']")
        print("🎯 Actual titles: \(loadedPosts.map { $0.title })")
        
        #expect(loadedPosts.count == 2)
        #expect(loadedPosts.contains { $0.title == "Debug Post 1" })
        #expect(loadedPosts.contains { $0.title == "Debug Post 2" })
    }
}