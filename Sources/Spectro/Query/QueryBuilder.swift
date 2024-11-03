//
//  QueryBuilder.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import Foundation
import PostgresKit

struct SQLBuilder {
    static func buildWhereClause(
        _ conditions: [String: (String, ConditionValue)]
    ) -> (clause: String, params: [PostgresData]) {
        let whereClause = conditions.keys.enumerated().map { index, key in
            let (op, _) = conditions[key]!
            return "\(key) \(op) $\((index + 1))"
        }.joined(separator: " AND ")

        let params = try! conditions.values.map {
            try $0.1.toPostgresData()
        }
        return (clause: whereClause, params: params)
    }
    
    static func buildInsert(table: String, values: [String: ConditionValue]) -> (sql: String, params: [PostgresData]) {
        let columns = values.keys.joined(separator: ", ")
        let placeholders = (1...values.count).map { "$\($0)" }.joined(separator: ", ")
        let sql = "INSERT INTO \(table) (\(columns)) VALUES (\(placeholders))"
        let params = try! values.values.map { try $0.toPostgresData() }
        
        return (sql: sql, params: params)
    }
    
    static func buildUpdate(
        table: String,
        values: [String: ConditionValue],
        where conditions: [String: (String, ConditionValue)]
    ) -> (sql: String, params: [PostgresData]) {
        let setClause = values.keys.enumerated().map { "\($1) = $\($0 + 1)" }
            .joined(separator: ", ")
        
        let whereClause = buildWhereClause(conditions)
        let offset = values.count
        
        // Adjust parameter numbering for WHERE clause
        let adjustedWhereClause = adjustParameterNumbers(in: whereClause.clause, offset: offset)
        
        let sql = "UPDATE \(table) SET \(setClause) WHERE \(adjustedWhereClause)"
        let params = try! values.values.map { try $0.toPostgresData() } + whereClause.params
        
        return (sql: sql, params: params)
    }
    
    private static func adjustParameterNumbers(in clause: String, offset: Int) -> String {
        let regex = try! NSRegularExpression(pattern: #"\$(\d+)"#)
        var result = clause
        
        let matches = regex.matches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result)
        )
        
        for match in matches.reversed() {
            if let matchRange = Range(match.range(at: 1), in: result),
               let number = Int(result[matchRange]) {
                let adjustedNumber = "$\(number + offset)"
                if let fullMatchRange = Range(match.range, in: result) {
                    result.replaceSubrange(fullMatchRange, with: adjustedNumber)
                }
            }
        }
        
        return result
    }
}
