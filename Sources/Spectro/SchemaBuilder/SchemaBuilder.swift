//
//  SchemaBuilder.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import Foundation

@resultBuilder
public struct SchemaBuilder {
    public static func buildBlock(_ fields: SField...) -> [SField] {
        fields
    }

    public static func Field(_ name: String, _ type: FieldType, isRedacted: Bool = false) -> SField {
        SField(name: name, type: type, isRedacted: isRedacted)
    }
}
