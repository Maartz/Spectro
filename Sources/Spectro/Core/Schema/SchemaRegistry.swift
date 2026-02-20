import Foundation

// MARK: - FieldType
//
// Replaces Any.Type in FieldInfo. Using a closed enum instead of metatypes
// makes FieldInfo fully Sendable without @unchecked, and allows exhaustive
// switching in SchemaMapper without runtime reflection.

public enum FieldType: Sendable {
    case string
    case int
    case double
    case float
    case bool
    case uuid
    case date
}

// MARK: - FieldInfo

public struct FieldInfo: Sendable {
    public let name: String
    public let databaseName: String
    public let fieldType: FieldType
    public let isPrimaryKey: Bool
    public let isForeignKey: Bool
    public let isTimestamp: Bool
    public let isNullable: Bool

    /// The Swift metatype for this field, derived from `fieldType`.
    ///
    /// Provided for backward compatibility with `SchemaMapper.extractValue(from:expectedType:)`.
    /// Prefer `fieldType` for new code.
    public var type: Any.Type {
        switch fieldType {
        case .string: return String.self
        case .int: return Int.self
        case .double: return Double.self
        case .float: return Float.self
        case .bool: return Bool.self
        case .uuid: return UUID.self
        case .date: return Date.self
        }
    }
}

// MARK: - SchemaMetadata

public struct SchemaMetadata: Sendable {
    public let tableName: String
    public let fields: [FieldInfo]
    public let primaryKeyField: String?

    public init(tableName: String, fields: [FieldInfo]) {
        self.tableName = tableName
        self.fields = fields
        self.primaryKeyField = fields.first(where: { $0.isPrimaryKey })?.name
    }
}

// MARK: - SchemaRegistry

public actor SchemaRegistry {
    private var registry: [String: SchemaMetadata] = [:]

    public static let shared = SchemaRegistry()

    private init() {}

    public func register<T: Schema>(_ type: T.Type) -> SchemaMetadata {
        let typeName = String(describing: type)
        if let existing = registry[typeName] { return existing }
        let metadata = extractMetadata(from: type)
        registry[typeName] = metadata
        return metadata
    }

    public func metadata<T: Schema>(for type: T.Type) -> SchemaMetadata? {
        registry[String(describing: type)]
    }

    private func extractMetadata<T: Schema>(from type: T.Type) -> SchemaMetadata {
        let instance = T()
        let mirror = Mirror(reflecting: instance)
        let fields = mirror.children.compactMap { child -> FieldInfo? in
            guard let label = child.label else { return nil }
            return extractFieldInfo(label: label, value: child.value)
        }
        return SchemaMetadata(tableName: T.tableName, fields: fields)
    }

    private func extractFieldInfo(label: String, value: Any) -> FieldInfo? {
        let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
        let databaseName = fieldName.snakeCase()

        switch value {
        case is ID:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .uuid,
                             isPrimaryKey: true, isForeignKey: false, isTimestamp: false, isNullable: false)

        case is Column<String>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .string,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case is Column<String?>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .string,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case is Column<Int>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .int,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case is Column<Int?>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .int,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case is Column<Bool>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .bool,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case is Column<Bool?>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .bool,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case is Column<Double>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .double,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case is Column<Double?>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .double,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case is Column<Float>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .float,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case is Column<Float?>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .float,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case is Column<Date>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .date,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: false)
        case is Column<Date?>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .date,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case is Column<UUID?>:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .uuid,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: false, isNullable: true)

        case is Timestamp:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .date,
                             isPrimaryKey: false, isForeignKey: false, isTimestamp: true, isNullable: false)

        case is ForeignKey:
            return FieldInfo(name: fieldName, databaseName: databaseName, fieldType: .uuid,
                             isPrimaryKey: false, isForeignKey: true, isTimestamp: false, isNullable: false)

        default:
            return nil
        }
    }
}

// MARK: - Schema Extension

extension Schema {
    public static var metadata: SchemaMetadata {
        get async {
            await SchemaRegistry.shared.register(self)
        }
    }
}
