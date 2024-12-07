public enum RelationType : Equatable {
    case hasOne
    case hasMany
    case belongsTo
    case manyToMany(through: String)
}