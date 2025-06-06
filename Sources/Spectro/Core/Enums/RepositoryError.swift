//
//  Repository.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

enum RepositoryError: Error, Equatable {
    case invalidQueryResult
    case unexpectedResultCount(String)
    case invalidData(String)
    case invalidChangeset([String: [String]])
    case notFound(String)
    case invalidRelationship(String)
    case notImplemented(String)
}
