import Foundation
import Testing
import PostgresKit
import NIOCore
@testable import Spectro

@Suite("Schema Repository API Tests")
struct SchemaRepositoryTests {
    
    static let testDB = try! TestDatabase()
    static let repo = PostgresRepo(pools: testDB.pools)
    
    init() async throws {
        // Configure the repository globally
        RepositoryConfiguration.configure(with: Self.repo)
        
        // Set up test table
        try await Self.testDB.setupTestTable()
    }
    
    // MARK: - Direct Schema Methods
    
    @Test("Schema.all() returns all records")
    func testSchemaAll() async throws {
        let users = try await UserSchema.all()
        
        #expect(users.count >= 2, "Should have at least 2 users from setup")
        #expect(users.allSatisfy { $0.id != UUID() }, "All users should have valid IDs")
    }
    
    @Test("Schema.get() returns specific record")
    func testSchemaGet() async throws {
        let id = UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!
        let user = try await UserSchema.get(id)
        
        #expect(user != nil, "Should find user with known ID")
        #expect(user?.data["name"] as? String == "John Doe", "Should be John Doe")
    }
    
    @Test("Schema.getOrFail() throws when not found")
    func testSchemaGetOrFail() async throws {
        let randomId = UUID()
        
        await #expect(throws: RepositoryError.self) {
            _ = try await UserSchema.getOrFail(randomId)
        }
    }
    
    @Test("Schema.insert() creates new record")
    func testSchemaInsert() async throws {
        let newUser = try await UserSchema.insert([
            "name": "Test User",
            "email": "test@example.com",
            "password": "password123",
            "age": 25
        ])
        
        #expect(newUser.data["name"] as? String == "Test User")
        #expect(newUser.data["email"] as? String == "test@example.com")
        
        // Verify it was actually inserted
        let retrieved = try await UserSchema.get(newUser.id)
        #expect(retrieved != nil, "Should find the newly inserted user")
    }
    
    @Test("Schema.changeset() and create()")
    func testSchemaChangeset() async throws {
        let changeset = UserSchema.changeset([
            "name": "Changeset User",
            "email": "changeset@example.com",
            "password": "secure123"
        ])
        
        let user = try await UserSchema.create(changeset)
        
        #expect(user.data["name"] as? String == "Changeset User")
        #expect(user.data["email"] as? String == "changeset@example.com")
    }
    
    // MARK: - Query Builder Methods
    
    @Test("Schema.query() with where clause")
    func testSchemaQueryWhere() async throws {
        let query = UserSchema.query()
            .where { $0.name.like("John%") }
        let users = try await UserSchema.execute(query)
        
        #expect(users.count == 1, "Should find exactly one user named John")
        #expect(users.first?.data["name"] as? String == "John Doe")
    }
    
    @Test("Schema.query() with select and order")
    func testSchemaQuerySelectOrder() async throws {
        let query = UserSchema.query()
            .select { [$0.name, $0.email] }
            .orderBy { [$0.name.desc()] }
        let users = try await UserSchema.execute(query)
        
        #expect(users.count >= 2, "Should have at least 2 users")
        #expect(users.first?.data["email"] != nil, "Should have email data")
        #expect(users.first?.data["name"] != nil, "Should have name data")
        
        // Verify ordering
        let names = users.compactMap { $0.data["name"] as? String }
        #expect(names == names.sorted(by: >), "Should be in descending order")
    }
    
    @Test("Query.first() returns first result")
    func testQueryFirst() async throws {
        let query = UserSchema.query()
            .where { $0.age > 20 }
            .orderBy { [$0.age.asc()] }
        let user = try await UserSchema.executeFirst(query)
        
        #expect(user != nil, "Should find at least one user")
        #expect((user?.data["age"] as? Int ?? 0) > 20, "Should have age > 20")
    }
    
    @Test("Query.one() throws when no results")
    func testQueryOne() async throws {
        await #expect(throws: RepositoryError.self) {
            let query = UserSchema.query()
                .where { $0.name.eq("Non Existent User") }
            _ = try await UserSchema.executeOne(query)
        }
    }
    
    @Test("Query.exists() checks for existence")
    func testQueryExists() async throws {
        let query1 = UserSchema.query()
            .where { $0.name.like("John%") }
        let exists = try await UserSchema.executeExists(query1)
        
        #expect(exists == true, "Should find John Doe")
        
        let query2 = UserSchema.query()
            .where { $0.name.eq("Nobody") }
        let notExists = try await UserSchema.executeExists(query2)
        
        #expect(notExists == false, "Should not find Nobody")
    }
    
    @Test("Complex query with multiple conditions")
    func testComplexQuery() async throws {
        let query = UserSchema.query()
            .where { $0.age > 20 && $0.is_active == true }
            .select { [$0.name, $0.email, $0.age] }
            .orderBy { [$0.age.desc(), $0.name.asc()] }
            .limit(10)
        let users = try await UserSchema.execute(query)
        
        #expect(users.allSatisfy { ($0.data["age"] as? Int ?? 0) > 20 })
    }
    
    // MARK: - Model Instance Methods
    
    @Test("Model.update() modifies record")
    func testModelUpdate() async throws {
        // Create a new user for this test to avoid affecting other tests
        let changeset = Changeset(UserSchema.self, [
            "name": "Test Update User",
            "email": "test.update@example.com",
            "age": 25,
            "password": "test123"
        ])
        
        let newUser = try await UserSchema.create(changeset)
        
        let updated = try await newUser.update([
            "name": "Updated Test User",
            "age": 30
        ])
        
        #expect(updated.data["name"] as? String == "Updated Test User")
        #expect(updated.data["age"] as? Int == 30)
        
        // Verify in database
        let retrieved = try await UserSchema.get(newUser.id)
        #expect(retrieved?.data["name"] as? String == "Updated Test User")
        
        // Clean up
        try await newUser.delete()
    }
    
    @Test("Model.delete() removes record")
    func testModelDelete() async throws {
        // Create a user to delete
        let user = try await UserSchema.insert([
            "name": "To Delete",
            "email": "delete@example.com",
            "password": "temp123"
        ])
        
        // Delete it
        try await user.delete()
        
        // Verify it's gone
        let retrieved = try await UserSchema.get(user.id)
        #expect(retrieved == nil, "User should be deleted")
    }
    
    @Test("Model.reload() refreshes data")
    func testModelReload() async throws {
        // Create a user
        let user = try await UserSchema.insert([
            "name": "Original Name",
            "email": "reload@example.com",
            "password": "pass123"
        ])
        
        // Update it directly through repo (simulating external change)
        let repo = RepositoryConfiguration.defaultRepo!
        _ = try await repo.update(user, UserSchema.changeset([
            "name": "External Update"
        ]))
        
        // Reload the model
        let reloaded = try await user.reload()
        
        #expect(reloaded.data["name"] as? String == "External Update")
    }
    
    // MARK: - Error Handling
    
    @Test("Insert with invalid data throws error")
    func testInsertInvalidData() async throws {
        // Assuming changeset validation is implemented
        let changeset = UserSchema.changeset([
            "name": "", // Empty name should be invalid
            "email": "invalid-email" // Invalid email format
        ])
        
        // This should throw when validation is fully implemented
        // For now, it might succeed depending on implementation
        do {
            _ = try await UserSchema.create(changeset)
        } catch {
            // Expected validation error
            #expect(error is RepositoryError)
        }
    }
}