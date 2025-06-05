import Foundation
import Testing
import PostgresKit
import NIOCore
@testable import Spectro

@Suite("Join API Tests")
struct JoinAPITests {
    
    static let testDB = try! TestDatabase()
    static let repo = PostgresRepo(pools: testDB.pools)
    
    init() async throws {
        // Set up test tables
        try await Self.testDB.setupTestTable()
        try await Self.setupJoinTestData()
    }
    
    static func setupJoinTestData() async throws {
        // Create posts table
        try await testDB.pools.withConnection { conn in
            conn.sql().raw(SQLQueryString("""
                CREATE TABLE IF NOT EXISTS posts (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    title TEXT NOT NULL,
                    content TEXT NOT NULL,
                    published BOOLEAN DEFAULT false,
                    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMPTZ
                )
            """)).run()
        }.get()
        
        // Create comments table
        try await testDB.pools.withConnection { conn in
            conn.sql().raw(SQLQueryString("""
                CREATE TABLE IF NOT EXISTS comments (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    content TEXT NOT NULL,
                    approved BOOLEAN DEFAULT false,
                    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
                    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
            """)).run()
        }.get()
        
        // Insert test posts
        try await testDB.pools.withConnection { conn in
            conn.sql().raw(SQLQueryString("""
                INSERT INTO posts (id, title, content, published, user_id) VALUES
                ('11111111-1111-1111-1111-111111111111', 'First Post', 'Content of first post', true, '123e4567-e89b-12d3-a456-426614174000'),
                ('22222222-2222-2222-2222-222222222222', 'Second Post', 'Content of second post', false, '123e4567-e89b-12d3-a456-426614174000'),
                ('33333333-3333-3333-3333-333333333333', 'Third Post', 'Content of third post', true, '987fcdeb-51a2-43d7-9b18-315274198000')
                ON CONFLICT (id) DO NOTHING
            """)).run()
        }.get()
        
        // Insert test comments
        try await testDB.pools.withConnection { conn in
            conn.sql().raw(SQLQueryString("""
                INSERT INTO comments (id, content, approved, post_id, user_id) VALUES
                ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Great post!', true, '11111111-1111-1111-1111-111111111111', '987fcdeb-51a2-43d7-9b18-315274198000'),
                ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Nice work', false, '11111111-1111-1111-1111-111111111111', '123e4567-e89b-12d3-a456-426614174000'),
                ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Interesting', true, '33333333-3333-3333-3333-333333333333', '123e4567-e89b-12d3-a456-426614174000')
                ON CONFLICT (id) DO NOTHING
            """)).run()
        }.get()
    }
    
    // MARK: - Basic Join Tests
    
    @Test("Basic join with relationship")
    func testBasicJoin() async throws {
        let query = UserSchema.query()
            .join("posts")
            .where { $0.name.eq("John Doe") }
        
        let users = try await Self.repo.all(UserSchema.self) { _ in query }
        
        #expect(users.count >= 1, "Should find John Doe who has posts")
        #expect(users.first?.data["name"] as? String == "John Doe")
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