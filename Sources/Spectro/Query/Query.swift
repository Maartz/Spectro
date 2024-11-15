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

    func `where`(_ builder: (FieldSelector) -> QueryCondition) -> Query {
        var copy = self
        let selector = FieldSelector(schema: schema)
        let condition = builder(selector)
        copy.conditions[condition.field] = (condition.op, condition.value)
        return copy
    }

    func select(_ columns: (FieldSelector) -> [FieldPredicate]) -> Query {
        var copy = self
        let selector = FieldSelector(schema: schema)
        copy.selections = columns(selector).map { $0.fieldName }
        return copy
    }
    
    func orderBy(_ columns: (FieldSelector) -> [FieldPredicate]) -> Query {
        var copy = self
        let selector = FieldSelector(schema: schema)
        copy.selections.append(contentsOf: columns(selector).map(\.fieldName))
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
