import Foundation

/// Core repository protocol for database operations
public protocol Repo: Sendable {
    func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T?
    func getOrFail<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T
    func all<T: Schema>(_ schema: T.Type) async throws -> [T]
    func insert<T: Schema>(_ instance: T) async throws -> T
    func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: any Sendable]) async throws -> T
    func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws
    func transaction<T: Sendable>(_ work: @escaping @Sendable (any Repo) async throws -> T) async throws -> T
}
