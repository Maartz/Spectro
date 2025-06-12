import Foundation
import PostgresNIO

/// Generic schema mapper that converts between database rows and Swift types
/// Inspired by Ecto's schema compilation and ActiveRecord's attribute mapping
public struct SchemaMapper {
    
    /// Map a database row to a schema instance
    public static func mapRow<T: Schema>(
        _ row: PostgresRow,
        to schemaType: T.Type,
        metadata: SchemaMetadata
    ) throws -> T {
        var instance = T()
        let randomAccess = row.makeRandomAccess()
        
        // Create a mutable dictionary to collect values
        var values: [String: Any] = [:]
        
        for field in metadata.fields {
            let dbValue = randomAccess[data: field.databaseName]
            if let value = extractValue(from: dbValue, expectedType: field.type) {
                values[field.name] = value
            }
        }
        
        // Apply values to instance
        try applyValues(values, to: &instance, using: metadata)
        
        return instance
    }
    
    /// Extract data from a schema instance for database operations
    public static func extractData<T: Schema>(
        from instance: T,
        metadata: SchemaMetadata,
        excludePrimaryKey: Bool = false
    ) -> [String: PostgresData] {
        var data: [String: PostgresData] = [:]
        let mirror = Mirror(reflecting: instance)
        
        for child in mirror.children {
            guard let label = child.label else { continue }
            
            // Find corresponding field metadata
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            guard let field = metadata.fields.first(where: { $0.name == fieldName }) else {
                continue
            }
            
            // Skip primary key field if requested (for inserts)
            if excludePrimaryKey && field.name == metadata.primaryKeyField {
                continue
            }
            
            // Extract value from property wrapper
            if let value = extractPropertyWrapperValue(child.value),
               let postgresData = try? convertToPostgresData(value) {
                data[field.databaseName] = postgresData
            }
        }
        
        return data
    }
    
    // MARK: - Private Helpers
    
    public static func extractValue(from dbValue: PostgresData, expectedType: Any.Type) -> Any? {
        switch expectedType {
        case is String.Type:
            return dbValue.string
        case is Int.Type:
            return dbValue.int
        case is Bool.Type:
            return dbValue.bool
        case is UUID.Type:
            return dbValue.uuid
        case is Date.Type:
            return dbValue.date
        case is Double.Type:
            return dbValue.double
        case is Float.Type:
            return dbValue.float
        case is Data.Type:
            if let bytes = dbValue.bytes {
                return Data(bytes)
            }
            return nil
        default:
            return nil
        }
    }
    
    private static func applyValues<T: Schema>(
        _ values: [String: Any],
        to instance: inout T,
        using metadata: SchemaMetadata
    ) throws {
        // This is the tricky part - we need to set values on property wrappers
        // For now, we'll use a protocol-based approach
        
        // Cast to a mutable protocol that schemas can adopt
        if var mutable = instance as? MutableSchema {
            mutable.apply(values: values)
            instance = mutable as! T
        } else {
            // Fallback to reflection-based approach
            try applyValuesViaReflection(values, to: &instance, using: metadata)
        }
    }
    
    private static func applyValuesViaReflection<T>(
        _ values: [String: Any],
        to instance: inout T,
        using metadata: SchemaMetadata
    ) throws {
        // This is where we need to implement the reflection-based value setting
        // For now, we'll use a temporary approach that requires schemas to implement
        // a protocol for value application
        
        // In a production implementation, we would either:
        // 1. Use code generation to create setters at compile time (like Ecto)
        // 2. Use Swift's KeyPath machinery with dynamic member lookup
        // 3. Require schemas to implement Codable and use that infrastructure
        
        throw SpectroError.notImplemented("Generic reflection-based value setting requires MutableSchema protocol")
    }
    
    private static func extractPropertyWrapperValue(_ wrapper: Any) -> Any? {
        let mirror = Mirror(reflecting: wrapper)
        
        for child in mirror.children {
            if child.label == "wrappedValue" {
                return child.value
            }
        }
        
        return wrapper
    }
    
    public static func convertToPostgresData(_ value: Any) throws -> PostgresData {
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

// MARK: - Mutable Schema Protocol

/// Protocol that schemas can adopt to enable efficient value setting
/// This is inspired by ActiveRecord's attribute assignment
public protocol MutableSchema {
    mutating func apply(values: [String: Any])
}