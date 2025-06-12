# Relationship Loading

Spectro's implicit lazy relationship system provides Ecto-inspired relationship handling with automatic N+1 query prevention.

## Overview

Spectro implements a revolutionary relationship loading system that appears as normal Swift properties while being lazy by default. This approach prevents the N+1 query problem common in ActiveRecord-style ORMs while maintaining clean, intuitive APIs.

### The Problem with Traditional ORMs

Traditional ORMs like ActiveRecord suffer from the N+1 query problem:

```swift
// BAD: This triggers N+1 queries
let users = try await User.all()
for user in users {
    print(user.posts.count) // Each access triggers a separate query!
}
```

### Spectro's Solution: Implicit Lazy Loading

With Spectro, relationships are lazy by default but appear as normal properties:

```swift
// GOOD: Relationships are lazy by default
let users = try await repo.all(User.self)
for user in users {
    // This doesn't trigger queries yet - relationships are lazy
    let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
    print(posts.count) // Only loads when explicitly requested
}

// BETTER: Use preloading for efficient batch loading
let usersWithPosts = try await repo.query(User.self)
    .preload(\.$posts)
    .all()
```

## Relationship Types

### HasMany Relationships

Define one-to-many relationships using the `@HasMany` property wrapper:

```swift
public struct User: Schema {
    @ID public var id: UUID
    @Column public var name: String = ""
    
    // Implicit lazy relationship - appears as [Post] but is lazy underneath
    @HasMany public var posts: [Post]
    
    public init() {}
}
```

Loading HasMany relationships:

```swift
let user = try await repo.get(User.self, id: userId)
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
```

### HasOne Relationships

Define one-to-one relationships using the `@HasOne` property wrapper:

```swift
public struct User: Schema {
    @ID public var id: UUID
    @Column public var name: String = ""
    
    // Implicit lazy relationship - appears as Profile? but is lazy underneath
    @HasOne public var profile: Profile?
    
    public init() {}
}
```

Loading HasOne relationships:

```swift
let user = try await repo.get(User.self, id: userId)
let profile = try await user.loadHasOne(Profile.self, foreignKey: "userId", using: repo)
```

### BelongsTo Relationships

Define inverse relationships using foreign keys:

```swift
public struct Post: Schema {
    @ID public var id: UUID
    @Column public var title: String = ""
    @ForeignKey public var userId: UUID = UUID()
    
    // Implicit lazy relationship - appears as User? but is lazy underneath
    @BelongsTo public var user: User?
    
    public init() {}
}
```

Loading BelongsTo relationships:

```swift
let post = try await repo.get(Post.self, id: postId)
let user = try await post.loadBelongsTo(User.self, foreignKey: "userId", using: repo)
```

## Advanced Features

### Preloading for Performance

Use the query builder's `preload` method to efficiently load relationships:

```swift
// Load users with their posts in a single optimized query
let usersWithPosts = try await repo.query(User.self)
    .where { $0.isActive == true }
    .preload(\.$posts)
    .all()

// Chain multiple preloads
let usersWithData = try await repo.query(User.self)
    .preload(\.$posts)
    .preload(\.$profile)
    .all()
```

### Lazy Relation API

Access the underlying lazy relation for advanced control:

```swift
public struct User: Schema {
    @HasMany public var posts: [Post]
    
    // Access the projected value for lazy relation features
    public var $posts: SpectroLazyRelation<[Post]> {
        _posts.projectedValue
    }
}

// Check loading state
switch user.$posts.loadState {
case .notLoaded:
    print("Posts not loaded yet")
case .loading:
    print("Posts currently loading")
case .loaded(let posts):
    print("Loaded \(posts.count) posts")
case .error(let error):
    print("Failed to load posts: \(error)")
}
```

### Batch Loading

The relationship loader supports efficient batch loading to prevent N+1 queries:

```swift
// This will be optimized into batch queries automatically
let users = try await repo.all(User.self)
let allPosts = try await RelationshipLoader.batchLoad(
    parents: users,
    relationship: "posts",
    childType: Post.self,
    foreignKey: "userId",
    using: repo
)
```

## Implementation Details

### SpectroLazyRelation

The core lazy relation type that wraps all relationships:

```swift
public struct SpectroLazyRelation<T: Sendable>: Sendable {
    public enum LoadState: Sendable {
        case notLoaded
        case loading
        case loaded(T)
        case error(Error)
    }
    
    public var loadState: LoadState { get }
    public var value: T? { get }
    public var isLoaded: Bool { get }
}
```

### Property Wrapper Magic

Property wrappers provide the clean API while hiding lazy loading complexity:

```swift
@propertyWrapper
public struct HasMany<T: Schema>: Sendable {
    private let lazyRelation: SpectroLazyRelation<[T]>
    
    public var wrappedValue: [T] {
        get { lazyRelation.value ?? [] }
    }
    
    public var projectedValue: SpectroLazyRelation<[T]> {
        lazyRelation
    }
}
```

### Relationship Loader

The relationship loader handles the actual database queries:

```swift
public struct RelationshipLoader {
    public static func loadHasMany<Parent: Schema, Child: Schema>(
        for parent: Parent,
        relationship: String,
        childType: Child.Type,
        foreignKey: String,
        using repo: GenericDatabaseRepo
    ) async throws -> [Child]
}
```

## Best Practices

### 1. Always Use Explicit Loading

Don't rely on automatic loading - be explicit about when you need relationships:

```swift
// GOOD: Explicit loading
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)

// BETTER: Use preloading for multiple records
let users = try await repo.query(User.self).preload(\.$posts).all()
```

### 2. Preload for Lists

When displaying lists of data, always preload relationships:

```swift
// Load users with their posts and profiles for a user list
let users = try await repo.query(User.self)
    .where { $0.isActive == true }
    .preload(\.$posts)
    .preload(\.$profile)
    .orderBy(\.$createdAt, .desc)
    .limit(20)
    .all()
```

### 3. Handle Loading States

Always handle the different loading states appropriately:

```swift
switch user.$posts.loadState {
case .notLoaded:
    // Show loading indicator or load button
    break
case .loading:
    // Show spinner
    break
case .loaded(let posts):
    // Display posts
    break
case .error(let error):
    // Show error message
    break
}
```

### 4. Use Type-Safe Foreign Keys

Always define foreign key relationships explicitly:

```swift
public struct Post: Schema {
    @ID public var id: UUID
    @ForeignKey public var userId: UUID = UUID() // Explicit foreign key
    @BelongsTo public var user: User?
}
```

## Performance Considerations

### Query Optimization

Spectro automatically optimizes relationship queries:

- **Batch Loading**: Multiple relationship loads are batched into single queries
- **Lazy Loading**: Relationships are only loaded when explicitly requested
- **Preloading**: Eager loading uses efficient JOIN or IN queries
- **Caching**: Loaded relationships are cached within the instance

### Memory Management

Lazy relationships help with memory management:

- **On-Demand Loading**: Only load data when needed
- **Weak References**: Avoid retain cycles in bidirectional relationships
- **Sendable Compliance**: Safe for concurrent access across actors

## Error Handling

Relationship loading can fail for various reasons:

```swift
do {
    let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
} catch SpectroError.invalidSchema(let reason) {
    // Schema definition issue
} catch SpectroError.queryExecutionFailed(let sql, let error) {
    // Database query failed
} catch {
    // Other errors
}
```

Common errors:

- **Invalid Foreign Key**: The foreign key field doesn't exist
- **Type Mismatch**: The relationship type doesn't match the foreign key type
- **Database Error**: Connection issues or SQL errors
- **Not Found**: The parent record doesn't exist