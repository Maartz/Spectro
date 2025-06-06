import Foundation
import Testing
@testable import Spectro

@Suite("Preload and Eager Loading Tests")
struct PreloadFunctionalTests {
    
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
    
    @Test("Basic preload with has-many relationship")
    func testPreloadHasManyRelationship() async throws {
        let repo = try await setupDatabase()
        
        // Create user with multiple posts
        let user = User(name: "Alice", email: "alice@example.com", age: 30)
        let savedUser = try await repo.insert(user)
        
        var post1 = Post()
        post1.title = "First Post"
        post1.content = "Content 1"
        post1.userId = savedUser.id
        let savedPost1 = try await repo.insert(post1)
        
        var post2 = Post()
        post2.title = "Second Post"
        post2.content = "Content 2" 
        post2.userId = savedUser.id
        let savedPost2 = try await repo.insert(post2)
        
        // Test preload syntax (conceptual - would need implementation)
        let usersWithPosts = try await repo.query(User.self)
            .where { $0.id == savedUser.id }
            // .preload { $0.posts } // Future: preload posts relationship
            .all()
        
        #expect(usersWithPosts.count == 1)
        
        // For now, test manual loading of relationships
        let userPosts = try await repo.query(Post.self)
            .where { $0.userId == savedUser.id }
            .orderBy { $0.title }
            .all()
        
        #expect(userPosts.count == 2)
        #expect(userPosts[0].title == "First Post")
        #expect(userPosts[1].title == "Second Post")
        
        // Clean up
        try await repo.delete(Post.self, id: savedPost1.id)
        try await repo.delete(Post.self, id: savedPost2.id)
        try await repo.delete(User.self, id: savedUser.id)
    }
    
    @Test("Preload belongs-to relationship")
    func testPreloadBelongsToRelationship() async throws {
        let repo = try await setupDatabase()
        
        // Create user and post
        let user = User(name: "Bob", email: "bob@example.com", age: 25)
        let savedUser = try await repo.insert(user)
        
        var post = Post()
        post.title = "Bob's Post"
        post.content = "Great content by Bob"
        post.userId = savedUser.id
        let savedPost = try await repo.insert(post)
        
        // Test preload belongs-to relationship (conceptual)
        let postsWithAuthors = try await repo.query(Post.self)
            .where { $0.id == savedPost.id }
            // .preload { $0.author } // Future: preload user relationship
            .all()
        
        #expect(postsWithAuthors.count == 1)
        
        // For now, test manual loading
        let postAuthor = try await repo.get(User.self, id: savedPost.userId)
        #expect(postAuthor?.name == "Bob")
        
        // Clean up
        try await repo.delete(Post.self, id: savedPost.id)
        try await repo.delete(User.self, id: savedUser.id)
    }
    
    @Test("Nested preload relationships")
    func testNestedPreloadRelationships() async throws {
        let repo = try await setupDatabase()
        
        // Create complex relationship structure
        let user = User(name: "Charlie", email: "charlie@example.com", age: 35)
        let savedUser = try await repo.insert(user)
        
        var post = Post()
        post.title = "Charlie's Post"
        post.content = "Amazing content"
        post.userId = savedUser.id
        let savedPost = try await repo.insert(post)
        
        var comment = Comment()
        comment.content = "Great post, Charlie!"
        comment.approved = true
        comment.postId = savedPost.id
        comment.userId = savedUser.id
        let savedComment = try await repo.insert(comment)
        
        // Test nested preload (conceptual - would preload user -> posts -> comments)
        let usersWithPostsAndComments = try await repo.query(User.self)
            .where { $0.id == savedUser.id }
            // .preload { [$0.posts, $0.posts.comments] } // Future: nested preload
            .all()
        
        #expect(usersWithPostsAndComments.count == 1)
        
        // For now, test manual nested loading
        let userPosts = try await repo.query(Post.self)
            .where { $0.userId == savedUser.id }
            .all()
        
        #expect(userPosts.count == 1)
        
        let postComments = try await repo.query(Comment.self)
            .where { $0.postId == savedPost.id }
            .all()
        
        #expect(postComments.count == 1)
        #expect(postComments[0].content == "Great post, Charlie!")
        
        // Clean up
        try await repo.delete(Comment.self, id: savedComment.id)
        try await repo.delete(Post.self, id: savedPost.id)
        try await repo.delete(User.self, id: savedUser.id)
    }
    
    @Test("Preload with conditions and ordering")
    func testPreloadWithConditionsAndOrdering() async throws {
        let repo = try await setupDatabase()
        
        // Create user with published and draft posts
        let user = User(name: "Diana", email: "diana@example.com", age: 28)
        let savedUser = try await repo.insert(user)
        
        var publishedPost = Post()
        publishedPost.title = "Published Post"
        publishedPost.content = "This is published"
        publishedPost.published = true
        publishedPost.userId = savedUser.id
        let savedPublishedPost = try await repo.insert(publishedPost)
        
        var draftPost = Post()
        draftPost.title = "Draft Post"
        draftPost.content = "This is a draft"
        draftPost.published = false
        draftPost.userId = savedUser.id
        let savedDraftPost = try await repo.insert(draftPost)
        
        // Test preload with conditions (conceptual - only load published posts)
        let usersWithPublishedPosts = try await repo.query(User.self)
            .where { $0.id == savedUser.id }
            // .preload { $0.posts.where { $0.published == true } } // Future: conditional preload
            .all()
        
        #expect(usersWithPublishedPosts.count == 1)
        
        // For now, test manual conditional loading
        let publishedPosts = try await repo.query(Post.self)
            .where { $0.userId == savedUser.id && $0.published == true }
            .orderBy { $0.title }
            .all()
        
        #expect(publishedPosts.count == 1)
        #expect(publishedPosts[0].title == "Published Post")
        
        // Clean up
        try await repo.delete(Post.self, id: savedPublishedPost.id)
        try await repo.delete(Post.self, id: savedDraftPost.id)
        try await repo.delete(User.self, id: savedUser.id)
    }
    
    @Test("Prevent N+1 query problem with preload")
    func testPreventNPlusOneQueries() async throws {
        let repo = try await setupDatabase()
        
        // Create multiple users with posts
        let users = [
            User(name: "User 1", email: "user1@example.com", age: 25),
            User(name: "User 2", email: "user2@example.com", age: 30),
            User(name: "User 3", email: "user3@example.com", age: 35)
        ]
        
        var savedUsers: [User] = []
        var savedPosts: [Post] = []
        
        for user in users {
            let savedUser = try await repo.insert(user)
            savedUsers.append(savedUser)
            
            var post = Post()
            post.title = "\(user.name)'s Post"
            post.content = "Content by \(user.name)"
            post.userId = savedUser.id
            let savedPost = try await repo.insert(post)
            savedPosts.append(savedPost)
        }
        
        // Test efficient preload (conceptual - loads all users and their posts in minimal queries)
        let usersWithPosts = try await repo.query(User.self)
            .where { $0.age.between(20, and: 40) }
            // .preload { $0.posts } // Future: efficient preload prevents N+1
            .orderBy { $0.name }
            .all()
        
        #expect(usersWithPosts.count == 3)
        
        // For now, demonstrate the N+1 problem exists without preload
        let allUsers = try await repo.query(User.self)
            .where { $0.age.between(20, and: 40) }
            .orderBy { $0.name }
            .all()
        
        #expect(allUsers.count == 3)
        
        // This would cause N+1 queries without preload
        for user in allUsers {
            let userPosts = try await repo.query(Post.self)
                .where { $0.userId == user.id }
                .all()
            #expect(userPosts.count == 1)
        }
        
        // Clean up
        for post in savedPosts {
            try await repo.delete(Post.self, id: post.id)
        }
        for user in savedUsers {
            try await repo.delete(User.self, id: user.id)
        }
    }
}