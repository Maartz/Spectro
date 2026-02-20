# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Spectro is a Swift ORM for PostgreSQL, inspired by Elixir's Ecto. It provides:
- Property-wrapper-based schema definition (`@ID`, `@Column`, `@HasMany`, etc.)
- An immutable, composable query builder (`Query<T>`)
- Actor-based connection pooling (SwiftNIO + PostgresKit)
- A `spectro` CLI for migrations and database management

Swift 6.1 is required (managed via `mise.toml`).

## Installing the CLI

The `spectro` CLI is distributed via [Mint](https://github.com/yonaskolb/Mint):

```bash
# Install globally
mint install Maartz/Spectro

# Run
spectro migrate generate CreateUsers
spectro migrate up
spectro migrate down
spectro migrate status
spectro database create --database myapp_dev
spectro database drop   --database myapp_dev
```

To pin the version in a project, add to `Mintfile`:
```
Maartz/Spectro@<tag>
```

## Commands (development)

```bash
# Build
swift build
swift build -c release
swift build --product spectro       # CLI only

# Test (requires live PostgreSQL — set env vars first)
./Tests/setup_test_db.sh            # one-time database provisioning
swift test
swift test --filter CoreFunctionalTests   # run specific suite

# CLI (from source, before installing via Mint)
./.build/debug/spectro migrate generate <MigrationName>
./.build/debug/spectro migrate up
./.build/debug/spectro migrate down
./.build/debug/spectro migrate status
```

Integration tests require these env vars:
```
DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD, TEST_DB_NAME
```

## Package Structure

| Target | Product | Role |
|---|---|---|
| `SpectroCore` | `SpectroCore` | Shared types (no external deps): `Inflector`, `MigrationFile`, `MigrationRecord`, error enums |
| `Spectro` | `SpectroKit` | Main ORM library |
| `SpectroCLI` | `spectro` | CLI executable (ArgumentParser-based) |

## Architecture

### Core Actors
- `DatabaseConnection` (`Sources/Spectro/Core/Database/DatabaseConnection.swift`) — wraps an NIO `EventLoopGroupConnectionPool`; bridges futures to async/await via `withCheckedThrowingContinuation`
- `GenericDatabaseRepo` (`Sources/Spectro/Repository/GenericDatabaseRepo.swift`) — implements the `Repo` protocol; primary CRUD layer
- `SchemaRegistry` (`Sources/Spectro/Core/Schema/SchemaRegistry.swift`) — singleton actor; inspects schema types via `Mirror`; stores field metadata

### Schema System
- `Schema` protocol requires `tableName: String` and `init()` (`Sources/Spectro/Core/Protocols/Schema.swift`)
- `SchemaBuilder` adds `static func build(from: [String: Any]) -> Self` for reflection-free row mapping
- `SchemaMapper` converts `PostgresRow` to Swift structs
- Property wrappers in `Sources/Spectro/SchemaBuilder/PropertyWrappers.swift`: `@ID`, `@Column<T>`, `@Timestamp`, `@ForeignKey`, `@HasMany<T>`, `@HasOne<T>`, `@BelongsTo<T>`
- `SpectroLazyRelation<T>` backs all relationship wrappers with a state machine: `notLoaded → loading → loaded(T)`

### Query Builder
- `Query<T: Schema>` (`Sources/Spectro/Query/Query.swift`) is a **value type** — every `.where()`, `.join()`, `.orderBy()`, `.limit()` etc. returns a new `Query<T>`; safe to branch and reuse intermediate queries
- Terminal methods: `.all()`, `.first()`, `.firstOrFail()`, `.count()`
- `QueryField<V>` supports operators: `==`, `!=`, `>`, `<`, `.contains()`, `.ilike()`, `.in()`, `.between()`, `.isNull()`

### Migration System
- Migrations are **plain SQL files**, placed in `Sources/Migrations/`, named `YYYYMMDDHHMMSS_<name>.sql`
- Each file uses `-- migrate:up` / `-- migrate:down` section markers:
  ```sql
  -- migrate:up
  CREATE TABLE "users" (...);

  -- migrate:down
  DROP TABLE "users";
  ```
- `MigrationManager` (`Sources/Spectro/Core/Migration/MigrationManager.swift`) discovers, parses, and runs them
- `SQLStatementParser` splits SQL at semicolons, handling dollar-quotes, inline `--` comments, and `/* */` block comments
- Migration status tracked in `schema_migrations` table (uses a `migration_status` Postgres enum)

### Public Facade
- `Spectro.swift` (`Sources/Spectro/Spectro.swift`) is the entry point: `Spectro(config:)` → `.repository()` → `Repo` actor or convenience CRUD methods directly on `Spectro`

## Key Conventions
- All actors (`DatabaseConnection`, `GenericDatabaseRepo`, `SchemaRegistry`) are `Sendable`
- Snake_case column mapping: `String+Case.swift` in `SpectroCore` (e.g., `createdAt` → `created_at`)
- Prefer `SchemaBuilder.build(from:)` over Mirror reflection when performance matters
- Tests use **Swift Testing** (`@Suite`, `@Test`) — not XCTest
