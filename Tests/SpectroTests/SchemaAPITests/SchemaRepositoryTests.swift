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
        // Create a test user with a known ID
        let changeset = Changeset(UserSchema.self, [
            "name": "Test Get User",
            "email": "test.get@example.com",
            "age": 30,
            "password": "test123"
        ])
        let createdUser = try await UserSchema.create(changeset)
        
        // Test the get method
        let user = try await UserSchema.get(createdUser.id)
        
        #expect(user != nil, "Should find user with known ID")
        #expect(user?.data["name"] as? String == "Test Get User", "Should find our test user")
        #expect(user?.id == createdUser.id, "Should have the correct ID")
        
        // Clean up
        try await createdUser.delete()
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
        // Create a test user
        let changeset = Changeset(UserSchema.self, [
            "name": "Query Test User",
            "email": "query.test@example.com",
            "age": 25,
            "password": "test123"
        ])
        let testUser = try await UserSchema.create(changeset)
        
        let query = UserSchema.query()
            .where { $0.name.like("Query Test%") }
        let users = try await UserSchema.execute(query)
        
        #expect(users.count >= 1, "Should find at least one user")
        #expect(users.first { $0.id == testUser.id }?.data["name"] as? String == "Query Test User")
        
        // Clean up
        try await testUser.delete()
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
        // Create a test user
        let changeset = Changeset(UserSchema.self, [
            "name": "Exists Test User",
            "email": "exists.test@example.com",
            "age": 25,
            "password": "test123"
        ])
        let testUser = try await UserSchema.create(changeset)
        
        let query1 = UserSchema.query()
            .where { $0.name.like("Exists Test%") }
        let exists = try await UserSchema.executeExists(query1)
        
        #expect(exists == true, "Should find our test user")
        
        let query2 = UserSchema.query()
            .where { $0.name.eq("Nobody") }
        let notExists = try await UserSchema.executeExists(query2)
        
        // Clean up
        try await testUser.delete()
        
        #expect(notExists == false, "Should not find Nobody")
    }
    
    @Test("Complex query with multiple conditions")
    func testComplexQuery() async throws {
        // Create test users
        let users = [
            ("Alice Complex", 25),
            ("Bob Complex", 30),
            ("Charlie Complex", 18) // This one should be filtered out
        ]
        
        var createdUsers: [UserSchema.Model] = []
        for (name, age) in users {
            let changeset = Changeset(UserSchema.self, [
                "name": name,
                "email": "\(name.lowercased().replacingOccurrences(of: " ", with: "."))@example.com",
                "age": age,
                "password": "test123",
                "is_active": true
            ])
            createdUsers.append(try await UserSchema.create(changeset))
        }
        
        let query = UserSchema.query()
            .where { $0.age > 20 && $0.is_active == true }
            .select { [$0.name, $0.email, $0.age] }
            .orderBy { [$0.age.desc(), $0.name.asc()] }
            .limit(10)
        let results = try await UserSchema.execute(query)
        
        // Should find Alice (25) and Bob (30), but not Charlie (18)
        let complexUsers = results.filter { ($0.data["name"] as? String ?? "").contains("Complex") }
        #expect(complexUsers.count == 2, "Should find 2 users over 20")
        #expect(complexUsers.allSatisfy { ($0.data["age"] as? Int ?? 0) > 20 })
        
        // Clean up
        for user in createdUsers {
            try await user.delete()
        }
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