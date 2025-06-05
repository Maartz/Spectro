//
//  Query+Joins.swift
//  Spectro
//
//  Created by William MARTIN on 6/4/25.
//

import Foundation

// Join information for SQL generation
public struct JoinInfo: Sendable {
    public let joinType: JoinType
    public let targetSchema: any Schema.Type
    public let relationship: RelationshipInfo
    public let alias: String?
    
    public init(joinType: JoinType = .inner, targetSchema: any Schema.Type, relationship: RelationshipInfo, alias: String? = nil) {
        self.joinType = joinType
        self.targetSchema = targetSchema
        self.relationship = relationship
        self.alias = alias
    }
}

public enum JoinType: Sendable {
    case inner
    case left
    case right
    case full
    
    var sql: String {
        switch self {
        case .inner: return "INNER JOIN"
        case .left: return "LEFT JOIN"
        case .right: return "RIGHT JOIN"
        case .full: return "FULL OUTER JOIN"
        }
    }
}

// Join methods for Query
extension Query {
    /// Join with a related schema using relationship name
    public func join(_ relationshipName: String, type: JoinType = .inner) -> Query {
        guard let relationship = schema.relationship(named: relationshipName) else {
            fatalError("Relationship '\(relationshipName)' not found on \(schema.schemaName)")
        }
        
        var copy = self
        let joinInfo = JoinInfo(
            joinType: type,
            targetSchema: relationship.foreignSchema,
            relationship: relationship
        )
        copy.joins.append(joinInfo)
        return copy
    }
    
    /// Add WHERE conditions for a joined relationship (ActiveRecord style)
    public func `where`(_ relationshipName: String, _ builder: (FieldSelector) -> Condition) -> Query {
        guard let relationship = schema.relationship(named: relationshipName) else {
            fatalError("Relationship '\(relationshipName)' not found on \(schema.schemaName)")
        }
        
        let selector = FieldSelector(schema: relationship.foreignSchema)
        let condition = builder(selector)
        
        var copy = self
        
        // Store the condition keyed by relationship name
        if case let simple as QueryCondition = condition {
            if copy.relationshipConditions[relationshipName] == nil {
                copy.relationshipConditions[relationshipName] = [:]
            }
            copy.relationshipConditions[relationshipName]![simple.field] = (simple.op, simple.value)
        }
        
        return copy
    }
    
    /// Add preloading for a relationship
    public func preload(_ relationshipName: String) -> Query {
        var copy = self
        copy.preloadRelationships.append(relationshipName)
        return copy
    }
    
    /// Add multiple preloads at once
    public func preload(_ relationshipNames: String...) -> Query {
        var copy = self
        copy.preloadRelationships.append(contentsOf: relationshipNames)
        return copy
    }
}