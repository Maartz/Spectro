//
//  QueryCondition.swift
//  Spectro
//
//  Created by William MARTIN on 11/15/24.
//

public struct QueryCondition: Condition {
    let field: String
    let op: String
    let value: ConditionValue

    // Add operators
    static func && (lhs: QueryCondition, rhs: QueryCondition)
        -> CompositeCondition
    {
        CompositeCondition(type: .and, conditions: [lhs, rhs])
    }

    static func || (lhs: QueryCondition, rhs: QueryCondition)
        -> CompositeCondition
    {
        CompositeCondition(type: .or, conditions: [lhs, rhs])
    }
}
