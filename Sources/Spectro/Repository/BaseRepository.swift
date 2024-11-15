import Foundation
import NIOCore
import PostgresKit

public class BaseRepository {
    private let pools: EventLoopGroupConnectionPool<PostgresConnectionSource>

    public init(pools: EventLoopGroupConnectionPool<PostgresConnectionSource>) {
        self.pools = pools
    }

    private func convertToPostgresData(_ value: ConditionValue) throws
        -> PostgresData
    {
        return try value.toPostgresData()
    }

    private func buildWhereClause(
        _ conditions: [String: (String, ConditionValue)]
    ) -> (clause: String, params: [PostgresData]) {
        let whereClause = conditions.keys.enumerated().map { index, key in
            let (op, _) = conditions[key]!
            return "\(key) \(op) $\((index + 1))"
        }.joined(separator: " AND ")

        let params = try! conditions.values.map {
            try convertToPostgresData($0.1)
        }
        return (clause: whereClause, params: params)
    }

    private func executeQuery<T: Sendable>(
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

    private func executeUpdate(
        sql: String,
        params: [PostgresData]
    ) async throws {
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

    public func all(query: Query) async throws -> [DataRow] {
        let whereClause = buildWhereClause(query.conditions)
        let sql = """
            SELECT \(query.selections.joined(separator: ", ")) FROM \(query)
            \(query.conditions.isEmpty ? "" : "WHERE " + whereClause.clause)
            """

        return try await executeQuery(sql: sql, params: whereClause.params) {
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
        let columns = values.keys.joined(separator: ", ")
        let placeholders = (1...values.count).map { "$\($0)" }.joined(
            separator: ", ")
        let sql = "INSERT INTO \(table) (\(columns)) VALUES (\(placeholders))"

        let params = try values.values.map { try convertToPostgresData($0) }
        try await executeUpdate(sql: sql, params: params)
    }

    public func update(
        table: String,
        values: [String: ConditionValue],
        where conditions: [String: (String, ConditionValue)]
    ) async throws {
        // Construct the SET clause
        let setClause = values.keys.enumerated().map { "\($1) = $\($0 + 1)" }
            .joined(separator: ", ")

        // Construct the WHERE clause
        let whereClause = buildWhereClause(conditions)

        // Adjust parameter numbering for WHERE clause
        let offset = values.count
        var adjustedWhereClause = whereClause.clause

        // Use NSRegularExpression for dynamic replacement
        let regex = try NSRegularExpression(pattern: #"\$(\d+)"#)
        let matches = regex.matches(
            in: adjustedWhereClause,
            options: [],
            range: NSRange(adjustedWhereClause.startIndex..<adjustedWhereClause.endIndex, in: adjustedWhereClause)
        )

        // Build adjusted where clause by replacing matches in reverse order
        for match in matches.reversed() {
            if let matchRange = Range(match.range(at: 1), in: adjustedWhereClause),
               let number = Int(adjustedWhereClause[matchRange]) {
                let adjustedNumber = "$\(number + offset)"
                if let fullMatchRange = Range(match.range, in: adjustedWhereClause) {
                    adjustedWhereClause.replaceSubrange(fullMatchRange, with: adjustedNumber)
                }
            }
        }

        let sql = "UPDATE \(table) SET \(setClause) WHERE \(adjustedWhereClause)"

        // Corrected order of params: SET values first, then WHERE conditions
        let params = try values.values.map { try convertToPostgresData($0) } + whereClause.params

        try await executeUpdate(sql: sql, params: params)
    }

    public func delete(
        from table: String,
        where conditions: [String: (String, ConditionValue)] = [:]
    ) async throws {
        // Check if `conditions` is empty, and if so, create a DELETE query without WHERE clause
        let sql: String
        let params: [PostgresData]

        if conditions.isEmpty {
            sql = "DELETE FROM \(table)"
            params = []
        } else {
            let whereClause = buildWhereClause(conditions)
            sql = "DELETE FROM \(table) WHERE \(whereClause.clause)"
            params = whereClause.params
        }

        try await executeUpdate(sql: sql, params: params)
    }

    public func count(
        from table: String,
        where conditions: [String: (String, ConditionValue)] = [:]
    ) async throws -> Int {
        let whereClause = buildWhereClause(conditions)
        let sql = """
            SELECT COUNT(*) AS count FROM \(table)
            \(conditions.isEmpty ? "" : "WHERE " + whereClause.clause)
            """

        let rows: [Int] = try await executeQuery(
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
