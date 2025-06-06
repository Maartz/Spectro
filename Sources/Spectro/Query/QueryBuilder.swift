//
//  QueryBuilder.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import Foundation
import PostgresKit

struct SQLBuilder {
    
    /// Build JOIN clauses for a query
    static func buildJoinClauses(_ joins: [JoinInfo], sourceTable: String) -> String {
        return joins.map { join in
            let relationshipInfo = join.relationship
            let joinTable = join.targetSchema.schemaName
            let alias = join.alias ?? joinTable
            
            let joinCondition: String
            switch relationshipInfo.type {
            case .belongsTo:
                // Current table's foreign key = target table's primary key
                joinCondition = "\(sourceTable).\(relationshipInfo.localKey) = \(alias).\(relationshipInfo.foreignKey)"
            case .hasOne, .hasMany:
                // Current table's primary key = target table's foreign key  
                joinCondition = "\(sourceTable).\(relationshipInfo.localKey) = \(alias).\(relationshipInfo.foreignKey)"
            case .manyToMany(let through):
                // Handle many-to-many through pivot table
                joinCondition = "\(sourceTable).id = \(through).\(relationshipInfo.localKey)"
            }
            
            if alias != joinTable {
                return "\(join.joinType.sql) \(joinTable) AS \(alias) ON \(joinCondition)"
            } else {
                return "\(join.joinType.sql) \(joinTable) ON \(joinCondition)"
            }
        }.joined(separator: " ")
    }
    
    /// Build WHERE clauses for relationship conditions
    static func buildRelationshipConditions(
        _ relationshipConditions: [String: [String: (String, ConditionValue)]],
        parameterOffset: Int = 0
    ) throws -> (clause: String, params: [PostgresData]) {
        var clauseParts: [String] = []
        var params: [PostgresData] = []
        var paramIndex = parameterOffset + 1
        
        for (relationshipName, conditions) in relationshipConditions {
            for (column, (op, value)) in conditions {
                let qualifiedColumn = "\(relationshipName).\(column)"
                
                switch value {
                case .null:
                    if op == "IS NULL" {
                        clauseParts.append("\(qualifiedColumn) IS NULL")
                    } else if op == "IS NOT NULL" {
                        clauseParts.append("\(qualifiedColumn) IS NOT NULL")
                    } else {
                        throw SpectroError.invalidParameter(name: "operator", value: op, reason: "Operator \(op) not supported for NULL values. Use 'IS NULL' or 'IS NOT NULL'")
                    }
                case .between(let start, let end):
                    clauseParts.append("\(qualifiedColumn) BETWEEN $\(paramIndex) AND $\(paramIndex + 1)")
                    params.append(try start.toPostgresData())
                    params.append(try end.toPostgresData())
                    paramIndex += 2
                case .array(let values):
                    if op == "IN" {
                        let placeholders = (0..<values.count).map { "$\(paramIndex + $0)" }.joined(separator: ", ")
                        clauseParts.append("\(qualifiedColumn) IN (\(placeholders))")
                        for arrayValue in values {
                            params.append(try arrayValue.toPostgresData())
                        }
                        paramIndex += values.count
                    } else {
                        throw SpectroError.invalidParameter(name: "operator", value: op, reason: "Array values only supported with 'IN' operator, got '\(op)'")
                    }
                default:
                    clauseParts.append("\(qualifiedColumn) \(op) $\(paramIndex)")
                    params.append(try value.toPostgresData())
                    paramIndex += 1
                }
            }
        }
        
        return (clause: clauseParts.joined(separator: " AND "), params: params)
    }
    static func buildWhereClause(
        _ conditions: [String: (String, ConditionValue)]
    ) throws -> (clause: String, params: [PostgresData]) {
        var clauseParts: [String] = []
        var params: [PostgresData] = []
        var paramIndex = 1

        for (column, (op, value)) in conditions {
            switch value {
            case .null:
                if op == "IS NULL" {
                    clauseParts.append("\(column) IS NULL")
                } else if op == "IS NOT NULL" {
                    clauseParts.append("\(column) IS NOT NULL")
                } else {
                    throw SpectroError.invalidParameter(name: "operator", value: op, reason: "Operator \(op) not supported for NULL values. Use 'IS NULL' or 'IS NOT NULL'")
                }
            case .between(let start, let end):
                clauseParts.append(
                    "\(column) BETWEEN $\(paramIndex) AND $\(paramIndex + 1)")
                params.append(try start.toPostgresData())
                params.append(try end.toPostgresData())
                paramIndex += 2
            case .array(let values):
                if op == "IN" {
                    let placeholders = (0..<values.count).map { "$\(paramIndex + $0)" }.joined(separator: ", ")
                    clauseParts.append("\(column) IN (\(placeholders))")
                    for arrayValue in values {
                        params.append(try arrayValue.toPostgresData())
                    }
                    paramIndex += values.count
                } else {
                    throw SpectroError.invalidParameter(name: "operator", value: op, reason: "Array values only supported with 'IN' operator, got '\(op)'")
                }
            default:
                clauseParts.append("\(column) \(op) $\(paramIndex)")
                params.append(try value.toPostgresData())
                paramIndex += 1
            }
        }

        return (clause: clauseParts.joined(separator: " AND "), params: params)
    }

    static func buildWhereClause(_ condition: CompositeCondition) -> (
        clause: String, params: [PostgresData]
    ) {
        condition.toSQL(parameterOffset: 0)
    }

    static func buildInsert(table: String, values: [String: ConditionValue])
        throws -> (sql: String, params: [PostgresData])
    {
        let columns = values.keys.joined(separator: ", ")
        let placeholders = (1...values.count).map { "$\($0)" }.joined(
            separator: ", ")
        let sql = "INSERT INTO \(table) (\(columns)) VALUES (\(placeholders))"
        let params = try values.values.map { try $0.toPostgresData() }

        return (sql: sql, params: params)
    }

    static func buildUpdate(
        table: String,
        values: [String: ConditionValue],
        where conditions: [String: (String, ConditionValue)]
    ) throws -> (sql: String, params: [PostgresData]) {
        let setClause = values.keys.enumerated().map { "\($1) = $\($0 + 1)" }
            .joined(separator: ", ")

        let whereClause = try buildWhereClause(conditions)
        let offset = values.count

        let adjustedWhereClause = adjustParameterNumbers(
            in: whereClause.clause, offset: offset)

        let sql =
            "UPDATE \(table) SET \(setClause) WHERE \(adjustedWhereClause)"
        let params =
            try values.values.map { try $0.toPostgresData() }
            + whereClause.params

        return (sql: sql, params: params)
    }

    private static func adjustParameterNumbers(in clause: String, offset: Int)
        -> String
    {
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
