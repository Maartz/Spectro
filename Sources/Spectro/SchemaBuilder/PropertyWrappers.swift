import Foundation

/// Property wrapper for database columns
@propertyWrapper
public struct Column<T>: Sendable where T: Sendable {
    public var wrappedValue: T
    
    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for ID fields (UUID primary key)
@propertyWrapper
public struct ID: Sendable {
    public var wrappedValue: UUID
    
    public init(wrappedValue: UUID = UUID()) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for timestamp fields
@propertyWrapper
public struct Timestamp: Sendable {
    public var wrappedValue: Date
    
    public init(wrappedValue: Date = Date()) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for foreign key relationships
@propertyWrapper
public struct ForeignKey: Sendable {
    public var wrappedValue: UUID
    
    public init(wrappedValue: UUID = UUID()) {
        self.wrappedValue = wrappedValue
    }
}

/// Property wrapper for has-many relationships with implicit lazy loading.
///
/// `@HasMany` defines a one-to-many relationship where the current schema has many instances
/// of the related schema. The relationship appears as a regular array but is lazy by default
/// to prevent N+1 query issues.
///
/// ## Usage
///
/// ```swift
/// public struct User: Schema {
///     @ID public var id: UUID
///     @Column public var name: String = ""
///     
///     // User has many posts
///     @HasMany public var posts: [Post]
///     
///     public init() {}
/// }
/// ```
///
/// ## Loading the Relationship
///
/// The relationship must be explicitly loaded:
///
/// ```swift
/// let user = try await repo.get(User.self, id: userId)
/// let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
/// ```
///
/// Or preloaded for better performance:
///
/// ```swift
/// let users = try await repo.query(User.self)
///     .preload(\.$posts)
///     .all()
/// ```
///
/// ## Accessing Lazy Features
///
/// Use the projected value to access lazy loading features:
///
/// ```swift
/// // Check if loaded
/// if user.$posts.isLoaded {
///     let posts = user.$posts.value ?? []
/// }
///
/// // Check loading state
/// switch user.$posts.loadState {
/// case .loaded(let posts):
///     print("Loaded \(posts.count) posts")
/// default:
///     print("Posts not loaded")
/// }
/// ```
@propertyWrapper
public struct HasMany<T: Schema>: Sendable {
    private let lazyRelation: SpectroLazyRelation<[T]>
    
    /// Public interface looks like a regular array
    public var wrappedValue: [T] {
        get {
            // Return loaded data or empty array if not loaded
            lazyRelation.value ?? []
        }
        set {
            // This would update the lazy relation with new data
            // For now, we'll ignore writes since this is primarily read-only
        }
    }
    
    /// Projected value provides access to lazy loading features
    public var projectedValue: SpectroLazyRelation<[T]> {
        lazyRelation
    }
    
    public init(wrappedValue: [T] = []) {
        self.lazyRelation = SpectroLazyRelation(loaded: wrappedValue, relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .hasMany,
            foreignKey: ""
        ))
    }
    
    /// Internal initializer for framework use
    public init(relationshipInfo: RelationshipInfo) {
        self.lazyRelation = SpectroLazyRelation<[T]>(relationshipInfo: relationshipInfo)
    }
}

/// Property wrapper for has-one relationships with implicit lazy loading.
///
/// `@HasOne` defines a one-to-one relationship where the current schema has one instance
/// of the related schema. The relationship appears as an optional value but is lazy by default
/// to prevent N+1 query issues.
///
/// ## Usage
///
/// ```swift
/// public struct User: Schema {
///     @ID public var id: UUID
///     @Column public var name: String = ""
///     
///     // User has one profile
///     @HasOne public var profile: Profile?
///     
///     public init() {}
/// }
/// ```
///
/// ## Loading the Relationship
///
/// The relationship must be explicitly loaded:
///
/// ```swift
/// let user = try await repo.get(User.self, id: userId)
/// let profile = try await user.loadHasOne(Profile.self, foreignKey: "userId", using: repo)
/// ```
///
/// Or preloaded for better performance:
///
/// ```swift
/// let users = try await repo.query(User.self)
///     .preload(\.$profile)
///     .all()
/// ```
///
/// ## Accessing Lazy Features
///
/// Use the projected value to access lazy loading features:
///
/// ```swift
/// // Check if loaded
/// if user.$profile.isLoaded {
///     let profile = user.$profile.value ?? nil
/// }
///
/// // Check loading state
/// switch user.$profile.loadState {
/// case .loaded(let profile):
///     if let profile = profile {
///         print("Profile loaded: \(profile.language)")
///     } else {
///         print("No profile found")
///     }
/// default:
///     print("Profile not loaded")
/// }
/// ```
@propertyWrapper
public struct HasOne<T: Schema>: Sendable {
    private let lazyRelation: SpectroLazyRelation<T?>
    
    /// Public interface looks like an optional value
    public var wrappedValue: T? {
        get {
            // Return loaded data or nil if not loaded
            lazyRelation.value ?? nil
        }
        set {
            // This would update the lazy relation with new data
            // For now, we'll ignore writes since this is primarily read-only
        }
    }
    
    /// Projected value provides access to lazy loading features
    public var projectedValue: SpectroLazyRelation<T?> {
        lazyRelation
    }
    
    public init(wrappedValue: T? = nil) {
        self.lazyRelation = SpectroLazyRelation(loaded: wrappedValue, relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .hasOne,
            foreignKey: ""
        ))
    }
    
    /// Internal initializer for framework use
    public init(relationshipInfo: RelationshipInfo) {
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: relationshipInfo)
    }
}

/// Property wrapper for belongs-to relationships with implicit lazy loading.
///
/// `@BelongsTo` defines an inverse relationship where the current schema belongs to
/// an instance of the related schema via a foreign key. The relationship appears as
/// an optional value but is lazy by default to prevent N+1 query issues.
///
/// ## Usage
///
/// ```swift
/// public struct Post: Schema {
///     @ID public var id: UUID
///     @Column public var title: String = ""
///     @ForeignKey public var userId: UUID = UUID()
///     
///     // Post belongs to a user
///     @BelongsTo public var user: User?
///     
///     public init() {}
/// }
/// ```
///
/// ## Loading the Relationship
///
/// The relationship must be explicitly loaded:
///
/// ```swift
/// let post = try await repo.get(Post.self, id: postId)
/// let user = try await post.loadBelongsTo(User.self, foreignKey: "userId", using: repo)
/// ```
///
/// Or preloaded for better performance:
///
/// ```swift
/// let posts = try await repo.query(Post.self)
///     .preload(\.$user)
///     .all()
/// ```
///
/// ## Accessing Lazy Features
///
/// Use the projected value to access lazy loading features:
///
/// ```swift
/// // Check if loaded
/// if post.$user.isLoaded {
///     let user = post.$user.value ?? nil
/// }
///
/// // Check loading state
/// switch post.$user.loadState {
/// case .loaded(let user):
///     if let user = user {
///         print("Author: \(user.name)")
///     } else {
///         print("No user found")
///     }
/// default:
///     print("User not loaded")
/// }
/// ```
@propertyWrapper
public struct BelongsTo<T: Schema>: Sendable {
    private let lazyRelation: SpectroLazyRelation<T?>
    
    /// Public interface looks like an optional value
    public var wrappedValue: T? {
        get {
            // Return loaded data or nil if not loaded
            lazyRelation.value ?? nil
        }
        set {
            // This would update the lazy relation with new data
            // For now, we'll ignore writes since this is primarily read-only
        }
    }
    
    /// Projected value provides access to lazy loading features
    public var projectedValue: SpectroLazyRelation<T?> {
        lazyRelation
    }
    
    public init(wrappedValue: T? = nil) {
        self.lazyRelation = SpectroLazyRelation(loaded: wrappedValue, relationshipInfo: RelationshipInfo(
            name: "",
            relatedTypeName: String(describing: T.self),
            kind: .belongsTo,
            foreignKey: ""
        ))
    }
    
    /// Internal initializer for framework use
    public init(relationshipInfo: RelationshipInfo) {
        self.lazyRelation = SpectroLazyRelation<T?>(relationshipInfo: relationshipInfo)
    }
}