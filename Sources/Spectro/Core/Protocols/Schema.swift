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
    static var includesImplicitID: Bool { get }
    static var uuidPK: Bool { get }

    static subscript(dynamicMember member: String) -> SField? { get }
}

extension Schema {
    public static var includesImplicitID: Bool { true }
    public static var uuidPK: Bool { true }

    public static var allFields: [SField] {
        var combinedFields = fields
        // TODO: add the case where uuidPK is false
        // pass it as Integer
        if uuidPK && includesImplicitID {
            combinedFields.insert(Field.description("id", .uuid), at: 0)
        }
        return combinedFields
    }

    public static subscript(dynamicMember member: String) -> SField? {
        allFields.first { $0.name == member }
    }
}
