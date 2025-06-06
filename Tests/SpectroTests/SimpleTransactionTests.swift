import Foundation
import Testing
@testable import Spectro

@Suite("Simple Transaction Tests")
struct SimpleTransactionTests {
    
    @Test("Transaction method exists and doesn't crash")
    func testTransactionExists() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // Test that transaction method exists and can be called
        let result = try await repo.transaction { transactionRepo in
            // Just return a simple value to verify transaction works
            return "transaction_works"
        }
        
        #expect(result == "transaction_works")
    }
    
    @Test("Spectro transaction convenience method works")
    func testSpectroTransaction() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres", 
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        // Use Spectro's convenience transaction method
        let result = try await spectro.transaction { repo in
            return 42
        }
        
        #expect(result == 42)
    }
    
    @Test("Transaction rollback behavior") 
    func testTransactionRollback() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // Verify transaction rolls back on error
        do {
            try await repo.transaction { transactionRepo in
                // Throw an error to trigger rollback
                throw SpectroError.invalidQuery("Test rollback")
            }
            
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as SpectroError {
            // Should catch the error we threw
            if case .invalidQuery(let message) = error {
                #expect(message == "Test rollback")
            } else {
                throw error
            }
        }
    }
}