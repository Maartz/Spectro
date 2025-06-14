# Spectro

Swift ORM for PostgreSQL built with property wrappers and actor-based concurrency.

## Features

- Property wrapper schema definitions (`@ID`, `@Column`, `@Timestamp`, `@ForeignKey`)
- Closure-based query syntax with compile-time validation
- Relationship property wrappers (`@HasMany`, `@HasOne`, `@BelongsTo`) with lazy loading
- Actor-based connection management for thread safety
- Transaction support with automatic rollback
- Built on PostgresNIO for async/await operations
- Swift 6 compatible with Sendable conformance

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Maartz/Spectro.git", from: "0.2.0")
]
```

## Quick Start

### Define Schema

```swift
import Spectro

struct User: Schema, SchemaBuilder {
    static let tableName = "users"
    
    @ID var id: UUID
    @Column var name: String = ""
    @Column var email: String = ""
    @Column var age: Int = 0
    @Column var isActive: Bool = true
    @Timestamp var createdAt: Date = Date()
    @Timestamp var updatedAt: Date = Date()
    
    init() {}
    
    static func build(from values: [String: Any]) -> User {
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
```

### Initialize Connection

```swift
let spectro = try await Spectro(
    username: "postgres",
    password: "password",
    database: "myapp"
)

let repo = spectro.repository()
```

### CRUD Operations

```swift
// Create
let user = User()
user.name = "Alice"
user.email = "alice@example.com"
let saved = try await repo.insert(user)

// Read
let user = try await repo.get(User.self, id: userId)
let users = try await repo.all(User.self)

// Update
let updated = try await repo.update(User.self, id: userId, changes: [
    "name": "Alice Smith",
    "age": 26
])

// Delete
try await repo.delete(User.self, id: userId)
```

### Query Builder

```swift
// Basic queries
let adults = try await repo.query(User.self)
    .where { $0.age > 18 }
    .orderBy { $0.createdAt }
    .limit(10)
    .all()

// Complex filtering
let results = try await repo.query(User.self)
    .where { $0.age.between(25, and: 65) }
    .where { $0.email.endsWith("@company.com") }
    .where { $0.isActive == true }
    .orderBy({ $0.createdAt }, .desc)
    .all()

// String operations
let search = try await repo.query(User.self)
    .where { $0.name.ilike("%john%") }      // Case-insensitive LIKE
    .where { $0.email.startsWith("admin") }  // String prefix
    .all()

// Count queries
let count = try await repo.query(User.self)
    .where { $0.isActive == true }
    .count()
```

### Joins

```swift
// Inner join
let usersWithPosts = try await repo.query(User.self)
    .join(Post.self) { join in
        join.left.id == join.right.userId
    }
    .all()

// Left join
let usersWithProfiles = try await repo.query(User.self)
    .leftJoin(Profile.self) { join in
        join.left.id == join.right.userId
    }
    .all()

// Many-to-many through junction table
let postsWithTags = try await repo.query(Post.self)
    .joinThrough(Tag.self, through: PostTag.self) { join in
        let firstJoin = join.main.id == join.junction.postId
        let secondJoin = join.junction.tagId == join.target.id
        return (firstJoin, secondJoin)
    }
    .all()
```

### Relationships

```swift
// Define relationships (currently require manual loading)
struct User: Schema {
    @HasMany var posts: [Post]
    @HasOne var profile: Profile?
}

struct Post: Schema {
    @BelongsTo var user: User?
}

// Load relationships explicitly
let user = try await repo.get(User.self, id: userId)
let posts = try await user.loadHasMany(Post.self, foreignKey: "userId", using: repo)

// Preload for efficiency
let users = try await repo.query(User.self)
    .preload(\.$posts)
    .all()
```

### Transactions

```swift
let result = try await repo.transaction { transactionRepo in
    let user = try await transactionRepo.insert(user)
    let post = Post()
    post.userId = user.id
    post.title = "First Post"
    let savedPost = try await transactionRepo.insert(post)
    return (user, savedPost)
}
```

## CLI Usage

The Spectro CLI provides database and migration management:

```bash
# Build the CLI
swift build --product spectro

# Database commands
spectro database create --database myapp_dev
spectro database drop --database myapp_dev

# Migration commands
spectro migrate generate CreateUsersTable
spectro migrate up
spectro migrate down
spectro migrate status
```

## Architecture

### Core Components

1. **Schema Protocol** - Base protocol for all database models
2. **SchemaBuilder Protocol** - Required for mapping database rows to Swift types
3. **Repository Pattern** - `GenericDatabaseRepo` provides CRUD operations
4. **Query Builder** - Immutable, composable query construction
5. **Actor-Based Connection** - Thread-safe database access via `DatabaseConnection`
6. **Property Wrappers** - Type-safe field definitions

### Database Support

Currently supports PostgreSQL via PostgresNIO. The design allows for future database adapters.

### Error Handling

All operations that can fail throw `SpectroError` with specific cases:
- `connectionFailed`
- `queryExecutionFailed`
- `notFound`
- `invalidSchema`
- `transactionFailed`

## Roadmap

### Version 0.3.0 (Current Target)
- [x] CLI tool for migrations
- [x] Property wrapper implementations
- [x] Basic relationship mapping
- [x] SchemaBuilder protocol
- [ ] Query parameter abstraction (remove string manipulation)
- [ ] Transaction isolation improvements
- [ ] Bulk insert/update operations
- [ ] Connection retry logic
- [ ] Comprehensive test suite

### Version 0.4.0
- [ ] Automatic relationship loading
- [ ] Migration versioning system
- [ ] Query performance optimization
- [ ] Prepared statement caching
- [ ] Connection pool monitoring

### Version 0.5.0
- [ ] Multiple database support
- [ ] Schema validation
- [ ] Database introspection
- [ ] Advanced query features (CTEs, window functions)

### Future
- [ ] Code generation for SchemaBuilder
- [ ] GraphQL integration
- [ ] Real-time subscriptions
- [ ] Sharding support

## Known Issues

1. **SchemaBuilder Required** - All schemas must implement SchemaBuilder protocol for field mapping
2. **Relationship Loading** - Relationships require manual loading (no automatic resolution yet)
3. **Query Parameters** - Parameter binding uses string manipulation (needs abstraction)
4. **Transaction Isolation** - Transactions use same connection (needs separate connections)
5. **Test Suite** - Some tests may have timing issues or infinite loops

## Development

### Setup

```bash
# Clone repository
git clone https://github.com/Maartz/Spectro.git
cd Spectro

# Create test database
createdb spectro_test

# Set up test schema
./Tests/setup_test_db.sh

# Run tests
swift test
```

### Environment Variables

Create `.env` file:
```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=myapp_db
DB_USER=postgres
DB_PASSWORD=password
TEST_DB_NAME=spectro_test
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see LICENSE file for details.