import Foundation

public struct DatabaseConfiguration {
    public let hostname: String
    public let port: Int
    public let username: String
    public let password: String
    public let database: String

    static let `default` = DatabaseConfiguration(
        hostname: "localhost",
        port: 5432,
        username: "postgres",
        password: "postgres",
        database: "spectro_test"
    )
}

enum ConfigurationError: Error {
    case fileNotFound(String)
    case invalidFormat(String)
}

public class ConfigurationManager {
    public static let shared = ConfigurationManager()
    private var envConfig: [String: String] = [:]
    private let fileManager: FileManager = .default
    private let projectRoot: URL

    private init() {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.projectRoot = currentDirectory
    }

    public func loadEnvFile(path: String = ".env") throws {
        let envPath = projectRoot.appendingPathComponent(".env")
        guard let content = try? String(contentsOf: envPath, encoding: .utf8) else {
            throw ConfigurationError.fileNotFound("Could not load .env at path: \(envPath.path)")
        }

        content.components(separatedBy: .newlines).forEach { line in
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                envConfig[key] = value.replacingOccurrences(of: "\"", with: "")
            }
        }
    }

    public func getDatabaseConfig(overrides: [String: String] = [:]) -> DatabaseConfiguration {
        var hostname = envConfig["DB_HOST"] ?? DatabaseConfiguration.default.hostname
        var port = Int(envConfig["DB_PORT"] ?? "") ?? DatabaseConfiguration.default.port
        var username = envConfig["DB_USER"] ?? DatabaseConfiguration.default.username
        var password = envConfig["DB_PASSWORD"] ?? DatabaseConfiguration.default.password
        var database = envConfig["DB_NAME"] ?? DatabaseConfiguration.default.database

        if let host = overrides["hostname"] { hostname = host }
        if let portString = overrides["port"], let p = Int(portString) { port = p }
        if let user = overrides["username"] { username = user }
        if let pass = overrides["password"] { password = pass }
        if let db = overrides["database"] { database = db }

        let config = DatabaseConfiguration(
            hostname: hostname, port: port, username: username, password: password,
            database: database)

        return config
    }
}
