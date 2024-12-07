import XCTest
@testable import Spectro

final class SchemaRelationshipTests: XCTestCase {
    func testUserSchemaRelationships() {
        let fields = UserSchema.fields
        
        debugPrint(fields)
        let postsField = fields.first { $0.name == "posts" }
        XCTAssertNotNil(postsField)
        if case .relationship(let rel) = postsField?.type {
            XCTAssertEqual(rel.type, .hasMany)
            XCTAssertTrue(rel.foreignSchema is PostSchema.Type)
        }
        
        let profileField = fields.first { $0.name == "profile" }
        XCTAssertNotNil(profileField)
        if case .relationship(let rel) = profileField?.type {
            XCTAssertEqual(rel.type, .hasOne)
            XCTAssertTrue(rel.foreignSchema is ProfileSchema.Type)
        }
    }
    
    func testPostSchemaBelongsTo() {
        let fields = PostSchema.fields
        let userField = fields.first { $0.name == "users" }
        XCTAssertNotNil(userField)
        if case .relationship(let rel) = userField?.type {
            XCTAssertEqual(rel.type, .belongsTo)
            XCTAssertTrue(rel.foreignSchema is UserSchema.Type)
        }
    }
}