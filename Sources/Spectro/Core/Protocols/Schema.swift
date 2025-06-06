import Foundation

/// Schema protocol for beautiful, type-safe database models
/// 
/// Usage:
/// ```swift
/// struct User: Schema {
///     static let tableName = "users"
///     
///     @ID var id: UUID
///     @Column var name: String
///     @Column var email: String
///     @Column var age: Int
///     @Timestamp var createdAt: Date
///     @Timestamp var updatedAt: Date
/// }
/// ```
public protocol Schema: Sendable {
    /// The database table name
    static var tableName: String { get }
    
    /// Required initializer for creating instances
    init()
}

// MARK: - Field Name Provider for KeyPath extraction

/// Protocol for schemas that provide static field name mappings
/// This enables efficient KeyPath to field name resolution
public protocol FieldNameProvider {
    /// Maps KeyPath string representations to field names
    static var fieldNames: [String: String] { get }
}

// MARK: - KeyPath Field Extraction

/// Helper to extract field names from KeyPaths at runtime
public enum KeyPathFieldExtractor {
    /// Extract field name from a KeyPath using runtime reflection
    public static func extractFieldName<T: Schema, V>(from keyPath: KeyPath<T, V>, schema: T.Type) -> String {
        // Create a temporary instance to use with reflection
        let instance = T()
        
        // Use Mirror to inspect the instance
        let mirror = Mirror(reflecting: instance)
        
        // Try to find the property that matches our keyPath
        for child in mirror.children {
            guard let label = child.label else { continue }
            
            // Remove property wrapper underscore prefix if present
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            
            // This is a simplified check - in production we'd need more sophisticated matching
            // For now, we'll use the debug description of the keyPath
            let keyPathString = String(describing: keyPath)
            
            if keyPathString.contains(fieldName) || keyPathString.contains(label) {
                return fieldName
            }
        }
        
        // Fallback: extract from keyPath description
        // KeyPath descriptions often look like: \User.name
        let keyPathString = String(describing: keyPath)
        if let lastComponent = keyPathString.split(separator: ".").last {
            return String(lastComponent)
        }
        
        return "unknown"
    }
}