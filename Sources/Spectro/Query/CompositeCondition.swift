//
//  CompositeCondition.swift
//  Spectro
//
//  Created by William MARTIN on 11/15/24.
//
import PostgresKit

public struct CompositeCondition: Condition {
    enum CompositeType {
        case and
        case or
    }
    
    let type: CompositeType
    let conditions: [any Condition]
    
    static func && (lhs: CompositeCondition, rhs: QueryCondition) -> CompositeCondition {
        CompositeCondition(type: lhs.type, conditions: lhs.conditions + [rhs])
    }
    
    static func || (lhs: CompositeCondition, rhs: QueryCondition) -> CompositeCondition {
        CompositeCondition(type: lhs.type, conditions: lhs.conditions + [rhs])
    }
    
    public func toSQL(parameterOffset: Int) -> (clause: String, params: [PostgresData]) {
            var currentOffset = parameterOffset
            var allParams: [PostgresData] = []
            let clauses = conditions.map { condition -> String in
                let sql = condition.toSQL(parameterOffset: currentOffset)
                currentOffset += sql.params.count
                allParams.append(contentsOf: sql.params)
                return sql.clause
            }
            
            let joinOperator = type == .and ? " AND " : " OR "
            return (
                clause: "(\(clauses.joined(separator: joinOperator)))",
                params: allParams
            )
        }
}
