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
    case null
    case jsonb(String)
    
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
        case .jsonb(let value):
            return try PostgresData(jsonb: value)
        case .null:
            return PostgresData(type: .null, value: nil)
        }
    }
}

extension ConditionValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        if value.hasPrefix("{") {
            self = .jsonb(value)
        } else {
            self = .string(value)
        }
    }
}

extension ConditionValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension ConditionValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension ConditionValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension ConditionValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}
