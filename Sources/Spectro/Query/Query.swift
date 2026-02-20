import Foundation
import PostgresKit
import SpectroCore

/// Closure-based query builder for beautiful, type-safe database operations
///
/// Usage:
/// ```swift
/// let users = try await repo.query(User.self)
///     .where { $0.name == "John" && $0.age > 18 }
///     .orderBy(\.createdAt, .desc)
///     .limit(10)
///     .all()
/// ```
public struct Query<T: Schema>: Sendable {
    private let schema: T.Type
    internal let connection: DatabaseConnection
    internal var whereClause: String = ""
    internal var parameters: [PostgresData] = []
    internal var orderFields: [OrderByClause] = []
    internal var limitValue: Int?
    internal var offsetValue: Int?
    private var selectedFields: Set<String>?
    internal var joins: [JoinClause] = []

    internal init(schema: T.Type, connection: DatabaseConnection) {
        self.schema = schema
        self.connection = connection
    }

    // MARK: - Where Clauses

    public func `where`(_ condition: (QueryBuilder<T>) -> QueryCondition) -> Query<T> {
        var copy = self
        let builder = QueryBuilder<T>()
        let queryCondition = condition(builder)

        if !copy.whereClause.isEmpty {
            copy.whereClause += " AND "
        }
        copy.whereClause += queryCondition.sql
        copy.parameters.append(contentsOf: queryCondition.parameters)

        return copy
    }

    // MARK: - Joins

    public func join<U: Schema>(
        _ joinSchema: U.Type,
        on condition: (JoinBuilder<T, U>) -> QueryCondition
    ) -> Query<T> {
        var copy = self
        let builder = JoinBuilder<T, U>()
        let joinCondition = condition(builder)
        copy.joins.append(JoinClause(
            type: .inner,
            table: joinSchema.tableName,
            condition: joinCondition.sql,
            parameters: joinCondition.parameters
        ))
        copy.parameters.append(contentsOf: joinCondition.parameters)
        return copy
    }

    public func leftJoin<U: Schema>(
        _ joinSchema: U.Type,
        on condition: (JoinBuilder<T, U>) -> QueryCondition
    ) -> Query<T> {
        var copy = self
        let builder = JoinBuilder<T, U>()
        let joinCondition = condition(builder)
        copy.joins.append(JoinClause(
            type: .left,
            table: joinSchema.tableName,
            condition: joinCondition.sql,
            parameters: joinCondition.parameters
        ))
        copy.parameters.append(contentsOf: joinCondition.parameters)
        return copy
    }

    public func rightJoin<U: Schema>(
        _ joinSchema: U.Type,
        on condition: (JoinBuilder<T, U>) -> QueryCondition
    ) -> Query<T> {
        var copy = self
        let builder = JoinBuilder<T, U>()
        let joinCondition = condition(builder)
        copy.joins.append(JoinClause(
            type: .right,
            table: joinSchema.tableName,
            condition: joinCondition.sql,
            parameters: joinCondition.parameters
        ))
        copy.parameters.append(contentsOf: joinCondition.parameters)
        return copy
    }

    public func joinThrough<U: Schema, Junction: Schema>(
        _ targetSchema: U.Type,
        through junctionSchema: Junction.Type,
        on condition: (ThroughJoinBuilder<T, U, Junction>) -> (QueryCondition, QueryCondition)
    ) -> Query<T> {
        var copy = self
        let builder = ThroughJoinBuilder<T, U, Junction>()
        let (firstJoin, secondJoin) = condition(builder)

        copy.joins.append(JoinClause(
            type: .inner,
            table: junctionSchema.tableName,
            condition: firstJoin.sql,
            parameters: firstJoin.parameters
        ))
        copy.parameters.append(contentsOf: firstJoin.parameters)

        copy.joins.append(JoinClause(
            type: .inner,
            table: targetSchema.tableName,
            condition: secondJoin.sql,
            parameters: secondJoin.parameters
        ))
        copy.parameters.append(contentsOf: secondJoin.parameters)

        return copy
    }

    // MARK: - Ordering
    //
    // Field names are quoted at storage time so buildOrderClause() can use
    // them verbatim without risk of double-quoting qualified join fields.

    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>) -> Query<T> {
        var copy = self
        let queryField = field(QueryBuilder<T>())
        copy.orderFields.append(OrderByClause(
            field: queryField.name.snakeCase().quoted,
            direction: .asc
        ))
        return copy
    }

    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>, _ direction: OrderDirection) -> Query<T> {
        var copy = self
        let queryField = field(QueryBuilder<T>())
        copy.orderFields.append(OrderByClause(
            field: queryField.name.snakeCase().quoted,
            direction: direction
        ))
        return copy
    }

    public func orderBy<V1, V2>(
        _ field1: (QueryBuilder<T>) -> QueryField<V1>,
        _ direction1: OrderDirection = .asc,
        then field2: (QueryBuilder<T>) -> QueryField<V2>,
        _ direction2: OrderDirection = .asc
    ) -> Query<T> {
        var copy = self
        let builder = QueryBuilder<T>()
        copy.orderFields.append(OrderByClause(field: field1(builder).name.snakeCase().quoted, direction: direction1))
        copy.orderFields.append(OrderByClause(field: field2(builder).name.snakeCase().quoted, direction: direction2))
        return copy
    }

    // MARK: - Field Selection

    public func select<V>(_ selector: (QueryBuilder<T>) -> QueryField<V>) -> TupleQuery<T, V> {
        let field = selector(QueryBuilder<T>())
        return TupleQuery<T, V>(baseQuery: self, selectedFields: [field.name.snakeCase()])
    }

    public func select<V1, V2>(_ selector: (QueryBuilder<T>) -> (QueryField<V1>, QueryField<V2>)) -> TupleQuery<T, Tuple2<V1, V2>> {
        let (f1, f2) = selector(QueryBuilder<T>())
        return TupleQuery<T, Tuple2<V1, V2>>(
            baseQuery: self,
            selectedFields: [f1.name.snakeCase(), f2.name.snakeCase()]
        )
    }

    public func select<V1, V2, V3>(_ selector: (QueryBuilder<T>) -> (QueryField<V1>, QueryField<V2>, QueryField<V3>)) -> TupleQuery<T, Tuple3<V1, V2, V3>> {
        let (f1, f2, f3) = selector(QueryBuilder<T>())
        return TupleQuery<T, Tuple3<V1, V2, V3>>(
            baseQuery: self,
            selectedFields: [f1.name.snakeCase(), f2.name.snakeCase(), f3.name.snakeCase()]
        )
    }

    public func select<V1, V2, V3, V4>(_ selector: (QueryBuilder<T>) -> (QueryField<V1>, QueryField<V2>, QueryField<V3>, QueryField<V4>)) -> TupleQuery<T, Tuple4<V1, V2, V3, V4>> {
        let (f1, f2, f3, f4) = selector(QueryBuilder<T>())
        return TupleQuery<T, Tuple4<V1, V2, V3, V4>>(
            baseQuery: self,
            selectedFields: [f1.name.snakeCase(), f2.name.snakeCase(), f3.name.snakeCase(), f4.name.snakeCase()]
        )
    }

    public func selectFields<V>(_ field: (QueryBuilder<T>) -> QueryField<V>) -> Query<T> {
        var copy = self
        let queryField = field(QueryBuilder<T>())
        if copy.selectedFields == nil { copy.selectedFields = [] }
        copy.selectedFields?.insert(queryField.name.snakeCase())
        return copy
    }

    // MARK: - Pagination

    public func limit(_ count: Int) -> Query<T> {
        var copy = self
        copy.limitValue = count
        return copy
    }

    public func offset(_ count: Int) -> Query<T> {
        var copy = self
        copy.offsetValue = count
        return copy
    }

    // MARK: - Relationship Preloading

    public func preload<Related>(_ relationshipKeyPath: KeyPath<T, SpectroLazyRelation<[Related]>>) -> PreloadQuery<T> {
        PreloadQuery(baseQuery: self, preloadedRelationships: [extractRelationshipName(from: relationshipKeyPath)])
    }

    public func preload<Related>(_ relationshipKeyPath: KeyPath<T, SpectroLazyRelation<Related?>>) -> PreloadQuery<T> {
        PreloadQuery(baseQuery: self, preloadedRelationships: [extractRelationshipName(from: relationshipKeyPath)])
    }

    // MARK: - Execution

    public func all() async throws -> [T] {
        let sql = buildSQL()
        let rows = try await connection.executeQuery(
            sql: sql,
            parameters: parameters,
            resultMapper: { $0 }
        )
        var results: [T] = []
        for row in rows {
            results.append(try await T.from(row: row))
        }
        return results
    }

    public func first() async throws -> T? {
        try await limit(1).all().first
    }

    public func firstOrFail() async throws -> T {
        guard let result = try await first() else {
            throw SpectroError.notFound(schema: T.tableName, id: UUID())
        }
        return result
    }

    public func count() async throws -> Int {
        let sql = buildCountSQL()
        let results = try await connection.executeQuery(
            sql: sql,
            parameters: parameters,
            resultMapper: { row in
                let randomAccess = row.makeRandomAccess()
                guard let count = randomAccess[data: "count"].int else {
                    throw SpectroError.resultDecodingFailed(column: "count", expectedType: "Int")
                }
                return count
            }
        )
        return results.first ?? 0
    }

    // MARK: - SQL Building

    internal func buildSQL() -> String {
        let table = T.tableName.quoted
        let selectClause = buildSelectClause()
        let joinClause = buildJoinClause()
        let orderClause = buildOrderClause()
        let limitClause = buildLimitClause()

        var sql = "SELECT \(selectClause) FROM \(table)"

        if !joinClause.isEmpty { sql += " \(joinClause)" }
        if !whereClause.isEmpty { sql += " WHERE \(whereClause)" }
        if !orderClause.isEmpty { sql += " ORDER BY \(orderClause)" }
        if !limitClause.isEmpty { sql += limitClause }

        return renumberPlaceholders(in: sql)
    }

    internal func buildCountSQL() -> String {
        let table = T.tableName.quoted
        let joinClause = buildJoinClause()

        var sql = "SELECT COUNT(*) as count FROM \(table)"

        if !joinClause.isEmpty { sql += " \(joinClause)" }
        if !whereClause.isEmpty { sql += " WHERE \(whereClause)" }

        return renumberPlaceholders(in: sql)
    }

    private func buildSelectClause() -> String {
        guard let fields = selectedFields, !fields.isEmpty else { return "*" }
        // selectedFields stores unquoted snake_case names; quote here for SQL
        return fields.sorted().map { $0.quoted }.joined(separator: ", ")
    }

    internal func buildJoinClause() -> String {
        guard !joins.isEmpty else { return "" }
        return joins.map { "\($0.type.sql) \($0.table.quoted) ON \($0.condition)" }
            .joined(separator: " ")
    }

    internal func buildOrderClause() -> String {
        guard !orderFields.isEmpty else { return "" }
        // Fields are pre-quoted at storage time (see orderBy methods above)
        return orderFields.map { "\($0.field) \($0.direction.sql)" }
            .joined(separator: ", ")
    }

    internal func buildLimitClause() -> String {
        var clause = ""
        if let limit = limitValue {
            guard limit >= 0 else { return "" }
            clause += " LIMIT \(limit)"
        }
        if let offset = offsetValue {
            guard offset >= 0 else { return clause }
            clause += " OFFSET \(offset)"
        }
        return clause
    }

    // MARK: - Placeholder Renumbering
    //
    // Conditions store SQL with `?` as an opaque positional sentinel.
    // Numbering ($1, $2, …) is applied once here, in a single left-to-right
    // pass over the fully-assembled SQL string.

    private func renumberPlaceholders(in sql: String) -> String {
        var result = ""
        var counter = 0
        for char in sql {
            if char == "?" {
                counter += 1
                result += "$\(counter)"
            } else {
                result.append(char)
            }
        }
        return result
    }

    // MARK: - Helpers

    internal func mapRowToSchema(_ row: PostgresRow) async throws -> T {
        try await T.from(row: row)
    }

    private func extractRelationshipName<Related>(from keyPath: KeyPath<T, SpectroLazyRelation<Related>>) -> String {
        if let propertyName = keyPath.propertyName { return propertyName }
        let keyPathString = String(describing: keyPath)
        if let match = keyPathString.range(of: #"\.\$?([a-zA-Z_][a-zA-Z0-9_]*)>*$"#, options: .regularExpression) {
            return String(keyPathString[match])
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ">", with: "")
        }
        return "unknown_relationship"
    }
}

// MARK: - TupleQuery

public struct TupleQuery<T: Schema, Result: Sendable>: Sendable {
    private let baseQuery: Query<T>
    // Stored as unquoted snake_case; quoted at SQL-build time
    private let selectedFields: [String]

    internal init(baseQuery: Query<T>, selectedFields: [String]) {
        self.baseQuery = baseQuery
        self.selectedFields = selectedFields
    }

    public func `where`(_ condition: (QueryBuilder<T>) -> QueryCondition) -> TupleQuery<T, Result> {
        TupleQuery<T, Result>(baseQuery: baseQuery.where(condition), selectedFields: selectedFields)
    }

    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>) -> TupleQuery<T, Result> {
        TupleQuery<T, Result>(baseQuery: baseQuery.orderBy(field), selectedFields: selectedFields)
    }

    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>, _ direction: OrderDirection) -> TupleQuery<T, Result> {
        TupleQuery<T, Result>(baseQuery: baseQuery.orderBy(field, direction), selectedFields: selectedFields)
    }

    public func limit(_ count: Int) -> TupleQuery<T, Result> {
        TupleQuery<T, Result>(baseQuery: baseQuery.limit(count), selectedFields: selectedFields)
    }

    public func offset(_ count: Int) -> TupleQuery<T, Result> {
        TupleQuery<T, Result>(baseQuery: baseQuery.offset(count), selectedFields: selectedFields)
    }

    public func all() async throws -> [Result] {
        let sql = buildTupleSQL()
        return try await baseQuery.connection.executeQuery(
            sql: sql,
            parameters: baseQuery.parameters,
            resultMapper: { row in try mapRowToTuple(row) }
        )
    }

    public func first() async throws -> Result? {
        try await limit(1).all().first
    }

    public func firstOrFail() async throws -> Result {
        guard let result = try await first() else {
            throw SpectroError.notFound(schema: T.tableName, id: UUID())
        }
        return result
    }

    public func count() async throws -> Int {
        try await baseQuery.count()
    }

    private func buildTupleSQL() -> String {
        let table = T.tableName.quoted
        let selectClause = selectedFields.map { $0.quoted }.joined(separator: ", ")
        let joinClause = baseQuery.buildJoinClause()
        let orderClause = baseQuery.buildOrderClause()
        let limitClause = baseQuery.buildLimitClause()

        var sql = "SELECT \(selectClause) FROM \(table)"

        if !joinClause.isEmpty { sql += " \(joinClause)" }
        if !baseQuery.whereClause.isEmpty { sql += " WHERE \(baseQuery.whereClause)" }
        if !orderClause.isEmpty { sql += " ORDER BY \(orderClause)" }
        if !limitClause.isEmpty { sql += limitClause }

        return renumberPlaceholders(in: sql)
    }

    private func renumberPlaceholders(in sql: String) -> String {
        var result = ""
        var counter = 0
        for char in sql {
            if char == "?" { counter += 1; result += "$\(counter)" }
            else { result.append(char) }
        }
        return result
    }

    private func mapRowToTuple(_ row: PostgresRow) throws -> Result {
        if let tupleBuildableType = Result.self as? any TupleBuildable.Type {
            return try TupleMapper.mapRow(row, selectedFields: selectedFields, to: tupleBuildableType) as! Result
        }
        if selectedFields.count == 1 {
            let randomAccess = row.makeRandomAccess()
            return try extractSingleValue(from: randomAccess[data: selectedFields[0]]) as! Result
        }
        throw SpectroError.notImplemented("Result type \(Result.self) must conform to TupleBuildable for multi-field selection")
    }

    private func extractSingleValue(from postgresData: PostgresData) throws -> Any {
        if let v = postgresData.string { return v }
        if let v = postgresData.int { return v }
        if let v = postgresData.bool { return v }
        if let v = postgresData.uuid { return v }
        if let v = postgresData.date { return v }
        if let v = postgresData.double { return v }
        throw SpectroError.resultDecodingFailed(column: "unknown", expectedType: "Any")
    }
}

// MARK: - QueryBuilder

@dynamicMemberLookup
public struct QueryBuilder<T: Schema>: Sendable {
    public init() {}

    public subscript<V>(dynamicMember keyPath: KeyPath<T, V>) -> QueryField<V> {
        QueryField<V>(name: extractFieldName(from: keyPath))
    }

    private func extractFieldName<V>(from keyPath: KeyPath<T, V>) -> String {
        let keyPathString = "\(keyPath)"
        return keyPathString.components(separatedBy: ".").last ?? keyPathString
    }
}

// MARK: - QueryField

public struct QueryField<V>: Sendable {
    let name: String

    init(name: String) {
        self.name = name
    }
}

// MARK: - QueryCondition
//
// SQL uses `?` as a positional sentinel — never $N.
// Column names are quoted at the point of operator use below.
// Placeholders are numbered once at query assembly time.

public struct QueryCondition: Sendable {
    let sql: String
    let parameters: [PostgresData]

    init(sql: String, parameters: [PostgresData] = []) {
        self.sql = sql
        self.parameters = parameters
    }
}

// MARK: - QueryField Operators

extension QueryField where V: Equatable {
    public static func == (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase().quoted) = ?", parameters: [convertToPostgresData(rhs)])
    }

    public static func != (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase().quoted) != ?", parameters: [convertToPostgresData(rhs)])
    }
}

extension QueryField where V: Comparable {
    public static func > (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase().quoted) > ?", parameters: [convertToPostgresData(rhs)])
    }

    public static func >= (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase().quoted) >= ?", parameters: [convertToPostgresData(rhs)])
    }

    public static func < (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase().quoted) < ?", parameters: [convertToPostgresData(rhs)])
    }

    public static func <= (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase().quoted) <= ?", parameters: [convertToPostgresData(rhs)])
    }
}

extension QueryField where V == String {
    public func like(_ pattern: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) LIKE ?", parameters: [PostgresData(string: pattern)])
    }

    public func ilike(_ pattern: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) ILIKE ?", parameters: [PostgresData(string: pattern)])
    }

    public func notLike(_ pattern: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) NOT LIKE ?", parameters: [PostgresData(string: pattern)])
    }

    public func notIlike(_ pattern: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) NOT ILIKE ?", parameters: [PostgresData(string: pattern)])
    }

    public func startsWith(_ prefix: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) LIKE ?", parameters: [PostgresData(string: "\(prefix)%")])
    }

    public func endsWith(_ suffix: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) LIKE ?", parameters: [PostgresData(string: "%\(suffix)")])
    }

    public func contains(_ substring: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) LIKE ?", parameters: [PostgresData(string: "%\(substring)%")])
    }

    public func iStartsWith(_ prefix: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) ILIKE ?", parameters: [PostgresData(string: "\(prefix)%")])
    }

    public func iEndsWith(_ suffix: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) ILIKE ?", parameters: [PostgresData(string: "%\(suffix)")])
    }

    public func iContains(_ substring: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) ILIKE ?", parameters: [PostgresData(string: "%\(substring)%")])
    }
}

extension QueryField where V: Equatable {
    public func `in`<S: Sequence>(_ values: S) -> QueryCondition where S.Element == V {
        let valueArray = Array(values)
        let placeholders = Array(repeating: "?", count: valueArray.count).joined(separator: ", ")
        return QueryCondition(
            sql: "\(name.snakeCase().quoted) IN (\(placeholders))",
            parameters: valueArray.map { convertToPostgresData($0) }
        )
    }

    public func notIn<S: Sequence>(_ values: S) -> QueryCondition where S.Element == V {
        let valueArray = Array(values)
        let placeholders = Array(repeating: "?", count: valueArray.count).joined(separator: ", ")
        return QueryCondition(
            sql: "\(name.snakeCase().quoted) NOT IN (\(placeholders))",
            parameters: valueArray.map { convertToPostgresData($0) }
        )
    }
}

extension QueryField where V: Comparable {
    public func between(_ lower: V, and upper: V) -> QueryCondition {
        QueryCondition(
            sql: "\(name.snakeCase().quoted) BETWEEN ? AND ?",
            parameters: [convertToPostgresData(lower), convertToPostgresData(upper)]
        )
    }
}

extension QueryField where V == Date {
    public func before(_ date: Date) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) < ?", parameters: [PostgresData(date: date)])
    }

    public func after(_ date: Date) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) > ?", parameters: [PostgresData(date: date)])
    }

    public func isToday() -> QueryCondition {
        QueryCondition(sql: "DATE(\(name.snakeCase().quoted)) = CURRENT_DATE")
    }

    public func isThisWeek() -> QueryCondition {
        QueryCondition(sql: "DATE_TRUNC('week', \(name.snakeCase().quoted)) = DATE_TRUNC('week', CURRENT_DATE)")
    }

    public func isThisMonth() -> QueryCondition {
        QueryCondition(sql: "DATE_TRUNC('month', \(name.snakeCase().quoted)) = DATE_TRUNC('month', CURRENT_DATE)")
    }

    public func isThisYear() -> QueryCondition {
        QueryCondition(sql: "DATE_TRUNC('year', \(name.snakeCase().quoted)) = DATE_TRUNC('year', CURRENT_DATE)")
    }
}

extension QueryField {
    public func isNull() -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) IS NULL")
    }

    public func isNotNull() -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase().quoted) IS NOT NULL")
    }
}

extension QueryField where V: Numeric {
    public func count() -> String { "COUNT(\(name.snakeCase().quoted))" }
    public func sum() -> String { "SUM(\(name.snakeCase().quoted))" }
    public func avg() -> String { "AVG(\(name.snakeCase().quoted))" }
    public func min() -> String { "MIN(\(name.snakeCase().quoted))" }
    public func max() -> String { "MAX(\(name.snakeCase().quoted))" }
}

// MARK: - Logical Operators

public func && (lhs: QueryCondition, rhs: QueryCondition) -> QueryCondition {
    QueryCondition(
        sql: "(\(lhs.sql)) AND (\(rhs.sql))",
        parameters: lhs.parameters + rhs.parameters
    )
}

public func || (lhs: QueryCondition, rhs: QueryCondition) -> QueryCondition {
    QueryCondition(
        sql: "(\(lhs.sql)) OR (\(rhs.sql))",
        parameters: lhs.parameters + rhs.parameters
    )
}

public prefix func ! (condition: QueryCondition) -> QueryCondition {
    QueryCondition(sql: "NOT (\(condition.sql))", parameters: condition.parameters)
}

// MARK: - PostgresData Conversion

private func convertToPostgresData(_ value: Any) -> PostgresData {
    switch value {
    case let v as String: return PostgresData(string: v)
    case let v as Int: return PostgresData(int: v)
    case let v as Bool: return PostgresData(bool: v)
    case let v as UUID: return PostgresData(uuid: v)
    case let v as Date: return PostgresData(date: v)
    case let v as Double: return PostgresData(double: v)
    case let v as Float: return PostgresData(float: v)
    default: return PostgresData(string: "\(value)")
    }
}

// MARK: - Supporting Types

internal struct OrderByClause: Sendable {
    let field: String
    let direction: OrderDirection
}

internal struct JoinClause: Sendable {
    let type: JoinType
    let table: String
    let condition: String
    let parameters: [PostgresData]
}

internal enum JoinType: Sendable {
    case inner, left, right, full

    var sql: String {
        switch self {
        case .inner: return "INNER JOIN"
        case .left: return "LEFT JOIN"
        case .right: return "RIGHT JOIN"
        case .full: return "FULL OUTER JOIN"
        }
    }
}

// MARK: - Join Builders

@dynamicMemberLookup
public struct JoinBuilder<T: Schema, U: Schema>: Sendable {
    public init() {}

    public var left: JoinQueryField<T> { JoinQueryField<T>(tableName: T.tableName) }
    public var right: JoinQueryField<U> { JoinQueryField<U>(tableName: U.tableName) }

    public subscript<V>(dynamicMember keyPath: KeyPath<T, V>) -> JoinField<V> {
        JoinField<V>(tableName: T.tableName, fieldName: extractFieldName(from: keyPath, schema: T.self))
    }
}

public struct ThroughJoinBuilder<T: Schema, U: Schema, Junction: Schema>: Sendable {
    public init() {}

    public var main: JoinQueryField<T> { JoinQueryField<T>(tableName: T.tableName) }
    public var junction: JoinQueryField<Junction> { JoinQueryField<Junction>(tableName: Junction.tableName) }
    public var target: JoinQueryField<U> { JoinQueryField<U>(tableName: U.tableName) }
}

@dynamicMemberLookup
public struct JoinQueryField<T: Schema>: Sendable {
    let tableName: String

    init(tableName: String) {
        self.tableName = tableName
    }

    public subscript<V>(dynamicMember keyPath: KeyPath<T, V>) -> JoinField<V> {
        JoinField<V>(tableName: tableName, fieldName: extractFieldName(from: keyPath, schema: T.self))
    }
}

public struct JoinField<V>: Sendable {
    let tableName: String
    let fieldName: String

    init(tableName: String, fieldName: String) {
        self.tableName = tableName
        self.fieldName = fieldName
    }

    /// Fully-qualified, quoted identifier: `"table"."column"`
    var qualifiedName: String {
        "\(tableName.quoted).\(fieldName.snakeCase().quoted)"
    }
}

// MARK: - JoinField Operators

extension JoinField where V: Equatable {
    public static func == (lhs: JoinField<V>, rhs: JoinField<V>) -> QueryCondition {
        QueryCondition(sql: "\(lhs.qualifiedName) = \(rhs.qualifiedName)")
    }

    public static func == (lhs: JoinField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.qualifiedName) = ?", parameters: [convertToPostgresData(rhs)])
    }

    public static func != (lhs: JoinField<V>, rhs: JoinField<V>) -> QueryCondition {
        QueryCondition(sql: "\(lhs.qualifiedName) != \(rhs.qualifiedName)")
    }
}

extension JoinField where V: Comparable {
    public static func > (lhs: JoinField<V>, rhs: JoinField<V>) -> QueryCondition {
        QueryCondition(sql: "\(lhs.qualifiedName) > \(rhs.qualifiedName)")
    }

    public static func < (lhs: JoinField<V>, rhs: JoinField<V>) -> QueryCondition {
        QueryCondition(sql: "\(lhs.qualifiedName) < \(rhs.qualifiedName)")
    }
}

// MARK: - KeyPath Field Name Extraction

private func extractFieldName<T: Schema, V>(from keyPath: KeyPath<T, V>, schema: T.Type) -> String {
    let keyPathString = "\(keyPath)"
    return keyPathString.components(separatedBy: ".").last ?? keyPathString
}

// MARK: - Repository Integration

extension DatabaseRepo {
    public func query<T: Schema>(_ schema: T.Type) -> Query<T> {
        Query(schema: schema, connection: connection)
    }
}
