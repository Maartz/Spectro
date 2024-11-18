//
//  String+Case.swift
//  SpectroCLI
//
//  Created by William MARTIN on 11/16/24.
//

import Foundation

public extension String {
    func snakeCase() -> String {
        let pattern = "([a-z0-9])([A-Z])"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: self.count)
        let snakeCased = regex.stringByReplacingMatches(
            in: self,
            range: range,
            withTemplate: "$1_$2"
        ).lowercased()
        
        return snakeCased
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }
    
    func pascalCase() -> String {
        // First convert to snake case to handle any existing format
        let words = self.snakeCase().split(separator: "_")
        return words
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined()
    }
}
