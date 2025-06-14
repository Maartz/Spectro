import Foundation

/// Extension to extract property names from KeyPaths
extension KeyPath {
    /// Extract the property name from a KeyPath string representation
    var propertyName: String? {
        let keyPathString = String(describing: self)
        
        // Look for patterns like ".$propertyName" or ".propertyName"
        if let dollarIndex = keyPathString.lastIndex(of: "$") {
            let afterDollar = keyPathString.index(after: dollarIndex)
            if afterDollar < keyPathString.endIndex {
                return String(keyPathString[afterDollar...])
            }
        }
        
        // Look for the last dot
        if let lastDot = keyPathString.lastIndex(of: ".") {
            let afterDot = keyPathString.index(after: lastDot)
            if afterDot < keyPathString.endIndex {
                let name = String(keyPathString[afterDot...])
                // Remove any trailing > characters
                return name.trimmingCharacters(in: CharacterSet(charactersIn: ">"))
            }
        }
        
        return nil
    }
}