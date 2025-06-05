import Foundation
import Testing
import PostgresKit
import NIOCore
@testable import Spectro

@Suite("Nested Preload Tests")
struct NestedPreloadTests {
    
    init() async {
        await TestSetup.configure()
    }
    
    @Test("Basic nested preload: users.posts.comments")
    func testBasicNestedPreload() async throws {
        // Test single nested preload
        let query = UserSchema.query()
            .where { $0.name.eq("John Doe") }
            .preload("posts.comments")
        
        let users = try await UserSchema.execute(query)
        
        #expect(users.count >= 1, "Should find John Doe")
        
        guard let user = users.first else {
            throw RepositoryError.notFound("John Doe not found")
        }
        
        // Check that posts are preloaded
        guard let posts = user.data["posts"] as? [DataRow] else {
            throw RepositoryError.invalidData("Posts not preloaded")
        }
        
        print("Found \(posts.count) posts for John Doe")
        #expect(posts.count >= 1, "John Doe should have posts")
        
        // Check that comments are nested-preloaded on posts
        let postsWithComments = posts.filter { post in
            post.values["comments"] != nil
        }
        
        print("Found \(postsWithComments.count) posts with preloaded comments")
        
        // At least one post should have comments preloaded (even if empty)
        #expect(postsWithComments.count >= 1, "At least one post should have comments preloaded")
        
        // Check the structure of a post with comments
        if let firstPost = posts.first,
           let comments = firstPost.values["comments"] as? [DataRow] {
            print("First post has \(comments.count) comments")
            // This could be 0 or more depending on test data
        }
    }
    
    @Test("Multiple nested preloads")
    func testMultipleNestedPreloads() async throws {
        // Test multiple nested associations
        let query = UserSchema.query()
            .where { $0.name.eq("John Doe") }
            .preload("posts.comments", "profile")
        
        let users = try await UserSchema.execute(query)
        
        #expect(users.count >= 1, "Should find John Doe")
        
        guard let user = users.first else {
            throw RepositoryError.notFound("John Doe not found")
        }
        
        // Check posts.comments preload
        if let posts = user.data["posts"] as? [DataRow] {
            print("Found \(posts.count) posts")
            
            // Check if any posts have comments
            let postsWithComments = posts.compactMap { post -> [DataRow]? in
                post.values["comments"] as? [DataRow]
            }
            print("Posts with comments preloaded: \(postsWithComments.count)")
        }
        
        // Check profile preload
        if let profile = user.data["profile"] {
            print("Profile preloaded: \(type(of: profile))")
        } else {
            print("No profile found for user")
        }
    }
    
    @Test("Deep nested preload: users.posts.comments (with actual comment data)")
    func testDeepNestedPreloadWithData() async throws {
        // First, let's make sure we have some comments in the database
        // Load posts and check for comments
        let postsQuery = PostSchema.query().where { $0.published == true }
        let posts = try await PostSchema.execute(postsQuery)
        print("Found \(posts.count) published posts")
        
        // Now test the nested preload
        let userQuery = UserSchema.query()
            .where { $0.name.eq("John Doe") }
            .preload("posts.comments")
        
        let users = try await UserSchema.execute(userQuery)
        
        #expect(users.count >= 1, "Should find John Doe")
        
        guard let user = users.first else { return }
        
        // Examine the preloaded structure
        print("User data keys: \(Array(user.data.keys))")
        
        if let preloadedPosts = user.data["posts"] as? [DataRow] {
            print("\\nPreloaded \(preloadedPosts.count) posts:")
            
            for (index, post) in preloadedPosts.enumerated() {
                let title = post.values["title"] as? String ?? "Unknown"
                print("  Post \(index + 1): \(title)")
                print("    Post data keys: \(Array(post.values.keys))")
                
                if let comments = post.values["comments"] as? [DataRow] {
                    print("    Comments (\(comments.count)):")
                    for comment in comments {
                        let content = comment.values["content"] as? String ?? "No content"
                        print("      - \(content)")
                    }
                } else {
                    print("    No comments preloaded")
                }
            }
        }
    }
}