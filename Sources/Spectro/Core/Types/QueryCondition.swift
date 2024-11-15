//
//  QueryCondition.swift
//  Spectro
//
//  Created by William MARTIN on 11/15/24.
//

import PostgresKit

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
    
    public func toSQL(parameterOffset: Int) -> (clause: String, params: [PostgresData]) {
        let param = try! value.toPostgresData()
        return (
            clause: "\(field) \(op) $\(parameterOffset + 1)",
            params: [param]
        )
    }
}
