#!/bin/bash

# Setup test database for Spectro tests
echo "Setting up Spectro test database..."

# Database configuration
DB_NAME="spectro_test"
DB_USER="postgres"
DB_PASS="postgres"

# Create database if it doesn't exist
psql -U $DB_USER -c "CREATE DATABASE $DB_NAME;" 2>/dev/null || echo "Database already exists"

# Create tables
psql -U $DB_USER -d $DB_NAME << EOF
-- Drop existing tables
DROP TABLE IF EXISTS comments CASCADE;
DROP TABLE IF EXISTS posts CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Create users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    age INTEGER DEFAULT 0,
    password TEXT NOT NULL,
    score DOUBLE PRECISION,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    login_count INT DEFAULT 0,
    last_login_at TIMESTAMPTZ,
    preferences JSONB DEFAULT '{}'::jsonb
);

-- Create posts table
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    published BOOLEAN DEFAULT false,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

-- Create profiles table
CREATE TABLE profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    language TEXT,
    opt_in_email TEXT,
    verified BOOLEAN DEFAULT false,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Create comments table
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content TEXT NOT NULL,
    approved BOOLEAN DEFAULT false,
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Insert test data
INSERT INTO users (id, name, email, age, password, score, is_active, created_at, login_count) VALUES
    ('123e4567-e89b-12d3-a456-426614174000', 'John Doe', 'john@example.com', 25, 'password123', 85.5, true, NOW(), 0),
    ('987fcdeb-51a2-43d7-9b18-315274198000', 'Jane Doe', 'jane@example.com', 30, 'password456', 92.5, true, NOW(), 5);

INSERT INTO posts (id, title, content, published, user_id) VALUES
    ('11111111-1111-1111-1111-111111111111', 'First Post', 'Content of first post', true, '123e4567-e89b-12d3-a456-426614174000'),
    ('22222222-2222-2222-2222-222222222222', 'Second Post', 'Content of second post', false, '123e4567-e89b-12d3-a456-426614174000'),
    ('33333333-3333-3333-3333-333333333333', 'Third Post', 'Content of third post', true, '987fcdeb-51a2-43d7-9b18-315274198000');

INSERT INTO comments (id, content, approved, post_id, user_id) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Great post!', true, '11111111-1111-1111-1111-111111111111', '987fcdeb-51a2-43d7-9b18-315274198000'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Nice work', false, '11111111-1111-1111-1111-111111111111', '123e4567-e89b-12d3-a456-426614174000'),
    ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'Interesting', true, '33333333-3333-3333-3333-333333333333', '123e4567-e89b-12d3-a456-426614174000');

EOF

echo "Test database setup complete!"