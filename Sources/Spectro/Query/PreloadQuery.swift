import Foundation
import PostgresNIO

/// Query with preloaded relationships to avoid N+1 problems
public struct PreloadQuery<T: Schema>: Sendable {
    private let baseQuery: Query<T>
    private let preloadedRelationships: [String]
    
    internal init(baseQuery: Query<T>, preloadedRelationships: [String]) {
        self.baseQuery = baseQuery
        self.preloadedRelationships = preloadedRelationships
    }
    
    // MARK: - Chaining Additional Preloads
    
    /// Preload another has-many relationship
    public func preload<Related>(_ relationshipKeyPath: KeyPath<T, SpectroLazyRelation<[Related]>>) -> PreloadQuery<T> {
        let relationshipName = extractRelationshipName(from: relationshipKeyPath)
        return PreloadQuery(
            baseQuery: baseQuery,
            preloadedRelationships: preloadedRelationships + [relationshipName]
        )
    }
    
    /// Preload another single relationship
    public func preload<Related>(_ relationshipKeyPath: KeyPath<T, SpectroLazyRelation<Related?>>) -> PreloadQuery<T> {
        let relationshipName = extractRelationshipName(from: relationshipKeyPath)
        return PreloadQuery(
            baseQuery: baseQuery,
            preloadedRelationships: preloadedRelationships + [relationshipName]
        )
    }
    
    // MARK: - Query Chaining (delegate to base query)
    
    /// Add where conditions
    public func `where`(_ condition: (QueryBuilder<T>) -> QueryCondition) -> PreloadQuery<T> {
        let updatedQuery = baseQuery.where(condition)
        return PreloadQuery(baseQuery: updatedQuery, preloadedRelationships: preloadedRelationships)
    }
    
    /// Add ordering
    public func orderBy<V>(_ field: (QueryBuilder<T>) -> QueryField<V>, _ direction: OrderDirection = .asc) -> PreloadQuery<T> {
        let updatedQuery = baseQuery.orderBy(field, direction)
        return PreloadQuery(baseQuery: updatedQuery, preloadedRelationships: preloadedRelationships)
    }
    
    /// Limit results
    public func limit(_ count: Int) -> PreloadQuery<T> {
        let updatedQuery = baseQuery.limit(count)
        return PreloadQuery(baseQuery: updatedQuery, preloadedRelationships: preloadedRelationships)
    }
    
    /// Offset results
    public func offset(_ count: Int) -> PreloadQuery<T> {
        let updatedQuery = baseQuery.offset(count)
        return PreloadQuery(baseQuery: updatedQuery, preloadedRelationships: preloadedRelationships)
    }
    
    // MARK: - Execution with Preloading
    
    /// Execute query and return results with preloaded relationships
    public func all() async throws -> [T] {
        // First, execute the base query to get primary entities
        let entities = try await baseQuery.all()
        
        // Then preload relationships for all entities in batch
        return try await preloadRelationshipsForEntities(entities)
    }
    
    /// Execute query and return first result with preloaded relationships
    public func first() async throws -> T? {
        let entities = try await limit(1).all()
        return entities.first
    }
    
    // MARK: - Private Preloading Implementation
    
    private func preloadRelationshipsForEntities(_ entities: [T]) async throws -> [T] {
        guard !entities.isEmpty && !preloadedRelationships.isEmpty else {
            return entities
        }
        
        // For each relationship, load the related data in batch
        var preloadedEntities = entities
        
        for relationshipName in preloadedRelationships {
            preloadedEntities = try await preloadRelationship(
                relationshipName,
                for: preloadedEntities
            )
        }
        
        return preloadedEntities
    }
    
    private func preloadRelationship(_ relationshipName: String, for entities: [T]) async throws -> [T] {
        // This is where the magic happens - batch load relationships
        // For now, return entities unchanged until we implement the batch loading
        return entities
    }
    
    /// Extract relationship name from KeyPath for preloading
    private func extractRelationshipName<Related>(from keyPath: KeyPath<T, SpectroLazyRelation<Related>>) -> String {
        // For now, return a placeholder. In production, this would use reflection
        // or a registry to map KeyPaths to relationship names
        return "unknown_relationship"
    }
}