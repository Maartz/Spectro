import Foundation
import PostgresNIO
import AsyncKit

/// Generic database repository that works with any Schema type
/// This replaces the hardcoded DatabaseRepo with a truly generic implementation
public actor GenericDatabaseRepo: Repo {
    private let connection: DatabaseConnection
    
    public init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    // MARK: - Query Operations
    
    public func query<T: Schema>(_ schema: T.Type) -> Query<T> {
        return Query(schema: schema, connection: connection)
    }
    
    // MARK: - Raw SQL Execution (for testing/migrations)
    
    /// Execute raw SQL - primarily for testing and migrations
    public func executeRawSQL(_ sql: String) async throws {
        try await connection.executeUpdate(sql: sql)
    }
    
    // MARK: - CRUD Operations
    
    public func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T? {
        let metadata = await SchemaRegistry.shared.register(schema)
        
        guard let primaryKey = metadata.primaryKeyField else {
            throw SpectroError.invalidSchema(reason: "Schema \(T.self) has no primary key field")
        }
        
        let sql = """
            SELECT * FROM \(metadata.tableName) 
            WHERE \(primaryKey.snakeCase()) = $1
            """
        
        let rows = try await connection.executeQuery(
            sql: sql,
            parameters: [PostgresData(uuid: id)],
            resultMapper: { $0 }
        )
        
        guard let row = rows.first else {
            return nil
        }
        
        return try await mapRowToSchema(row, schema: schema)
    }
    
    public func all<T: Schema>(_ schema: T.Type) async throws -> [T] {
        let metadata = await SchemaRegistry.shared.register(schema)
        let sql = "SELECT * FROM \(metadata.tableName)"
        let rows = try await connection.executeQuery(
            sql: sql,
            resultMapper: { $0 }
        )
        
        var results: [T] = []
        for row in rows {
            let instance = try await mapRowToSchema(row, schema: schema)
            results.append(instance)
        }
        
        return results
    }
    
    public func insert<T: Schema>(_ instance: T) async throws -> T {
        let metadata = await SchemaRegistry.shared.register(T.self)
        let data = SchemaMapper.extractData(from: instance, metadata: metadata, excludePrimaryKey: true)
        
        // Build INSERT query
        let columns = data.keys.joined(separator: ", ")
        let placeholders = (1...data.count).map { "$\($0)" }.joined(separator: ", ")
        let values = Array(data.values)
        
        let sql = """
            INSERT INTO \(metadata.tableName) (\(columns))
            VALUES (\(placeholders))
            RETURNING *
            """
        
        let rows = try await connection.executeQuery(
            sql: sql,
            parameters: values,
            resultMapper: { $0 }
        )
        
        guard let row = rows.first else {
            throw SpectroError.databaseError(reason: "Insert did not return a row")
        }
        
        return try await mapRowToSchema(row, schema: T.self)
    }
    
    public func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: Any]) async throws -> T {
        let metadata = await SchemaRegistry.shared.register(schema)
        
        guard let primaryKey = metadata.primaryKeyField else {
            throw SpectroError.invalidSchema(reason: "Schema \(schema) has no primary key field")
        }
        
        // Convert changes to PostgresData
        var setClause: [String] = []
        var values: [PostgresData] = []
        var paramIndex = 1
        
        for (column, value) in changes {
            setClause.append("\(column.snakeCase()) = $\(paramIndex)")
            values.append(try SchemaMapper.convertToPostgresData(value))
            paramIndex += 1
        }
        
        values.append(PostgresData(uuid: id))
        
        let sql = """
            UPDATE \(metadata.tableName)
            SET \(setClause.joined(separator: ", "))
            WHERE \(primaryKey.snakeCase()) = $\(paramIndex)
            RETURNING *
            """
        
        let rows = try await connection.executeQuery(
            sql: sql,
            parameters: values,
            resultMapper: { $0 }
        )
        
        guard let row = rows.first else {
            throw SpectroError.databaseError(reason: "Update did not return a row")
        }
        
        return try await mapRowToSchema(row, schema: schema)
    }
    
    public func getOrFail<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T {
        if let result = try await get(schema, id: id) {
            return result
        } else {
            throw SpectroError.notFound(schema: schema.tableName, id: id)
        }
    }
    
    public func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws {
        let metadata = await SchemaRegistry.shared.register(schema)
        
        guard let primaryKey = metadata.primaryKeyField else {
            throw SpectroError.invalidSchema(reason: "Schema \(T.self) has no primary key field")
        }
        
        let sql = """
            DELETE FROM \(metadata.tableName)
            WHERE \(primaryKey.snakeCase()) = $1
            """
        
        try await connection.executeUpdate(sql: sql, parameters: [PostgresData(uuid: id)])
    }
    
    public func transaction<T: Sendable>(_ work: @escaping @Sendable (Repo) async throws -> T) async throws -> T {
        // Start transaction
        try await executeRawSQL("BEGIN ISOLATION LEVEL READ COMMITTED")
        
        do {
            // Create a new repo instance for the transaction
            let transactionRepo = GenericDatabaseRepo(connection: connection)
            let result = try await work(transactionRepo)
            
            // Commit transaction
            try await executeRawSQL("COMMIT")
            return result
        } catch {
            // Rollback on error
            do {
                try await executeRawSQL("ROLLBACK")
            } catch {
                // Log rollback failure but don't mask original error
                print("Warning: Failed to rollback transaction: \(error)")
            }
            throw error
        }
    }
    
    // MARK: - Private Mapping Methods
    
    private func mapRowToSchema<T: Schema>(_ row: PostgresRow, schema: T.Type) async throws -> T {
        let metadata = await SchemaRegistry.shared.register(schema)
        var instance = T()
        let randomAccess = row.makeRandomAccess()
        
        // Build values dictionary from row
        var values: [String: Any] = [:]
        
        for field in metadata.fields {
            let dbValue = randomAccess[data: field.databaseName]
            // Extract value based on field type
            if let value = SchemaMapper.extractValue(from: dbValue, expectedType: field.type) {
                values[field.name] = value
            }
        }
        
        // Apply values to instance
        if let builderType = T.self as? any SchemaBuilder.Type {
            return builderType.build(from: values) as! T
        } else {
            // For schemas that don't implement SchemaBuilder,
            // we need a different approach. For now, we'll return
            // the default instance and log a warning
            print("Warning: Schema \(T.self) should implement SchemaBuilder for full functionality")
            return instance
        }
    }
}