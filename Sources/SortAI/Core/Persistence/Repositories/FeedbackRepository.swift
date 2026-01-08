// MARK: - Feedback Repository
// Repository for human-in-the-loop feedback queue

import Foundation
import GRDB

// MARK: - Feedback Repository

/// Manages FeedbackItem persistence operations
final class FeedbackRepository: Sendable {
    
    private let database: SortAIDatabase
    
    // Thresholds
    private let autoAcceptThreshold: Double = 0.85
    private let reviewThreshold: Double = 0.5
    
    init(database: SortAIDatabase) {
        self.database = database
    }
    
    // MARK: - Create Operations
    
    /// Adds a categorization result to the feedback queue
    @discardableResult
    func add(
        fileURL: URL,
        category: String,
        subcategories: [String],
        confidence: Double,
        rationale: String,
        keywords: [String],
        fileEntityId: Int64? = nil
    ) throws -> FeedbackItem {
        // Determine status based on confidence
        let status: FeedbackItem.FeedbackStatus
        if confidence >= autoAcceptThreshold {
            status = .autoAccepted
        } else {
            status = .pending
        }
        
        var item = FeedbackItem(
            fileURL: fileURL,
            suggestedCategory: category,
            suggestedSubcategories: subcategories,
            confidence: confidence,
            rationale: rationale,
            extractedKeywords: keywords,
            fileEntityId: fileEntityId
        )
        item.status = status
        
        try database.write { db in
            try item.insert(db)
            // Explicitly set id if not set by didInsert callback
            if item.id == nil {
                item.id = db.lastInsertedRowID
            }
        }
        
        return item
    }
    
    /// Creates multiple feedback items in a batch
    @discardableResult
    func addBatch(_ items: [FeedbackItem]) throws -> [FeedbackItem] {
        try database.write { db in
            var result: [FeedbackItem] = []
            for var item in items {
                try item.insert(db)
                if item.id == nil {
                    item.id = db.lastInsertedRowID
                }
                result.append(item)
            }
            return result
        }
    }
    
    // MARK: - Read Operations
    
    /// Gets a feedback item by ID
    func get(id: Int64) throws -> FeedbackItem? {
        try database.read { db in
            try FeedbackItem.fetchOne(db, key: id)
        }
    }
    
    /// Gets items pending review
    func getPending(limit: Int = 50) throws -> [FeedbackItem] {
        try database.read { db in
            try FeedbackItem
                .filter(Column("status") == FeedbackItem.FeedbackStatus.pending.rawValue)
                .order(Column("confidence").asc)  // Lowest confidence first
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Gets recently processed items
    func getRecent(limit: Int = 50) throws -> [FeedbackItem] {
        try database.read { db in
            try FeedbackItem
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Gets items by status
    func getByStatus(_ status: FeedbackItem.FeedbackStatus, limit: Int = 50) throws -> [FeedbackItem] {
        try database.read { db in
            try FeedbackItem
                .filter(Column("status") == status.rawValue)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Gets items for a specific file
    func findByFileURL(_ url: URL) throws -> [FeedbackItem] {
        try database.read { db in
            try FeedbackItem
                .filter(Column("fileURL") == url.path)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }
    
    /// Counts items by status
    func count(status: FeedbackItem.FeedbackStatus? = nil) throws -> Int {
        try database.read { db in
            if let status = status {
                return try FeedbackItem.filter(Column("status") == status.rawValue).fetchCount(db)
            }
            return try FeedbackItem.fetchCount(db)
        }
    }
    
    // MARK: - Statistics
    
    /// Gets queue statistics
    func statistics() throws -> QueueStatistics {
        try database.read { db in
            let pending = try FeedbackItem
                .filter(Column("status") == FeedbackItem.FeedbackStatus.pending.rawValue)
                .fetchCount(db)
            
            let autoAccepted = try FeedbackItem
                .filter(Column("status") == FeedbackItem.FeedbackStatus.autoAccepted.rawValue)
                .fetchCount(db)
            
            let humanAccepted = try FeedbackItem
                .filter(Column("status") == FeedbackItem.FeedbackStatus.humanAccepted.rawValue)
                .fetchCount(db)
            
            let humanCorrected = try FeedbackItem
                .filter(Column("status") == FeedbackItem.FeedbackStatus.humanCorrected.rawValue)
                .fetchCount(db)
            
            let total = try FeedbackItem.fetchCount(db)
            
            return QueueStatistics(
                pendingReview: pending,
                autoAccepted: autoAccepted,
                humanAccepted: humanAccepted,
                humanCorrected: humanCorrected,
                total: total
            )
        }
    }
    
    // MARK: - Update Operations
    
    /// Updates a feedback item
    func update(_ item: FeedbackItem) throws {
        try database.write { db in
            try item.update(db)
        }
    }
    
    /// Records human acceptance of the suggested category
    func acceptSuggestion(itemId: Int64) throws -> FeedbackItem {
        try database.write { db in
            guard var item = try FeedbackItem.fetchOne(db, key: itemId) else {
                throw DatabaseError.recordNotFound("FeedbackItem:\(itemId)")
            }
            
            item.status = .humanAccepted
            item.reviewedAt = Date()
            try item.update(db)
            return item
        }
    }
    
    /// Records human correction with a different category
    func correctCategory(
        itemId: Int64,
        newCategory: String,
        newSubcategories: [String],
        notes: String? = nil
    ) throws -> FeedbackItem {
        try database.write { db in
            guard var item = try FeedbackItem.fetchOne(db, key: itemId) else {
                throw DatabaseError.recordNotFound("FeedbackItem:\(itemId)")
            }
            
            item.status = .humanCorrected
            item.humanCategory = newCategory
            item.humanSubcategories = try? String(data: JSONEncoder().encode(newSubcategories), encoding: .utf8)
            item.feedbackNotes = notes
            item.reviewedAt = Date()
            try item.update(db)
            return item
        }
    }
    
    /// Skips an item for later review
    func skip(itemId: Int64) throws -> FeedbackItem {
        try database.write { db in
            guard var item = try FeedbackItem.fetchOne(db, key: itemId) else {
                throw DatabaseError.recordNotFound("FeedbackItem:\(itemId)")
            }
            
            item.status = .skipped
            try item.update(db)
            return item
        }
    }
    
    /// Updates item status
    func updateStatus(itemId: Int64, status: FeedbackItem.FeedbackStatus) throws {
        try database.write { db in
            try db.execute(
                sql: "UPDATE feedback_queue SET status = ?, reviewedAt = ? WHERE id = ?",
                arguments: [status.rawValue, Date(), itemId]
            )
        }
    }
    
    // MARK: - Delete Operations
    
    /// Deletes a feedback item by ID
    func delete(id: Int64) throws -> Bool {
        try database.write { db in
            try FeedbackItem.deleteOne(db, key: id)
        }
    }
    
    /// Deletes items older than a date
    func deleteOlderThan(_ date: Date) throws -> Int {
        try database.write { db in
            try FeedbackItem.filter(Column("createdAt") < date).deleteAll(db)
        }
    }
    
    /// Deletes all items with a specific status
    func deleteByStatus(_ status: FeedbackItem.FeedbackStatus) throws -> Int {
        try database.write { db in
            try FeedbackItem.filter(Column("status") == status.rawValue).deleteAll(db)
        }
    }
    
    // MARK: - Batch Operations
    
    /// Accepts multiple items at once
    func acceptBatch(itemIds: [Int64]) throws -> Int {
        try database.write { db in
            var count = 0
            for itemId in itemIds {
                if var item = try FeedbackItem.fetchOne(db, key: itemId) {
                    item.status = .humanAccepted
                    item.reviewedAt = Date()
                    try item.update(db)
                    count += 1
                }
            }
            return count
        }
    }
    
    /// Skips multiple items at once
    func skipBatch(itemIds: [Int64]) throws -> Int {
        try database.write { db in
            var count = 0
            for itemId in itemIds {
                if var item = try FeedbackItem.fetchOne(db, key: itemId) {
                    item.status = .skipped
                    try item.update(db)
                    count += 1
                }
            }
            return count
        }
    }
}

