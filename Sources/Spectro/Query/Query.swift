//
//  Query.swift
//  Spectro
//
//  Created by William MARTIN on 11/1/24.
//

public struct Query {
    var table: String
    var conditions: [String] = []
    var selections: [String] = ["*"] // Default to select all

    static func from(_ table: String) -> Query {
        return Query(table: table)
    }

    func `where`(_ condition: String) -> Query {
        var copy = self
        copy.conditions.append(condition)
        return copy
    }

    func select(_ columns: String...) -> Query {
        var copy = self
        copy.selections = columns
        return copy
    }
}
