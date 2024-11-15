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

    // This one takes a Query, I'd like to make the rest look like this in the DX.
    // As insert expects you to provide everything whereas I want to
    // let query = Query(from f in Foo)
    // insert(query: query) for example
    // at a given point we should reflect Schema to build the queries such as
    // get_by_* where * is a field of the schema
    public func all(query: Query) async throws -> [DataRow] {
        let whereClause = SQLBuilder.buildWhereClause(query.conditions)
        let orderClause =
            query.orderBy.isEmpty
            ? ""
            : " ORDER BY "
                + query.orderBy.map { "\($0.field) \($0.direction.sql)" }
                .joined(separator: ", ")
        let limitClause = query.limit.map { " LIMIT \($0)" } ?? ""
        let offsetClause = query.offset.map { " OFFSET \($0)" } ?? ""

        let sql = """
            SELECT \(query.selections.joined(separator: ", ")) FROM \(query.table)
            \(query.conditions.isEmpty ? "" : "WHERE " + whereClause.clause)
            \(orderClause)\(limitClause)\(offsetClause)
            """

        return try await db.executeQuery(sql: sql, params: whereClause.params) {
            row in
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

    public func insert(into table: String, values: [String: ConditionValue])
        async throws
    {
        let query = SQLBuilder.buildInsert(table: table, values: values)
        try await db.executeUpdate(sql: query.sql, params: query.params)
    }

    public func update(
        table: String,
        values: [String: ConditionValue],
        where conditions: [String: (String, ConditionValue)]
    ) async throws {
        let query = SQLBuilder.buildUpdate(
            table: table, values: values, where: conditions)
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

    public func get(
        from table: String,
        selecting columns: [String],
        where conditions: [String: (String, ConditionValue)]
    ) async throws -> DataRow? {
        let whereClause = SQLBuilder.buildWhereClause(conditions)
        let sql = """
            SELECT \(columns.joined(separator: ", ")) FROM \(table)
            \(conditions.isEmpty ? "" : "WHERE " + whereClause.clause)
            LIMIT 1
            """

        let results: [DataRow] = try await db.executeQuery(
            sql: sql, params: whereClause.params
        ) { row in
            let randomAccessRow = row.makeRandomAccess()
            var dict: [String: String] = [:]
            for column in columns {
                if let columnValue = randomAccessRow[data: column].string {
                    dict[column] = columnValue
                }
            }
            return DataRow(values: dict)
        }

        return results.first
    }

    public func one(
        from table: String,
        selecting columns: [String],
        where conditions: [String: (String, ConditionValue)]
    ) async throws -> DataRow {
        let whereClause = SQLBuilder.buildWhereClause(conditions)
        let sql = """
            SELECT \(columns.joined(separator: ", ")) FROM \(table)
            \(conditions.isEmpty ? "" : "WHERE " + whereClause.clause)
            LIMIT 2
            """

        let results = try await db.executeQuery(
            sql: sql, params: whereClause.params
        ) { row in
            let randomAccessRow = row.makeRandomAccess()
            var dict: [String: String] = [:]
            for column in columns {
                if let columnValue = randomAccessRow[data: column].string {
                    dict[column] = columnValue
                }
            }
            return DataRow(values: dict)
        }

        guard results.count <= 1 else {
            throw RepositoryError.unexpectedResultCount(
                "Expected 1 result, got \(results.count)")
        }

        guard let result = results.first else {
            throw RepositoryError.unexpectedResultCount(
                "Expected 1 result, got 0")
        }

        return result
    }

    public func executeRaw(_ sql: String, _ bindings: [Encodable]) async throws
    {
        let params = try bindings.map { value in
            if let conditionValue = value as? ConditionValue {
                return try conditionValue.toPostgresData()
            } else {
                return try ConditionValue.value(value).toPostgresData()
            }
        }
        try await db.executeUpdate(sql: sql, params: params)
    }
}
