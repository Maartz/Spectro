public struct JoinClause: Sendable {

    public let type: JoinType
    public let table: String
    public let condition: String

    var sql: String {
        return "\(type.sql) \(table) ON \(condition)"
    }
}
