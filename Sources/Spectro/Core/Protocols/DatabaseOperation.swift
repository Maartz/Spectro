//
//  DatabaseOperation.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import NIOCore
import PostgresKit

protocol DatabaseOperations {
    func executeQuery<T: Sendable>(
        sql: String,
        params: [PostgresData],
        resultMapper: @Sendable @escaping (PostgresRow) throws -> T
    ) async throws -> [T]

    func executeUpdate(sql: String, params: [PostgresData]) async throws
}
