public struct Relationship {
    let type: RelationType
    let targetSchema: Schema.Type
    let foreignKey: String

    public init(type: RelationType, target: Schema.Type, foreignKey: String? = nil) {
        self.type = type
        self.targetSchema = target
        self.foreignKey = foreignKey ?? "\(target.schemaName)_id"
    }

    var joinType: JoinType {
        switch type {
            case .hasOne, .hasMany: return .left
            case .belongsTo: return .inner
        }
    }

    func defaultJoinClause(sourceAlias: String, targetAlias: String) -> String {
        switch type {
            case .hasOne, .hasMany: return "\(targetAlias).\(foreignKey) = \(sourceAlias).id"
            case .belongsTo: return "\(sourceAlias).\(foreignKey) = \(targetAlias).id"
        }
    }

    func toJoinClause(fromTable: String) -> JoinClause {
        switch type {
        case .hasMany:
            return JoinClause(
                type: .left, table: targetSchema.schemaName,
                condition: "\(targetSchema.schemaName).\(foreignKey) = \(fromTable).id")
        case .hasOne:
            return JoinClause(
                type: .left, table: targetSchema.schemaName,
                condition: "\(targetSchema.schemaName).\(foreignKey) = \(fromTable).id")
        case .belongsTo:
            return JoinClause(
                type: .inner, table: targetSchema.schemaName,
                condition: "\(fromTable).\(foreignKey) = \(targetSchema.schemaName).id")
        }
    }
}
