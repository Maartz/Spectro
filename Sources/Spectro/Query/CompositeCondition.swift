//
//  CompositeCondition.swift
//  Spectro
//
//  Created by William MARTIN on 11/15/24.
//

public struct CompositeCondition: Condition {
    enum CompositeType {
        case and
        case or
    }
    
    let type: CompositeType
    let conditions: [QueryCondition]
    
    // Add operators for chaining
    static func && (lhs: CompositeCondition, rhs: QueryCondition) -> CompositeCondition {
        CompositeCondition(type: lhs.type, conditions: lhs.conditions + [rhs])
    }
    
    static func || (lhs: CompositeCondition, rhs: QueryCondition) -> CompositeCondition {
        CompositeCondition(type: lhs.type, conditions: lhs.conditions + [rhs])
    }
}
