public enum JoinType: Sendable {
    case inner
    case left
    case right
    case full
    case outer

    var sql: String {
        switch self {
        case .inner: return "INNER JOIN"
        case .left: return "LEFT JOIN"
        case .right: return "RIGHT JOIN"
        case .full: return "FULL JOIN"
        case .outer: return "OUTER JOIN"
        }
    }
}
