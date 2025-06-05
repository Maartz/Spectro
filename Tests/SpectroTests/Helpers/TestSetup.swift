import Foundation
@testable import Spectro

/// Shared test setup for all tests
@MainActor
public struct TestSetup {
    private static var isConfigured = false
    
    public static func configure() {
        guard !isConfigured else { return }
        
        do {
            let testDB = try TestDatabase()
            let repo = PostgresRepo(pools: testDB.pools)
            
            // Configure the global repository
            RepositoryConfiguration.configure(with: repo)
            
            isConfigured = true
        } catch {
            fatalError("Failed to configure test setup: \(error)")
        }
    }
    
    /// Get a configured repository for tests that need direct repo access
    public static func getRepo() throws -> PostgresRepo {
        configure() // Ensure configuration
        
        guard let repo = RepositoryConfiguration.defaultRepo as? PostgresRepo else {
            fatalError("Repository not properly configured")
        }
        
        return repo
    }
}