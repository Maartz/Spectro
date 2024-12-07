//
//  Schema+Extensions.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import Foundation
import PostgresKit

extension Schema {
    static func validateValue(_ value: Any?, for field: SField) -> ConditionValue {
        guard let value = value else {
            return .null
        }
        
        switch field.type {
        case .string:
            return .string(String(describing: value))
            
        case .integer(let defaultValue):
            if let int = value as? Int {
                return .int(int)
            }
            if let defaultInt = defaultValue {
                return .int(defaultInt)
            }
            return .null
            
        case .float(let defaultValue):
            if let double = value as? Double {
                return .double(double)
            }
            if let defaultDouble = defaultValue {
                return .double(defaultDouble)
            }
            return .null
            
        case .boolean(let defaultValue):
            if let bool = value as? Bool {
                return .bool(bool)
            }
            if let defaultBool = defaultValue {
                return .bool(defaultBool)
            }
            return .null
            
        case .jsonb:
            if let string = value as? String {
                return .jsonb(string)
            }
            return .null
            
        case .uuid:
            if let uuid = value as? UUID {
                return .uuid(uuid)
            }
            return .null
            
        case .timestamp:
            if let date = value as? Date {
                return .date(date)
            }
            return .null
        
        case .relationship:
            if let uuid = value as? UUID { return .uuid(uuid) }
            if let string = value as? String, let uuid = UUID(uuidString: string) {
                return .uuid(uuid)
            }
            return .null
        }
    }
    
    static func createTable() -> String {
        var fieldDefinitions = fields.map { field in
            var def = "\(field.name) \(field.type.sqlDefinition)"
            if let defaultValue = field.type.defaultValue {
                switch defaultValue {
                case let int as Int:
                    def += " DEFAULT \(int)"
                case let double as Double:
                    def += " DEFAULT \(double)"
                case let bool as Bool:
                    def += " DEFAULT \(bool)"
                default:
                    break
                }
            }

            if case .relationship(let relationship) = field.type {
                switch relationship.type {
                    case .belongsTo:
                        def += " REFERENCES \(relationship.foreignSchema.schemaName)(id)"
                    case .hasOne, .hasMany:
                        break
                }
            }

            return def
        }
        fieldDefinitions.insert("id UUID PRIMARY KEY DEFAULT gen_random_uuid()", at: 0)

        return """
            CREATE TABLE IF NOT EXISTS \(schemaName) (
                \(fieldDefinitions.joined(separator: ",\n    "))
            );
        """
    }
}

extension Repository {
    func createTable<S: Schema>(_ schema: S.Type) async throws {
        try await executeRaw(schema.createTable(), [])
    }
    
    func insert<S: Schema>(_ schema: S.Type, values: [String: Any]) async throws {
        let validatedValues = Dictionary(uniqueKeysWithValues:
            schema.fields.compactMap { field in
                let value = values[field.name]
                return (field.name, schema.validateValue(value, for: field))
            }
        )
        
        try await insert(into: schema.schemaName, values: validatedValues)
    }
}
