public enum RelationType: Equatable, Sendable {
    case hasOne
    case hasMany
    case belongsTo
    case manyToMany(through: String)
}