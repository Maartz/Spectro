//
//  FieldType.swift
//  Spectro
//
//  Created by William MARTIN on 11/3/24.
//

public enum FieldType: Equatable {
    case string
    case integer(default: Int? = nil)
    case boolean(default: Bool? = nil)
    case date
    case double
    case jsonb
}
