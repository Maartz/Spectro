# ``Spectro``

A modern Swift ORM for PostgreSQL inspired by Elixir's Ecto, providing type-safe database interactions with implicit lazy relationships.

## Overview

Spectro is a revolutionary Swift ORM that brings the power and elegance of Elixir's Ecto to iOS and macOS development. Built with Swift 6 concurrency in mind, Spectro provides a dual-API approach combining the Repository pattern for control with ActiveRecord-style convenience methods for rapid development.

### Key Features

- **Implicit Lazy Relationships**: Relationships appear as normal Swift properties but are lazy by default, preventing N+1 query issues
- **Type-Safe Query Builder**: Compose queries using closure syntax with compile-time field validation
- **Property Wrapper DSL**: Define schemas using clean, declarative syntax
- **Ecto-Inspired Design**: Familiar patterns for developers coming from Elixir/Phoenix
- **Swift 6 Ready**: Full concurrency support with proper Sendable conformance
- **PostgreSQL Native**: Built specifically for PostgreSQL with full feature support

## Getting Started

### Basic Schema Definition

Define your database schemas using property wrappers:

```swift
public struct User: Schema, SchemaBuilder {
    public static let tableName = "users"
    
    @ID public var id: UUID
    @Column public var name: String = ""
    @Column public var email: String = ""
    @Column public var age: Int = 0
    @Timestamp public var createdAt: Date = Date()
    
    public init() {}
}
```

### Connecting to Database

```swift
let config = DatabaseConfiguration(
    hostname: "localhost",
    port: 5432,
    username: "postgres",
    password: "password",
    database: "myapp_dev"
)

let spectro = try Spectro(configuration: config)
let repo = spectro.repository()
```

### Basic CRUD Operations

```swift
// Create
var user = User(name: "John Doe", email: "john@example.com", age: 30)
user = try await repo.insert(user)

// Read
let users = try await repo.all(User.self)
let user = try await repo.get(User.self, id: userId)

// Update
let updatedUser = try await repo.update(User.self, id: userId, changes: [
    "age": 31
])

// Delete
try await repo.delete(User.self, id: userId)
```

## Topics

### Essential Components

- ``Schema``
- ``SchemaBuilder``
- ``Spectro``
- ``DatabaseConfiguration``

### Repository Pattern

- ``Repo``
- ``GenericDatabaseRepo``
- ``DatabaseRepo``

### Query System

- ``Query``
- ``QueryBuilder``
- ``QueryCondition``
- ``TupleQuery``

### Relationship Loading

- ``SpectroLazyRelation``
- ``RelationshipLoader``
- ``PreloadQuery``

### Property Wrappers

- ``ID``
- ``Column``
- ``ForeignKey``
- ``Timestamp``
- ``HasMany``
- ``HasOne``
- ``BelongsTo``

### Schema Registry

- ``SchemaRegistry``
- ``SchemaMetadata``
- ``SchemaMapper``

### Error Handling

- ``SpectroError``

### Extensions

- ``String``
- ``StringProtocol``