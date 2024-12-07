import Foundation

public struct Inflector {
    private static let irregularPlurals: [String: String] = [
        "person": "people",
        "child": "children",
        "tooth": "teeth",
        "goose": "geese",
        "foot": "feet",
        "mouse": "mice",
        "criterion": "criteria",
        "analysis": "analyses",
        "datum": "data",
        "medium": "media",
        "stimulus": "stimuli",
        "phenomenon": "phenomena",
        "index": "indices",
        "matrix": "matrices",
        "vertex": "vertices",
        "axis": "axes",
    ]

    private static let uncountable: Set<String> = [
        "equipment", "information", "rice", "money", "species",
        "series", "fish", "sheep", "water", "weather", "software",
        "hardware", "feedback", "deer", "traffic", "metadata",
    ]

    private static let pluralizationRules: [(String, String)] = [
        // Words ending in 'y' preceded by a consonant
        ("([^aeiou])y$", "$1ies"),
        // Words ending in 'o' preceded by a consonant
        ("([^aeiou])o$", "$1oes"),
        // Words ending in 'is'
        ("(.*)(is)$", "$1es"),
        // Words ending in 'us'
        ("(.*)(us)$", "$1i"),
        // Words ending in 'ch', 'sh', 'ss', 'x'
        ("(.*)(ch|sh|ss|x)$", "$1$2es"),
        // Words ending in 'f' or 'fe'
        ("(.*)([^f])f[e]?$", "$1$2ves"),
        // Default rule: add 's'
        ("(.*)$", "$1s"),
    ]

    private static let singularizationRules: [(String, String)] = [
        // Reverse of pluralization rules
        ("(.*)ies$", "$1y"),
        ("(.*)oes$", "$1o"),
        ("(.*)ces$", "$1x"),
        ("(.*)ves$", "$1f"),
        ("(.*)les$", "$1le"),
        ("(.*)es$", "$1"),
        ("(.*)s$", "$1"),
    ]

    /// Converts a word to its singular form
    /// - Parameter word: The plural word to convert
    /// - Returns: The singular form of the word
    public static func singularize(_ word: String) -> String {
        // Return as-is if it's uncountable
        if uncountable.contains(word.lowercased()) {
            return word
        }

        // Check for irregular plurals
        if let singular = irregularPlurals.first(where: { $0.value == word })?.key {
            return singular
        }

        // Apply singularization rules
        for (pattern, replacement) in singularizationRules {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(word.startIndex..., in: word)
                if regex.firstMatch(in: word, options: [], range: range) != nil {
                    let singularized = regex.stringByReplacingMatches(
                        in: word,
                        options: [],
                        range: range,
                        withTemplate: replacement
                    )
                    return singularized
                }
            }
        }

        return word
    }

    /// Converts a word to its plural form
    /// - Parameter word: The singular word to convert
    /// - Returns: The plural form of the word
    public static func pluralize(_ word: String) -> String {
        // Return as-is if it's uncountable
        if uncountable.contains(word.lowercased()) {
            return word
        }

        // Check for irregular plurals
        if let plural = irregularPlurals[word] {
            return plural
        }

        // Apply pluralization rules
        for (pattern, replacement) in pluralizationRules {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(word.startIndex..., in: word)
                if regex.firstMatch(in: word, options: [], range: range) != nil {
                    let pluralized = regex.stringByReplacingMatches(
                        in: word,
                        options: [],
                        range: range,
                        withTemplate: replacement
                    )
                    return pluralized
                }
            }
        }

        return word
    }
}

extension String {
    public func singularize() -> String {
        Inflector.singularize(self)
    }

    public func pluralize() -> String {
        Inflector.pluralize(self)
    }
}

#if DEBUG
    // Tests to verify pluralization rules
    extension Inflector {
        static func runTests() {
            // Test irregular plurals
            assert(singularize("people") == "person")
            assert(pluralize("person") == "people")

            // Test regular rules
            assert(singularize("categories") == "category")
            assert(pluralize("category") == "categories")

            // Test uncountable words
            assert(singularize("fish") == "fish")
            assert(pluralize("fish") == "fish")

            // Test common database table names
            assert(singularize("users") == "user")
            assert(singularize("addresses") == "address")
            assert(singularize("categories") == "category")
            assert(singularize("companies") == "company")
            assert(singularize("countries") == "country")
            assert(singularize("entries") == "entry")
            assert(singularize("facilities") == "facility")
        }
    }
#endif
