import Foundation
import Testing
import PostgresKit
import NIOCore
@testable import Spectro

@Suite("Debug Preload Tests")
struct DebugPreloadTests {
    
    init() async {
        await TestSetup.configure()
    }
    
    @Test("Debug preload association logic")
    func testDebugPreloadAssociation() async throws {
        // Let's manually check the relationship
        let postsRelationship = UserSchema.relationship(named: "posts")
        print("Posts relationship: \(String(describing: postsRelationship))")
        
        if let rel = postsRelationship {
            print("Relationship type: \(rel.type)")
            print("Local key: \(rel.localKey)")
            print("Foreign key: \(rel.foreignKey)")
            print("Foreign schema: \(rel.foreignSchema.schemaName)")
        }
        
        // Test the actual query that should be run
        let user = try await UserSchema.all { $0.where { $0.name.eq("John Doe") } }.first!
        print("John Doe ID: \(user.id)")
        print("John Doe ID string: \(user.id.uuidString)")
        
        // Test the posts query directly
        let postsQuery = PostSchema.query().where { selector in
            QueryCondition(
                field: "user_id",
                op: "IN", 
                value: .array([.uuid(user.id)])
            )
        }
        print("Posts query SQL: \(postsQuery.debugSQL())")
        
        let posts = try await PostSchema.execute(postsQuery)
        print("Direct posts query found: \(posts.count) posts")
        
        for post in posts {
            let title = post.data["title"] as? String ?? "Unknown"
            let userId = post.data["user_id"] as? String ?? "No user_id"
            print("  Post: \(title), user_id: \(userId)")
        }
    }
}