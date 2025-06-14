import Foundation
import Testing
@testable import Spectro

/// Integration tests that require a real PostgreSQL database
/// 
/// Prerequisites:
/// 1. PostgreSQL must be running
/// 2. Test database must exist: createdb spectro_test
/// 3. Test user must have permissions
///
/// To run these tests:
/// ```bash
/// createdb spectro_test
/// swift test --filter DatabaseIntegrationTests
/// ```
@Suite("Database Integration Tests", .serialized)
struct DatabaseIntegrationTests {
    
    /// Shared test spectro instance
    static var spectro: Spectro?
    
    init() async throws {
        // Skip if already initialized
        if Self.spectro != nil { return }
        
        do {
            // Try to connect to test database
            let testSpectro = try await Spectro(
                hostname: ProcessInfo.processInfo.environment["TEST_DB_HOST"] ?? "localhost",
                port: Int(ProcessInfo.processInfo.environment["TEST_DB_PORT"] ?? "5432") ?? 5432,
                username: ProcessInfo.processInfo.environment["TEST_DB_USER"] ?? "postgres",
                password: ProcessInfo.processInfo.environment["TEST_DB_PASSWORD"] ?? "postgres",
                database: ProcessInfo.processInfo.environment["TEST_DB_NAME"] ?? "spectro_test"
            )
            
            // Verify connection works
            _ = try await testSpectro.testConnection()
            
            // Set up test tables
            let repo = testSpectro.repository()
            try await setupTestTables(repo: repo)
            
            Self.spectro = testSpectro
        } catch {
            print("⚠️  Database integration tests skipped: \(error)")
            print("   Make sure PostgreSQL is running and test database exists")
            throw error
        }
    }
    
    
    // MARK: - CRUD Tests
    
    @Test("Create, Read, Update, Delete operations")
    func testCRUD() async throws {
        guard let spectro = Self.spectro else {
            throw DBTestError.databaseNotAvailable
        }
        
        let repo = spectro.repository()
        
        // Clean tables before test
        try await cleanTestData(repo: repo)
        
        // Create
        var user = User()
        user.name = "Test User"
        user.email = "test\(UUID().uuidString.prefix(8))@example.com"
        user.age = 25
        
        let created = try await repo.insert(user)
        #expect(created.id != user.id) // Should have new ID
        #expect(created.name == "Test User")
        
        // Read
        let found = try await repo.get(User.self, id: created.id)
        #expect(found?.name == "Test User")
        #expect(found?.email == created.email)
        
        // Update
        let updated = try await repo.update(User.self, id: created.id, changes: [
            "name": "Updated User",
            "age": 26
        ])
        #expect(updated.name == "Updated User")
        #expect(updated.age == 26)
        
        // Delete
        try await repo.delete(User.self, id: created.id)
        let deleted = try await repo.get(User.self, id: created.id)
        #expect(deleted == nil)
    }
    
    @Test("Query operations")
    func testQueries() async throws {
        guard let spectro = Self.spectro else {
            throw DBTestError.databaseNotAvailable
        }
        
        let repo = spectro.repository()
        
        // Clean and insert test data
        try await cleanTestData(repo: repo)
        
        let users = [
            ("Alice", 25, true),
            ("Bob", 35, true),
            ("Charlie", 45, false),
            ("David", 20, true)
        ]
        
        for (name, age, active) in users {
            var user = User()
            user.name = name
            user.email = "\(name.lowercased())\(UUID().uuidString.prefix(8))@example.com"
            user.age = age
            user.isActive = active
            _ = try await repo.insert(user)
        }
        
        // Test various queries
        let adults = try await repo.query(User.self)
            .where { $0.age >= 21 }
            .orderBy { $0.age }
            .all()
        #expect(adults.count == 3)
        #expect(adults.first?.name == "Alice")
        
        let activeUsers = try await repo.query(User.self)
            .where { $0.isActive == true }
            .count()
        #expect(activeUsers == 3)
        
        let firstInactive = try await repo.query(User.self)
            .where { $0.isActive == false }
            .first()
        #expect(firstInactive?.name == "Charlie")
    }
    
    @Test("Transaction support")
    func testTransactions() async throws {
        guard let spectro = Self.spectro else {
            throw DBTestError.databaseNotAvailable
        }
        
        let repo = spectro.repository()
        try await cleanTestData(repo: repo)
        
        // Successful transaction
        let result = try await repo.transaction { txRepo in
            var user = User()
            user.name = "Transaction User"
            user.email = "tx\(UUID().uuidString.prefix(8))@example.com"
            let savedUser = try await txRepo.insert(user)
            
            var post = Post()
            post.title = "Transaction Post"
            post.content = "Created in transaction"
            post.userId = savedUser.id
            let savedPost = try await txRepo.insert(post)
            
            return (savedUser, savedPost)
        }
        
        // Verify data was saved
        let user = try await repo.get(User.self, id: result.0.id)
        #expect(user?.name == "Transaction User")
        
        let post = try await repo.get(Post.self, id: result.1.id)
        #expect(post?.title == "Transaction Post")
        
        // Failed transaction (should rollback)
        do {
            try await repo.transaction { txRepo in
                var user = User()
                user.name = "Rollback User"
                user.email = "rollback\(UUID().uuidString.prefix(8))@example.com"
                _ = try await txRepo.insert(user)
                
                // Force an error
                throw DBTestError.forcedRollback
            }
            #expect(false, "Transaction should have failed")
        } catch DBTestError.forcedRollback {
            // Expected
        }
        
        // Verify rollback worked - no "Rollback User" should exist
        let rollbackUsers = try await repo.query(User.self)
            .where { $0.name == "Rollback User" }
            .all()
        #expect(rollbackUsers.isEmpty)
    }
    
    @Test("Join operations")
    func testJoins() async throws {
        guard let spectro = Self.spectro else {
            throw DBTestError.databaseNotAvailable
        }
        
        let repo = spectro.repository()
        try await cleanTestData(repo: repo)
        
        // Create test data
        var user = User()
        user.name = "Join Test User"
        user.email = "join\(UUID().uuidString.prefix(8))@example.com"
        let savedUser = try await repo.insert(user)
        
        var post = Post()
        post.title = "Join Test Post"
        post.content = "Testing joins"
        post.userId = savedUser.id
        let savedPost = try await repo.insert(post)
        
        // Test inner join
        let usersWithPosts = try await repo.query(User.self)
            .join(Post.self) { join in
                join.left.id == join.right.userId
            }
            .where { $0.name == "Join Test User" }
            .all()
        
        #expect(usersWithPosts.count == 1)
        #expect(usersWithPosts.first?.name == "Join Test User")
    }
    
    @Test("Cleanup test data")
    func testCleanup() async throws {
        // Clean up after all tests
        if let spectro = Self.spectro {
            let repo = spectro.repository()
            try await cleanTestData(repo: repo)
            await spectro.shutdown()
            Self.spectro = nil
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupTestTables(repo: GenericDatabaseRepo) async throws {
        // Create tables if they don't exist
        let tableQueries = [
            """
            CREATE TABLE IF NOT EXISTS users (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                name TEXT NOT NULL,
                email TEXT NOT NULL,
                age INTEGER DEFAULT 0,
                is_active BOOLEAN DEFAULT true,
                created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS posts (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                published BOOLEAN DEFAULT false,
                user_id UUID NOT NULL,
                created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS profiles (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                language TEXT DEFAULT 'en',
                opt_in_email BOOLEAN DEFAULT false,
                verified BOOLEAN DEFAULT false,
                user_id UUID NOT NULL,
                created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
            )
            """
        ]
        
        for query in tableQueries {
            try await repo.executeRawSQL(query)
        }
    }
    
    private func cleanTestData(repo: GenericDatabaseRepo) async throws {
        // Clean in reverse dependency order
        let cleanQueries = [
            "DELETE FROM profiles",
            "DELETE FROM posts",
            "DELETE FROM users"
        ]
        
        for query in cleanQueries {
            do {
                try await repo.executeRawSQL(query)
            } catch {
                // Table might not exist, continue
                print("Warning: Failed to clean table: \(error)")
            }
        }
    }
}

enum DBTestError: Error {
    case databaseNotAvailable
    case forcedRollback
}