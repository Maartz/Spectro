import Foundation

// MARK: - Example Schema Definitions

/// User schema with property wrapper syntax
public struct User: Schema {
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
}

/// Post schema demonstrating relationships
public struct Post: Schema {
    public static let tableName = "posts"
    
    @ID public var id: UUID
    @Column public var title: String = ""
    @Column public var content: String = ""
    @Column public var published: Bool = false
    @Column public var userId: UUID = UUID()
    @Timestamp public var createdAt: Date = Date()
    @Timestamp public var updatedAt: Date = Date()
    
    public init() {}
}

/// Comment schema
public struct Comment: Schema {
    public static let tableName = "comments"
    
    @ID public var id: UUID
    @Column public var content: String = ""
    @Column public var approved: Bool = false
    @Column public var postId: UUID = UUID()
    @Column public var userId: UUID = UUID()
    @Timestamp public var createdAt: Date = Date()
    
    public init() {}
}

/// Profile schema
public struct Profile: Schema {
    public static let tableName = "profiles"
    
    @ID public var id: UUID
    @Column public var language: String = "en"
    @Column public var optInEmail: Bool = false
    @Column public var verified: Bool = false
    @Column public var userId: UUID = UUID()
    @Timestamp public var createdAt: Date = Date()
    
    public init() {}
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