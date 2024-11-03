//
//  PostgresRepositoryTests.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import XCTest
import NIOCore
import PostgresKit
import Foundation
@testable import Spectro

final class PostgresRepositoryTests: XCTestCase {
    var database: TestDatabase!
    var repository: PostgresRepository!
    
    override func setUp() async throws {
        database = try TestDatabase()
        repository = PostgresRepository(pools: database.pools)
        try await database.setupTestTable()
    }
    
    override func tearDown() async throws {
        try await database.tearDownTestTable()
        try await database.shutdown()
    }
    
    func testBasicQuery() async throws {
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name", "LIKE", "John%")
        
        let results = try await repository.all(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].values["name"], "John Doe")
        XCTAssertEqual(results[0].values["email"], "john@example.com")
    }
    
    func testInsertQuery() async throws {
        try await repository.insert(
            into: "test_users",
            values: [
                "name": "William Martin",
                "email": "maartz@icloud.com"
            ]
        )
        
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name", "LIKE", "William%")
        
        let results = try await repository.all(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].values["name"], "William Martin")
        XCTAssertEqual(results[0].values["email"], "maartz@icloud.com")
    }
    
    func testMultipleInsertsQuery() async throws {
        let users: [[String: ConditionValue]] = [
            [
                "name": "William Martin",
                "email": "maartz@icloud.com"
            ],
            [
                "name": "Vincent Doe",
                "email": "vincent@example.com"
            ],
            [
                "name": "Tyler Durden",
                "email": "tyler@example.com"
            ]
        ]
        
        for user in users {
            try await repository.insert(into: "test_users", values: user)
        }
        
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name", "LIKE", "%Doe")
        
        let results = try await repository.all(query: query)
        
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[2].values["name"], "Vincent Doe")
        XCTAssertEqual(results[2].values["email"], "vincent@example.com")
    }
    
    func testUpdateQuery() async throws {
        try await repository.insert(
            into: "test_users",
            values: [
                "name": "William Martin",
                "email": "maartz@icloud.com"
            ]
        )
        
        try await repository.update(
            table: "test_users",
            values: [
                "name": "Maartz",
                "email": "william@auroraeditor.com"
            ],
            where: ["email": ("=", "maartz@icloud.com")]
        )
        
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name", "=", "Maartz")
        
        let results = try await repository.all(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].values["name"], "Maartz")
        XCTAssertEqual(results[0].values["email"], "william@auroraeditor.com")
    }
    
    func testDeleteQuery() async throws {
        try await repository.insert(
            into: "test_users",
            values: [
                "name": "Tyler Durden",
                "email": "tyler@example.com"
            ]
        )
        
        let initialCount = try await repository.count(from: "test_users")
        XCTAssertEqual(initialCount, 3) // 2 from setup + 1 inserted
        
        try await repository.delete(
            from: "test_users",
            where: ["name": ("=", "Tyler Durden")]
        )
        
        let finalCount = try await repository.count(from: "test_users")
        XCTAssertEqual(finalCount, 2)
        
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name", "=", "Tyler Durden")
        
        let results = try await repository.all(query: query)
        XCTAssertEqual(results.count, 0)
    }
    
    func testRepoCount() async throws {
        let initialCount = try await repository.count(
            from: "test_users",
            where: ["name": ("LIKE", "%Doe")]
        )
        XCTAssertEqual(initialCount, 2)
        
        try await repository.insert(
            into: "test_users",
            values: [
                "name": "Vincent Doe",
                "email": "vincent@example.com"
            ]
        )
        
        let finalCount = try await repository.count(
            from: "test_users",
            where: ["name": ("LIKE", "%Doe")]
        )
        XCTAssertEqual(finalCount, 3)
    }
    
    func testGetQuery() async throws {
        let table = "test_users"
        let columns = ["name", "email"]
        let conditions: [String: (String, ConditionValue)] = [
            "name": ("=", "John Doe")
        ]

        let result = try await repository.get(from: table, selecting: columns, where: conditions)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.values["name"], "John Doe")
        XCTAssertEqual(result?.values["email"], "john@example.com")
    }

    func testOneQuery() async throws {
        let table = "test_users"
        let columns = ["name", "email"]
        let conditions: [String: (String, ConditionValue)] = [
            "name": ("=", "John Doe")
        ]
        
        let result = try await repository.one(
            from: table,
            selecting: columns,
            where: conditions
        )
        
        XCTAssertEqual(result.values["name"], "John Doe")
        XCTAssertEqual(result.values["email"], "john@example.com")
        
        do {
            _ = try await repository.one(
                from: table,
                selecting: columns,
                where: ["name": ("LIKE", "%Doe")]
            )
            XCTFail("Expected error to be thrown")
        } catch {
            guard let repoError = error as? RepositoryError,
                  case .unexpectedResultCount = repoError else {
                XCTFail("Expected unexpectedResultCount error, got \(error)")
                return
            }
        }
    }
    
    func testCompleteUserFlow() async throws {
        let userId = UUID()
        let now = Date.now
        
        try await repository.insert(
            into: "test_users",
            values: .with([
                "id": userId,
                "name": "William Martin",
                "email": "will@test.com",
                "age": 28,
                "score": 95.5,
                "is_active": true,
                "created_at": now,
                "login_count": 0,
                "preferences": "{\"theme\": \"dark\"}"
            ])
        )
        
        let query = Query.from("test_users")
            .select("name", "email", "age", "score", "is_active", "login_count")
            .where("age", ">", 25)
            .where("score", ">=", 90.0)
            .where("is_active", "=", true)
        
        let results = try await repository.all(query: query)
        XCTAssertEqual(results.count, 2)
        
        try await repository.update(
            table: "test_users",
            values: .with([
                "score": 98.0,
                "login_count": 1,
                "last_login_at": now,
                "updated_at": now
            ]),
            where: .conditions([
                "id": ("=", userId)
            ])
        )
        
        let updated = try await repository.one(
            from: "test_users",
            selecting: ["score", "login_count", "last_login_at", "updated_at"],
            where: .conditions(["id": ("=", userId)])
        )
        
        XCTAssertEqual(Double(updated.values["score"] ?? "0"), 98.0)
        XCTAssertEqual(Int(updated.values["login_count"] ?? "0"), 1)
        
        try await repository.update(
            table: "test_users",
            values: .with(["deleted_at": now]),
            where: .conditions(["id": ("=", userId)])
        )
        
        let deletedUser = try await repository.get(
            from: "test_users",
            selecting: ["name", "deleted_at"],
            where: .conditions(["id": ("=", userId)])
        )
        
        XCTAssertNotNil(deletedUser)
        XCTAssertNotNil(deletedUser?.values["deleted_at"])
    }

    func testNullableFields() async throws {
        let userId = UUID()
        
        try await repository.insert(
            into: "test_users",
            values: .with([
                "id": userId,
                "name": "Test User",
                "email": "test@example.com"
            ])
        )
        
        let query = Query.from("test_users")
            .select("id", "name", "age")
            .where("age", "IS", .null)
        
        let results = try await repository.all(query: query)
        
        XCTAssertEqual(results.count, 1, "Expected to find 1 result where 'age' is NULL, but found \(results.count)")
        XCTAssertEqual(UUID(uuidString: results[0].values["id"] ?? ""), userId, "Expected UUID to match \(userId)")
    }
}
