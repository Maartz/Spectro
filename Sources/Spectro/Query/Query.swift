import Foundation
import PostgresKit

/// KeyPath-based query builder for type-safe database operations
/// 
/// Usage:
/// ```swift
/// let users = try await repo.query(User.self)
///     .where(\.name, .equals, "John")
///     .where(\.age, .greaterThan, 18)
///     .orderBy(\.createdAt, .desc)
///     .limit(10)
///     .all()
/// ```
public struct Query<T: Schema>: Sendable {
    private let schema: T.Type
    internal let connection: DatabaseConnection
    private var conditions: [QueryCondition] = []
    private var orderFields: [OrderByClause] = []
    private var limitValue: Int?
    private var offsetValue: Int?
    private var selectedFields: Set<String>?
    
    internal init(schema: T.Type, connection: DatabaseConnection) {
        self.schema = schema
        self.connection = connection
    }
    
    // MARK: - Where Clauses
    
    /// Add a where condition using KeyPath
    public func `where`<V: Sendable & Equatable>(
        _ keyPath: KeyPath<T, V>,
        _ operation: QueryOperation,
        _ value: V
    ) -> Query<T> {
        var copy = self
        let fieldName = extractFieldName(from: keyPath)
        copy.conditions.append(QueryCondition(
            field: fieldName,
            operation: operation,
            value: .single(value)
        ))
        return copy
    }
    
    /// Add a where condition for optional values
    public func `where`<V: Sendable & Equatable>(
        _ keyPath: KeyPath<T, V?>,
        _ operation: QueryOperation,
        _ value: V?
    ) -> Query<T> {
        var copy = self
        let fieldName = extractFieldName(from: keyPath)
        
        if let value = value {
            copy.conditions.append(QueryCondition(
                field: fieldName,
                operation: operation,
                value: .single(value)
            ))
        } else {
            copy.conditions.append(QueryCondition(
                field: fieldName,
                operation: .isNull,
                value: .null
            ))
        }
        return copy
    }
    
    /// Add an IN condition
    public func `where`<V: Sendable & Equatable>(
        _ keyPath: KeyPath<T, V>,
        in values: [V]
    ) -> Query<T> {
        var copy = self
        let fieldName = extractFieldName(from: keyPath)
        copy.conditions.append(QueryCondition(
            field: fieldName,
            operation: .in,
            value: .array(values.map { $0 as Any })
        ))
        return copy
    }
    
    /// Add a BETWEEN condition
    public func `where`<V: Sendable & Comparable>(
        _ keyPath: KeyPath<T, V>,
        between start: V,
        and end: V
    ) -> Query<T> {
        var copy = self
        let fieldName = extractFieldName(from: keyPath)
        copy.conditions.append(QueryCondition(
            field: fieldName,
            operation: .between,
            value: .range(start, end)
        ))
        return copy
    }
    
    // MARK: - Ordering
    
    /// Add order by clause using KeyPath
    public func orderBy<V>(
        _ keyPath: KeyPath<T, V>,
        _ direction: OrderDirection = .asc
    ) -> Query<T> {
        var copy = self
        let fieldName = extractFieldName(from: keyPath)
        copy.orderFields.append(OrderByClause(field: fieldName, direction: direction))
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
    
    // MARK: - Selection
    
    /// Select specific fields using KeyPaths
    public func select<V>(_ keyPath: KeyPath<T, V>) -> Query<T> {
        var copy = self
        let fieldName = extractFieldName(from: keyPath)
        if copy.selectedFields == nil {
            copy.selectedFields = Set()
        }
        copy.selectedFields?.insert(fieldName)
        return copy
    }
    
    /// Select multiple fields using KeyPaths
    public func select<V1, V2>(
        _ keyPath1: KeyPath<T, V1>,
        _ keyPath2: KeyPath<T, V2>
    ) -> Query<T> {
        return select(keyPath1).select(keyPath2)
    }
    
    /// Select three fields using KeyPaths
    public func select<V1, V2, V3>(
        _ keyPath1: KeyPath<T, V1>,
        _ keyPath2: KeyPath<T, V2>,
        _ keyPath3: KeyPath<T, V3>
    ) -> Query<T> {
        return select(keyPath1).select(keyPath2).select(keyPath3)
    }
    
    // MARK: - Execution
    
    /// Execute query and return all results
    public func all() async throws -> [T] {
        let sql = try buildSQL()
        let parameters = try buildParameters()
        
        let results = try await connection.executeQuery(
            sql: sql,
            parameters: parameters,
            resultMapper: { row in
                try mapRowToSchema(row)
            }
        )
        
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
            throw SpectroError.notFound(schema: T.tableName, id: UUID()) // TODO: Better error
        }
        return result
    }
    
    /// Count the number of results
    public func count() async throws -> Int {
        let sql = try buildCountSQL()
        let parameters = try buildParameters()
        
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
    
    internal func buildSQL() throws -> String {
        let table = T.tableName
        let selectClause = buildSelectClause()
        let whereClause = try buildWhereClause()
        let orderClause = buildOrderClause()
        let limitClause = buildLimitClause()
        
        var sql = "SELECT \(selectClause) FROM \(table)"
        
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
    
    internal func buildCountSQL() throws -> String {
        let table = T.tableName
        let whereClause = try buildWhereClause()
        
        var sql = "SELECT COUNT(*) as count FROM \(table)"
        
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
    
    private func buildWhereClause() throws -> String {
        guard !conditions.isEmpty else { return "" }
        
        let clauses = try conditions.enumerated().map { index, condition in
            let paramIndex = index + 1
            
            switch condition.operation {
            case .isNull:
                return "\(condition.field) IS NULL"
            case .isNotNull:
                return "\(condition.field) IS NOT NULL"
            case .in:
                if case .array(let values) = condition.value {
                    let placeholders = (0..<values.count).map { "$\(paramIndex + $0)" }.joined(separator: ", ")
                    return "\(condition.field) IN (\(placeholders))"
                } else {
                    throw SpectroError.invalidParameter(name: "value", value: condition.value, reason: "IN operation requires array value")
                }
            case .between:
                return "\(condition.field) BETWEEN $\(paramIndex) AND $\(paramIndex + 1)"
            default:
                return "\(condition.field) \(condition.operation.sql) $\(paramIndex)"
            }
        }
        
        return clauses.joined(separator: " AND ")
    }
    
    private func buildOrderClause() -> String {
        guard !orderFields.isEmpty else { return "" }
        
        return orderFields.map { "\($0.field) \($0.direction.sql)" }
            .joined(separator: ", ")
    }
    
    private func buildLimitClause() -> String {
        var clause = ""
        
        if let limit = limitValue {
            clause += " LIMIT \(limit)"
        }
        
        if let offset = offsetValue {
            clause += " OFFSET \(offset)"
        }
        
        return clause
    }
    
    internal func buildParameters() throws -> [PostgresData] {
        var parameters: [PostgresData] = []
        
        for condition in conditions {
            switch condition.value {
            case .single(let value):
                parameters.append(try convertToPostgresData(value))
            case .array(let values):
                for value in values {
                    parameters.append(try convertToPostgresData(value))
                }
            case .range(let start, let end):
                parameters.append(try convertToPostgresData(start))
                parameters.append(try convertToPostgresData(end))
            case .null:
                break // No parameter needed for NULL
            }
        }
        
        return parameters
    }
    
    // MARK: - Helper Methods
    
    private func extractFieldName<V>(from keyPath: KeyPath<T, V>) -> String {
        // Try static field mapping first (most efficient)
        if let schema = T.self as? FieldNameProvider.Type {
            let keyPathString = String(describing: keyPath)
            if let fieldName = schema.fieldNames[keyPathString] {
                return fieldName
            }
        }
        
        // Fallback to runtime extraction
        return KeyPathFieldExtractor.extractFieldName(from: keyPath, schema: T.self)
    }
    
    internal func mapRowToSchema(_ row: PostgresRow) throws -> T {
        var instance = T()
        let randomAccess = row.makeRandomAccess()
        
        // Use reflection to map database values to property wrapper fields
        let mirror = Mirror(reflecting: instance)
        
        for child in mirror.children {
            guard let label = child.label else { continue }
            
            // Remove property wrapper underscore prefix if present
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            
            // Try to get the database column value
            let dbValue = randomAccess[data: fieldName]
            
            // Map database value to the appropriate Swift type
            do {
                try mapDatabaseValueToProperty(&instance, label: label, dbValue: dbValue)
            } catch {
                // Continue mapping other fields even if one fails
                // This provides resilient behavior for optional fields
                continue
            }
        }
        
        return instance
    }
    
    private func mapDatabaseValueToProperty<U: Schema>(_ instance: inout U, label: String, dbValue: PostgresData) throws {
        let mirror = Mirror(reflecting: instance)
        
        // This is a simplified implementation using reflection
        // In a production system, we'd use property wrapper metadata or code generation
        
        // For now, we'll handle the most common cases
        // The actual mapping would need to be more sophisticated for a complete implementation
        
        if label == "id" || label == "_id" {
            if let uuid = dbValue.uuid {
                // Use reflection to set the ID field
                // This is simplified - real implementation would use proper property wrapper access
            }
        }
        
        // Note: This is a placeholder implementation
        // A complete implementation would:
        // 1. Use property wrapper metadata to determine field types
        // 2. Properly convert PostgresData to Swift types
        // 3. Handle relationships and complex types
        // 4. Support all property wrapper types (@Column, @Timestamp, etc.)
    }
    
    private func convertToPostgresData(_ value: Any) throws -> PostgresData {
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
        default:
            throw SpectroError.invalidParameter(
                name: "value",
                value: value,
                reason: "Unsupported type for PostgreSQL parameter: \(type(of: value))"
            )
        }
    }
}

// MARK: - Supporting Types

/// Query operations for type-safe conditions
public enum QueryOperation: String, Sendable {
    case equals = "="
    case notEquals = "!="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case like = "LIKE"
    case ilike = "ILIKE"
    case isNull = "IS NULL"
    case isNotNull = "IS NOT NULL"
    case `in` = "IN"
    case between = "BETWEEN"
    
    var sql: String {
        return rawValue
    }
}

/// Internal query condition representation
private struct QueryCondition: Sendable {
    let field: String
    let operation: QueryOperation
    let value: QueryValue
}

/// Internal value representation for queries
private enum QueryValue: Sendable {
    case single(Any)
    case array([Any])
    case range(Any, Any)
    case null
}

/// Order by clause representation
private struct OrderByClause: Sendable {
    let field: String
    let direction: OrderDirection
}

// MARK: - Repository Integration

extension DatabaseRepo {
    /// Create a type-safe query for a schema
    public func query<T: Schema>(_ schema: T.Type) -> Query<T> {
        return Query(schema: schema, connection: connection)
    }
}

