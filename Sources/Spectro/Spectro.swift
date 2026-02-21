import Foundation
@preconcurrency import PostgresKit

/// Swift ORM for PostgreSQL with property wrapper schemas and actor-based concurrency.
public struct Spectro {
    private let connection: DatabaseConnection

    public init(configuration: DatabaseConfiguration) throws {
        self.connection = try DatabaseConnection(configuration: configuration)
    }

    public init(
        hostname: String = "localhost",
        port: Int = 5432,
        username: String,
        password: String,
        database: String,
        maxConnectionsPerEventLoop: Int = 4
    ) throws {
        let config = DatabaseConfiguration(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            database: database,
            maxConnectionsPerEventLoop: maxConnectionsPerEventLoop
        )
        try self.init(configuration: config)
    }

    public static func fromEnvironment() throws -> Spectro {
        try Spectro(configuration: DatabaseConfiguration.fromEnvironment())
    }

    public func repository() -> GenericDatabaseRepo {
        GenericDatabaseRepo(connection: connection)
    }

    public func testConnection() async throws -> String {
        try await connection.testConnection()
    }

    public func migrationManager() -> MigrationManager {
        MigrationManager(connection: connection)
    }

    public func shutdown() async {
        await connection.shutdown()
    }
}

// MARK: - Convenience

extension Spectro {
    public func transaction<T: Sendable>(_ work: @escaping @Sendable (any Repo) async throws -> T) async throws -> T {
        try await repository().transaction(work)
    }

    public func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T? {
        try await repository().get(schema, id: id)
    }

    public func all<T: Schema>(_ schema: T.Type) async throws -> [T] {
        try await repository().all(schema)
    }

    public func insert<T: Schema>(_ instance: T) async throws -> T {
        try await repository().insert(instance)
    }

    public func upsert<T: Schema>(_ instance: T, conflictTarget: ConflictTarget, set: [String]? = nil) async throws -> T {
        try await repository().upsert(instance, conflictTarget: conflictTarget, set: set)
    }

    public func insertAll<T: Schema>(_ instances: [T]) async throws -> [T] {
        try await repository().insertAll(instances)
    }

    public func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: any Sendable]) async throws -> T {
        try await repository().update(schema, id: id, changes: changes)
    }

    public func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws {
        try await repository().delete(schema, id: id)
    }
}
