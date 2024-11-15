//
//  QueryTests.swift
//  Spectro
//
//  Created by William MARTIN on 11/1/24.
//

import XCTest

@testable import Spectro

final class QueryTests: XCTestCase {

    func testQueryFromClause() {
        let query = Query.from(UserSchema.self)
        XCTAssertEqual(
            query.schema.schemaName, "users", "The table name should be 'users'"
        )
    }

    func testQueryWhereClause() {
        let query = Query.from(UserSchema.self).where("age", ">", 18)

        XCTAssertEqual(
            query.conditions.count, 1, "There should be one condition")
        XCTAssertEqual(
            query.conditions["age"]?.0, ">",
            "The operator should be '>' for age condition")
        XCTAssertEqual(
            query.conditions["age"]?.1, .int(18),
            "The value should be 18 for age condition")

        let queryWithMultipleConditions = query.where(
            "is_active", "=", .bool(true))
        XCTAssertEqual(
            queryWithMultipleConditions.conditions.count, 2,
            "There should be two conditions")
        XCTAssertEqual(
            queryWithMultipleConditions.conditions["is_active"]?.0, "=",
            "The operator should be '=' for is_active condition")
        XCTAssertEqual(
            queryWithMultipleConditions.conditions["is_active"]?.1, .bool(true),
            "The value should be true for is_active condition")
    }

    func testQuerySelectClause() {
        let query = Query.from(UserSchema.self).select { ["name", "email"] }
        XCTAssertEqual(
            query.selections.count, 2, "There should be two selected columns")
        XCTAssertEqual(
            query.selections, ["name", "email"],
            "Selections should be ['name', 'email']")

        let defaultQuery = Query.from(UserSchema.self)
        XCTAssertEqual(
            defaultQuery.selections, ["*"], "Default selection should be '*'")
    }
}
