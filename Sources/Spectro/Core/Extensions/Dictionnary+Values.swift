//
//  Dictionnary+Values.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//
import Foundation

extension Dictionary where Key == String, Value == ConditionValue {
    public static func with(_ values: [String: Any?]) -> [String: ConditionValue] {
        values.compactMapValues { value in
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
            case .none:
                return nil
            default:
                return .string(String(describing: value))
            }
        }
    }
}

extension Dictionary where Key == String, Value == (String, ConditionValue) {
    public static func conditions(_ values: [String: (String, Any)]) -> [String: (String, ConditionValue)] {
        values.mapValues { op, value -> (String, ConditionValue) in
            let conditionValue: ConditionValue = switch value {
            case let string as String:
                if string.hasPrefix("{") {
                    .jsonb(string)
                } else {
                    .string(string)
                }
            case let int as Int:
                .int(int)
            case let double as Double:
                .double(double)
            case let bool as Bool:
                .bool(bool)
            case let uuid as UUID:
                .uuid(uuid)
            case let date as Date:
                .date(date)
            default:
                .string(String(describing: value))
            }
            return (op, conditionValue)
        }
    }
}
