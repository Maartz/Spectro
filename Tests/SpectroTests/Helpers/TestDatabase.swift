//
//  TestHelpers.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import NIOCore
import PostgresKit
import XCTest

final class TestDatabase: @unchecked Sendable {
    let eventLoop: EventLoopGroup
    let pools: EventLoopGroupConnectionPool<PostgresConnectionSource>

    init() throws {
        self.eventLoop = MultiThreadedEventLoopGroup(
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
        self.pools = EventLoopGroupConnectionPool(source: source, on: eventLoop)
    }

    func shutdown() async throws {
        try await pools.shutdownAsync()
        try await eventLoop.shutdownGracefully()
    }

    func setupTestTable() async throws {
        try await pools.withConnection { conn -> EventLoopFuture<Void> in
            conn.sql()
                .raw(
                    SQLQueryString(
                        """
                            CREATE TABLE IF NOT EXISTS users (
                                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                                name TEXT NOT NULL,
                                email TEXT NOT NULL,
                                age INT,
                                password TEXT NOT NULL,
                                score DOUBLE PRECISION,
                                is_active BOOLEAN DEFAULT true,
                                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                updated_at TIMESTAMPTZ,
                                deleted_at TIMESTAMPTZ,
                                login_count INT DEFAULT 0,
                                last_login_at TIMESTAMPTZ,
                                preferences JSONB DEFAULT '{}'::jsonb
                            )
                        """)
                )
                .run()
                .flatMap { _ in
                    conn.sql()
                        .raw(
                            SQLQueryString(
                                """
                                    INSERT INTO users (
                                        id, name, email, age, score,
                                        is_active, created_at, login_count
                                    ) VALUES
                                    (
                                        '123e4567-e89b-12d3-a456-426614174000',
                                        'John Doe',
                                        'john@example.com',
                                        25,
                                        'FOO',
                                        85.5,
                                        true,
                                        NOW(),
                                        0
                                    ),
                                    (
                                        '987fcdeb-51a2-43d7-9b18-315274198000',
                                        'Jane Doe',
                                        'jane@example.com',
                                        30,
                                        'FOO',
                                        92.5,
                                        true,
                                        NOW(),
                                        5
                                    )
                                    ON CONFLICT (id) DO NOTHING
                                """)
                        )
                        .run()
                }
        }.get()
    }

    func tearDownTestTable() async throws {
        try await pools.withConnection { conn -> EventLoopFuture<Void> in
            conn.sql()
                .raw(SQLQueryString("DROP TABLE IF EXISTS users"))
                .run()
        }.get()
    }
}
