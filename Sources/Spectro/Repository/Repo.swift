import Foundation

public protocol Repo {
  func all<T: Schema>(_ schema: T.Type, query: ((Query) -> Query)?) async throws -> [T.Model]
  func get<T: Schema>(_ schema: T.Type, _ id: UUID) async throws -> T.Model?
  func getOrFail<T: Schema>(_ schema: T.Type, _ id: UUID) async throws -> T.Model
  func insert<T: Schema>(_ changeset: Changeset<T>) async throws -> T.Model
  func update<T: Schema>(_ model: T.Model, _ changeset: Changeset<T>) async throws -> T.Model
  func delete<T: Schema>(_ model: T.Model) async throws
  func preload<T: Schema>(_ models: [T.Model], _ associations: [String]) async throws -> [T.Model]
}
