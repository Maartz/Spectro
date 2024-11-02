//
//  Query.swift
//  Spectro
//
//  Created by William MARTIN on 11/1/24.
//

public struct Query: Sendable {
    
    var table: String
    var conditions: [String: (String, ConditionValue)] = [:]
    var selections: [String] = ["*"]

    static func from(_ table: String) -> Query {
        return Query(table: table)
    }

    func `where`(_ field: String, _ op: String, _ value: ConditionValue) -> Query {
        var copy = self
        copy.conditions[field] = (op, value)
        return copy
    }

    func select(_ columns: String...) -> Query {
        var copy = self
        copy.selections = columns
        return copy
    }
}


