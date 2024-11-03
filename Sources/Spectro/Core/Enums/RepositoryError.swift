//
//  Repository.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

enum RepositoryError: Error, Equatable {
    case invalidQueryResult
    case unexpectedResultCount(String)
}
