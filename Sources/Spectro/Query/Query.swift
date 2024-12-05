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
    var orderBy: [OrderByField] = []
    var limit: Int?
    var offset: Int?
    var joins: [JoinClause] = []

    private init(table: String, schema: Schema.Type) {
        self.table = table
        self.schema = schema
    }

    static func from(_ schema: any Schema.Type) -> Query {
        return Query(table: schema.schemaName, schema: schema)
    }

    func `where`(_ builder: (FieldSelector) -> Condition) -> Query {
        var copy = self
        let selector = FieldSelector(schema: schema)
        let condition = builder(selector)

        switch condition {
        case let simple as QueryCondition:
            copy.conditions[simple.field] = (simple.op, simple.value)
        case let composite as CompositeCondition:
            _ = SQLBuilder.buildWhereClause(composite)
        default:
            fatalError("Unexpected condition type")
        }
        return copy
    }

    func select(_ columns: (FieldSelector) -> [FieldPredicate]) -> Query {
        var copy = self
        let selector = FieldSelector(schema: schema)
        copy.selections = columns(selector).map { $0.fieldName }
        return copy
    }

    func orderBy(_ builder: (FieldSelector) -> [OrderByField]) -> Query {
        var copy = self
        let selector = FieldSelector(schema: schema)
        copy.orderBy = builder(selector)
        return copy
    }

    func limit(_ value: Int) -> Query {
        var copy = self
        copy.limit = value
        return copy
    }

    func offset(_ value: Int) -> Query {
        var copy = self
        copy.offset = value
        return copy
    }

    func join(type: JoinType = .inner, table: String, on condition: String) -> Query {
        var newQuery = self
        newQuery.joins.append(JoinClause(type: type, table: table, condition: condition))
        return newQuery
    }

    func debugSQL() -> String {
        let whereClause = SQLBuilder.buildWhereClause(conditions)
        let whereString = conditions.isEmpty ? "" : " WHERE \(whereClause.clause)"
        let orderClause =
            orderBy.isEmpty
            ? ""
            : " ORDER BY "
                + orderBy.map { "\($0.field) \($0.direction.sql)" }
                .joined(separator: ", ")
        let limitClause = limit.map { " LIMIT \($0)" } ?? ""
        let offsetClause = offset.map { " OFFSET \($0)" } ?? ""

        return """
            SELECT \(selections.joined(separator: ", "))
            FROM \(table)\(whereString)\(orderClause)\(limitClause)\(offsetClause)
            """
    }

}
