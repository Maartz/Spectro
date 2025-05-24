import Foundation
import PostgresKit

public final class PostgresRepo: Repo, @unchecked Sendable {
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
        let id = UUID()
        values["id"] = .uuid(id)
        values["created_at"] = .date(Date())
        values["updated_at"] = .date(Date())

        let sql = SQLBuilder.buildInsert(
            table: changeset.schema.schemaName,
            values: values
        )

        try await db.executeUpdate(sql: sql.sql, params: sql.params)

        // Fetch the inserted record
        guard let model = try await get(T.self, id) else {
            throw RepositoryError.invalidQueryResult
        }

        return model
    }

    public func update<T: Schema>(_ model: T.Model, _ changeset: Changeset<T>) async throws -> T.Model {
        guard changeset.isValid else {
            throw RepositoryError.invalidChangeset(changeset.errors)
        }

        var values = changeset.changes
        values["updated_at"] = .date(Date())

        let sql = SQLBuilder.buildUpdate(
            table: changeset.schema.schemaName,
            values: values,
            where: ["id": ("=", ConditionValue.uuid(model.id))]
        )

        try await db.executeUpdate(sql: sql.sql, params: sql.params)

        // Fetch the updated record
        guard let updatedModel = try await get(T.self, model.id) else {
            throw RepositoryError.invalidQueryResult
        }

        return updatedModel
    }

    public func delete<T: Schema>(_ model: T.Model) async throws {
        let whereClause = SQLBuilder.buildWhereClause(["id": ("=", ConditionValue.uuid(model.id))])
        let sql = "DELETE FROM \(T.schemaName) WHERE \(whereClause.clause)"

        try await db.executeUpdate(sql: sql, params: whereClause.params)
    }

    public func preload<T: Schema>(_ models: [T.Model], _ associations: [String]) async throws -> [T.Model] {
        // TODO: Implement preloading
        // This will be easier once we have join support
        return models
    }

    private func executeQuery(_ query: Query) async throws -> [DataRow] {
        let whereClause = SQLBuilder.buildWhereClause(query.conditions)
        let orderClause = query.orderBy.isEmpty ? "" : " ORDER BY " + query.orderBy.map { "\($0.field) \($0.direction.sql)" }.joined(separator: ", ")
        let limitClause = query.limit.map { " LIMIT \($0)" } ?? ""
        let offsetClause = query.offset.map { " OFFSET \($0)" } ?? ""

        // If selections is ["*"], get all schema field names instead
        let actualSelections: [String]
        if query.selections == ["*"] {
            // Get all field names from the schema, including implicit ID
            actualSelections = query.schema.allFields.map { $0.name }
        } else {
            actualSelections = query.selections
        }

        let sql = """
            SELECT \(actualSelections.joined(separator: ", ")) FROM \(query.table)
            \(query.conditions.isEmpty ? "" : "WHERE " + whereClause.clause)
            \(orderClause)\(limitClause)\(offsetClause)
            """

        return try await db.executeQuery(
            sql: sql,
            params: whereClause.params
        ) { row in
            let randomAccessRow = row.makeRandomAccess()
            var dict: [String: String] = [:]

            for column in actualSelections {
                if let columnValue = randomAccessRow[data: column].string {
                    dict[column] = columnValue
                }
            }

            return DataRow(values: dict)
        }
    }
}
