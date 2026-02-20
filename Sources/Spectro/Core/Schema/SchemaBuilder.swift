import Foundation
@preconcurrency import PostgresNIO

/// Protocol for building schema instances from database rows.
///
/// Implement this to eliminate runtime reflection on the hot path.
/// Use the `@Schema` macro to generate the implementation automatically.
///
/// ```swift
/// @Schema
/// struct User: Schema { ... }
/// // @Schema generates:
/// // extension User: SchemaBuilder {
/// //     public static func build(from values: [String: Any]) -> User { ... }
/// // }
/// ```
public protocol SchemaBuilder: Schema {
    static func build(from values: [String: Any]) -> Self
}

/// Default no-op implementation. Concrete types should override via
/// `@Schema` macro or a manual `SchemaBuilder` conformance.
extension SchemaBuilder {
    public static func build(from values: [String: Any]) -> Self {
        Self()
    }
}

// MARK: - Row Mapping

extension Schema {
    /// Synchronous row mapping for contexts where async is unavailable.
    public static func fromSync(row: PostgresRow) throws -> Self {
        // Synchronous path: returns a default instance.
        // For full field population, prefer the async from(row:) which
        // consults SchemaRegistry metadata.
        return Self()
    }

    /// Map a PostgreSQL row to a schema instance.
    ///
    /// 1. Registers the schema with `SchemaRegistry` to obtain field metadata.
    /// 2. Extracts each column value using the `FieldType` enum — no metatype
    ///    traffic across actor boundaries.
    /// 3. Delegates construction to `SchemaBuilder.build(from:)` if available,
    ///    otherwise falls back to `MutableSchema.apply(values:)`.
    public static func from(row: PostgresRow) async throws -> Self {
        let metadata = await SchemaRegistry.shared.register(self)
        let randomAccess = row.makeRandomAccess()

        var values: [String: Any] = [:]
        for field in metadata.fields {
            let dbValue = randomAccess[data: field.databaseName]
            // Switch on FieldType enum — fully Sendable, no Any.Type metatypes
            switch field.fieldType {
            case .string:
                if let v = dbValue.string  { values[field.name] = v }
            case .int:
                if let v = dbValue.int     { values[field.name] = v }
            case .bool:
                if let v = dbValue.bool    { values[field.name] = v }
            case .uuid:
                if let v = dbValue.uuid    { values[field.name] = v }
            case .date:
                if let v = dbValue.date    { values[field.name] = v }
            case .double:
                if let v = dbValue.double  { values[field.name] = v }
            case .float:
                if let v = dbValue.float   { values[field.name] = v }
            }
        }

        if let builderType = self as? any SchemaBuilder.Type {
            return builderType.build(from: values) as! Self
        }
        if var mutable = Self() as? MutableSchema {
            mutable.apply(values: values)
            return mutable as! Self
        }
        throw SpectroError.invalidSchema(
            reason: "Schema \(Self.self) must conform to SchemaBuilder (use @Schema macro) or MutableSchema"
        )
    }
}
