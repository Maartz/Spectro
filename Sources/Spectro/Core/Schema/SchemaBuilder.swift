import Foundation
import PostgresNIO

/// Protocol for building schema instances from database rows
/// Inspired by Ecto's schema DSL and ActiveRecord's instantiation
public protocol SchemaBuilder: Schema {
    /// Build an instance from a dictionary of values
    static func build(from values: [String: Any]) -> Self
}

/// Default implementation using reflection
extension SchemaBuilder {
    public static func build(from values: [String: Any]) -> Self {
        var instance = Self()
        
        // Use mirror to discover properties
        let mirror = Mirror(reflecting: instance)
        
        // Create a new instance by setting each property
        // This is where we'd ideally use a macro or code generation
        // For now, we'll provide a default that schemas can override
        
        return instance
    }
}

/// Extension to make Schema decoding work with our row mapper
extension Schema {
    /// Create an instance from a database row (synchronous version)
    public static func fromSync(row: PostgresRow) throws -> Self {
        // For now, we'll use a simplified approach that works with basic types
        // This assumes the schema has default property wrapper values that can be set
        var instance = Self()
        
        // Use mirror to update properties
        let mirror = Mirror(reflecting: instance)
        let randomAccess = row.makeRandomAccess()
        
        // For now, we'll need to implement this in individual schema types
        // or use a more sophisticated approach. This is a placeholder.
        
        return instance
    }
    
    /// Create an instance from a database row
    public static func from(row: PostgresRow) async throws -> Self {
        // Get schema metadata
        let metadata = await SchemaRegistry.shared.register(self)
        let randomAccess = row.makeRandomAccess()
        
        // Build value dictionary
        var values: [String: Any] = [:]
        
        for field in metadata.fields {
            let dbValue = randomAccess[data: field.databaseName]
            // Extract value based on field type
            switch field.type {
            case is String.Type:
                values[field.name] = dbValue.string
            case is Int.Type:
                values[field.name] = dbValue.int
            case is Bool.Type:
                values[field.name] = dbValue.bool
            case is UUID.Type:
                values[field.name] = dbValue.uuid
            case is Date.Type:
                values[field.name] = dbValue.date
            case is Double.Type:
                values[field.name] = dbValue.double
            case is Float.Type:
                values[field.name] = dbValue.float
            case is Data.Type:
                if let bytes = dbValue.bytes {
                    values[field.name] = Data(bytes)
                }
            default:
                break
            }
        }
        
        // Use builder if available, otherwise use init + reflection
        if let builderType = self as? any SchemaBuilder.Type {
            return builderType.build(from: values) as! Self
        } else {
            // Fallback: create instance and attempt to populate
            return try createAndPopulate(values: values)
        }
    }
    
    /// Fallback creation method using init
    private static func createAndPopulate(values: [String: Any]) throws -> Self {
        // For structs without a builder, we need a different approach
        // This is where Swift's limitations show - we can't mutate struct properties
        // after initialization without unsafe code
        
        // The solution is to require either:
        // 1. A memberwise initializer
        // 2. Conformance to SchemaBuilder
        // 3. Use of classes instead of structs
        
        var instance = Self()
        
        // Try to use property wrapper setters if available
        if var mutable = instance as? MutableSchema {
            mutable.apply(values: values)
            return mutable as! Self
        }
        
        // Otherwise, return the default instance
        // User will need to implement SchemaBuilder for full functionality
        return instance
    }
}