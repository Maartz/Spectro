//
//  Query.swift
//  Spectro
//
//  Created by William MARTIN on 11/1/24.
//

public struct Query<Root: Schema>: Sendable {
    let table: String
    let schema: Root.Type
    let source: TableRef<Root>
    var conditions: [String: (String, ConditionValue)] = [:]
    var selections: [String] = ["*"]
    var orderBy: [OrderByField] = []
    var limit: Int?
    var offset: Int?
    var joins: [JoinClause] = []

    private init(schema: Root.Type, alias: String? = nil) {
        self.table = schema.schemaName
        self.schema = schema
        self.source = TableRef(schema: schema, alias: alias ?? schema.schemaName)
    }

    static func from(_ schema: Root.Type, as alias: String? = nil) -> Query<Root> {
        return Query(schema: schema, alias: alias)
    }

    func `where`(_ builder: (QueryableTable<Root>) -> Condition) -> Query<Root> {
        var copy = self
        let table = QueryableTable<Root>(alias: source.alias)
        let condition = builder(table)

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

    func select(_ builder: (QueryableTable<Root>) -> [SelectableField]) ->  Query<Root>{
        var copy = self
        let table = QueryableTable<Root>(alias: source.alias)
        copy.selections = builder(table).map(\.qualified)
        return copy
    }

    func orderBy(_ builder: (QueryableTable<Root>) -> [OrderByField]) ->  Query<Root> {
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
