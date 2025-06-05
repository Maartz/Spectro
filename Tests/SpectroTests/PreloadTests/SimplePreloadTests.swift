import Foundation
import Testing
import PostgresKit
import NIOCore
@testable import Spectro

@Suite("Simple Preload Tests")
struct SimplePreloadTests {
    
    init() async {
        await TestSetup.configure()
    }
    
    @Test("Simple preload: users.posts (no nesting)")
    func testSimplePostsPreload() async throws {
        let query = UserSchema.query()
            .where { $0.name.eq("John Doe") }
            .preload("posts")
        
        let users = try await UserSchema.execute(query)
        
        #expect(users.count >= 1, "Should find John Doe")
        
        guard let user = users.first else {
            throw RepositoryError.notFound("John Doe not found")
        }
        
        print("User data keys: \(Array(user.data.keys))")
        
        // Check that posts are preloaded
        guard let posts = user.data["posts"] as? [DataRow] else {
            print("Posts data type: \(type(of: user.data["posts"]))")
            print("Posts data: \(user.data["posts"] ?? "nil")")
            throw RepositoryError.invalidData("Posts not preloaded correctly")
        }
        
        print("Found \(posts.count) posts for John Doe")
        #expect(posts.count >= 1, "John Doe should have posts")
        
        // Check post details
        for (index, post) in posts.enumerated() {
            let title = post.values["title"] as? String ?? "Unknown"
            let userId = post.values["user_id"] as? String ?? "No user_id"
            print("Post \(index + 1): \(title), user_id: \(userId)")
        }
    }
    
    @Test("Simple preload: posts.user (belongsTo)")
    func testSimpleBelongsToPreload() async throws {
        let query = PostSchema.query()
            .where { $0.published == true }
            .preload("user")
        
        let posts = try await PostSchema.execute(query)
        
        #expect(posts.count >= 1, "Should find published posts")
        
        for (index, post) in posts.enumerated() {
            let title = post.data["title"] as? String ?? "Unknown"
            print("Post \(index + 1): \(title)")
            
            if let user = post.data["user"] as? DataRow {
                let userName = user.values["name"] as? String ?? "Unknown"
                print("  User: \(userName)")
            } else {
                print("  User data type: \(type(of: post.data["user"]))")
                print("  User data: \(post.data["user"] ?? "nil")")
            }
        }
    }
}