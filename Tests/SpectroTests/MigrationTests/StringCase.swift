//
//  StringCase.swift
//  Spectro
//
//  Created by William MARTIN on 11/16/24.
//

@testable import SpectroCore
import XCTest

final class StringCaseTests: XCTestCase {
    func testSnakeCase() {
        XCTAssertEqual("createUsersTable".snakeCase(), "create_users_table")
        XCTAssertEqual("APIResponse".snakeCase(), "apiresponse")
        XCTAssertEqual("Create Users Table".snakeCase(), "create_users_table")
        XCTAssertEqual("create-users-table".snakeCase(), "create_users_table")
        XCTAssertEqual("already_snake_case".snakeCase(), "already_snake_case")
        XCTAssertEqual("CreateUsers-Table Space".snakeCase(), "create_users_table_space")
    }
    
    func testPascalCase() {
        XCTAssertEqual("create_users_table".pascalCase(), "CreateUsersTable")
        XCTAssertEqual("create users table".pascalCase(), "CreateUsersTable")
        XCTAssertEqual("create-users-table".pascalCase(), "CreateUsersTable")
        XCTAssertEqual("CreateUsersTable".pascalCase(), "CreateUsersTable")
        XCTAssertEqual("create_Users-table SPACE".pascalCase(), "CreateUsersTableSpace")
    }
}
