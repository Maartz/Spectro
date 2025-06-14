#!/bin/bash

# Run only functional tests that don't require database
echo "🧪 Running Spectro Functional Tests (No Database Required)"
echo "========================================================="

swift test --filter FunctionalTests 2>/dev/null | grep -E "(Test|passed|failed|Suite)" | grep -v "Core Spectro Functionality"

echo ""
echo "✅ Functional tests complete!"
echo ""
echo "These tests validate:"
echo "  • Schema property wrappers (@ID, @Column, etc.)"
echo "  • SchemaBuilder implementation"
echo "  • Relationship property wrappers (@HasMany, @HasOne, @BelongsTo)"
echo "  • Error handling"
echo "  • Database configuration"
echo "  • String utilities"
echo ""
echo "To run database integration tests:"
echo "  1. Start PostgreSQL"
echo "  2. createdb spectro_test"
echo "  3. swift test --filter DatabaseIntegrationTests"