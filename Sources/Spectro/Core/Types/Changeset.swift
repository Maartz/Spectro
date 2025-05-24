import Foundation

public struct Changeset<T: Schema> {
  public let schema: T.Type
  public var changes: [String: Any]
  public var errors: [String: [String]] = [:]

  public init(_ schema: T.Type, _ params: [String: Any]) {
    self.schema = schema
    self.changes = [:]

    for field in schema.fields {
      if let value = params[field.name] {
        let validated = schema.validateValue(value, for: field)
        if validated != .null {
          changes[field.name] = validated
        } else {
          addError(field.name, "invalid value type")
        }
      }
    }
  }

  public var isValid: Bool {
    errors.isEmpty
  }

  public mutating func validateRequired(_ fields: [String]) {
    for field in fields {
      if changes[field] == nil {
        addError(field, "is required")
      }
    }
  }

  public mutating func put(_ field: String, _ value: Any) {
    if let schemaField = schema.fields.first(where: { $0.name == field }) {
      let validated = schema.validateValue(value, for: schemaField)
      if validated != .null {
        changes[field] = validated
      } else {
        addError(field, "invalid value type")
      }
    }
  }

  public mutating func addError(_ field: String, _ message: String) {
    if errors[field] != nil {
      errors[field]?.append(message)
    } else {
      errors[field] = [message]
    }
  }
}
