import PostgresKit

/// Extract a human-readable message from a PostgreSQL error.
func extractPGMessage(from error: any Error) -> String {
    if let psql = error as? PSQLError,
       let message = psql.serverInfo?[.message] {
        return message
    }
    // Fall back to the error description without the full type name
    let desc = String(describing: error)
    // Strip "SpectroError.queryExecutionFailed(sql: ..., error: " wrapper
    if let range = desc.range(of: "server: ") {
        let start = range.upperBound
        let end = desc.index(before: desc.endIndex)
        return String(desc[start...end])
    }
    return desc
}
