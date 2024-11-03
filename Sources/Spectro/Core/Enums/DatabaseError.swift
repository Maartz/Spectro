//
//  Database.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

enum DatabaseError: Error {
    case connectionFailed
    case queryFailed(String)
    case invalidData
}
