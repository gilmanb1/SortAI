// MARK: - Human Feedback System
// Manages human-in-the-loop categorization corrections and learning

import Foundation
import GRDB

// MARK: - Feedback Item

/// Represents a file awaiting or having received human feedback
struct FeedbackItem: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: Int64?
    let fileURL: String
    let fileName: String
    let suggestedCategory: String
    let suggestedSubcategories: String  // JSON array
    let confidence: Double
    let rationale: String
    var status: FeedbackStatus
    var humanCategory: String?
    var humanSubcategories: String?     // JSON array
    var feedbackNotes: String?
    let createdAt: Date
    var reviewedAt: Date?
    let extractedKeywords: String       // JSON array - keywords from content
    let fileEntityId: Int64?            // Reference to entity in knowledge graph
    
    static let databaseTableName = "feedback_queue"
    
    enum FeedbackStatus: String, Codable, DatabaseValueConvertible {
        case pending        // Awaiting review (low confidence)
        case autoAccepted   // High confidence, auto-accepted
        case humanAccepted  // Human confirmed suggestion
        case humanCorrected // Human provided different category
        case skipped        // User skipped for now
    }
    
    var needsReview: Bool {
        status == .pending
    }
    
    var suggestedPath: CategoryPath {
        var components = [suggestedCategory]
        if let subs = try? JSONDecoder().decode([String].self, from: suggestedSubcategories.data(using: .utf8) ?? Data()) {
            components.append(contentsOf: subs)
        }
        return CategoryPath(components: components)
    }
    
    var humanPath: CategoryPath? {
        guard let cat = humanCategory else { return nil }
        var components = [cat]
        if let subsData = humanSubcategories?.data(using: .utf8),
           let subs = try? JSONDecoder().decode([String].self, from: subsData) {
            components.append(contentsOf: subs)
        }
        return CategoryPath(components: components)
    }
    
    var keywords: [String] {
        guard let data = extractedKeywords.data(using: .utf8),
              let keywords = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return keywords
    }
    
    init(
        fileURL: URL,
        suggestedCategory: String,
        suggestedSubcategories: [String],
        confidence: Double,
        rationale: String,
        extractedKeywords: [String],
        fileEntityId: Int64? = nil
    ) {
        self.fileURL = fileURL.path
        self.fileName = fileURL.lastPathComponent
        self.suggestedCategory = suggestedCategory
        self.suggestedSubcategories = (try? String(data: JSONEncoder().encode(suggestedSubcategories), encoding: .utf8)) ?? "[]"
        self.confidence = confidence
        self.rationale = rationale
        self.status = confidence >= 0.8 ? .autoAccepted : .pending
        self.createdAt = Date()
        self.extractedKeywords = (try? String(data: JSONEncoder().encode(extractedKeywords), encoding: .utf8)) ?? "[]"
        self.fileEntityId = fileEntityId
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Feedback Manager

/// Manages the feedback queue and learning from human corrections
/// Uses the unified SortAIDatabase for persistence
final class FeedbackManager: FeedbackManaging, @unchecked Sendable {
    
    private let database: SortAIDatabase
    private let feedbackRepository: FeedbackRepository
    private let knowledgeGraph: KnowledgeGraphStore
    private let lock = NSLock()
    
    // Thresholds
    private let autoAcceptThreshold: Double = 0.85
    private let reviewThreshold: Double = 0.5
    
    /// Initialize with unified SortAIDatabase
    init(knowledgeGraph: KnowledgeGraphStore, database: SortAIDatabase? = nil) async throws {
        self.knowledgeGraph = knowledgeGraph
        self.database = database ?? SortAIDatabase.shared
        self.feedbackRepository = self.database.feedback
    }
    
    /// Legacy initializer for backward compatibility
    @available(*, deprecated, message: "Use init(knowledgeGraph:database:) instead. Database path is ignored.")
    convenience init(knowledgeGraph: KnowledgeGraphStore, databasePath: String?) async throws {
        try await self.init(knowledgeGraph: knowledgeGraph, database: nil)
    }
    
    // MARK: - Queue Operations
    
    /// Adds a categorization result to the feedback queue
    func addToQueue(
        fileURL: URL,
        category: String,
        subcategories: [String],
        confidence: Double,
        rationale: String,
        keywords: [String]
    ) async throws -> FeedbackItem {
        // Create file entity in knowledge graph
        let fileEntity = try knowledgeGraph.findOrCreateEntity(
            type: .file,
            name: fileURL.lastPathComponent,
            metadata: ["path": fileURL.path]
        )
        
        // Add to feedback repository (status is determined by confidence)
        let item = try feedbackRepository.add(
            fileURL: fileURL,
            category: category,
            subcategories: subcategories,
            confidence: confidence,
            rationale: rationale,
            keywords: keywords,
            fileEntityId: fileEntity.id
        )
        
        // Auto-learn from high-confidence results after insert
        if item.status == .autoAccepted {
            try await learnFromAcceptance(item: item)
        }
        
        return item
    }
    
    /// Gets items pending review
    func getPendingItems(limit: Int = 50) throws -> [FeedbackItem] {
        try feedbackRepository.getPending(limit: limit)
    }
    
    /// Gets recently processed items
    func getRecentItems(limit: Int = 50) throws -> [FeedbackItem] {
        try feedbackRepository.getRecent(limit: limit)
    }
    
    /// Gets queue statistics
    func getQueueStats() throws -> QueueStatistics {
        try feedbackRepository.statistics()
    }
    
    // MARK: - Human Feedback Processing
    
    /// Records human acceptance of the suggested category
    func acceptSuggestion(itemId: Int64) async throws {
        let item = try feedbackRepository.acceptSuggestion(itemId: itemId)
        try await learnFromAcceptance(item: item)
    }
    
    /// Records human correction with a different category
    func correctCategory(
        itemId: Int64,
        newCategory: String,
        newSubcategories: [String],
        notes: String? = nil
    ) async throws {
        let item = try feedbackRepository.correctCategory(
            itemId: itemId,
            newCategory: newCategory,
            newSubcategories: newSubcategories,
            notes: notes
        )
        
        try await learnFromCorrection(item: item, newCategory: newCategory, newSubcategories: newSubcategories)
    }
    
    /// Creates a new category from human input
    func createNewCategory(
        itemId: Int64,
        categoryPath: CategoryPath,
        notes: String? = nil
    ) async throws -> Entity {
        // Create the category in the knowledge graph
        let categoryEntity = try knowledgeGraph.getOrCreateCategoryPath(categoryPath)
        
        // Update the feedback item
        _ = try feedbackRepository.correctCategory(
            itemId: itemId,
            newCategory: categoryPath.root,
            newSubcategories: Array(categoryPath.components.dropFirst()),
            notes: notes
        )
        
        // Get the item for learning
        guard let item = try feedbackRepository.get(id: itemId) else {
            throw FeedbackError.itemNotFound(itemId)
        }
        
        try await learnFromCorrection(
            item: item,
            newCategory: categoryPath.root,
            newSubcategories: Array(categoryPath.components.dropFirst())
        )
        
        return categoryEntity
    }
    
    /// Skips an item for later review
    func skipItem(itemId: Int64) throws {
        _ = try feedbackRepository.skip(itemId: itemId)
    }
    
    // MARK: - Learning
    
    /// Learns from an accepted categorization
    private func learnFromAcceptance(item: FeedbackItem) async throws {
        let categoryPath = item.suggestedPath
        let categoryEntity = try knowledgeGraph.getOrCreateCategoryPath(categoryPath)
        
        // Record human confirmation if applicable
        if let fileId = item.fileEntityId {
            try knowledgeGraph.recordHumanConfirmation(fileId: fileId, categoryId: categoryEntity.id!)
        }
        
        // Learn keyword -> category associations
        for keyword in item.keywords {
            try knowledgeGraph.learnKeywordSuggestion(
                keyword: keyword,
                categoryId: categoryEntity.id!,
                weight: 0.3 * item.confidence  // Weight by confidence
            )
        }
        
        // Learn filename patterns
        let filenameKeywords = extractFilenameKeywords(item.fileName)
        for keyword in filenameKeywords {
            try knowledgeGraph.learnKeywordSuggestion(
                keyword: keyword,
                categoryId: categoryEntity.id!,
                weight: 0.5 * item.confidence  // Filename patterns are strong signals
            )
        }
    }
    
    /// Learns from a human correction
    private func learnFromCorrection(item: FeedbackItem, newCategory: String, newSubcategories: [String]) async throws {
        let oldPath = item.suggestedPath
        let newPath = CategoryPath(components: [newCategory] + newSubcategories)
        
        // Create the new category path
        let newCategoryEntity = try knowledgeGraph.getOrCreateCategoryPath(newPath)
        
        // Record the correction
        if let fileId = item.fileEntityId {
            // Record rejection of old category
            if let oldEntity = try? knowledgeGraph.findOrCreateEntity(type: .category, name: oldPath.description) {
                try knowledgeGraph.recordHumanRejection(fileId: fileId, categoryId: oldEntity.id!)
            }
            
            // Record confirmation of new category
            try knowledgeGraph.recordHumanConfirmation(fileId: fileId, categoryId: newCategoryEntity.id!)
        }
        
        // Learn from keywords - associate with new category
        for keyword in item.keywords {
            try knowledgeGraph.learnKeywordSuggestion(
                keyword: keyword,
                categoryId: newCategoryEntity.id!,
                weight: 0.7  // Human corrections are strong signals
            )
        }
        
        // Learn filename patterns - associate with new category
        let filenameKeywords = extractFilenameKeywords(item.fileName)
        for keyword in filenameKeywords {
            try knowledgeGraph.learnKeywordSuggestion(
                keyword: keyword,
                categoryId: newCategoryEntity.id!,
                weight: 0.9  // Filename patterns from corrections are very strong
            )
        }
    }
    
    /// Extracts keywords from a filename (nonisolated for sync use)
    private nonisolated func extractFilenameKeywords(_ filename: String) -> [String] {
        let withoutExtension = (filename as NSString).deletingPathExtension
        
        return withoutExtension
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .components(separatedBy: .whitespaces)
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 }  // Skip short tokens
    }
    
    // MARK: - Re-categorization
    
    /// Gets files that might match a newly created category
    func getFilesForRecategorization(categoryId: Int64, limit: Int = 50) async throws -> [FeedbackItem] {
        // Get keywords associated with this category
        let relationships = try knowledgeGraph.getRelationships(to: categoryId, type: .suggestsCategory)
        
        guard !relationships.isEmpty else { return [] }
        
        // Get the keywords
        var keywords: [String] = []
        for rel in relationships {
            if let entity = try knowledgeGraph.getEntity(id: rel.sourceId),
               entity.type == .keyword {
                keywords.append(entity.normalizedName)
            }
        }
        
        guard !keywords.isEmpty else { return [] }
        
        // Find files with matching keywords that weren't categorized into this category
        return try database.read { db in
            let sql = """
                SELECT * FROM feedback_queue
                WHERE status IN ('autoAccepted', 'humanAccepted')
                AND suggestedCategory != (
                    SELECT name FROM entities WHERE id = ?
                )
                ORDER BY createdAt DESC
                LIMIT ?
            """
            
            return try FeedbackItem.fetchAll(db, sql: sql, arguments: [categoryId, limit])
        }
    }
}

// MARK: - Errors

enum FeedbackError: LocalizedError {
    case itemNotFound(Int64)
    case invalidCategory(String)
    
    var errorDescription: String? {
        switch self {
        case .itemNotFound(let id):
            return "Feedback item not found: \(id)"
        case .invalidCategory(let name):
            return "Invalid category: \(name)"
        }
    }
}

// MARK: - Statistics

struct QueueStatistics: Sendable {
    let pendingReview: Int
    let autoAccepted: Int
    let humanAccepted: Int
    let humanCorrected: Int
    let total: Int
    
    var accuracy: Double {
        guard total > 0 else { return 0 }
        let correct = autoAccepted + humanAccepted
        return Double(correct) / Double(total)
    }
}

