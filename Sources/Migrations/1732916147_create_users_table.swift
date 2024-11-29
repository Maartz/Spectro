import SpectroKit

struct M1732916147CreateUsersTable: Migration {
    let version = "1732916147_create_users_table"

    func up() -> String {
        """
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            username VARCHAR(50) NOT NULL,
            email VARCHAR(100) UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        );
        """
    }

    func down() -> String {
        """
        DROP TABLE IF EXISTS users;
        """
    }
}

