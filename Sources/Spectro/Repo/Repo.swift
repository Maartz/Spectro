import PostgresKit
import NIOCore

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

    func all(query: Query) async throws -> [DataRow] {
        try await withCheckedThrowingContinuation { continuation in
            let future: EventLoopFuture<[DataRow]> = pools.withConnection { conn -> EventLoopFuture<[DataRow]> in
                var sql = "SELECT \(query.selections.joined(separator: ", ")) FROM \(query.table)"
                if !query.conditions.isEmpty {
                    sql += " WHERE " + query.conditions.joined(separator: " AND ")
                }

                return conn.sql()
                    .raw(SQLQueryString(sql))
                    .all()
                    .flatMapThrowing { rows -> [DataRow] in
                        rows.map { row in
                            var dict: [String: String] = [:]
                            for column in query.selections {
                                if let value = try? row.decode(column: column, as: String.self) {
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
}
