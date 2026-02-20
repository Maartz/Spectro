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

    @Test("SchemaRegistry detects optional columns as nullable")
    func optionalColumnsNullable() async {
        let metadata = await SchemaRegistry.shared.register(TestUserWithBio.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(fieldMap["bio"] != nil, "bio field must be registered")
        #expect(fieldMap["bio"]?.fieldType == .string)
        #expect(fieldMap["bio"]?.isNullable == true)
        #expect(fieldMap["name"]?.isNullable == false)
    }

    @Test("SchemaRegistry snake_cases database column names")
    func databaseNames() async {
        let metadata = await SchemaRegistry.shared.register(TestUser.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })

        #expect(fieldMap["isActive"]?.databaseName == "is_active")
        #expect(fieldMap["createdAt"]?.databaseName == "created_at")
    }
}

@Suite("@Schema Macro")
struct SchemaMacroTests {

    @Test("Macro generates tableName")
    func macroTableName() {
        #expect(TestMacroUser.tableName == "test_macro_users")
    }

    @Test("Macro generates init() with correct defaults")
    func macroDefaultInit() {
        let user = TestMacroUser()
        #expect(user.name == "")
        #expect(user.email == "")
        #expect(user.bio == nil)
    }

    @Test("Macro generates convenience init for @Column properties")
    func macroConvenienceInit() {
        let user = TestMacroUser(name: "Alice", email: "alice@test.com")
        #expect(user.name == "Alice")
        #expect(user.email == "alice@test.com")
        #expect(user.bio == nil)
    }

    @Test("Macro convenience init accepts optional columns")
    func macroConvenienceInitOptional() {
        let user = TestMacroUser(name: "Bob", email: "bob@test.com", bio: "Hello")
        #expect(user.name == "Bob")
        #expect(user.bio == "Hello")
    }

    @Test("Macro convenience init auto-fills @ID and @Timestamp")
    func macroAutoFillsIDAndTimestamp() {
        let before = Date()
        let user = TestMacroUser(name: "C", email: "c@test.com")
        let after = Date()
        #expect(user.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        #expect(user.createdAt >= before)
        #expect(user.createdAt <= after)
    }

    @Test("Macro generates build(from:) that round-trips values")
    func macroBuild() {
        let id = UUID()
        let date = Date()
        let user = TestMacroUser.build(from: [
            "id": id,
            "name": "Alice",
            "email": "alice@example.com",
            "bio": "Hi there",
            "createdAt": date,
        ])
        #expect(user.id == id)
        #expect(user.name == "Alice")
        #expect(user.email == "alice@example.com")
        #expect(user.bio == "Hi there")
        #expect(user.createdAt == date)
    }

    @Test("Macro build(from:) handles nil optional correctly")
    func macroBuildNilOptional() {
        let user = TestMacroUser.build(from: [
            "name": "Bob",
            "email": "bob@example.com",
        ])
        #expect(user.name == "Bob")
        #expect(user.bio == nil)
    }

    @Test("SchemaRegistry detects macro-generated schema fields")
    func macroSchemaRegistry() async {
        let metadata = await SchemaRegistry.shared.register(TestMacroUser.self)
        #expect(metadata.tableName == "test_macro_users")
        let fieldNames = metadata.fields.map(\.name)
        #expect(fieldNames.contains("id"))
        #expect(fieldNames.contains("name"))
        #expect(fieldNames.contains("email"))
        #expect(fieldNames.contains("bio"))
        #expect(fieldNames.contains("createdAt"))
    }

    @Test("SchemaRegistry detects nullable bio on macro schema")
    func macroNullableField() async {
        let metadata = await SchemaRegistry.shared.register(TestMacroUser.self)
        let fieldMap = Dictionary(uniqueKeysWithValues: metadata.fields.map { ($0.name, $0) })
        #expect(fieldMap["bio"]?.isNullable == true)
        #expect(fieldMap["bio"]?.fieldType == .string)
        #expect(fieldMap["name"]?.isNullable == false)
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
