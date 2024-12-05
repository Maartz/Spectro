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
        Field.hasMany("posts", PostSchema.self)
        Field.hasOne("profile", ProfileSchema.self)
    }
}

struct PostSchema: Schema {
    static let schemaName = "posts"

    @SchemaBuilder
    static var fields: [SField] {
        Field.description("title", .string)
        Field.description("content", .string)
        Field.belongsTo(UserSchema.self)
        Field.description("created_at", .timestamp)
    }
}

struct ProfileSchema: Schema {
    static let schemaName = "profiles"
    
    @SchemaBuilder
    static var fields: [SField] {
        Field.description("bio", .string)
        Field.description("avatar_url", .string)
        Field.belongsTo(UserSchema.self)
    }
}
