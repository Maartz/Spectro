//
//  SchemaMigration.swift
//  Spectro
//
//  Created by William MARTIN on 11/16/24.
//

struct SchemaMigration: Schema {
    static let schemaName = "schema_migrations"

    @SchemaBuilder
    static var fields: [SField] {
        Field.description("version", .string)
        Field.description("name", .string)
        Field.description("applied_at", .timestamp)
        Field.description("status", .string)
    }
}
