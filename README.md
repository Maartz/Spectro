# Spectro 🌈

A modern, type-safe Swift ORM for PostgreSQL built with Swift 6 and property wrappers. Spectro delivers beautiful APIs inspired by ActiveRecord and Ecto, with actor-based concurrency and zero crashes in production.

## ✨ Features

- 🔗 **Implicit Lazy Relationships** - Revolutionary relationship loading that appears as normal Swift properties but prevents N+1 queries by default
- 🏛️ **Ecto-Inspired Design** - Familiar patterns from Elixir's Ecto ORM with Swift's type safety
- 🏗️ **Property wrapper schemas** - Beautiful `@ID`, `@Column`, `@HasMany`, `@BelongsTo` syntax
- 🔍 **100% closure-based queries** - Beautiful, consistent Swift syntax with compile-time guarantees  
- 🎯 **Revolutionary tuple selection** - `select { ($0.name, $0.email) }` returns `[(String, String)]`
- 📝 **Rich string functions** - `ilike()`, `startsWith()`, `contains()`, `iContains()` and more
- 📅 **Smart date helpers** - `isToday()`, `isThisWeek()`, `before()`, `after()` built-in
- ⚡️ **Swift 6 + Actor concurrency** - Thread-safe database operations
- 🔐 **Production-ready** - Zero `fatalError()` calls, comprehensive error handling
- 🔄 **Transaction support** - ACID compliance with automatic rollback
- 📦 **Clean repository pattern** - Explicit data operations without global state
- 🎯 **N+1 Prevention** - Lazy loading by default with efficient preloading capabilities
- 🚀 **Built on PostgresNIO** - High performance async/await throughout

## 📦 Installation

Add Spectro to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/Maartz/Spectro.git", from: "0.2.0")
]
```

## 🚀 Quick Start

### 1. Define Your Schema

```swift
import Spectro

struct User: Schema {
    static let tableName = "users"
    
    @ID var id: UUID
    @Column var name: String = ""
    @Column var email: String = ""
    @Column var age: Int = 0
    @Column var isActive: Bool = true
    @Timestamp var createdAt: Date = Date()
    @Timestamp var updatedAt: Date = Date()
    
    init() {}
    
    init(name: String, email: String, age: Int) {
        self.name = name
        self.email = email
        self.age = age
    }
}

struct Post: Schema {
    static let tableName = "posts"
    
    @ID var id: UUID
    @Column var title: String = ""
    @Column var content: String = ""
    @Column var published: Bool = false
    @ForeignKey var userId: UUID = UUID()
    @Timestamp var createdAt: Date = Date()
    
    init() {}
}
```

### 2. Initialize Spectro

```swift
import Spectro

// Create connection
let spectro = try Spectro(
    username: "postgres",
    password: "your_password",
    database: "your_database"
)

// Get repository
let repo = spectro.repository()
```

### 3. Beautiful CRUD Operations

```swift
// Create with type-safe initialization
let user = User(name: "Alice", email: "alice@example.com", age: 25)
let savedUser = try await repo.insert(user)

// Beautiful closure-based queries
let adults = try await repo.query(User.self)
    .where { $0.age > 18 && $0.isActive == true }
    .orderBy({ $0.createdAt }, .desc)
    .limit(10)
    .all()

// Single record queries
let user = try await repo.get(User.self, id: userId)
let user = try await repo.getOrFail(User.self, id: userId)

// Updates
let updated = try await repo.update(User.self, id: userId, changes: [
    "age": 26,
    "isActive": true
])

// Deletions
try await repo.delete(User.self, id: userId)
```

### 4. Advanced Queries

```swift
// Complex filtering with beautiful consistent syntax + REVOLUTIONARY string functions
let powerUsers = try await repo.query(User.self)
    .where { $0.age.between(25, and: 65) && $0.email.ilike("%@company.com") }
    .where { $0.name.in(["Alice", "Bob", "Charlie"]) || $0.email.endsWith("@vip.com") }
    .where { $0.createdAt.isThisYear() }
    .orderBy({ $0.createdAt }, .desc, then: { $0.name }, .asc)
    .limit(50)
    .offset(20)
    .all()

// Advanced string and date filtering
let searchResults = try await repo.query(User.self)
    .where { $0.name.iContains("john") }           // Case-insensitive contains
    .where { $0.email.startsWith("admin") }        // Starts with
    .where { $0.createdAt.isThisMonth() }          // Date helpers
    .where { $0.age.isNotNull() }                  // Null checks
    .orderBy({ $0.createdAt }, .desc)
    .all()

// REVOLUTIONARY: Tuple-based field selection! 🤯
let userNamesAndEmails = try await repo.query(User.self)
    .select { ($0.name, $0.email) }                // Returns [(String, String)]
    .where { $0.isActive == true }
    .orderBy { $0.name }
    .all()

// Single field selection (unwrapped)
let userNames = try await repo.query(User.self)
    .select { $0.name }                            // Returns [String]
    .where { $0.isActive == true }
    .all()

// Three fields as tuple
let userProfiles = try await repo.query(User.self)
    .select { ($0.name, $0.email, $0.age) }       // Returns [(String, String, Int)]
    .where { $0.age > 18 }
    .orderBy({ $0.createdAt }, .desc)
    .limit(100)
    .all()

// Count and existence queries
let activeUserCount = try await repo.query(User.self)
    .where { $0.isActive == true && $0.email.isNotNull() }
    .count()

let hasAdults = try await repo.query(User.self)
    .where { $0.age > 18 }
    .count() > 0
```

### 5. Beautiful Join Syntax

```swift
// Simple join - users with their posts
let usersWithPosts = try await repo.query(User.self)
    .join(Post.self) { join in
        join.left.id == join.right.userId
    }
    .where { $0.isActive == true }
    .all()

// Left join - all users, optionally with profiles
let usersWithProfiles = try await repo.query(User.self)
    .leftJoin(Profile.self) { join in
        join.left.id == join.right.userId
    }
    .all()

// Complex join conditions
let userPostsWithComments = try await repo.query(User.self)
    .join(Post.self) { join in
        join.left.id == join.right.userId
    }
    .join(Comment.self) { join in
        join.left.id == join.right.postId
    }
    .where { $0.isActive == true }
    .all()

// Many-to-many through junction table
let postsWithTags = try await repo.query(Post.self)
    .joinThrough(Tag.self, through: PostTag.self) { join in
        let firstJoin = join.main.id == join.junction.postId
        let secondJoin = join.junction.tagId == join.target.id
        return (firstJoin, secondJoin)
    }
    .where { $0.published == true }
    .all()

// FUTURE: Revolutionary join syntax with tuple selection! 🚀
// Coming in v0.2.0 - select across joined tables:
/*
let userPostData = try await repo.query(User.self)
    .join(Post.self) { join in
        join.left.id == join.right.userId
    }
    .select { ($0.name, $1.title, $1.createdAt) }  // User, Post, Comment
    .where { $0.isActive == true && $1.published == true }
    .all()  // Returns [(String, String, Date)]
*/
```

### 6. Implicit Lazy Relationships 🔗

**The revolutionary feature that makes Spectro unique!** Relationships appear as normal Swift properties but are lazy by default, preventing N+1 query issues automatically.

#### Defining Relationships

```swift
// User schema with relationships
struct User: Schema, SchemaBuilder {
    static let tableName = "users"
    
    @ID var id: UUID
    @Column var name: String = ""
    @Column var email: String = ""
    
    // Relationships appear as normal properties but are lazy!
    @HasMany var posts: [Post]           // User has many posts
    @HasOne var profile: Profile?        // User has one profile
    
    init() {}
    
    static func build(from values: [String: Any]) -> User {
        // Implementation...
    }
}

struct Post: Schema, SchemaBuilder {
    static let tableName = "posts"
    
    @ID var id: UUID
    @Column var title: String = ""
    @ForeignKey var userId: UUID = UUID()
    
    // Inverse relationship
    @BelongsTo var user: User?           // Post belongs to user
    
    init() {}
    
    static func build(from values: [String: Any]) -> Post {
        // Implementation...
    }
}
```

#### Loading Relationships (No N+1 Queries!)

```swift
// Get a user
let user = try await repo.get(User.self, id: userId)

// BAD in traditional ORMs: This would trigger N+1 queries
// for user in users { print(user.posts.count) }  // Each access = 1 query!

// GOOD in Spectro: Explicit loading prevents N+1
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)
print("User has \(posts.count) posts")

// Load belongs-to relationships
let post = try await repo.get(Post.self, id: postId)
let author = try await post.loadBelongsTo(User.self, foreignKey: "userId", using: repo)
if let author = author {
    print("Post by \(author.name)")
}

// Load has-one relationships
let profile = try await user.loadHasOne(Profile.self, foreignKey: "userId", using: repo)
```

#### Preloading for Performance

```swift
// EFFICIENT: Use preloading for lists to prevent N+1
let usersWithPosts = try await repo.query(User.self)
    .where { $0.isActive == true }
    .preload(\.$posts)           // Efficient batch loading
    .all()

// Now access without additional queries
for user in usersWithPosts {
    let posts = user.$posts.value ?? []  // No query needed!
    print("\(user.name): \(posts.count) posts")
}

// Chain multiple preloads
let usersWithData = try await repo.query(User.self)
    .preload(\.$posts)
    .preload(\.$profile)
    .limit(20)
    .all()
```

#### Checking Relationship State

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

#### Why This Prevents N+1 Queries

```swift
// TRADITIONAL ORMs - CAUSES N+1 QUERIES:
let users = User.all()                    // 1 query
for user in users {
    print(user.posts.count)              // N queries (one per user!)
}
// Total: 1 + N queries = SLOW! 🐌

// SPECTRO - NO N+1 QUERIES:
let users = try await repo.all(User.self) // 1 query
for user in users {
    // Relationships are lazy - no automatic queries!
    print("User: \(user.name)")           // No additional queries
}

// When you need relationships, load them efficiently:
let usersWithPosts = try await repo.query(User.self)
    .preload(\.$posts)                    // 2 queries total (users + all posts)
    .all()
// Total: 2 queries = FAST! ⚡
```

### 7. Transactions

```swift
// Automatic transaction handling
let result = try await repo.transaction { transactionRepo in
    let user = try await transactionRepo.insert(user)
    let post = Post(title: "My Post", content: "Content", userId: user.id)
    let savedPost = try await transactionRepo.insert(post)
    
    return (user, savedPost)
}

// Automatic rollback on error
try await repo.transaction { transactionRepo in
    let user = try await transactionRepo.insert(user)
    
    // This will rollback the entire transaction
    throw SpectroError.validationError(field: "email", errors: ["Invalid"])
}
```

### 7. Convenience Methods

```swift
// Direct Spectro operations
let user = try await spectro.get(User.self, id: userId)
let users = try await spectro.all(User.self)
let newUser = try await spectro.insert(user)

// Transaction convenience
let result = try await spectro.transaction { repo in
    // All operations within transaction
    return try await repo.insert(user)
}
```

## 💎 Beautiful API Showcase

### Property Wrapper Magic

```swift
struct User: Schema {
    static let tableName = "users"
    
    @ID var id: UUID                    // Auto-generated UUID primary key
    @Column var name: String = ""       // Required string column
    @Column var email: String = ""      // Required string column  
    @Column var age: Int = 0           // Integer with default
    @Column var isActive: Bool = true  // Boolean with default
    @Timestamp var createdAt: Date = Date()  // Auto-managed timestamp
    @Timestamp var updatedAt: Date = Date()  // Auto-managed timestamp
    
    init() {}
    
    // Custom initializer for convenience
    init(name: String, email: String, age: Int) {
        self.name = name
        self.email = email
        self.age = age
    }
}
```

### Beautiful Consistent Closure Syntax + Revolutionary Features

```swift
// 🎯 REVOLUTIONARY: Tuple-based field selection!
let userInfo = try await repo.query(User.self)
    .select { ($0.name, $0.email, $0.age) }      // Returns [(String, String, Int)]
    .where { $0.isActive == true }
    .orderBy { $0.createdAt }
    .limit(10)
    .all()

// 📝 Rich string functions with beautiful syntax
let searchUsers = try await repo.query(User.self)
    .where { $0.name.iContains("john") }         // Case-insensitive contains
    .where { $0.email.endsWith("@company.com") } // String functions
    .where { $0.bio.isNotNull() }                // Null handling
    .select { ($0.name, $0.email) }              // Tuple selection
    .all()

// 📅 Smart date helpers - no more complex date logic!
let recentActiveUsers = try await repo.query(User.self)
    .where { $0.createdAt.isThisMonth() }        // Built-in date helpers
    .where { $0.lastLoginAt.isThisWeek() }
    .where { $0.age.between(18, and: 65) }
    .orderBy({ $0.lastLoginAt }, .desc)
    .select { ($0.name, $0.lastLoginAt) }
    .all()

// 🔥 Everything is beautifully consistent - no mixed syntax!
let perfectQuery = repo.query(User.self)
    .select { $0.name }                          // Closure (returns [String])
    .where { $0.age > 25 }                       // Closure  
    .orderBy { $0.createdAt }                    // Closure
    .limit(10)                                   // Value (makes sense)
    .all()

// 🚀 Advanced pattern matching with full power
let powerUsers = try await repo.query(User.self)
    .where { user in
        (user.email.ilike("%@premium.com") || user.tier == "VIP") &&
        user.createdAt.isThisYear() &&
        user.loginCount > 50
    }
    .select { ($0.name, $0.email, $0.tier, $0.loginCount) }
    .orderBy({ $0.loginCount }, .desc)
    .limit(100)
    .all()
```

### Clean, Explicit API

```swift
// No global state - everything is explicit
let spectro = try Spectro(database: config)
let repo = spectro.repository()

// No method chaining on instances - clear data flow
let user = User(name: "Alice", email: "alice@example.com", age: 25)
let saved = try await repo.insert(user)                    // Clear: we're inserting
let found = try await repo.get(User.self, id: saved.id)   // Clear: we're querying
let updated = try await repo.update(User.self, id: saved.id, changes: [...]) // Clear: we're updating
```

## 🏗️ Architecture Excellence

### Actor-Based Concurrency

```swift
// Thread-safe database connections
public actor DatabaseConnection {
    // All database operations are isolated and thread-safe
    public func executeQuery<T>(...) async throws -> [T]
    public func transaction<T>(...) async throws -> T
}
```

### Zero Crashes Production Safety

```swift
// ❌ Old dangerous pattern:
let user = users.first!  // Crashes in production

// ✅ New safe pattern:
let user = try await repo.query(User.self)
    .where(\.email, .equals, "alice@example.com")
    .first()  // Returns Optional<User>

// ✅ Or explicit error handling:
let user = try await repo.query(User.self)
    .where(\.email, .equals, "alice@example.com")
    .firstOrFail()  // Throws SpectroError.notFound
```

### Comprehensive Error Handling

```swift
public enum SpectroError: Error, Sendable {
    case connectionFailed(underlying: Error)
    case queryExecutionFailed(sql: String, error: Error)
    case resultDecodingFailed(column: String, expectedType: String)
    case notFound(schema: String, id: UUID)
    case validationError(field: String, errors: [String])
    case transactionFailed(underlying: Error)
    case notImplemented(String)
}
```

## 🔧 Configuration

### Environment-Based Setup

```swift
// From environment variables
let spectro = try Spectro.fromEnvironment()

// Or explicit configuration
let spectro = try Spectro(
    hostname: "localhost",
    port: 5432,
    username: "postgres", 
    password: "password",
    database: "myapp",
    maxConnectionsPerEventLoop: 4
)
```

### Database Setup

```bash
# Create your database
createdb myapp_db
createdb myapp_test_db

# Set environment variables
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=myapp_db
export DB_USER=postgres
export DB_PASSWORD=password
```

## 🧪 Testing

Spectro makes testing beautiful and simple:

```swift
import Testing
@testable import Spectro

@Suite("User Tests")
struct UserTests {
    @Test("Can create and query users")
    func testUserCRUD() async throws {
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres", 
            database: "spectro_test"
        )
        defer { Task { await spectro.shutdown() } }
        
        let repo = spectro.repository()
        
        // Create
        let user = User(name: "Test User", email: "test@example.com", age: 30)
        let saved = try await repo.insert(user)
        
        // Read
        let found = try await repo.get(User.self, id: saved.id)
        #expect(found?.name == "Test User")
        
        // Query with consistent closure syntax
        let adults = try await repo.query(User.self)
            .where { $0.age > 18 }
            .orderBy { $0.createdAt }
            .all()
        #expect(adults.count > 0)
    }
}
```

## 🚀 Performance & Best Practices

### Connection Pooling

```swift
// Automatic connection pooling with EventLoopGroupConnectionPool
let spectro = try Spectro(
    username: "postgres",
    password: "password",
    database: "myapp",
    maxConnectionsPerEventLoop: 4  // Optimize for your workload
)
```

### Transaction Best Practices

```swift
// ✅ Good - Short transactions
try await repo.transaction { transactionRepo in
    let user = try await transactionRepo.insert(user)
    let profile = try await transactionRepo.insert(profile)
    return (user, profile)
}

// ❌ Avoid - Long-running transactions
try await repo.transaction { transactionRepo in
    // Don't do heavy computation or external API calls in transactions
    let result = try await heavyComputation()  // This blocks other transactions
    return result
}
```

### Query Optimization

```swift
// ✅ Use specific queries instead of loading all data
let activeUsers = try await repo.query(User.self)
    .select { $0.name }
    .select { $0.email }
    .where { $0.isActive == true }
    .orderBy { $0.createdAt }
    .limit(100)
    .all()

// ✅ Use counts when you only need numbers
let userCount = try await repo.query(User.self)
    .where { $0.isActive == true }
    .count()

// ✅ Use first() for single results
let user = try await repo.query(User.self)
    .where { $0.email == "unique@example.com" }
    .first()
```

## 🗺️ Roadmap

### ✅ Completed (v0.2.0)
- [x] Property wrapper schema definitions
- [x] **100% closure-based syntax** - Beautiful consistency throughout  
- [x] **Revolutionary tuple selection** - `select { ($0.name, $0.email) }`
- [x] **Rich string functions** - `ilike()`, `startsWith()`, `contains()`, `iContains()`, etc.
- [x] **Smart date helpers** - `isToday()`, `isThisWeek()`, `before()`, `after()`
- [x] **Null handling** - `isNull()`, `isNotNull()` built-in
- [x] Beautiful join syntax with `through` support
- [x] Actor-based connection management
- [x] Comprehensive error handling (zero crashes)
- [x] Transaction support with automatic rollback
- [x] Repository pattern with clean APIs
- [x] Swift 6 compatibility
- [x] Production safety (no fatalError/try!)

### 🚧 Next Release (v0.3.0)
- [ ] **Tuple selection for joins** - `select { ($0.name, $1.title, $2.content) }`
- [ ] Eager loading with automatic relationship resolution
- [ ] Integer primary key support (auto-incrementing)
- [ ] Migration system integration
- [ ] Query caching layer
- [ ] Bulk operations for performance

### 📋 Future Releases
- [ ] Prepared statement caching
- [ ] Query performance analytics
- [ ] Advanced validation layer
- [ ] Multiple database support
- [ ] GraphQL-style field selection
- [ ] Real-time query subscriptions

## 🤝 Contributing

We welcome contributions! Spectro is built with:

- **Swift 6** - Modern concurrency and Sendable safety
- **PostgresNIO** - High-performance PostgreSQL driver
- **Actor isolation** - Thread-safe database access
- **Property wrappers** - Clean, declarative schema definitions

### Development Setup

1. Clone the repository
2. Set up PostgreSQL with test database:
   ```bash
   createdb spectro_test
   ```
3. Run the test database setup script:
   ```bash
   ./Tests/setup_schema.sh
   ```
4. Run tests:
   ```bash
   swift test
   ```

### Test Database Setup

The test suite uses a pre-created database schema to avoid concurrent table creation issues. Before running tests:

```bash
# Create test database
createdb spectro_test

# Setup schema
./Tests/setup_schema.sh

# Run tests
swift test
```

All tests should pass ✅ - the test suite focuses on core functionality with proper database isolation.

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Spectro** - The modern Swift ORM that doesn't compromise on safety, performance, or beauty. 🌈

Built with ❤️ for the Swift community.
