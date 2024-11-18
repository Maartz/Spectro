//
//  Test.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import ArgumentParser
@testable import SpectroCore

struct Test: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test"
    )
    
    @Argument(help: "String to convert")
    var input: String
    
    func run() throws {
        print("Original: \(input)")
        print("Snake case: \(input.snakeCase())")
        print("Pascal case: \(input.pascalCase())")
    }
}
