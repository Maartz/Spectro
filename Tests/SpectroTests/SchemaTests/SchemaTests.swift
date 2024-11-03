//
//  SchemaTests.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import XCTest
@testable import Spectro

final class SchemaTests: XCTestCase {
    
    func testUserSchemaDefinition() throws {
        let schemaName = UserSchema.schemaName
        let fields = UserSchema.fields

        XCTAssertEqual(schemaName, "users", "Expected schema name 'users' but got \(schemaName)")
        XCTAssertEqual(fields.count, 3, "Expected 3 fields in User schema, but got \(fields.count)")

        let nameField = UserSchema.name
        XCTAssertNotNil(nameField, "Expected 'name' field in User schema")
        XCTAssertEqual(nameField?.type, .string, "Expected 'name' field to be of type string")

        let ageField = UserSchema.age
        XCTAssertNotNil(ageField, "Expected 'age' field in User schema")
        
        if case let .integer(defaultValue) = ageField?.type {
            XCTAssertEqual(defaultValue, 0, "Expected default value of 0 for 'age'")
        } else {
            XCTFail("Expected 'age' field to be of type integer")
        }

        let passwordField = UserSchema.password
        XCTAssertNotNil(passwordField, "Expected 'password' field in User schema")
        XCTAssertEqual(passwordField?.isRedacted, true, "Expected 'password' field to be redacted")
    }

    // TODO: would be great to be able to pass an Array of params to Query.select
    // .select(UserSchema.fields.map { $0.name })
    func testSchemaToQueryTranslation() throws {
        let query = Query.from(UserSchema.schemaName)
            .select("name", "age", "password")
            .where("name", "=", "John Doe")

        XCTAssertEqual(query.table, "users", "Expected query table 'users'")
        XCTAssertEqual(query.selections, ["name", "age", "password"], "Expected selections to match UserSchema fields")
    }

    func testDefaultValuesApplied() {
        let ageField = UserSchema.age
        
        if case let .integer(defaultValue) = ageField?.type {
            XCTAssertEqual(defaultValue, 0, "Expected default age to be 0")
        }
    }

    func testInvalidSchemaFields() throws {
        let invalidField = UserSchema.nonExistentField
        XCTAssertNil(invalidField, "Expected 'nonExistentField' to be nil in UserSchema")
    }
    
    func testSchemaFieldAccess() {
        let nameField = UserSchema.name
        XCTAssertNotNil(nameField, "Expected 'name' field to exist in UserSchema")
        
        let query = Query.from(UserSchema.schemaName)
            .where(UserSchema.name?.name ?? "", "=", "John Doe")
        
        XCTAssertEqual(query.table, "users", "Expected query to target 'users' table")
    }
}

