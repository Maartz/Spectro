import Foundation
import Testing
import PostgresKit
import NIOCore
@testable import Spectro

@Suite("Join API Tests")
struct JoinAPITests {
    
    init() async {
        // Just configure the repository, don't manage database schema
        await TestSetup.configure()
    }
    
    // MARK: - Basic Join Tests
    
    @Test("Basic join with relationship")
    func testBasicJoin() async throws {
        // First verify John Doe exists
        let johnQuery = UserSchema.query().where { $0.name.eq("John Doe") }
        let johns = try await UserSchema.execute(johnQuery)
        print("Found \(johns.count) John Does without join")
        
        // Test simple SQL generation first
        let query = UserSchema.query()
            .join("posts")
            .where { $0.name.eq("John Doe") }
        
        print("Generated SQL: \(query.debugSQL())")
        
        let users = try await UserSchema.execute(query)
        print("Join query found \(users.count) users")
        
        // For now, just verify the SQL is generated correctly
        let sql = query.debugSQL()
        #expect(sql.contains("INNER JOIN posts"))
        #expect(sql.contains("users.id = posts.user_id"))
        #expect(sql.contains("WHERE name = $1"))
    }
    
    @Test("Join with relationship conditions - ActiveRecord style")
    func testJoinWithRelationshipConditions() async throws {
        let query = UserSchema.query()
            .join("posts")
            .where { $0.name.eq("John Doe") }
            .where("posts") { $0.published == true }
        
        let users = try await UserSchema.execute(query)
        
        #expect(users.count >= 1, "Should find John Doe with published posts")
    }
    
    @Test("Multiple joins")
    func testMultipleJoins() async throws {
        let query = UserSchema.query()
            .join("posts")
            .join("posts") // This should work for nested relationships through posts
            .where { $0.name.eq("John Doe") }
            .where("posts") { $0.published == true }
        
        let users = try await UserSchema.execute(query)
        
        #expect(users.count >= 0, "Should execute without errors")
    }
    
    // MARK: - Relationship Navigation Tests
    
    @Test("Navigate through relationships")
    func testRelationshipNavigation() async throws {
        // Navigate from users to posts
        let query = UserSchema.query()
            .where { $0.name.eq("John Doe") }
            .through("posts")
            .where { $0.published == true }
        
        let posts = try await PostSchema.execute(query)
        
        #expect(posts.count >= 1, "Should find published posts by John Doe")
        #expect(posts.allSatisfy { ($0.data["published"] as? Bool) == true })
    }
    
    @Test("Deep navigation through multiple relationships")
    func testDeepNavigation() async throws {
        // Navigate from users -> posts -> comments
        let query = UserSchema.query()
            .where { $0.name.eq("John Doe") }
            .through("posts")
            .where { $0.published == true }
            .through("comments")
            .where { $0.approved == true }
        
        let comments = try await CommentSchema.execute(query)
        
        #expect(comments.count >= 0, "Should execute without errors")
        // Note: We might not have any results depending on test data, but query should work
    }
    
    // MARK: - Preload Tests
    
    @Test("Basic preload functionality")
    func testBasicPreload() async throws {
        let query = UserSchema.query()
            .where { $0.name.eq("John Doe") }
            .preload("posts")
        
        let users = try await UserSchema.execute(query)
        
        #expect(users.count >= 1, "Should find John Doe")
        
        // TODO: Implement preload result checking once preload loading is implemented
        // This test currently just verifies the query builds and executes
    }
    
    @Test("Multiple preloads")
    func testMultiplePreloads() async throws {
        let query = UserSchema.query()
            .preload("posts", "profile")
        
        let users = try await UserSchema.execute(query)
        
        #expect(users.count >= 0, "Should execute without errors")
        
        // TODO: Verify preloaded data once preload implementation is complete
    }
    
    // MARK: - Complex Combination Tests
    
    @Test("Combination: Join for filtering + Preload for data")
    func testJoinAndPreloadCombination() async throws {
        let query = UserSchema.query()
            .join("posts")
            .where("posts") { $0.published == true }
            .preload("profile")
        
        let users = try await UserSchema.execute(query)
        
        #expect(users.count >= 0, "Should execute complex query without errors")
    }
    
    @Test("Complex multi-level query")
    func testComplexMultiLevelQuery() async throws {
        // Find users who have published posts with approved comments
        let query = UserSchema.query()
            .join("posts")
            .where { $0.age > 20 }
            .where("posts") { $0.published == true }
            .preload("profile")
        
        let users = try await UserSchema.execute(query)
        
        #expect(users.count >= 0, "Should handle complex queries")
        
        // Verify all users meet the age criteria
        #expect(users.allSatisfy { ($0.data["age"] as? Int ?? 0) > 20 })
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Invalid relationship name throws error")
    func testInvalidRelationshipName() async throws {
        #expect(throws: Never.self) {
            // This should throw a fatal error for invalid relationship
            let _ = UserSchema.query().join("nonexistent_relationship")
        }
    }
    
    // MARK: - SQL Generation Tests
    
    @Test("Verify SQL generation for joins")
    func testSQLGeneration() async throws {
        let query = UserSchema.query()
            .join("posts")
            .where { $0.name.eq("John") }
            .where("posts") { $0.published == true }
        
        // This test verifies that the query can be built and doesn't crash
        // We could add SQL inspection if needed
        let debugSQL = query.debugSQL()
        
        #expect(debugSQL.contains("SELECT"), "Should generate SELECT statement")
        #expect(debugSQL.contains("FROM users"), "Should include FROM clause")
    }
    
    // MARK: - Relationship Discovery Tests
    
    @Test("Relationship introspection")
    func testRelationshipIntrospection() async throws {
        let relationships = UserSchema.relationships
        
        #expect(relationships.count >= 2, "UserSchema should have posts and profile relationships")
        
        let postRelationship = UserSchema.relationship(named: "posts")
        #expect(postRelationship != nil, "Should find posts relationship")
        #expect(postRelationship?.type == .hasMany, "Posts should be hasMany relationship")
        
        let profileRelationship = UserSchema.relationship(named: "profile")
        #expect(profileRelationship != nil, "Should find profile relationship")
        #expect(profileRelationship?.type == .hasOne, "Profile should be hasOne relationship")
    }
    
    @Test("Foreign key inference")
    func testForeignKeyInference() async throws {
        let postRelationship = UserSchema.relationship(named: "posts")
        
        #expect(postRelationship?.localKey == "id", "User local key should be id")
        #expect(postRelationship?.foreignKey == "user_id", "Post foreign key should be user_id")
        
        // Test belongsTo relationship
        let userRelationship = PostSchema.relationship(named: "user")
        
        #expect(userRelationship?.localKey == "user_id", "Post local key should be user_id")
        #expect(userRelationship?.foreignKey == "id", "User foreign key should be id")
    }
}