# Performance Optimization

Advanced techniques for optimizing relationship loading and query performance in Spectro.

## Overview

Spectro's implicit lazy relationship system is designed for performance by default, but understanding the underlying mechanisms helps you build even more efficient applications.

## Understanding the N+1 Problem

The N+1 query problem is one of the most common performance issues in ORMs:

### The Problem

```swift
// BAD: This causes N+1 queries
let users = try await repo.all(User.self)  // 1 query
for user in users {
    // Each iteration causes another query (N queries)
    let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
    print("\(user.name): \(posts.count) posts")
}
// Total: 1 + N queries (where N = number of users)
```

If you have 100 users, this results in 101 database queries!

### Spectro's Solution

```swift
// GOOD: Spectro's lazy loading prevents automatic N+1
let users = try await repo.all(User.self)  // 1 query
for user in users {
    // Relationships are lazy - no automatic queries triggered
    print("\(user.name): posts not loaded yet")
}

// BETTER: Use explicit batch loading
let usersWithPosts = try await repo.query(User.self)
    .preload(\.$posts)  // Efficient batch loading
    .all()
// Total: 2 queries (1 for users, 1 for all posts)
```

## Relationship Loading Strategies

### 1. Lazy Loading (Default)

Relationships are loaded only when explicitly requested:

```swift
let user = try await repo.get(User.self, id: userId)
// No relationship queries yet

let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
// Query executed now: SELECT * FROM posts WHERE user_id = $1
```

**Pros:**
- No unnecessary queries
- Memory efficient
- Explicit control

**Cons:**
- Can lead to N+1 if not managed properly
- Requires explicit loading calls

### 2. Preloading (Eager Loading)

Load relationships efficiently for multiple records:

```swift
let users = try await repo.query(User.self)
    .preload(\.$posts)
    .all()

// Generates optimized queries:
// 1. SELECT * FROM users
// 2. SELECT * FROM posts WHERE user_id IN ($1, $2, $3, ...)
```

**Pros:**
- Prevents N+1 queries
- Efficient batch loading
- Automatic optimization

**Cons:**
- May load unnecessary data
- Higher memory usage

### 3. Selective Loading

Load only what you need:

```swift
// For a user list (don't need posts)
let users = try await repo.query(User.self)
    .where { $0.isActive == true }
    .all()

// For a user detail page (need posts)
let user = try await repo.get(User.self, id: userId)
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
```

## Query Optimization Techniques

### 1. Use Indexes

Ensure proper database indexes for foreign keys:

```sql
-- Essential indexes for relationship performance
CREATE INDEX idx_posts_user_id ON posts(user_id);
CREATE INDEX idx_comments_post_id ON comments(post_id);
CREATE INDEX idx_profiles_user_id ON profiles(user_id);
```

### 2. Limit Result Sets

Always limit large relationship queries:

```swift
// Load recent posts only
let posts = try await repo.query(Post.self)
    .where { $0.userId == userId }
    .orderBy { $0.createdAt }
    .limit(20)
    .all()
```

### 3. Select Only Needed Fields

Use tuple queries for better performance:

```swift
// Load only title and created date
let postSummaries = try await repo.query(Post.self)
    .where { $0.userId == userId }
    .select { ($0.title, $0.createdAt) }
    .all()
```

### 4. Batch Operations

Process multiple records efficiently:

```swift
// Instead of individual loads
for userId in userIds {
    let user = try await repo.get(User.self, id: userId)  // N queries
}

// Use batch loading
let users = try await repo.query(User.self)
    .where { $0.id.in(userIds) }  // 1 query
    .all()
```

## Memory Management

### 1. Relationship Caching

Loaded relationships are cached on instances:

```swift
let user = try await repo.get(User.self, id: userId)
let posts1 = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)  // Query executed
let posts2 = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)  // Uses cache

// Check if cached
if user.$posts.isLoaded {
    let posts = user.$posts.value ?? []  // No query needed
}
```

### 2. Memory Pressure Handling

For large datasets, consider pagination:

```swift
func loadUserPostsPaginated(userId: UUID, page: Int, pageSize: Int = 20) async throws -> [Post] {
    return try await repo.query(Post.self)
        .where { $0.userId == userId }
        .orderBy { $0.createdAt }
        .offset(page * pageSize)
        .limit(pageSize)
        .all()
}

// Load posts in chunks
var page = 0
repeat {
    let posts = try await loadUserPostsPaginated(userId: userId, page: page)
    // Process posts...
    page += 1
} while !posts.isEmpty
```

### 3. Weak References for Circular Relationships

Avoid retain cycles in bidirectional relationships:

```swift
// This would create a retain cycle if not handled properly
public struct User: Schema {
    @HasMany public var posts: [Post]
}

public struct Post: Schema {
    @BelongsTo public var user: User?  // Spectro handles this safely
}
```

## Monitoring and Debugging

### 1. Query Logging

Enable query logging to identify performance issues:

```swift
// Configure logging (implementation-specific)
let config = DatabaseConfiguration(/* ... */)
config.enableQueryLogging = true

// Monitor slow queries
config.slowQueryThreshold = 0.1  // Log queries > 100ms
```

### 2. Relationship Loading Metrics

Track relationship loading patterns:

```swift
struct RelationshipMetrics {
    static var loadCounts: [String: Int] = [:]
    
    static func track(relationship: String) {
        loadCounts[relationship, default: 0] += 1
    }
}

// In your loading code
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
RelationshipMetrics.track(relationship: "User.posts")
```

### 3. Performance Testing

Write performance tests for critical paths:

```swift
func testUserListPerformance() async throws {
    // Create test data
    let users = (1...100).map { User(name: "User \($0)", email: "user\($0)@test.com", age: 20) }
    for user in users {
        _ = try await repo.insert(user)
    }
    
    // Measure query performance
    let startTime = CFAbsoluteTimeGetCurrent()
    let loadedUsers = try await repo.query(User.self)
        .preload(\.$posts)
        .all()
    let duration = CFAbsoluteTimeGetCurrent() - startTime
    
    // Assert performance expectations
    XCTAssertLessThan(duration, 0.5, "User list loading should complete in < 500ms")
    XCTAssertEqual(loadedUsers.count, 100)
}
```

## Database-Specific Optimizations

### PostgreSQL-Specific Features

#### 1. Use EXPLAIN ANALYZE

Analyze query performance:

```sql
EXPLAIN ANALYZE 
SELECT u.*, p.* 
FROM users u 
LEFT JOIN posts p ON u.id = p.user_id 
WHERE u.is_active = true;
```

#### 2. Optimize JOIN Strategies

Control how PostgreSQL executes joins:

```sql
-- Force specific join types if needed
SET enable_hashjoin = off;
SET enable_mergejoin = off;
-- This forces nested loop joins
```

#### 3. Use Partial Indexes

Create indexes for specific conditions:

```sql
-- Index only active users
CREATE INDEX idx_users_active ON users(id) WHERE is_active = true;

-- Index only published posts
CREATE INDEX idx_posts_published ON posts(user_id) WHERE published = true;
```

## Common Performance Anti-Patterns

### 1. Loading in Loops

```swift
// BAD: N+1 queries
let userIds = [/* ... */]
for userId in userIds {
    let user = try await repo.get(User.self, id: userId)
    let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
    // Process user and posts...
}

// GOOD: Batch loading
let users = try await repo.query(User.self)
    .where { $0.id.in(userIds) }
    .preload(\.$posts)
    .all()
for user in users {
    let posts = user.$posts.value ?? []
    // Process user and posts...
}
```

### 2. Over-Preloading

```swift
// BAD: Loading unnecessary data
let users = try await repo.query(User.self)
    .preload(\.$posts)          // Might not need posts
    .preload(\.$profile)        // Might not need profile
    .preload(\.$comments)       // Definitely don't need comments
    .all()

// GOOD: Load only what you need
let users = try await repo.query(User.self)
    .preload(\.$profile)        // Only load profile for user list
    .all()
```

### 3. Ignoring Relationship State

```swift
// BAD: Always loading without checking
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)

// GOOD: Check if already loaded
let posts: [Post]
if user.$posts.isLoaded {
    posts = user.$posts.value ?? []
} else {
    posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
}
```

## Performance Best Practices Summary

### DO:
- ✅ Use preloading for lists and collections
- ✅ Load relationships explicitly when needed
- ✅ Check loading state before loading
- ✅ Use pagination for large result sets
- ✅ Add proper database indexes
- ✅ Monitor query performance
- ✅ Use transactions for related operations
- ✅ Limit result sets with WHERE clauses

### DON'T:
- ❌ Load relationships in loops
- ❌ Over-preload unnecessary data
- ❌ Ignore loading state
- ❌ Load unbounded result sets
- ❌ Forget database indexes
- ❌ Make assumptions about caching
- ❌ Use relationships without explicit loading

## Real-World Examples

### User Dashboard

```swift
func loadUserDashboard(userId: UUID) async throws -> UserDashboard {
    // Load user with essential relationships
    let user = try await repo.get(User.self, id: userId)
    
    // Load recent posts (limited)
    let recentPosts = try await repo.query(Post.self)
        .where { $0.userId == userId }
        .orderBy { $0.createdAt }
        .limit(5)
        .all()
    
    // Load profile if exists
    let profile = try await user.loadHasOne(Profile.self, foreignKey: "userId", using: repo)
    
    // Load post count (efficient)
    let postCount = try await repo.query(Post.self)
        .where { $0.userId == userId }
        .count()
    
    return UserDashboard(
        user: user,
        profile: profile,
        recentPosts: recentPosts,
        totalPosts: postCount
    )
}
```

### Blog Post List

```swift
func loadBlogPosts(page: Int = 0, pageSize: Int = 20) async throws -> [PostWithAuthor] {
    // Efficient loading with preloaded authors
    let posts = try await repo.query(Post.self)
        .where { $0.published == true }
        .preload(\.$user)  // Preload authors
        .orderBy { $0.createdAt }
        .offset(page * pageSize)
        .limit(pageSize)
        .all()
    
    // Convert to presentation models
    return posts.compactMap { post in
        guard let author = post.$user.value else { return nil }
        return PostWithAuthor(
            title: post.title,
            content: post.content,
            authorName: author.name,
            publishedAt: post.createdAt
        )
    }
}
```

### Search with Relationships

```swift
func searchUsersWithPosts(query: String) async throws -> [UserSearchResult] {
    // Find matching users
    let users = try await repo.query(User.self)
        .where { $0.name.ilike("%\(query)%") }
        .preload(\.$posts)
        .limit(50)
        .all()
    
    // Transform to search results
    return users.map { user in
        let posts = user.$posts.value ?? []
        return UserSearchResult(
            user: user,
            postCount: posts.count,
            latestPost: posts.max(by: { $0.createdAt < $1.createdAt })
        )
    }
}
```