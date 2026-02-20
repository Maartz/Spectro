import Foundation
import Testing
@testable import Spectro

@Suite("Schema Protocol")
struct SchemaTests {

    @Test("Schema provides tableName")
    func tableName() {
        #expect(TestUser.tableName == "test_users")
        #expect(TestPost.tableName == "test_posts")
    }

    @Test("Schema provides default init")
    func defaultInit() {
        let user = TestUser()
        #expect(user.name == "")
        #expect(user.email == "")
        #expect(user.age == 0)
        #expect(user.isActive == true)
    }

    @Test("SchemaBuilder.build populates fields from dictionary")
    func schemaBuilderBuild() {
        let id = UUID()
        let user = TestUser.build(from: [
            "id": id,
            "name": "Alice",
            "email": "alice@example.com",
            "age": 30,
            "isActive": false,
        ])
        #expect(user.id == id)
        #expect(user.name == "Alice")
        #expect(user.email == "alice@example.com")
        #expect(user.age == 30)
        #expect(user.isActive == false)
    }

    @Test("SchemaBuilder.build ignores unknown keys")
    func schemaBuilderUnknownKeys() {
        let user = TestUser.build(from: [
            "name": "Bob",
            "nonexistent": 42,
        ])
        #expect(user.name == "Bob")
        #expect(user.age == 0)
    }

    @Test("SchemaRegistry extracts metadata via Mirror")
    func schemaRegistryMetadata() async {
        let metadata = await SchemaRegistry.shared.register(TestUser.self)
        #expect(metadata.tableName == "test_users")
        #expect(metadata.primaryKeyField == "id")

        let fieldNames = metadata.fields.map(\.name)
        #expect(fieldNames.contains("id"))
        #expect(fieldNames.contains("name"))
        #expect(fieldNames.contains("email"))
        #expect(fieldNames.contains("age"))
        #expect(fieldNames.contains("isActive"))
        #expect(fieldNames.contains("createdAt"))
    }

    @Test("SchemaRegistry identifies field types correctly")
    func fieldTypes() async {
        let metadata = await SchemaRegistry.shared.register(TestUser.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(fieldMap["id"]?.fieldType == .uuid)
        #expect(fieldMap["id"]?.isPrimaryKey == true)
        #expect(fieldMap["name"]?.fieldType == .string)
        #expect(fieldMap["age"]?.fieldType == .int)
        #expect(fieldMap["isActive"]?.fieldType == .bool)
        #expect(fieldMap["createdAt"]?.fieldType == .date)
        #expect(fieldMap["createdAt"]?.isTimestamp == true)
    }

    @Test("SchemaRegistry identifies foreign keys")
    func foreignKeyDetection() async {
        let metadata = await SchemaRegistry.shared.register(TestPost.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(fieldMap["userId"]?.isForeignKey == true)
        #expect(fieldMap["userId"]?.fieldType == .uuid)
    }

    @Test("SchemaRegistry snake_cases database column names")
    func databaseNames() async {
        let metadata = await SchemaRegistry.shared.register(TestUser.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(fieldMap["isActive"]?.databaseName == "is_active")
        #expect(fieldMap["createdAt"]?.databaseName == "created_at")
    }
}

@Suite("DynamicSchema")
struct DynamicSchemaTests {
    class TestDynamicUser: DynamicSchema, @unchecked Sendable {
        override class var tableName: String { "dynamic_users" }
    }

    @Test("DynamicSchema provides tableName")
    func tableName() {
        #expect(TestDynamicUser.tableName == "dynamic_users")
    }

    @Test("DynamicSchema supports dynamic member access")
    func dynamicMemberAccess() {
        let user = TestDynamicUser()
        user.name = "Alice"
        user.age = 30
        #expect(user.name as? String == "Alice")
        #expect(user.age as? Int == 30)
    }

    @Test("DynamicSchema returns nil for unset attributes")
    func unsetAttributes() {
        let user = TestDynamicUser()
        #expect(user.name == nil)
    }
}
