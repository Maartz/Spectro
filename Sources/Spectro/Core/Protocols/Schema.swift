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
    
    /// Returns only database columns (excludes virtual relationship fields)
    public static var databaseFields: [SField] {
        var dbFields: [SField] = []
        
        for field in allFields {
            switch field.type {
            case .relationship(let relationship):
                // Only belongsTo creates a real database column (foreign key)
                if relationship.type == .belongsTo {
                    // Create a new field with the foreign key column name
                    let foreignKeyName = "\(field.name)_id"
                    let foreignKeyField = SField(name: foreignKeyName, type: .uuid)
                    dbFields.append(foreignKeyField)
                }
                // hasMany, hasOne, manyToMany are virtual - no database columns
            default:
                // Regular database fields
                dbFields.append(field)
            }
        }
        
        return dbFields
    }

    public static subscript(dynamicMember member: String) -> SField? {
        allFields.first { $0.name == member }
    }
}
