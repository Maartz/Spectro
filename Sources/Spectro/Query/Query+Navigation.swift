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
        
        // Add implicit join to connect the tables
        let joinInfo = JoinInfo(
            joinType: .inner,
            targetSchema: relationship.foreignSchema,
            relationship: relationship
        )
        newQuery.joins.append(joinInfo)
        
        // Copy existing conditions as they apply to the original schema
        // We need to preserve the relationship context
        newQuery.relationshipConditions[schema.schemaName] = conditions
        
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