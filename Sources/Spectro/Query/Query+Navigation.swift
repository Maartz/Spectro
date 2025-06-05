//
//  Query+Navigation.swift
//  Spectro
//
//  Created by William MARTIN on 6/4/25.
//

import Foundation

// Relationship navigation through method chaining
extension Query {
    /// Navigate to a related schema (method chaining style)
    /// This changes the root schema of the query to the related schema
    public func through(_ relationshipName: String) -> Query {
        guard let relationship = schema.relationship(named: relationshipName) else {
            fatalError("Relationship '\(relationshipName)' not found on \(schema.schemaName)")
        }
        
        // Create a new query for the target schema
        var newQuery = Query.from(relationship.foreignSchema)
        
        // Copy existing joins from the current query
        newQuery.joins = joins
        
        // Add implicit join to connect the current schema to the target schema
        // Check if we need an alias for the current schema
        let currentSchemaName = schema.schemaName
        let existingAliases = newQuery.joins.map { $0.alias ?? $0.targetSchema.schemaName }
        let existingTableCount = existingAliases.filter { $0.starts(with: currentSchemaName) }.count
        
        let sourceAlias: String? = if existingTableCount > 0 {
            "\(currentSchemaName)_\(existingTableCount + 1)"
        } else {
            nil // Use table name as-is for first occurrence
        }
        
        // Create a "reverse" relationship for the join (from target back to source)
        let reverseRelationship = RelationshipInfo(
            name: schema.schemaName.singularize(),
            type: relationship.type.reverse(),
            foreignSchema: schema,
            localKey: relationship.foreignKey,
            foreignKey: relationship.localKey
        )
        
        let joinInfo = JoinInfo(
            joinType: .inner,
            targetSchema: schema,
            relationship: reverseRelationship,
            alias: sourceAlias
        )
        newQuery.joins.append(joinInfo)
        
        // Copy existing conditions, but adjust the relationship context
        newQuery.relationshipConditions = relationshipConditions
        
        // Add current schema conditions under the appropriate alias/name
        let sourceTableRef = sourceAlias ?? currentSchemaName
        newQuery.relationshipConditions[sourceTableRef] = conditions
        
        // Copy other query properties
        newQuery.limit = limit
        newQuery.offset = offset
        
        return newQuery
    }
}

// Dynamic property-style navigation using @dynamicMemberLookup
@dynamicMemberLookup
public struct RelationshipNavigator {
    private let query: Query
    
    init(query: Query) {
        self.query = query
    }
    
    public subscript(dynamicMember relationshipName: String) -> Query {
        return query.through(relationshipName)
    }
}

// Extension to provide property-style access to relationships
extension Query {
    /// Access relationships using property syntax
    /// Usage: query.relationships.posts.where { ... }
    public var relationships: RelationshipNavigator {
        RelationshipNavigator(query: self)
    }
}

// Convenience extensions for common relationship patterns
extension Schema {
    /// Create a query that navigates through a relationship
    public static func through(_ relationshipName: String) -> Query {
        return query().through(relationshipName)
    }
}