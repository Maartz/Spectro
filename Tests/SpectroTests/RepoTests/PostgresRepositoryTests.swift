//
//  PostgresRepositoryTests.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import XCTest
import NIOCore
import PostgresKit
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
            .where("name", "LIKE", .string("John%"))
        
        let results = try await repository.all(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].values["name"], "John Doe")
        XCTAssertEqual(results[0].values["email"], "john@example.com")
    }
    
    func testInsertQuery() async throws {
        try await repository.insert(
            into: "test_users",
            values: [
                "name": .string("William Martin"),
                "email": .string("maartz@icloud.com")
            ]
        )
        
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name", "LIKE", .string("William%"))
        
        let results = try await repository.all(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].values["name"], "William Martin")
        XCTAssertEqual(results[0].values["email"], "maartz@icloud.com")
    }
    
    func testMultipleInsertsQuery() async throws {
        let users: [[String: ConditionValue]] = [
            [
                "name": .string("William Martin"),
                "email": .string("maartz@icloud.com")
            ],
            [
                "name": .string("Vincent Doe"),
                "email": .string("vincent@example.com")
            ],
            [
                "name": .string("Tyler Durden"),
                "email": .string("tyler@example.com")
            ]
        ]
        
        for user in users {
            try await repository.insert(into: "test_users", values: user)
        }
        
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name", "LIKE", .string("%Doe"))
        
        let results = try await repository.all(query: query)
        
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[2].values["name"], "Vincent Doe")
        XCTAssertEqual(results[2].values["email"], "vincent@example.com")
    }
    
    func testUpdateQuery() async throws {
        try await repository.insert(
            into: "test_users",
            values: [
                "name": .string("William Martin"),
                "email": .string("maartz@icloud.com")
            ]
        )
        
        try await repository.update(
            table: "test_users",
            values: [
                "name": .string("Maartz"),
                "email": .string("william@auroraeditor.com")
            ],
            where: ["email": ("=", .string("maartz@icloud.com"))]
        )
        
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name", "=", .string("Maartz"))
        
        let results = try await repository.all(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].values["name"], "Maartz")
        XCTAssertEqual(results[0].values["email"], "william@auroraeditor.com")
    }
    
    func testDeleteQuery() async throws {
        try await repository.insert(
            into: "test_users",
            values: [
                "name": .string("Tyler Durden"),
                "email": .string("tyler@example.com")
            ]
        )
        
        let initialCount = try await repository.count(from: "test_users")
        XCTAssertEqual(initialCount, 3) // 2 from setup + 1 inserted
        
        try await repository.delete(
            from: "test_users",
            where: ["name": ("=", .string("Tyler Durden"))]
        )
        
        let finalCount = try await repository.count(from: "test_users")
        XCTAssertEqual(finalCount, 2)
        
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name", "=", .string("Tyler Durden"))
        
        let results = try await repository.all(query: query)
        XCTAssertEqual(results.count, 0)
    }
    
    func testRepoCount() async throws {
        let initialCount = try await repository.count(
            from: "test_users",
            where: ["name": ("LIKE", .string("%Doe"))]
        )
        XCTAssertEqual(initialCount, 2)
        
        try await repository.insert(
            into: "test_users",
            values: [
                "name": .string("Vincent Doe"),
                "email": .string("vincent@example.com")
            ]
        )
        
        let finalCount = try await repository.count(
            from: "test_users",
            where: ["name": ("LIKE", .string("%Doe"))]
        )
        XCTAssertEqual(finalCount, 3)
    }
    
    func testGetQuery() async throws {
        let table = "test_users"
        let columns = ["name", "email"]
        let conditions: [String: (String, ConditionValue)] = [
            "name": ("=", .string("John Doe"))
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
            "name": ("=", .string("John Doe"))
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
                where: ["name": ("LIKE", .string("%Doe"))]
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
}
