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
    
    public init(name: String, type: FieldType, isRedacted: Bool = false) {
        self.name = name
        self.type = type
        self.isRedacted = isRedacted
    }
}
