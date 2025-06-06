# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Spectro is a modern Swift ORM for PostgreSQL inspired by Elixir's Ecto, providing type-safe database interactions with a dual-API approach (Repository pattern + ActiveRecord-style convenience methods).

## Common Development Commands

```bash
# Build the project
swift build

# Run all tests
swift test

# Run specific test
swift test --filter TestClassName

# Build and run CLI
swift build && ./.build/debug/spectro --help

# Setup test database
./Tests/setup_test_db.sh

# Migration commands
spectro migrate generate <name>    # Create new migration
spectro migrate up                 # Apply migrations
spectro migrate down               # Rollback last migration
spectro migrate status             # Check migration status

# Database commands  
spectro database create            # Create database
spectro database drop              # Drop database
```

## Architecture Overview

### Core Components

1. **Schema Protocol** - Defines table structure using @SchemaBuilder DSL
   - Located in: `Sources/Spectro/Core/Protocols/Schema.swift`
   - Extensions provide Repository methods, relationships, and model functionality
   - Supports dynamic member lookup for field access

2. **Repository Pattern** - Data access layer with CRUD operations
   - Protocol: `Sources/Spectro/Repository/Repo.swift`
   - Implementation: `Sources/Spectro/Repository/PostgresRepo.swift`
   - Global configuration via `RepositoryConfiguration`

3. **Query System** - Composable, immutable query builder
   - Main class: `Sources/Spectro/Query/Query.swift`
   - Supports joins, filtering, ordering, pagination, preloading
   - Navigation through relationships via `.through()`

4. **Migration System** - Database version control
   - Manager: `Sources/Spectro/Core/Migration/MigrationManager.swift`
   - CLI: `Sources/SpectroCLI/Commands/Migration/`
   - Migrations stored in `migrations/` with timestamp prefixes

5. **Connection Management** - Built on Swift NIO
   - Entry point: `Sources/Spectro/Spectro.swift`
   - Uses PostgresKit for async/await PostgreSQL operations

### Key Design Patterns

- **Dual API Approach**: Repository pattern for control + Schema-level convenience methods
- **Immutable Queries**: All query methods return new instances for composition
- **Type Safety**: Compile-time field validation using Swift's type system
- **Relationship Handling**: First-class support for hasMany, hasOne, belongsTo relationships
- **Swift 6 Ready**: Full concurrency support with Sendable conformance

### Testing Strategy

- External database setup via `setup_test_db.sh` rather than in-code migrations
- Test database configured through environment variables
- Functional tests in `Tests/SpectroTests/` cover core functionality
- Separate test files for joins, migrations, and preloading

### Environment Configuration

Create `.env` file with:
```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=your_app_db
DB_USER=your_username
DB_PASSWORD=your_password
TEST_DB_NAME=your_app_test_db
```

### Migration Files

Generated in `migrations/` directory with format:
- `YYYYMMDDHHMMSS_migration_name_up.sql`
- `YYYYMMDDHHMMSS_migration_name_down.sql`

Tracked in `schema_migrations` table in database.