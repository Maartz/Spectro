import Foundation

// MARK: - Example Schema Definitions

/// User schema demonstrating property wrapper syntax and relationship definitions.
///
/// This example shows how to define a complete schema with all property wrapper types
/// and demonstrates the implicit lazy relationship pattern that Spectro uses.
///
/// ## Features Demonstrated
///
/// - **Property Wrappers**: Using `@ID`, `@Column`, and `@Timestamp` for field definitions
/// - **SchemaBuilder**: Implementing the builder pattern for efficient row mapping
/// - **Relationships**: While not shown here (due to Swift recursive type limitations),
///   relationships would be defined using `@HasMany`, `@HasOne`, and `@BelongsTo`
///
/// ## Usage Examples
///
/// ```swift
/// // Create a new user
/// var user = User(name: "John Doe", email: "john@example.com", age: 30)
/// user = try await repo.insert(user)
///
/// // Query users
/// let activeUsers = try await repo.query(User.self)
///     .where { $0.isActive == true }
///     .orderBy { $0.createdAt }
///     .all()
///
/// // Load relationships (if defined)
/// let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
/// ```
public struct User: Schema, SchemaBuilder {
    public static let tableName = "users"
    
    @ID public var id: UUID
    @Column public var name: String = ""
    @Column public var email: String = ""
    @Column public var age: Int = 0
    @Column public var isActive: Bool = true
    @Timestamp public var createdAt: Date = Date()
    @Timestamp public var updatedAt: Date = Date()
    
    public init() {}
    
    public init(name: String, email: String, age: Int) {
        self.name = name
        self.email = email
        self.age = age
    }
    
    // MARK: - SchemaBuilder Implementation
    
    public static func build(from values: [String: Any]) -> User {
        var user = User()
        
        if let id = values["id"] as? UUID {
            user.id = id
        }
        if let name = values["name"] as? String {
            user.name = name
        }
        if let email = values["email"] as? String {
            user.email = email
        }
        if let age = values["age"] as? Int {
            user.age = age
        }
        if let isActive = values["isActive"] as? Bool {
            user.isActive = isActive
        }
        if let createdAt = values["createdAt"] as? Date {
            user.createdAt = createdAt
        }
        if let updatedAt = values["updatedAt"] as? Date {
            user.updatedAt = updatedAt
        }
        
        return user
    }
}

/// Post schema demonstrating relationships
public struct Post: Schema, SchemaBuilder {
    public static let tableName = "posts"
    
    @ID public var id: UUID
    @Column public var title: String = ""
    @Column public var content: String = ""
    @Column public var published: Bool = false
    @ForeignKey public var userId: UUID = UUID()
    @Timestamp public var createdAt: Date = Date()
    @Timestamp public var updatedAt: Date = Date()
    
    public init() {}
    
    // MARK: - SchemaBuilder Implementation
    
    public static func build(from values: [String: Any]) -> Post {
        var post = Post()
        
        if let id = values["id"] as? UUID {
            post.id = id
        }
        if let title = values["title"] as? String {
            post.title = title
        }
        if let content = values["content"] as? String {
            post.content = content
        }
        if let published = values["published"] as? Bool {
            post.published = published
        }
        if let userId = values["userId"] as? UUID {
            post.userId = userId
        }
        if let createdAt = values["createdAt"] as? Date {
            post.createdAt = createdAt
        }
        if let updatedAt = values["updatedAt"] as? Date {
            post.updatedAt = updatedAt
        }
        
        return post
    }
}

/// Comment schema
public struct Comment: Schema, SchemaBuilder {
    public static let tableName = "comments"
    
    @ID public var id: UUID
    @Column public var content: String = ""
    @Column public var approved: Bool = false
    @ForeignKey public var postId: UUID = UUID()
    @ForeignKey public var userId: UUID = UUID()
    @Timestamp public var createdAt: Date = Date()
    
    public init() {}
    
    // MARK: - SchemaBuilder Implementation
    
    public static func build(from values: [String: Any]) -> Comment {
        var comment = Comment()
        
        if let id = values["id"] as? UUID {
            comment.id = id
        }
        if let content = values["content"] as? String {
            comment.content = content
        }
        if let approved = values["approved"] as? Bool {
            comment.approved = approved
        }
        if let postId = values["postId"] as? UUID {
            comment.postId = postId
        }
        if let userId = values["userId"] as? UUID {
            comment.userId = userId
        }
        if let createdAt = values["createdAt"] as? Date {
            comment.createdAt = createdAt
        }
        
        return comment
    }
}

/// Profile schema
public struct Profile: Schema, SchemaBuilder {
    public static let tableName = "profiles"
    
    @ID public var id: UUID
    @Column public var language: String = "en"
    @Column public var optInEmail: Bool = false
    @Column public var verified: Bool = false
    @ForeignKey public var userId: UUID = UUID()
    @Timestamp public var createdAt: Date = Date()
    
    public init() {}
    
    // MARK: - SchemaBuilder Implementation
    
    public static func build(from values: [String: Any]) -> Profile {
        var profile = Profile()
        
        if let id = values["id"] as? UUID {
            profile.id = id
        }
        if let language = values["language"] as? String {
            profile.language = language
        }
        if let optInEmail = values["optInEmail"] as? Bool {
            profile.optInEmail = optInEmail
        }
        if let verified = values["verified"] as? Bool {
            profile.verified = verified
        }
        if let userId = values["userId"] as? UUID {
            profile.userId = userId
        }
        if let createdAt = values["createdAt"] as? Date {
            profile.createdAt = createdAt
        }
        
        return profile
    }
}

/// Tag schema for many-to-many relationship
public struct Tag: Schema, SchemaBuilder {
    public static let tableName = "tags"
    
    @ID public var id: UUID
    @Column public var name: String = ""
    @Column public var color: String = ""
    @Timestamp public var createdAt: Date = Date()
    
    public init() {}
    
    // MARK: - SchemaBuilder Implementation
    
    public static func build(from values: [String: Any]) -> Tag {
        var tag = Tag()
        
        if let id = values["id"] as? UUID {
            tag.id = id
        }
        if let name = values["name"] as? String {
            tag.name = name
        }
        if let color = values["color"] as? String {
            tag.color = color
        }
        if let createdAt = values["createdAt"] as? Date {
            tag.createdAt = createdAt
        }
        
        return tag
    }
}

/// PostTag junction table for many-to-many
public struct PostTag: Schema, SchemaBuilder {
    public static let tableName = "post_tags"
    
    @ID public var id: UUID
    @ForeignKey public var postId: UUID = UUID()
    @ForeignKey public var tagId: UUID = UUID()
    @Timestamp public var createdAt: Date = Date()
    
    public init() {}
    
    // MARK: - SchemaBuilder Implementation
    
    public static func build(from values: [String: Any]) -> PostTag {
        var postTag = PostTag()
        
        if let id = values["id"] as? UUID {
            postTag.id = id
        }
        if let postId = values["postId"] as? UUID {
            postTag.postId = postId
        }
        if let tagId = values["tagId"] as? UUID {
            postTag.tagId = tagId
        }
        if let createdAt = values["createdAt"] as? Date {
            postTag.createdAt = createdAt
        }
        
        return postTag
    }
}

// MARK: - Implement FieldNameProvider for optimized KeyPath resolution

extension User: FieldNameProvider {
    public static var fieldNames: [String: String] {
        [
            "\\User.id": "id",
            "\\User.name": "name",
            "\\User.email": "email",
            "\\User.age": "age",
            "\\User.isActive": "isActive",
            "\\User.createdAt": "createdAt",
            "\\User.updatedAt": "updatedAt"
        ]
    }
}

extension Post: FieldNameProvider {
    public static var fieldNames: [String: String] {
        [
            "\\Post.id": "id",
            "\\Post.title": "title",
            "\\Post.content": "content",
            "\\Post.published": "published",
            "\\Post.userId": "userId",
            "\\Post.createdAt": "createdAt",
            "\\Post.updatedAt": "updatedAt"
        ]
    }
}