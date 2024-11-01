//
//  Query.swift
//  Spectro
//
//  Created by William MARTIN on 11/1/24.
//

public struct Query: Sendable {
    var table: String
    var conditions: [String] = []
    var selections: [String] = ["*"] // Default to select all

    public static func from(_ table: String) -> Query {
        return Query(table: table)
    }

    public func `where`(_ condition: String) -> Query {
        var copy = self
        copy.conditions.append(condition)
        return copy
    }

    public func select(_ columns: String...) -> Query {
        var copy = self
        copy.selections = columns
        return copy
    }
}
