public enum RelationType: Sendable {
    case hasMany
    case hasOne
    case belongsTo
}

public struct RelationshipInfo: Sendable {
    public let name: String
    public let relatedTypeName: String
    public let kind: RelationType
    public let foreignKey: String?

    public init(name: String, relatedTypeName: String, kind: RelationType, foreignKey: String?) {
        self.name = name
        self.relatedTypeName = relatedTypeName
        self.kind = kind
        self.foreignKey = foreignKey
    }
}
