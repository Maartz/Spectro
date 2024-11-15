//
//  ConditionValue.swift
//  Spectro
//
//  Created by William MARTIN on 11/2/24.
//

import Foundation
import PostgresKit

public indirect enum ConditionValue: Sendable, Equatable, Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case uuid(UUID)
    case date(Date)
    case null
    case jsonb(String)
    case between(ConditionValue, ConditionValue)

    public static func value(_ value: Any) -> ConditionValue {
        switch value {
        case let string as String:
            if string.hasPrefix("{") {
                return .jsonb(string)
            }
            return .string(string)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let uuid as UUID:
            return .uuid(uuid)
        case let date as Date:
            return .date(date)
        case is NSNull:
            return .null
        default:
            return .string(String(describing: value))
        }
    }

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
        case .between( _, _):
            fatalError("BETWEEN should be handled by SQLBuilder")
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
