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
            .where("name LIKE 'John%'")
        
        let results = try await repo.all(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].values["name"], "John Doe")
        XCTAssertEqual(results[0].values["email"], "john@example.com")
    }
    
    func testInsertQuery() async throws {
        try await repo.insert(
            into: "test_users",
            values: ["name": "William Martin", "email": "maartz@icloud.com"]
        )
        
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name LIKE 'William%'")
        
        let results = try await repo.all(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].values["name"], "William Martin")
        XCTAssertEqual(results[0].values["email"], "maartz@icloud.com")
    }
    
    func testMultipleInsertsQuery() async throws {
        let users = [
            ["name": "William Martin", "email": "maartz@icloud.com"],
            ["name": "Vincent Doe", "email": "vincent@example.com"],
            ["name": "Tyler Durden", "email": "tyler@example.com"],
        ]
        
        for user in users {
            try await repo.insert(
                into: "test_users",
                values: user
            )
        }
        
        let query = Query.from("test_users")
            .select("name", "email")
            .where("name LIKE '%Doe'")
        
        let results = try await repo.all(query: query)
        
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[2].values["name"], "Vincent Doe")
        XCTAssertEqual(results[2].values["email"], "vincent@example.com")
    }
    
    func testUpdateQuery() async throws {
        let users = [
            ["name": "William Martin", "email": "maartz@icloud.com"],
            ["name": "Vincent Doe", "email": "vincent@example.com"],
            ["name": "Tyler Durden", "email": "tyler@example.com"],
        ]
        
        for user in users {
            try await repo.insert(
                into: "test_users",
                values: user
            )
        }
        
        var query = Query.from("test_users")
            .select("name", "email")
            .where("name LIKE '%Martin'")
        
        var results = try await repo.all(query: query)
        XCTAssertEqual(results.count, 1)
        
        try await repo.update(into: "test_users", values: ["name": "Maartz", "email": "william@auroraeditor.com"], where: ["name": "William Martin"])
        
        results = try await repo.all(query: query)
        XCTAssertEqual(results.count, 0)
        
        query = Query.from("test_users")
            .select("name", "email")
            .where("name = 'Maartz'")
        results = try await repo.all(query: query)
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].values["name"], "Maartz")
        XCTAssertEqual(results[0].values["email"], "william@auroraeditor.com")
    }
    
    func testDeleteQuery() async throws {
        let users = [
            ["name": "William Martin", "email": "maartz@icloud.com"],
            ["name": "Vincent Doe", "email": "vincent@example.com"],
            ["name": "Tyler Durden", "email": "tyler@example.com"],
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
        
        try await repo.delete(from: "test_users", where: ["name": "Tyler Durden"])
        
        results = try await repo.all(query: query)
        XCTAssertEqual(results.count, 4)
        
        query = Query.from("test_users")
            .select("name", "email")
            .where("name = 'Tyler Durden'")
        results = try await repo.all(query: query)
        XCTAssertEqual(results.count, 0)
    }
   
    func testRepoCount() async throws {
        var count = try await repo.count(from: "test_users", where: ["name": ("LIKE", "%Doe")])
        XCTAssertEqual(count, 2)
        
        let users = [
            ["name": "William Martin", "email": "maartz@icloud.com"],
            ["name": "Vincent Doe", "email": "vincent@example.com"],
            ["name": "Tyler Durden", "email": "tyler@example.com"],
        ]
        
        for user in users {
            try await repo.insert(
                into: "test_users",
                values: user
            )
        }
        count = try await repo.count(from: "test_users", where: ["email": ("LIKE", "%example.com")])
        XCTAssertEqual(count, 4)
    }
}
