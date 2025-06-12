#!/bin/bash

# Database setup script for Spectro tests
# This script creates the test database and necessary extensions

set -e

# Configuration
DB_HOST=${DB_HOST:-localhost}
DB_PORT=${DB_PORT:-5432}
DB_USER=${DB_USER:-postgres}
DB_PASSWORD=${DB_PASSWORD:-postgres}
TEST_DB_NAME=${TEST_DB_NAME:-spectro_test}

echo "Setting up Spectro test database..."
echo "Host: $DB_HOST:$DB_PORT"
echo "User: $DB_USER"
echo "Test Database: $TEST_DB_NAME"

# Function to run psql commands
run_psql() {
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d postgres -c "$1"
}

run_psql_db() {
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $TEST_DB_NAME -c "$1"
}

# Check if PostgreSQL is running
echo "Checking PostgreSQL connection..."
if ! PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
    echo "Error: Cannot connect to PostgreSQL at $DB_HOST:$DB_PORT with user $DB_USER"
    echo "Please ensure PostgreSQL is running and credentials are correct."
    exit 1
fi

echo "PostgreSQL connection successful!"

# Drop existing test database if it exists
echo "Dropping existing test database if it exists..."
run_psql "DROP DATABASE IF EXISTS $TEST_DB_NAME;"

# Create test database
echo "Creating test database: $TEST_DB_NAME"
run_psql "CREATE DATABASE $TEST_DB_NAME;"

# Connect to test database and set up extensions
echo "Setting up database extensions..."
run_psql_db "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"

# Create basic tables (these will be recreated by tests but good for manual testing)
echo "Creating base tables..."

# Users table
run_psql_db "
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    age INTEGER,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);"

# Products table
run_psql_db "
CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    price DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    stock INTEGER NOT NULL DEFAULT 0,
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);"

# Tags table
run_psql_db "
CREATE TABLE IF NOT EXISTS tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    color TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);"

# Posts table (depends on users)
run_psql_db "
CREATE TABLE IF NOT EXISTS posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    published BOOLEAN DEFAULT false,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);"

# Comments table (depends on posts and users)
run_psql_db "
CREATE TABLE IF NOT EXISTS comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content TEXT NOT NULL,
    approved BOOLEAN DEFAULT false,
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);"

# Profiles table (depends on users)
run_psql_db "
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    language TEXT DEFAULT 'en',
    opt_in_email BOOLEAN DEFAULT false,
    verified BOOLEAN DEFAULT false,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);"

# Post tags junction table (depends on posts and tags)
run_psql_db "
CREATE TABLE IF NOT EXISTS post_tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(post_id, tag_id)
);"

# Create indexes for better performance
echo "Creating indexes..."
run_psql_db "CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);"
run_psql_db "CREATE INDEX IF NOT EXISTS idx_users_is_active ON users(is_active);"
run_psql_db "CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);"
run_psql_db "CREATE INDEX IF NOT EXISTS idx_posts_published ON posts(published);"
run_psql_db "CREATE INDEX IF NOT EXISTS idx_comments_post_id ON comments(post_id);"
run_psql_db "CREATE INDEX IF NOT EXISTS idx_comments_user_id ON comments(user_id);"
run_psql_db "CREATE INDEX IF NOT EXISTS idx_products_active ON products(active);"
run_psql_db "CREATE INDEX IF NOT EXISTS idx_products_price ON products(price);"

echo "Database setup complete!"
echo ""
echo "Test database '$TEST_DB_NAME' is ready for Spectro tests."
echo "You can now run: swift test"
echo ""
echo "To manually connect to the test database:"
echo "PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $TEST_DB_NAME"