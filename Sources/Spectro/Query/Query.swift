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

    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>) -> Query<T> {
        var copy = self
        let builder = QueryBuilder<T>()
        let queryField = field(builder)
        copy.orderFields.append(OrderByClause(field: queryField.name.snakeCase(), direction: .asc))
        return copy
    }

    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>, _ direction: OrderDirection) -> Query<T> {
        var copy = self
        let builder = QueryBuilder<T>()
        let queryField = field(builder)
        copy.orderFields.append(OrderByClause(field: queryField.name.snakeCase(), direction: direction))
        return copy
    }

    public func orderBy<V1, V2>(
        _ field1: (QueryBuilder<T>) -> QueryField<V1>,
        _ direction1: OrderDirection = .asc,
        then field2: (QueryBuilder<T>) -> QueryField<V2>,
        _ direction2: OrderDirection = .asc
    ) -> Query<T> {
        let builder = QueryBuilder<T>()
        var copy = self
        copy.orderFields.append(OrderByClause(field: field1(builder).name.snakeCase(), direction: direction1))
        copy.orderFields.append(OrderByClause(field: field2(builder).name.snakeCase(), direction: direction2))
        return copy
    }

    // MARK: - Field Selection

    public func select<V>(_ selector: (QueryBuilder<T>) -> QueryField<V>) -> TupleQuery<T, V> {
        let builder = QueryBuilder<T>()
        let field = selector(builder)
        return TupleQuery<T, V>(baseQuery: self, selectedFields: [field.name.snakeCase()])
    }

    public func select<V1, V2>(_ selector: (QueryBuilder<T>) -> (QueryField<V1>, QueryField<V2>)) -> TupleQuery<T, Tuple2<V1, V2>> {
        let builder = QueryBuilder<T>()
        let (f1, f2) = selector(builder)
        return TupleQuery<T, Tuple2<V1, V2>>(
            baseQuery: self,
            selectedFields: [f1.name.snakeCase(), f2.name.snakeCase()]
        )
    }

    public func select<V1, V2, V3>(_ selector: (QueryBuilder<T>) -> (QueryField<V1>, QueryField<V2>, QueryField<V3>)) -> TupleQuery<T, Tuple3<V1, V2, V3>> {
        let builder = QueryBuilder<T>()
        let (f1, f2, f3) = selector(builder)
        return TupleQuery<T, Tuple3<V1, V2, V3>>(
            baseQuery: self,
            selectedFields: [f1.name.snakeCase(), f2.name.snakeCase(), f3.name.snakeCase()]
        )
    }

    public func select<V1, V2, V3, V4>(_ selector: (QueryBuilder<T>) -> (QueryField<V1>, QueryField<V2>, QueryField<V3>, QueryField<V4>)) -> TupleQuery<T, Tuple4<V1, V2, V3, V4>> {
        let builder = QueryBuilder<T>()
        let (f1, f2, f3, f4) = selector(builder)
        return TupleQuery<T, Tuple4<V1, V2, V3, V4>>(
            baseQuery: self,
            selectedFields: [f1.name.snakeCase(), f2.name.snakeCase(), f3.name.snakeCase(), f4.name.snakeCase()]
        )
    }

    /// Select specific fields (legacy API)
    public func selectFields<V>(_ field: (QueryBuilder<T>) -> QueryField<V>) -> Query<T> {
        var copy = self
        let builder = QueryBuilder<T>()
        let queryField = field(builder)
        if copy.selectedFields == nil {
            copy.selectedFields = []
        }
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
        let relationshipName = extractRelationshipName(from: relationshipKeyPath)
        return PreloadQuery(baseQuery: self, preloadedRelationships: [relationshipName])
    }

    public func preload<Related>(_ relationshipKeyPath: KeyPath<T, SpectroLazyRelation<Related?>>) -> PreloadQuery<T> {
        let relationshipName = extractRelationshipName(from: relationshipKeyPath)
        return PreloadQuery(baseQuery: self, preloadedRelationships: [relationshipName])
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
            let instance = try await T.from(row: row)
            results.append(instance)
        }
        return results
    }

    public func first() async throws -> T? {
        let results = try await limit(1).all()
        return results.first
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
        let table = T.tableName
        let selectClause = buildSelectClause()
        let joinClause = buildJoinClause()
        let orderClause = buildOrderClause()
        let limitClause = buildLimitClause()

        var sql = "SELECT \(selectClause) FROM \(table)"

        if !joinClause.isEmpty {
            sql += " \(joinClause)"
        }
        if !whereClause.isEmpty {
            sql += " WHERE \(whereClause)"
        }
        if !orderClause.isEmpty {
            sql += " ORDER BY \(orderClause)"
        }
        if !limitClause.isEmpty {
            sql += limitClause
        }

        return renumberPlaceholders(in: sql)
    }

    internal func buildCountSQL() -> String {
        let table = T.tableName
        let joinClause = buildJoinClause()

        var sql = "SELECT COUNT(*) as count FROM \(table)"

        if !joinClause.isEmpty {
            sql += " \(joinClause)"
        }
        if !whereClause.isEmpty {
            sql += " WHERE \(whereClause)"
        }

        return renumberPlaceholders(in: sql)
    }

    private func buildSelectClause() -> String {
        if let fields = selectedFields, !fields.isEmpty {
            return fields.sorted().joined(separator: ", ")
        }
        return "*"
    }

    internal func buildJoinClause() -> String {
        guard !joins.isEmpty else { return "" }
        return joins.map { "\($0.type.sql) \($0.table) ON \($0.condition)" }
            .joined(separator: " ")
    }

    internal func buildOrderClause() -> String {
        guard !orderFields.isEmpty else { return "" }
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
    // pass over the fully-assembled SQL string. This avoids the substring-
    // replacement corruption that occurs when renumbering is attempted during
    // condition composition (e.g. $10 containing $1 as a prefix).

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
        return try await T.from(row: row)
    }

    private func extractRelationshipName<Related>(from keyPath: KeyPath<T, SpectroLazyRelation<Related>>) -> String {
        if let propertyName = keyPath.propertyName {
            return propertyName
        }
        let keyPathString = String(describing: keyPath)
        if let match = keyPathString.range(of: #"\.\$?([a-zA-Z_][a-zA-Z0-9_]*)>*$"#, options: .regularExpression) {
            let matched = String(keyPathString[match])
            return matched
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
        let table = T.tableName
        let selectClause = selectedFields.joined(separator: ", ")
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
            if char == "?" {
                counter += 1
                result += "$\(counter)"
            } else {
                result.append(char)
            }
        }
        return result
    }

    private func mapRowToTuple(_ row: PostgresRow) throws -> Result {
        if let tupleBuildableType = Result.self as? any TupleBuildable.Type {
            return try TupleMapper.mapRow(row, selectedFields: selectedFields, to: tupleBuildableType) as! Result
        }
        if selectedFields.count == 1 {
            let randomAccess = row.makeRandomAccess()
            let fieldValue = randomAccess[data: selectedFields[0]]
            return try extractSingleValue(from: fieldValue) as! Result
        }
        throw SpectroError.notImplemented("Result type \(Result.self) must conform to TupleBuildable for multi-field selection")
    }

    private func extractSingleValue(from postgresData: PostgresData) throws -> Any {
        if let string = postgresData.string { return string }
        if let int = postgresData.int { return int }
        if let bool = postgresData.bool { return bool }
        if let uuid = postgresData.uuid { return uuid }
        if let date = postgresData.date { return date }
        if let double = postgresData.double { return double }
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
// Placeholders are numbered once at query assembly time by
// Query.renumberPlaceholders(in:), not during condition composition.

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
        QueryCondition(sql: "\(lhs.name.snakeCase()) = ?", parameters: [convertToPostgresData(rhs)])
    }

    public static func != (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase()) != ?", parameters: [convertToPostgresData(rhs)])
    }
}

extension QueryField where V: Comparable {
    public static func > (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase()) > ?", parameters: [convertToPostgresData(rhs)])
    }

    public static func >= (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase()) >= ?", parameters: [convertToPostgresData(rhs)])
    }

    public static func < (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase()) < ?", parameters: [convertToPostgresData(rhs)])
    }

    public static func <= (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase()) <= ?", parameters: [convertToPostgresData(rhs)])
    }
}

extension QueryField where V == String {
    public func like(_ pattern: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) LIKE ?", parameters: [PostgresData(string: pattern)])
    }

    public func ilike(_ pattern: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) ILIKE ?", parameters: [PostgresData(string: pattern)])
    }

    public func notLike(_ pattern: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) NOT LIKE ?", parameters: [PostgresData(string: pattern)])
    }

    public func notIlike(_ pattern: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) NOT ILIKE ?", parameters: [PostgresData(string: pattern)])
    }

    public func startsWith(_ prefix: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) LIKE ?", parameters: [PostgresData(string: "\(prefix)%")])
    }

    public func endsWith(_ suffix: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) LIKE ?", parameters: [PostgresData(string: "%\(suffix)")])
    }

    public func contains(_ substring: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) LIKE ?", parameters: [PostgresData(string: "%\(substring)%")])
    }

    public func iStartsWith(_ prefix: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) ILIKE ?", parameters: [PostgresData(string: "\(prefix)%")])
    }

    public func iEndsWith(_ suffix: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) ILIKE ?", parameters: [PostgresData(string: "%\(suffix)")])
    }

    public func iContains(_ substring: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) ILIKE ?", parameters: [PostgresData(string: "%\(substring)%")])
    }
}

extension QueryField where V: Equatable {
    public func `in`<S: Sequence>(_ values: S) -> QueryCondition where S.Element == V {
        let valueArray = Array(values)
        let placeholders = Array(repeating: "?", count: valueArray.count).joined(separator: ", ")
        return QueryCondition(
            sql: "\(name.snakeCase()) IN (\(placeholders))",
            parameters: valueArray.map { convertToPostgresData($0) }
        )
    }

    public func notIn<S: Sequence>(_ values: S) -> QueryCondition where S.Element == V {
        let valueArray = Array(values)
        let placeholders = Array(repeating: "?", count: valueArray.count).joined(separator: ", ")
        return QueryCondition(
            sql: "\(name.snakeCase()) NOT IN (\(placeholders))",
            parameters: valueArray.map { convertToPostgresData($0) }
        )
    }
}

extension QueryField where V: Comparable {
    public func between(_ lower: V, and upper: V) -> QueryCondition {
        QueryCondition(
            sql: "\(name.snakeCase()) BETWEEN ? AND ?",
            parameters: [convertToPostgresData(lower), convertToPostgresData(upper)]
        )
    }
}

extension QueryField where V == Date {
    public func before(_ date: Date) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) < ?", parameters: [PostgresData(date: date)])
    }

    public func after(_ date: Date) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) > ?", parameters: [PostgresData(date: date)])
    }

    public func isToday() -> QueryCondition {
        QueryCondition(sql: "DATE(\(name.snakeCase())) = CURRENT_DATE")
    }

    public func isThisWeek() -> QueryCondition {
        QueryCondition(sql: "DATE_TRUNC('week', \(name.snakeCase())) = DATE_TRUNC('week', CURRENT_DATE)")
    }

    public func isThisMonth() -> QueryCondition {
        QueryCondition(sql: "DATE_TRUNC('month', \(name.snakeCase())) = DATE_TRUNC('month', CURRENT_DATE)")
    }

    public func isThisYear() -> QueryCondition {
        QueryCondition(sql: "DATE_TRUNC('year', \(name.snakeCase())) = DATE_TRUNC('year', CURRENT_DATE)")
    }
}

extension QueryField {
    public func isNull() -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) IS NULL")
    }

    public func isNotNull() -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) IS NOT NULL")
    }
}

extension QueryField where V: Numeric {
    public func count() -> String { "COUNT(\(name.snakeCase()))" }
    public func sum() -> String { "SUM(\(name.snakeCase()))" }
    public func avg() -> String { "AVG(\(name.snakeCase()))" }
    public func min() -> String { "MIN(\(name.snakeCase()))" }
    public func max() -> String { "MAX(\(name.snakeCase()))" }
}

// MARK: - Logical Operators
//
// Conditions use `?` sentinels, so composition is plain string concatenation —
// no renumbering needed here.

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
    case let string as String: return PostgresData(string: string)
    case let int as Int: return PostgresData(int: int)
    case let bool as Bool: return PostgresData(bool: bool)
    case let uuid as UUID: return PostgresData(uuid: uuid)
    case let date as Date: return PostgresData(date: date)
    case let double as Double: return PostgresData(double: double)
    case let float as Float: return PostgresData(float: float)
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

    var qualifiedName: String { "\(tableName).\(fieldName.snakeCase())" }
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
