import Foundation
import PostgresKit

extension Schema {
    static func validateValue(_ value: Any?, for field: SField) -> ConditionValue {
        guard let value = value else {
            if field.name == "id" {
                return .uuid(UUID())
            }
            return .null
        }

        switch field.type {
        case .string:
            return .string(String(describing: value))

        case .integer(let defaultValue):
            if let int = value as? Int {
                return .int(int)
            }
            if let defaultInt = defaultValue {
                return .int(defaultInt)
            }
            return .null

        case .float(let defaultValue):
            if let double = value as? Double {
                return .double(double)
            }
            if let defaultDouble = defaultValue {
                return .double(defaultDouble)
            }
            return .null

        case .boolean(let defaultValue):
            if let bool = value as? Bool {
                return .bool(bool)
            }
            if let defaultBool = defaultValue {
                return .bool(defaultBool)
            }
            return .null

        case .jsonb:
            if let string = value as? String {
                return .jsonb(string)
            }
            if let dict = value as? [String: Any] {
                if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                    let jsonString = String(data: jsonData, encoding: .utf8)
                {
                    return .jsonb(jsonString)
                }
            }
            if let array = value as? [Any] {
                if let jsonData = try? JSONSerialization.data(withJSONObject: array),
                    let jsonString = String(data: jsonData, encoding: .utf8)
                {
                    return .jsonb(jsonString)
                }
            }
            return .null

        case .uuid:
            if let uuid = value as? UUID {
                return .uuid(uuid)
            }
            if let string = value as? String,
                let uuid = UUID(uuidString: string)
            {
                return .uuid(uuid)
            }
            if field.name == "id" {
                return .uuid(UUID())
            }
            return .null

        case .timestamp:
            if let date = value as? Date {
                return .date(date)
            }
            return .null

        case .relationship(type: _, target: _):
            if let string = value as? String {
                return .jsonb(string)
            }
            // Ensure arrays and dictionaries are properly converted to JSONB
            if let jsonData = try? JSONSerialization.data(withJSONObject: value),
                let jsonString = String(data: jsonData, encoding: .utf8)
            {
                return .jsonb(jsonString)
            }
            return .null

        case .foreignKey(to: _):
            if let uuid = value as? UUID {
                return .uuid(uuid)
            }
            if let string = value as? String,
                let uuid = UUID(uuidString: string)
            {
                return .uuid(uuid)
            }
            return .null
        }
    }

    static func createTable() -> String {
        let fieldDefinitions = allFields.map { field in
            var def = "\(field.name) \(field.type.sqlDefinition)"

            if field.name == "id" {
                def += " PRIMARY KEY"
            }

            if let defaultValue = field.type.defaultValue {
                switch defaultValue {
                case let int as Int:
                    def += " DEFAULT \(int)"
                case let double as Double:
                    def += " DEFAULT \(double)"
                case let bool as Bool:
                    def += " DEFAULT \(bool)"
                default:
                    break
                }
            }

            if case .foreignKey(let target) = field.type {
                def += " REFERENCES \(target.schemaName)(id) ON DELETE CASCADE"
            }
            return def
        }

        return """
                CREATE TABLE IF NOT EXISTS \(schemaName) (
                    \(fieldDefinitions.joined(separator: ",\n    "))
                );
            """
    }

    // TODO: create a function updateTable
}

extension Repository {
    func insert<S: Schema>(_ schema: S.Type, values: [String: Any]) async throws {
        let validatedValues = Dictionary(
            uniqueKeysWithValues:
                schema.allFields.compactMap { field in
                    let value = values[field.name]
                    let validatedValue = schema.validateValue(value, for: field)
                    print("Validating field: \(field.name) with value type: \(type(of: value))")  // Debug print
                    return (field.name, validatedValue)
                }
        )

        try await insert(into: schema.schemaName, values: validatedValues)
    }
}
