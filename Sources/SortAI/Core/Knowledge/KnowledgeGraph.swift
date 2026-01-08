// MARK: - Knowledge Graph (GraphRAG)
// Stores entities, relationships, and learned patterns for intelligent categorization

import Foundation
import GRDB

// MARK: - Entity Types

/// Types of entities in the knowledge graph
enum EntityType: String, Codable, DatabaseValueConvertible {
    case file           // A processed file
    case category       // A category in the taxonomy
    case keyword        // A keyword/term extracted from content
    case person         // A person mentioned or identified
    case topic          // A high-level topic/theme
    case pattern        // A learned pattern (filename, content pattern)
}

/// A node in the knowledge graph
struct Entity: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?
    let type: EntityType
    let name: String
    let normalizedName: String  // Lowercase, trimmed for matching
    var metadata: String?       // JSON blob for type-specific data
    let createdAt: Date
    var updatedAt: Date
    var usageCount: Int         // How often this entity is referenced
    
    static let databaseTableName = "entities"
    
    init(type: EntityType, name: String, metadata: [String: Any]? = nil) {
        self.type = type
        self.name = name
        self.normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let metadata = metadata {
            self.metadata = try? String(data: JSONSerialization.data(withJSONObject: metadata), encoding: .utf8)
        }
        self.createdAt = Date()
        self.updatedAt = Date()
        self.usageCount = 1
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Relationship Types

/// Types of relationships between entities
enum RelationshipType: String, Codable, DatabaseValueConvertible {
    // Category relationships
    case isChildOf          // category IS_CHILD_OF category
    case belongsTo          // file BELONGS_TO category
    
    // Content relationships
    case hasKeyword         // file/category HAS_KEYWORD keyword
    case mentions           // file MENTIONS person
    case relatedTo          // entity RELATED_TO entity (general)
    
    // Learning relationships
    case suggestsCategory   // keyword/pattern SUGGESTS_CATEGORY category
    case humanConfirmed     // file HUMAN_CONFIRMED category (training data)
    case humanRejected      // file HUMAN_REJECTED category (negative training)
    
    // Similarity relationships
    case similarTo          // entity SIMILAR_TO entity (embedding-based)
}

/// An edge in the knowledge graph
struct Relationship: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?
    let sourceId: Int64
    let targetId: Int64
    let type: RelationshipType
    var weight: Double          // Strength of relationship (0.0-1.0)
    var metadata: String?       // JSON blob for relationship-specific data
    let createdAt: Date
    var updatedAt: Date
    
    static let databaseTableName = "relationships"
    
    init(sourceId: Int64, targetId: Int64, type: RelationshipType, weight: Double = 1.0, metadata: [String: Any]? = nil) {
        self.sourceId = sourceId
        self.targetId = targetId
        self.type = type
        self.weight = min(1.0, max(0.0, weight))
        if let metadata = metadata {
            self.metadata = try? String(data: JSONSerialization.data(withJSONObject: metadata), encoding: .utf8)
        }
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Category Path

/// Represents a flexible-depth category path (e.g., "Tech/Education/Programming")
struct CategoryPath: Codable, Hashable, Sendable, CustomStringConvertible {
    let components: [String]
    
    var description: String {
        components.joined(separator: " / ")
    }
    
    var depth: Int {
        components.count
    }
    
    var parent: CategoryPath? {
        guard components.count > 1 else { return nil }
        return CategoryPath(components: Array(components.dropLast()))
    }
    
    var leaf: String {
        components.last ?? ""
    }
    
    var root: String {
        components.first ?? ""
    }
    
    init(components: [String]) {
        self.components = components.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    
    init(path: String, separator: String = "/") {
        self.components = path
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    /// Creates a child path by appending a component
    func appending(_ component: String) -> CategoryPath {
        CategoryPath(components: components + [component])
    }
    
    /// Checks if this path is a descendant of another path
    func isDescendant(of ancestor: CategoryPath) -> Bool {
        guard components.count > ancestor.components.count else { return false }
        return Array(components.prefix(ancestor.components.count)) == ancestor.components
    }
}

// MARK: - Knowledge Graph Store

/// Manages the knowledge graph using the unified SortAIDatabase
/// Uses a class with thread-safe database access for compatibility with GRDB
final class KnowledgeGraphStore: KnowledgeGraphing, @unchecked Sendable {
    
    private let database: SortAIDatabase
    private let entityRepository: EntityRepository
    private let relationshipRepository: RelationshipRepository
    private let lock = NSLock()
    
    // Entity cache for fast lookups
    private var entityCache: [String: Entity] = [:]
    private let maxCacheSize = 10000
    
    /// Initialize with the shared SortAIDatabase
    init(database: SortAIDatabase? = nil) throws {
        self.database = database ?? SortAIDatabase.shared
        self.entityRepository = self.database.entities
        self.relationshipRepository = RelationshipRepository(database: self.database)
    }
    
    /// Legacy initializer for backward compatibility (database path is ignored, uses unified database)
    @available(*, deprecated, message: "Use init(database:) instead. Database path is ignored.")
    convenience init(databasePath: String?) throws {
        try self.init(database: nil)
    }
    
    // MARK: - Entity Operations
    
    /// Finds or creates an entity
    func findOrCreateEntity(type: EntityType, name: String, metadata: [String: Any]? = nil) throws -> Entity {
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "\(type.rawValue):\(normalizedName)"
        
        // Check cache first
        lock.lock()
        if let cached = entityCache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        let entity = try entityRepository.findOrCreate(type: type, name: name, metadata: metadata)
        
        // Update cache
        lock.lock()
        if entityCache.count < maxCacheSize {
            entityCache[cacheKey] = entity
        }
        lock.unlock()
        
        return entity
    }
    
    /// Gets an entity by ID
    func getEntity(id: Int64) throws -> Entity? {
        try entityRepository.get(id: id)
    }
    
    /// Gets entities by type
    func getEntities(type: EntityType, limit: Int = 100) throws -> [Entity] {
        try entityRepository.getByType(type, limit: limit)
    }
    
    /// Searches entities by name
    func searchEntities(query: String, type: EntityType? = nil, limit: Int = 20) throws -> [Entity] {
        try entityRepository.search(query: query, type: type, limit: limit)
    }
    
    // MARK: - Relationship Operations
    
    /// Creates a relationship between entities
    func createRelationship(sourceId: Int64, targetId: Int64, type: RelationshipType, weight: Double = 1.0, metadata: [String: Any]? = nil) throws -> Relationship {
        try relationshipRepository.createOrStrengthen(
            sourceId: sourceId,
            targetId: targetId,
            type: type,
            weight: weight,
            metadata: metadata
        )
    }
    
    /// Gets relationships from an entity
    func getRelationships(from sourceId: Int64, type: RelationshipType? = nil) throws -> [Relationship] {
        try relationshipRepository.getFrom(sourceId: sourceId, type: type)
    }
    
    /// Gets relationships to an entity
    func getRelationships(to targetId: Int64, type: RelationshipType? = nil) throws -> [Relationship] {
        try relationshipRepository.getTo(targetId: targetId, type: type)
    }
    
    // MARK: - Category Operations
    
    /// Gets or creates a category path, creating all ancestors
    func getOrCreateCategoryPath(_ path: CategoryPath) throws -> Entity {
        try entityRepository.getOrCreateCategoryPath(path)
    }
    
    /// Gets all root categories
    func getRootCategories() throws -> [Entity] {
        try entityRepository.getRootCategories()
    }
    
    /// Gets child categories of a parent
    func getChildCategories(of parentId: Int64) throws -> [Entity] {
        try entityRepository.getChildCategories(of: parentId)
    }
    
    /// Gets all categories (flattened)
    func getAllCategories(limit: Int = 100) throws -> [Entity] {
        try getEntities(type: .category, limit: limit)
    }
    
    // MARK: - Learning Operations
    
    /// Records that a keyword suggests a category
    func learnKeywordSuggestion(keyword: String, categoryId: Int64, weight: Double = 0.5) throws {
        // First create/find the keyword entity
        let keywordEntity = try entityRepository.findOrCreate(type: .keyword, name: keyword)
        guard let keywordId = keywordEntity.id else {
            throw DatabaseError.invalidData("Failed to get keyword entity ID")
        }
        // Then create the relationship
        try relationshipRepository.learnKeywordSuggestion(keywordId: keywordId, categoryId: categoryId, weight: weight)
    }
    
    /// Records human confirmation of a categorization
    func recordHumanConfirmation(fileId: Int64, categoryId: Int64) throws {
        try relationshipRepository.recordHumanConfirmation(fileId: fileId, categoryId: categoryId)
    }
    
    /// Records human rejection of a categorization
    func recordHumanRejection(fileId: Int64, categoryId: Int64) throws {
        _ = try relationshipRepository.create(
            sourceId: fileId,
            targetId: categoryId,
            type: .humanRejected,
            weight: 1.0
        )
    }
    
    /// Gets suggested categories for keywords
    func getSuggestedCategories(for keywords: [String], limit: Int = 5) throws -> [(Entity, Double)] {
        guard !keywords.isEmpty else { return [] }
        
        // Convert string keywords to entity IDs
        var keywordIds: [Int64] = []
        for keyword in keywords {
            let normalizedKeyword = keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let entity = try entityRepository.find(type: .keyword, normalizedName: normalizedKeyword) {
                if let id = entity.id {
                    keywordIds.append(id)
                }
            }
        }
        
        guard !keywordIds.isEmpty else { return [] }
        
        // Get suggested category IDs with weights
        let results = try relationshipRepository.getSuggestedCategories(for: keywordIds, limit: limit)
        
        // Convert to entities
        var entityResults: [(Entity, Double)] = []
        for (entityId, weight) in results {
            if let entity = try entityRepository.get(id: entityId) {
                entityResults.append((entity, weight))
            }
        }
        
        return entityResults
    }
    
    // MARK: - Statistics
    
    /// Gets graph statistics
    func getStatistics() throws -> GraphStatistics {
        let dbStats = try database.statistics()
        return GraphStatistics(
            totalEntities: dbStats.entityCount,
            totalRelationships: dbStats.relationshipCount,
            categoryCount: try entityRepository.count(type: .category),
            keywordCount: try entityRepository.count(type: .keyword),
            fileCount: try entityRepository.count(type: .file)
        )
    }
    
    /// Clear cache (for testing)
    func clearCache() {
        lock.lock()
        entityCache.removeAll()
        lock.unlock()
    }
}

// MARK: - Statistics

struct GraphStatistics: Sendable {
    let totalEntities: Int
    let totalRelationships: Int
    let categoryCount: Int
    let keywordCount: Int
    let fileCount: Int
}

