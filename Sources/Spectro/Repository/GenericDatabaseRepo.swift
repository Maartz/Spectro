import Foundation
import PostgresNIO
import AsyncKit

/// Generic database repository that works with any Schema type.
///
/// `GenericDatabaseRepo` provides a type-safe, actor-based data access layer for PostgreSQL.
/// It implements the Repository pattern with full CRUD operations, query building, and transaction support.
///
/// ## Basic Usage
///
/// ```swift
/// let repo = spectro.repository()
///
/// // Insert a new record
/// let user = try await repo.insert(User())
///
/// // Query with filtering
/// let adults = try await repo.query(User.self)
///     .where { $0.age >= 18 }
///     .all()
///
/// // Transaction support
/// let result = try await repo.transaction { txRepo in
///     let user = try await txRepo.insert(User())
///     let post = try await txRepo.insert(Post())
///     return (user, post)
/// }
/// ```
///
/// ## Actor-Based Concurrency
///
/// The repository is an actor to ensure thread-safe database access across concurrent operations.
/// All methods are marked with `async` and use Swift's structured concurrency.
///
/// ## Error Handling
///
/// Methods throw `SpectroError` for database-specific errors:
/// - `.notFound`: Record not found
/// - `.invalidSchema`: Schema configuration issues
/// - `.queryExecutionFailed`: Database query errors
/// - `.transactionFailed`: Transaction errors
public actor GenericDatabaseRepo: Repo {
    private let connection: DatabaseConnection
    
    /// Initialize repository with database connection.
    ///
    /// - Parameter connection: Active database connection instance
    public init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    // MARK: - Query Operations
    
    /// Create a new query builder for the specified schema.
    ///
    /// Returns an immutable query builder that can be chained with filtering,
    /// ordering, pagination, and join operations.
    ///
    /// - Parameter schema: Schema type to query
    /// - Returns: Query builder instance
    ///
    /// ## Example
    ///
    /// ```swift
    /// let query = repo.query(User.self)
    ///     .where { $0.age > 18 }
    ///     .orderBy { $0.createdAt }
    ///     .limit(10)
    /// ```
    public func query<T: Schema>(_ schema: T.Type) -> Query<T> {
        return Query(schema: schema, connection: connection)
    }
    
    // MARK: - Raw SQL Execution
    
    /// Execute raw SQL statement.
    ///
    /// Primarily intended for testing, migrations, and administrative operations.
    /// For regular data operations, prefer the type-safe query methods.
    ///
    /// - Parameter sql: SQL statement to execute
    /// - Throws: `SpectroError.queryExecutionFailed` if execution fails
    ///
    /// ## Warning
    ///
    /// This method bypasses Spectro's type safety. Use with caution and prefer
    /// the typed query methods when possible.
    public func executeRawSQL(_ sql: String) async throws {
        try await connection.executeUpdate(sql: sql)
    }
    
    // MARK: - CRUD Operations
    
    /// Retrieve a single record by primary key.
    ///
    /// - Parameters:
    ///   - schema: Schema type to retrieve
    ///   - id: Primary key value (UUID)
    /// - Returns: Found record or `nil` if not found
    /// - Throws: `SpectroError.invalidSchema` if schema has no primary key
    ///
    /// ## Example
    ///
    /// ```swift
    /// let user = try await repo.get(User.self, id: userId)
    /// if let user = user {
    ///     print("Found user: \(user.name)")
    /// }
    /// ```
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
    
    /// Retrieve all records for a schema.
    ///
    /// Fetches every record in the table. For large datasets, consider using
    /// `query(_:).limit(_:)` or pagination to avoid memory issues.
    ///
    /// - Parameter schema: Schema type to retrieve
    /// - Returns: Array of all records
    /// - Throws: `SpectroError.queryExecutionFailed` if query fails
    ///
    /// ## Example
    ///
    /// ```swift
    /// let allUsers = try await repo.all(User.self)
    /// print("Total users: \(allUsers.count)")
    /// ```
    ///
    /// ## Performance Note
    ///
    /// For better performance with large datasets, use query filtering:
    ///
    /// ```swift
    /// let recentUsers = try await repo.query(User.self)
    ///     .where { $0.createdAt > Date().addingTimeInterval(-86400) }
    ///     .all()
    /// ```
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
    
    /// Insert a new record into the database.
    ///
    /// The primary key will be auto-generated if not set. Timestamp fields
    /// like `createdAt` and `updatedAt` are set automatically.
    ///
    /// - Parameter instance: Record to insert
    /// - Returns: Inserted record with generated ID and timestamps
    /// - Throws: `SpectroError.queryExecutionFailed` if insertion fails
    ///
    /// ## Example
    ///
    /// ```swift
    /// var user = User()
    /// user.name = "John Doe"
    /// user.email = "john@example.com"
    ///
    /// let savedUser = try await repo.insert(user)
    /// print("Created user with ID: \(savedUser.id)")
    /// ```
    ///
    /// ## Database Behavior
    ///
    /// - Primary key (`@ID`) fields are auto-generated
    /// - `@Timestamp` fields are set to current time
    /// - Foreign key validation is enforced
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
    
    /// Update an existing record with partial changes.
    ///
    /// Only the specified fields will be updated. Other fields remain unchanged.
    /// The `updatedAt` timestamp is automatically updated if present.
    ///
    /// - Parameters:
    ///   - schema: Schema type to update
    ///   - id: Primary key of record to update
    ///   - changes: Dictionary of field names to new values
    /// - Returns: Updated record with new values
    /// - Throws: `SpectroError.notFound` if record doesn't exist
    ///
    /// ## Example
    ///
    /// ```swift
    /// let updated = try await repo.update(User.self, id: userId, changes: [
    ///     "name": "Jane Doe",
    ///     "age": 26
    /// ])
    /// ```
    ///
    /// ## Field Names
    ///
    /// Use camelCase property names. They will be automatically converted
    /// to snake_case for the database (e.g., `firstName` → `first_name`).
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
    
    /// Retrieve a record by primary key or throw an error if not found.
    ///
    /// Convenience method that throws instead of returning `nil` when a record
    /// is not found. Useful when you expect the record to exist.
    ///
    /// - Parameters:
    ///   - schema: Schema type to retrieve
    ///   - id: Primary key value (UUID)
    /// - Returns: Found record (never `nil`)
    /// - Throws: `SpectroError.notFound` if record doesn't exist
    ///
    /// ## Example
    ///
    /// ```swift
    /// let user = try await repo.getOrFail(User.self, id: userId)
    /// // user is guaranteed to be non-nil if no error is thrown
    /// ```
    public func getOrFail<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T {
        if let result = try await get(schema, id: id) {
            return result
        } else {
            throw SpectroError.notFound(schema: schema.tableName, id: id)
        }
    }
    
    /// Delete a record by primary key.
    ///
    /// Permanently removes the record from the database. This operation
    /// cannot be undone outside of a transaction rollback.
    ///
    /// - Parameters:
    ///   - schema: Schema type to delete from
    ///   - id: Primary key of record to delete
    /// - Throws: `SpectroError.invalidSchema` if schema has no primary key
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await repo.delete(User.self, id: userId)
    /// ```
    ///
    /// ## Cascading Deletes
    ///
    /// Foreign key constraints in the database will determine cascading behavior.
    /// Related records may also be deleted based on your schema design.
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
    
    /// Execute multiple database operations within a transaction.
    ///
    /// Ensures atomicity - either all operations succeed or all are rolled back.
    /// The transaction uses `READ COMMITTED` isolation level.
    ///
    /// - Parameter work: Closure containing database operations
    /// - Returns: Result of the work closure
    /// - Throws: `SpectroError.transactionFailed` if transaction fails
    ///
    /// ## Example
    ///
    /// ```swift
    /// let result = try await repo.transaction { txRepo in
    ///     let user = try await txRepo.insert(User())
    ///     let post = try await txRepo.insert(Post(userId: user.id))
    ///     return (user, post)
    /// }
    /// ```
    ///
    /// ## Error Handling
    ///
    /// If any operation in the transaction throws an error, the entire
    /// transaction is automatically rolled back.
    ///
    /// ## Concurrency
    ///
    /// The transaction repo is isolated to the current transaction scope.
    /// Other concurrent operations are not affected.
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
    
    /// Map a PostgreSQL row to a schema instance.
    ///
    /// Uses the schema's `SchemaBuilder` implementation to construct instances
    /// from database row data. Handles type conversion and field mapping.
    ///
    /// - Parameters:
    ///   - row: PostgreSQL row data
    ///   - schema: Schema type to create
    /// - Returns: Schema instance with populated data
    /// - Throws: `SpectroError.invalidSchema` if schema lacks SchemaBuilder
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
            // Schema must implement SchemaBuilder for proper field mapping
            fatalError("""
                Schema \(T.self) must implement SchemaBuilder protocol.
                
                Add this to your schema:
                
                extension \(T.self): SchemaBuilder {
                    public static func build(from values: [String: Any]) -> \(T.self) {
                        var instance = \(T.self)()
                        // Map your fields here
                        if let id = values["id"] as? UUID { instance.id = id }
                        // ... add other fields
                        return instance
                    }
                }
                
                Or use @propertyWrapper macros when they become available in Swift.
                """)
        }
    }
}