import Foundation

// MARK: - Core Property Wrappers

/// Property wrapper for database columns.
///
/// Use `@Column` to mark a property as a database column. The property name
/// will be converted to snake_case for the database column name.
///
/// ## Usage
///
/// ```swift
/// struct User: Schema {
///     @Column var name: String = ""
///     @Column var email: String = ""
///     @Column var age: Int = 0
///     @Column var isActive: Bool = true
/// }
/// ```
///
/// ## Supported Types
///
/// - `String`
/// - `Int`
/// - `Bool`
/// - `Double`
/// - `Float`
/// - `Date`
@propertyWrapper
public struct Column<T>: Sendable where T: Sendable {
    public var wrappedValue: T
    
    /// Initialize with a default value.
    ///
    /// - Parameter wrappedValue: Default value for the column
    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for UUID primary key fields.
///
/// Use `@ID` to mark a property as the primary key. The property must be of type `UUID`.
/// A new UUID will be generated automatically when the instance is created.
///
/// ## Usage
///
/// ```swift
/// struct User: Schema {
///     @ID var id: UUID  // Auto-generated UUID
///     // ...
/// }
/// ```
@propertyWrapper
public struct ID: Sendable {
    public var wrappedValue: UUID
    
    /// Initialize with an auto-generated UUID.
    ///
    /// - Parameter wrappedValue: UUID value (defaults to new UUID)
    public init(wrappedValue: UUID = UUID()) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for timestamp fields.
///
/// Use `@Timestamp` for fields that track creation time, update time, etc.
/// Automatically set to the current date when the instance is created.
///
/// ## Usage
///
/// ```swift
/// struct User: Schema {
///     @Timestamp var createdAt: Date = Date()
///     @Timestamp var updatedAt: Date = Date()
/// }
/// ```
@propertyWrapper
public struct Timestamp: Sendable {
    public var wrappedValue: Date
    
    /// Initialize with current date.
    ///
    /// - Parameter wrappedValue: Date value (defaults to current date)
    public init(wrappedValue: Date = Date()) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for foreign key fields.
///
/// Use `@ForeignKey` to mark a property as a foreign key reference to another table.
/// The property must be of type `UUID`.
///
/// ## Usage
///
/// ```swift
/// struct Post: Schema {
///     @ID var id: UUID
///     @ForeignKey var userId: UUID = UUID()  // References users.id
/// }
/// ```
@propertyWrapper
public struct ForeignKey: Sendable {
    public var wrappedValue: UUID
    
    /// Initialize with a UUID value.
    ///
    /// - Parameter wrappedValue: UUID value for the foreign key
    public init(wrappedValue: UUID = UUID()) {
        self.wrappedValue = wrappedValue
    }
}

// MARK: - Relationship Property Wrappers

/// Property wrapper for has-many relationships with lazy loading.
///
/// `@HasMany` defines a one-to-many relationship where the current schema has many instances
/// of the related schema. The relationship is lazy by default to prevent N+1 query issues.
///
/// ## Usage
///
/// ```swift
/// struct User: Schema {
///     @ID var id: UUID
///     @HasMany var posts: [Post]  // User has many posts
/// }
/// ```
///
/// ## Loading Relationships
///
/// Relationships must be explicitly loaded:
///
/// ```swift
/// let user = try await repo.get(User.self, id: userId)
/// let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
/// ```
///
/// Or preloaded for efficiency:
///
/// ```swift
/// let users = try await repo.query(User.self)
///     .preload(\.$posts)
///     .all()
/// ```
///
/// ## Accessing Lazy State
///
/// Use the projected value (`$`) to access lazy loading features:
///
/// ```swift
/// if user.$posts.isLoaded {
///     let posts = user.$posts.value ?? []
/// }
/// ```
@propertyWrapper
public struct HasMany<T: Schema>: Sendable {
    private let lazyRelation: SpectroLazyRelation<[T]>
    
    /// Returns the loaded relationship data or empty array if not loaded.
    public var wrappedValue: [T] {
        get {
            lazyRelation.value ?? []
        }
        set {
            // Relationships are primarily read-only
        }
    }
    
    /// Provides access to lazy loading features.
    public var projectedValue: SpectroLazyRelation<[T]> {
        lazyRelation
    }
    
    /// Initialize with default empty array.
    ///
    /// The relationship starts in an unloaded state.
    ///
    /// - Parameter wrappedValue: Default value (ignored for lazy relationships)
    public init(wrappedValue: [T] = []) {
        self.lazyRelation = SpectroLazyRelation<[T]>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .hasMany,
            foreignKey: ""
        ))
    }
    
    /// Internal initializer for framework use.
    ///
    /// - Parameter relationshipInfo: Relationship metadata
    public init(relationshipInfo: RelationshipInfo) {
        self.lazyRelation = SpectroLazyRelation<[T]>(relationshipInfo: relationshipInfo)
    }
}

/// Property wrapper for has-one relationships with lazy loading.
///
/// `@HasOne` defines a one-to-one relationship where the current schema has one instance
/// of the related schema. The relationship is lazy by default to prevent N+1 query issues.
///
/// ## Usage
///
/// ```swift
/// struct User: Schema {
///     @ID var id: UUID
///     @HasOne var profile: Profile?  // User has one profile
/// }
/// ```
///
/// ## Loading Relationships
///
/// ```swift
/// let user = try await repo.get(User.self, id: userId)
/// let profile = try await user.loadHasOne(Profile.self, foreignKey: "userId", using: repo)
/// ```
///
/// ## Accessing Lazy State
///
/// ```swift
/// if user.$profile.isLoaded {
///     let profile = user.$profile.value
/// }
/// ```
@propertyWrapper
public struct HasOne<T: Schema>: Sendable {
    private let lazyRelation: SpectroLazyRelation<T?>
    
    /// Returns the loaded relationship data or nil if not loaded.
    public var wrappedValue: T? {
        get {
            lazyRelation.value ?? nil
        }
        set {
            // Relationships are primarily read-only
        }
    }
    
    /// Provides access to lazy loading features.
    public var projectedValue: SpectroLazyRelation<T?> {
        lazyRelation
    }
    
    /// Initialize with default nil value.
    ///
    /// The relationship starts in an unloaded state.
    ///
    /// - Parameter wrappedValue: Default value (ignored for lazy relationships)
    public init(wrappedValue: T? = nil) {
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .hasOne,
            foreignKey: ""
        ))
    }
    
    /// Internal initializer for framework use.
    ///
    /// - Parameter relationshipInfo: Relationship metadata
    public init(relationshipInfo: RelationshipInfo) {
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: relationshipInfo)
    }
}

/// Property wrapper for belongs-to relationships with lazy loading.
///
/// `@BelongsTo` defines an inverse relationship where the current schema belongs to
/// an instance of the related schema via a foreign key. The relationship is lazy by default.
///
/// ## Usage
///
/// ```swift
/// struct Post: Schema {
///     @ID var id: UUID
///     @ForeignKey var userId: UUID = UUID()
///     @BelongsTo var user: User?  // Post belongs to a user
/// }
/// ```
///
/// ## Loading Relationships
///
/// ```swift
/// let post = try await repo.get(Post.self, id: postId)
/// let user = try await post.loadBelongsTo(User.self, foreignKey: "userId", using: repo)
/// ```
///
/// ## Accessing Lazy State
///
/// ```swift
/// if post.$user.isLoaded {
///     let user = post.$user.value
/// }
/// ```
@propertyWrapper
public struct BelongsTo<T: Schema>: Sendable {
    private let lazyRelation: SpectroLazyRelation<T?>
    
    /// Returns the loaded relationship data or nil if not loaded.
    public var wrappedValue: T? {
        get {
            lazyRelation.value ?? nil
        }
        set {
            // Relationships are primarily read-only
        }
    }
    
    /// Provides access to lazy loading features.
    public var projectedValue: SpectroLazyRelation<T?> {
        lazyRelation
    }
    
    /// Initialize with default nil value.
    ///
    /// The relationship starts in an unloaded state.
    ///
    /// - Parameter wrappedValue: Default value (ignored for lazy relationships)
    public init(wrappedValue: T? = nil) {
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .belongsTo,
            foreignKey: ""
        ))
    }
    
    /// Internal initializer for framework use.
    ///
    /// - Parameter relationshipInfo: Relationship metadata
    public init(relationshipInfo: RelationshipInfo) {
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: relationshipInfo)
    }
}