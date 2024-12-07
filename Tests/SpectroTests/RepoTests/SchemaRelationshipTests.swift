import XCTest
@testable import Spectro

final class SchemaRelationshipTests: XCTestCase {
    func testUserSchemaRelationships() {
        let fields = UserSchema.fields
        
        let postsField = fields.first { $0.name == "posts" }
        XCTAssertNotNil(postsField)
        if case .relationship(let rel) = postsField?.type {
            XCTAssertEqual(rel.type, .hasMany)
            XCTAssertTrue(rel.foreignSchema is PostSchema.Type)
        }
        
        let profileField = fields.first { $0.name == "profile" }
        XCTAssertNotNil(profileField)
        if case .relationship(let rel) = profileField?.type {
            XCTAssertEqual(rel.type, .hasOne)
            XCTAssertTrue(rel.foreignSchema is ProfileSchema.Type)
        }
    }
    
    func testPostSchemaBelongsTo() {
        let fields = PostSchema.fields
        let userField = fields.first { $0.name == "users" }
        XCTAssertNotNil(userField)
        if case .relationship(let rel) = userField?.type {
            XCTAssertEqual(rel.type, .belongsTo)
            XCTAssertTrue(rel.foreignSchema is UserSchema.Type)
        }
    }
    
    func testCreateTableSQL() {
        let statements = UserSchema.createTable()
        let createUserTable = statements[0]
        
        XCTAssertTrue(createUserTable.contains("id UUID PRIMARY KEY DEFAULT gen_random_uuid()"))
        XCTAssertTrue(createUserTable.contains("posts UUID"))
        XCTAssertTrue(createUserTable.contains("profile UUID"))
        
        let postStatements = PostSchema.createTable()
        let createPostTable = postStatements[0]
        XCTAssertTrue(createPostTable.contains("users UUID REFERENCES users(id)"))
    }
    
    func testFieldValidation() {
        // Test UUID validation for relationships
        let userUUID = UUID()
        let field = Field.belongsTo("user", UserSchema.self)
        
        // Valid UUID
        let validValue = UserSchema.validateValue(userUUID, for: field)
        XCTAssertEqual(validValue, .uuid(userUUID))
        
        // Valid UUID string
        let validStringValue = UserSchema.validateValue(userUUID.uuidString, for: field)
        XCTAssertEqual(validStringValue, .uuid(userUUID))
        
        // Invalid value
        let invalidValue = UserSchema.validateValue("not-a-uuid", for: field)
        XCTAssertEqual(invalidValue, .null)
    }
    
    func testRelationshipEquality() {
        let rel1 = Relationship(name: "posts", type: .hasMany, foreignSchema: PostSchema.self)
        let rel2 = Relationship(name: "posts", type: .hasMany, foreignSchema: PostSchema.self)
        let rel3 = Relationship(name: "posts", type: .hasOne, foreignSchema: PostSchema.self)
        
        XCTAssertEqual(rel1, rel2)
        XCTAssertNotEqual(rel1, rel3)
    }
    
    func testDefaultValues() {
        let fields = UserSchema.fields
        
        // Test integer default
        let scoreField = fields.first { $0.name == "score" }
        XCTAssertNotNil(scoreField)
        if case .integer(let defaultValue) = scoreField?.type {
            XCTAssertEqual(defaultValue, 0)
        }
        
        // Test boolean default
        let isActiveField = fields.first { $0.name == "is_active" }
        XCTAssertNotNil(isActiveField)
        if case .boolean(let defaultValue) = isActiveField?.type {
            XCTAssertEqual(defaultValue, true)
        }
    }

    func testManyToManyPivotTable() {
        struct UserWithRoles: Schema {
            static let schemaName = "users"
            @SchemaBuilder
            static var fields: [SField] {
                Field.description("name", .string)
                Field.manyToMany("roles", RoleSchema.self, through: "user_roles")
            }
        }
        
        struct RoleSchema: Schema {
            static let schemaName = "roles"
            @SchemaBuilder
            static var fields: [SField] {
                Field.description("name", .string)
                Field.manyToMany("users", UserWithRoles.self, through: "user_roles")
            }
        }
        
        let statements = UserWithRoles.createTable()
        XCTAssertEqual(statements.count, 2)
        
        let pivotTable = statements[1]
        XCTAssertTrue(pivotTable.contains("CREATE TABLE IF NOT EXISTS user_roles"))
        XCTAssertTrue(pivotTable.contains("user_id UUID REFERENCES users(id) ON DELETE CASCADE"))
        XCTAssertTrue(pivotTable.contains("role_id UUID REFERENCES roles(id) ON DELETE CASCADE"))
        XCTAssertTrue(pivotTable.contains("PRIMARY KEY (user_id, role_id)"))
        XCTAssertTrue(pivotTable.contains("created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP"))
    }
}