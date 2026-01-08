// MARK: - Entity Repository
// Repository for knowledge graph entities (files, categories, keywords, etc.)

import Foundation
import GRDB

// MARK: - Entity Repository

/// Manages Entity persistence operations
final class EntityRepository: Sendable {
    
    private let database: SortAIDatabase
    
    init(database: SortAIDatabase) {
        self.database = database
    }
    
    // MARK: - Create Operations
    
    /// Finds an existing entity or creates a new one
    @discardableResult
    func findOrCreate(type: EntityType, name: String, metadata: [String: Any]? = nil) throws -> Entity {
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        return try database.write { db in
            // Try to find existing
            if var existing = try Entity
                .filter(Column("type") == type.rawValue && Column("normalizedName") == normalizedName)
                .fetchOne(db) {
                existing.usageCount += 1
                existing.updatedAt = Date()
                try existing.update(db)
                return existing
            }
            
            // Create new - use insertAndFetch to ensure id is returned
            var entity = Entity(type: type, name: name, metadata: metadata)
            try entity.insert(db)
            // Explicitly set id if not set by didInsert callback
            if entity.id == nil {
                entity.id = db.lastInsertedRowID
            }
            return entity
        }
    }
    
    /// Creates a new entity (fails if already exists)
    @discardableResult
    func create(type: EntityType, name: String, metadata: [String: Any]? = nil) throws -> Entity {
        try database.write { db in
            var entity = Entity(type: type, name: name, metadata: metadata)
            try entity.insert(db)
            // Explicitly set id if not set by didInsert callback
            if entity.id == nil {
                entity.id = db.lastInsertedRowID
            }
            return entity
        }
    }
    
    // MARK: - Read Operations
    
    /// Gets an entity by ID
    func get(id: Int64) throws -> Entity? {
        try database.read { db in
            try Entity.fetchOne(db, key: id)
        }
    }
    
    /// Gets entities by type
    func getByType(_ type: EntityType, limit: Int = 100) throws -> [Entity] {
        try database.read { db in
            try Entity
                .filter(Column("type") == type.rawValue)
                .order(Column("usageCount").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Searches entities by name
    func search(query: String, type: EntityType? = nil, limit: Int = 20) throws -> [Entity] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        return try database.read { db in
            var request = Entity.filter(Column("normalizedName").like("%\(normalizedQuery)%"))
            
            if let type = type {
                request = request.filter(Column("type") == type.rawValue)
            }
            
            return try request
                .order(Column("usageCount").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Gets all entities with a specific normalized name and type
    func find(type: EntityType, normalizedName: String) throws -> Entity? {
        try database.read { db in
            try Entity
                .filter(Column("type") == type.rawValue && Column("normalizedName") == normalizedName)
                .fetchOne(db)
        }
    }
    
    /// Counts entities by type
    func count(type: EntityType? = nil) throws -> Int {
        try database.read { db in
            if let type = type {
                return try Entity.filter(Column("type") == type.rawValue).fetchCount(db)
            }
            return try Entity.fetchCount(db)
        }
    }
    
    // MARK: - Update Operations
    
    /// Updates an entity
    func update(_ entity: Entity) throws {
        var mutableEntity = entity
        mutableEntity.updatedAt = Date()
        try database.write { db in
            try mutableEntity.update(db)
        }
    }
    
    /// Increments usage count for an entity
    func incrementUsage(id: Int64) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE entities SET usageCount = usageCount + 1, updatedAt = ? WHERE id = ?",
                arguments: [Date(), id]
            )
        }
    }
    
    // MARK: - Delete Operations
    
    /// Deletes an entity by ID
    func delete(id: Int64) throws -> Bool {
        try database.write { db in
            try Entity.deleteOne(db, key: id)
        }
    }
    
    /// Deletes all entities of a type
    func deleteAll(type: EntityType) throws -> Int {
        try database.write { db in
            try Entity.filter(Column("type") == type.rawValue).deleteAll(db)
        }
    }
    
    // MARK: - Category Operations
    
    /// Gets or creates a category path, creating all ancestors
    func getOrCreateCategoryPath(_ path: CategoryPath) throws -> Entity {
        var parentId: Int64? = nil
        var categoryEntity: Entity!
        
        try database.write { db in
            for (index, component) in path.components.enumerated() {
                let partialPath = CategoryPath(components: Array(path.components.prefix(index + 1)))
                let fullName = partialPath.description
                let normalizedName = fullName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Find or create entity
                if var existing = try Entity
                    .filter(Column("type") == EntityType.category.rawValue && Column("normalizedName") == normalizedName)
                    .fetchOne(db) {
                    existing.usageCount += 1
                    existing.updatedAt = Date()
                    try existing.update(db)
                    categoryEntity = existing
                } else {
                    var entity = Entity(
                        type: .category,
                        name: fullName,
                        metadata: [
                            "depth": index + 1,
                            "component": component,
                            "isLeaf": index == path.components.count - 1
                        ]
                    )
                    try entity.insert(db)
                    // Explicitly set id if not set by didInsert callback
                    if entity.id == nil {
                        entity.id = db.lastInsertedRowID
                    }
                    categoryEntity = entity
                }
                
                // Create parent-child relationship
                if let pid = parentId {
                    // Check if relationship exists
                    let existingRel = try Relationship
                        .filter(Column("sourceId") == categoryEntity.id! && Column("targetId") == pid && Column("type") == RelationshipType.isChildOf.rawValue)
                        .fetchOne(db)
                    
                    if existingRel == nil {
                        let relationship = Relationship(
                            sourceId: categoryEntity.id!,
                            targetId: pid,
                            type: .isChildOf
                        )
                        _ = try relationship.inserted(db)
                    }
                }
                
                parentId = categoryEntity.id
            }
        }
        
        return categoryEntity
    }
    
    /// Gets all root categories (categories without parents)
    func getRootCategories() throws -> [Entity] {
        try database.read { db in
            let sql = """
                SELECT e.* FROM entities e
                WHERE e.type = 'category'
                AND NOT EXISTS (
                    SELECT 1 FROM relationships r
                    WHERE r.sourceId = e.id AND r.type = 'isChildOf'
                )
                ORDER BY e.usageCount DESC
            """
            return try Entity.fetchAll(db, sql: sql)
        }
    }
    
    /// Gets child categories of a parent
    func getChildCategories(of parentId: Int64) throws -> [Entity] {
        try database.read { db in
            let sql = """
                SELECT e.* FROM entities e
                JOIN relationships r ON e.id = r.sourceId
                WHERE r.targetId = ? AND r.type = 'isChildOf'
                ORDER BY e.usageCount DESC
            """
            return try Entity.fetchAll(db, sql: sql, arguments: [parentId])
        }
    }
    
    /// Gets all categories
    func getAllCategories(limit: Int = 100) throws -> [Entity] {
        try getByType(.category, limit: limit)
    }
}

