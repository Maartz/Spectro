import Foundation
import PostgresNIO

/// Handles loading relationships for schema instances
public struct RelationshipLoader {
    
    /// Load a has-many relationship for a given instance
    public static func loadHasMany<Parent: Schema, Child: Schema>(
        for parent: Parent,
        relationship: String,
        childType: Child.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> [Child] {
        // Get the primary key value from the parent
        let parentMetadata = await SchemaRegistry.shared.register(Parent.self)
        guard let primaryKeyField = parentMetadata.primaryKeyField else {
            throw SpectroError.invalidSchema(reason: "Parent schema \(Parent.self) has no primary key")
        }
        
        // Extract the primary key value using reflection
        let parentId = try extractPrimaryKeyValue(from: parent, fieldName: primaryKeyField)
        
        // Query child records that reference this parent
        let condition = QueryCondition(sql: "\(foreignKey.snakeCase()) = $1", parameters: [PostgresData(uuid: parentId)])
        
        return try await repo.query(childType)
            .where { _ in condition }
            .all()
    }
    
    /// Load a has-one relationship for a given instance
    public static func loadHasOne<Parent: Schema, Child: Schema>(
        for parent: Parent,
        relationship: String,
        childType: Child.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> Child? {
        let children = try await loadHasMany(
            for: parent,
            relationship: relationship,
            childType: childType,
            foreignKey: foreignKey,
            using: repo
        )
        return children.first
    }
    
    /// Load a belongs-to relationship for a given instance
    public static func loadBelongsTo<Child: Schema, Parent: Schema>(
        for child: Child,
        relationship: String,
        parentType: Parent.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> Parent? {
        // Extract the foreign key value from the child
        let foreignKeyValue = try extractForeignKeyValue(from: child, fieldName: foreignKey)
        
        // Get the parent record by ID
        return try await repo.get(parentType, id: foreignKeyValue)
    }
    
    // MARK: - Helper Methods
    
    private static func extractPrimaryKeyValue<T: Schema>(from instance: T, fieldName: String) throws -> UUID {
        let mirror = Mirror(reflecting: instance)
        
        for child in mirror.children {
            guard let label = child.label else { continue }
            
            // Remove underscore prefix if present
            let normalizedLabel = label.hasPrefix("_") ? String(label.dropFirst()) : label
            
            if normalizedLabel == fieldName {
                // Extract UUID from property wrapper
                if let id = child.value as? ID {
                    return id.wrappedValue
                } else if let uuid = child.value as? UUID {
                    return uuid
                }
                break
            }
        }
        
        throw SpectroError.missingRequiredField("Primary key field '\(fieldName)' not found or not a UUID")
    }
    
    private static func extractForeignKeyValue<T: Schema>(from instance: T, fieldName: String) throws -> UUID {
        let mirror = Mirror(reflecting: instance)
        
        for child in mirror.children {
            guard let label = child.label else { continue }
            
            // Remove underscore prefix if present  
            let normalizedLabel = label.hasPrefix("_") ? String(label.dropFirst()) : label
            
            if normalizedLabel == fieldName {
                // Extract UUID from property wrapper
                if let foreignKey = child.value as? ForeignKey {
                    return foreignKey.wrappedValue
                } else if let uuid = child.value as? UUID {
                    return uuid
                }
                break
            }
        }
        
        throw SpectroError.missingRequiredField("Foreign key field '\(fieldName)' not found or not a UUID")
    }
}

// MARK: - Schema Extensions for Relationship Loading

extension Schema {
    
    /// Load a has-many relationship
    public func loadHasMany<T: Schema>(
        _ relationshipType: T.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> [T] {
        return try await RelationshipLoader.loadHasMany(
            for: self,
            relationship: String(describing: relationshipType),
            childType: relationshipType,
            foreignKey: foreignKey,
            using: repo
        )
    }
    
    /// Load a has-one relationship
    public func loadHasOne<T: Schema>(
        _ relationshipType: T.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> T? {
        return try await RelationshipLoader.loadHasOne(
            for: self,
            relationship: String(describing: relationshipType),
            childType: relationshipType,
            foreignKey: foreignKey,
            using: repo
        )
    }
    
    /// Load a belongs-to relationship
    public func loadBelongsTo<T: Schema>(
        _ relationshipType: T.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> T? {
        return try await RelationshipLoader.loadBelongsTo(
            for: self,
            relationship: String(describing: relationshipType),
            parentType: relationshipType,
            foreignKey: foreignKey,
            using: repo
        )
    }
}