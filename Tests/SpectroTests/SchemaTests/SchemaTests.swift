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

        XCTAssertEqual(
            schemaName, "users",
            "Expected schema name 'users' but got \(schemaName)")
        XCTAssertEqual(
            fields.count, 12,
            "Expected 12 fields in User schema, but got \(fields.count)")

        let nameField = UserSchema.name
        XCTAssertNotNil(nameField, "Expected 'name' field in User schema")
        XCTAssertEqual(
            nameField?.type, .string,
            "Expected 'name' field to be of type string")

        let ageField = UserSchema.age
        XCTAssertNotNil(ageField, "Expected 'age' field in User schema")

        if case let .integer(defaultValue) = ageField?.type {
            XCTAssertEqual(
                defaultValue, 0, "Expected default value of 0 for 'age'")
        } else {
            XCTFail("Expected 'age' field to be of type integer")
        }

        let passwordField = UserSchema.password
        XCTAssertNotNil(
            passwordField, "Expected 'password' field in User schema")
        XCTAssertEqual(
            passwordField?.isRedacted, true,
            "Expected 'password' field to be redacted")
    }

    func testSchemaToQueryTranslation() throws {
        let query = Query.from(UserSchema.self)
            .select { [$0.age, $0.password, $0.name] }
            .where { $0.name.eq("John Doe") }

        XCTAssertEqual(
            query.schema.schemaName, "users", "Expected query table 'users'")
        XCTAssertEqual(
            query.selections, ["age", "password", "name"],
            "Expected selections to match UserSchema fields")
    }

    func testDefaultValuesApplied() {
        let ageField = UserSchema.age

        if case let .integer(defaultValue) = ageField?.type {
            XCTAssertEqual(defaultValue, 0, "Expected default age to be 0")
        }
    }

    func testInvalidSchemaFields() throws {
        let invalidField = UserSchema.nonExistentField
        XCTAssertNil(
            invalidField, "Expected 'nonExistentField' to be nil in UserSchema")
    }
}
