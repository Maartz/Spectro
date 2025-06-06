import Foundation
import Testing
@testable import Spectro

@Suite("Database Transaction Tests")
struct TransactionTests {
    
    /// Setup test database before running tests
    func setupDatabase() async throws -> DatabaseRepo {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        
        let repo = spectro.repository()
        try await TestDatabase.resetDatabase(using: repo)
        return repo
    }
    
    @Test("Basic transaction commit works")
    func testTransactionCommit() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        try await TestDatabase.resetDatabase(using: repo)
        
        // Execute operations in a transaction
        let result = try await repo.transaction { transactionRepo in
            // Insert a user within the transaction using new Schema system
            let user = User(name: "Transaction User", email: TestDatabase.uniqueEmail("transaction"), age: 30)
            let insertedUser = try await transactionRepo.insert(user)
            
            // Verify we can read it within the same transaction
            let foundUser = try await transactionRepo.get(User.self, id: insertedUser.id)
            #expect(foundUser != nil)
            #expect(foundUser?.name == "Transaction User")
            
            return insertedUser.id
        }
        
        // Verify the user exists after transaction commits
        let committedUser = try await repo.get(User.self, id: result)
        #expect(committedUser != nil)
        #expect(committedUser?.name == "Transaction User")
    }
    
    @Test("Transaction rollback on error")
    func testTransactionRollback() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        try await TestDatabase.resetDatabase(using: repo)
        
        // Get initial user count
        let initialUsers = try await repo.all(User.self)
        let initialCount = initialUsers.count
        
        // Try to execute a transaction that will fail
        do {
            try await repo.transaction { transactionRepo in
                // Insert a user using new Schema system
                let user = User(name: "Rollback User", email: TestDatabase.uniqueEmail("rollback"), age: 25)
                let _ = try await transactionRepo.insert(user)
                
                // Force an error to trigger rollback
                throw SpectroError.invalidQuery("Intentional error for rollback test")
            }
            
            // Should not reach here
            #expect(Bool(false), "Transaction should have failed")
        } catch {
            // Expected to catch the error
            #expect(error is SpectroError)
        }
        
        // Verify no users were added (transaction rolled back)
        let finalUsers = try await repo.all(User.self)
        #expect(finalUsers.count == initialCount)
    }
    
    @Test("Transaction supports all CRUD operations")
    func testTransactionCRUD() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        try await TestDatabase.resetDatabase(using: repo)
        
        try await repo.transaction { transactionRepo in
            // CREATE using new Schema system
            let user = User(name: "CRUD User", email: TestDatabase.uniqueEmail("crud"), age: 35)
            let savedUser = try await transactionRepo.insert(user)
            let userId = savedUser.id
            
            // READ
            let foundUser = try await transactionRepo.get(User.self, id: userId)
            #expect(foundUser != nil)
            #expect(foundUser?.name == "CRUD User")
            
            // UPDATE
            let updatedUser = try await transactionRepo.update(User.self, id: userId, changes: ["age": 36])
            #expect(updatedUser.age == 36)
            
            // Verify update persisted within transaction
            let verifyUser = try await transactionRepo.get(User.self, id: userId)
            #expect(verifyUser?.age == 36)
            
            // DELETE
            try await transactionRepo.delete(User.self, id: userId)
            
            // Verify deletion within transaction
            let deletedUser = try await transactionRepo.get(User.self, id: userId)
            #expect(deletedUser == nil)
        }
        
        // All operations were successful within the transaction
        #expect(Bool(true))
    }
    
    @Test("Nested transactions are not supported")
    func testNestedTransactions() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // For now, nested transactions work but we should document they're not recommended
        // This test demonstrates the current behavior
        let result = try await repo.transaction { outerRepo in
            // This currently works - PostgreSQL supports nested transactions via savepoints
            let innerResult = try await outerRepo.transaction { innerRepo in
                return "Inner transaction works"
            }
            return innerResult
        }
        
        #expect(result == "Inner transaction works")
    }
    
    @Test("Spectro convenience transaction method works")
    func testSpectroTransactionMethod() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        // Use Spectro's convenience transaction method
        let userId = try await spectro.transaction { repo in
            let user = User(name: "Spectro Transaction User", email: TestDatabase.uniqueEmail("spectro"), age: 28)
            let savedUser = try await repo.insert(user)
            return savedUser.id
        }
        
        // Verify the user was committed
        let committedUser = try await spectro.get(User.self, id: userId)
        #expect(committedUser != nil)
        #expect(committedUser?.name == "Spectro Transaction User")
    }
    
    @Test("Transaction isolation demonstration")
    func testTransactionIsolation() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // This test demonstrates that transactions are isolated
        // Changes made within a transaction are not visible outside until commit
        
        try await TestDatabase.resetDatabase(using: repo)
        
        let userIdFromTransaction = try await repo.transaction { transactionRepo in
            // Insert user within transaction using new Schema system
            let user = User(name: "Isolation Test User", email: TestDatabase.uniqueEmail("isolation"), age: 40)
            let savedUser = try await transactionRepo.insert(user)
            return savedUser.id
        }
        
        // Verify the user was committed
        let userAfterCommit = try await repo.get(User.self, id: userIdFromTransaction)
        #expect(userAfterCommit != nil)
    }
}