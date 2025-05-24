import Foundation
import PostgresKit

public final class PostgresRepo: Repo {
    private let db: DatabaseOperations

    public init(pools: EventLoopGroupConnectionPool<PostgresConnectionSource>) {
        self.db = PostgresDatabaseOperations(pools: pools)
    }

    public func all<T: Schema>(_ schema: T.Type, query: ((Query) -> Query)? = nil) async throws -> [T.Model] {
        var baseQuery = Query.from(schema)
        if let queryBuilder = query {
            baseQuery = queryBuilder(baseQuery)
        }

        let rows = try await executeQuery(baseQuery)
        return try rows.map { row in
            try T.Model(from: row)
        }
    }

    public func get<T: Schema>(_ schema: T.Type, _ id: UUID) async throws -> T.Model? {
        let query = Query.from(schema).where { $0.id.eq(id) }.limit(1)
        let results = try await all(schema, query: { _ in query })
        return results.first
    }

    public func getOrFail<T: Schema>(_ schema: T.Type, _ id: UUID) async throws -> T.Model {
        guard let model = try await get(schema, id) else {
            throw RepositoryError.notFound("No \(schema.schemaName) with id \(id)")
        }
        return model
    }

    public func insert<T: Schema>(_ changeset: Changeset<T>) async throws -> T.Model {
        guard changeset.isValid else {
            throw RepositoryError.invalidChangeset(changeset.errors)
        }

        var values = changeset.changes
        values["id"] = UUID()
        values["created_at"] = Date()
        values["updated_at"] = Date()

        let sql = SQLBuilder.buildInsert(
            table: changeset.schema.schemaName,
            values: values.mapValues { ConditionValue.value($0) }
        )

        let rows: [DataRow] = try await db.executeQuery(
            sql: sql.sql,
            params: sql.params
        ) { row in
            // Convert PostgresRow to DataRow
            DataRow(from: row)
        }

        guard let row = rows.first else {
            throw RepositoryError.insertFailed
        }

        return try T.Model(from: row)
    }

    public func update<T: Schema>(_ model: T.Model, _ changeset: Changeset<T>) async throws -> T.Model {
        guard changeset.isValid else {
            throw RepositoryError.invalidChangeset(changeset.errors)
        }

        var values = changeset.changes
        values["updated_at"] = Date()

        let sql = SQLBuilder.buildUpdate(
            table: changeset.schema.schemaName,
            values: values.mapValues { ConditionValue.value($0) },
            where: ["id": ("=", .uuid(model.id))],
            returning: "*"
        )

        let rows: [DataRow] = try await db.executeQuery(
            sql: sql.sql,
            params: sql.params
        ) { row in
            DataRow(from: row)
        }

        guard let row = rows.first else {
            throw RepositoryError.updateFailed
        }

        return try T.Model(from: row)
    }

    public func delete<T: Schema>(_ model: T.Model) async throws {
        let sql = SQLBuilder.buildDelete(
            table: T.schemaName,
            where: ["id": ("=", .uuid(model.id))]
        )

        try await db.executeUpdate(sql: sql.sql, params: sql.params)
    }

    public func preload<T: Schema>(_ models: [T.Model], _ associations: [String]) async throws -> [T.Model] {
        // TODO: Implement preloading
        // This will be easier once we have join support
        return models
    }

    private func executeQuery(_ query: Query) async throws -> [DataRow] {
        let sql = query.toSQL()
        return try await db.executeQuery(
            sql: sql.sql,
            params: sql.params
        ) { row in
            DataRow(values: row)
        }
    }
}
