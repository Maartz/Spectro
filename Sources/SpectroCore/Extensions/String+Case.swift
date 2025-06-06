//
//  String+Case.swift
//  SpectroCore
//
//  Created by William MARTIN on 11/16/24.
//

import Foundation

public extension String {
    func snakeCase() -> String {
        let pattern = "([a-z0-9])([A-Z])"
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            // Fallback: simple character-by-character conversion if regex fails
            return self.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "-", with: "_")
        }
        
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
        let words = self.snakeCase().split(separator: "_")
        return words
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined()
    }
}
