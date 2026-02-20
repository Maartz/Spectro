import Foundation
@preconcurrency import PostgresNIO

/// Handles loading relationships for individual schema instances.
///
/// For batch loading (N+1 prevention), use `Query.preload(_:)` instead.
public struct RelationshipLoader {

    // MARK: - Has-Many

    public static func loadHasMany<Parent: Schema, Child: Schema>(
        for parent: Parent,
        relationship: String,
        childType: Child.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> [Child] {
        let parentMetadata = await SchemaRegistry.shared.register(Parent.self)
        guard let pkField = parentMetadata.primaryKeyField else {
            throw SpectroError.invalidSchema(reason: "Schema \(Parent.self) has no primary key")
        }
        let parentId = try extractUUID(from: parent, fieldName: pkField)
            ?? { throw SpectroError.missingRequiredField("Primary key '\(pkField)' not found in \(Parent.self)") }()
        let condition = QueryCondition(
            sql: "\"\(foreignKey.snakeCase())\" = ?",
            parameters: [PostgresData(uuid: parentId)]
        )
        return try await repo.query(childType).where { _ in condition }.all()
    }

    // MARK: - Has-One

    public static func loadHasOne<Parent: Schema, Child: Schema>(
        for parent: Parent,
        relationship: String,
        childType: Child.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> Child? {
        try await loadHasMany(
            for: parent, relationship: relationship,
            childType: childType, foreignKey: foreignKey, using: repo
        ).first
    }

    // MARK: - Belongs-To

    public static func loadBelongsTo<Child: Schema, Parent: Schema>(
        for child: Child,
        relationship: String,
        parentType: Parent.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> Parent? {
        guard let fkVal = try? extractUUID(from: child, fieldName: foreignKey) else {
            throw SpectroError.missingRequiredField("FK '\(foreignKey)' not found in \(Child.self)")
        }
        return try await repo.get(parentType, id: fkVal)
    }

    // MARK: - UUID Extraction (also used by PreloadQuery)

    /// Extract a UUID from any `@ID`, `@ForeignKey`, or bare `UUID` property by field name.
    static func extractUUID<T: Schema>(from instance: T, fieldName: String) -> UUID? {
        PreloadQuery<T>.extractUUID(from: instance, fieldName: fieldName)
    }
}

// MARK: - Schema Extension API

extension Schema {
    public func loadHasMany<T: Schema>(
        _ type: T.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> [T] {
        try await RelationshipLoader.loadHasMany(
            for: self, relationship: String(describing: type),
            childType: type, foreignKey: foreignKey, using: repo
        )
    }

    public func loadHasOne<T: Schema>(
        _ type: T.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> T? {
        try await RelationshipLoader.loadHasOne(
            for: self, relationship: String(describing: type),
            childType: type, foreignKey: foreignKey, using: repo
        )
    }

    public func loadBelongsTo<T: Schema>(
        _ type: T.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> T? {
        try await RelationshipLoader.loadBelongsTo(
            for: self, relationship: String(describing: type),
            parentType: type, foreignKey: foreignKey, using: repo
        )
    }
}
