//
//  Condition.swift
//  Spectro
//
//  Created by William MARTIN on 11/15/24.
//

import PostgresKit

public protocol Condition {
    func toSQL(parameterOffset: Int) -> (clause: String, params: [PostgresData])
}
extension Condition {
    static func && (lhs: Self, rhs: Condition) -> CompositeCondition {
        CompositeCondition(type: .and, conditions: [lhs, rhs])
    }
    
    static func || (lhs: Self, rhs: Condition) -> CompositeCondition {
        CompositeCondition(type: .or, conditions: [lhs, rhs])
    }
}
