# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Session Initialization (mandatory)

Read these files at the start of EVERY session before doing anything:
1. Sub-project `CLAUDE.md` files for the component you're working on
2. `tasks/todo.md` — current priorities and progress
3. `tasks/lessons.md` — mistakes to avoid

---

## Critical Rules (non-negotiable)

These rules override everything else. Violations are unacceptable.

### 1. Full Development Lifecycle — implement, review, test, verify
The mandatory workflow for ANY change is:

1. **Implement** — code the changes (use team agents for parallel work on independent files)
2. **Review** — spawn a review agent to audit all modified files for bugs, missing imports, regressions
3. **Fix** — apply all fixes from the review before proceeding
4. **Test** — run the relevant test suite (`./tasks test`, `mix test`, Xcode tests)
5. **Verify** — prove it works: check logs, demonstrate correctness, run affected flows

Never skip the review step — it catches bugs that save hours of debugging.

### 2. Always Update Documentation
After ANY meaningful change:
- Update relevant `CLAUDE.md` files if architecture or patterns changed
- Update `tasks/todo.md` with progress
- Update `README.md` if user-facing behavior changed
- Update `tasks/lessons.md` after corrections

---

## Workflow Orchestration

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Agent Discipline (PROTECT YOUR CONTEXT WINDOW)
Your context window is a precious, finite resource. Every file you read, every grep result, every tool output consumes it irreversibly. **Delegate aggressively to agents.**

**Default behavior:** Before doing ANY investigation, exploration, code reading, or multi-step analysis yourself, ask: "Can an agent do this instead?" If yes, spawn one. If multiple independent investigations are needed, spawn multiple agents **in parallel** in a single message.

**Rules:**
- **NEVER read files directly** to "understand the codebase" or "investigate an issue." Spawn an Explore agent instead.
- **NEVER run grep/glob yourself** for open-ended searches. Spawn an agent.
- **Spawn agents in parallel** when tasks are independent. One message, multiple Task tool calls.
- **Your main context is for:** coordinating agents, making decisions based on their results, writing code, and talking to the user. NOT for accumulating raw file contents or search results.
- **When a task has 2+ investigation steps**, spawn an agent for each step in parallel rather than doing them sequentially yourself.
- One task per agent for focused execution.

**Anti-patterns (violations):**
- Reading 5 files yourself to "understand" something → should be one Explore agent
- Running grep, reading the matches, running more greps → should be one agent
- Investigating a bug by reading controller, service, model, route yourself → one agent
- Any chain of Read/Grep/Glob that exceeds 3 calls → you should have used an agent

**The litmus test:** If you're about to make your 3rd Read/Grep/Glob call on a single investigation thread, STOP. You should have spawned an agent.

### 3. Team-First for Complex Tasks
Use teams as often as possible. Each agent should be an **expert in its domain**:
- **Clojure agent** — emotion-engine changes, XTDB queries, ML pipeline
- **Elixir agent** — Phoenix API, channels, GenServer, Ecto migrations
- **Swift agent** — SwiftUI views, MusicKit, WebSocket client
- **Review agent** — audit all modified files for bugs, regressions, style
- **Explore agent** — codebase research, architecture discovery

Spawn teams for any task touching 2+ components. Assign domain expertise. Coordinate from main context.

### 4. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start

### 5. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 6. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes — don't over-engineer
- Challenge your own work before presenting it

### 7. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests → then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management
1. **Plan First**: Write plan to `tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review to `tasks/todo.md`
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections

## Core Principles
- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.



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
- `PrimaryKeyType` protocol (`Sources/Spectro/Core/Protocols/PrimaryKeyType.swift`) — UUID, Int, String conformances; provides `toPostgresData()`, `fromPostgresData()`, `defaultValue`, `fieldType`
- `PrimaryKeyWrapperProtocol` / `ForeignKeyWrapperProtocol` — marker protocols for Mirror-based type checking of generic `ID<T>` and `ForeignKey<T>`
- `SchemaBuilder` adds `static func build(from: [String: Any]) -> Self` for reflection-free row mapping
- `SchemaMapper` converts `PostgresRow` to Swift structs
- Property wrappers in `Sources/Spectro/SchemaBuilder/PropertyWrappers.swift`:
  - `@ID<T: PrimaryKeyType>` — generic primary key (UUID, Int, String)
  - `@Column<T>` — with optional column name override: `@Column("display_name")`
  - `@Timestamp`, `@ForeignKey<T: PrimaryKeyType>` — with optional column name override
  - `@HasMany<T>`, `@HasOne<T>`, `@BelongsTo<T>` — with optional FK binding: `@HasMany(foreignKey: "author_id")`
  - `@ManyToMany<T>` — junction table relationships
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
