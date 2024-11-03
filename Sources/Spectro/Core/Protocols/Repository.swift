//
//  Repository.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

public protocol Repository {
    func all(query: Query) async throws -> [DataRow]
    func insert(into table: String, values: [String: ConditionValue]) async throws
    func update(table: String, values: [String: ConditionValue], where conditions: [String: (String, ConditionValue)]) async throws
    func delete(from table: String, where conditions: [String: (String, ConditionValue)]) async throws
    func count(from table: String, where conditions: [String: (String, ConditionValue)]) async throws -> Int
}
