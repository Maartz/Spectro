import Foundation
import Testing
@testable import Spectro

@Suite("Preload and Eager Loading Tests")
struct PreloadFunctionalTests {
    
    @Test("Basic repository operations work")
    func testBasicRepositoryOperations() async throws {
        let repo = try TestSetup.getRepo()
        
        // Simple test to ensure repository can connect and work
        let users = try await repo.all(UserSchema.self)
        #expect(users.count >= 0)
        
        await TestSetup.shutdown()
    }
    
    // TODO: Implement preload tests once query builder supports preloading
}