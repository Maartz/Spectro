import Foundation
@testable import Spectro

/// Shared test setup for all tests using new actor-based architecture
public struct TestSetup {
    private static var _spectro: Spectro?
    
    /// Get or create a test Spectro instance
    public static func getSpectro() throws -> Spectro {
        if let spectro = _spectro {
            return spectro
        }
        
        let config = DatabaseConfiguration(
            hostname: "localhost",
            port: 5432,
            username: "postgres",
            password: "postgres", 
            database: "spectro_test"
        )
        
        let spectro = try Spectro(configuration: config)
        _spectro = spectro
        return spectro
    }
    
    /// Get a configured repository for tests that need direct repo access
    public static func getRepo() throws -> DatabaseRepo {
        let spectro = try getSpectro()
        return spectro.repository()
    }
    
    /// Clean up resources after tests
    public static func shutdown() async {
        if let spectro = _spectro {
            await spectro.shutdown()
            _spectro = nil
        }
    }
}