// MARK: - Relationship Repository
// Repository for knowledge graph relationships (edges between entities)

import Foundation
import GRDB

// MARK: - Relationship Repository

/// Manages Relationship persistence operations
final class RelationshipRepository: Sendable {
    
    private let database: SortAIDatabase
    
    init(database: SortAIDatabase) {
        self.database = database
    }
    
    // MARK: - Create Operations
    
    /// Creates or strengthens a relationship between entities
    @discardableResult
    func createOrStrengthen(
        sourceId: Int64,
        targetId: Int64,
        type: RelationshipType,
        weight: Double = 1.0,
        metadata: [String: Any]? = nil
    ) throws -> Relationship {
        try database.write { db in
            // Check if relationship exists
            if var existing = try Relationship
                .filter(Column("sourceId") == sourceId && Column("targetId") == targetId && Column("type") == type.rawValue)
                .fetchOne(db) {
                // Strengthen the relationship
                existing.weight = min(1.0, existing.weight + 0.1)
                existing.updatedAt = Date()
                try existing.update(db)
                return existing
            }
            
            // Create new
            var relationship = Relationship(
                sourceId: sourceId,
                targetId: targetId,
                type: type,
                weight: weight,
                metadata: metadata
            )
            try relationship.insert(db)
            // Explicitly set id if not set by didInsert callback
            if relationship.id == nil {
                relationship.id = db.lastInsertedRowID
            }
            return relationship
        }
    }
    
    /// Creates a new relationship (fails if already exists)
    @discardableResult
    func create(
        sourceId: Int64,
        targetId: Int64,
        type: RelationshipType,
        weight: Double = 1.0,
        metadata: [String: Any]? = nil
    ) throws -> Relationship {
        try database.write { db in
            var relationship = Relationship(
                sourceId: sourceId,
                targetId: targetId,
                type: type,
                weight: weight,
                metadata: metadata
            )
            try relationship.insert(db)
            // Explicitly set id if not set by didInsert callback
            if relationship.id == nil {
                relationship.id = db.lastInsertedRowID
            }
            return relationship
        }
    }
    
    // MARK: - Read Operations
    
    /// Gets a relationship by ID
    func get(id: Int64) throws -> Relationship? {
        try database.read { db in
            try Relationship.fetchOne(db, key: id)
        }
    }
    
    /// Gets relationships from an entity
    func getFrom(sourceId: Int64, type: RelationshipType? = nil) throws -> [Relationship] {
        try database.read { db in
            var request = Relationship.filter(Column("sourceId") == sourceId)
            if let type = type {
                request = request.filter(Column("type") == type.rawValue)
            }
            return try request.order(Column("weight").desc).fetchAll(db)
        }
    }
    
    /// Gets relationships to an entity
    func getTo(targetId: Int64, type: RelationshipType? = nil) throws -> [Relationship] {
        try database.read { db in
            var request = Relationship.filter(Column("targetId") == targetId)
            if let type = type {
                request = request.filter(Column("type") == type.rawValue)
            }
            return try request.order(Column("weight").desc).fetchAll(db)
        }
    }
    
    /// Finds a specific relationship
    func find(sourceId: Int64, targetId: Int64, type: RelationshipType) throws -> Relationship? {
        try database.read { db in
            try Relationship
                .filter(Column("sourceId") == sourceId && Column("targetId") == targetId && Column("type") == type.rawValue)
                .fetchOne(db)
        }
    }
    
    /// Counts relationships by type
    func count(type: RelationshipType? = nil) throws -> Int {
        try database.read { db in
            if let type = type {
                return try Relationship.filter(Column("type") == type.rawValue).fetchCount(db)
            }
            return try Relationship.fetchCount(db)
        }
    }
    
    // MARK: - Update Operations
    
    /// Updates a relationship
    func update(_ relationship: Relationship) throws {
        var mutableRelationship = relationship
        mutableRelationship.updatedAt = Date()
        try database.write { db in
            try mutableRelationship.update(db)
        }
    }
    
    /// Updates relationship weight
    func updateWeight(id: Int64, weight: Double) throws {
        let clampedWeight = min(1.0, max(0.0, weight))
        try database.write { db in
            try db.execute(
                sql: "UPDATE relationships SET weight = ?, updatedAt = ? WHERE id = ?",
                arguments: [clampedWeight, Date(), id]
            )
        }
    }
    
    // MARK: - Delete Operations
    
    /// Deletes a relationship by ID
    func delete(id: Int64) throws -> Bool {
        try database.write { db in
            try Relationship.deleteOne(db, key: id)
        }
    }
    
    /// Deletes all relationships from a source entity
    func deleteFrom(sourceId: Int64) throws -> Int {
        try database.write { db in
            try Relationship.filter(Column("sourceId") == sourceId).deleteAll(db)
        }
    }
    
    /// Deletes all relationships to a target entity
    func deleteTo(targetId: Int64) throws -> Int {
        try database.write { db in
            try Relationship.filter(Column("targetId") == targetId).deleteAll(db)
        }
    }
    
    // MARK: - Learning Operations
    
    /// Records that a keyword suggests a category
    func learnKeywordSuggestion(keywordId: Int64, categoryId: Int64, weight: Double = 0.5) throws {
        try createOrStrengthen(
            sourceId: keywordId,
            targetId: categoryId,
            type: .suggestsCategory,
            weight: weight
        )
    }
    
    /// Records human confirmation of a categorization
    func recordHumanConfirmation(fileId: Int64, categoryId: Int64) throws {
        try createOrStrengthen(
            sourceId: fileId,
            targetId: categoryId,
            type: .humanConfirmed,
            weight: 1.0
        )
    }
    
    /// Records human rejection of a categorization
    func recordHumanRejection(fileId: Int64, categoryId: Int64) throws {
        try createOrStrengthen(
            sourceId: fileId,
            targetId: categoryId,
            type: .humanRejected,
            weight: 1.0
        )
    }
    
    /// Gets suggested categories for keywords
    func getSuggestedCategories(for keywordIds: [Int64], limit: Int = 5) throws -> [(entityId: Int64, totalWeight: Double)] {
        guard !keywordIds.isEmpty else { return [] }
        
        return try database.read { db in
            let placeholders = keywordIds.map { _ in "?" }.joined(separator: ", ")
            
            let sql = """
                SELECT targetId, SUM(weight) as totalWeight
                FROM relationships
                WHERE sourceId IN (\(placeholders))
                AND type = 'suggestsCategory'
                GROUP BY targetId
                ORDER BY totalWeight DESC
                LIMIT ?
            """
            
            let arguments: [DatabaseValueConvertible] = keywordIds + [limit]
            
            struct Result: FetchableRecord {
                let targetId: Int64
                let totalWeight: Double
                
                init(row: Row) {
                    targetId = row["targetId"]
                    totalWeight = row["totalWeight"]
                }
            }
            
            let results = try Result.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return results.map { ($0.targetId, $0.totalWeight) }
        }
    }
}

