//
//  TestHelpers.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import PostgresKit
import NIOCore
import XCTest
@testable import Spectro

final class TestDatabase {
    let eventLoop: EventLoopGroup
    let pools: EventLoopGroupConnectionPool<PostgresConnectionSource>
    
    init() throws {
        self.eventLoop = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        
        let config = SQLPostgresConfiguration(
            hostname: "localhost",
            port: 5432,
            username: "postgres",
            password: "postgres",
            database: "postgres",
            tls: .disable
        )
        
        let source = PostgresConnectionSource(sqlConfiguration: config)
        self.pools = EventLoopGroupConnectionPool(source: source, on: eventLoop)
    }
    
    func shutdown() async throws {
        try await pools.shutdownAsync()
        try await eventLoop.shutdownGracefully()
    }
    
    func setupTestTable() async throws {
        try await pools.withConnection { conn -> EventLoopFuture<Void> in
            conn.sql()
                .raw(SQLQueryString("""
                    CREATE TABLE IF NOT EXISTS test_users (
                        id SERIAL PRIMARY KEY,
                        name TEXT NOT NULL,
                        email TEXT NOT NULL
                    )
                """))
                .run()
                .flatMap { _ in
                    conn.sql()
                        .raw(SQLQueryString("""
                            INSERT INTO test_users (name, email) VALUES
                            ('John Doe', 'john@example.com'),
                            ('Jane Doe', 'jane@example.com')
                        """))
                        .run()
                }
        }.get()
    }
    
    func tearDownTestTable() async throws {
        try await pools.withConnection { conn -> EventLoopFuture<Void> in
            conn.sql()
                .raw(SQLQueryString("DROP TABLE IF EXISTS test_users"))
                .run()
        }.get()
    }
}
