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
        Field.description("email", .string)
        Field.description("score", .integer(defaultValue: 0))
        Field.description("is_active", .boolean(defaultValue: true))
        Field.description("created_at", .timestamp)
        Field.description("updated_at", .timestamp)
        Field.description("deleted_at", .timestamp)
        Field.description("login_count", .integer(defaultValue: 0))
        Field.description("last_login_at", .timestamp)
        Field.description("preferences", .jsonb)
    }
}
