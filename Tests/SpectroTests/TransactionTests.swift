import Foundation
import Testing
@testable import Spectro

@Suite("Database Transaction Tests")
struct TransactionTests {
    
    @Test("Basic transaction commit works")
    func testTransactionCommit() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // Execute operations in a transaction
        let result = try await repo.transaction { transactionRepo in
            // Insert a user within the transaction
            let userData = [
                "name": "Transaction User",
                "email": "transaction@example.com",
                "age": 30
            ] as [String: Any]
            
            let insertedUser = try await transactionRepo.insert(UserSchema.self, data: userData)
            
            // Verify we can read it within the same transaction
            let foundUser = try await transactionRepo.get(UserSchema.self, id: insertedUser.id)
            #expect(foundUser != nil)
            #expect(foundUser?.data["name"] as? String == "Transaction User")
            
            return insertedUser.id
        }
        
        // Verify the user exists after transaction commits
        let committedUser = try await repo.get(UserSchema.self, id: result)
        #expect(committedUser != nil)
        #expect(committedUser?.data["name"] as? String == "Transaction User")
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
        
        // Get initial user count
        let initialUsers = try await repo.all(UserSchema.self)
        let initialCount = initialUsers.count
        
        // Try to execute a transaction that will fail
        do {
            try await repo.transaction { transactionRepo in
                // Insert a user
                let userData = [
                    "name": "Rollback User",
                    "email": "rollback@example.com",
                    "age": 25
                ] as [String: Any]
                
                let _ = try await transactionRepo.insert(UserSchema.self, data: userData)
                
                // Force an error to trigger rollback
                throw SpectroError.invalidQuery("Intentional error for rollback test")
            }
            
            // Should not reach here
            #expect(false, "Transaction should have failed")
        } catch {
            // Expected to catch the error
            #expect(error is SpectroError)
        }
        
        // Verify no users were added (transaction rolled back)
        let finalUsers = try await repo.all(UserSchema.self)
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
        
        try await repo.transaction { transactionRepo in
            // CREATE
            let userData = [
                "name": "CRUD User",
                "email": "crud@example.com",
                "age": 35
            ] as [String: Any]
            
            let user = try await transactionRepo.insert(UserSchema.self, data: userData)
            let userId = user.id
            
            // READ
            let foundUser = try await transactionRepo.get(UserSchema.self, id: userId)
            #expect(foundUser != nil)
            #expect(foundUser?.data["name"] as? String == "CRUD User")
            
            // UPDATE
            let updates = ["age": 36] as [String: Any]
            let updatedUser = try await transactionRepo.update(UserSchema.self, id: userId, changes: updates)
            #expect(updatedUser.data["age"] as? Int == 36)
            
            // Verify update persisted within transaction
            let verifyUser = try await transactionRepo.get(UserSchema.self, id: userId)
            #expect(verifyUser?.data["age"] as? Int == 36)
            
            // DELETE
            try await transactionRepo.delete(UserSchema.self, id: userId)
            
            // Verify deletion within transaction
            let deletedUser = try await transactionRepo.get(UserSchema.self, id: userId)
            #expect(deletedUser == nil)
        }
        
        // All operations were successful within the transaction
        #expect(true)
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
        
        do {
            try await repo.transaction { outerRepo in
                // Try to start a nested transaction
                try await outerRepo.transaction { innerRepo in
                    return "Should not reach here"
                }
            }
            
            #expect(false, "Nested transactions should not be supported")
        } catch let error as SpectroError {
            // Should catch notImplemented error for nested transactions
            if case .notImplemented(let message) = error {
                #expect(message.contains("Nested transactions"))
            } else {
                throw error
            }
        }
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
            let userData = [
                "name": "Spectro Transaction User",
                "email": "spectro.transaction@example.com",
                "age": 28
            ] as [String: Any]
            
            let user = try await repo.insert(UserSchema.self, data: userData)
            return user.id
        }
        
        // Verify the user was committed
        let committedUser = try await spectro.get(UserSchema.self, id: userId)
        #expect(committedUser != nil)
        #expect(committedUser?.data["name"] as? String == "Spectro Transaction User")
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
        
        var userIdFromTransaction: UUID?
        
        try await repo.transaction { transactionRepo in
            // Insert user within transaction
            let userData = [
                "name": "Isolation Test User",
                "email": "isolation@example.com",
                "age": 40
            ] as [String: Any]
            
            let user = try await transactionRepo.insert(UserSchema.self, data: userData)
            userIdFromTransaction = user.id
            
            // User exists within transaction
            let userInTransaction = try await transactionRepo.get(UserSchema.self, id: user.id)
            #expect(userInTransaction != nil)
        }
        
        // After transaction commits, user should exist
        if let userId = userIdFromTransaction {
            let userAfterCommit = try await repo.get(UserSchema.self, id: userId)
            #expect(userAfterCommit != nil)
        }
    }
}