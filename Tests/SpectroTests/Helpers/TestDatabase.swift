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
                                        id, name, email, age, password, score,
                                        is_active, created_at, login_count
                                    ) VALUES
                                    (
                                        '123e4567-e89b-12d3-a456-426614174000',
                                        'John Doe',
                                        'john@example.com',
                                        25,
                                        'password123',
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
                                        'password456',
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
                .flatMap { _ in
                    // Create posts table
                    conn.sql()
                        .raw(
                            SQLQueryString(
                                """
                                CREATE TABLE IF NOT EXISTS posts (
                                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                                    title TEXT NOT NULL,
                                    content TEXT NOT NULL,
                                    published BOOLEAN DEFAULT false,
                                    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                                    updated_at TIMESTAMPTZ
                                )
                                """)
                        )
                        .run()
                }
                .flatMap { _ in
                    // Create comments table
                    conn.sql()
                        .raw(
                            SQLQueryString(
                                """
                                CREATE TABLE IF NOT EXISTS comments (
                                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                                    content TEXT NOT NULL,
                                    approved BOOLEAN DEFAULT false,
                                    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
                                    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                                )
                                """)
                        )
                        .run()
                }
                .flatMap { _ in
                    // Insert test posts
                    conn.sql()
                        .raw(
                            SQLQueryString(
                                """
                                INSERT INTO posts (id, title, content, published, user_id) VALUES
                                ('11111111-1111-1111-1111-111111111111', 'First Post', 'Content of first post', true, '123e4567-e89b-12d3-a456-426614174000'),
                                ('22222222-2222-2222-2222-222222222222', 'Second Post', 'Content of second post', false, '123e4567-e89b-12d3-a456-426614174000'),
                                ('33333333-3333-3333-3333-333333333333', 'Third Post', 'Content of third post', true, '987fcdeb-51a2-43d7-9b18-315274198000')
                                ON CONFLICT (id) DO NOTHING
                                """)
                        )
                        .run()
                }
                .flatMap { _ in
                    // Insert test comments
                    conn.sql()
                        .raw(
                            SQLQueryString(
                                """
                                INSERT INTO comments (id, content, approved, post_id, user_id) VALUES
                                ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Great post!', true, '11111111-1111-1111-1111-111111111111', '987fcdeb-51a2-43d7-9b18-315274198000'),
                                ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Nice work', false, '11111111-1111-1111-1111-111111111111', '123e4567-e89b-12d3-a456-426614174000'),
                                ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Interesting', true, '33333333-3333-3333-3333-333333333333', '123e4567-e89b-12d3-a456-426614174000')
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
                .raw(SQLQueryString("DROP TABLE IF EXISTS comments CASCADE"))
                .run()
                .flatMap { _ in
                    conn.sql()
                        .raw(SQLQueryString("DROP TABLE IF EXISTS posts CASCADE"))
                        .run()
                }
                .flatMap { _ in
                    conn.sql()
                        .raw(SQLQueryString("DROP TABLE IF EXISTS users CASCADE"))
                        .run()
                }
        }.get()
    }
}
