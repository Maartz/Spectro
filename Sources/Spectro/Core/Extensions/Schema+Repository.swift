//
//  Schema+Repository.swift
//  Spectro
//
//  Created by William MARTIN on 6/4/25.
//

import Foundation

// DEPRECATED: Schema-level convenience methods are being phased out
// Use explicit repository pattern instead: repo.get(UserSchema.self, id: userId)
// This file is kept temporarily for backward compatibility during the transition

extension Schema {
    /// DEPRECATED: Use repo.get(Schema.self, id:) instead
    @available(*, deprecated, message: "Use explicit repository pattern: repo.get(Schema.self, id:)")
    public static func get(_ id: UUID) async throws -> Model? {
        throw SpectroError.notImplemented("Schema convenience methods deprecated. Use repo.get(Schema.self, id:) instead")
    }
    
    /// DEPRECATED: Use repo.all(Schema.self) instead
    @available(*, deprecated, message: "Use explicit repository pattern: repo.all(Schema.self)")
    public static func all() async throws -> [Model] {
        throw SpectroError.notImplemented("Schema convenience methods deprecated. Use repo.all(Schema.self) instead")
    }
    
    /// DEPRECATED: Use repo.insert(Schema.self, data:) instead
    @available(*, deprecated, message: "Use explicit repository pattern: repo.insert(Schema.self, data:)")
    public static func insert(_ changes: [String: Any]) async throws -> Model {
        throw SpectroError.notImplemented("Schema convenience methods deprecated. Use repo.insert(Schema.self, data:) instead")
    }
}

// DEPRECATED: Model instance methods are being phased out
// Use explicit repository pattern instead
extension SchemaModel {
    /// DEPRECATED: Use repo.update(Schema.self, id:, changes:) instead
    @available(*, deprecated, message: "Use explicit repository pattern: repo.update(Schema.self, id:, changes:)")
    public func update(_ changes: [String: Any]) async throws -> SchemaModel<S> {
        throw SpectroError.notImplemented("Model convenience methods deprecated. Use repo.update(Schema.self, id:, changes:) instead")
    }
    
    /// DEPRECATED: Use repo.delete(Schema.self, id:) instead
    @available(*, deprecated, message: "Use explicit repository pattern: repo.delete(Schema.self, id:)")
    public func delete() async throws {
        throw SpectroError.notImplemented("Model convenience methods deprecated. Use repo.delete(Schema.self, id:) instead")
    }
    
    /// DEPRECATED: Use repo.get(Schema.self, id:) instead
    @available(*, deprecated, message: "Use explicit repository pattern: repo.get(Schema.self, id:)")
    public func reload() async throws -> SchemaModel<S> {
        throw SpectroError.notImplemented("Model convenience methods deprecated. Use repo.get(Schema.self, id:) instead")
    }
}