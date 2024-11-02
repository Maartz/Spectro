//
//  ConditionValue.swift
//  Spectro
//
//  Created by William MARTIN on 11/2/24.
//

import Foundation
import PostgresKit

public enum ConditionValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case uuid(UUID)
    case date(Date)
    
    func toPostgresData() throws -> PostgresData {
        switch self {
        case .string(let value):
            return PostgresData(string: value)
        case .int(let value):
            return PostgresData(int64: Int64(value))
        case .double(let value):
            return PostgresData(double: value)
        case .bool(let value):
            return PostgresData(bool: value)
        case .uuid(let value):
            return PostgresData(uuid: value)
        case .date(let value):
            return PostgresData(date: value)
        }
    }
}
