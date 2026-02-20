import Foundation
import PostgresNIO
import AsyncKit

/// Generic database repository that works with any Schema type.
///
/// `GenericDatabaseRepo` provides a type-safe, actor-based data access layer for PostgreSQL.
/// It implements the Repository pattern with full CRUD operations, query building, and transaction support.
public actor GenericDatabaseRepo: Repo {
    private let connection: DatabaseConnection

    public init(connection: DatabaseConnection) {
        self.connection = connection
    }

    // MARK: - Query

    public func query<T: Schema>(_ schema: T.Type) -> Query<T> {
        Query(schema: schema, connection: connection)
    }

    // MARK: - Raw SQL

    public func executeRawSQL(_ sql: String) async throws {
        try await connection.executeUpdate(sql: sql)
    }

    // MARK: - CRUD

    public func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T? {
        let metadata = await SchemaRegistry.shared.register(schema)

        guard let primaryKey = metadata.primaryKeyField else {
            throw SpectroError.invalidSchema(reason: "Schema \(T.self) has no primary key field")
        }

        let sql = "SELECT * FROM \(metadata.tableName) WHERE \(primaryKey.snakeCase()) = $1"

        let rows = try await connection.executeQuery(
            sql: sql,
            parameters: [PostgresData(uuid: id)],
            resultMapper: { $0 }
        )

        guard let row = rows.first else { return nil }
        return try await mapRowToSchema(row, schema: schema)
    }

    public func all<T: Schema>(_ schema: T.Type) async throws -> [T] {
        let metadata = await SchemaRegistry.shared.register(schema)
        let sql = "SELECT * FROM \(metadata.tableName)"
        let rows = try await connection.executeQuery(sql: sql, resultMapper: { $0 })

        var results: [T] = []
        for row in rows {
            results.append(try await mapRowToSchema(row, schema: schema))
        }
        return results
    }

    public func insert<T: Schema>(_ instance: T) async throws -> T {
        let metadata = await SchemaRegistry.shared.register(T.self)
        let data = SchemaMapper.extractData(from: instance, metadata: metadata, excludePrimaryKey: true)

        let columns = data.keys.joined(separator: ", ")
        let placeholders = (1...data.count).map { "$\($0)" }.joined(separator: ", ")
        let values = Array(data.values)

        let sql = """
            INSERT INTO \(metadata.tableName) (\(columns))
            VALUES (\(placeholders))
            RETURNING *
            """

        let rows = try await connection.executeQuery(
            sql: sql,
            parameters: values,
            resultMapper: { $0 }
        )

        guard let row = rows.first else {
            throw SpectroError.databaseError(reason: "Insert did not return a row")
        }

        return try await mapRowToSchema(row, schema: T.self)
    }

    public func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: Any]) async throws -> T {
        let metadata = await SchemaRegistry.shared.register(schema)

        guard let primaryKey = metadata.primaryKeyField else {
            throw SpectroError.invalidSchema(reason: "Schema \(schema) has no primary key field")
        }

        var setClause: [String] = []
        var values: [PostgresData] = []
        var paramIndex = 1

        for (column, value) in changes {
            setClause.append("\(column.snakeCase()) = $\(paramIndex)")
            values.append(try SchemaMapper.convertToPostgresData(value))
            paramIndex += 1
        }

        values.append(PostgresData(uuid: id))

        let sql = """
            UPDATE \(metadata.tableName)
            SET \(setClause.joined(separator: ", "))
            WHERE \(primaryKey.snakeCase()) = $\(paramIndex)
            RETURNING *
            """

        let rows = try await connection.executeQuery(
            sql: sql,
            parameters: values,
            resultMapper: { $0 }
        )

        guard let row = rows.first else {
            throw SpectroError.databaseError(reason: "Update did not return a row")
        }

        return try await mapRowToSchema(row, schema: schema)
    }

    public func getOrFail<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T {
        guard let result = try await get(schema, id: id) else {
            throw SpectroError.notFound(schema: schema.tableName, id: id)
        }
        return result
    }

    public func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws {
        let metadata = await SchemaRegistry.shared.register(schema)

        guard let primaryKey = metadata.primaryKeyField else {
            throw SpectroError.invalidSchema(reason: "Schema \(T.self) has no primary key field")
        }

        let sql = "DELETE FROM \(metadata.tableName) WHERE \(primaryKey.snakeCase()) = $1"
        try await connection.executeUpdate(sql: sql, parameters: [PostgresData(uuid: id)])
    }

    public func transaction<T: Sendable>(_ work: @escaping @Sendable (Repo) async throws -> T) async throws -> T {
        try await executeRawSQL("BEGIN ISOLATION LEVEL READ COMMITTED")

        do {
            let transactionRepo = GenericDatabaseRepo(connection: connection)
            let result = try await work(transactionRepo)
            try await executeRawSQL("COMMIT")
            return result
        } catch {
            do {
                try await executeRawSQL("ROLLBACK")
            } catch {
                // Don't mask the original error
            }
            throw error
        }
    }

    // MARK: - Private

    private func mapRowToSchema<T: Schema>(_ row: PostgresRow, schema: T.Type) async throws -> T {
        let metadata = await SchemaRegistry.shared.register(schema)
        let randomAccess = row.makeRandomAccess()

        var values: [String: Any] = [:]
        for field in metadata.fields {
            let dbValue = randomAccess[data: field.databaseName]
            if let value = SchemaMapper.extractValue(from: dbValue, expectedType: field.type) {
                values[field.name] = value
            }
        }

        guard let builderType = T.self as? any SchemaBuilder.Type else {
            throw SpectroError.invalidSchema(
                reason: """
                    Schema \(T.self) must implement SchemaBuilder.
                    Add a `static func build(from values: [String: Any]) -> \(T.self)` \
                    or use the @Schema macro once available.
                    """
            )
        }

        return builderType.build(from: values) as! T
    }
}
