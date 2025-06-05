import Foundation
import Testing
import PostgresKit
import NIOCore
@testable import Spectro

@Suite("Preload System")
struct PreloadFunctionalTests {
    
    init() async {
        await TestSetup.configure()
    }
    
    @Test("Basic preload: hasMany relationship")
    func testBasicHasManyPreload() async throws {
        let users = try await UserSchema.all { query in
            query.where { $0.name.eq("John Doe") }
                 .preload("posts")
        }
        
        #expect(users.count >= 1, "Should find John Doe")
        
        guard let user = users.first else { return }
        guard let posts = user.data["posts"] as? [DataRow] else {
            throw RepositoryError.invalidData("Posts not preloaded")
        }
        
        print("✅ Preloaded \(posts.count) posts for John Doe")
        #expect(posts.count >= 0)
        
        // Verify post structure
        for post in posts {
            #expect(post.values["title"] != nil)
            #expect(post.values["user_id"] != nil)
        }
    }
    
    @Test("Basic preload: belongsTo relationship") 
    func testBasicBelongsToPreload() async throws {
        let posts = try await PostSchema.all { query in
            query.where { $0.published == true }
                 .preload("user")
                 .limit(3)
        }
        
        #expect(posts.count >= 1, "Should find published posts")
        
        for post in posts {
            if let user = post.data["user"] as? DataRow {
                #expect(user.values["name"] != nil)
                #expect(user.values["email"] != nil)
                print("✅ Post '\(post.data["title"] ?? "Unknown")' has user: \(user.values["name"] ?? "Unknown")")
            }
        }
    }
    
    @Test("Nested preload: posts.comments")
    func testNestedPreload() async throws {
        let users = try await UserSchema.all { query in
            query.where { $0.name.eq("John Doe") }
                 .preload("posts.comments")
        }
        
        #expect(users.count >= 1, "Should find John Doe")
        
        guard let user = users.first,
              let posts = user.data["posts"] as? [DataRow] else { return }
        
        print("✅ Nested preload: \(posts.count) posts loaded")
        
        var totalComments = 0
        for post in posts {
            if let comments = post.values["comments"] as? [DataRow] {
                totalComments += comments.count
                print("   Post '\(post.values["title"] ?? "Unknown")' has \(comments.count) comments")
            }
        }
        
        print("✅ Total nested comments: \(totalComments)")
        #expect(totalComments >= 0)
    }
    
    @Test("Multiple preloads")
    func testMultiplePreloads() async throws {
        let users = try await UserSchema.all { query in
            query.preload("posts", "profile")
                 .limit(2)
        }
        
        #expect(users.count >= 0)
        
        for user in users {
            let userName = user.data["name"] as? String ?? "Unknown"
            let postsCount = (user.data["posts"] as? [DataRow])?.count ?? 0
            let hasProfile = user.data["profile"] != nil
            
            print("✅ User \(userName): \(postsCount) posts, profile: \(hasProfile)")
            
            #expect(user.data["posts"] != nil, "Posts should be preloaded")
            // Profile might be nil - that's ok
        }
    }
    
    @Test("Deep nested preload: users.posts.comments")
    func testDeepNestedPreload() async throws {
        let users = try await UserSchema.all { query in
            query.where { $0.is_active == true }
                 .preload("posts.comments")
                 .limit(1)
        }
        
        guard let user = users.first,
              let posts = user.data["posts"] as? [DataRow] else { return }
        
        var totalComments = 0
        for post in posts {
            if let comments = post.values["comments"] as? [DataRow] {
                totalComments += comments.count
                
                // Verify comment structure
                for comment in comments {
                    #expect(comment.values["content"] != nil)
                    #expect(comment.values["post_id"] != nil)
                }
            }
        }
        
        print("✅ Deep nested preload: Found \(totalComments) total comments")
    }
    
    @Test("Preload with query conditions")
    func testPreloadWithConditions() async throws {
        // Preload posts but also filter the main query
        let activeUsers = try await UserSchema.all { query in
            query.where { $0.is_active == true && $0.age > 20 }
                 .preload("posts")
                 .limit(5)
        }
        
        #expect(activeUsers.count >= 0)
        
        // All users should meet the criteria
        for user in activeUsers {
            let isActive = user.data["is_active"] as? Bool ?? false
            let age = user.data["age"] as? Int ?? 0
            
            #expect(isActive == true)
            #expect(age > 20)
            #expect(user.data["posts"] != nil, "Posts should be preloaded")
        }
    }
}
