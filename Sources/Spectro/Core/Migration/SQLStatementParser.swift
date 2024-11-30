import Foundation

enum SQLParsingError: Error {
    case unbalancedDollarQuotes
    case invalidStatement
}

class SQLStatementParser {
    static func parse(_ sql: String) throws -> [String] {
        var statements: [String] = []
        var currentStatement = ""
        var inDollarQuote = false
        var dollarQuoteTag = ""
        
        let lines = sql.components(separatedBy: CharacterSet.newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("--") {
                continue
            }
            
            var i = 0
            let characters = Array(line)
            
            while i < characters.count {
                let char = characters[i]
                
                if char == "$" && i + 1 < characters.count {
                    if !inDollarQuote {
                        var tag = "$"
                        var j = i + 1
                        while j < characters.count && characters[j] != "$" {
                            tag.append(characters[j])
                            j += 1
                        }
                        if j < characters.count && characters[j] == "$" {
                            tag.append("$")
                            dollarQuoteTag = tag
                            inDollarQuote = true
                            currentStatement.append(tag)
                            i = j
                        }
                    } else if i + dollarQuoteTag.count <= characters.count {
                        let potentialEnd = String(characters[i..<min(i + dollarQuoteTag.count, characters.count)])
                        if potentialEnd == dollarQuoteTag {
                            inDollarQuote = false
                            currentStatement.append(dollarQuoteTag)
                            i += dollarQuoteTag.count - 1
                        }
                    }
                }
                else if char == ";" && !inDollarQuote {
                    currentStatement.append(";")
                    let trimmedStatement = currentStatement.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedStatement.isEmpty {
                        statements.append(trimmedStatement)
                    }
                    currentStatement = ""
                } else {
                    currentStatement.append(char)
                }
                
                i += 1
            }
            
            if !currentStatement.isEmpty {
                currentStatement.append("\n")
            }
        }
        
        let finalStatement = currentStatement.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalStatement.isEmpty {
            statements.append(finalStatement + ";")
        }
        
        if inDollarQuote {
            throw SQLParsingError.unbalancedDollarQuotes
        }
        
        return statements
    }
}
