import NIOCore
import PostgresKit
import XCTest

@testable import Spectro

final class RepoTests: XCTestCase {
    var repo: Repo!
    var pools: EventLoopGroupConnectionPool<PostgresConnectionSource>!
    var eventLoop: EventLoopGroup!
    
    override func setUp() async throws {
        eventLoop = MultiThreadedEventLoopGroup(
            numberOfThreads: System.coreCount)
        
        let config = SQLPostgresConfiguration(
            hostname: "localhost",
            port: 5432,
            username: "postgres",
            password: "postgres",
            database: "postgres",
            tls: .disable
        )
        
        let source = PostgresConnectionSource(sqlConfiguration: config)
        pools = EventLoopGroupConnectionPool(source: source, on: eventLoop)
        
        repo = Repo(pools: pools)
        
        try await pools.withConnection { conn -> EventLoopFuture<Void> in
            return conn.sql()
                .raw(
                    SQLQueryString(
                        """
                            CREATE TABLE IF NOT EXISTS test_users (
                                id SERIAL PRIMARY KEY,
                                name TEXT NOT NULL,
                                email TEXT NOT NULL
                            )
                        """)
                )
                .run()
                .flatMap { _ in
                    conn.sql()
                        .raw(
                            SQLQueryString(
                                """
                                    INSERT INTO test_users (name, email) VALUES
                                    ('John Doe', 'john@example.com'),
                                    ('Jane Doe', 'jane@example.com')
                                """)
                        )
                        .run()
                }
        }.get()
    }
    
    override func tearDown() async throws {
        try await pools.withConnection { conn -> EventLoopFuture<Void> in
            conn.sql()
                .raw(SQLQueryString("DROP TABLE IF EXISTS test_users"))
                .run()
        }.get()
        
        try await pools.shutdownAsync()
        try await eventLoop.shutdownGracefully()
    }
    
    func testBasicQuery() async throws {
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name", "LIKE", .string("John%"))
        
        let results = try await repo.all(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].values["name"], "John Doe")
        XCTAssertEqual(results[0].values["email"], "john@example.com")
    }

    func testInsertQuery() async throws {
        try await repo.insert(
            into: "test_users",
            values: ["name": .string("William Martin"), "email": .string("maartz@icloud.com")]
        )

        let query = Query.from("test_users")
            .select("name", "email")
            .where("name", "LIKE", .string("William%"))
        
        let results = try await repo.all(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].values["name"], "William Martin")
        XCTAssertEqual(results[0].values["email"], "maartz@icloud.com")
    }

    func testMultipleInsertsQuery() async throws {
        let users : [[String: ConditionValue]] = [
            ["name": .string("William Martin"), "email": .string("maartz@icloud.com")],
            ["name": .string("Vincent Doe"), "email": .string("vincent@example.com")],
            ["name": .string("Tyler Durden"), "email": .string("tyler@example.com")],
        ]
        
        for user in users {
            try await repo.insert(
                into: "test_users",
                values: user
            )
        }
        
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name", "LIKE", .string("%Doe"))
        
        let results = try await repo.all(query: query)
        
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[2].values["name"], "Vincent Doe")
        XCTAssertEqual(results[2].values["email"], "vincent@example.com")
    }

    func testUpdateQuery() async throws {
        let users: [[String: ConditionValue]] = [
            ["name": .string("William Martin"), "email": .string("maartz@icloud.com")],
            ["name": .string("Vincent Doe"), "email": .string("vincent@example.com")],
            ["name": .string("Tyler Durden"), "email": .string("tyler@example.com")],
        ]
        
        for user in users {
            try await repo.insert(
                into: "test_users",
                values: user
            )
        }
        
        var query = Query.from("test_users")
            .select("name", "email")
            .where("name", "LIKE", .string("%Martin"))
        
        var results = try await repo.all(query: query)
        XCTAssertEqual(results.count, 1)
        
        // Updated values dictionary to use ConditionValue types
        try await repo.update(
            table: "test_users",
            values: ["name": .string("Maartz"), "email": .string("william@auroraeditor.com")],
            where: ["name": ("=", .string("William Martin"))]
        )
        
        results = try await repo.all(query: query)
        XCTAssertEqual(results.count, 0)
        
        query = Query.from("test_users")
            .select("name", "email")
            .where("name", "=", .string("Maartz"))
        results = try await repo.all(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].values["name"], "Maartz")
        XCTAssertEqual(results[0].values["email"], "william@auroraeditor.com")
    }


    func testDeleteQuery() async throws {
        let users : [[String: ConditionValue]] = [
            ["name": .string("William Martin"), "email": .string("maartz@icloud.com")],
            ["name": .string("Vincent Doe"), "email": .string("vincent@example.com")],
            ["name": .string("Tyler Durden"), "email": .string("tyler@example.com")],
        ]
        
        for user in users {
            try await repo.insert(
                into: "test_users",
                values: user
            )
        }
        
        var query = Query.from("test_users")
            .select("name", "email")
        var results = try await repo.all(query: query)
        XCTAssertEqual(results.count, 5) // because of the setup initial seeding
        
        try await repo.delete(from: "test_users", where: ["name": ("=", .string("Tyler Durden"))])
        
        results = try await repo.all(query: query)
        XCTAssertEqual(results.count, 4)
        
        query = Query.from("test_users")
            .select("name", "email")
            .where("name", "=", .string("Tyler Durden"))
        results = try await repo.all(query: query)
        XCTAssertEqual(results.count, 0)
    }
   
    func testRepoCount() async throws {
        var count = try await repo.count(from: "test_users", where: ["name": ("LIKE", .string("%Doe"))])
        XCTAssertEqual(count, 2)
        
        let users : [[String: ConditionValue]] = [
            ["name": .string("William Martin"), "email": .string("maartz@icloud.com")],
            ["name": .string("Vincent Doe"), "email": .string("vincent@example.com")],
            ["name": .string("Tyler Durden"), "email": .string("tyler@example.com")],
        ]
        
        for user in users {
            try await repo.insert(
                into: "test_users",
                values: user
            )
        }
        count = try await repo.count(from: "test_users", where: ["email": ("LIKE", .string("%example.com"))])
        XCTAssertEqual(count, 4)
    }
}
