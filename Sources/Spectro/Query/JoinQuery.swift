import Foundation
import PostgresNIO

/// Query that includes joined tables and returns combined results
public struct JoinQuery<T: Schema, U: Schema>: Sendable {
    private let baseQuery: Query<T>
    private let joinedSchema: U.Type
    private let joinClause: JoinClause
    
    internal init(baseQuery: Query<T>, joinedSchema: U.Type, joinClause: JoinClause) {
        self.baseQuery = baseQuery
        self.joinedSchema = joinedSchema
        self.joinClause = joinClause
    }
    
    /// Execute join query and return tuples of (main, joined) records
    public func all() async throws -> [(T, U?)] {
        let sql = buildJoinSQL()
        
        let results = try await baseQuery.connection.executeQuery(
            sql: sql,
            parameters: baseQuery.parameters,
            resultMapper: { row in
                // Since the resultMapper needs to be synchronous, we'll need to use Schema.from(row:) 
                // in a synchronous way or change the implementation approach
                do {
                    let mainRecord = try T.fromSync(row: row)
                    let joinedRecord: U?
                    do {
                        joinedRecord = try U.fromSync(row: row)
                    } catch {
                        joinedRecord = nil
                    }
                    return (mainRecord, joinedRecord)
                } catch {
                    throw error
                }
            }
        )
        
        return results
    }
    
    /// Execute query and return first result
    public func first() async throws -> (T, U?)? {
        let results = try await limit(1).all()
        return results.first
    }
    
    /// Add where conditions to the join query
    public func `where`(_ condition: (JoinQueryBuilder<T, U>) -> QueryCondition) -> JoinQuery<T, U> {
        let builder = JoinQueryBuilder<T, U>()
        let queryCondition = condition(builder)
        
        // Create a new base query with the additional condition
        var newBaseQuery = baseQuery
        if newBaseQuery.whereClause.isEmpty {
            newBaseQuery.whereClause = queryCondition.sql
        } else {
            newBaseQuery.whereClause += " AND (\(queryCondition.sql))"
        }
        newBaseQuery.parameters.append(contentsOf: queryCondition.parameters)
        
        return JoinQuery(baseQuery: newBaseQuery, joinedSchema: joinedSchema, joinClause: joinClause)
    }
    
    /// Add ordering to the join query
    public func orderBy<V>(_ field: (JoinQueryBuilder<T, U>) -> JoinField<V>, _ direction: OrderDirection = .asc) -> JoinQuery<T, U> {
        let builder = JoinQueryBuilder<T, U>()
        let joinField = field(builder)
        
        var newBaseQuery = baseQuery
        newBaseQuery.orderFields.append(OrderByClause(field: joinField.qualifiedName, direction: direction))
        
        return JoinQuery(baseQuery: newBaseQuery, joinedSchema: joinedSchema, joinClause: joinClause)
    }
    
    /// Limit results
    public func limit(_ count: Int) -> JoinQuery<T, U> {
        var newBaseQuery = baseQuery
        newBaseQuery.limitValue = count
        return JoinQuery(baseQuery: newBaseQuery, joinedSchema: joinedSchema, joinClause: joinClause)
    }
    
    /// Offset results
    public func offset(_ count: Int) -> JoinQuery<T, U> {
        var newBaseQuery = baseQuery
        newBaseQuery.offsetValue = count
        return JoinQuery(baseQuery: newBaseQuery, joinedSchema: joinedSchema, joinClause: joinClause)
    }
    
    // MARK: - Private Methods
    
    private func buildJoinSQL() -> String {
        let mainTable = T.tableName
        let joinTable = U.tableName
        
        // Select all columns from both tables with table prefixes
        let mainColumns = buildColumnsWithPrefix(for: T.self, prefix: mainTable)
        let joinColumns = buildColumnsWithPrefix(for: U.self, prefix: joinTable)
        let selectClause = "\(mainColumns), \(joinColumns)"
        
        var sql = "SELECT \(selectClause) FROM \(mainTable)"
        sql += " \(joinClause.type.sql) \(joinTable) ON \(joinClause.condition)"
        
        if !baseQuery.whereClause.isEmpty {
            sql += " WHERE \(baseQuery.whereClause)"
        }
        
        if !baseQuery.orderFields.isEmpty {
            let orderClause = baseQuery.orderFields.map { "\($0.field) \($0.direction.sql)" }.joined(separator: ", ")
            sql += " ORDER BY \(orderClause)"
        }
        
        if let limit = baseQuery.limitValue {
            sql += " LIMIT \(limit)"
        }
        
        if let offset = baseQuery.offsetValue {
            sql += " OFFSET \(offset)"
        }
        
        return sql
    }
    
    private func buildColumnsWithPrefix<S: Schema>(for schemaType: S.Type, prefix: String) -> String {
        // In a real implementation, we'd get column names from schema metadata
        // For now, we'll use a simplified approach
        return "\(prefix).*"
    }
    
    private func mapJoinedRow(_ row: PostgresRow) async throws -> (T, U?) {
        // Map the main record
        let mainRecord = try await T.from(row: row)
        
        // Try to map the joined record
        // We need to handle the case where the join might be LEFT/RIGHT and return NULL
        let joinedRecord: U?
        do {
            joinedRecord = try await U.from(row: row)
        } catch {
            // If mapping fails (e.g., due to NULL values in LEFT JOIN), set to nil
            joinedRecord = nil
        }
        
        return (mainRecord, joinedRecord)
    }
}

/// Builder for creating conditions on joined queries
@dynamicMemberLookup
public struct JoinQueryBuilder<T: Schema, U: Schema>: Sendable {
    public init() {}
    
    /// Access main table fields
    public var main: JoinQueryField<T> {
        JoinQueryField<T>(tableName: T.tableName)
    }
    
    /// Access joined table fields
    public var joined: JoinQueryField<U> {
        JoinQueryField<U>(tableName: U.tableName)
    }
    
    /// Dynamic member lookup for main table fields
    public subscript<V>(dynamicMember keyPath: KeyPath<T, V>) -> JoinField<V> {
        let fieldName = extractFieldName(from: keyPath, schema: T.self)
        return JoinField<V>(tableName: T.tableName, fieldName: fieldName)
    }
}

// MARK: - Helper Functions for JoinQueryBuilder

private func extractFieldName<T: Schema, V>(from keyPath: KeyPath<T, V>, schema: T.Type) -> String {
    let keyPathString = "\(keyPath)"
    let components = keyPathString.components(separatedBy: ".")
    guard let propertyName = components.last else {
        return keyPathString
    }
    return propertyName
}

// MARK: - Extensions to Query for JOIN execution

extension Query {
    /// Execute as a join query with typed results
    public func executeJoin<U: Schema>(with joinedType: U.Type) -> JoinQuery<T, U> {
        // Find the join clause for the specified type
        guard let joinClause = joins.first(where: { $0.table == joinedType.tableName }) else {
            fatalError("No join found for schema type \(joinedType)")
        }
        
        return JoinQuery(baseQuery: self, joinedSchema: joinedType, joinClause: joinClause)
    }
    
    /// Convenience method to join and immediately execute
    public func joinAndExecute<U: Schema>(
        _ joinSchema: U.Type,
        on condition: (JoinBuilder<T, U>) -> QueryCondition
    ) async throws -> [(T, U?)] {
        return try await self
            .join(joinSchema, on: condition)
            .executeJoin(with: joinSchema)
            .all()
    }
    
    /// Left join and execute
    public func leftJoinAndExecute<U: Schema>(
        _ joinSchema: U.Type,
        on condition: (JoinBuilder<T, U>) -> QueryCondition
    ) async throws -> [(T, U?)] {
        return try await self
            .leftJoin(joinSchema, on: condition)
            .executeJoin(with: joinSchema)
            .all()
    }
}