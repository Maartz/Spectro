# Lessons Learned

## Swift 6 Concurrency
- All actors must be Sendable
- SpectroLazyRelation is a value type (struct) — can't use reference semantics
- Type erasure in generics prevents runtime query building

## Testing
- Tests use Swift Testing (@Suite, @Test), not XCTest
- Integration tests require live PostgreSQL
- Use TRUNCATE between tests for isolation
- Unique table names prevent test interference

## Architecture
- Query<T> is a value type — every modifier returns a new instance
- SchemaRegistry uses Mirror for field metadata
- Snake_case column mapping is automatic
- QueryCondition init is internal — factory methods using it must live in the Spectro module
- The `where` closure API uses `QueryCondition(sql:parameters:)` with `?` placeholders, not `$N`
- When adding stored closures to value types, use a private full-field initializer to enable copy methods (withLoader, withLoaded) that preserve all fields
- `repo.get(Type.self, id:)` is simpler than a query for belongs-to lookups by PK
- For struct mutating methods, verify no existing callers expect the non-mutating signature before changing

## Macro-Generated Code
- withLoader must reset loadState to .notLoaded, not preserve it. The @Schema macro init does `self.posts = []` which sets the relation to `.loaded([])`. If withLoader preserves that state, `load(using:)` short-circuits and returns the stale empty value, never calling the loader. Always reset to .notLoaded when attaching a new loader.
- The @Schema macro generates loader injection in build(from:) for relationships: hasManyLoader for @HasMany, hasOneLoader for @HasOne, belongsToLoader for @BelongsTo. These are auto-attached when entities are built from database rows.

## SQL Generation
- PostgreSQL SUM/MIN/MAX on INTEGER returns BIGINT, not DOUBLE — use CAST(... AS DOUBLE PRECISION) for aggregate results
- Always use `.quoted` for identifier quoting — never manual `"\"\(name)\""` interpolation
- SpectroError.invalidSchema requires label: `reason:`
- Guard against empty arrays in SQL generation (e.g., empty `set` in upsert produces invalid SQL)
- Dictionary `.keys` and `.values` iterate in matching order for the same instance, but this is fragile across refactors
