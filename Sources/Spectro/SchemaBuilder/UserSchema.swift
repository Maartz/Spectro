//
//  UserSchema.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

struct UserSchema: Schema {
    static let schemaName = "users"

    @SchemaBuilder static var fields: [SField] {
        SchemaBuilder.Field("name", .string)
        SchemaBuilder.Field("age", .integer(default: 0))
        SchemaBuilder.Field("password", .string, isRedacted: true)
    }
}
