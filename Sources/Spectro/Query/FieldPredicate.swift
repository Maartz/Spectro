//
//  FieldPredicate.swift
//  Spectro
//
//  Created by William MARTIN on 11/15/24.
//

public struct FieldPredicate {
    let name: String
    let type: FieldType

    public var fieldName: String { name }

    func like(_ value: String) -> QueryCondition {
        QueryCondition(field: name, op: "LIKE", value: .string(value))
    }

    func eq(_ value: Any) -> QueryCondition {
        QueryCondition(field: name, op: "=", value: ConditionValue.value(value))
    }

    func `in`(_ values: [Any]) -> QueryCondition {
        QueryCondition(
            field: name, op: "IN", value: ConditionValue.value(values))
    }

    func `not`(_ value: Any) -> QueryCondition {
        QueryCondition(
            field: name, op: "NOT", value: ConditionValue.value(value))
    }

    func `is`(_ value: Bool) -> QueryCondition {
        QueryCondition(field: name, op: "IS", value: ConditionValue.bool(value))
    }

    func isNull() -> QueryCondition {
        QueryCondition(field: name, op: "IS NULL", value: .null)
    }

    static func > (lhs: FieldPredicate, rhs: Int) -> QueryCondition {
        QueryCondition(field: lhs.name, op: ">", value: .int(rhs))
    }

    static func >= (lhs: FieldPredicate, rhs: Double) -> QueryCondition {
        QueryCondition(field: lhs.name, op: ">=", value: .double(rhs))
    }

    static func == (lhs: FieldPredicate, rhs: Bool) -> QueryCondition {
        QueryCondition(field: lhs.name, op: "=", value: .bool(rhs))
    }

    static func < (lhs: FieldPredicate, rhs: Int) -> QueryCondition {
        QueryCondition(field: lhs.name, op: "<", value: .int(rhs))
    }

    static func <= (lhs: FieldPredicate, rhs: Double) -> QueryCondition {
        QueryCondition(field: lhs.name, op: "<=", value: .double(rhs))
    }

    func between(_ start: Any, _ end: Any) -> QueryCondition {
        QueryCondition(
            field: name,
            op: "BETWEEN",
            value: .between(
                ConditionValue.value(start), ConditionValue.value(end))  // New ConditionValue case
        )
    }

    func contains(_ value: String) -> QueryCondition {
        QueryCondition(
            field: name,
            op: "LIKE",
            value: .string("%\(value)%")
        )
    }

    func asc() -> OrderByField {
        OrderByField(field: name, direction: .asc)
    }

    func desc() -> OrderByField {
        OrderByField(field: name, direction: .desc)
    }
}

extension FieldPredicate: ExpressibleByStringLiteral, CustomStringConvertible {
    public var description: String {
        name
    }

    public init(stringLiteral value: String) {
        self.name = value
        self.type = .string  // Default, though this shouldn't matter for string conversion
    }
}
