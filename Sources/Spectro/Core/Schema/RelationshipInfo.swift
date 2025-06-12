import Foundation

/// Relationship information for schema associations
public struct RelationshipInfo: Sendable {
    public let name: String
    public let relatedTypeName: String
    public let kind: RelationshipKind
    public let foreignKey: String?
    
    public init(name: String, relatedTypeName: String, kind: RelationshipKind, foreignKey: String? = nil) {
        self.name = name
        self.relatedTypeName = relatedTypeName
        self.kind = kind
        self.foreignKey = foreignKey
    }
}

/// Types of relationships
public enum RelationshipKind: Sendable {
    case hasMany
    case hasOne  
    case belongsTo
}