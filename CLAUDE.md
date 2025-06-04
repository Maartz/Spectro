# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Spectro is a Swift ORM for PostgreSQL heavily inspired by Elixir's Ecto library. It provides type-safe schema definitions, an expressive query builder, database migrations, and a repository pattern implementation built on top of NIO and PostgresKit.

## Common Commands

```bash
# Build the project
swift build

# Run tests
swift test

# Build release version
swift build -c release

# Build and run the CLI tool
swift run spectro

# Clean build artifacts
swift package clean

# Database CLI commands
swift run spectro database create
swift run spectro database drop

# Migration CLI commands
swift run spectro migrate generate <name>
swift run spectro migrate up
swift run spectro migrate down
swift run spectro migrate status
```

## Architecture

The project is organized into three main packages:

### SpectroCore
Core types and enums without external dependencies:
- `DatabaseError`, `MigrationError`, `MigrationStatus` enums
- String extensions for case conversion
- Basic types like `Inflector` and `MigrationFile`

### Spectro (Main Library)
The main ORM library with:
- **Core/**: Database operations, migration management, protocols
- **Query/**: Query builder implementation with composable conditions
- **Repository/**: Repository pattern with PostgreSQL implementation
- **SchemaBuilder/**: DSL for defining schemas using `@resultBuilder`

### SpectroCLI
Command-line interface for database and migration operations.

## Key Design Patterns

1. **Schema Pattern**: Define database schemas as Swift structs implementing the `Schema` protocol with a DSL:
   ```swift
   struct UserSchema: Schema {
       static let schemaName = "users"
       @SchemaBuilder
       static var fields: [SField] { ... }
   }
   ```

2. **Query Builder**: Type-safe, composable query construction:
   ```swift
   Query.from(UserSchema.self)
       .select { [$0.name, $0.email] }
       .where { $0.age > 25 }
   ```

3. **Repository Pattern**: Abstract database operations through `Repository` protocol with `PostgresRepository` implementation

4. **Migration System**: File-based migrations with timestamp versioning in `migrations/` directory

## Environment Configuration

The project uses `.env` files for database configuration:
```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=your_database
DB_USER=your_username
DB_PASSWORD=your_password
```

## Current Development Status

The project is actively being refactored to implement a new repository layer similar to Ecto's design. Recent commits show work on:
- Implementing a new repo layer (PostgresRepo.swift)
- Adding changeset functionality for data validation
- Migration from Swift 5.8 to 6.1

Tests are currently commented out, likely due to ongoing refactoring work.