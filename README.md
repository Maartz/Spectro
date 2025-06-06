# Spectro 🌈

A modern, type-safe Swift ORM for PostgreSQL built with Swift 6 and property wrappers. Spectro delivers beautiful APIs inspired by ActiveRecord and Ecto, with actor-based concurrency and zero crashes in production.

## ✨ Features

- 🏗️ **Property wrapper schemas** - Beautiful `@ID`, `@Column`, `@Timestamp` syntax
- 🔍 **KeyPath-based queries** - Type-safe queries with compile-time guarantees
- ⚡️ **Swift 6 + Actor concurrency** - Thread-safe database operations
- 🔐 **Production-ready** - Zero `fatalError()` calls, comprehensive error handling
- 🔄 **Transaction support** - ACID compliance with automatic rollback
- 📦 **Clean repository pattern** - Explicit data operations without global state
- 🎯 **Inspired by ActiveRecord/Ecto** - More type-safe, more explicit, more Swift
- 🚀 **Built on PostgresNIO** - High performance async/await throughout

## 📦 Installation

Add Spectro to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/Maartz/Spectro.git", from: "0.1.0")
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

// Type-safe KeyPath queries
let adults = try await repo.query(User.self)
    .where(\.age, .greaterThan, 18)
    .where(\.isActive, .equals, true)
    .orderBy(\.createdAt, .desc)
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
// Complex filtering
let powerUsers = try await repo.query(User.self)
    .where(\.age, .between, 25, and: 65)
    .where(\.email, .like, "%@company.com")
    .where(\.name, in: ["Alice", "Bob", "Charlie"])
    .orderBy(\.createdAt, .desc)
    .orderBy(\.name, .asc)
    .limit(50)
    .offset(20)
    .all()

// Count queries
let activeUserCount = try await repo.query(User.self)
    .where(\.isActive, .equals, true)
    .count()

// First/single results
let firstUser = try await repo.query(User.self)
    .where(\.email, .equals, "alice@example.com")
    .first()

let user = try await repo.query(User.self)
    .where(\.email, .equals, "alice@example.com")
    .firstOrFail()
```

### 5. Transactions

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

### 6. Convenience Methods

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

### Type-Safe KeyPath Queries

```swift
// Compile-time type safety - these won't compile if field types don't match
let query = repo.query(User.self)
    .where(\.name, .equals, "John")        // String comparison
    .where(\.age, .greaterThan, 18)        // Int comparison
    .where(\.isActive, .equals, true)      // Bool comparison
    .where(\.createdAt, .lessThan, Date()) // Date comparison
    .orderBy(\.name, .asc)                 // Type-safe ordering
    .limit(10)

let users = try await query.all()
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
        
        // Query
        let adults = try await repo.query(User.self)
            .where(\.age, .greaterThan, 18)
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
    .where(\.isActive, .equals, true)
    .limit(100)
    .all()

// ✅ Use counts when you only need numbers
let userCount = try await repo.query(User.self)
    .where(\.isActive, .equals, true)
    .count()

// ✅ Use first() for single results
let user = try await repo.query(User.self)
    .where(\.email, .equals, "unique@example.com")
    .first()
```

## 🗺️ Roadmap

### ✅ Completed (v0.1.0)
- [x] Property wrapper schema definitions
- [x] KeyPath-based type-safe queries  
- [x] Actor-based connection management
- [x] Comprehensive error handling (zero crashes)
- [x] Transaction support with automatic rollback
- [x] Repository pattern with clean APIs
- [x] Swift 6 compatibility
- [x] Production safety (no fatalError/try!)

### 🚧 Next Release (v0.2.0)
- [ ] Relationship support (`@HasMany`, `@HasOne`, `@BelongsTo`)
- [ ] Join queries and eager loading
- [ ] Integer primary key support
- [ ] Migration system integration
- [ ] Query caching layer

### 📋 Future Releases
- [ ] Many-to-many relationships
- [ ] Bulk operations
- [ ] Prepared statement caching
- [ ] Query performance analytics
- [ ] Advanced validation layer
- [ ] Multiple database support

## 🤝 Contributing

We welcome contributions! Spectro is built with:

- **Swift 6** - Modern concurrency and Sendable safety
- **PostgresNIO** - High-performance PostgreSQL driver
- **Actor isolation** - Thread-safe database access
- **Property wrappers** - Clean, declarative schema definitions

### Development Setup

1. Clone the repository
2. Set up PostgreSQL with test database
3. Run `swift test` to ensure everything works

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Spectro** - The modern Swift ORM that doesn't compromise on safety, performance, or beauty. 🌈

Built with ❤️ for the Swift community.
