//
//  Query.swift
//  Spectro
//
//  Created by William MARTIN on 11/1/24.
//

public struct Query: Sendable {
    let table: String
    let schema: Schema.Type
    var conditions: [String: (String, ConditionValue)] = [:]
    var selections: [String] = ["*"]

    private init(table: String, schema: Schema.Type) {
        self.table = table
        self.schema = schema
    }

    static func from(_ schema: any Schema.Type) -> Query {
        return Query(table: schema.schemaName, schema: schema)
    }

    func `where`(_ field: String, _ op: String, _ value: ConditionValue)
        -> Query
    {
        var copy = self
        copy.conditions[field] = (op, value)
        return copy
    }

    func select(_ columns: String...) -> Query {
        var copy = self
        copy.selections = columns
        return copy
    }
    
    func debugSQL() -> String {
        let whereClause = SQLBuilder.buildWhereClause(conditions)
        return """
            SELECT \(selections.joined(separator: ", ")) 
            FROM \(table)
            \(conditions.isEmpty ? "" : "WHERE " + whereClause.clause)
            """
    }
}
