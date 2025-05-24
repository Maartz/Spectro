//
//  Commands.swift
//  Spectro
//
//  Created by William MARTIN on 11/16/24.
//

import ArgumentParser
import Foundation
import Testing

@testable import SpectroCLI
@testable import SpectroCore

@Test func testStringCaseConversion() throws {
  let input = "createUsersTable"
  let snakeCase = input.snakeCase()
  let pascalCase = input.pascalCase()

  #expect(snakeCase == "create_users_table")
  #expect(pascalCase == "CreateUsersTable")
}

@Test func testTestCommandConfiguration() throws {
  let config = Test.configuration
  #expect(config.commandName == "test")
}
