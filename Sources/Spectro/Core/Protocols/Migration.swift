//
//  Migration.swift
//  Spectro
//
//  Created by William MARTIN on 11/16/24.
//

public protocol Migration {
    var version: String { get }
    
    func up() -> String
    func down() -> String
}
