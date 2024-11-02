import Foundation
import NIOCore
import PostgresKit

enum DatabaseError: Error {
    case invalidDataType
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

    private func convertToPostgresData(_ value: Any) throws -> PostgresData {
        switch value {
        case let stringValue as String:
            return PostgresData(string: stringValue)
        case let intValue as Int:
            return PostgresData(int64: Int64(intValue))
        case let doubleValue as Double:
            return PostgresData(double: doubleValue)
        case let boolValue as Bool:
            return PostgresData(bool: boolValue)
        case let uuid as UUID:
            return PostgresData(uuid: uuid)
        case let date as Date:
            return PostgresData(date: date)
        case is NSNull:
            return PostgresData(type: .text, value: nil)
        default:
            throw DatabaseError.invalidDataType
        }
    }

    func all(query: Query) async throws -> [DataRow] {
        try await withCheckedThrowingContinuation { continuation in
            let future: EventLoopFuture<[DataRow]> = pools.withConnection {
                conn -> EventLoopFuture<[DataRow]> in
                var sql =
                    "SELECT \(query.selections.joined(separator: ", ")) FROM \(query.table)"
                if !query.conditions.isEmpty {
                    sql +=
                        " WHERE " + query.conditions.joined(separator: " AND ")
                }

                return conn.sql()
                    .raw(SQLQueryString(sql))
                    .all()
                    .flatMapThrowing { rows -> [DataRow] in
                        rows.map { row in
                            var dict: [String: String] = [:]
                            for column in query.selections {
                                if let value = try? row.decode(
                                    column: column, as: String.self)
                                {
                                    dict[column] = value
                                }
                            }
                            return DataRow(values: dict)
                        }
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

    public func insert(into table: String, values: [String: Any]) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let future: EventLoopFuture<Void> = pools.withConnection { conn in
                do {
                    let columns = values.keys.joined(separator: ", ")
                    let placeholders = (1...values.count).map { "$\($0)" }
                        .joined(separator: ", ")
                    let sql =
                        "INSERT INTO \(table) (\(columns)) VALUES (\(placeholders))"

                    let params = try values.values.map {
                        try self.convertToPostgresData($0)
                    }
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

    public func update(
        into table: String, values: [String: Any], where conditions: [String: Any]
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let future: EventLoopFuture<Void> = pools.withConnection { conn in
                do {
                    let setClause = values.keys.enumerated().map {
                        "\($1) = $\($0 + 1)"
                    }.joined(separator: ", ")

                    let whereClause = conditions.keys.enumerated().map {
                        "\($1) = $\($0 + values.count + 1)"
                    }.joined(separator: " AND ")

                    let sql =
                        "UPDATE \(table) SET \(setClause) WHERE \(whereClause)"

                    let params =
                        try values.values.map {
                            try self.convertToPostgresData($0)
                        }
                        + conditions.values.map {
                            try self.convertToPostgresData($0)
                        }

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

}
