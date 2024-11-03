//
//  PostgresRepository.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import PostgresKit

public final class PostgresRepository: Repository {
    private let db: DatabaseOperations
    
    public init(pools: EventLoopGroupConnectionPool<PostgresConnectionSource>) {
        self.db = PostgresDatabaseOperations(pools: pools)
    }
    
    public func all(query: Query) async throws -> [DataRow] {
        let whereClause = SQLBuilder.buildWhereClause(query.conditions)
        let sql = """
            SELECT \(query.selections.joined(separator: ", ")) FROM \(query.table)
            \(query.conditions.isEmpty ? "" : "WHERE " + whereClause.clause)
            """
        
        return try await db.executeQuery(sql: sql, params: whereClause.params) { row in
            let randomAccessRow = row.makeRandomAccess()
            var dict: [String: String] = [:]
            for column in query.selections {
                if let columnValue = randomAccessRow[data: column].string {
                    dict[column] = columnValue
                }
            }
            return DataRow(values: dict)
        }
    }
    
    public func insert(into table: String, values: [String: ConditionValue]) async throws {
        let query = SQLBuilder.buildInsert(table: table, values: values)
        try await db.executeUpdate(sql: query.sql, params: query.params)
    }
    
    public func update(
        table: String,
        values: [String: ConditionValue],
        where conditions: [String: (String, ConditionValue)]
    ) async throws {
        let query = SQLBuilder.buildUpdate(table: table, values: values, where: conditions)
        try await db.executeUpdate(sql: query.sql, params: query.params)
    }
    
    public func delete(
        from table: String,
        where conditions: [String: (String, ConditionValue)] = [:]
    ) async throws {
        let sql: String
        let params: [PostgresData]
        
        if conditions.isEmpty {
            sql = "DELETE FROM \(table)"
            params = []
        } else {
            let whereClause = SQLBuilder.buildWhereClause(conditions)
            sql = "DELETE FROM \(table) WHERE \(whereClause.clause)"
            params = whereClause.params
        }
        
        try await db.executeUpdate(sql: sql, params: params)
    }
    
    public func count(
        from table: String,
        where conditions: [String: (String, ConditionValue)] = [:]
    ) async throws -> Int {
        let whereClause = SQLBuilder.buildWhereClause(conditions)
        let sql = """
            SELECT COUNT(*) AS count FROM \(table)
            \(conditions.isEmpty ? "" : "WHERE " + whereClause.clause)
            """
        
        let rows: [Int] = try await db.executeQuery(
            sql: sql, params: whereClause.params
        ) { row in
            let randomAccessRow = row.makeRandomAccess()
            guard let count = randomAccessRow[data: "count"].int else {
                throw RepositoryError.invalidQueryResult
            }
            return count
        }
        return rows.first ?? 0
    }
}
