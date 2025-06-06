//
//  SchemaMigration.swift
//  Spectro
//
//  Created by William MARTIN on 11/16/24.
//

import Foundation

public struct SchemaMigration: Schema {
    public static let tableName = "schema_migrations"

    @ID public var id: UUID
    @Column public var version: String = ""
    @Column public var name: String = ""
    @Timestamp public var appliedAt: Date = Date()
    @Column public var status: String = ""

    public init() {}
}
