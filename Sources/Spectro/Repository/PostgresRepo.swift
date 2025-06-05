import Foundation
import PostgresKit

// Performance optimization: Array chunking extension
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

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
        var models = try rows.map { row in
            try T.Model(from: row)
        }
        
        // Handle preloads if any are specified
        if !baseQuery.preloadRelationships.isEmpty {
            models = try await preload(models, baseQuery.preloadRelationships)
        }
        
        return models
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
        guard !models.isEmpty else { return models }
        
        // Separate simple and nested associations for optimal processing
        let (simpleAssociations, nestedAssociations) = partitionAssociations(associations)
        
        var enrichedModels = models
        
        // Process simple associations concurrently (massive performance boost)
        if !simpleAssociations.isEmpty {
            enrichedModels = try await preloadAssociationsConcurrently(enrichedModels, simpleAssociations)
        }
        
        // Process nested associations sequentially (they depend on previous data)
        for nestedAssociation in nestedAssociations {
            enrichedModels = try await preloadAssociation(enrichedModels, nestedAssociation)
        }
        
        return enrichedModels
    }
    
    /// Separate simple associations (posts, profile) from nested ones (posts.comments)
    private func partitionAssociations(_ associations: [String]) -> (simple: [String], nested: [String]) {
        var simple: [String] = []
        var nested: [String] = []
        
        for association in associations {
            if association.contains(".") {
                nested.append(association)
            } else {
                simple.append(association)
            }
        }
        
        return (simple, nested)
    }
    
    /// Process multiple simple associations concurrently for maximum performance
    private func preloadAssociationsConcurrently<T: Schema>(_ models: [T.Model], _ associations: [String]) async throws -> [T.Model] {
        // Prepare data for concurrent loading
        let modelIds = models.map { $0.id }
        
        // Pre-extract foreign key data for belongsTo relationships
        var foreignKeyMaps: [String: [UUID]] = [:]
        for association in associations {
            guard let relationship = T.relationship(named: association) else { continue }
            
            if case .belongsTo = relationship.type {
                let foreignKeyValues = models.compactMap { model in
                    model.data[relationship.localKey] as? String
                }.compactMap { UUID(uuidString: $0) }
                foreignKeyMaps[association] = foreignKeyValues
            }
        }
        
        // Load all associations concurrently
        let associationResults = try await withThrowingTaskGroup(of: (String, [DataRow]).self) { group in
            
            // Launch concurrent tasks for each association
            for association in associations {
                // Capture foreign key map for this specific association to avoid data races
                let foreignKeys = foreignKeyMaps[association]
                group.addTask {
                    let relatedData = try await self.loadAssociationData(
                        T.self, 
                        association, 
                        modelIds, 
                        foreignKeyMap: foreignKeys
                    )
                    return (association, relatedData)
                }
            }
            
            // Collect all results
            var results: [String: [DataRow]] = [:]
            for try await (association, data) in group {
                results[association] = data
            }
            return results
        }
        
        // Apply all associations to models efficiently
        var enrichedModels = models
        for association in associations {
            guard let relatedData = associationResults[association] else { continue }
            
            // Get relationship info
            guard let relationship = T.relationship(named: association) else {
                throw RepositoryError.invalidRelationship("Relationship '\(association)' not found on \(T.schemaName)")
            }
            
            // Associate the data using optimized hashmap lookup
            enrichedModels = try associateData(enrichedModels, relatedData, relationship, association)
        }
        
        return enrichedModels
    }
    
    /// Load data for a specific association (optimized for concurrent execution)
    private func loadAssociationData<T: Schema>(
        _ schemaType: T.Type, 
        _ association: String, 
        _ modelIds: [UUID],
        foreignKeyMap: [UUID]? = nil
    ) async throws -> [DataRow] {
        // Get the relationship info
        guard let relationship = schemaType.relationship(named: association) else {
            throw RepositoryError.invalidRelationship("Relationship '\(association)' not found on \(schemaType.schemaName)")
        }
        
        // Load related data based on relationship type
        switch relationship.type {
        case .hasMany, .hasOne:
            return try await loadRelatedData(
                fromSchema: relationship.foreignSchema,
                whereField: relationship.foreignKey,
                matchingIds: modelIds
            )
            
        case .belongsTo:
            guard let foreignKeys = foreignKeyMap, !foreignKeys.isEmpty else { 
                return [] 
            }
            return try await loadRelatedData(
                fromSchema: relationship.foreignSchema,
                whereField: "id",
                matchingIds: foreignKeys
            )
            
        case .manyToMany:
            throw RepositoryError.notImplemented("Many-to-many preloading not yet implemented")
        }
    }
    
    private func preloadAssociation<T: Schema>(_ models: [T.Model], _ association: String) async throws -> [T.Model] {
        // Handle nested preloads like "posts.comments"
        let parts = association.split(separator: ".").map(String.init)
        guard let firstAssociation = parts.first else {
            throw RepositoryError.invalidRelationship("Empty association name")
        }
        
        // Get the relationship info for the first association
        guard let relationship = T.relationship(named: firstAssociation) else {
            throw RepositoryError.invalidRelationship("Relationship '\(firstAssociation)' not found on \(T.schemaName)")
        }
        
        // Extract IDs from models for foreign key lookup
        let modelIds = models.map { $0.id }
        
        // Load related data based on relationship type
        var relatedData: [DataRow]
        
        switch relationship.type {
        case .hasMany, .hasOne:
            // For hasMany/hasOne: foreign table has foreign_key pointing to our id
            // SELECT * FROM posts WHERE user_id IN (...)
            relatedData = try await loadRelatedData(
                fromSchema: relationship.foreignSchema,
                whereField: relationship.foreignKey,
                matchingIds: modelIds
            )
            
        case .belongsTo:
            // For belongsTo: our table has foreign_key pointing to their id
            // First extract the foreign key values from our models
            let foreignKeyValues = models.compactMap { model in
                model.data[relationship.localKey] as? String // Assuming UUID as string
            }
            guard !foreignKeyValues.isEmpty else { return models }
            
            // SELECT * FROM users WHERE id IN (...)
            relatedData = try await loadRelatedData(
                fromSchema: relationship.foreignSchema,
                whereField: "id",
                matchingIds: foreignKeyValues.compactMap { UUID(uuidString: $0) }
            )
            
        case .manyToMany:
            // TODO: Implement many-to-many preloading
            throw RepositoryError.notImplemented("Many-to-many preloading not yet implemented")
        }
        
        // Load nested associations if this is a nested preload
        if parts.count > 1 {
            let nestedAssociation = parts.dropFirst().joined(separator: ".")
            relatedData = try await loadNestedPreloads(relatedData, nestedAssociation, relationship.foreignSchema)
        }
        
        // Associate the loaded data with models
        return try associateData(models, relatedData, relationship, firstAssociation)
    }
    
    private func loadRelatedData(
        fromSchema schema: any Schema.Type,
        whereField: String,
        matchingIds: [UUID]
    ) async throws -> [DataRow] {
        guard !matchingIds.isEmpty else { return [] }
        
        // Performance optimization: Remove duplicates to reduce query size
        let uniqueIds = Array(Set(matchingIds))
        
        // Performance optimization: Batch large ID lists to prevent SQL parameter limits
        let batchSize = 1000  // Most databases handle 1000 IN parameters efficiently
        var allResults: [DataRow] = []
        
        // Process IDs in batches for optimal performance
        for batch in uniqueIds.chunked(into: batchSize) {
            let query = Query.from(schema).where { selector in
                return QueryCondition(
                    field: whereField,
                    op: "IN",
                    value: .array(batch.map { .uuid($0) })
                )
            }
            
            let batchResults = try await executeQuery(query)
            allResults.append(contentsOf: batchResults)
        }
        
        return allResults
    }
    
    /// Load nested preloads on already-loaded data
    private func loadNestedPreloads(
        _ parentData: [DataRow],
        _ nestedAssociation: String,
        _ parentSchema: any Schema.Type
    ) async throws -> [DataRow] {
        guard !parentData.isEmpty else { return parentData }
        
        // Parse the nested association (could be multi-level like "comments.replies")
        let parts = nestedAssociation.split(separator: ".").map(String.init)
        guard let firstNestedAssociation = parts.first else { return parentData }
        
        // Get the relationship info from the parent schema
        guard let relationship = parentSchema.relationship(named: firstNestedAssociation) else {
            throw RepositoryError.invalidRelationship("Relationship '\(firstNestedAssociation)' not found on \(parentSchema.schemaName)")
        }
        
        // Extract parent IDs for loading nested data
        let parentIds = parentData.compactMap { row in
            if let idString = row.values["id"] as? String {
                return UUID(uuidString: idString)
            }
            return nil
        }
        
        // Load the nested data
        let nestedData: [DataRow]
        switch relationship.type {
        case .hasMany, .hasOne:
            nestedData = try await loadRelatedData(
                fromSchema: relationship.foreignSchema,
                whereField: relationship.foreignKey,
                matchingIds: parentIds
            )
        case .belongsTo:
            // For belongsTo, extract foreign key values from parent data
            let foreignKeyValues = parentData.compactMap { row in
                row.values[relationship.localKey] as? String
            }.compactMap { UUID(uuidString: $0) }
            
            nestedData = try await loadRelatedData(
                fromSchema: relationship.foreignSchema,
                whereField: "id",
                matchingIds: foreignKeyValues
            )
        case .manyToMany:
            throw RepositoryError.notImplemented("Many-to-many nested preloading not yet implemented")
        }
        
        // If there are more nested levels, recursively process them
        var finalNestedData = nestedData
        if parts.count > 1 {
            let deeperNestedAssociation = parts.dropFirst().joined(separator: ".")
            finalNestedData = try await loadNestedPreloads(nestedData, deeperNestedAssociation, relationship.foreignSchema)
        }
        
        // Associate the nested data with the parent data
        return try associateNestedData(parentData, finalNestedData, relationship, firstNestedAssociation)
    }
    
    /// Associate nested data with parent DataRows
    private func associateNestedData(
        _ parentData: [DataRow],
        _ nestedData: [DataRow],
        _ relationship: RelationshipInfo,
        _ associationName: String
    ) throws -> [DataRow] {
        // Create a map of nested data for efficient lookup
        var nestedMap: [String: [DataRow]] = [:]
        
        for row in nestedData {
            let key: String
            
            switch relationship.type {
            case .hasMany, .hasOne:
                // Group by foreign key (e.g., comments grouped by post_id)
                key = row.values[relationship.foreignKey] as? String ?? ""
            case .belongsTo:
                // Group by primary key (e.g., users grouped by id)
                key = row.values["id"] as? String ?? ""
            case .manyToMany:
                throw RepositoryError.notImplemented("Many-to-many association not implemented")
            }
            
            if nestedMap[key] == nil {
                nestedMap[key] = []
            }
            nestedMap[key]?.append(row)
        }
        
        // Associate data with each parent row
        return parentData.map { parentRow in
            var enrichedData = parentRow.values
            
            let lookupKey: String
            switch relationship.type {
            case .hasMany, .hasOne:
                // Lookup by parent ID
                lookupKey = parentRow.values["id"] as? String ?? ""
            case .belongsTo:
                // Lookup by foreign key value in parent
                lookupKey = parentRow.values[relationship.localKey] as? String ?? ""
            case .manyToMany:
                lookupKey = ""
            }
            
            switch relationship.type {
            case .hasMany:
                // Associate array of nested models
                enrichedData[associationName] = nestedMap[lookupKey] ?? []
            case .hasOne, .belongsTo:
                // Associate single nested model
                enrichedData[associationName] = nestedMap[lookupKey]?.first
            case .manyToMany:
                break // Not implemented
            }
            
            return DataRow(values: enrichedData)
        }
    }
    
    private func associateData<T: Schema>(
        _ models: [T.Model],
        _ relatedData: [DataRow],
        _ relationship: RelationshipInfo,
        _ associationName: String
    ) throws -> [T.Model] {
        // Create a map of related data for efficient lookup
        var relatedMap: [String: [DataRow]] = [:]
        
        for row in relatedData {
            let key: String
            
            switch relationship.type {
            case .hasMany, .hasOne:
                // Group by foreign key (e.g., posts grouped by user_id)
                key = row.values[relationship.foreignKey] as? String ?? ""
            case .belongsTo:
                // Group by primary key (e.g., users grouped by id)
                key = row.values["id"] as? String ?? ""
            case .manyToMany:
                throw RepositoryError.notImplemented("Many-to-many association not implemented")
            }
            
            if relatedMap[key] == nil {
                relatedMap[key] = []
            }
            relatedMap[key]?.append(row)
        }
        
        // Associate data with each model
        return try models.map { model in
            var modelData = model.data
            
            let lookupKey: String
            switch relationship.type {
            case .hasMany, .hasOne:
                // For hasMany/hasOne: lookup by our ID (related data is grouped by foreign key pointing to us)
                lookupKey = model.id.uuidString
            case .belongsTo:
                // For belongsTo: lookup by foreign key value in our model (related data is grouped by their ID)
                lookupKey = model.data[relationship.localKey] as? String ?? ""
            case .manyToMany:
                throw RepositoryError.notImplemented("Many-to-many association not implemented")
            }
            
            switch relationship.type {
            case .hasMany:
                // Associate array of related models
                modelData[associationName] = relatedMap[lookupKey] ?? []
            case .hasOne, .belongsTo:
                // Associate single related model
                modelData[associationName] = relatedMap[lookupKey]?.first
            case .manyToMany:
                throw RepositoryError.notImplemented("Many-to-many association not implemented")
            }
            
            return try T.Model(from: DataRow(values: modelData))
        }
    }

    private func executeQuery(_ query: Query) async throws -> [DataRow] {
        // Build JOIN clauses
        let joinClause = query.joins.isEmpty ? "" : " " + SQLBuilder.buildJoinClauses(query.joins, sourceTable: query.table)
        
        // Build WHERE clauses for main table
        let whereClause = SQLBuilder.buildWhereClause(query.conditions)
        
        // Build WHERE clauses for composite conditions
        var compositeWhereClauses: [(clause: String, params: [PostgresData])] = []
        var parameterOffset = whereClause.params.count
        
        for composite in query.compositeConditions {
            let compositeWhere = SQLBuilder.buildWhereClause(composite)
            // Adjust parameter indices to be sequential
            let adjustedClause = adjustParameterNumbers(in: compositeWhere.clause, offset: parameterOffset)
            compositeWhereClauses.append((clause: adjustedClause, params: compositeWhere.params))
            parameterOffset += compositeWhere.params.count
        }
        
        // Build WHERE clauses for joined relationships
        let relationshipWhere = SQLBuilder.buildRelationshipConditions(
            query.relationshipConditions,
            parameterOffset: parameterOffset
        )
        
        // Combine WHERE conditions
        var allConditions: [String] = []
        var allParams: [PostgresData] = []
        
        if !whereClause.clause.isEmpty {
            allConditions.append(whereClause.clause)
            allParams.append(contentsOf: whereClause.params)
        }
        
        for compositeWhere in compositeWhereClauses {
            if !compositeWhere.clause.isEmpty {
                allConditions.append(compositeWhere.clause)
                allParams.append(contentsOf: compositeWhere.params)
            }
        }
        
        if !relationshipWhere.clause.isEmpty {
            allConditions.append(relationshipWhere.clause)
            allParams.append(contentsOf: relationshipWhere.params)
        }
        
        let combinedWhereClause = allConditions.isEmpty ? "" : " WHERE " + allConditions.joined(separator: " AND ")
        
        // Build other clauses
        let orderClause = query.orderBy.isEmpty ? "" : " ORDER BY " + query.orderBy.map { "\($0.field) \($0.direction.sql)" }.joined(separator: ", ")
        let limitClause = query.limit.map { " LIMIT \($0)" } ?? ""
        let offsetClause = query.offset.map { " OFFSET \($0)" } ?? ""

        // Prepare selections with table prefixes for joins
        let actualSelections: [String]
        if query.selections == ["*"] {
            if query.joins.isEmpty {
                // Keep the original behavior for simple queries
                actualSelections = ["*"]
            } else {
                // For joins, we need to be explicit about columns to avoid conflicts
                actualSelections = query.schema.databaseFields.map { "\(query.table).\($0.name)" }
            }
        } else {
            // Ensure ID is always included in selections
            var selections = query.selections
            if !selections.contains("id") {
                selections.insert("id", at: 0)
            }
            if query.joins.isEmpty {
                actualSelections = selections
            } else {
                // Prefix with table name for joins
                actualSelections = selections.map { "\(query.table).\($0)" }
            }
        }

        let sql = """
            SELECT \(actualSelections.joined(separator: ", ")) FROM \(query.table)\(joinClause)\(combinedWhereClause)\(orderClause)\(limitClause)\(offsetClause)
            """

        return try await db.executeQuery(
            sql: sql,
            params: allParams
        ) { row in
            let randomAccessRow = row.makeRandomAccess()
            var dict: [String: Any] = [:]

            // Handle different selection types
            let columnsToProcess: [String]
            if actualSelections == ["*"] {
                // For SELECT *, get only database columns (exclude relationships)
                columnsToProcess = query.schema.databaseFields.map { $0.name }
            } else {
                columnsToProcess = actualSelections
            }

            for column in columnsToProcess {
                // For join queries, the column might be prefixed with table name
                let actualColumnName = column.contains(".") ? column.split(separator: ".").last.map(String.init) ?? column : column
                let columnData = randomAccessRow[data: actualColumnName]
                
                // Try to convert to appropriate types
                if let intValue = columnData.int {
                    dict[actualColumnName] = intValue
                } else if let doubleValue = columnData.double {
                    dict[actualColumnName] = doubleValue
                } else if let boolValue = columnData.bool {
                    dict[actualColumnName] = boolValue
                } else if let uuidValue = columnData.uuid {
                    dict[actualColumnName] = uuidValue.uuidString
                } else if let stringValue = columnData.string {
                    dict[actualColumnName] = stringValue
                }
            }

            return DataRow(values: dict)
        }
    }
    
    private func adjustParameterNumbers(in clause: String, offset: Int) -> String {
        let regex = try! NSRegularExpression(pattern: #"\$(\d+)"#)
        var result = clause
        
        let matches = regex.matches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result)
        )
        
        for match in matches.reversed() {
            if let matchRange = Range(match.range(at: 1), in: result),
                let number = Int(result[matchRange])
            {
                let adjustedNumber = "$\(number + offset)"
                if let fullMatchRange = Range(match.range, in: result) {
                    result.replaceSubrange(fullMatchRange, with: adjustedNumber)
                }
            }
        }
        
        return result
    }
}
