//
//  SchemaMigration.swift
//  Spectro
//
//  Created by William MARTIN on 11/16/24.
//

import Foundation

public struct SchemaMigration: Schema, SchemaBuilder {
    public static let tableName = "schema_migrations"

    @ID public var id: UUID
    @Column public var version: String = ""
    @Column public var name: String = ""
    @Timestamp public var appliedAt: Date = Date()
    @Column public var status: String = ""

    public init() {}
    
    // MARK: - SchemaBuilder Implementation
    
    public static func build(from values: [String: Any]) -> SchemaMigration {
        var migration = SchemaMigration()
        
        if let id = values["id"] as? UUID {
            migration.id = id
        }
        if let version = values["version"] as? String {
            migration.version = version
        }
        if let name = values["name"] as? String {
            migration.name = name
        }
        if let appliedAt = values["appliedAt"] as? Date {
            migration.appliedAt = appliedAt
        } else if let appliedAt = values["applied_at"] as? Date {
            migration.appliedAt = appliedAt
        }
        if let status = values["status"] as? String {
            migration.status = status
        }
        
        return migration
    }
}
