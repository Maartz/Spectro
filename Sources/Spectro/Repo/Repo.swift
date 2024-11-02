import Foundation
import NIOCore
import PostgresKit

enum DatabaseError: Error {
    case invalidDataType
}

enum RepoError: Error {
    case invalidQueryResult
    case unexpectedResultCount(String)
}

public struct DataRow: Sendable {
    public let values: [String: String]

    init(values: [String: String]) {
        self.values = values
    }
}

public class Repo {
    private let pools: EventLoopGroupConnectionPool<PostgresConnectionSource>

    public init(pools: EventLoopGroupConnectionPool<PostgresConnectionSource>) {
        self.pools = pools
    }

    private func convertToPostgresData(_ value: ConditionValue) throws -> PostgresData {
        return try value.toPostgresData()
    }

    public func all(query: Query) async throws -> [DataRow] {
        try await withCheckedThrowingContinuation { continuation in
            let whereClause = query.conditions.keys.enumerated().map { index, key in
                let (op, _) = query.conditions[key]!
                return "\(key) \(op) $\((index + 1))"
            }.joined(separator: " AND ")

            let sql = """
            SELECT \(query.selections.joined(separator: ", ")) FROM \(query.table)
            \(query.conditions.isEmpty ? "" : "WHERE " + whereClause)
            """

            let future: EventLoopFuture<[DataRow]> = pools.withConnection { conn in
                do {
                    let params = try query.conditions.values.map { try self.convertToPostgresData($0.1) }

                    return conn.query(sql, params).flatMapThrowing { rows in
                        rows.map { row in
                            // Convert row to PostgresRandomAccessRow for efficient access
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
                } catch {
                    return conn.eventLoop.makeFailedFuture(error)
                }
            }

            future.whenComplete { result in
                switch result {
                case .success(let rows):
                    continuation.resume(returning: rows)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func insert(into table: String, values: [String: ConditionValue]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let future: EventLoopFuture<Void> = pools.withConnection { conn in
                do {
                    let columns = values.keys.joined(separator: ", ")
                    let placeholders = (1...values.count).map { "$\($0)" }.joined(separator: ", ")
                    let sql = "INSERT INTO \(table) (\(columns)) VALUES (\(placeholders))"

                    let params = try values.values.map { try self.convertToPostgresData($0) }
                    return conn.query(sql, params).map { _ in }
                } catch {
                    return conn.eventLoop.makeFailedFuture(error)
                }
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


    public func update(table: String, values: [String: ConditionValue], where conditions: [String: (String, ConditionValue)]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let setClause = values.keys.enumerated().map { "\($1) = $\($0 + 1)" }.joined(separator: ", ")
            let whereClause = conditions.keys.enumerated().map { index, key in
                let (op, _) = conditions[key]!
                return "\(key) \(op) $\((index + values.count + 1))"
            }.joined(separator: " AND ")

            let sql = "UPDATE \(table) SET \(setClause) WHERE \(whereClause)"
            
            let future: EventLoopFuture<Void> = pools.withConnection { conn in
                do {
                    let params = try values.values.map { try self.convertToPostgresData($0)} + conditions.values.map { try self.convertToPostgresData($0.1 ) }
                    return conn.query(sql, params).map { _ in }
                } catch {
                    return conn.eventLoop.makeFailedFuture(error)
                }
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

    public func delete(from table: String, where conditions: [String: (String, ConditionValue)]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let whereClause = conditions.keys.enumerated().map { index, key in
                let (op, _) = conditions[key]!
                return "\(key) \(op) $\((index + 1))"
            }.joined(separator: " AND ")

            let sql = "DELETE FROM \(table) WHERE \(whereClause)"
            
            let future: EventLoopFuture<Void> = pools.withConnection { conn in
                do {
                    let params = try conditions.values.map { try self.convertToPostgresData($0.1) }
                    return conn.query(sql, params).map { _ in }
                } catch {
                    return conn.eventLoop.makeFailedFuture(error)
                }
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

    public func count(from table: String, where conditions: [String: (String, ConditionValue)] = [:]) async throws -> Int {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let whereClause = conditions.keys.enumerated().map { index, key in
                let (op, _) = conditions[key]!
                return "\(key) \(op) $\((index + 1))"
            }.joined(separator: " AND ")

            let sql = """
            SELECT COUNT(*) AS count FROM \(table)
            \(conditions.isEmpty ? "" : "WHERE " + whereClause)
            """
            
            let future: EventLoopFuture<Int> = pools.withConnection { conn in
                do {
                    let params = try conditions.values.map { try self.convertToPostgresData($0.1) }
                    return conn.query(sql, params).flatMapThrowing { rows in
                        guard let firstRow = rows.first?.makeRandomAccess(), let count = firstRow[data: "count"].int else {
                            throw RepoError.invalidQueryResult
                        }
                        return count
                    }
                } catch {
                    return conn.eventLoop.makeFailedFuture(error)
                }
            }
            
            future.whenComplete { result in
                switch result {
                case .success(let count):
                    continuation.resume(returning: count)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

}
