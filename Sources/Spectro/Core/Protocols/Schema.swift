//
//  Schema.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

import Foundation

@dynamicMemberLookup
protocol Schema {
    static var schemaName: String { get }
    static var fields: [SField] { get }
    static var includesImplicitID: Bool { get }

    static subscript(dynamicMember member: String) -> SField? { get }
}

extension Schema {
    public static var includesImplicitID: Bool { true }

    public static var allFields: [SField] {
        var combinedFields = fields
        if includesImplicitID {
            combinedFields.insert(Field.description("id", .uuid), at: 0)
        }
        return combinedFields
    }

    public static subscript(dynamicMember member: String) -> SField? {
        allFields.first { $0.name == member }
    }
}
