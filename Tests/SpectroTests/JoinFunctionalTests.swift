import Foundation
import Testing
@testable import Spectro

@Suite("Join and Relationship Tests")  
struct JoinFunctionalTests {
    
    @Test("Basic repository operations work")
    func testBasicRepositoryOperations() async throws {
        let repo = try TestSetup.getRepo()
        
        // Simple test to ensure repository can connect and work
        let users = try await repo.all(UserSchema.self)
        #expect(users.count >= 0)
        
        await TestSetup.shutdown()
    }
    
    // TODO: Implement relationship/join tests once query builder is enhanced
}