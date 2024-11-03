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
        Field.create("name", .string)
        Field.create("age", .integer(defaultValue: 0))
        Field.create("password", .string, isRedacted: true)
    }
}
