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
    
    subscript(dynamicMember field: String) -> String {
        guard schema[dynamicMember: field] != nil else {
            fatalError("Field '\(field)' does not exist in schema \(schema.schemaName)")
        }
        return field
    }
}
