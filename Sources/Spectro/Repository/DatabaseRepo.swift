import Foundation
@preconcurrency import PostgresKit

/// Concrete repository implementation using actor-based DatabaseConnection
public struct DatabaseRepo: Repo {
    internal let connection: DatabaseConnection

    public init(connection: DatabaseConnection) {
        self.connection = connection
    }

    // MARK: - CRUD

    public func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T? {
        let sql = "SELECT * FROM \(schema.tableName) WHERE id = $1"
        let results = try await connection.executeQuery(
            sql: sql,
            parameters: [PostgresData(uuid: id)]
        ) { row in try self.mapRowToSchema(row, schema: schema) }
        return results.first
    }

    public func getOrFail<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T {
        guard let model = try await get(schema, id: id) else {
            throw SpectroError.notFound(schema: schema.tableName, id: id)
        }
        return model
    }

    public func all<T: Schema>(_ schema: T.Type) async throws -> [T] {
        try await connection.executeQuery(sql: "SELECT * FROM \(schema.tableName)") { row in
            try self.mapRowToSchema(row, schema: schema)
        }
    }

    public func insert<T: Schema>(_ instance: T) async throws -> T {
        let data = extractData(from: instance)
        let columns = data.keys.sorted()
        let placeholders = columns.enumerated().map { "$\($0.offset + 1)" }

        let sql = """
            INSERT INTO \(T.tableName) (\(columns.joined(separator: ", ")))
            VALUES (\(placeholders.joined(separator: ", ")))
            RETURNING *
            """

        let parameters = try columns.map { try convertToPostgresData(data[$0]!) }
        let results = try await connection.executeQuery(sql: sql, parameters: parameters) { row in
            try self.mapRowToSchema(row, schema: T.self)
        }
        guard let inserted = results.first else {
            throw SpectroError.unexpectedResultCount(expected: 1, actual: 0)
        }
        return inserted
    }

    public func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: any Sendable]) async throws -> T {
        guard !changes.isEmpty else { return try await getOrFail(schema, id: id) }

        let columns = changes.keys.sorted()
        let setClauses = columns.enumerated().map { "\($0.element) = $\($0.offset + 2)" }

        let sql = """
            UPDATE \(schema.tableName)
            SET \(setClauses.joined(separator: ", "))
            WHERE id = $1
            RETURNING *
            """

        var parameters: [PostgresData] = [PostgresData(uuid: id)]
        for column in columns {
            parameters.append(try convertToPostgresData(changes[column]!))
        }

        let results = try await connection.executeQuery(sql: sql, parameters: parameters) { row in
            try self.mapRowToSchema(row, schema: schema)
        }
        guard let updated = results.first else {
            throw SpectroError.notFound(schema: schema.tableName, id: id)
        }
        return updated
    }

    public func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws {
        let count = try await connection.execute(
            sql: "DELETE FROM \(schema.tableName) WHERE id = $1",
            parameters: [PostgresData(uuid: id)]
        )
        if count == 0 { throw SpectroError.notFound(schema: schema.tableName, id: id) }
    }

    public func transaction<T: Sendable>(_ work: @escaping @Sendable (any Repo) async throws -> T) async throws -> T {
        try await work(self)
    }

    // MARK: - Private

    private func mapRowToSchema<T: Schema>(_ row: PostgresRow, schema: T.Type) throws -> T {
        let instance = T()
        let randomAccess = row.makeRandomAccess()
        var values: [String: Any] = [:]

        let mirror = Mirror(reflecting: instance)
        for child in mirror.children {
            guard let label = child.label else { continue }
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            let dbValue = randomAccess[data: fieldName.snakeCase()]
            if let v = dbValue.string        { values[fieldName] = v }
            else if let v = dbValue.int      { values[fieldName] = v }
            else if let v = dbValue.bool     { values[fieldName] = v }
            else if let v = dbValue.uuid     { values[fieldName] = v }
            else if let v = dbValue.date     { values[fieldName] = v }
            else if let v = dbValue.double   { values[fieldName] = v }
        }

        guard let builderType = T.self as? any SchemaBuilder.Type else {
            throw SpectroError.invalidSchema(reason: "Schema \(T.self) must implement SchemaBuilder")
        }
        return builderType.build(from: values) as! T
    }

    private func extractData<T: Schema>(from instance: T) -> [String: Any] {
        var data: [String: Any] = [:]
        for child in Mirror(reflecting: instance).children {
            guard let label = child.label else { continue }
            let fieldName = label.hasPrefix("_") ? String(label.dropFirst()) : label
            if let value = extractPropertyWrapperValue(child.value) {
                data[fieldName.snakeCase()] = value
            }
        }
        return data
    }

    private func extractPropertyWrapperValue(_ wrapper: Any) -> Any? {
        for child in Mirror(reflecting: wrapper).children {
            if child.label == "wrappedValue" { return child.value }
        }
        return wrapper
    }

    private func convertToPostgresData(_ value: Any) throws -> PostgresData {
        switch value {
        case let v as String:  return PostgresData(string: v)
        case let v as Int:     return PostgresData(int: v)
        case let v as Bool:    return PostgresData(bool: v)
        case let v as UUID:    return PostgresData(uuid: v)
        case let v as Date:    return PostgresData(date: v)
        case let v as Double:  return PostgresData(double: v)
        case let v as Float:   return PostgresData(float: v)
        case let v as Data:    return PostgresData(bytes: [UInt8](v))
        default:
            throw SpectroError.invalidParameter(
                name: "value",
                value: String(describing: value),
                reason: "Unsupported type: \(type(of: value))"
            )
        }
    }
}
