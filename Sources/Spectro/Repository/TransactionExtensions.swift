import Foundation

/// Extensions for transaction support
extension GenericDatabaseRepo {
    
    /// Execute work within a savepoint (nested transaction)
    public func savepoint<T: Sendable>(_ name: String, work: @escaping @Sendable (Repo) async throws -> T) async throws -> T {
        let savepointName = "sp_\(name)_\(UUID().uuidString.prefix(8))"
        
        // Create savepoint
        try await executeRawSQL("SAVEPOINT \(savepointName)")
        
        do {
            let result = try await work(self)
            
            // Release savepoint on success
            try await executeRawSQL("RELEASE SAVEPOINT \(savepointName)")
            return result
        } catch {
            // Rollback to savepoint on error
            do {
                try await executeRawSQL("ROLLBACK TO SAVEPOINT \(savepointName)")
                try await executeRawSQL("RELEASE SAVEPOINT \(savepointName)")
            } catch {
                print("Warning: Failed to rollback to savepoint \(savepointName): \(error)")
            }
            
            throw error
        }
    }
    
    /// Execute work with a specific isolation level
    public func withIsolationLevel<T: Sendable>(_ level: IsolationLevel, work: @escaping @Sendable (Repo) async throws -> T) async throws -> T {
        // Set isolation level for this transaction
        try await executeRawSQL("BEGIN ISOLATION LEVEL \(level.sql)")
        
        do {
            let result = try await work(self)
            try await executeRawSQL("COMMIT")
            return result
        } catch {
            do {
                try await executeRawSQL("ROLLBACK")
            } catch {
                print("Warning: Failed to rollback transaction: \(error)")
            }
            throw error
        }
    }
}

/// PostgreSQL isolation levels
public enum IsolationLevel: Sendable {
    case readUncommitted
    case readCommitted
    case repeatableRead
    case serializable
    
    var sql: String {
        switch self {
        case .readUncommitted:
            return "READ UNCOMMITTED"
        case .readCommitted:
            return "READ COMMITTED"
        case .repeatableRead:
            return "REPEATABLE READ"
        case .serializable:
            return "SERIALIZABLE"
        }
    }
}