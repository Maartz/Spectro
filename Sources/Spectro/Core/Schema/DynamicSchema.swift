import Foundation

/// Base class for dynamic schemas with ActiveRecord-style attribute access
/// This approach allows us to set values dynamically without hardcoding
@dynamicMemberLookup
open class DynamicSchema: Schema {
    // Storage for dynamic attributes
    private var attributes: [String: Any] = [:]
    private var propertyWrappers: [String: Any] = [:]
    
    // Required by Schema protocol
    open class var tableName: String {
        fatalError("Subclasses must override tableName")
    }
    
    public required init() {
        // Initialize property wrappers via reflection
        initializePropertyWrappers()
    }
    
    // MARK: - Dynamic Member Lookup
    
    public subscript(dynamicMember member: String) -> Any? {
        get {
            return attributes[member]
        }
        set {
            attributes[member] = newValue
            updatePropertyWrapper(member, value: newValue)
        }
    }
    
    // MARK: - Internal Methods
    
    internal func setAttribute(_ name: String, value: Any?) {
        attributes[name] = value
        updatePropertyWrapper(name, value: value)
    }
    
    internal func getAttribute(_ name: String) -> Any? {
        return attributes[name]
    }
    
    internal func getAllAttributes() -> [String: Any] {
        return attributes
    }
    
    // MARK: - Private Methods
    
    private func initializePropertyWrappers() {
        let mirror = Mirror(reflecting: self)
        
        for child in mirror.children {
            guard let label = child.label else { continue }
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            propertyWrappers[fieldName] = child.value
            
            // Extract initial value from property wrapper
            if let value = extractPropertyWrapperValue(child.value) {
                attributes[fieldName] = value
            }
        }
    }
    
    private func updatePropertyWrapper(_ name: String, value: Any?) {
        // This would update the actual property wrapper
        // Implementation depends on having mutable access to property wrappers
    }
    
    private func extractPropertyWrapperValue(_ wrapper: Any) -> Any? {
        let mirror = Mirror(reflecting: wrapper)
        for child in mirror.children {
            if child.label == "wrappedValue" {
                return child.value
            }
        }
        return wrapper
    }
}

// MARK: - Schema Protocol Extension for Dynamic Behavior

extension Schema {
    /// Apply values to a schema instance using dynamic dispatch
    public mutating func applyValues(_ values: [String: Any]) {
        if var dynamic = self as? DynamicSchema {
            for (key, value) in values {
                dynamic.setAttribute(key, value: value)
            }
            self = dynamic as! Self
        } else {
            // Fallback for non-dynamic schemas
            // This is where we'd need more sophisticated reflection
        }
    }
}