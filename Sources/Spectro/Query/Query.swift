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
    
    // MARK: - Where Clauses with Beautiful Closure Syntax
    
    /// Add a where condition using closure syntax
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
    
    // MARK: - Beautiful Join Syntax
    
    /// Inner join with closure-based condition
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
    
    /// Left join with closure-based condition
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
    
    /// Right join with closure-based condition
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
    
    /// Many-to-many join through junction table
    public func joinThrough<U: Schema, Junction: Schema>(
        _ targetSchema: U.Type,
        through junctionSchema: Junction.Type,
        on condition: (ThroughJoinBuilder<T, U, Junction>) -> (QueryCondition, QueryCondition)
    ) -> Query<T> {
        var copy = self
        let builder = ThroughJoinBuilder<T, U, Junction>()
        let (firstJoin, secondJoin) = condition(builder)
        
        // First join: main table to junction
        copy.joins.append(JoinClause(
            type: .inner,
            table: junctionSchema.tableName,
            condition: firstJoin.sql,
            parameters: firstJoin.parameters
        ))
        copy.parameters.append(contentsOf: firstJoin.parameters)
        
        // Second join: junction to target table
        copy.joins.append(JoinClause(
            type: .inner,
            table: targetSchema.tableName,
            condition: secondJoin.sql,
            parameters: secondJoin.parameters
        ))
        copy.parameters.append(contentsOf: secondJoin.parameters)
        
        return copy
    }
    
    // MARK: - Ordering with Beautiful Closure Syntax
    
    /// Add order by clause using closure syntax for ascending order
    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>) -> Query<T> {
        var copy = self
        let builder = QueryBuilder<T>()
        let queryField = field(builder)
        copy.orderFields.append(OrderByClause(field: queryField.name.snakeCase(), direction: .asc))
        return copy
    }
    
    /// Add order by clause using closure syntax with explicit direction
    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>, _ direction: OrderDirection) -> Query<T> {
        var copy = self
        let builder = QueryBuilder<T>()
        let queryField = field(builder)
        copy.orderFields.append(OrderByClause(field: queryField.name.snakeCase(), direction: direction))
        return copy
    }
    
    /// Multiple ordering with closure syntax
    public func orderBy<V1, V2>(
        _ field1: (QueryBuilder<T>) -> QueryField<V1>,
        _ direction1: OrderDirection = .asc,
        then field2: (QueryBuilder<T>) -> QueryField<V2>,
        _ direction2: OrderDirection = .asc
    ) -> Query<T> {
        let builder = QueryBuilder<T>()
        var copy = self
        
        let queryField1 = field1(builder)
        let queryField2 = field2(builder)
        
        copy.orderFields.append(OrderByClause(field: queryField1.name.snakeCase(), direction: direction1))
        copy.orderFields.append(OrderByClause(field: queryField2.name.snakeCase(), direction: direction2))
        
        return copy
    }
    
    // MARK: - Revolutionary Tuple-Based Selection
    
    /// Select single field returning unwrapped value
    public func select<V>(_ selector: (QueryBuilder<T>) -> QueryField<V>) -> TupleQuery<T, V> {
        let builder = QueryBuilder<T>()
        let field = selector(builder)
        return TupleQuery<T, V>(
            baseQuery: self,
            selectedFields: [field.name.snakeCase()]
        )
    }
    
    /// Select two fields returning tuple Tuple2<V1, V2>
    public func select<V1, V2>(_ selector: (QueryBuilder<T>) -> (QueryField<V1>, QueryField<V2>)) -> TupleQuery<T, Tuple2<V1, V2>> {
        let builder = QueryBuilder<T>()
        let (field1, field2) = selector(builder)
        return TupleQuery<T, Tuple2<V1, V2>>(
            baseQuery: self,
            selectedFields: [field1.name.snakeCase(), field2.name.snakeCase()]
        )
    }
    
    /// Select three fields returning tuple Tuple3<V1, V2, V3>
    public func select<V1, V2, V3>(_ selector: (QueryBuilder<T>) -> (QueryField<V1>, QueryField<V2>, QueryField<V3>)) -> TupleQuery<T, Tuple3<V1, V2, V3>> {
        let builder = QueryBuilder<T>()
        let (field1, field2, field3) = selector(builder)
        return TupleQuery<T, Tuple3<V1, V2, V3>>(
            baseQuery: self,
            selectedFields: [field1.name.snakeCase(), field2.name.snakeCase(), field3.name.snakeCase()]
        )
    }
    
    /// Select four fields returning tuple Tuple4<V1, V2, V3, V4>
    public func select<V1, V2, V3, V4>(_ selector: (QueryBuilder<T>) -> (QueryField<V1>, QueryField<V2>, QueryField<V3>, QueryField<V4>)) -> TupleQuery<T, Tuple4<V1, V2, V3, V4>> {
        let builder = QueryBuilder<T>()
        let (field1, field2, field3, field4) = selector(builder)
        return TupleQuery<T, Tuple4<V1, V2, V3, V4>>(
            baseQuery: self,
            selectedFields: [field1.name.snakeCase(), field2.name.snakeCase(), field3.name.snakeCase(), field4.name.snakeCase()]
        )
    }
    
    // MARK: - Legacy Field Selection (for backward compatibility)
    
    /// Select specific fields using closure syntax (legacy)
    public func selectFields<V>(_ field: (QueryBuilder<T>) -> QueryField<V>) -> Query<T> {
        var copy = self
        let builder = QueryBuilder<T>()
        let queryField = field(builder)
        if copy.selectedFields == nil {
            copy.selectedFields = Set()
        }
        copy.selectedFields?.insert(queryField.name.snakeCase())
        return copy
    }
    
    // MARK: - Limiting and Pagination
    
    /// Limit the number of results
    public func limit(_ count: Int) -> Query<T> {
        var copy = self
        copy.limitValue = count
        return copy
    }
    
    /// Skip a number of results
    public func offset(_ count: Int) -> Query<T> {
        var copy = self
        copy.offsetValue = count
        return copy
    }
    
    // MARK: - Relationship Preloading
    
    /// Preload a has-many relationship to avoid N+1 queries.
    ///
    /// Preloading allows you to efficiently load relationships for multiple records
    /// in a single or minimal number of database queries, preventing the N+1 query problem.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Load users with their posts in optimized queries
    /// let users = try await repo.query(User.self)
    ///     .where { $0.isActive == true }
    ///     .preload(\.$posts)
    ///     .all()
    ///
    /// // Access preloaded relationships without additional queries
    /// for user in users {
    ///     let posts = user.$posts.value ?? []
    ///     print("\(user.name) has \(posts.count) posts")
    /// }
    /// ```
    ///
    /// ## Performance Benefits
    ///
    /// - **Batch Loading**: Uses IN queries or JOINs to load all relationships efficiently
    /// - **Reduced Round Trips**: Minimizes database round trips
    /// - **Memory Efficient**: Only loads what you need when you need it
    ///
    /// ## Chaining Preloads
    ///
    /// You can chain multiple preload calls:
    ///
    /// ```swift
    /// let users = try await repo.query(User.self)
    ///     .preload(\.$posts)
    ///     .preload(\.$profile)
    ///     .preload(\.$comments)
    ///     .all()
    /// ```
    ///
    /// - Parameter relationshipKeyPath: A key path to the has-many relationship property
    /// - Returns: A ``PreloadQuery`` that can be further modified or executed
    public func preload<Related>(_ relationshipKeyPath: KeyPath<T, SpectroLazyRelation<[Related]>>) -> PreloadQuery<T> {
        let relationshipName = extractRelationshipName(from: relationshipKeyPath)
        return PreloadQuery(baseQuery: self, preloadedRelationships: [relationshipName])
    }
    
    /// Preload a has-one or belongs-to relationship to avoid N+1 queries.
    ///
    /// Similar to the has-many preload, but for single-value relationships like
    /// has-one and belongs-to associations.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// // Load posts with their authors in optimized queries
    /// let posts = try await repo.query(Post.self)
    ///     .where { $0.published == true }
    ///     .preload(\.$user)
    ///     .all()
    ///
    /// // Access preloaded relationships without additional queries
    /// for post in posts {
    ///     if let user = post.$user.value {
    ///         print("\(post.title) by \(user.name)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter relationshipKeyPath: A key path to the has-one or belongs-to relationship property
    /// - Returns: A ``PreloadQuery`` that can be further modified or executed
    public func preload<Related>(_ relationshipKeyPath: KeyPath<T, SpectroLazyRelation<Related?>>) -> PreloadQuery<T> {
        let relationshipName = extractRelationshipName(from: relationshipKeyPath)
        return PreloadQuery(baseQuery: self, preloadedRelationships: [relationshipName])
    }
    
    // MARK: - Execution
    
    /// Execute query and return all results
    public func all() async throws -> [T] {
        let sql = buildSQL()
        
        let rows = try await connection.executeQuery(
            sql: sql,
            parameters: parameters,
            resultMapper: { $0 }  // Just return the raw rows
        )
        
        // Map rows to schema instances using the proper async method
        var results: [T] = []
        for row in rows {
            let instance = try await T.from(row: row)
            results.append(instance)
        }
        
        return results
    }
    
    /// Execute query and return first result
    public func first() async throws -> T? {
        let results = try await limit(1).all()
        return results.first
    }
    
    /// Execute query and return first result or throw if not found
    public func firstOrFail() async throws -> T {
        guard let result = try await first() else {
            throw SpectroError.notFound(schema: T.tableName, id: UUID())
        }
        return result
    }
    
    /// Count the number of results
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
        
        return sql
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
        
        return sql
    }
    
    private func buildSelectClause() -> String {
        if let selectedFields = selectedFields, !selectedFields.isEmpty {
            return selectedFields.joined(separator: ", ")
        }
        return "*"
    }
    
    internal func buildJoinClause() -> String {
        guard !joins.isEmpty else { return "" }
        
        return joins.map { join in
            "\(join.type.sql) \(join.table) ON \(join.condition)"
        }.joined(separator: " ")
    }
    
    internal func buildOrderClause() -> String {
        guard !orderFields.isEmpty else { return "" }
        
        return orderFields.map { "\($0.field) \($0.direction.sql)" }
            .joined(separator: ", ")
    }
    
    internal func buildLimitClause() -> String {
        var clause = ""
        
        if let limit = limitValue {
            clause += " LIMIT \(limit)"
        }
        
        if let offset = offsetValue {
            clause += " OFFSET \(offset)"
        }
        
        return clause
    }
    
    // MARK: - Helper Methods
    
    private func extractFieldName<V>(from keyPath: KeyPath<T, V>) -> String {
        // Extract the property name from the keypath string
        let keyPathString = "\(keyPath)"
        let components = keyPathString.components(separatedBy: ".")
        guard let propertyName = components.last else {
            return keyPathString
        }
        return propertyName.snakeCase()
    }
    
    internal func mapRowToSchema(_ row: PostgresRow) async throws -> T {
        // Use the new Schema extension method for generic mapping
        return try await T.from(row: row)
    }
    
    private func mapDatabaseValueToProperty<U: Schema>(_ instance: inout U, label: String, dbValue: PostgresData) throws {
        // This method is now obsolete - using Schema.from(row:) instead
    }
    
    /// Extract relationship name from KeyPath for preloading
    private func extractRelationshipName<Related>(from keyPath: KeyPath<T, SpectroLazyRelation<Related>>) -> String {
        // Use the KeyPath extension to extract property name
        if let propertyName = keyPath.propertyName {
            return propertyName
        }
        
        // Fallback: parse the keyPath string representation
        let keyPathString = String(describing: keyPath)
        
        // Handle patterns like "KeyPath<User, SpectroLazyRelation<Array<Post>>>" 
        // We want to extract the property name which usually appears after the last dot
        if let match = keyPathString.range(of: #"\.\$?([a-zA-Z_][a-zA-Z0-9_]*)>*$"#, options: .regularExpression) {
            let matched = String(keyPathString[match])
            let cleaned = matched
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ">", with: "")
            return cleaned
        }
        
        return "unknown_relationship"
    }
}

// MARK: - Revolutionary Tuple Query for Field Selection

/// Query that returns tuples instead of full models - REVOLUTIONARY!
public struct TupleQuery<T: Schema, Result: Sendable>: Sendable {
    private let baseQuery: Query<T>
    private let selectedFields: [String]
    
    internal init(baseQuery: Query<T>, selectedFields: [String]) {
        self.baseQuery = baseQuery
        self.selectedFields = selectedFields
    }
    
    // MARK: - Where Conditions (same beautiful syntax)
    
    /// Add a where condition using closure syntax
    public func `where`(_ condition: (QueryBuilder<T>) -> QueryCondition) -> TupleQuery<T, Result> {
        let updatedQuery = baseQuery.where(condition)
        return TupleQuery<T, Result>(baseQuery: updatedQuery, selectedFields: selectedFields)
    }
    
    // MARK: - Ordering (same beautiful syntax)
    
    /// Add order by clause using closure syntax for ascending order
    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>) -> TupleQuery<T, Result> {
        let updatedQuery = baseQuery.orderBy(field)
        return TupleQuery<T, Result>(baseQuery: updatedQuery, selectedFields: selectedFields)
    }
    
    /// Add order by clause using closure syntax with explicit direction
    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>, _ direction: OrderDirection) -> TupleQuery<T, Result> {
        let updatedQuery = baseQuery.orderBy(field, direction)
        return TupleQuery<T, Result>(baseQuery: updatedQuery, selectedFields: selectedFields)
    }
    
    // MARK: - Pagination
    
    /// Limit the number of results
    public func limit(_ count: Int) -> TupleQuery<T, Result> {
        let updatedQuery = baseQuery.limit(count)
        return TupleQuery<T, Result>(baseQuery: updatedQuery, selectedFields: selectedFields)
    }
    
    /// Skip a number of results
    public func offset(_ count: Int) -> TupleQuery<T, Result> {
        let updatedQuery = baseQuery.offset(count)
        return TupleQuery<T, Result>(baseQuery: updatedQuery, selectedFields: selectedFields)
    }
    
    // MARK: - Execution Methods (return tuples!)
    
    /// Execute query and return all tuple results
    public func all() async throws -> [Result] {
        let sql = buildTupleSQL()
        
        let results = try await baseQuery.connection.executeQuery(
            sql: sql,
            parameters: baseQuery.parameters,
            resultMapper: { row in
                try mapRowToTuple(row)
            }
        )
        
        return results
    }
    
    /// Execute the query and return the first tuple result.
    ///
    /// - Returns: First tuple result or `nil` if no matches
    /// - Throws: `SpectroError.queryExecutionFailed` if query fails
    public func first() async throws -> Result? {
        let results = try await limit(1).all()
        return results.first
    }
    
    /// Execute query and return first tuple result or throw if not found
    public func firstOrFail() async throws -> Result {
        guard let result = try await first() else {
            throw SpectroError.notFound(schema: T.tableName, id: UUID())
        }
        return result
    }
    
    /// Count the number of results
    public func count() async throws -> Int {
        let countQuery = baseQuery // Use base query for counting
        return try await countQuery.count()
    }
    
    // MARK: - SQL Building for Tuples
    
    private func buildTupleSQL() -> String {
        let table = T.tableName
        let selectClause = selectedFields.joined(separator: ", ")
        let joinClause = baseQuery.buildJoinClause()
        let orderClause = baseQuery.buildOrderClause()
        let limitClause = baseQuery.buildLimitClause()
        
        var sql = "SELECT \(selectClause) FROM \(table)"
        
        if !joinClause.isEmpty {
            sql += " \(joinClause)"
        }
        
        if !baseQuery.whereClause.isEmpty {
            sql += " WHERE \(baseQuery.whereClause)"
        }
        
        if !orderClause.isEmpty {
            sql += " ORDER BY \(orderClause)"
        }
        
        if !limitClause.isEmpty {
            sql += limitClause
        }
        
        return sql
    }
    
    // MARK: - Tuple Mapping Magic
    
    private func mapRowToTuple(_ row: PostgresRow) throws -> Result {
        // Use the new TupleMapper for proper tuple construction
        if let tupleBuildableType = Result.self as? any TupleBuildable.Type {
            return try TupleMapper.mapRow(row, selectedFields: selectedFields, to: tupleBuildableType) as! Result
        } else {
            // Fallback for single values that don't conform to TupleBuildable
            if selectedFields.count == 1 {
                let randomAccess = row.makeRandomAccess()
                let fieldValue = randomAccess[data: selectedFields[0]]
                return try extractValue(from: fieldValue) as! Result
            } else {
                throw SpectroError.notImplemented("Result type \(Result.self) must conform to TupleBuildable for multi-field selection")
            }
        }
    }
    
    private func extractValue(from postgresData: PostgresData) throws -> Any {
        // Extract value based on PostgresData type
        if let string = postgresData.string {
            return string
        } else if let int = postgresData.int {
            return int
        } else if let bool = postgresData.bool {
            return bool
        } else if let uuid = postgresData.uuid {
            return uuid
        } else if let date = postgresData.date {
            return date
        } else if let double = postgresData.double {
            return double
        } else {
            throw SpectroError.resultDecodingFailed(column: "unknown", expectedType: "Any")
        }
    }
}

// MARK: - Query Builder for Closures

/// Builder for creating query conditions with beautiful Swift syntax
@dynamicMemberLookup
public struct QueryBuilder<T: Schema>: Sendable {
    public init() {}
    
    /// Access schema properties for building conditions
    public subscript<V>(dynamicMember keyPath: KeyPath<T, V>) -> QueryField<V> {
        let fieldName = extractFieldName(from: keyPath)
        return QueryField<V>(name: fieldName)
    }
    
    private func extractFieldName<V>(from keyPath: KeyPath<T, V>) -> String {
        let keyPathString = "\(keyPath)"
        let components = keyPathString.components(separatedBy: ".")
        guard let propertyName = components.last else {
            return keyPathString
        }
        return propertyName
    }
}

/// Represents a field in a query with type-safe operations
public struct QueryField<V>: Sendable {
    let name: String
    
    init(name: String) {
        self.name = name
    }
}

// MARK: - Query Condition Building

/// A query condition with SQL and parameters
public struct QueryCondition: Sendable {
    let sql: String
    let parameters: [PostgresData]
    
    init(sql: String, parameters: [PostgresData] = []) {
        self.sql = sql
        self.parameters = parameters
    }
}

// MARK: - Operators for QueryField

extension QueryField where V: Equatable {
    /// Equality comparison
    public static func == (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase()) = $1", parameters: [convertToPostgresData(rhs)])
    }
    
    /// Inequality comparison
    public static func != (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase()) != $1", parameters: [convertToPostgresData(rhs)])
    }
}

extension QueryField where V: Comparable {
    /// Greater than comparison
    public static func > (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase()) > $1", parameters: [convertToPostgresData(rhs)])
    }
    
    /// Greater than or equal comparison
    public static func >= (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase()) >= $1", parameters: [convertToPostgresData(rhs)])
    }
    
    /// Less than comparison
    public static func < (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase()) < $1", parameters: [convertToPostgresData(rhs)])
    }
    
    /// Less than or equal comparison
    public static func <= (lhs: QueryField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.name.snakeCase()) <= $1", parameters: [convertToPostgresData(rhs)])
    }
}

extension QueryField where V == String {
    /// LIKE pattern matching (case-sensitive)
    public func like(_ pattern: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) LIKE $1", parameters: [PostgresData(string: pattern)])
    }
    
    /// ILIKE pattern matching (case-insensitive) - PostgreSQL specific
    public func ilike(_ pattern: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) ILIKE $1", parameters: [PostgresData(string: pattern)])
    }
    
    /// NOT LIKE pattern matching
    public func notLike(_ pattern: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) NOT LIKE $1", parameters: [PostgresData(string: pattern)])
    }
    
    /// NOT ILIKE pattern matching (case-insensitive)
    public func notIlike(_ pattern: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) NOT ILIKE $1", parameters: [PostgresData(string: pattern)])
    }
    
    /// String starts with prefix
    public func startsWith(_ prefix: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) LIKE $1", parameters: [PostgresData(string: "\(prefix)%")])
    }
    
    /// String ends with suffix
    public func endsWith(_ suffix: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) LIKE $1", parameters: [PostgresData(string: "%\(suffix)")])
    }
    
    /// String contains substring
    public func contains(_ substring: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) LIKE $1", parameters: [PostgresData(string: "%\(substring)%")])
    }
    
    /// Case-insensitive versions
    public func iStartsWith(_ prefix: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) ILIKE $1", parameters: [PostgresData(string: "\(prefix)%")])
    }
    
    public func iEndsWith(_ suffix: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) ILIKE $1", parameters: [PostgresData(string: "%\(suffix)")])
    }
    
    public func iContains(_ substring: String) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) ILIKE $1", parameters: [PostgresData(string: "%\(substring)%")])
    }
}

extension QueryField where V: Equatable {
    /// IN clause
    public func `in`<S: Sequence>(_ values: S) -> QueryCondition where S.Element == V {
        let valueArray = Array(values)
        let placeholders = (1...valueArray.count).map { "$\($0)" }.joined(separator: ", ")
        let parameters = valueArray.map { convertToPostgresData($0) }
        return QueryCondition(
            sql: "\(name.snakeCase()) IN (\(placeholders))", 
            parameters: parameters
        )
    }
    
    /// NOT IN clause
    public func notIn<S: Sequence>(_ values: S) -> QueryCondition where S.Element == V {
        let valueArray = Array(values)
        let placeholders = (1...valueArray.count).map { "$\($0)" }.joined(separator: ", ")
        let parameters = valueArray.map { convertToPostgresData($0) }
        return QueryCondition(
            sql: "\(name.snakeCase()) NOT IN (\(placeholders))", 
            parameters: parameters
        )
    }
}

extension QueryField where V: Comparable {
    /// BETWEEN clause
    public func between(_ lower: V, and upper: V) -> QueryCondition {
        QueryCondition(
            sql: "\(name.snakeCase()) BETWEEN $1 AND $2", 
            parameters: [convertToPostgresData(lower), convertToPostgresData(upper)]
        )
    }
}

// MARK: - Date-specific functions

extension QueryField where V == Date {
    /// Date is before given date
    public func before(_ date: Date) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) < $1", parameters: [PostgresData(date: date)])
    }
    
    /// Date is after given date
    public func after(_ date: Date) -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) > $1", parameters: [PostgresData(date: date)])
    }
    
    /// Date is today
    public func isToday() -> QueryCondition {
        QueryCondition(sql: "DATE(\(name.snakeCase())) = CURRENT_DATE")
    }
    
    /// Date is in the current week
    public func isThisWeek() -> QueryCondition {
        QueryCondition(sql: "DATE_TRUNC('week', \(name.snakeCase())) = DATE_TRUNC('week', CURRENT_DATE)")
    }
    
    /// Date is in the current month
    public func isThisMonth() -> QueryCondition {
        QueryCondition(sql: "DATE_TRUNC('month', \(name.snakeCase())) = DATE_TRUNC('month', CURRENT_DATE)")
    }
    
    /// Date is in the current year
    public func isThisYear() -> QueryCondition {
        QueryCondition(sql: "DATE_TRUNC('year', \(name.snakeCase())) = DATE_TRUNC('year', CURRENT_DATE)")
    }
}

// MARK: - Null handling

extension QueryField {
    /// Field is NULL
    public func isNull() -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) IS NULL")
    }
    
    /// Field is NOT NULL
    public func isNotNull() -> QueryCondition {
        QueryCondition(sql: "\(name.snakeCase()) IS NOT NULL")
    }
}

// MARK: - Numeric aggregation functions

extension QueryField where V: Numeric {
    /// Count non-null values
    public func count() -> String {
        return "COUNT(\(name.snakeCase()))"
    }
    
    /// Sum of values
    public func sum() -> String {
        return "SUM(\(name.snakeCase()))"
    }
    
    /// Average of values
    public func avg() -> String {
        return "AVG(\(name.snakeCase()))"
    }
    
    /// Minimum value
    public func min() -> String {
        return "MIN(\(name.snakeCase()))"
    }
    
    /// Maximum value
    public func max() -> String {
        return "MAX(\(name.snakeCase()))"
    }
}

// MARK: - Logical Operators

/// Combine conditions with AND
public func && (lhs: QueryCondition, rhs: QueryCondition) -> QueryCondition {
    let leftParameterCount = lhs.parameters.count
    
    // Adjust parameter placeholders in right condition
    var adjustedRightSQL = rhs.sql
    for i in 1...rhs.parameters.count {
        adjustedRightSQL = adjustedRightSQL.replacingOccurrences(of: "$\(i)", with: "$\(leftParameterCount + i)")
    }
    
    return QueryCondition(
        sql: "(\(lhs.sql)) AND (\(adjustedRightSQL))",
        parameters: lhs.parameters + rhs.parameters
    )
}

/// Combine conditions with OR
public func || (lhs: QueryCondition, rhs: QueryCondition) -> QueryCondition {
    let leftParameterCount = lhs.parameters.count
    
    // Adjust parameter placeholders in right condition
    var adjustedRightSQL = rhs.sql
    for i in 1...rhs.parameters.count {
        adjustedRightSQL = adjustedRightSQL.replacingOccurrences(of: "$\(i)", with: "$\(leftParameterCount + i)")
    }
    
    return QueryCondition(
        sql: "(\(lhs.sql)) OR (\(adjustedRightSQL))",
        parameters: lhs.parameters + rhs.parameters
    )
}

/// Negate a condition
public prefix func ! (condition: QueryCondition) -> QueryCondition {
    QueryCondition(
        sql: "NOT (\(condition.sql))",
        parameters: condition.parameters
    )
}

// MARK: - Helper Functions

private func convertToPostgresData(_ value: Any) -> PostgresData {
    switch value {
    case let string as String:
        return PostgresData(string: string)
    case let int as Int:
        return PostgresData(int: int)
    case let bool as Bool:
        return PostgresData(bool: bool)
    case let uuid as UUID:
        return PostgresData(uuid: uuid)
    case let date as Date:
        return PostgresData(date: date)
    case let double as Double:
        return PostgresData(double: double)
    case let float as Float:
        return PostgresData(float: float)
    default:
        // Fallback - convert to string
        return PostgresData(string: "\(value)")
    }
}

// MARK: - Supporting Types

/// Order by clause representation
internal struct OrderByClause: Sendable {
    let field: String
    let direction: OrderDirection
}

/// Join clause representation
internal struct JoinClause: Sendable {
    let type: JoinType
    let table: String
    let condition: String
    let parameters: [PostgresData]
}

/// Types of SQL joins
internal enum JoinType: Sendable {
    case inner
    case left
    case right
    case full
    
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

/// Builder for creating join conditions with beautiful Swift syntax
@dynamicMemberLookup
public struct JoinBuilder<T: Schema, U: Schema>: Sendable {
    public init() {}
    
    /// Access left table (main query table) properties
    public var left: JoinQueryField<T> {
        JoinQueryField<T>(tableName: T.tableName)
    }
    
    /// Access right table (joined table) properties
    public var right: JoinQueryField<U> {
        JoinQueryField<U>(tableName: U.tableName)
    }
    
    /// Dynamic member lookup for left table
    public subscript<V>(dynamicMember keyPath: KeyPath<T, V>) -> JoinField<V> {
        let fieldName = extractFieldName(from: keyPath, schema: T.self)
        return JoinField<V>(tableName: T.tableName, fieldName: fieldName)
    }
}

/// Builder for many-to-many joins through junction tables
public struct ThroughJoinBuilder<T: Schema, U: Schema, Junction: Schema>: Sendable {
    public init() {}
    
    /// Access main table properties
    public var main: JoinQueryField<T> {
        JoinQueryField<T>(tableName: T.tableName)
    }
    
    /// Access junction table properties
    public var junction: JoinQueryField<Junction> {
        JoinQueryField<Junction>(tableName: Junction.tableName)
    }
    
    /// Access target table properties
    public var target: JoinQueryField<U> {
        JoinQueryField<U>(tableName: U.tableName)
    }
}

/// Represents a table in join queries
@dynamicMemberLookup
public struct JoinQueryField<T: Schema>: Sendable {
    let tableName: String
    
    init(tableName: String) {
        self.tableName = tableName
    }
    
    /// Access table properties for join conditions
    public subscript<V>(dynamicMember keyPath: KeyPath<T, V>) -> JoinField<V> {
        let fieldName = extractFieldName(from: keyPath, schema: T.self)
        return JoinField<V>(tableName: tableName, fieldName: fieldName)
    }
}

/// Represents a field in a join condition
public struct JoinField<V>: Sendable {
    let tableName: String
    let fieldName: String
    
    init(tableName: String, fieldName: String) {
        self.tableName = tableName
        self.fieldName = fieldName
    }
    
    /// Full qualified field name for SQL
    var qualifiedName: String {
        return "\(tableName).\(fieldName.snakeCase())"
    }
}

// MARK: - Join Field Operators

extension JoinField where V: Equatable {
    /// Equality comparison between join fields
    public static func == (lhs: JoinField<V>, rhs: JoinField<V>) -> QueryCondition {
        QueryCondition(sql: "\(lhs.qualifiedName) = \(rhs.qualifiedName)")
    }
    
    /// Equality comparison with value
    public static func == (lhs: JoinField<V>, rhs: V) -> QueryCondition {
        QueryCondition(sql: "\(lhs.qualifiedName) = $1", parameters: [convertToPostgresData(rhs)])
    }
    
    /// Inequality comparison between join fields
    public static func != (lhs: JoinField<V>, rhs: JoinField<V>) -> QueryCondition {
        QueryCondition(sql: "\(lhs.qualifiedName) != \(rhs.qualifiedName)")
    }
}

extension JoinField where V: Comparable {
    /// Greater than comparison between join fields
    public static func > (lhs: JoinField<V>, rhs: JoinField<V>) -> QueryCondition {
        QueryCondition(sql: "\(lhs.qualifiedName) > \(rhs.qualifiedName)")
    }
    
    /// Less than comparison between join fields
    public static func < (lhs: JoinField<V>, rhs: JoinField<V>) -> QueryCondition {
        QueryCondition(sql: "\(lhs.qualifiedName) < \(rhs.qualifiedName)")
    }
}

// MARK: - Helper Functions for Joins

private func extractFieldName<T: Schema, V>(from keyPath: KeyPath<T, V>, schema: T.Type) -> String {
    let keyPathString = "\(keyPath)"
    let components = keyPathString.components(separatedBy: ".")
    guard let propertyName = components.last else {
        return keyPathString
    }
    return propertyName
}

// MARK: - Repository Integration

extension DatabaseRepo {
    /// Create a type-safe query for a schema
    public func query<T: Schema>(_ schema: T.Type) -> Query<T> {
        return Query(schema: schema, connection: connection)
    }
}


