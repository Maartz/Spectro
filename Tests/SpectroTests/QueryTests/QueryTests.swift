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
        let query = Query.from("users")
        XCTAssertEqual(query.table, "users", "The table name should be 'users'")
    }

    func testQueryWhereClause() {
        let query = Query.from("users").where("age > 18")
        XCTAssertEqual(
            query.conditions.count, 1, "There should be one condition")
        XCTAssertEqual(
            query.conditions.first, "age > 18",
            "The condition should be 'age > 18'")

        let queryWithMultipleConditions = query.where("is_active = true")
        XCTAssertEqual(
            queryWithMultipleConditions.conditions.count, 2,
            "There should be two conditions")
        XCTAssertEqual(
            queryWithMultipleConditions.conditions[1], "is_active = true",
            "The second condition should be 'is_active = true'")
    }

    func testQuerySelectClause() {
        let query = Query.from("users").select("name", "email")
        XCTAssertEqual(
            query.selections.count, 2, "There should be two selected columns")
        XCTAssertEqual(
            query.selections, ["name", "email"],
            "Selections should be ['name', 'email']")

        let defaultQuery = Query.from("users")
        XCTAssertEqual(
            defaultQuery.selections, ["*"], "Default selection should be '*'")
    }
}
