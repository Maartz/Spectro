import Foundation

public struct DatabaseConfiguration: Sendable {
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

public final class ConfigurationManager: Sendable {
  public static let shared = ConfigurationManager()
  private let envConfig: ThreadSafeContainer<[String: String]>
  private let projectRoot: URL

  private init() {
    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    self.projectRoot = currentDirectory
    self.envConfig = ThreadSafeContainer([:])
  }

  public func loadEnvFile(path: String = ".env") throws {
    let envPath = projectRoot.appendingPathComponent(".env")
    guard let content = try? String(contentsOf: envPath, encoding: .utf8) else {
      throw ConfigurationError.fileNotFound("Could not load .env at path: \(envPath.path)")
    }

    var newConfig: [String: String] = [:]
    content.components(separatedBy: .newlines).forEach { line in
      let parts = line.split(separator: "=", maxSplits: 1)
      if parts.count == 2 {
        let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
        newConfig[key] = value.replacingOccurrences(of: "\"", with: "")
      }
    }
    envConfig.value = newConfig
  }

  public func getDatabaseConfig(overrides: [String: String] = [:]) -> DatabaseConfiguration {
    let currentEnvConfig = envConfig.value

    var hostname = currentEnvConfig["DB_HOST"] ?? DatabaseConfiguration.default.hostname
    var port = Int(currentEnvConfig["DB_PORT"] ?? "") ?? DatabaseConfiguration.default.port
    var username = currentEnvConfig["DB_USER"] ?? DatabaseConfiguration.default.username
    var password = currentEnvConfig["DB_PASSWORD"] ?? DatabaseConfiguration.default.password
    var database = currentEnvConfig["DB_NAME"] ?? DatabaseConfiguration.default.database

    if let host = overrides["hostname"] { hostname = host }
    if let portString = overrides["port"], let p = Int(portString) { port = p }
    if let user = overrides["username"] { username = user }
    if let pass = overrides["password"] { password = pass }
    if let db = overrides["database"] { database = db }

    return DatabaseConfiguration(
      hostname: hostname, port: port, username: username, password: password,
      database: database)
  }
}

private final class ThreadSafeContainer<T>: @unchecked Sendable {
  private let lock = NSLock()
  private var _value: T

  init(_ value: T) {
    _value = value
  }

  var value: T {
    get {
      lock.lock()
      defer { lock.unlock() }
      return _value
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      _value = newValue
    }
  }
}
