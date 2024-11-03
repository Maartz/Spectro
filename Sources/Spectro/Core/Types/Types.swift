//
//  Types.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

public struct DataRow: Sendable {
    public let values: [String: String]

    init(values: [String: String]) {
        self.values = values
    }
}
