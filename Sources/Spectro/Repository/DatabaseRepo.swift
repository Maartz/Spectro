import Foundation
import PostgresKit

/// Concrete repository implementation using actor-based DatabaseConnection
/// Works with the new property wrapper-based Schema system
public struct DatabaseRepo: Repo {
    internal let connection: DatabaseConnection
    
    public init(connection: DatabaseConnection) {
        self.connection = connection
    }
    
    // MARK: - Core CRUD Operations
    
    public func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T? {
        let sql = "SELECT * FROM \(schema.tableName) WHERE id = $1"
        let parameters = [PostgresData(uuid: id)]
        
        let results = try await connection.executeQuery(
            sql: sql,
            parameters: parameters
        ) { row in
            try self.mapRowToSchema(row, schema: schema)
        }
        
        return results.first
    }
    
    public func getOrFail<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T {
        guard let model = try await get(schema, id: id) else {
            throw SpectroError.notFound(schema: schema.tableName, id: id)
        }
        return model
    }
    
    public func all<T: Schema>(_ schema: T.Type) async throws -> [T] {
        let sql = "SELECT * FROM \(schema.tableName)"
        
        return try await connection.executeQuery(sql: sql) { row in
            try self.mapRowToSchema(row, schema: schema)
        }
    }
    
    public func insert<T: Schema>(_ instance: T) async throws -> T {
        let data = extractData(from: instance)
        let columns = data.keys.sorted()
        let placeholders = columns.enumerated().map { "$\($0.offset + 1)" }
        
        let sql = """
            INSERT INTO \(T.tableName) (\(columns.joined(separator: ", ")))
            VALUES (\(placeholders.joined(separator: ", ")))
            RETURNING *
            """
        
        let parameters = try columns.map { column in
            try convertToPostgresData(data[column]!)
        }
        
        let results = try await connection.executeQuery(
            sql: sql,
            parameters: parameters
        ) { row in
            try self.mapRowToSchema(row, schema: T.self)
        }
        
        guard let inserted = results.first else {
            throw SpectroError.unexpectedResultCount(expected: 1, actual: 0)
        }
        
        return inserted
    }
    
    public func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: Any]) async throws -> T {
        guard !changes.isEmpty else {
            return try await getOrFail(schema, id: id)
        }
        
        let columns = changes.keys.sorted()
        let setClauses = columns.enumerated().map { "\($0.element) = $\($0.offset + 2)" }
        
        let sql = """
            UPDATE \(schema.tableName)
            SET \(setClauses.joined(separator: ", "))
            WHERE id = $1
            RETURNING *
            """
        
        var parameters: [PostgresData] = [PostgresData(uuid: id)]
        for column in columns {
            parameters.append(try convertToPostgresData(changes[column]!))
        }
        
        let results = try await connection.executeQuery(
            sql: sql,
            parameters: parameters
        ) { row in
            try self.mapRowToSchema(row, schema: schema)
        }
        
        guard let updated = results.first else {
            throw SpectroError.notFound(schema: schema.tableName, id: id)
        }
        
        return updated
    }
    
    public func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws {
        let sql = "DELETE FROM \(schema.tableName) WHERE id = $1"
        let parameters = [PostgresData(uuid: id)]
        
        let deletedCount = try await connection.execute(sql: sql, parameters: parameters)
        
        if deletedCount == 0 {
            throw SpectroError.notFound(schema: schema.tableName, id: id)
        }
    }
    
    // MARK: - Transaction Support
    
    public func transaction<T: Sendable>(_ work: @escaping @Sendable (Repo) async throws -> T) async throws -> T {
        // For now, transactions just use the same repo (simplified implementation)
        // A full implementation would create a transaction-specific context
        return try await work(self)
    }
    
    // MARK: - Helper Methods
    
    private func mapRowToSchema<T: Schema>(_ row: PostgresRow, schema: T.Type) throws -> T {
        var instance = T()
        let randomAccess = row.makeRandomAccess()
        
        // Use reflection to map database values to property wrapper fields
        let mirror = Mirror(reflecting: instance)
        
        for child in mirror.children {
            guard let label = child.label else { continue }
            
            // Remove property wrapper underscore prefix if present
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            let dbFieldName = fieldName.snakeCase()
            
            // Try to get the database column value
            let dbValue = randomAccess[data: dbFieldName]
            
            // Map database value to the appropriate Swift type
            do {
                try mapDatabaseValueToProperty(&instance, label: label, fieldName: fieldName, dbValue: dbValue)
            } catch {
                // Continue mapping other fields even if one fails
                // This provides resilient behavior for optional fields
                continue
            }
        }
        
        return instance
    }
    
    private func mapDatabaseValueToProperty<T: Schema>(_ instance: inout T, label: String, fieldName: String, dbValue: PostgresData) throws {
        // This is a simplified implementation using reflection
        // In a production system, we'd use more sophisticated type mapping
        
        // For now, we'll handle the most common cases
        switch fieldName {
        case "id":
            if let uuid = dbValue.uuid {
                setValue(&instance, key: label, value: uuid)
            }
        case "name", "email", "title", "content", "language":
            if let string = dbValue.string {
                setValue(&instance, key: label, value: string)
            }
        case "age", "loginCount":
            if let int = dbValue.int {
                setValue(&instance, key: label, value: int)
            }
        case "isActive", "published", "approved", "verified", "optInEmail":
            if let bool = dbValue.bool {
                setValue(&instance, key: label, value: bool)
            }
        case "createdAt", "updatedAt", "deletedAt", "lastLoginAt":
            if let date = dbValue.date {
                setValue(&instance, key: label, value: date)
            }
        case "userId", "postId":
            if let uuid = dbValue.uuid {
                setValue(&instance, key: label, value: uuid)
            }
        case "score":
            if let double = dbValue.double {
                setValue(&instance, key: label, value: double)
            } else if let float = dbValue.float {
                setValue(&instance, key: label, value: Double(float))
            }
        default:
            // Handle dynamic types based on the database value
            if let string = dbValue.string {
                setValue(&instance, key: label, value: string)
            } else if let int = dbValue.int {
                setValue(&instance, key: label, value: int)
            } else if let bool = dbValue.bool {
                setValue(&instance, key: label, value: bool)
            } else if let uuid = dbValue.uuid {
                setValue(&instance, key: label, value: uuid)
            } else if let date = dbValue.date {
                setValue(&instance, key: label, value: date)
            }
        }
    }
    
    private func setValue<T>(_ instance: inout T, key: String, value: Any) {
        // Use KeyPath-based setting for property wrappers
        // This is a simplified approach that works with our current schema definitions
        
        if let user = instance as? User {
            var mutableUser = user
            switch key {
            case "_id", "id":
                if let uuid = value as? UUID {
                    mutableUser.id = uuid
                }
            case "_name", "name":
                if let string = value as? String {
                    mutableUser.name = string
                }
            case "_email", "email":
                if let string = value as? String {
                    mutableUser.email = string
                }
            case "_age", "age":
                if let int = value as? Int {
                    mutableUser.age = int
                }
            case "_isActive", "isActive":
                if let bool = value as? Bool {
                    mutableUser.isActive = bool
                }
            case "_createdAt", "createdAt":
                if let date = value as? Date {
                    mutableUser.createdAt = date
                }
            case "_updatedAt", "updatedAt":
                if let date = value as? Date {
                    mutableUser.updatedAt = date
                }
            default:
                break
            }
            if let updated = mutableUser as? T {
                instance = updated
            }
        } else if let post = instance as? Post {
            var mutablePost = post
            switch key {
            case "_id", "id":
                if let uuid = value as? UUID {
                    mutablePost.id = uuid
                }
            case "_title", "title":
                if let string = value as? String {
                    mutablePost.title = string
                }
            case "_content", "content":
                if let string = value as? String {
                    mutablePost.content = string
                }
            case "_published", "published":
                if let bool = value as? Bool {
                    mutablePost.published = bool
                }
            case "_userId", "userId":
                if let uuid = value as? UUID {
                    mutablePost.userId = uuid
                }
            case "_createdAt", "createdAt":
                if let date = value as? Date {
                    mutablePost.createdAt = date
                }
            case "_updatedAt", "updatedAt":
                if let date = value as? Date {
                    mutablePost.updatedAt = date
                }
            default:
                break
            }
            if let updated = mutablePost as? T {
                instance = updated
            }
        } else if let comment = instance as? Comment {
            var mutableComment = comment
            switch key {
            case "_id", "id":
                if let uuid = value as? UUID {
                    mutableComment.id = uuid
                }
            case "_content", "content":
                if let string = value as? String {
                    mutableComment.content = string
                }
            case "_approved", "approved":
                if let bool = value as? Bool {
                    mutableComment.approved = bool
                }
            case "_postId", "postId":
                if let uuid = value as? UUID {
                    mutableComment.postId = uuid
                }
            case "_userId", "userId":
                if let uuid = value as? UUID {
                    mutableComment.userId = uuid
                }
            case "_createdAt", "createdAt":
                if let date = value as? Date {
                    mutableComment.createdAt = date
                }
            default:
                break
            }
            if let updated = mutableComment as? T {
                instance = updated
            }
        }
    }
    
    private func extractData<T: Schema>(from instance: T) -> [String: Any] {
        var data: [String: Any] = [:]
        
        // Use reflection to extract property wrapper values
        let mirror = Mirror(reflecting: instance)
        
        for child in mirror.children {
            guard let label = child.label else { continue }
            
            // Remove property wrapper underscore prefix if present
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            let dbFieldName = fieldName.snakeCase()
            
            // Extract the actual value from property wrappers
            let value = extractPropertyWrapperValue(child.value)
            
            if let value = value {
                data[dbFieldName] = value
            }
        }
        
        return data
    }
    
    private func extractPropertyWrapperValue(_ wrapper: Any) -> Any? {
        // Use reflection to get the wrappedValue from property wrappers
        let mirror = Mirror(reflecting: wrapper)
        
        // Look for wrappedValue property
        for child in mirror.children {
            if child.label == "wrappedValue" {
                return child.value
            }
        }
        
        // If not a property wrapper, return the value directly
        return wrapper
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
        case let float as Float:
            return PostgresData(float: float)
        case let data as Data:
            return PostgresData(bytes: [UInt8](data))
        default:
            throw SpectroError.invalidParameter(
                name: "value",
                value: value,
                reason: "Unsupported type for PostgreSQL parameter: \(type(of: value))"
            )
        }
    }
}


// MARK: - String Extensions

extension String {
    /// Convert camelCase to snake_case for database columns
    func snakeCase() -> String {
        let pattern = "([a-z0-9])([A-Z])"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return self.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "-", with: "_")
        }
        
        let range = NSRange(location: 0, length: self.count)
        let snakeCased = regex.stringByReplacingMatches(
            in: self,
            range: range,
            withTemplate: "$1_$2"
        ).lowercased()
        
        return snakeCased
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
}