import Foundation
import Testing
@testable import Spectro

@Suite("Functional Tests")
struct FunctionalTests {
    
    // MARK: - Schema Tests (No Database Required)
    
    @Test("Schema property wrappers")
    func testSchemaPropertyWrappers() {
        var user = User()
        user.name = "Test User"
        user.email = "test@example.com"
        user.age = 25
        
        #expect(user.name == "Test User")
        #expect(user.email == "test@example.com")
        #expect(user.age == 25)
        #expect(user.isActive == true) // Default value
        #expect(User.tableName == "users")
    }
    
    @Test("SchemaBuilder implementation")
    func testSchemaBuilder() {
        let values: [String: Any] = [
            "id": UUID(),
            "name": "John Doe",
            "email": "john@example.com",
            "age": 30,
            "isActive": false,
            "createdAt": Date(),
            "updatedAt": Date()
        ]
        
        let user = User.build(from: values)
        #expect(user.name == "John Doe")
        #expect(user.email == "john@example.com")
        #expect(user.age == 30)
        #expect(user.isActive == false)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("SpectroError cases")
    func testSpectroErrorCases() {
        let errors: [SpectroError] = [
            .connectionFailed(underlying: SimpleTestError.sample),
            .queryExecutionFailed(sql: "SELECT *", error: SimpleTestError.sample),
            .notFound(schema: "users", id: UUID()),
            .invalidSchema(reason: "Missing primary key"),
            .transactionFailed(underlying: SimpleTestError.sample)
        ]
        
        for error in errors {
            // Verify errors can be created and have descriptions
            let description = String(describing: error)
            #expect(!description.isEmpty)
        }
    }
    
    // MARK: - Relationship Tests
    
    @Test("Relationship property wrappers")
    func testRelationshipPropertyWrappers() {
        struct UserWithRelations: Schema {
            static let tableName = "users"
            @ID var id: UUID
            @HasMany var posts: [Post]
            @HasOne var profile: Profile?
            init() {}
        }
        
        let user = UserWithRelations()
        
        // Test lazy relation properties
        #expect(!user.$posts.isLoaded)
        #expect(user.$posts.value == nil)
        #expect(user.posts.isEmpty) // Default empty array
        
        #expect(!user.$profile.isLoaded)
        #expect(user.$profile.value == nil)
        #expect(user.profile == nil)
    }
    
    // MARK: - Property Wrapper Tests
    
    @Test("Property wrapper functionality")
    func testPropertyWrappers() {
        // Test ID wrapper
        var idWrapper = ID()
        let originalId = idWrapper.wrappedValue
        idWrapper.wrappedValue = UUID()
        #expect(idWrapper.wrappedValue != originalId)
        
        // Test Column wrapper
        var stringColumn = Column(wrappedValue: "test")
        #expect(stringColumn.wrappedValue == "test")
        stringColumn.wrappedValue = "updated"
        #expect(stringColumn.wrappedValue == "updated")
        
        // Test Timestamp wrapper
        let timestamp = Timestamp()
        #expect(timestamp.wrappedValue <= Date())
        
        // Test ForeignKey wrapper
        let foreignKey = ForeignKey()
        #expect(foreignKey.wrappedValue != UUID())
    }
    
    // MARK: - Configuration Tests
    
    @Test("Database configuration")
    func testDatabaseConfiguration() {
        let config = DatabaseConfiguration(
            hostname: "localhost",
            port: 5432,
            username: "test_user",
            password: "test_password",
            database: "test_db"
        )
        
        #expect(config.hostname == "localhost")
        #expect(config.port == 5432)
        #expect(config.username == "test_user")
        #expect(config.password == "test_password")
        #expect(config.database == "test_db")
    }
    
    // MARK: - Schema Validation Tests
    
    @Test("Schema table name validation")
    func testSchemaTableNames() {
        #expect(User.tableName == "users")
        #expect(Post.tableName == "posts")
        #expect(Comment.tableName == "comments")
        #expect(Profile.tableName == "profiles")
        #expect(Tag.tableName == "tags")
        #expect(PostTag.tableName == "post_tags")
    }
    
    // MARK: - String Extension Tests
    
    @Test("String case conversion")
    func testStringCaseConversion() {
        #expect("firstName".snakeCase() == "first_name")
        #expect("lastName".snakeCase() == "last_name")
        #expect("isActive".snakeCase() == "is_active")
        #expect("createdAt".snakeCase() == "created_at")
        #expect("simple".snakeCase() == "simple")
    }
}

// Simple test helper
enum SimpleTestError: Error {
    case sample
}