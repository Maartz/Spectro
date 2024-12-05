//
//  FieldType.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//
import PostgresKit
import SpectroCore

public enum FieldType {
    case string
    case integer(defaultValue: Int? = nil)
    case float(defaultValue: Double? = nil)
    case boolean(defaultValue: Bool? = nil)
    case jsonb
    case uuid
    case timestamp
    case foreignKey(to: Schema.Type)
    case relationship(type: RelationType, target: Schema.Type)

    var postgresType: PostgresDataType {
        switch self {
        case .string: return .text
        case .integer: return .int8
        case .float: return .float8
        case .boolean: return .bool
        case .jsonb: return .jsonb
        case .uuid: return .uuid
        case .timestamp: return .timestamp
        case .foreignKey: return .uuid
        case .relationship: return .jsonb
        }
    }

    var sqlDefinition: String {
        switch self {
        case .string: return "TEXT"
        case .integer: return "INTEGER"
        case .float: return "DOUBLE PRECISION"
        case .boolean: return "BOOLEAN"
        case .jsonb: return "JSONB"
        case .uuid: return "UUID"
        case .timestamp: return "TIMESTAMPTZ"
        case .foreignKey: return "UUID"
        case .relationship: return "JSONB"
        }
    }

    var defaultValue: Any? {
        switch self {
        case .integer(let defaultValue): return defaultValue
        case .float(let defaultValue): return defaultValue
        case .boolean(let defaultValue): return defaultValue
        default: return nil
        }
    }

    var isRelationship: Bool {
        if case .relationship = self {
            return true
        }
        return false
    }

    var isForeignKey: Bool {
        if case .foreignKey = self {
            return true
        }
        return false
    }

    var targetSchema: Schema.Type? {
        switch self {
        case .foreignKey(let target): return target
        case .relationship(_, let target): return target
        default: return nil
        }
    }
}

extension Field {
    public static func hasMany<T: Schema>(_ name: String, _ target: T.Type) -> SField {
        let relationshipName = name.isEmpty ? 
            Inflector.pluralize(target.schemaName) : name
        return SField(
            name: relationshipName, 
            type: .relationship(type: .hasMany, target: target)
        )
    }
    
    public static func belongsTo<T: Schema>(_ target: T.Type, fieldName: String? = nil) -> SField {
        let name = fieldName ?? "\(Inflector.singularize(target.schemaName))_id"
        return SField(name: name, type: .foreignKey(to: target))
    }

    public static func hasOne<T: Schema>(_ name: String, _ target: T.Type) -> SField {
            let relationshipName = name.isEmpty ? Inflector.singularize(target.schemaName) : name
            return SField(name: relationshipName, type: .relationship(type: .hasOne, target: target))
        }
}

extension FieldType: Equatable {
    public static func == (lhs: FieldType, rhs: FieldType) -> Bool {
        switch (lhs, rhs) {
        case (.string, .string):
            return true
        case (.integer(let lhsDefault), .integer(let rhsDefault)):
            return lhsDefault == rhsDefault
        case (.float(let lhsDefault), .float(let rhsDefault)):
            return lhsDefault == rhsDefault
        case (.boolean(let lhsDefault), .boolean(let rhsDefault)):
            return lhsDefault == rhsDefault
        case (.jsonb, .jsonb):
            return true
        case (.uuid, .uuid):
            return true
        case (.timestamp, .timestamp):
            return true
        case (.foreignKey(let lhsTarget), .foreignKey(let rhsTarget)):
            return String(describing: lhsTarget) == String(describing: rhsTarget)
        case (
            .relationship(let lhsType, let lhsTarget), .relationship(let rhsType, let rhsTarget)
        ):
            return lhsType == rhsType
                && String(describing: lhsTarget) == String(describing: rhsTarget)
        default:
            return false
        }
    }
}
