//
//  UserSchema.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

struct UserSchema: Schema {
    static let schemaName = "users"

    @SchemaBuilder
    static var fields: [SField] {
        Field.description("name", .string)
        Field.description("age", .integer(defaultValue: 0))
        Field.description("password", .string, isRedacted: true)
    }
}
