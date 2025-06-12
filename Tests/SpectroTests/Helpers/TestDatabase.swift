import Foundation
@testable import Spectro

/// Database setup utilities for tests
public actor TestDatabaseState {
    private static let shared = TestDatabaseState()
    private var sharedSpectro: Spectro?
    private var isInitialized = false
    
    public static func getSharedSpectro() async throws -> Spectro {
        return try await shared.getSpectroInternal()
    }
    
    public static func shutdownSharedSpectro() async {
        await shared.shutdownInternal()
    }
    
    public static func initializeOnce() async throws {
        try await shared.initializeOnceInternal()
    }
    
    private func getSpectroInternal() throws -> Spectro {
        if let spectro = sharedSpectro {
            return spectro
        }
        
        let spectro = try Spectro(
            username: "postgres",
            password: "postgres",
            database: "spectro_test"
        )
        sharedSpectro = spectro
        return spectro
    }
    
    private func shutdownInternal() async {
        if let spectro = sharedSpectro {
            await spectro.shutdown()
            sharedSpectro = nil
            isInitialized = false
        }
    }
    
    private func initializeOnceInternal() async throws {
        guard !isInitialized else { return }
        
        let spectro = try getSpectroInternal()
        let repo = spectro.repository()
        
        // Drop and recreate all tables to ensure clean state
        try await TestDatabase.dropTables(using: repo)
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms for cleanup
        try await TestDatabase.createTables(using: repo)
        
        isInitialized = true
    }
}

/// Database setup utilities for tests
public struct TestDatabase {
    
    /// Create all test tables in correct dependency order
    public static func createTables(using repo: GenericDatabaseRepo) async throws {
        // Create tables in dependency order - parents before children
        try await createUsersTable(using: repo)    // No dependencies
        try await createTagsTable(using: repo)     // No dependencies
        try await createProductsTable(using: repo) // No dependencies
        try await createPostsTable(using: repo)    // Depends on users
        try await createCommentsTable(using: repo) // Depends on posts & users
        try await createProfilesTable(using: repo) // Depends on users
        try await createPostTagsTable(using: repo) // Depends on posts & tags
    }
    
    /// Drop all test tables
    public static func dropTables(using repo: GenericDatabaseRepo) async throws {
        let dropStatements = [
            "DROP TABLE IF EXISTS post_tags CASCADE",
            "DROP TABLE IF EXISTS tags CASCADE", 
            "DROP TABLE IF EXISTS comments CASCADE",
            "DROP TABLE IF EXISTS posts CASCADE",
            "DROP TABLE IF EXISTS profiles CASCADE",
            "DROP TABLE IF EXISTS products CASCADE",
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
    public static func resetDatabase(using repo: GenericDatabaseRepo) async throws {
        try await dropTables(using: repo)
        // Wait a bit for cleanup to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        try await createTables(using: repo)
    }
    
    /// Setup test database with initial schema (call once at start)
    public static func setupTestDatabase(using repo: GenericDatabaseRepo) async throws {
        // Just clean existing data - tables should already exist from setup script
        try await cleanTables(using: repo)
    }
    
    /// Clean all data from tables (for tests that don't need full reset)
    public static func cleanTables(using repo: GenericDatabaseRepo) async throws {
        let cleanStatements = [
            "DELETE FROM post_tags",
            "DELETE FROM comments",
            "DELETE FROM posts", 
            "DELETE FROM profiles",
            "DELETE FROM tags",
            "DELETE FROM products",
            "DELETE FROM users"
        ]
        
        for statement in cleanStatements {
            try await executeRawSQL(statement, using: repo)
        }
    }
    
    /// Generate unique email for tests to avoid conflicts
    public static func uniqueEmail(_ base: String = "test") -> String {
        let timestamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let uuid = UUID().uuidString.lowercased().prefix(8)
        return "\(base).\(timestamp).\(uuid)@example.com"
    }
    
    // MARK: - Individual Table Creation
    
    private static func createUsersTable(using repo: GenericDatabaseRepo) async throws {
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
    
    private static func createPostsTable(using repo: GenericDatabaseRepo) async throws {
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
    
    private static func createCommentsTable(using repo: GenericDatabaseRepo) async throws {
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
    
    private static func createProfilesTable(using repo: GenericDatabaseRepo) async throws {
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
    
    private static func createTagsTable(using repo: GenericDatabaseRepo) async throws {
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
    
    private static func createProductsTable(using repo: GenericDatabaseRepo) async throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS products (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            name TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            price DECIMAL(10,2) NOT NULL DEFAULT 0.00,
            stock INTEGER NOT NULL DEFAULT 0,
            active BOOLEAN DEFAULT true,
            created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        )
        """
        try await executeRawSQL(sql, using: repo)
    }
    
    private static func createPostTagsTable(using repo: GenericDatabaseRepo) async throws {
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
    
    private static func executeRawSQL(_ sql: String, using repo: GenericDatabaseRepo) async throws {
        try await repo.executeRawSQL(sql)
    }
}