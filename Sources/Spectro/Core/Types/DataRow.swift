//
//  DataRow.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

public struct DataRow: @unchecked Sendable {
    public let values: [String: Any]

    init(values: [String: Any]) {
        self.values = values
    }
}
