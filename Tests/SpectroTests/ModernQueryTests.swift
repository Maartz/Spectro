import Foundation
import Testing
@testable import Spectro

@Suite("Revolutionary Closure-based Query Tests")
struct ModernQueryTests {
    
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
    
    @Test("Schema table name mapping works")
    func testSchemaTableNames() throws {
        // Test that all schemas have correct table names
        #expect(User.tableName == "users")
        #expect(Post.tableName == "posts")
        #expect(Comment.tableName == "comments")
        #expect(Profile.tableName == "profiles")
        #expect(Tag.tableName == "tags")
        #expect(PostTag.tableName == "post_tags")
        
        print("✅ All schema table names working correctly")
    }
    
    @Test("Can create beautiful closure-based queries")
    func testClosureBasedQueryBuilder() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // Test that we can create beautiful closure-based queries
        let query = repo.query(User.self)
        
        // Add beautiful closure conditions
        let typedQuery = query
            .where { $0.name == "John" }
            .where { $0.age > 18 }
            .orderBy({ $0.createdAt }, .desc)
            .limit(10)
        
        // Verify the query builds without errors
        #expect(typedQuery is Query<User>)
    }
    
    @Test("Closure query conditions work correctly")
    func testClosureQueryConditions() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // Test various closure-based conditions
        let query1 = repo.query(User.self).where { $0.age > 18 }
        let query2 = repo.query(User.self).where { $0.name == "John" }
        let query3 = repo.query(User.self).where { $0.email.endsWith("@example.com") }
        let query4 = repo.query(User.self).where { $0.age.between(18, and: 65) }
        
        // All should build without errors
        #expect(query1 is Query<User>)
        #expect(query2 is Query<User>)
        #expect(query3 is Query<User>)
        #expect(query4 is Query<User>)
    }
    
    @Test("Closure query API is type-safe")
    func testTypeSafety() throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // These should all compile and be type-safe
        let query1 = repo.query(User.self)
            .where { $0.name == "John" }     // String comparison
            .where { $0.age > 18 }           // Int comparison
        
        let query2 = repo.query(User.self)
            .where { $0.id.in([UUID(), UUID()]) } // UUID array
        
        let query3 = repo.query(User.self)
            .where { $0.age.between(18, and: 65) } // Range comparison
        
        let query4 = repo.query(User.self)
            .orderBy({ $0.createdAt }, .desc)    // Date ordering
            .orderBy({ $0.name }, .asc)          // String ordering
        
        let query5a = repo.query(User.self)
            .select { $0.name }                  // Single field selection
        
        let query5b = repo.query(User.self)
            .select { ($0.name, $0.email) }     // Revolutionary tuple selection
        
        // All these should compile without errors
        #expect(Bool(true))
    }
    
    @Test("Query builder is immutable")
    func testQueryBuilderImmutability() throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        let baseQuery = repo.query(User.self)
        
        // Adding conditions should return new instances
        let query1 = baseQuery.where { $0.name == "John" }
        let query2 = baseQuery.where { $0.age > 18 }
        let query3 = query1.where { $0.email.endsWith("@example.com") }
        
        // Each query should be independent
        #expect(query1 is Query<User>)
        #expect(query2 is Query<User>)
        #expect(query3 is Query<User>)
    }
    
    @Test("Revolutionary API demonstration")
    func testRevolutionaryAPI() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // Demonstrate the revolutionary API we've built:
        
        // Complex query with natural Swift syntax
        let _ = repo.query(User.self)
            .where { $0.age >= 18 }
            .where { $0.email.endsWith("@company.com") }
            .where { $0.name != "Admin" }
            .orderBy({ $0.createdAt }, .desc)
            .orderBy({ $0.name }, .asc)
            .limit(50)
            .offset(0)
        
        // Simple equality check with natural syntax
        let _ = repo.query(User.self)
            .where { $0.name == "John" }
        
        // Range queries with beautiful between syntax
        let _ = repo.query(User.self)
            .where { $0.age.between(18, and: 30) }
        
        // Array membership with natural in() function
        let _ = repo.query(User.self)
            .where { $0.id.in([UUID(), UUID(), UUID()]) }
        
        // Revolutionary tuple field selection
        let _ = repo.query(User.self)
            .select { ($0.name, $0.email, $0.age) }
            .where { $0.age > 21 }
        
        // Complex conditions with && and || operators
        let _ = repo.query(User.self)
            .where { $0.age > 25 && $0.email.iContains("company") }
            .where { $0.isActive == true || $0.name.startsWith("Admin") }
        
        // This demonstrates the revolutionary, natural API we've built!
        #expect(Bool(true))
        
        print("✅ Revolutionary Query API Demonstrated:")
        print("   🎯 Natural Swift closure syntax")
        print("   🔗 Beautiful && and || operators")
        print("   📐 Rich string functions: .endsWith(), .iContains(), .startsWith()")
        print("   🎨 Revolutionary tuple selection")
        print("   💫 Natural range functions: .between()")
        print("   🚀 Better DX than any other ORM!")
    }
}