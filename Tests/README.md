# Spectro Tests

This directory contains comprehensive tests for the Spectro ORM, covering all major functionality including generic type mapping, CRUD operations, query system, and error handling.

## Test Setup

### Prerequisites

1. **PostgreSQL** - Install and run PostgreSQL server
2. **Database Access** - Ensure you can connect with user `postgres` and password `postgres`

### Quick Setup

```bash
# Run the setup script
./Tests/setup_schema.sh

# Run all tests
swift test
```

### Manual Setup

If you need custom database configuration:

```bash
# Set environment variables
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=postgres
export DB_PASSWORD=your_password
export TEST_DB_NAME=spectro_test

# Run setup
./Tests/setup_schema.sh
```

## Test Structure

### Test Suites

1. **BasicTests.swift** - Basic Spectro instance and connection tests
2. **GenericMappingTests.swift** - SchemaRegistry metadata extraction tests
3. **GenericCRUDTests.swift** - Full CRUD operations with multiple schema types
4. **QuerySystemTests.swift** - Comprehensive query system testing
5. **SchemaBuilderTests.swift** - SchemaBuilder pattern validation
6. **ErrorHandlingTests.swift** - Error cases and edge conditions

### Test Database Management

Tests use a shared database state managed by `TestDatabaseState` actor:

- **Serialized execution** - Tests run sequentially to avoid conflicts
- **Automatic cleanup** - Each test cleans data before running
- **Schema recreation** - Tables are dropped/recreated as needed

### Test Schemas

The tests use several schema types to validate generic functionality:

- **User** - Basic user with email, age, timestamps
- **Product** - E-commerce product with price, stock, description  
- **Post** - Blog post with foreign key to User
- **Comment** - Comment with foreign keys to Post and User
- **Tag** - Simple tag for many-to-many relationships

## Test Coverage

### Phase 1: Generic Type Mapping ✅
- [x] SchemaRegistry metadata extraction
- [x] SchemaBuilder pattern for any schema type
- [x] Generic repository operations
- [x] Property wrapper reflection

### Phase 2: Comprehensive Test Coverage ✅
- [x] CRUD operations for multiple schema types
- [x] Query system with where/order/limit/offset
- [x] Transaction support
- [x] Error handling and edge cases
- [x] Concurrent operations
- [x] Foreign key relationships

### Phase 3: Core ORM Features (Pending)
- [ ] Tuple query implementation
- [ ] Real transaction support with rollback
- [ ] Relationship loading (@HasMany, @HasOne, @BelongsTo)
- [ ] JOIN query execution

### Phase 4: Advanced Features (Pending)
- [ ] Query optimization and caching
- [ ] Migration generation from schemas
- [ ] Connection pooling configuration
- [ ] PostgreSQL-specific features

## Running Specific Tests

```bash
# Run only basic tests
swift test --filter BasicSpectroTests

# Run CRUD tests
swift test --filter GenericCRUDTests

# Run query tests
swift test --filter QuerySystemTests

# Run error handling tests
swift test --filter ErrorHandlingTests
```

## Test Data

Tests use unique identifiers to avoid conflicts:

```swift
// Generate unique email addresses
let email = TestDatabase.uniqueEmail("test") // test.1640995200.abc123@example.com
```

## Debugging Tests

### View Test Database

```bash
# Connect to test database
PGPASSWORD=postgres psql -h localhost -p 5432 -U postgres -d spectro_test

# List tables
\dt

# View table structure
\d users

# View test data
SELECT * FROM users;
```

### Test Isolation

Each test suite is marked with `.serialized` to ensure tests don't interfere with each other. Individual tests clean their data using:

```swift
try await TestDatabase.cleanTables(using: repo)
```

## Adding New Tests

When adding new test files:

1. Import the test framework and Spectro
```swift
import Foundation
import Testing
@testable import Spectro
```

2. Mark test suites as serialized for database tests
```swift
@Suite("My Test Suite", .serialized)
struct MyTests {
    // tests here
}
```

3. Clean data before each test
```swift
@Test("My test")
func testSomething() async throws {
    let spectro = try await TestDatabaseState.getSharedSpectro()
    let repo = spectro.repository()
    
    // Clean data first
    try await TestDatabase.cleanTables(using: repo)
    
    // Test implementation
}
```

4. Use unique identifiers for test data
```swift
let user = User(name: "Test User", email: TestDatabase.uniqueEmail("mytest"), age: 25)
```

## Performance Testing

For performance tests, use larger datasets:

```swift
// Insert many records
for i in 1...1000 {
    let user = User(name: "User \(i)", email: TestDatabase.uniqueEmail("perf\(i)"), age: 20 + i)
    _ = try await repo.insert(user)
}
```

But be mindful of CI/CD environments - keep test data reasonable for automation.

## Continuous Integration

The test suite is designed to work in CI environments:

- Uses standard PostgreSQL configuration
- Automatically sets up and tears down test database
- No external dependencies beyond PostgreSQL
- Fast execution with proper test isolation