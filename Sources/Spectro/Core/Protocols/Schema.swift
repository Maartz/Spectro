//
//  Schema.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import Foundation

@dynamicMemberLookup
public protocol Schema {
    static var schemaName: String { get }
    static var fields: [SField] { get }

    static subscript(dynamicMember member: String) -> SField? { get }
}

public extension Schema {
    static subscript(dynamicMember member: String) -> SField? {
        fields.first { $0.name == member }
    }
}
