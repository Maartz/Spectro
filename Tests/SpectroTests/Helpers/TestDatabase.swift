import Foundation
@testable import Spectro

/// Database setup utilities for tests
public struct TestDatabase {
    
    /// Create all test tables
    public static func createTables(using repo: DatabaseRepo) async throws {
        do {
            try await createUsersTable(using: repo)
        } catch {
            print("Warning: Failed to create users table: \(error)")
        }
        
        do {
            try await createPostsTable(using: repo)
        } catch {
            print("Warning: Failed to create posts table: \(error)")
        }
        
        do {
            try await createCommentsTable(using: repo)
        } catch {
            print("Warning: Failed to create comments table: \(error)")
        }
        
        do {
            try await createProfilesTable(using: repo)
        } catch {
            print("Warning: Failed to create profiles table: \(error)")
        }
        
        do {
            try await createTagsTable(using: repo)
        } catch {
            print("Warning: Failed to create tags table: \(error)")
        }
        
        do {
            try await createPostTagsTable(using: repo)
        } catch {
            print("Warning: Failed to create post_tags table: \(error)")
        }
    }
    
    /// Drop all test tables
    public static func dropTables(using repo: DatabaseRepo) async throws {
        let dropStatements = [
            "DROP TABLE IF EXISTS post_tags CASCADE",
            "DROP TABLE IF EXISTS tags CASCADE", 
            "DROP TABLE IF EXISTS comments CASCADE",
            "DROP TABLE IF EXISTS posts CASCADE",
            "DROP TABLE IF EXISTS profiles CASCADE",
            "DROP TABLE IF EXISTS users CASCADE"
        ]
        
        for statement in dropStatements {
            do {
                try await executeRawSQL(statement, using: repo)
            } catch {
                // Continue dropping other tables even if one fails
                print("Warning: Failed to drop table with statement: \(statement), error: \(error)")
            }
        }
    }
    
    /// Reset database - drop and recreate all tables
    public static func resetDatabase(using repo: DatabaseRepo) async throws {
        try await dropTables(using: repo)
        try await createTables(using: repo)
    }
    
    /// Setup test database with initial schema (call once at start)
    public static func setupTestDatabase(using repo: DatabaseRepo) async throws {
        // Try to create tables if they don't exist, ignore errors if they do
        do {
            try await createTables(using: repo)
        } catch {
            // Tables likely already exist, just clean them
            try await cleanTables(using: repo)
        }
    }
    
    /// Clean all data from tables (for tests that don't need full reset)
    public static func cleanTables(using repo: DatabaseRepo) async throws {
        let cleanStatements = [
            "DELETE FROM post_tags",
            "DELETE FROM comments",
            "DELETE FROM posts", 
            "DELETE FROM profiles",
            "DELETE FROM tags",
            "DELETE FROM users"
        ]
        
        for statement in cleanStatements {
            try await executeRawSQL(statement, using: repo)
        }
    }
    
    /// Generate unique email for tests to avoid conflicts
    public static func uniqueEmail(_ base: String = "test") -> String {
        return "\(base)+\(UUID().uuidString.prefix(8))@example.com"
    }
    
    // MARK: - Individual Table Creation
    
    private static func createUsersTable(using repo: DatabaseRepo) async throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS users (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            name TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            age INTEGER,
            is_active BOOLEAN DEFAULT true,
            created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        )
        """
        try await executeRawSQL(sql, using: repo)
    }
    
    private static func createPostsTable(using repo: DatabaseRepo) async throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS posts (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            title TEXT NOT NULL,
            content TEXT NOT NULL,
            published BOOLEAN DEFAULT false,
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        )
        """
        try await executeRawSQL(sql, using: repo)
    }
    
    private static func createCommentsTable(using repo: DatabaseRepo) async throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS comments (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            content TEXT NOT NULL,
            approved BOOLEAN DEFAULT false,
            post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        )
        """
        try await executeRawSQL(sql, using: repo)
    }
    
    private static func createProfilesTable(using repo: DatabaseRepo) async throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS profiles (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            language TEXT DEFAULT 'en',
            opt_in_email BOOLEAN DEFAULT false,
            verified BOOLEAN DEFAULT false,
            user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        )
        """
        try await executeRawSQL(sql, using: repo)
    }
    
    private static func createTagsTable(using repo: DatabaseRepo) async throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS tags (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            name TEXT NOT NULL UNIQUE,
            color TEXT DEFAULT '',
            created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        )
        """
        try await executeRawSQL(sql, using: repo)
    }
    
    private static func createPostTagsTable(using repo: DatabaseRepo) async throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS post_tags (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
            tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
            created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(post_id, tag_id)
        )
        """
        try await executeRawSQL(sql, using: repo)
    }
    
    // MARK: - Helper Methods
    
    private static func executeRawSQL(_ sql: String, using repo: DatabaseRepo) async throws {
        // Execute raw SQL using the connection
        _ = try await repo.connection.executeQuery(sql: sql) { _ in
            return ()
        }
    }
}
