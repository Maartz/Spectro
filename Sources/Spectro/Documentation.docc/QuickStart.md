# Quick Start Guide

Get up and running with Spectro's implicit lazy relationship system in minutes.

## Overview

This guide will walk you through setting up Spectro, defining schemas with relationships, and using the implicit lazy loading system to build efficient database applications.

## Installation

Add Spectro to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/spectro.git", from: "0.2.0")
]
```

## Database Setup

First, set up your PostgreSQL database and run the schema setup:

```bash
# Create database
createdb myapp_dev

# Run Spectro migrations (if using CLI)
spectro migrate up

# Or manually create tables
psql myapp_dev -f schema.sql
```

## Step 1: Define Your Schemas

Create your schema definitions using property wrappers:

```swift
import Spectro

// User schema
public struct User: Schema, SchemaBuilder {
    public static let tableName = "users"
    
    @ID public var id: UUID
    @Column public var name: String = ""
    @Column public var email: String = ""
    @Column public var age: Int = 0
    @Column public var isActive: Bool = true
    @Timestamp public var createdAt: Date = Date()
    @Timestamp public var updatedAt: Date = Date()
    
    public init() {}
    
    public init(name: String, email: String, age: Int) {
        self.name = name
        self.email = email
        self.age = age
    }
    
    // MARK: - SchemaBuilder Implementation
    public static func build(from values: [String: Any]) -> User {
        var user = User()
        if let id = values["id"] as? UUID { user.id = id }
        if let name = values["name"] as? String { user.name = name }
        if let email = values["email"] as? String { user.email = email }
        if let age = values["age"] as? Int { user.age = age }
        if let isActive = values["isActive"] as? Bool { user.isActive = isActive }
        if let createdAt = values["createdAt"] as? Date { user.createdAt = createdAt }
        if let updatedAt = values["updatedAt"] as? Date { user.updatedAt = updatedAt }
        return user
    }
}

// Post schema with foreign key
public struct Post: Schema, SchemaBuilder {
    public static let tableName = "posts"
    
    @ID public var id: UUID
    @Column public var title: String = ""
    @Column public var content: String = ""
    @Column public var published: Bool = false
    @ForeignKey public var userId: UUID = UUID()
    @Timestamp public var createdAt: Date = Date()
    @Timestamp public var updatedAt: Date = Date()
    
    public init() {}
    
    // MARK: - SchemaBuilder Implementation
    public static func build(from values: [String: Any]) -> Post {
        var post = Post()
        if let id = values["id"] as? UUID { post.id = id }
        if let title = values["title"] as? String { post.title = title }
        if let content = values["content"] as? String { post.content = content }
        if let published = values["published"] as? Bool { post.published = published }
        if let userId = values["userId"] as? UUID { post.userId = userId }
        if let createdAt = values["createdAt"] as? Date { post.createdAt = createdAt }
        if let updatedAt = values["updatedAt"] as? Date { post.updatedAt = updatedAt }
        return post
    }
}
```

## Step 2: Connect to Database

Set up your database connection:

```swift
import Spectro

// Configure database connection
let config = DatabaseConfiguration(
    hostname: "localhost",
    port: 5432,
    username: "postgres",
    password: "your_password",
    database: "myapp_dev"
)

// Create Spectro instance
let spectro = try Spectro(configuration: config)
let repo = spectro.repository()
```

## Step 3: Basic CRUD Operations

Perform basic database operations:

```swift
// Create
var user = User(name: "John Doe", email: "john@example.com", age: 30)
user = try await repo.insert(user)
print("Created user with ID: \(user.id)")

// Read
let users = try await repo.all(User.self)
let specificUser = try await repo.get(User.self, id: user.id)

// Update
let updatedUser = try await repo.update(User.self, id: user.id, changes: [
    "age": 31,
    "name": "John Smith"
])

// Delete
try await repo.delete(User.self, id: user.id)
```

## Step 4: Advanced Queries

Use the type-safe query builder:

```swift
// Simple where clause
let activeUsers = try await repo.query(User.self)
    .where { $0.isActive == true }
    .all()

// Complex conditions
let youngActiveUsers = try await repo.query(User.self)
    .where { $0.isActive == true && $0.age < 30 }
    .orderBy { $0.createdAt }
    .limit(10)
    .all()

// String searches
let johnUsers = try await repo.query(User.self)
    .where { $0.name.ilike("%john%") }
    .all()

// Date ranges
let recentUsers = try await repo.query(User.self)
    .where { $0.createdAt.after(Date().addingTimeInterval(-86400)) }
    .all()
```

## Step 5: Working with Relationships

The key feature of Spectro is its implicit lazy relationship system:

### Loading Relationships Explicitly

```swift
// Get a user
let user = try await repo.get(User.self, id: userId)

// Load their posts (explicit loading - no N+1 queries)
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
print("User has \(posts.count) posts")

// Load a post's author
let post = try await repo.get(Post.self, id: postId)
let author = try await post.loadBelongsTo(User.self, foreignKey: "userId", using: repo)
if let author = author {
    print("Post by \(author.name)")
}
```

### Preloading for Performance

For better performance when working with multiple records:

```swift
// BAD: This would cause N+1 queries if relationships were auto-loaded
let users = try await repo.all(User.self)
for user in users {
    // Each iteration would trigger a separate query
    let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
    print("\(user.name): \(posts.count) posts")
}

// GOOD: Use preloading (when implemented)
let usersWithPosts = try await repo.query(User.self)
    .preload(\.$posts)  // Efficient batch loading
    .all()

for user in usersWithPosts {
    // No additional queries - relationships are preloaded
    let posts = user.$posts.value ?? []
    print("\(user.name): \(posts.count) posts")
}
```

### Relationship States

Check the loading state of relationships:

```swift
let user = try await repo.get(User.self, id: userId)

// Check if posts are loaded
if user.$posts.isLoaded {
    let posts = user.$posts.value ?? []
    print("Posts already loaded: \(posts.count)")
} else {
    print("Posts not loaded yet")
}

// Handle different loading states
switch user.$posts.loadState {
case .notLoaded:
    print("Posts not loaded")
case .loading:
    print("Posts currently loading")
case .loaded(let posts):
    print("Loaded \(posts.count) posts")
case .error(let error):
    print("Failed to load posts: \(error)")
}
```

## Step 6: Error Handling

Handle common errors gracefully:

```swift
do {
    let user = try await repo.get(User.self, id: someId)
    let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
    print("Loaded \(posts.count) posts")
} catch SpectroError.notFound(let schema, let id) {
    print("Could not find \(schema) with ID \(id)")
} catch SpectroError.queryExecutionFailed(let sql, let error) {
    print("Query failed: \(sql)")
    print("Error: \(error)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Step 7: Transactions

Use transactions for data consistency:

```swift
try await repo.transaction { transactionRepo in
    // Create user
    var user = User(name: "Alice", email: "alice@example.com", age: 25)
    user = try await transactionRepo.insert(user)
    
    // Create their first post
    var post = Post()
    post.title = "My First Post"
    post.content = "Hello, world!"
    post.userId = user.id
    post.published = true
    post = try await transactionRepo.insert(post)
    
    // If any operation fails, the entire transaction is rolled back
    return (user, post)
}
```

## Best Practices

### 1. Always Load Relationships Explicitly

```swift
// GOOD: Explicit loading
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)

// BETTER: Preload for multiple records
let users = try await repo.query(User.self).preload(\.$posts).all()
```

### 2. Use Transactions for Related Operations

```swift
try await repo.transaction { repo in
    let user = try await repo.insert(newUser)
    let profile = try await repo.insert(profileForUser(user))
    return (user, profile)
}
```

### 3. Handle Errors Appropriately

```swift
do {
    // Database operations
} catch SpectroError.notFound {
    // Handle missing records
} catch SpectroError.queryExecutionFailed {
    // Handle SQL errors
} catch {
    // Handle unexpected errors
}
```

### 4. Use Type-Safe Queries

```swift
// GOOD: Type-safe field access
let users = try await repo.query(User.self)
    .where { $0.age > 18 }
    .orderBy { $0.createdAt }
    .all()

// AVOID: Raw SQL (when possible)
```

## Common Patterns

### Loading Related Data for Lists

```swift
// For a user profile page
let user = try await repo.get(User.self, id: userId)
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
let profile = try await user.loadHasOne(Profile.self, foreignKey: "userId", using: repo)

// For a blog post list with authors
let posts = try await repo.query(Post.self)
    .where { $0.published == true }
    .preload(\.$user)
    .orderBy { $0.createdAt }
    .limit(20)
    .all()
```

### Conditional Relationship Loading

```swift
let user = try await repo.get(User.self, id: userId)

// Only load posts if needed
if showPosts {
    let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
    // Use posts...
}
```

## Next Steps

- Read the comprehensive <doc:RelationshipLoading> guide
- Explore the <doc:QueryBuilder> documentation
- Check out the <doc:SchemaDesign> best practices
- Learn about <doc:Performance> optimization

## Troubleshooting

### Common Issues

1. **Foreign Key Constraints**: Ensure your foreign key fields match the target table's primary key type
2. **Schema Registration**: Make sure all schemas conform to both `Schema` and `SchemaBuilder`
3. **Connection Issues**: Check your database credentials and ensure PostgreSQL is running
4. **Type Mismatches**: Verify that your Swift types match your database column types

### Getting Help

- Check the API documentation for detailed method signatures
- Look at the example schemas in the codebase
- Run tests to see working examples
- Open an issue if you find a bug