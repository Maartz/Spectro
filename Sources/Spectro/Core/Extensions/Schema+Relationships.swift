//
//  Schema+Relationships.swift
//  Spectro
//
//  Created by William MARTIN on 6/4/25.
//

import Foundation

// Enhanced relationship information for joins and introspection
public struct RelationshipInfo: Sendable {
    public let name: String
    public let type: RelationType
    public let foreignSchema: any Schema.Type
    public let localKey: String    // Key on local table
    public let foreignKey: String  // Key on foreign table
    
    public init(name: String, type: RelationType, foreignSchema: any Schema.Type, localKey: String? = nil, foreignKey: String? = nil, sourceSchema: (any Schema.Type)? = nil) {
        self.name = name
        self.type = type
        self.foreignSchema = foreignSchema
        
        // Default key inference based on relationship type
        switch type {
        case .belongsTo:
            self.localKey = localKey ?? "\(name)_id"
            self.foreignKey = foreignKey ?? "id"
        case .hasOne, .hasMany:
            self.localKey = localKey ?? "id"
            // For hasMany/hasOne, the foreign key is on the target table pointing back to us
            // We need to infer this from context. For now, use a simple pattern
            if let sourceSchema = sourceSchema {
                self.foreignKey = foreignKey ?? "\(sourceSchema.schemaName.singularize())_id"
            } else {
                // Fallback: assume the relationship name without 's' + _id
                self.foreignKey = foreignKey ?? "\(name.singularize())_id"
            }
        case .manyToMany:
            self.localKey = localKey ?? "id"
            self.foreignKey = foreignKey ?? "id"
        }
    }
}

// Extension to provide relationship introspection
extension Schema {
    /// Get all relationships defined in this schema
    public static var relationships: [RelationshipInfo] {
        return allFields.compactMap { field in
            guard case .relationship(let rel) = field.type else { return nil }
            return RelationshipInfo(
                name: field.name,
                type: rel.type,
                foreignSchema: rel.foreignSchema,
                sourceSchema: Self.self
            )
        }
    }
    
    /// Get a specific relationship by name
    public static func relationship(named name: String) -> RelationshipInfo? {
        return relationships.first { $0.name == name }
    }
    
    /// Get relationships of a specific type
    public static func relationships(ofType type: RelationType) -> [RelationshipInfo] {
        return relationships.filter { $0.type == type }
    }
}

// KeyPath-based relationship access for type safety
public struct RelationshipKeyPath<Source: Schema, Target: Schema> {
    public let relationshipInfo: RelationshipInfo
    public let targetSchema: Target.Type
    
    internal init(relationshipInfo: RelationshipInfo, targetSchema: Target.Type) {
        self.relationshipInfo = relationshipInfo
        self.targetSchema = targetSchema
    }
}

// Extension to create type-safe relationship keypaths
extension Schema {
    public static subscript<Target: Schema>(relationshipKeyPath name: String, _: Target.Type) -> RelationshipKeyPath<Self, Target> {
        guard let rel = relationship(named: name) else {
            fatalError("Relationship '\(name)' not found on \(Self.schemaName)")
        }
        guard rel.foreignSchema == Target.self else {
            fatalError("Relationship '\(name)' target schema mismatch")
        }
        return RelationshipKeyPath(relationshipInfo: rel, targetSchema: Target.self)
    }
}

// String extension for singularization (simple implementation)
extension String {
    func singularize() -> String {
        if self.hasSuffix("ies") {
            return String(self.dropLast(3)) + "y"
        } else if self.hasSuffix("ches") || self.hasSuffix("shes") || self.hasSuffix("ses") || self.hasSuffix("xes") || self.hasSuffix("zes") {
            return String(self.dropLast(2))
        } else if self.hasSuffix("s") && !self.hasSuffix("ss") {
            return String(self.dropLast(1))
        }
        return self
    }
}