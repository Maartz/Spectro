//
//  Repository.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

protocol Repository {
    func all(query: Query) async throws -> [DataRow]
    func insert(into table: String, values: [String: ConditionValue])
        async throws
    func update(
        table: String, values: [String: ConditionValue],
        where conditions: [String: (String, ConditionValue)]) async throws
    func delete(
        from table: String, where conditions: [String: (String, ConditionValue)]
    ) async throws
    func count(
        from table: String, where conditions: [String: (String, ConditionValue)]
    ) async throws -> Int
    func get(
        from table: String, selecting columns: [String],
        where conditions: [String: (String, ConditionValue)]
    ) async throws -> DataRow?
    func one(
        from table: String, selecting columns: [String],
        where conditions: [String: (String, ConditionValue)]
    ) async throws -> DataRow
    func executeRaw(_ sql: String, _ bindings: [Encodable]) async throws
    func createTable<S: Schema>(_ s: S.Type) async throws
}

extension Repository {
    func createTable<S: Schema>(_ schema: S.Type) async throws {
        try await executeRaw(schema.createTable(), [])
    }
}
