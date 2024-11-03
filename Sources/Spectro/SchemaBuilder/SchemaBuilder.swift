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
    public static func create(
        _ name: String, _ type: FieldType, isRedacted: Bool = false
    ) -> SField {
        SField(name: name, type: type, isRedacted: isRedacted)
    }
}
