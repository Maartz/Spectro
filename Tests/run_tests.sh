#!/bin/bash

# Spectro Test Runner
# This script sets up and runs tests for the Spectro ORM

set -e

echo "🧪 Spectro Test Suite"
echo "===================="

# Check if PostgreSQL is running
if ! pg_isready -q; then
    echo "❌ PostgreSQL is not running. Please start PostgreSQL first."
    echo "   On macOS: brew services start postgresql"
    echo "   Or use Postgres.app"
    exit 1
fi

# Create test database if it doesn't exist
echo "📦 Setting up test database..."
if ! psql -lqt | cut -d \| -f 1 | grep -qw spectro_test; then
    echo "   Creating spectro_test database..."
    createdb spectro_test || {
        echo "❌ Failed to create test database. Make sure you have permissions."
        exit 1
    }
fi

# Run tests based on argument
if [ "$1" = "unit" ]; then
    echo "🔧 Running unit tests only (no database required)..."
    swift test --filter FunctionalTests
elif [ "$1" = "integration" ]; then
    echo "🔌 Running integration tests (database required)..."
    swift test --filter DatabaseIntegrationTests
elif [ "$1" = "all" ]; then
    echo "🚀 Running all tests..."
    swift test
else
    echo "📋 Running functional tests (no database)..."
    swift test --filter FunctionalTests
    echo ""
    echo "To run other test suites:"
    echo "  ./Tests/run_tests.sh unit        # Unit tests only"
    echo "  ./Tests/run_tests.sh integration # Database integration tests"
    echo "  ./Tests/run_tests.sh all         # All tests"
fi

echo ""
echo "✅ Test run complete!"