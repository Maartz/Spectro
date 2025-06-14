import Foundation

/// Registry for mapping KeyPaths to relationship field names
/// This allows us to extract relationship names from KeyPaths during preloading
public actor RelationshipRegistry {
    public static let shared = RelationshipRegistry()
    
    private var registry: [String: RelationshipMapping] = [:]
    
    private init() {}
    
    public struct RelationshipMapping {
        let fieldName: String
        let relatedType: String
        let kind: RelationshipKind
        let foreignKey: String?
    }
    
    /// Register a relationship for a specific schema type
    public func register<T: Schema, Related>(
        for schemaType: T.Type,
        keyPath: KeyPath<T, SpectroLazyRelation<Related>>,
        fieldName: String,
        relatedType: Related.Type,
        kind: RelationshipKind,
        foreignKey: String? = nil
    ) {
        let key = makeKey(schemaType: schemaType, keyPath: keyPath)
        registry[key] = RelationshipMapping(
            fieldName: fieldName,
            relatedType: String(describing: relatedType),
            kind: kind,
            foreignKey: foreignKey
        )
    }
    
    /// Get relationship mapping for a KeyPath
    public func getMapping<T: Schema, Related>(
        for schemaType: T.Type,
        keyPath: KeyPath<T, SpectroLazyRelation<Related>>
    ) -> RelationshipMapping? {
        let key = makeKey(schemaType: schemaType, keyPath: keyPath)
        return registry[key]
    }
    
    /// Extract field name from a KeyPath
    public func extractFieldName<T: Schema, Related>(
        for schemaType: T.Type,
        keyPath: KeyPath<T, SpectroLazyRelation<Related>>
    ) -> String? {
        return getMapping(for: schemaType, keyPath: keyPath)?.fieldName
    }
    
    private func makeKey<T: Schema, Related>(
        schemaType: T.Type,
        keyPath: KeyPath<T, SpectroLazyRelation<Related>>
    ) -> String {
        // Create a unique key for this schema + keypath combination
        return "\(T.self).\(keyPath)"
    }
}

/// Extension to help with relationship registration during schema initialization
public extension Schema {
    /// Register relationships for this schema type
    static func registerRelationships() async {
        // This would be called during schema initialization
        // Subclasses can override to register their relationships
    }
}