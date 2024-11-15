//
//  OrderDirection.swift
//  Spectro
//
//  Created by William MARTIN on 11/15/24.
//

public enum OrderDirection: Sendable {
    case asc
    case desc
    
    var sql: String {
        switch self {
        case .asc: return "ASC"
        case .desc: return "DESC"
        }
    }
}
