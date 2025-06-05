import Foundation
import Testing
@testable import Spectro

@Suite("Relationship Introspection Tests")
struct RelationshipIntrospectionTests {
    
    // MARK: - Relationship Discovery Tests (No DB required)
    
    @Test("Relationship introspection")
    func testRelationshipIntrospection() async throws {
        let relationships = UserSchema.relationships
        
        #expect(relationships.count >= 2, "UserSchema should have posts and profile relationships")
        
        let postRelationship = UserSchema.relationship(named: "posts")
        #expect(postRelationship != nil, "Should find posts relationship")
        #expect(postRelationship?.type == .hasMany, "Posts should be hasMany relationship")
        
        let profileRelationship = UserSchema.relationship(named: "profile")
        #expect(profileRelationship != nil, "Should find profile relationship")
        #expect(profileRelationship?.type == .hasOne, "Profile should be hasOne relationship")
    }
    
    @Test("Foreign key inference")
    func testForeignKeyInference() async throws {
        let postRelationship = UserSchema.relationship(named: "posts")
        
        #expect(postRelationship?.localKey == "id", "User local key should be id")
        #expect(postRelationship?.foreignKey == "user_id", "Post foreign key should be user_id")
        
        // Test belongsTo relationship
        let userRelationship = PostSchema.relationship(named: "user")
        
        #expect(userRelationship?.localKey == "user_id", "Post local key should be user_id")
        #expect(userRelationship?.foreignKey == "id", "User foreign key should be id")
    }
    
    @Test("Relationship types")
    func testRelationshipTypes() async throws {
        let hasMany = UserSchema.relationships(ofType: .hasMany)
        #expect(hasMany.count >= 1, "Should have at least posts as hasMany")
        
        let hasOne = UserSchema.relationships(ofType: .hasOne)
        #expect(hasOne.count >= 1, "Should have at least profile as hasOne")
        
        let belongsTo = PostSchema.relationships(ofType: .belongsTo)
        #expect(belongsTo.count >= 1, "Post should belong to user")
    }
    
    @Test("String singularization")
    func testSingularization() async throws {
        #expect("posts".singularize() == "post")
        #expect("users".singularize() == "user")
        #expect("companies".singularize() == "company")
        #expect("categories".singularize() == "category")
        #expect("stories".singularize() == "story")
        #expect("person".singularize() == "person") // No change for singular
    }
}