import Foundation
import PostgresKit

/// Concrete repository implementation using actor-based DatabaseConnection
/// Replaces the global state approach with explicit actor-based connection management
public struct DatabaseRepo: Repo {
    private let connection: DatabaseConnection
    
    public init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    // MARK: - Core CRUD Operations
    
    public func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T.Model? {
        let sql = "SELECT * FROM \(schema.schemaName) WHERE id = $1"
        let parameters = [PostgresData(uuid: id)]
        
        let results = try await connection.executeQuery(
            sql: sql,
            parameters: parameters
        ) { row in
            try self.mapRowToModel(row, schema: schema)
        }
        
        return results.first
    }
    
    public func getOrFail<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T.Model {
        guard let model = try await get(schema, id: id) else {
            throw SpectroError.notFound(schema: schema.schemaName, id: id)
        }
        return model
    }
    
    public func all<T: Schema>(_ schema: T.Type) async throws -> [T.Model] {
        let sql = "SELECT * FROM \(schema.schemaName)"
        
        return try await connection.executeQuery(sql: sql) { row in
            try self.mapRowToModel(row, schema: schema)
        }
    }
    
    public func insert<T: Schema>(_ schema: T.Type, data: [String: Any]) async throws -> T.Model {
        // Validate required fields exist
        try validateInsertData(data, for: schema)
        
        // Add timestamps if schema supports them
        var insertData = data
        if schema.fields.contains(where: { $0.name == "created_at" }) {
            insertData["created_at"] = Date()
        }
        if schema.fields.contains(where: { $0.name == "updated_at" }) {
            insertData["updated_at"] = Date()
        }
        
        // Generate ID if not provided
        if insertData["id"] == nil {
            insertData["id"] = UUID()
        }
        
        let columns = insertData.keys.sorted()
        let placeholders = (1...columns.count).map { "$\($0)" }.joined(separator: ", ")
        let columnsList = columns.joined(separator: ", ")
        
        let sql = """
            INSERT INTO \(schema.schemaName) (\(columnsList)) 
            VALUES (\(placeholders)) 
            RETURNING *
        """
        
        let parameters = try columns.map { column in
            try convertToPostgresData(insertData[column]!)
        }
        
        let results = try await connection.executeQuery(
            sql: sql,
            parameters: parameters
        ) { row in
            try self.mapRowToModel(row, schema: schema)
        }
        
        guard let model = results.first else {
            throw SpectroError.unexpectedResultCount(expected: 1, actual: 0)
        }
        
        return model
    }
    
    public func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: Any]) async throws -> T.Model {
        guard !changes.isEmpty else {
            return try await getOrFail(schema, id: id)
        }
        
        // Add updated_at timestamp if schema supports it
        var updateData = changes
        if schema.fields.contains(where: { $0.name == "updated_at" }) {
            updateData["updated_at"] = Date()
        }
        
        let columns = updateData.keys.sorted()
        let setClause = columns.enumerated().map { index, column in
            "\(column) = $\(index + 1)"
        }.joined(separator: ", ")
        
        let sql = """
            UPDATE \(schema.schemaName) 
            SET \(setClause) 
            WHERE id = $\(columns.count + 1) 
            RETURNING *
        """
        
        var parameters = try columns.map { column in
            try convertToPostgresData(updateData[column]!)
        }
        parameters.append(PostgresData(uuid: id))
        
        let results = try await connection.executeQuery(
            sql: sql,
            parameters: parameters
        ) { row in
            try self.mapRowToModel(row, schema: schema)
        }
        
        guard let model = results.first else {
            throw SpectroError.notFound(schema: schema.schemaName, id: id)
        }
        
        return model
    }
    
    public func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws {
        let sql = "DELETE FROM \(schema.schemaName) WHERE id = $1"
        let parameters = [PostgresData(uuid: id)]
        
        try await connection.executeUpdate(sql: sql, parameters: parameters)
    }
    
    // MARK: - Query Building
    
    public func query<T: Schema>(_ schema: T.Type) -> QueryBuilder<T> {
        QueryBuilder(schema: schema, repo: self)
    }
    
    // MARK: - Transaction Support
    
    public func transaction<T: Sendable>(_ work: @Sendable (Repo) async throws -> T) async throws -> T {
        return try await connection.transaction { transactionContext in
            let transactionRepo = TransactionRepo(context: transactionContext)
            return try await work(transactionRepo)
        }
    }
    
    // MARK: - Helper Methods
    
    private func mapRowToModel<T: Schema>(_ row: PostgresRow, schema: T.Type) throws -> T.Model {
        let randomAccess = row.makeRandomAccess()
        var data: [String: Any] = [:]
        
        // Map all available columns to dictionary
        for field in schema.fields {
            let columnData = randomAccess[data: field.name]
            
            // Convert PostgresData to appropriate Swift type
            data[field.name] = try convertFromPostgresData(columnData, fieldType: field.type)
        }
        
        return try T.Model(from: data)
    }
    
    private func convertToPostgresData(_ value: Any) throws -> PostgresData {
        switch value {
        case let uuid as UUID:
            return PostgresData(uuid: uuid)
        case let string as String:
            return PostgresData(string: string)
        case let int as Int:
            return PostgresData(int: int)
        case let bool as Bool:
            return PostgresData(bool: bool)
        case let date as Date:
            return PostgresData(date: date)
        case let double as Double:
            return PostgresData(double: double)
        case let float as Float:
            return PostgresData(float: float)
        case Optional<Any>.none:
            return PostgresData(null: ())
        default:
            throw SpectroError.invalidParameter(name: "unknown", value: value)
        }
    }
    
    private func convertFromPostgresData(_ data: PostgresData, fieldType: FieldType) throws -> Any? {
        if data.value == nil {
            return nil
        }
        
        switch fieldType {
        case .uuid:
            return data.uuid
        case .string:
            return data.string
        case .integer(defaultValue: _):
            return data.int
        case .boolean(defaultValue: _):
            return data.bool
        case .timestamp:
            return data.date
        case .float(defaultValue: _):
            return data.double
        case .jsonb:
            // For now, return as string - will improve with better JSON support
            return data.string
        }
    }
    
    private func validateInsertData<T: Schema>(_ data: [String: Any], for schema: T.Type) throws {
        // Check for required fields (those without default values)
        for field in schema.fields {
            let hasDefaultValue = field.type.hasDefaultValue
            let isProvidedInData = data[field.name] != nil
            
            if !hasDefaultValue && !isProvidedInData && field.name != "id" {
                throw SpectroError.missingRequiredField(schema: schema.schemaName, field: field.name)
            }
        }
    }
}

/// Transaction-scoped repository that works within a database transaction
private struct TransactionRepo: Repo {
    private let context: TransactionContext
    
    init(context: TransactionContext) {
        self.context = context
    }
    
    func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T.Model? {
        let sql = "SELECT * FROM \(schema.schemaName) WHERE id = $1"
        let parameters = [PostgresData(uuid: id)]
        
        let results = try await context.query(sql, parameters) { row in
            try self.mapRowToModel(row, schema: schema)
        }
        
        return results.first
    }
    
    func getOrFail<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T.Model {
        guard let model = try await get(schema, id: id) else {
            throw SpectroError.notFound(schema: schema.schemaName, id: id)
        }
        return model
    }
    
    func all<T: Schema>(_ schema: T.Type) async throws -> [T.Model] {
        let sql = "SELECT * FROM \(schema.schemaName)"
        
        return try await context.query(sql) { row in
            try self.mapRowToModel(row, schema: schema)
        }
    }
    
    func insert<T: Schema>(_ schema: T.Type, data: [String: Any]) async throws -> T.Model {
        // Same implementation as DatabaseRepo but using transaction context
        throw SpectroError.notImplemented("TransactionRepo.insert - will implement after basic structure is complete")
    }
    
    func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: Any]) async throws -> T.Model {
        throw SpectroError.notImplemented("TransactionRepo.update - will implement after basic structure is complete")
    }
    
    func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws {
        let sql = "DELETE FROM \(schema.schemaName) WHERE id = $1"
        let parameters = [PostgresData(uuid: id)]
        try await context.execute(sql, parameters)
    }
    
    func query<T: Schema>(_ schema: T.Type) -> QueryBuilder<T> {
        QueryBuilder(schema: schema, repo: self)
    }
    
    func transaction<T: Sendable>(_ work: @Sendable (Repo) async throws -> T) async throws -> T {
        // Nested transactions not supported for now
        throw SpectroError.notImplemented("Nested transactions not yet supported")
    }
    
    // MARK: - Helper Methods
    
    private func mapRowToModel<T: Schema>(_ row: PostgresRow, schema: T.Type) throws -> T.Model {
        let randomAccess = row.makeRandomAccess()
        var data: [String: Any] = [:]
        
        for field in schema.fields {
            let columnData = randomAccess[data: field.name]
            data[field.name] = try convertFromPostgresData(columnData, fieldType: field.type)
        }
        
        return try T.Model(from: data)
    }
    
    private func convertFromPostgresData(_ data: PostgresData, fieldType: FieldType) throws -> Any? {
        if data.value == nil {
            return nil
        }
        
        switch fieldType {
        case .uuid:
            return data.uuid
        case .string:
            return data.string
        case .integer(defaultValue: _):
            return data.int
        case .boolean(defaultValue: _):
            return data.bool
        case .timestamp:
            return data.date
        case .float(defaultValue: _):
            return data.double
        case .jsonb:
            return data.string
        }
    }
}

// MARK: - FieldType Extensions

extension FieldType {
    var hasDefaultValue: Bool {
        switch self {
        case .uuid, .string, .timestamp, .jsonb:
            return false
        case .integer(defaultValue: let value):
            return value != nil
        case .boolean(defaultValue: let value):
            return value != nil
        case .float(defaultValue: let value):
            return value != nil
        }
    }
}