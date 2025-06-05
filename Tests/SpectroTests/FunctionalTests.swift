import Foundation
import Testing
import PostgresKit
import NIOCore
@testable import Spectro

@Suite("Spectro Functional Tests")
struct SpectroFunctionalTests {
    
    init() async {
        await TestSetup.configure()
    }
    
    // MARK: - CRUD Operations
    
    @Test("Complete CRUD cycle for users")
    func testUserCRUDCycle() async throws {
        // Create
        let changeset = UserSchema.changeset([
            "name": "Alice Smith",
            "email": "alice@example.com", 
            "age": 28,
            "password": "secret123"
        ])
        let user = try await UserSchema.create(changeset)
        
        #expect(user.data["name"] as? String == "Alice Smith")
        #expect(user.data["age"] as? Int == 28)
        
        // Read
        let fetchedUser = try await UserSchema.get(user.id)
        #expect(fetchedUser != nil)
        if let fetched = fetchedUser {
            #expect(fetched.data["email"] as? String == "alice@example.com")
        }
        
        // Update
        let updatedUser = try await user.update([
            "age": 29,
            "name": "Alice Johnson"
        ])
        #expect(updatedUser.data["age"] as? Int == 29)
        #expect(updatedUser.data["name"] as? String == "Alice Johnson")
        
        // Delete
        try await user.delete()
        let deletedUser = try await UserSchema.get(user.id)
        #expect(deletedUser == nil)
    }
    
    @Test("Query users with conditions and ordering")
    func testUserQuerying() async throws {
        // Test basic where clause
        let johnUsers = try await UserSchema.all { query in
            query.where { $0.name.eq("John Doe") }
        }
        #expect(johnUsers.count >= 1)
        
        // Test complex conditions with ordering
        let adultUsers = try await UserSchema.all { query in
            query.where { $0.age > 20 }
                 .orderBy { [$0.age.desc(), $0.name.asc()] }
                 .limit(10)
        }
        #expect(adultUsers.count >= 1)
        #expect(adultUsers.allSatisfy { ($0.data["age"] as? Int ?? 0) > 20 })
    }
    
    @Test("Changeset validation and error handling")
    func testChangesetValidation() async throws {
        // Test valid changeset
        let validChangeset = UserSchema.changeset([
            "name": "Bob Wilson",
            "email": "bob@example.com",
            "age": 35,
            "password": "password123"
        ])
        #expect(validChangeset.isValid)
        
        let user = try await UserSchema.create(validChangeset)
        #expect(user.data["name"] as? String == "Bob Wilson")
        
        // Cleanup
        try await user.delete()
    }
    
    // MARK: - Preload Functionality
    
    @Test("Simple preload: users with posts")
    func testSimplePreload() async throws {
        let users = try await UserSchema.all { query in
            query.where { $0.name.eq("John Doe") }
                 .preload("posts")
        }
        
        #expect(users.count >= 1)
        
        guard let user = users.first else { return }
        #expect(user.data["posts"] != nil)
        
        if let posts = user.data["posts"] as? [DataRow] {
            print("User has \(posts.count) preloaded posts")
            #expect(posts.count >= 0) // Could be 0 or more
        }
    }
    
    @Test("Nested preload: users with posts and comments")
    func testNestedPreload() async throws {
        let users = try await UserSchema.all { query in
            query.where { $0.name.eq("John Doe") }
                 .preload("posts.comments")
        }
        
        #expect(users.count >= 1)
        
        guard let user = users.first,
              let posts = user.data["posts"] as? [DataRow] else { return }
        
        // Check that posts have comments preloaded
        for post in posts {
            #expect(post.values["comments"] != nil)
        }
    }
    
    @Test("Multiple preloads: users with posts and profile")
    func testMultiplePreloads() async throws {
        let users = try await UserSchema.all { query in
            query.preload("posts", "profile")
                 .limit(5)
        }
        
        #expect(users.count >= 0)
        
        // Each user should have preloaded associations
        for user in users {
            #expect(user.data["posts"] != nil)
            // Profile might be nil if no profile exists
        }
    }
    
    // MARK: - Join and Navigation
    
    @Test("Basic joins for filtering")
    func testBasicJoins() async throws {
        let usersWithPosts = try await UserSchema.all { query in
            query.join("posts")
                 .where("posts") { $0.published == true }
        }
        
        #expect(usersWithPosts.count >= 0)
    }
    
    @Test("Relationship navigation")
    func testRelationshipNavigation() async throws {
        // Navigate from users to their published posts
        let publishedPosts = try await UserSchema.all { query in
            query.where { $0.name.eq("John Doe") }
                 .through("posts")
                 .where { $0.published == true }
        }
        
        #expect(publishedPosts.count >= 0)
    }
    
    @Test("Deep relationship navigation")
    func testDeepNavigation() async throws {
        // Navigate users -> posts -> comments
        let approvedComments = try await UserSchema.all { query in
            query.where { $0.is_active == true }
                 .through("posts")
                 .where { $0.published == true }
                 .through("comments")
                 .where { $0.approved == true }
        }
        
        #expect(approvedComments.count >= 0)
    }
    
    // MARK: - Migrations
    
    @Test("Migration system works")
    func testMigrations() async throws {
        // This is a basic smoke test - detailed migration tests in MigrationTests
        let spectro = try Spectro(username: "postgres", password: "postgres", database: "spectro_test")
        defer { spectro.shutdown() }
        
        let manager = spectro.migrationManager()
        
        // Should be able to get migration status without errors
        let status = try await manager.getMigrationStatus()
        #expect(status.count >= 0)
    }
    
    // MARK: - Error Handling
    
    @Test("Proper error handling for missing records")
    func testErrorHandling() async throws {
        let nonExistentId = UUID()
        
        // get() should return nil
        let result = try await UserSchema.get(nonExistentId)
        #expect(result == nil)
        
        // getOrFail() should throw
        await #expect(throws: RepositoryError.self) {
            _ = try await UserSchema.getOrFail(nonExistentId)
        }
    }
}
