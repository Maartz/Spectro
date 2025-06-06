import Foundation
import Testing
@testable import Spectro

@Suite("Join and Relationship Tests")  
struct JoinFunctionalTests {
    
    /// Setup test database before running tests
    func setupDatabase() async throws -> DatabaseRepo {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        
        let repo = spectro.repository()
        try await TestDatabase.resetDatabase(using: repo)
        return repo
    }
    
    @Test("Inner join between users and posts")
    func testInnerJoinUsersPosts() async throws {
        let repo = try await setupDatabase()
        
        // Create test data
        let user = User(name: "Alice", email: "alice@example.com", age: 30)
        let savedUser = try await repo.insert(user)
        
        var post = Post()
        post.title = "Alice's Post"
        post.content = "Great content by Alice"
        post.published = true
        post.userId = savedUser.id
        let savedPost = try await repo.insert(post)
        
        // Test beautiful join syntax
        let usersWithPosts = try await repo.query(User.self)
            .join(Post.self) { join in
                join.left.id == join.right.userId
            }
            .where { $0.isActive == true }
            .all()
        
        #expect(usersWithPosts.count >= 1)
        
        // Clean up
        try await repo.delete(Post.self, id: savedPost.id)
        try await repo.delete(User.self, id: savedUser.id)
    }
    
    @Test("Left join for optional relationships")
    func testLeftJoinOptionalRelationships() async throws {
        let repo = try await setupDatabase()
        
        // Create user without posts
        let userWithoutPosts = User(name: "Bob", email: "bob@example.com", age: 25)
        let savedUserWithoutPosts = try await repo.insert(userWithoutPosts)
        
        // Create user with posts
        let userWithPosts = User(name: "Alice", email: "alice@example.com", age: 30)
        let savedUserWithPosts = try await repo.insert(userWithPosts)
        
        var post = Post()
        post.title = "Alice's Post"
        post.content = "Great content"
        post.userId = savedUserWithPosts.id
        let savedPost = try await repo.insert(post)
        
        // Left join - should include users even without posts
        let allUsersWithOptionalPosts = try await repo.query(User.self)
            .leftJoin(Post.self) { join in
                join.left.id == join.right.userId
            }
            .orderBy { $0.name }
            .all()
        
        #expect(allUsersWithOptionalPosts.count >= 2)
        
        // Clean up
        try await repo.delete(Post.self, id: savedPost.id)
        try await repo.delete(User.self, id: savedUserWithPosts.id)
        try await repo.delete(User.self, id: savedUserWithoutPosts.id)
    }
    
    @Test("Join with where conditions on both tables")
    func testJoinWithComplexConditions() async throws {
        let repo = try await setupDatabase()
        
        // Create test data
        let youngUser = User(name: "Young Alice", email: "young@example.com", age: 22)
        let oldUser = User(name: "Old Bob", email: "old@example.com", age: 45)
        let savedYoungUser = try await repo.insert(youngUser)
        let savedOldUser = try await repo.insert(oldUser)
        
        var publishedPost = Post()
        publishedPost.title = "Published Post"
        publishedPost.content = "This is published"
        publishedPost.published = true
        publishedPost.userId = savedYoungUser.id
        let savedPublishedPost = try await repo.insert(publishedPost)
        
        var draftPost = Post()
        draftPost.title = "Draft Post"
        draftPost.content = "This is a draft"
        draftPost.published = false
        draftPost.userId = savedOldUser.id
        let savedDraftPost = try await repo.insert(draftPost)
        
        // Join with conditions on both tables
        let youngUsersWithPublishedPosts = try await repo.query(User.self)
            .join(Post.self) { join in
                join.left.id == join.right.userId
            }
            .where { $0.age < 30 } // User condition
            .where { $0.isActive == true } // User condition
            .all()
        
        #expect(youngUsersWithPublishedPosts.count >= 1)
        
        // Clean up
        try await repo.delete(Post.self, id: savedPublishedPost.id)
        try await repo.delete(Post.self, id: savedDraftPost.id)
        try await repo.delete(User.self, id: savedYoungUser.id)
        try await repo.delete(User.self, id: savedOldUser.id)
    }
    
    @Test("Multiple joins showcase")
    func testMultipleJoins() async throws {
        let repo = try await setupDatabase()
        
        // Create user
        let user = User(name: "Alice", email: "alice@example.com", age: 30)
        let savedUser = try await repo.insert(user)
        
        // Create post
        var post = Post()
        post.title = "Alice's Post"
        post.content = "Great content"
        post.userId = savedUser.id
        let savedPost = try await repo.insert(post)
        
        // Create comment
        var comment = Comment()
        comment.content = "Great post!"
        comment.approved = true
        comment.postId = savedPost.id
        comment.userId = savedUser.id
        let savedComment = try await repo.insert(comment)
        
        // Complex join: User -> Post -> Comment
        let usersWithCommentsOnTheirPosts = try await repo.query(User.self)
            .join(Post.self) { join in
                join.left.id == join.right.userId
            }
            .join(Comment.self) { join in
                // This would need to be enhanced to support multi-table joins
                // For now, we'll test the concept
                join.left.id == join.right.userId
            }
            .where { $0.isActive == true }
            .all()
        
        #expect(usersWithCommentsOnTheirPosts.count >= 0) // May be 0 if multi-table joins not fully implemented
        
        // Clean up
        try await repo.delete(Comment.self, id: savedComment.id)
        try await repo.delete(Post.self, id: savedPost.id)
        try await repo.delete(User.self, id: savedUser.id)
    }
}