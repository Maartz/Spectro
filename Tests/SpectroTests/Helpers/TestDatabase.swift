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
            database: "spectro_test",
            tls: .disable
        )

        let source = PostgresConnectionSource(sqlConfiguration: config)
        self.pools = EventLoopGroupConnectionPool(source: source, on: eventLoop)
    }

    func shutdown() async throws {
        try await pools.shutdownAsync()
        try await eventLoop.shutdownGracefully()
    }

    // Database schema setup should be done externally
    // This class only provides connection management
}
