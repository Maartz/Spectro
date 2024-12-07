//
//  SchemaBuilder.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import Foundation

@resultBuilder
public struct SchemaBuilder {
    public static func buildBlock(_ components: SField...) -> [SField] {
        components
    }

    public static func buildExpression(_ field: SField) -> SField {
        field
    }
}

public enum Field {
    public static func description(
        _ name: String, _ type: FieldType, isRedacted: Bool = false
    ) -> SField {
        SField(name: name, type: type, isRedacted: isRedacted)
    }

    public static func hasOne(_ name: String, _ schema: any Schema.Type) -> SField {
        SField(name: name, type: .relationship(.init(name: name, type: .hasOne, foreignSchema: schema)))
    }

    public static func hasMany(_ name: String, _ schema: any Schema.Type) -> SField {
        SField(name: name, type: .relationship(.init(name: name, type: .hasMany, foreignSchema: schema)))
    }

    public static func belongsTo(_ name: String, _ schema: any Schema.Type) -> SField {
        SField(name: name, type: .relationship(.init(name: name, type: .belongsTo, foreignSchema: schema)))
    }
    
    public static func manyToMany(_ name: String, _ schema: any Schema.Type, through: String) -> SField {
        SField(name: name, type: .relationship(.init(
            name: name,
            type: .manyToMany(through: through),
            foreignSchema: schema
        )))
    }
}
