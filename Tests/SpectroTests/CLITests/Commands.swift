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

  #assert(snakeCase, "create_users_table")
  #assert(pascalCase, "CreateUsersTable")
}

@Test func testTestCommandConfiguration() throws {
  let config = Test.configuration
  #assert(config.commandName, "test")
}
