import Foundation
import Testing
import SpectroCore
@testable import Spectro

extension DatabaseIntegrationTests {
@Suite("Aggregate Queries")
struct AggregateQueryTests {

    private func withSeededTable(_ body: (GenericDatabaseRepo) async throws -> Void) async throws {
        let spectro = try TestDatabase.makeSpectro()
        let repo = spectro.repository()
        try await repo.executeRawSQL("""
            CREATE TABLE IF NOT EXISTS "test_users" (
                "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                "name" TEXT NOT NULL DEFAULT '',
                "email" TEXT NOT NULL DEFAULT '',
                "age" INT NOT NULL DEFAULT 0,
                "is_active" BOOLEAN NOT NULL DEFAULT true,
                "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        """)
        try await repo.executeRawSQL("TRUNCATE \"test_users\"")
        let _ = try await repo.insert(TestUser(name: "Alice", email: "alice@test.com", age: 30, isActive: true))
        let _ = try await repo.insert(TestUser(name: "Bob", email: "bob@test.com", age: 25, isActive: true))
        let _ = try await repo.insert(TestUser(name: "Charlie", email: "charlie@test.com", age: 35, isActive: false))
        do {
            try await body(repo)
        } catch {
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }

    private func withEmptyTable(_ body: (GenericDatabaseRepo) async throws -> Void) async throws {
        let spectro = try TestDatabase.makeSpectro()
        let repo = spectro.repository()
        try await repo.executeRawSQL("""
            CREATE TABLE IF NOT EXISTS "test_users" (
                "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                "name" TEXT NOT NULL DEFAULT '',
                "email" TEXT NOT NULL DEFAULT '',
                "age" INT NOT NULL DEFAULT 0,
                "is_active" BOOLEAN NOT NULL DEFAULT true,
                "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        """)
        try await repo.executeRawSQL("TRUNCATE \"test_users\"")
        do {
            try await body(repo)
        } catch {
            await spectro.shutdown()
            throw error
        }
        await spectro.shutdown()
    }

    // MARK: - Sum

    @Test("sum returns total of numeric field")
    func testSumReturnsTotal() async throws {
        try await withSeededTable { repo in
            let total = try await repo.query(TestUser.self).sum("age")
            #expect(total != nil)
            #expect(total == 90.0) // 30 + 25 + 35
        }
    }

    // MARK: - Avg

    @Test("avg returns average of numeric field")
    func testAvgReturnsAverage() async throws {
        try await withSeededTable { repo in
            let average = try await repo.query(TestUser.self).avg("age")
            #expect(average != nil)
            #expect(average == 30.0) // (30 + 25 + 35) / 3
        }
    }

    // MARK: - Min

    @Test("min returns minimum value of numeric field")
    func testMinReturnsMinimum() async throws {
        try await withSeededTable { repo in
            let minimum = try await repo.query(TestUser.self).min("age")
            #expect(minimum != nil)
            #expect(minimum == 25.0) // Bob's age
        }
    }

    // MARK: - Max

    @Test("max returns maximum value of numeric field")
    func testMaxReturnsMaximum() async throws {
        try await withSeededTable { repo in
            let maximum = try await repo.query(TestUser.self).max("age")
            #expect(maximum != nil)
            #expect(maximum == 35.0) // Charlie's age
        }
    }

    // MARK: - Empty table

    @Test("aggregates return nil on empty table")
    func testAggregateOnEmptyTableReturnsNil() async throws {
        try await withEmptyTable { repo in
            let sumResult = try await repo.query(TestUser.self).sum("age")
            let avgResult = try await repo.query(TestUser.self).avg("age")
            let minResult = try await repo.query(TestUser.self).min("age")
            let maxResult = try await repo.query(TestUser.self).max("age")
            #expect(sumResult == nil)
            #expect(avgResult == nil)
            #expect(minResult == nil)
            #expect(maxResult == nil)
        }
    }

    // MARK: - With WHERE clause

    @Test("aggregate with where clause only considers filtered rows")
    func testAggregateWithWhereClause() async throws {
        try await withSeededTable { repo in
            // Only active users: Alice (30) and Bob (25)
            let total = try await repo.query(TestUser.self)
                .where { $0.isActive == true }
                .sum("age")
            #expect(total == 55.0) // 30 + 25

            let average = try await repo.query(TestUser.self)
                .where { $0.isActive == true }
                .avg("age")
            #expect(average == 27.5) // (30 + 25) / 2

            let minimum = try await repo.query(TestUser.self)
                .where { $0.isActive == true }
                .min("age")
            #expect(minimum == 25.0) // Bob

            let maximum = try await repo.query(TestUser.self)
                .where { $0.isActive == true }
                .max("age")
            #expect(maximum == 30.0) // Alice
        }
    }
}
}
