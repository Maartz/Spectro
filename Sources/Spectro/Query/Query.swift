//
//  Query.swift
//  Spectro
//
//  Created by William MARTIN on 11/1/24.
//

import Foundation
import PostgresKit

public struct Query: Sendable {
    let table: String
    let schema: Schema.Type
    var conditions: [String: (String, ConditionValue)] = [:]
    var compositeConditions: [CompositeCondition] = []
    var selections: [String] = ["*"]
    var orderBy: [OrderByField] = []
    var limit: Int?
    var offset: Int?
    // New fields for joins and relationships
    var joins: [JoinInfo] = []
    var relationshipConditions: [String: [String: (String, ConditionValue)]] = [:]
    var preloadRelationships: [String] = []

    private init(table: String, schema: Schema.Type) {
        self.table = table
        self.schema = schema
    }

    static func from(_ schema: any Schema.Type) -> Query {
        return Query(table: schema.schemaName, schema: schema)
    }

    func `where`(_ builder: (FieldSelector) -> Condition) -> Query {
        var copy = self
        let selector = FieldSelector(schema: schema)
        let condition = builder(selector)

        switch condition {
        case let simple as QueryCondition:
            copy.conditions[simple.field] = (simple.op, simple.value)
        case let composite as CompositeCondition:
            copy.compositeConditions.append(composite)
        default:
            fatalError("Unexpected condition type")
        }
        return copy
    }

    func select(_ columns: (FieldSelector) -> [FieldPredicate]) -> Query {
        var copy = self
        let selector = FieldSelector(schema: schema)
        copy.selections = columns(selector).map { $0.fieldName }
        return copy
    }

    func orderBy(_ builder: (FieldSelector) -> [OrderByField]) -> Query {
        var copy = self
        let selector = FieldSelector(schema: schema)
        copy.orderBy = builder(selector)
        return copy
    }

    func limit(_ value: Int) -> Query {
        var copy = self
        copy.limit = value
        return copy
    }

    func offset(_ value: Int) -> Query {
        var copy = self
        copy.offset = value
        return copy
    }

    func debugSQL() -> String {
        // Build JOIN clauses
        let joinClause = joins.isEmpty ? "" : " " + SQLBuilder.buildJoinClauses(joins, sourceTable: table)
        
        // Build WHERE clauses for main table
        let whereClause = SQLBuilder.buildWhereClause(conditions)
        
        // Build WHERE clauses for composite conditions
        var compositeWhereClauses: [(clause: String, params: [PostgresData])] = []
        var parameterOffset = whereClause.params.count
        
        for composite in compositeConditions {
            let compositeWhere = SQLBuilder.buildWhereClause(composite)
            // Adjust parameter indices to be sequential
            let adjustedClause = adjustParameterNumbers(in: compositeWhere.clause, offset: parameterOffset)
            compositeWhereClauses.append((clause: adjustedClause, params: compositeWhere.params))
            parameterOffset += compositeWhere.params.count
        }
        
        // Build WHERE clauses for joined relationships
        let relationshipWhere = SQLBuilder.buildRelationshipConditions(
            relationshipConditions,
            parameterOffset: parameterOffset
        )
        
        // Combine WHERE conditions
        var allConditions: [String] = []
        
        if !whereClause.clause.isEmpty {
            allConditions.append(whereClause.clause)
        }
        
        for compositeWhere in compositeWhereClauses {
            if !compositeWhere.clause.isEmpty {
                allConditions.append(compositeWhere.clause)
            }
        }
        
        if !relationshipWhere.clause.isEmpty {
            allConditions.append(relationshipWhere.clause)
        }
        
        let combinedWhereClause = allConditions.isEmpty ? "" : " WHERE " + allConditions.joined(separator: " AND ")
        
        let orderClause = orderBy.isEmpty ? "" : " ORDER BY " + orderBy.map { "\($0.field) \($0.direction.sql)" }
            .joined(separator: ", ")
        let limitClause = limit.map { " LIMIT \($0)" } ?? ""
        let offsetClause = offset.map { " OFFSET \($0)" } ?? ""
        
        return """
        SELECT \(selections.joined(separator: ", "))
        FROM \(table)\(joinClause)\(combinedWhereClause)\(orderClause)\(limitClause)\(offsetClause)
        """
    }
    
    private func adjustParameterNumbers(in clause: String, offset: Int) -> String {
        let regex = try! NSRegularExpression(pattern: #"\$(\d+)"#)
        var result = clause
        
        let matches = regex.matches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result)
        )
        
        for match in matches.reversed() {
            if let matchRange = Range(match.range(at: 1), in: result),
                let number = Int(result[matchRange])
            {
                let adjustedNumber = "$\(number + offset)"
                if let fullMatchRange = Range(match.range, in: result) {
                    result.replaceSubrange(fullMatchRange, with: adjustedNumber)
                }
            }
        }
        
        return result
    }

}
