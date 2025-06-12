import Foundation

/// Schema field information extracted at runtime
public struct FieldInfo: Sendable {
    public let name: String
    public let databaseName: String
    public let type: Any.Type
    public let isPrimaryKey: Bool
    public let isForeignKey: Bool
    public let isTimestamp: Bool
    public let isNullable: Bool
}

/// Schema metadata for runtime introspection
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

/// Registry for schema metadata - inspired by Ecto's schema compilation
public actor SchemaRegistry {
    private var registry: [String: SchemaMetadata] = [:]
    
    public static let shared = SchemaRegistry()
    
    private init() {}
    
    /// Register a schema type - called automatically when Schema is first used
    public func register<T: Schema>(_ type: T.Type) -> SchemaMetadata {
        let typeName = String(describing: type)
        
        if let existing = registry[typeName] {
            return existing
        }
        
        let metadata = extractMetadata(from: type)
        registry[typeName] = metadata
        return metadata
    }
    
    /// Get metadata for a registered schema
    public func metadata<T: Schema>(for type: T.Type) -> SchemaMetadata? {
        let typeName = String(describing: type)
        return registry[typeName]
    }
    
    /// Extract metadata from a schema type using reflection
    private func extractMetadata<T: Schema>(from type: T.Type) -> SchemaMetadata {
        let instance = T()
        let mirror = Mirror(reflecting: instance)
        
        var fields: [FieldInfo] = []
        
        for child in mirror.children {
            guard let label = child.label else { continue }
            
            // Extract field info based on property wrapper type
            if let fieldInfo = extractFieldInfo(label: label, value: child.value) {
                fields.append(fieldInfo)
            }
        }
        
        return SchemaMetadata(tableName: T.tableName, fields: fields)
    }
    
    private func extractFieldInfo(label: String, value: Any) -> FieldInfo? {
        // Remove underscore prefix from property wrapper storage
        let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
        let databaseName = fieldName.snakeCase()
        
        // Determine field type and attributes based on property wrapper
        switch value {
        case let id as ID:
            return FieldInfo(
                name: fieldName,
                databaseName: databaseName,
                type: UUID.self,
                isPrimaryKey: true,
                isForeignKey: false,
                isTimestamp: false,
                isNullable: false
            )
            
        case let column as Column<String>:
            return FieldInfo(
                name: fieldName,
                databaseName: databaseName,
                type: String.self,
                isPrimaryKey: false,
                isForeignKey: false,
                isTimestamp: false,
                isNullable: false
            )
            
        case let column as Column<Int>:
            return FieldInfo(
                name: fieldName,
                databaseName: databaseName,
                type: Int.self,
                isPrimaryKey: false,
                isForeignKey: false,
                isTimestamp: false,
                isNullable: false
            )
            
        case let column as Column<Bool>:
            return FieldInfo(
                name: fieldName,
                databaseName: databaseName,
                type: Bool.self,
                isPrimaryKey: false,
                isForeignKey: false,
                isTimestamp: false,
                isNullable: false
            )
            
        case let column as Column<Double>:
            return FieldInfo(
                name: fieldName,
                databaseName: databaseName,
                type: Double.self,
                isPrimaryKey: false,
                isForeignKey: false,
                isTimestamp: false,
                isNullable: false
            )
            
        case let column as Column<Float>:
            return FieldInfo(
                name: fieldName,
                databaseName: databaseName,
                type: Float.self,
                isPrimaryKey: false,
                isForeignKey: false,
                isTimestamp: false,
                isNullable: false
            )
            
        case let column as Column<Date>:
            return FieldInfo(
                name: fieldName,
                databaseName: databaseName,
                type: Date.self,
                isPrimaryKey: false,
                isForeignKey: false,
                isTimestamp: false,
                isNullable: false
            )
            
        case let timestamp as Timestamp:
            return FieldInfo(
                name: fieldName,
                databaseName: databaseName,
                type: Date.self,
                isPrimaryKey: false,
                isForeignKey: false,
                isTimestamp: true,
                isNullable: false
            )
            
        case let foreignKey as ForeignKey:
            return FieldInfo(
                name: fieldName,
                databaseName: databaseName,
                type: UUID.self,
                isPrimaryKey: false,
                isForeignKey: true,
                isTimestamp: false,
                isNullable: false
            )
            
        default:
            // Handle optional columns
            let valueType = type(of: value)
            if String(describing: valueType).contains("Column<Optional<") {
                // This is a nullable column - extract inner type
                // For now, we'll skip these - proper implementation would use generic introspection
                return nil
            }
            return nil
        }
    }
}

// MARK: - Schema Extension for Metadata Access

extension Schema {
    /// Get metadata for this schema type
    public static var metadata: SchemaMetadata {
        get async {
            await SchemaRegistry.shared.register(self)
        }
    }
}