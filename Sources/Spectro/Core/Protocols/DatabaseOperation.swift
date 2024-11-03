//
//  DatabaseOperation.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import PostgresKit
import NIOCore

public protocol DatabaseOperations {
    func executeQuery<T: Sendable>(
        sql: String,
        params: [PostgresKit.PostgresData],
        resultMapper: @Sendable @escaping (PostgresKit.PostgresRow) throws -> T
    ) async throws -> [T]
    
    func executeUpdate(
        sql: String,
        params: [PostgresKit.PostgresData]
    ) async throws
}
