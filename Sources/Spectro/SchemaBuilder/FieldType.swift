//
//  FieldType.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//
import PostgresKit

public enum FieldType: Equatable {
    case string
    case integer(defaultValue: Int? = nil)
    case float(defaultValue: Double? = nil)
    case boolean(defaultValue: Bool? = nil)
    case jsonb
    case uuid
    case timestamp
    case relationship(Relationship)

    var postgresType: PostgresDataType {
        switch self {
        case .string: return .text
        case .integer: return .int8
        case .float: return .float8
        case .boolean: return .bool
        case .jsonb: return .jsonb
        case .uuid: return .uuid
        case .timestamp: return .timestamp
        case .relationship: return .uuid
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
        case .relationship: return "UUID"
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
}
