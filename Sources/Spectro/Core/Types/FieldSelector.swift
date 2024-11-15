//
//  FieldSelector.swift
//  Spectro
//
//  Created by William MARTIN on 11/15/24.
//

@dynamicMemberLookup
public struct FieldSelector {
    private let schema: Schema.Type
    
    init(schema: Schema.Type) {
        self.schema = schema
    }
    
    subscript(dynamicMember field: String) -> FieldPredicate {
        guard let schemaField = schema[dynamicMember: field] else {
            fatalError("Field '\(field)' does not exist in schema \(schema.schemaName)")
        }
        return FieldPredicate(name: field, type: schemaField.type)
    }
}
