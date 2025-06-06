import Foundation

/// Clean, essential repository interface for database operations
/// Works with actor-based DatabaseConnection for thread safety
public protocol Repo: Sendable {
    /// Get a single record by ID
    func get<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T.Model?
    
    /// Get a single record by ID or throw if not found
    func getOrFail<T: Schema>(_ schema: T.Type, id: UUID) async throws -> T.Model
    
    /// Get all records for a schema
    func all<T: Schema>(_ schema: T.Type) async throws -> [T.Model]
    
    /// Insert a new record
    func insert<T: Schema>(_ schema: T.Type, data: [String: Any]) async throws -> T.Model
    
    /// Update an existing record by ID
    func update<T: Schema>(_ schema: T.Type, id: UUID, changes: [String: Any]) async throws -> T.Model
    
    /// Delete a record by ID
    func delete<T: Schema>(_ schema: T.Type, id: UUID) async throws
    
    /// Execute a query and return results
    func query<T: Schema>(_ schema: T.Type) -> QueryBuilder<T>
    
    /// Execute work within a transaction
    func transaction<T: Sendable>(_ work: @Sendable (Repo) async throws -> T) async throws -> T
}

/// Query builder for type-safe query construction
public struct QueryBuilder<T: Schema>: Sendable {
    let schema: T.Type
    let repo: any Repo
    private var conditions: [QueryCondition] = []
    private var orderBy: [OrderClause] = []
    private var limitValue: Int?
    private var offsetValue: Int?
    
    init(schema: T.Type, repo: any Repo) {
        self.schema = schema
        self.repo = repo
    }
    
    /// Add WHERE conditions (will be chained together)
    public func `where`(_ condition: QueryCondition) -> QueryBuilder<T> {
        var builder = self
        builder.conditions.append(condition)
        return builder
    }
    
    /// Add ORDER BY clause
    public func orderBy(_ order: OrderClause) -> QueryBuilder<T> {
        var builder = self
        builder.orderBy.append(order)
        return builder
    }
    
    /// Set LIMIT
    public func limit(_ count: Int) -> QueryBuilder<T> {
        var builder = self
        builder.limitValue = count
        return builder
    }
    
    /// Set OFFSET
    public func offset(_ count: Int) -> QueryBuilder<T> {
        var builder = self
        builder.offsetValue = count
        return builder
    }
    
    /// Execute the query and return all results
    public func all() async throws -> [T.Model] {
        // This will be implemented by the concrete repository
        // For now, we'll throw not implemented
        throw SpectroError.notImplemented("QueryBuilder.all() - will be implemented with new architecture")
    }
    
    /// Execute the query and return first result
    public func first() async throws -> T.Model? {
        let results = try await limit(1).all()
        return results.first
    }
}

/// Simple query condition for WHERE clauses
public struct QueryCondition: Sendable {
    let field: String
    let operator: String
    let value: Any
    
    public init(field: String, operator: String, value: Any) {
        self.field = field
        self.operator = operator
        self.value = value
    }
    
    public static func equal(_ field: String, _ value: Any) -> QueryCondition {
        QueryCondition(field: field, operator: "=", value: value)
    }
    
    public static func greaterThan(_ field: String, _ value: Any) -> QueryCondition {
        QueryCondition(field: field, operator: ">", value: value)
    }
    
    public static func lessThan(_ field: String, _ value: Any) -> QueryCondition {
        QueryCondition(field: field, operator: "<", value: value)
    }
}

/// Order by clause
public struct OrderClause: Sendable {
    let field: String
    let direction: OrderDirection
    
    public init(field: String, direction: OrderDirection = .ascending) {
        self.field = field
        self.direction = direction
    }
    
    public static func asc(_ field: String) -> OrderClause {
        OrderClause(field: field, direction: .ascending)
    }
    
    public static func desc(_ field: String) -> OrderClause {
        OrderClause(field: field, direction: .descending)
    }
}
