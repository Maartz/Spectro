import Foundation

public actor ConfigurationManager {
    public static let shared = ConfigurationManager()
    
    private var envVars: [String: String] = [:]
    
    private init() {}
    
    public struct DatabaseConfig {
        let hostname: String
        let port: Int
        let username: String
        let password: String
        let database: String
    }
    
    public func loadEnvFile() throws {
        let envPath = FileManager.default.currentDirectoryPath + "/.env"
        
        guard FileManager.default.fileExists(atPath: envPath) else {
            // No .env file, use environment variables
            return
        }
        
        let contents = try String(contentsOfFile: envPath, encoding: .utf8)
        let lines = contents.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty && !trimmed.hasPrefix("#") else { continue }
            
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            
            envVars[key] = value
        }
    }
    
    public func getDatabaseConfig(overrides: [String: String] = [:]) -> DatabaseConfig {
        let hostname = overrides["hostname"] ?? envVars["DB_HOST"] ?? ProcessInfo.processInfo.environment["DB_HOST"] ?? "localhost"
        let port = Int(overrides["port"] ?? envVars["DB_PORT"] ?? ProcessInfo.processInfo.environment["DB_PORT"] ?? "5432") ?? 5432
        let username = overrides["username"] ?? envVars["DB_USER"] ?? ProcessInfo.processInfo.environment["DB_USER"] ?? "postgres"
        let password = overrides["password"] ?? envVars["DB_PASSWORD"] ?? ProcessInfo.processInfo.environment["DB_PASSWORD"] ?? ""
        let database = overrides["database"] ?? envVars["DB_NAME"] ?? ProcessInfo.processInfo.environment["DB_NAME"] ?? "postgres"
        
        return DatabaseConfig(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database
        )
    }
}