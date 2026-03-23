# Spectro

A Swift ORM for PostgreSQL, inspired by Elixir's Ecto. Property-wrapper schemas, composable query builder, actor-based concurrency, and a CLI for migrations.

## Features

- **Property-wrapper schema definitions** &mdash; `@ID`, `@Column`, `@Timestamp`, `@ForeignKey`, `@HasMany`, `@HasOne`, `@BelongsTo`
- **`@Schema` macro** &mdash; generates `SchemaBuilder` conformance at compile time (zero boilerplate)
- **Immutable query builder** &mdash; `Query<T>` is a value type; every `.where()`, `.join()`, `.orderBy()` returns a new query
- **Relationship preloading** &mdash; batch-loads relationships to prevent N+1 queries
- **Actor-based connection pooling** &mdash; built on SwiftNIO and PostgresKit
- **Transaction support** &mdash; `READ COMMITTED` isolation with automatic rollback on error
- **Plain SQL migrations** &mdash; timestamped `.sql` files with `-- migrate:up` / `-- migrate:down` markers
- **CLI tool** &mdash; `spectro` binary for database creation, migrations, and status
- **Swift 6 strict concurrency** &mdash; full `Sendable` compliance

## Requirements

- Swift 6.0+ (managed via `mise.toml`)
- macOS 13+
- PostgreSQL

## Installation

### Via Mint (recommended)

```bash
mint install Maartz/Spectro
```

Pin a version in your `Mintfile`:

```
Maartz/Spectro@main
```

### As a Swift Package dependency

```swift
.package(url: "https://github.com/Maartz/Spectro.git", from: "0.3.0")
```

Then add `"SpectroKit"` to your target's dependencies.

## Quick Start

### Define a schema

```swift
import Spectro

@Schema("users")
struct User {
    @ID        var id: UUID
    @Column    var name: String = ""
    @Column    var email: String = ""
    @Timestamp var createdAt: Date = Date()
}
```

The `@Schema` macro generates `Schema` and `SchemaBuilder` conformance at compile time.

### Connect and query

```swift
let spectro = try Spectro(
    hostname: "localhost",
    username: "postgres",
    password: "postgres",
    database: "myapp_dev"
)

// Insert
let user = try await spectro.insert(User())

// Query
let repo = spectro.repository()
let activeUsers = try await repo.query(User.self)
    .where { $0.name == "John" }
    .orderBy { $0.createdAt }
    .limit(10)
    .all()

// Get by ID
let user = try await spectro.get(User.self, id: someUUID)

// Update
let updated = try await spectro.update(User.self, id: someUUID, changes: ["name": "Jane"])

// Delete
try await spectro.delete(User.self, id: someUUID)

// Transaction
let result = try await spectro.transaction { repo in
    let user = try await repo.insert(newUser)
    let profile = try await repo.insert(newProfile)
    return (user, profile)
}

// Shutdown
await spectro.shutdown()
```

### Relationships

```swift
@Schema("posts")
struct Post {
    @ID         var id: UUID
    @Column     var title: String = ""
    @ForeignKey var userId: UUID
    @Timestamp  var createdAt: Date = Date()
    @BelongsTo  var user: User?
}

@Schema("users")
struct User {
    @ID        var id: UUID
    @Column    var name: String = ""
    @HasMany   var posts: [Post]
    @Timestamp var createdAt: Date = Date()
}

// Preload relationships (2 queries, not N+1)
let users = try await repo.query(User.self)
    .preload(\.$posts)
    .all()
```

### Joins

```swift
let results = try await repo.query(User.self)
    .join(Post.self, on: { $0.left.id == $0.right.userId })
    .where { $0.name == "John" }
    .all()
```

### Query operators

```swift
// Comparison
.where { $0.age >= 18 && $0.age <= 65 }

// String patterns (case-sensitive and insensitive)
.where { $0.name.iContains("john") }      // ILIKE '%john%'
.where { $0.email.endsWith("@gmail.com") } // LIKE '%@gmail.com'

// Collection
.where { $0.status.in(["active", "pending"]) }
.where { $0.age.between(18, and: 65) }

// Null checks
.where { $0.deletedAt.isNull() }

// Date convenience
.where { $0.createdAt.isThisMonth() }

// Complex logic
.where { ($0.role == "admin" || $0.role == "moderator") && $0.isActive == true }
```

Available operators:
- Comparison: `==`, `!=`, `>`, `>=`, `<`, `<=`
- String: `.like()`, `.ilike()`, `.notLike()`, `.notIlike()`, `.contains()`, `.startsWith()`, `.endsWith()`, `.iContains()`, `.iStartsWith()`, `.iEndsWith()`
- Collection: `.in()`, `.notIn()`, `.between()`
- Null: `.isNull()`, `.isNotNull()`
- Date: `.before()`, `.after()`, `.isToday()`, `.isThisWeek()`, `.isThisMonth()`, `.isThisYear()`
- Logical: `&&` (AND), `||` (OR), `!` (NOT)

## CLI Reference

```
spectro database create    Create a new PostgreSQL database
spectro database drop      Drop an existing database
spectro migrate up         Run all pending migrations
spectro migrate down       Rollback applied migrations
spectro migrate status     Show migration status
spectro generate migration <name>   Generate a new SQL migration file
```

All commands accept `--username`, `--password`, and `--database` flags. Values are resolved in order: CLI flags > `.env` file > environment variables > defaults.

### Migration files

Migrations are plain SQL in `Sources/Migrations/`:

```sql
-- migrate:up
CREATE TABLE "users" (
    "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL DEFAULT '',
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- migrate:down
DROP TABLE "users";
```

## Architecture

Spectro is organized into four targets:

| Target | Product | Role |
|---|---|---|
| `SpectroCore` | `SpectroCore` | Shared types (zero external deps) |
| `SpectroMacros` | Compiler plugin | `@Schema` macro |
| `Spectro` | `SpectroKit` | Core ORM library |
| `SpectroCLI` | `spectro` | CLI executable |

Three actors manage concurrency: `DatabaseConnection` (pool/queries), `GenericDatabaseRepo` (CRUD), and `SchemaRegistry` (metadata cache). All query types are `Sendable` value types.

See [docs/architecture.html](docs/architecture.html) for the full architecture reference with diagrams.

## Configuration

Create a `.env` file in your project root:

```
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=myapp_dev
```

Or use environment variables directly, or initialize `Spectro` with explicit parameters.

## Development

```bash
# Build
swift build

# Build release
swift build -c release

# Build CLI only
swift build --product spectro

# Run tests (requires PostgreSQL)
./Tests/setup_test_db.sh     # one-time setup
swift test

# Run a specific test suite
swift test --filter CoreFunctionalTests
```

## License

MIT
