//
//  Field.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

public struct SField {
    public let name: String
    public let type: FieldType
    public let isRedacted: Bool
    public let relationship: Relationship?

    public init(
        name: String, type: FieldType, isRedacted: Bool = false, relationship: Relationship? = nil
    ) {
        self.name = name
        self.type = type
        self.isRedacted = isRedacted
        self.relationship = relationship
    }
}
