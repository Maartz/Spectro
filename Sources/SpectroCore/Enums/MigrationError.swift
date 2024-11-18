//
//  MigrationError.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

public enum MigrationError: Error {
    case fileExists(String)
    case invalidMigrationName(String)
    case invalidMigrationMissingTimestamp
    case directoryNotFound(String)
    case invalidMigrationFile(String)
}
