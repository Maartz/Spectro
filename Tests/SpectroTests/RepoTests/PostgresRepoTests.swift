import Foundation
import Testing
import PostgresKit
import NIOCore
@testable import Spectro

@Suite("PostgresRepo Tests")
struct PostgresRepoTests {

    static let testDB = try! TestDatabase()
    static let repo = PostgresRepo(pools: testDB.pools)

    init() async throws {
        try await Self.testDB.setupTestTable()
    }

    // MARK: - All Tests

    @Test("Get all users without query")
    func testAllWithoutQuery() async throws {
        let users = try await Self.repo.all(UserSchema.self)

        #expect(users.count >= 2, "Should have at least 2 users from setup")
        #expect(users.allSatisfy { $0.id != UUID() }, "All users should have valid IDs")
    }

    @Test("Get all users with query filter")
    func testAllWithQuery() async throws {
        // Create a test user to ensure we have predictable data
        let changeset = Changeset(UserSchema.self, [
            "name": "John Test Query",
            "email": "john.query@test.com",
            "age": 25,
            "password": "test123"
        ])
        let testUser = try await Self.repo.insert(changeset)
        
        let users = try await Self.repo.all(UserSchema.self) { query in
            query.where { $0.name.like("John Test%") }
        }

        #expect(users.count >= 1, "Should find at least one user named John Test")
        let foundUser = users.first { ($0.data["name"] as? String)?.hasPrefix("John Test") ?? false }
        #expect(foundUser?.data["name"] as? String == "John Test Query", "Should find our test user")
        
        // Clean up
        try await Self.repo.delete(testUser)
    }

    @Test("Get all users with select and order")
    func testAllWithSelectAndOrder() async throws {
        let users = try await Self.repo.all(UserSchema.self) { query in
            query
                .select { [$0.name, $0.email] }
                .orderBy { [$0.name.desc()] }
        }

        #expect(users.count >= 2, "Should have at least 2 users")
        #expect(users.first?.data["email"] != nil, "Should have email data")
        #expect(users.first?.data["name"] != nil, "Should have name data")
    }

    // MARK: - Get Tests

    @Test("Get user by existing ID")
    func testGetExistingUser() async throws {
        // First get a user to have a valid ID
        let allUsers = try await Self.repo.all(UserSchema.self)
        guard let firstUser = allUsers.first else {
            Issue.record("No users found in database")
            return
        }

        let user = try await Self.repo.get(UserSchema.self, firstUser.id)

        #expect(user != nil, "Should find the user")
        #expect(user?.id == firstUser.id, "Should have the correct ID")
    }

    @Test("Get user by non-existing ID")
    func testGetNonExistingUser() async throws {
        let nonExistentId = UUID()
        let user = try await Self.repo.get(UserSchema.self, nonExistentId)

        #expect(user == nil, "Should not find non-existent user")
    }

    @Test("Get or fail with existing ID")
    func testGetOrFailExistingUser() async throws {
        let allUsers = try await Self.repo.all(UserSchema.self)
        guard let firstUser = allUsers.first else {
            Issue.record("No users found in database")
            return
        }

        let user = try await Self.repo.getOrFail(UserSchema.self, firstUser.id)

        #expect(user.id == firstUser.id, "Should return the correct user")
    }

    @Test("Get or fail with non-existing ID throws error")
    func testGetOrFailNonExistingUserThrows() async throws {
        let nonExistentId = UUID()

        await #expect(throws: RepositoryError.self) {
            _ = try await Self.repo.getOrFail(UserSchema.self, nonExistentId)
        }
    }

    // MARK: - Insert Tests

    @Test("Insert new user with valid changeset")
    func testInsertValidUser() async throws {
        let changeset = Changeset(UserSchema.self, [
            "name": "Test User",
            "email": "test@example.com",
            "age": 25,
            "is_active": true
        ])

        let user = try await Self.repo.insert(changeset)

        #expect(user.data["name"] as? String == "Test User", "Should have correct name")
        #expect(user.data["email"] as? String == "test@example.com", "Should have correct email")
        #expect(user.id != UUID(), "Should have a valid ID")

        // Verify it's actually in the database
        let fetchedUser = try await Self.repo.get(UserSchema.self, user.id)
        #expect(fetchedUser != nil, "Should be able to fetch the inserted user")

        // Clean up
        try await Self.repo.delete(user)
    }

    @Test("Insert user with invalid changeset throws error")
    func testInsertInvalidChangesetThrows() async throws {
        var changeset = Changeset(UserSchema.self, [
            "name": "Test User",
            "email": "test@example.com"
        ])

        // Make the changeset invalid by adding validation errors
        changeset.validateRequired(["non_existent_field"])

        await #expect(throws: RepositoryError.self) {
            _ = try await Self.repo.insert(changeset)
        }
    }

    @Test("Insert user with required fields")
    func testInsertUserWithRequiredFields() async throws {
        var changeset = Changeset(UserSchema.self, [
            "name": "Required User",
            "email": "required@example.com"
        ])

        changeset.validateRequired(["name", "email"])

        #expect(changeset.isValid, "Changeset should be valid with required fields")

        let user = try await Self.repo.insert(changeset)
        #expect(user.data["name"] as? String == "Required User", "Should have correct name")

        // Clean up
        try await Self.repo.delete(user)
    }

    // MARK: - Update Tests

    @Test("Update existing user")
    func testUpdateExistingUser() async throws {
        // First insert a user
        let insertChangeset = Changeset(UserSchema.self, [
            "name": "Original Name",
            "email": "original@example.com",
            "age": 30
        ])

        let originalUser = try await Self.repo.insert(insertChangeset)

        // Now update the user
        let updateChangeset = Changeset(UserSchema.self, [
            "name": "Updated Name",
            "age": 35
        ])

        let updatedUser = try await Self.repo.update(originalUser, updateChangeset)

        #expect(updatedUser.id == originalUser.id, "Should have the same ID")
        #expect(updatedUser.data["name"] as? String == "Updated Name", "Should have updated name")
        #expect(updatedUser.data["email"] as? String == "original@example.com", "Should keep original email")

        // Clean up
        try await Self.repo.delete(updatedUser)
    }

    @Test("Update with invalid changeset throws error")
    func testUpdateInvalidChangesetThrows() async throws {
        // First insert a user
        let insertChangeset = Changeset(UserSchema.self, [
            "name": "Test User",
            "email": "test@example.com"
        ])

        let user = try await Self.repo.insert(insertChangeset)

        var changeset = Changeset(UserSchema.self, [:])
        changeset.addError("name", "is invalid")

        await #expect(throws: RepositoryError.self) {
            _ = try await Self.repo.update(user, changeset)
        }

        // Clean up
        try await Self.repo.delete(user)
    }

    // MARK: - Delete Tests

    @Test("Delete existing user")
    func testDeleteExistingUser() async throws {
        // First insert a user to delete
        let changeset = Changeset(UserSchema.self, [
            "name": "To Be Deleted",
            "email": "delete@example.com"
        ])

        let user = try await Self.repo.insert(changeset)
        let userId = user.id

        // Verify the user exists
        let existingUser = try await Self.repo.get(UserSchema.self, userId)
        #expect(existingUser != nil, "User should exist before deletion")

        // Delete the user
        try await Self.repo.delete(user)

        // Verify the user is gone
        let deletedUser = try await Self.repo.get(UserSchema.self, userId)
        #expect(deletedUser == nil, "User should not exist after deletion")
    }

    // MARK: - Preload Tests

    @Test("Preload returns same models (not implemented)")
    func testPreloadReturnsModels() async throws {
        let users = try await Self.repo.all(UserSchema.self)
        let preloadedUsers = try await Self.repo.preload(users, ["posts"])

        #expect(preloadedUsers.count == users.count, "Should return same number of users")

        let preloadedIds = preloadedUsers.map { $0.id }
        let originalIds = users.map { $0.id }
        #expect(preloadedIds == originalIds, "Should return same user IDs")
    }

    // MARK: - Integration Tests

    @Test("Full CRUD cycle")
    func testFullCRUDCycle() async throws {
        // Create
        let createChangeset = Changeset(UserSchema.self, [
            "name": "CRUD Test User",
            "email": "crud@example.com",
            "age": 28,
            "is_active": true
        ])

        let createdUser = try await Self.repo.insert(createChangeset)
        #expect(createdUser.data["name"] as? String == "CRUD Test User", "Should create user correctly")

        // Read
        let readUser = try await Self.repo.getOrFail(UserSchema.self, createdUser.id)
        #expect(readUser.id == createdUser.id, "Should read the same user")

        // Update
        let updateChangeset = Changeset(UserSchema.self, [
            "name": "Updated CRUD User",
            "age": 29
        ])

        let updatedUser = try await Self.repo.update(readUser, updateChangeset)
        #expect(updatedUser.data["name"] as? String == "Updated CRUD User", "Should update user correctly")
        #expect(updatedUser.data["age"] as? Int == 29, "Should update age correctly")

        // Delete
        try await Self.repo.delete(updatedUser)
        let deletedUser = try await Self.repo.get(UserSchema.self, createdUser.id)
        #expect(deletedUser == nil, "Should delete user correctly")
    }

    @Test("Query with multiple conditions")
    func testQueryWithMultipleConditions() async throws {
        // Insert test data
        let user1Changeset = Changeset(UserSchema.self, [
            "name": "Young Active User",
            "email": "young@example.com",
            "age": 20,
            "is_active": true
        ])

        let user2Changeset = Changeset(UserSchema.self, [
            "name": "Old Inactive User",
            "email": "old@example.com",
            "age": 50,
            "is_active": false
        ])

        let user1 = try await Self.repo.insert(user1Changeset)
        let user2 = try await Self.repo.insert(user2Changeset)

        // Query with multiple conditions
        let activeUsers = try await Self.repo.all(UserSchema.self) { query in
            query.where { $0.is_active == true }
        }

        let youngUsers = try await Self.repo.all(UserSchema.self) { query in
            query.where { $0.age < 25 }
        }

        #expect(activeUsers.contains { $0.id == user1.id }, "Should find active user")
        #expect(youngUsers.contains { $0.id == user1.id }, "Should find young user")
        #expect(!activeUsers.contains { $0.id == user2.id }, "Should not find inactive user in active query")

        // Cleanup
        try await Self.repo.delete(user1)
        try await Self.repo.delete(user2)
    }

    // MARK: - Error Handling Tests

    @Test("Changeset validation works correctly")
    func testChangesetValidation() async {
        var changeset = Changeset(UserSchema.self, [
            "name": "Test User"
        ])

        // Test required field validation
        changeset.validateRequired(["name", "email"])

        #expect(!changeset.isValid, "Should be invalid without required email")
        #expect(changeset.errors["email"] != nil, "Should have error for missing email")

        // Add the required field
        changeset.put("email", "test@example.com")

        // Re-validate
        changeset = Changeset(UserSchema.self, [
            "name": "Test User",
            "email": "test@example.com"
        ])
        changeset.validateRequired(["name", "email"])

        #expect(changeset.isValid, "Should be valid with all required fields")
    }
}
