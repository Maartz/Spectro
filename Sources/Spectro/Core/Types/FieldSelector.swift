//
//  FieldSelector.swift
//  Spectro
//
//  Created by William MARTIN on 11/15/24.
//

import SpectroCore

extension Schema {
    static func normalizeFieldName(for field: SField) -> String {
        if case .foreignKey(let target) = field.type {
            let singularName = Inflector.singularize(target.schemaName)
            let name = "\(singularName)_id"
            debugPrint("NormalnormalizeFieldName \(name)")
            return name
        }
        return field.name
    }

    static var availalbeFields: Set<String> {
        Set(allFields.map { normalizeFieldName(for: $0) })
    }

    static var queryableFields: [SField] {
            allFields.flatMap { field -> [SField] in 
                switch field.type {
                    case .foreignKey(let target):
                        let foreignKeyField = SField(name: "\(Inflector.singularize(target.schemaName))_id", type: .uuid)
                        return [foreignKeyField]

                    case .relationship(type: .hasMany, target: _):
                        return [field]
                    default: return [field]
                    }
            }
        }
}

@dynamicMemberLookup
public struct FieldSelector {
    private let schema: Schema.Type
    
    init(schema: Schema.Type) {
        self.schema = schema
    }
    
    subscript(dynamicMember field: String) -> FieldPredicate {
        if let schemaField = schema.queryableFields.first(where: {$0.name == field}) {
            if case .relationship = schemaField.type {
                return FieldPredicate(name: field, type: .jsonb)
                }
            return FieldPredicate(name: field, type: schemaField.type)
        }

        fatalError("""
            Field '\(field)' does not exist in schema \(schema.schemaName).
            Available fields: \(schema.availalbeFields.sorted().joined(separator: ", "))
        """)
        
    }
}
