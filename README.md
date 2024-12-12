# Spectro 🌈

> **Note**: Spectro is currently a work in progress. APIs and functionality may change as we continue development.

A Swift ORM for PostgreSQL that prioritizes type safety and developer experience. Spectro is heavily inspired by Elixir's Ecto library, bringing its elegant design patterns and robust functionality to the Swift ecosystem. The project provides an elegant query builder, schema definitions with relationships, and database migrations through a convenient CLI.

## Features

- 🏗️ Type-safe schema definitions with relationships
- 🔍 Expressive query builder (inspired by Ecto's composable queries)
- 🔄 Database migrations with CLI support
- 📦 Repository pattern implementation
- ⚡️ Built on top of NIO and PostgresKit
- 🔐 Environment-based configuration

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/spectro.git", from: "0.1.0")
]
```

## Quick Start

### Configuration

Create a .env file in your project root:

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=your_database
DB_USER=your_username
DB_PASSWORD=your_password
```

Make sure to add .env to your .gitignore file to keep your credentials secure.


### Define Your Schema

```swift
struct UserSchema: Schema {
    static let schemaName = "users"
    
    @SchemaBuilder
    static var fields: [SField] {
        Field.description("name", .string)
        Field.description("email", .string)
        Field.description("age", .integer(defaultValue: 0))
        Field.description("is_active", .boolean(defaultValue: true))
        Field.hasMany("posts", PostSchema.self)
        Field.hasOne("profile", ProfileSchema.self)
    }
}

struct PostSchema: Schema {
    static let schemaName = "posts"
    
    @SchemaBuilder
    static var fields: [SField] {
        Field.description("Title", .string)
        Field.description("Content", .string)
        Field.belongsTo("users", UserSchema.self)
    }
}
```

### Query Builder

```swift
// Select specific fields with conditions
let query = Query.from(UserSchema.self)
    .select { [$0.name, $0.email] }
    .where { $0.age > 25 && $0.is_active == true }
    .orderBy { [$0.name.asc()] }
    .limit(10)

let results = try await repository.all(query: query)

// Insert new records
try await repository.insert(
    into: "users",
    values: [
        "name": "John Doe",
        "email": "john@example.com",
        "age": 30
    ]
)

// Update records
try await repository.update(
    table: "users",
    values: ["is_active": false],
    where: ["email": ("=", "john@example.com")]
)
```

### Migrations CLI

```bash
# Generate a new migration
spectro migrate generate add_users_table

# Run migrations
spectro migrate up

# Rollback last migration
spectro migrate down
```

## Contributing

Contributions are welcome! Feel free to:

- Submit bug reports and feature requests
- Create pull requests
- Improve documentation
- Share feedback

## Coming Soon

- [ ] More relationship types
- [ ] Advanced query capabilities (joins, etc.)
- [ ] Eager loading
- [ ] Validation layer
- [ ] More database drivers
- [ ] Query caching
- [ ] Support other databases

## License

MIT License - see LICENSE file for details
