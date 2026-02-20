import Foundation

// MARK: - Column Wrappers

@propertyWrapper
public struct Column<T: Sendable>: Sendable {
    public var wrappedValue: T
    public init(wrappedValue: T) { self.wrappedValue = wrappedValue }
}

@propertyWrapper
public struct ID: Sendable {
    public var wrappedValue: UUID
    public init(wrappedValue: UUID = UUID()) { self.wrappedValue = wrappedValue }
}

@propertyWrapper
public struct Timestamp: Sendable {
    public var wrappedValue: Date
    public init(wrappedValue: Date = Date()) { self.wrappedValue = wrappedValue }
}

@propertyWrapper
public struct ForeignKey: Sendable {
    public var wrappedValue: UUID
    public init(wrappedValue: UUID = UUID()) { self.wrappedValue = wrappedValue }
}

// MARK: - Relationship Wrappers
//
// lazyRelation is stored as `var` so PreloadQuery can inject loaded data
// by writing to the projected value key path (\.$posts, \.$user, etc.).
// The projectedValue setter is what makes WritableKeyPath work.

@propertyWrapper
public struct HasMany<T: Schema>: Sendable {
    private var lazyRelation: SpectroLazyRelation<[T]>

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
        self.lazyRelation = SpectroLazyRelation<[T]>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .hasMany,
            foreignKey: nil
        ))
    }

    public init(relationshipInfo: RelationshipInfo) {
        self.lazyRelation = SpectroLazyRelation<[T]>(relationshipInfo: relationshipInfo)
    }
}

@propertyWrapper
public struct HasOne<T: Schema>: Sendable {
    private var lazyRelation: SpectroLazyRelation<T?>

    public var wrappedValue: T? {
        get { lazyRelation.value ?? nil }
        set { lazyRelation = lazyRelation.withLoaded(newValue) }
    }

    public var projectedValue: SpectroLazyRelation<T?> {
        get { lazyRelation }
        set { lazyRelation = newValue }
    }

    public init(wrappedValue: T? = nil) {
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .hasOne,
            foreignKey: nil
        ))
    }

    public init(relationshipInfo: RelationshipInfo) {
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: relationshipInfo)
    }
}

@propertyWrapper
public struct BelongsTo<T: Schema>: Sendable {
    private var lazyRelation: SpectroLazyRelation<T?>

    public var wrappedValue: T? {
        get { lazyRelation.value ?? nil }
        set { lazyRelation = lazyRelation.withLoaded(newValue) }
    }

    public var projectedValue: SpectroLazyRelation<T?> {
        get { lazyRelation }
        set { lazyRelation = newValue }
    }

    public init(wrappedValue: T? = nil) {
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .belongsTo,
            foreignKey: nil
        ))
    }

    public init(relationshipInfo: RelationshipInfo) {
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: relationshipInfo)
    }
}
