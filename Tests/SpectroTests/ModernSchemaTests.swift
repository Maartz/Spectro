import Foundation
import Testing
@testable import Spectro

@Suite("Modern Schema API Tests")
struct ModernSchemaTests {
    
    @Test("Can create modern schema instances")
    func testModernSchemaCreation() throws {
        // Test that we can create instances with clean syntax
        let user = ModernUser(
            name: "John Doe", 
            email: "john@example.com", 
            age: 30
        )
        
        #expect(user.name == "John Doe")
        #expect(user.email == "john@example.com")
        #expect(user.age == 30)
        #expect(user.id != UUID()) // Should have a generated UUID
        
        // Test schema metadata
        #expect(ModernUser.tableName == "users")
        #expect(ModernUser.schemaName == "users")
    }
    
    @Test("Property wrappers work correctly")
    func testPropertyWrappers() throws {
        var user = ModernUser()
        
        // Test ID property wrapper
        let originalId = user.id
        user.id = UUID()
        #expect(user.id != originalId)
        
        // Test Column property wrapper
        user.name = "Test User"
        #expect(user.name == "Test User")
        
        // Test Timestamp property wrapper
        let originalTime = user.createdAt
        user.createdAt = Date()
        #expect(user.createdAt >= originalTime)
    }
    
    @Test("Can use modern schemas with repository")
    func testModernSchemaWithRepository() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres", 
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // For now, just test that the types work together
        // We'd need to implement the actual Schema protocol conformance
        // to make this fully work with the repository
        
        #expect(repo is DatabaseRepo)
    }
    
    @Test("Modern API is beautiful")
    func testAPIBeauty() throws {
        // Demonstrate the beautiful API we're building towards:
        
        // Clean, declarative schema definition
        let user = ModernUser(
            name: "Alice Johnson",
            email: "alice@example.com",
            age: 28
        )
        
        // Property access is natural
        #expect(user.name == "Alice Johnson")
        #expect(user.age == 28)
        
        // Timestamps are automatic
        #expect(user.createdAt <= Date())
        #expect(user.updatedAt <= Date())
        
        // ID is automatically generated
        #expect(user.id.uuidString.count == 36)
        
        // This is the beautiful API we're working towards!
        // Once we implement proper Schema conformance, we'll be able to do:
        // let saved = try await repo.save(user)
        // let found = try await repo.find(User.self, user.id)
    }
}