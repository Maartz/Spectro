# API Reference

Complete reference for Spectro's relationship loading and query APIs.

## Overview

This document provides a comprehensive reference for all relationship loading features, property wrappers, and query methods in Spectro.

## Relationship Property Wrappers

### @HasMany

Defines a one-to-many relationship.

```swift
@propertyWrapper
public struct HasMany<T: Schema>: Sendable

@HasMany public var posts: [Post]
```

**Methods:**
- `wrappedValue: [T]` - Access the relationship as a regular array
- `projectedValue: SpectroLazyRelation<[T]>` - Access lazy loading features

**Usage:**
```swift
public struct User: Schema {
    @HasMany public var posts: [Post]
}

// Loading
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)

// Preloading
let users = try await repo.query(User.self).preload(\.$posts).all()

// State checking
if user.$posts.isLoaded {
    let posts = user.$posts.value ?? []
}
```

### @HasOne

Defines a one-to-one relationship.

```swift
@propertyWrapper
public struct HasOne<T: Schema>: Sendable

@HasOne public var profile: Profile?
```

**Methods:**
- `wrappedValue: T?` - Access the relationship as an optional value
- `projectedValue: SpectroLazyRelation<T?>` - Access lazy loading features

**Usage:**
```swift
public struct User: Schema {
    @HasOne public var profile: Profile?
}

// Loading
let profile = try await user.loadHasOne(Profile.self, foreignKey: "userId", using: repo)

// Preloading
let users = try await repo.query(User.self).preload(\.$profile).all()
```

### @BelongsTo

Defines an inverse/belongs-to relationship.

```swift
@propertyWrapper
public struct BelongsTo<T: Schema>: Sendable

@BelongsTo public var user: User?
```

**Methods:**
- `wrappedValue: T?` - Access the relationship as an optional value
- `projectedValue: SpectroLazyRelation<T?>` - Access lazy loading features

**Usage:**
```swift
public struct Post: Schema {
    @ForeignKey public var userId: UUID
    @BelongsTo public var user: User?
}

// Loading
let user = try await post.loadBelongsTo(User.self, foreignKey: "userId", using: repo)

// Preloading
let posts = try await repo.query(Post.self).preload(\.$user).all()
```

## SpectroLazyRelation

Core type that wraps all relationships with lazy loading capability.

```swift
public struct SpectroLazyRelation<T: Sendable>: Sendable
```

### Properties

- `loadState: LoadState` - Current loading state
- `value: T?` - The loaded value (nil if not loaded)
- `isLoaded: Bool` - Whether the relationship is loaded

### LoadState Enum

```swift
public enum LoadState: Sendable {
    case notLoaded              // Not loaded yet
    case loading                // Currently loading
    case loaded(T)              // Successfully loaded
    case error(Error)           // Failed to load
}
```

### Usage

```swift
let user = try await repo.get(User.self, id: userId)

// Check loading state
switch user.$posts.loadState {
case .notLoaded:
    // Load the relationship
    let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
case .loaded(let posts):
    // Use already loaded data
    print("User has \(posts.count) posts")
case .loading:
    // Show loading indicator
    break
case .error(let error):
    // Handle error
    print("Failed to load: \(error)")
}

// Quick loaded check
if user.$posts.isLoaded {
    let posts = user.$posts.value ?? []
    print("Posts: \(posts.count)")
}
```

## Schema Extensions for Relationships

Extensions on the Schema protocol provide relationship loading methods.

### loadHasMany

Load a has-many relationship for a schema instance.

```swift
public func loadHasMany<T: Schema>(
    _ relationshipType: T.Type,
    foreignKey: String,
    using repo: GenericDatabaseRepo
) async throws -> [T]
```

**Parameters:**
- `relationshipType`: The type of the related schema
- `foreignKey`: The foreign key field name (in snake_case or camelCase)
- `repo`: The repository to use for loading

**Returns:** Array of related instances

**Example:**
```swift
let user = try await repo.get(User.self, id: userId)
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
```

### loadHasOne

Load a has-one relationship for a schema instance.

```swift
public func loadHasOne<T: Schema>(
    _ relationshipType: T.Type,
    foreignKey: String,
    using repo: GenericDatabaseRepo
) async throws -> T?
```

**Parameters:**
- `relationshipType`: The type of the related schema
- `foreignKey`: The foreign key field name
- `repo`: The repository to use for loading

**Returns:** Optional related instance

**Example:**
```swift
let user = try await repo.get(User.self, id: userId)
let profile = try await user.loadHasOne(Profile.self, foreignKey: "userId", using: repo)
```

### loadBelongsTo

Load a belongs-to relationship for a schema instance.

```swift
public func loadBelongsTo<T: Schema>(
    _ relationshipType: T.Type,
    foreignKey: String,
    using repo: GenericDatabaseRepo
) async throws -> T?
```

**Parameters:**
- `relationshipType`: The type of the parent schema
- `foreignKey`: The foreign key field name on the current schema
- `repo`: The repository to use for loading

**Returns:** Optional parent instance

**Example:**
```swift
let post = try await repo.get(Post.self, id: postId)
let user = try await post.loadBelongsTo(User.self, foreignKey: "userId", using: repo)
```

## Query Preloading

Methods on the Query class for eager loading relationships.

### preload (HasMany)

Preload a has-many relationship to avoid N+1 queries.

```swift
public func preload<Related>(
    _ relationshipKeyPath: KeyPath<T, SpectroLazyRelation<[Related]>>
) -> PreloadQuery<T>
```

**Parameters:**
- `relationshipKeyPath`: KeyPath to the has-many relationship property

**Returns:** PreloadQuery that can be further modified

**Example:**
```swift
let users = try await repo.query(User.self)
    .where { $0.isActive == true }
    .preload(\.$posts)
    .all()
```

### preload (HasOne/BelongsTo)

Preload a has-one or belongs-to relationship.

```swift
public func preload<Related>(
    _ relationshipKeyPath: KeyPath<T, SpectroLazyRelation<Related?>>
) -> PreloadQuery<T>
```

**Parameters:**
- `relationshipKeyPath`: KeyPath to the has-one or belongs-to relationship property

**Returns:** PreloadQuery that can be further modified

**Example:**
```swift
let posts = try await repo.query(Post.self)
    .where { $0.published == true }
    .preload(\.$user)
    .all()
```

## PreloadQuery

A query type that supports relationship preloading.

```swift
public struct PreloadQuery<T: Schema>: Sendable
```

### Methods

All standard Query methods are available, plus:

- `preload()` - Chain additional preloads
- `all()` - Execute and return results with preloaded relationships
- `first()` - Get first result with preloaded relationships
- `where()` - Add where conditions
- `orderBy()` - Add ordering
- `limit()` - Limit results
- `offset()` - Skip results

### Chaining Preloads

```swift
let users = try await repo.query(User.self)
    .preload(\.$posts)
    .preload(\.$profile)
    .preload(\.$comments)
    .where { $0.isActive == true }
    .orderBy { $0.createdAt }
    .limit(10)
    .all()
```

## RelationshipLoader

Static methods for loading relationships.

```swift
public struct RelationshipLoader
```

### loadHasMany

```swift
public static func loadHasMany<Parent: Schema, Child: Schema>(
    for parent: Parent,
    relationship: String,
    childType: Child.Type,
    foreignKey: String,
    using repo: GenericDatabaseRepo
) async throws -> [Child]
```

### loadHasOne

```swift
public static func loadHasOne<Parent: Schema, Child: Schema>(
    for parent: Parent,
    relationship: String,
    childType: Child.Type,
    foreignKey: String,
    using repo: GenericDatabaseRepo
) async throws -> Child?
```

### loadBelongsTo

```swift
public static func loadBelongsTo<Child: Schema, Parent: Schema>(
    for child: Child,
    relationship: String,
    parentType: Parent.Type,
    foreignKey: String,
    using repo: GenericDatabaseRepo
) async throws -> Parent?
```

### batchLoad (Future)

Efficiently load relationships for multiple parents.

```swift
public static func batchLoad<Parent: Schema, Child: Schema>(
    parents: [Parent],
    relationship: String,
    childType: Child.Type,
    foreignKey: String,
    using repo: GenericDatabaseRepo
) async throws -> [UUID: [Child]]
```

## Error Types

Relationship loading can throw various SpectroError cases:

### Common Errors

```swift
public enum SpectroError: Error, Sendable {
    case notFound(schema: String, id: UUID)
    case queryExecutionFailed(sql: String, error: Error)
    case invalidSchema(reason: String)
    case missingRequiredField(String)
    case resultDecodingFailed(column: String, expectedType: String)
}
```

### Error Handling Example

```swift
do {
    let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
    print("Loaded \(posts.count) posts")
} catch SpectroError.invalidSchema(let reason) {
    print("Schema error: \(reason)")
} catch SpectroError.queryExecutionFailed(let sql, let error) {
    print("Query failed: \(sql)")
    print("Database error: \(error)")
} catch SpectroError.missingRequiredField(let field) {
    print("Missing field: \(field)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Configuration and Setup

### RelationshipInfo

Metadata about relationships used internally.

```swift
public struct RelationshipInfo: Sendable {
    public let name: String
    public let relatedTypeName: String
    public let kind: RelationshipKind
    public let foreignKey: String
}

public enum RelationshipKind: Sendable {
    case hasMany
    case hasOne
    case belongsTo
}
```

### Schema Registry Integration

Relationships integrate with the schema registry for metadata:

```swift
// Automatically registered when using property wrappers
public struct User: Schema {
    @HasMany public var posts: [Post]  // Registered automatically
}
```

## Performance Considerations

### Query Optimization

- **Lazy by Default**: No queries until explicitly loaded
- **Batch Loading**: Preloading uses efficient IN queries
- **Caching**: Loaded relationships are cached on instances
- **Memory Efficient**: Only loads what you request

### Best Practices

1. **Use Preloading for Lists**:
```swift
// Good for displaying a list
let users = try await repo.query(User.self).preload(\.$posts).all()
```

2. **Explicit Loading for Single Records**:
```swift
// Good for detail views
let user = try await repo.get(User.self, id: id)
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
```

3. **Check Loading State**:
```swift
// Avoid unnecessary queries
if !user.$posts.isLoaded {
    let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
}
```

4. **Handle Errors Gracefully**:
```swift
do {
    let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
} catch {
    // Provide fallback or show error to user
    let posts: [Post] = []
}
```

## Thread Safety

All relationship types are fully `Sendable` and safe for concurrent access:

- `SpectroLazyRelation<T>` is thread-safe
- Property wrappers are immutable and safe
- Loading operations can be called from any actor
- State changes are atomic and consistent

## Migration from Other ORMs

### From ActiveRecord-style ORMs

```swift
// Old way (causes N+1)
let users = User.all()
for user in users {
    print(user.posts.count)  // Each access triggers a query
}

// Spectro way (efficient)
let users = try await repo.query(User.self).preload(\.$posts).all()
for user in users {
    let posts = user.$posts.value ?? []
    print(posts.count)  // No additional queries
}
```

### From Core Data

```swift
// Core Data
let request: NSFetchRequest<User> = User.fetchRequest()
request.relationshipKeyPathsForPrefetching = ["posts"]
let users = try context.fetch(request)

// Spectro
let users = try await repo.query(User.self).preload(\.$posts).all()
```