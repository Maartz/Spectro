import Foundation

/// Base protocol for database schemas with property wrapper support.
///
/// `Schema` defines the foundation for type-safe database models in Spectro.
/// It uses property wrappers to declaratively define fields and their database mappings.
///
/// ## Basic Schema Definition
///
/// ```swift
/// struct User: Schema {
///     static let tableName = "users"
///     
///     @ID var id: UUID
///     @Column var name: String = ""
///     @Column var email: String = ""
///     @Column var age: Int = 0
///     @Timestamp var createdAt: Date = Date()
///     @Timestamp var updatedAt: Date = Date()
///     
///     init() {}
/// }
/// ```
///
/// ## Property Wrappers
///
/// Spectro provides several property wrappers for different field types:
///
/// - ``ID``: Auto-generated UUID primary keys
/// - ``Column``: Regular database columns
/// - ``Timestamp``: Automatic timestamp fields
/// - ``ForeignKey``: Foreign key references
/// - ``HasMany``: One-to-many relationships
/// - ``HasOne``: One-to-one relationships
/// - ``BelongsTo``: Many-to-one relationships
///
/// ## Database Mapping
///
/// Property names are automatically converted to snake_case for database columns:
/// - `firstName` → `first_name`
/// - `isActive` → `is_active`
/// - `createdAt` → `created_at`
///
/// ## Relationships
///
/// Define relationships between schemas using relationship property wrappers:
///
/// ```swift
/// struct User: Schema {
///     static let tableName = "users"
///     @ID var id: UUID
///     @HasMany var posts: [Post]      // User has many posts
///     @HasOne var profile: Profile?   // User has one profile
///     init() {}
/// }
///
/// struct Post: Schema {
///     static let tableName = "posts"
///     @ID var id: UUID
///     @ForeignKey var userId: UUID = UUID()
///     @BelongsTo var user: User?      // Post belongs to user
///     init() {}
/// }
/// ```
///
/// ## Requirements
///
/// Schemas must:
/// 1. Provide a `tableName` static property
/// 2. Have a parameterless `init()` method
/// 3. Conform to `Sendable` for concurrency safety
///
/// ## Best Practices
///
/// - Use descriptive table names (plural: "users", "posts")
/// - Always include an `@ID` field for the primary key
/// - Add `@Timestamp` fields for audit trails
/// - Use `@ForeignKey` for explicit foreign key relationships
/// - Implement `SchemaBuilder` for custom field mapping
public protocol Schema: Sendable {
    /// The database table name for this schema.
    ///
    /// Should be plural and in snake_case (e.g., "users", "blog_posts").
    static var tableName: String { get }
    
    /// Required parameterless initializer for creating instances.
    ///
    /// This initializer is used by Spectro to create instances when mapping
    /// database rows to schema objects. Property wrappers should provide
    /// sensible default values.
    init()
}

// MARK: - Field Name Provider for KeyPath extraction

/// Protocol for schemas that provide static field name mappings.
///
/// `FieldNameProvider` enables efficient KeyPath-to-field-name resolution
/// for schemas that need custom field naming strategies or performance optimization.
///
/// ## Usage
///
/// ```swift
/// struct User: Schema, FieldNameProvider {
///     static let tableName = "users"
///     static let fieldNames: [String: String] = [
///         "\User.firstName": "first_name",
///         "\User.lastName": "last_name",
///         "\User.emailAddress": "email"
///     ]
///     
///     @Column var firstName: String = ""
///     @Column var lastName: String = ""
///     @Column var emailAddress: String = ""
/// }
/// ```
///
/// ## Performance Benefits
///
/// Pre-computed field name mappings avoid runtime reflection overhead
/// when building queries with KeyPath-based field access.
public protocol FieldNameProvider {
    /// Maps KeyPath string representations to database field names.
    ///
    /// The dictionary keys should be the string representation of KeyPaths,
    /// and values should be the corresponding database column names.
    static var fieldNames: [String: String] { get }
}

// MARK: - KeyPath Field Extraction

/// Utility for extracting field names from KeyPaths using runtime reflection.
///
/// `KeyPathFieldExtractor` provides fallback mechanisms for schemas that don't
/// implement `FieldNameProvider`, using Swift's reflection capabilities to
/// determine field names from KeyPath expressions.
public enum KeyPathFieldExtractor {
    /// Extract field name from a KeyPath using runtime reflection.
    ///
    /// This method uses Swift's `Mirror` API to inspect schema instances and
    /// match KeyPaths to property names. It handles property wrapper prefixes
    /// and provides fallback parsing of KeyPath string representations.
    ///
    /// - Parameters:
    ///   - keyPath: KeyPath to extract field name from
    ///   - schema: Schema type for context
    /// - Returns: Field name string
    ///
    /// ## Algorithm
    ///
    /// 1. Creates a temporary schema instance
    /// 2. Uses Mirror to inspect properties
    /// 3. Removes property wrapper underscore prefixes
    /// 4. Matches KeyPath descriptions against property names
    /// 5. Falls back to parsing KeyPath string representation
    ///
    /// ## Performance Note
    ///
    /// This method uses reflection and should be cached where possible.
    /// Consider implementing `FieldNameProvider` for frequently accessed schemas.
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
            
            // Match KeyPath description against property names
            let keyPathString = String(describing: keyPath)
            
            if keyPathString.contains(fieldName) || keyPathString.contains(label) {
                return fieldName
            }
        }
        
        // Fallback: extract from KeyPath description
        // KeyPath descriptions often look like: \User.name
        let keyPathString = String(describing: keyPath)
        if let lastComponent = keyPathString.split(separator: ".").last {
            return String(lastComponent)
        }
        
        return "unknown"
    }
}