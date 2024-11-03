//
//  DatabaseOperation.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import PostgresKit
import NIOCore

final class PostgresDatabaseOperations: DatabaseOperations {
    private let pools: EventLoopGroupConnectionPool<PostgresConnectionSource>
    
    init(pools: EventLoopGroupConnectionPool<PostgresConnectionSource>) {
        self.pools = pools
    }
    
    func executeQuery<T: Sendable>(
        sql: String,
        params: [PostgresData] = [],
        resultMapper: @Sendable @escaping (PostgresRow) throws -> T
    ) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let future: EventLoopFuture<[T]> = pools.withConnection { conn in
                conn.query(sql, params).flatMapThrowing { result in
                    let processedRows = try result.rows.map(resultMapper)
                    return Array(processedRows)
                }
            }
            
            future.whenComplete { result in
                switch result {
                case .success(let rows):
                    let safeCopy = Array(rows)
                    continuation.resume(returning: safeCopy)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func executeUpdate(sql: String, params: [PostgresData]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let future: EventLoopFuture<Void> = pools.withConnection { conn in
                conn.query(sql, params).map { _ in }
            }
            
            future.whenComplete { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
