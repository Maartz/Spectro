public struct Relationship: Equatable {
    let name: String
    let type: RelationType
    let foreignSchema: any Schema.Type

    public static func == (lhs: Relationship, rhs: Relationship) -> Bool {
        lhs.name == rhs.name &&
        lhs.type == rhs.type &&
        String(describing: lhs.foreignSchema) == String(describing: rhs.foreignSchema)
    }
}