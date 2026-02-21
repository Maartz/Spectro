# Spectro ORM - Current Sprint

## Four Workstreams — COMPLETE

### Workstream 1: Fix SpectroLazyRelation.load(using:)
- [x] Add stored type-erased loader closure
- [x] Add factory methods (hasManyLoader, hasOneLoader, belongsToLoader)
- [ ] Update SchemaMacro to inject loader closures (deferred — separate workstream)
- [x] Delete unused stub methods (loadHasMany, loadHasOne, loadBelongsTo, loadManyToMany)
- [x] Add withLoader(_:) copy method for loader injection
- [x] Rewrite load(using:) to use stored loader with proper state transitions
- [x] Preserve loader in withLoaded(_:) copies

### Workstream 2: Clean Up Dead Code
- [x] Delete DatabaseRepo.swift
- [x] Remove `extension DatabaseRepo` block from Query.swift
- [x] Fix fromSync(row:) in SchemaBuilder.swift

### Workstream 3: Upsert + Bulk Insert
- [x] Create ConflictTarget type
- [x] Add upsert/insertAll to Repo protocol
- [x] Implement in GenericDatabaseRepo
- [x] Add convenience facades in Spectro.swift

### Workstream 4: Aggregate Queries
- [x] Add buildAggregateSQL helper to Query
- [x] Add sum/avg/min/max terminal methods

### Phase 4: Tests
- [x] Tests for upsert (3 tests)
- [x] Tests for bulk insert (4 tests)
- [x] Tests for aggregates (6 tests)
- [x] Tests for lazy loading (11 tests: 5 unit + 6 integration)

### Phase 5: Review
- [x] Review agent audited all changes
- [x] Fixed FK quoting in loader factories (use .quoted)
- [x] Added empty set guard in upsert

### SchemaMacro Loader Injection
- [x] @Schema macro auto-injects loader closures in build(from:) for @HasMany, @HasOne, @BelongsTo
- [x] Fix withLoader to reset loadState to .notLoaded (prevents stale cached defaults from init)
- [x] Integration tests for auto-injected loaders (4 tests in MacroLoaderInjectionTests)

## Future Work
- [ ] Test coverage for .constraint(...) conflict target
- [ ] Type-safe aggregate API with QueryField overloads
- [ ] Grouped aggregates (GROUP BY)
