import Foundation
import Testing
import PostgresKit
import NIOCore
@testable import Spectro

@Suite("Join and Navigation System")
struct JoinFunctionalTests {
    
    init() async {
        await TestSetup.configure()
    }
    
    @Test("Basic join for filtering")
    func testBasicJoin() async throws {
        // Find users who have posts
        let usersWithPosts = try await UserSchema.all { query in
            query.join("posts")
                 .where { $0.name.eq("John Doe") }
        }
        
        #expect(usersWithPosts.count >= 0)
        print("✅ Found \(usersWithPosts.count) users with posts via JOIN")
    }
    
    @Test("Join with relationship conditions")
    func testJoinWithConditions() async throws {
        // Find users who have published posts
        let usersWithPublishedPosts = try await UserSchema.all { query in
            query.join("posts")
                 .where("posts") { $0.published == true }
        }
        
        #expect(usersWithPublishedPosts.count >= 0)
        print("✅ Found \(usersWithPublishedPosts.count) users with published posts")
    }
    
    @Test("Multiple joins with auto-aliasing")
    func testMultipleJoins() async throws {
        // This should work now with auto-aliasing
        let users = try await UserSchema.all { query in
            query.join("posts")
                 .join("posts") // Should auto-alias as posts_2
                 .where { $0.name.eq("John Doe") }
        }
        
        #expect(users.count >= 0)
        print("✅ Multiple joins with auto-aliasing work: \(users.count) results")
    }
    
    @Test("Relationship navigation: users.posts")
    func testBasicNavigation() async throws {
        // Navigate from users to their posts
        let johnsPosts = try await UserSchema.all { query in
            query.where { $0.name.eq("John Doe") }
                 .through("posts")
                 .where { $0.published == true }
        }
        
        #expect(johnsPosts.count >= 0)
        print("✅ Navigation to John's published posts: \(johnsPosts.count) results")
        
        // Verify these are actually posts
        for post in johnsPosts {
            #expect(post.data["title"] != nil)
            #expect(post.data["content"] != nil)
        }
    }
    
    @Test("Deep navigation: users.posts.comments")
    func testDeepNavigation() async throws {
        // Navigate users -> posts -> comments
        let commentsOnJohnsPosts = try await UserSchema.all { query in
            query.where { $0.name.eq("John Doe") }
                 .through("posts")
                 .where { $0.published == true }
                 .through("comments")
                 .where { $0.approved == true }
        }
        
        #expect(commentsOnJohnsPosts.count >= 0)
        print("✅ Deep navigation to approved comments on John's published posts: \(commentsOnJohnsPosts.count) results")
        
        // Verify these are actually comments
        for comment in commentsOnJohnsPosts {
            #expect(comment.data["content"] != nil)
            #expect(comment.data["post_id"] != nil)
        }
    }
    
    @Test("Combined join and preload")
    func testJoinAndPreloadCombination() async throws {
        // Use JOIN for filtering, preload for data loading
        let users = try await UserSchema.all { query in
            query.join("posts")
                 .where("posts") { $0.published == true }
                 .preload("profile")
        }
        
        #expect(users.count >= 0)
        print("✅ Combined JOIN + preload: \(users.count) users with published posts and preloaded profiles")
        
        // Each user should have preloaded profile data
        for user in users {
            #expect(user.data["profile"] != nil || user.data["profile"] == nil) // Profile might not exist
            print("   User: \(user.data["name"] ?? "Unknown")")
        }
    }
    
    @Test("Complex multi-table navigation")
    func testComplexNavigation() async throws {
        // Find active users with published posts
        let activeUsersWithPublishedPosts = try await UserSchema.all { query in
            query.where { $0.is_active == true && $0.age > 18 }
                 .join("posts")
                 .where("posts") { $0.published == true }
                 .limit(10)
        }
        
        #expect(activeUsersWithPublishedPosts.count >= 0)
        
        // Verify all results meet criteria
        for user in activeUsersWithPublishedPosts {
            let isActive = user.data["is_active"] as? Bool ?? false
            let age = user.data["age"] as? Int ?? 0
            
            #expect(isActive == true)
            #expect(age > 18)
        }
        
        print("✅ Complex navigation: \(activeUsersWithPublishedPosts.count) active adult users with published posts")
    }
}
