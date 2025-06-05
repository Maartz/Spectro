public enum RelationType: Equatable, Sendable {
    case hasOne
    case hasMany
    case belongsTo
    case manyToMany(through: String)
    
    /// Get the reverse relationship type for navigation
    func reverse() -> RelationType {
        switch self {
        case .hasOne, .hasMany:
            return .belongsTo
        case .belongsTo:
            return .hasMany // Could be hasOne, but hasMany is safer
        case .manyToMany(let through):
            return .manyToMany(through: through)
        }
    }
}