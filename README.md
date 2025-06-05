# Spectro 🌈

A modern Swift ORM for PostgreSQL that prioritizes type safety, developer experience, and elegant APIs. Spectro is heavily inspired by Elixir's Ecto library, bringing its composable query patterns and relationship handling to the Swift ecosystem.

## ✨ Features

- 🏗️ **Type-safe schema definitions** with rich field types and relationships
- 🔍 **Expressive query builder** with method chaining and composable queries
- 🔗 **Advanced relationship handling** - hasMany, hasOne, belongsTo with join support
- 💫 **Beautiful API design** - ActiveRecord-style convenience methods with repository pattern power
- 🔄 **Database migrations** with comprehensive CLI support
- 📦 **Repository pattern** with global configuration and schema-level methods
- ⚡️ **Built on Swift NIO** - async/await throughout, high performance
- 🔐 **Environment-based configuration** for secure credential management
- 🎯 **Swift 6 compatible** with full concurrency support

## 📦 Installation

Add Spectro to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/Maartz/Spectro.git", from: "0.1.0")
]
```

## 🚀 Quick Start

### 1. Database Setup

Create your PostgreSQL database and configure access:

```bash
# Create database
createdb your_app_db

# For testing (recommended)
createdb your_app_test_db
```

### 2. Environment Configuration

Create a `.env` file in your project root:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=your_app_db
DB_USER=your_username
DB_PASSWORD=your_password

# Test database
TEST_DB_NAME=your_app_test_db
```

⚠️ **Important**: Add `.env` to your `.gitignore` to keep credentials secure.

### 3. Define Your Schemas

Schemas define your data structure and relationships:

```swift
import Spectro

struct UserSchema: Schema {
    static let schemaName = "users"
    
    @SchemaBuilder
    static var fields: [SField] {
        Field.description("name", .string)
        Field.description("email", .string)
        Field.description("age", .integer(defaultValue: 0))
        Field.description("is_active", .boolean(defaultValue: true))
        Field.description("created_at", .timestamp)
        
        // Relationships
        Field.hasMany("posts", PostSchema.self)
        Field.hasOne("profile", ProfileSchema.self)
    }
}

struct PostSchema: Schema {
    static let schemaName = "posts"
    
    @SchemaBuilder
    static var fields: [SField] {
        Field.description("title", .string)
        Field.description("content", .string)
        Field.description("published", .boolean(defaultValue: false))
        Field.description("created_at", .timestamp)
        
        // Relationships
        Field.belongsTo("user", UserSchema.self)
        Field.hasMany("comments", CommentSchema.self)
    }
}
```

### 4. Initialize Spectro

```swift
import Spectro

// Configure the database connection
let spectro = try Spectro(
    username: "your_username",
    password: "your_password", 
    database: "your_app_db"
)

// Configure global repository (for schema-level methods)
let repo = PostgresRepo(pools: spectro.pools)
RepositoryConfiguration.configure(with: repo)
```

## 💡 Core Concepts

### Schema-Level API (Recommended)

Spectro provides a beautiful, ActiveRecord-inspired API that works at the schema level:

```swift
// Get all users
let users = try await UserSchema.all()

// Query with conditions
let activeUsers = try await UserSchema.all { query in
    query.where { $0.is_active == true && $0.age > 18 }
         .orderBy { [$0.name.asc()] }
         .limit(10)
}

// Find by ID
let user = try await UserSchema.get(userId)
let user = try await UserSchema.getOrFail(userId) // Throws if not found

// Create new records
let user = try await UserSchema.create([
    "name": "John Doe",
    "email": "john@example.com",
    "age": 30
])

// Update records
let updatedUser = try await user.update([
    "age": 31,
    "is_active": true
])

// Delete records
try await user.delete()
```

### Query Builder

Build complex queries with type-safe, composable methods:

```swift
let query = UserSchema.query()
    .select { [$0.name, $0.email, $0.age] }
    .where { $0.age > 25 && $0.is_active == true }
    .orderBy { [$0.created_at.desc(), $0.name.asc()] }
    .limit(20)
    .offset(10)

let users = try await UserSchema.execute(query)
```

### Advanced Relationship Queries

Spectro supports powerful relationship queries inspired by Ecto and ActiveRecord:

```swift
// Join tables for filtering
let usersWithPosts = try await UserSchema.all { query in
    query.join("posts")
         .where("posts") { $0.published == true }
}

// Navigate through relationships
let publishedPosts = try await UserSchema.all { query in
    query.where { $0.name.eq("John Doe") }
         .through("posts")
         .where { $0.published == true }
}

// Deep relationship navigation
let approvedComments = try await UserSchema.all { query in
    query.where { $0.is_active == true }
         .through("posts")
         .where { $0.published == true }
         .through("comments")
         .where { $0.approved == true }
}

// Preload relationships (eager loading)
let usersWithData = try await UserSchema.all { query in
    query.preload("posts", "profile")
}
```

### Repository Pattern (Alternative)

For more explicit control, use the repository pattern directly:

```swift
let repo = PostgresRepo(pools: spectro.pools)

// Direct repository usage
let users = try await repo.all(UserSchema.self) { query in
    query.where { $0.age > 25 }
}

let user = try await repo.get(UserSchema.self, userId)
let newUser = try await repo.insert(changeset)
```

## 🔧 Database Migrations

Spectro provides a comprehensive CLI for managing database schema changes:

```bash
# Generate a new migration
spectro migrate generate add_users_table

# Run pending migrations
spectro migrate up

# Rollback last migration
spectro migrate down

# Check migration status
spectro migrate status
```

Migration files are generated in `migrations/` directory with timestamp prefixes for proper ordering.

## 🏗️ Architecture & Design Decisions

### Repository Pattern with Schema-Level Convenience

Spectro follows a **dual-API approach** combining the best of both worlds:

1. **Repository Pattern (Foundation)**: Explicit, testable, follows DDD principles
2. **Schema-Level API (Convenience)**: ActiveRecord-style methods for common operations

This allows you to use the beautiful `UserSchema.all()` API for simple cases while having the full power of `repo.all(UserSchema.self)` when you need explicit control.

### Relationship Handling Philosophy

Inspired by **Elixir's Ecto**, Spectro treats relationships as first-class citizens:

- **Introspection**: Schemas can discover their relationships at runtime
- **Join Support**: Multiple join strategies (INNER, LEFT, RIGHT, FULL)
- **Navigation**: Method chaining through relationships with `.through()`
- **Preloading**: Separate concern from joins for eager loading

### Query Composition

Following **Ecto's composable query** philosophy:
- Queries are immutable and composable
- Method chaining for readability
- Type-safe field selectors
- Lazy evaluation until execution

### Type Safety First

- **Field Types**: Rich type system with proper Swift mappings
- **Compile-time Safety**: Catch errors at compile time, not runtime
- **Swift 6 Ready**: Full concurrency support with proper Sendable conformance

## 🧪 Testing

### Setup Test Database

```bash
# Run the setup script
./Tests/setup_test_db.sh
```

This creates tables and test data in your `spectro_test` database.

### Architecture Principle

Tests follow **separation of concerns**:
- **Database Schema**: Managed externally via setup scripts
- **Test Logic**: Focus on functionality, not infrastructure
- **Repository Configuration**: Handled by test infrastructure

Run tests:

```bash
swift test
```

## 📚 Advanced Usage

### Custom Field Types

```swift
struct UserSchema: Schema {
    @SchemaBuilder
    static var fields: [SField] {
        Field.description("metadata", .jsonb)
        Field.description("score", .float(defaultValue: 0.0))
        Field.description("created_at", .timestamp)
        Field.description("preferences", .jsonb)
    }
}
```

### Complex Queries

```swift
// Complex filtering with relationships
let powerUsers = try await UserSchema.all { query in
    query.join("posts")
         .where { $0.is_active == true && $0.age > 25 }
         .where("posts") { $0.published == true }
         .select { [$0.name, $0.email] }
         .orderBy { [$0.created_at.desc()] }
         .limit(50)
}

// Relationship navigation chains
let comments = try await UserSchema.all { query in
    query.where { $0.name.like("John%") }
         .through("posts")
         .where { $0.published == true }
         .through("comments")
         .where { $0.approved == true }
}
```

### Changesets for Data Validation

```swift
let changeset = Changeset(UserSchema.self, [
    "name": "John Doe",
    "email": "john@example.com",
    "age": 30
])

// Validate before inserting
if changeset.isValid {
    let user = try await UserSchema.create(changeset)
} else {
    print("Validation errors: \(changeset.errors)")
}
```

## 🗺️ Roadmap

### ✅ Completed
- [x] Schema definitions with relationships
- [x] Query builder with method chaining
- [x] Repository pattern implementation
- [x] Join functionality (INNER, LEFT, RIGHT, FULL)
- [x] Relationship navigation with `.through()`
- [x] Schema-level convenience API
- [x] Migration CLI
- [x] Type-safe field selectors
- [x] Swift 6 compatibility

### 🚧 In Progress
- [ ] Preload implementation (eager loading)
- [ ] Multi-table result mapping
- [ ] Query caching layer

### 📋 Planned
- [ ] Validation layer expansion
- [ ] Connection pooling optimization
- [ ] Query performance analytics
- [ ] Support for other databases (MySQL, SQLite)
- [ ] Schema introspection from existing databases
- [ ] Query logging and debugging tools

## 🤝 Contributing

We welcome contributions! Please feel free to:

- 🐛 Submit bug reports and feature requests
- 🔧 Create pull requests
- 📖 Improve documentation
- 💬 Share feedback and suggestions
- ⭐ Star the repository if you find it useful

### Development Setup

1. Clone the repository
2. Set up PostgreSQL with test databases
3. Run `./Tests/setup_test_db.sh`
4. Run tests with `swift test`

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

**Spectro** - Building the future of Swift database interactions, one query at a time. 🌈
