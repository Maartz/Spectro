import Foundation
import PostgresKit

// MARK: - Column Wrappers

@propertyWrapper
public struct Column<T: Sendable>: Sendable {
    public var wrappedValue: T
    public let columnName: String?

    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
        self.columnName = nil
    }

    public init(wrappedValue: T, _ columnName: String) {
        self.wrappedValue = wrappedValue
        self.columnName = columnName
    }
}

@propertyWrapper
public struct ID<T: PrimaryKeyType>: Sendable, PrimaryKeyWrapperProtocol {
    public var wrappedValue: T

    public init(wrappedValue: T = T.defaultValue) { self.wrappedValue = wrappedValue }

    // MARK: - PrimaryKeyWrapperProtocol
    public var primaryKeyPostgresData: PostgresData { wrappedValue.toPostgresData() }
    public var primaryKeyFieldType: FieldType { T.fieldType }
    public var primaryKeyHashable: AnyHashable { AnyHashable(wrappedValue) }
}

@propertyWrapper
public struct Timestamp: Sendable {
    public var wrappedValue: Date
    public init(wrappedValue: Date = Date()) { self.wrappedValue = wrappedValue }
}

@propertyWrapper
public struct ForeignKey<T: PrimaryKeyType>: Sendable, ForeignKeyWrapperProtocol {
    public var wrappedValue: T
    public let columnName: String?

    public init(wrappedValue: T = T.defaultValue) {
        self.wrappedValue = wrappedValue
        self.columnName = nil
    }

    public init(wrappedValue: T = T.defaultValue, _ columnName: String) {
        self.wrappedValue = wrappedValue
        self.columnName = columnName
    }

    // MARK: - ForeignKeyWrapperProtocol
    public var foreignKeyPostgresData: PostgresData { wrappedValue.toPostgresData() }
    public var foreignKeyFieldType: FieldType { T.fieldType }
    public var foreignKeyHashable: AnyHashable { AnyHashable(wrappedValue) }
    public var foreignKeyColumnName: String? { columnName }
}

// MARK: - Relationship Wrappers
//
// lazyRelation is stored as `var` so PreloadQuery can inject loaded data
// by writing to the projected value key path (\.$posts, \.$user, etc.).
// The projectedValue setter is what makes WritableKeyPath work.

@propertyWrapper
public struct HasMany<T: Schema>: Sendable {
    private var lazyRelation: SpectroLazyRelation<[T]>
    public let foreignKey: String?

    /// The loaded array, or empty if the relationship has not been loaded.
    public var wrappedValue: [T] {
        get { lazyRelation.value ?? [] }
        set { lazyRelation = lazyRelation.withLoaded(newValue) }
    }

    /// Access lazy-loading state and inject preloaded data.
    ///
    /// Setting this projected value is how `PreloadQuery` injects batch-loaded
    /// results: `entity[keyPath: \.$posts] = SpectroLazyRelation(loaded: posts, ...)`
    public var projectedValue: SpectroLazyRelation<[T]> {
        get { lazyRelation }
        set { lazyRelation = newValue }
    }

    public init(wrappedValue: [T] = []) {
        self.foreignKey = nil
        self.lazyRelation = SpectroLazyRelation<[T]>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .hasMany,
            foreignKey: nil
        ))
    }

    public init(wrappedValue: [T] = [], foreignKey: String) {
        self.foreignKey = foreignKey
        self.lazyRelation = SpectroLazyRelation<[T]>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .hasMany,
            foreignKey: foreignKey
        ))
    }

    public init(relationshipInfo: RelationshipInfo) {
        self.foreignKey = relationshipInfo.foreignKey
        self.lazyRelation = SpectroLazyRelation<[T]>(relationshipInfo: relationshipInfo)
    }
}

@propertyWrapper
public struct HasOne<T: Schema>: Sendable {
    private var lazyRelation: SpectroLazyRelation<T?>
    public let foreignKey: String?

    public var wrappedValue: T? {
        get { lazyRelation.value ?? nil }
        set { lazyRelation = lazyRelation.withLoaded(newValue) }
    }

    public var projectedValue: SpectroLazyRelation<T?> {
        get { lazyRelation }
        set { lazyRelation = newValue }
    }

    public init(wrappedValue: T? = nil) {
        self.foreignKey = nil
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .hasOne,
            foreignKey: nil
        ))
    }

    public init(wrappedValue: T? = nil, foreignKey: String) {
        self.foreignKey = foreignKey
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .hasOne,
            foreignKey: foreignKey
        ))
    }

    public init(relationshipInfo: RelationshipInfo) {
        self.foreignKey = relationshipInfo.foreignKey
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: relationshipInfo)
    }
}

@propertyWrapper
public struct BelongsTo<T: Schema>: Sendable {
    private var lazyRelation: SpectroLazyRelation<T?>
    public let foreignKey: String?

    public var wrappedValue: T? {
        get { lazyRelation.value ?? nil }
        set { lazyRelation = lazyRelation.withLoaded(newValue) }
    }

    public var projectedValue: SpectroLazyRelation<T?> {
        get { lazyRelation }
        set { lazyRelation = newValue }
    }

    public init(wrappedValue: T? = nil) {
        self.foreignKey = nil
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .belongsTo,
            foreignKey: nil
        ))
    }

    public init(wrappedValue: T? = nil, foreignKey: String) {
        self.foreignKey = foreignKey
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .belongsTo,
            foreignKey: foreignKey
        ))
    }

    public init(relationshipInfo: RelationshipInfo) {
        self.foreignKey = relationshipInfo.foreignKey
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: relationshipInfo)
    }
}

@propertyWrapper
public struct ManyToMany<T: Schema>: Sendable {
    private var lazyRelation: SpectroLazyRelation<[T]>

    /// The loaded array, or empty if the relationship has not been loaded.
    public var wrappedValue: [T] {
        get { lazyRelation.value ?? [] }
        set { lazyRelation = lazyRelation.withLoaded(newValue) }
    }

    /// Access lazy-loading state and inject preloaded data.
    public var projectedValue: SpectroLazyRelation<[T]> {
        get { lazyRelation }
        set { lazyRelation = newValue }
    }

    /// Create a many-to-many relationship.
    ///
    /// - Parameters:
    ///   - junctionTable: The name of the junction/pivot table (e.g. "user_tags").
    ///   - parentFK: The column in the junction table that references the parent's PK.
    ///               If nil, derived by convention from the parent type at preload time.
    ///   - relatedFK: The column in the junction table that references the related type's PK.
    ///                If nil, derived by convention from the related type at preload time.
    public init(junctionTable: String, parentFK: String? = nil, relatedFK: String? = nil) {
        let relatedTypeName = String(describing: T.self)
        self.lazyRelation = SpectroLazyRelation<[T]>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: relatedTypeName,
            kind: .manyToMany,
            foreignKey: nil,
            junctionTable: junctionTable,
            parentForeignKey: parentFK ?? "",
            relatedForeignKey: relatedFK ?? ""
        ))
    }

    public init(wrappedValue: [T] = []) {
        self.lazyRelation = SpectroLazyRelation<[T]>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .manyToMany,
            foreignKey: nil
        ))
    }

    public init(relationshipInfo: RelationshipInfo) {
        self.lazyRelation = SpectroLazyRelation<[T]>(relationshipInfo: relationshipInfo)
    }
}
