import Foundation
@testable import Spectro

// MARK: - Test Schema Definitions

struct TestUser: Schema, SchemaBuilder {
    static let tableName = "test_users"

    @ID var id: UUID
    @Column var name: String
    @Column var email: String
    @Column var age: Int
    @Column var isActive: Bool
    @Timestamp var createdAt: Date

    init() {
        self.id = UUID()
        self.name = ""
        self.email = ""
        self.age = 0
        self.isActive = true
        self.createdAt = Date()
    }

    init(name: String, email: String, age: Int, isActive: Bool = true) {
        self.id = UUID()
        self.name = name
        self.email = email
        self.age = age
        self.isActive = isActive
        self.createdAt = Date()
    }

    static func build(from values: [String: Any]) -> TestUser {
        var user = TestUser()
        if let v = values["id"] as? UUID { user.id = v }
        if let v = values["name"] as? String { user.name = v }
        if let v = values["email"] as? String { user.email = v }
        if let v = values["age"] as? Int { user.age = v }
        if let v = values["isActive"] as? Bool { user.isActive = v }
        if let v = values["createdAt"] as? Date { user.createdAt = v }
        return user
    }
}

struct TestPost: Schema, SchemaBuilder {
    static let tableName = "test_posts"

    @ID var id: UUID
    @Column var title: String
    @Column var body: String
    @ForeignKey var userId: UUID
    @Timestamp var createdAt: Date

    init() {
        self.id = UUID()
        self.title = ""
        self.body = ""
        self.userId = UUID()
        self.createdAt = Date()
    }

    init(title: String, body: String, userId: UUID) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.userId = userId
        self.createdAt = Date()
    }

    static func build(from values: [String: Any]) -> TestPost {
        var post = TestPost()
        if let v = values["id"] as? UUID { post.id = v }
        if let v = values["title"] as? String { post.title = v }
        if let v = values["body"] as? String { post.body = v }
        if let v = values["userId"] as? UUID { post.userId = v }
        if let v = values["createdAt"] as? Date { post.createdAt = v }
        return post
    }
}
