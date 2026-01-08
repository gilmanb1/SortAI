// MARK: - Record Repository
// Repository for processing records (history of all processed files)

import Foundation
import GRDB

// MARK: - Record Repository

/// Manages ProcessingRecord persistence operations
final class RecordRepository: Sendable {
    
    private let database: SortAIDatabase
    
    init(database: SortAIDatabase) {
        self.database = database
    }
    
    // MARK: - Create Operations
    
    /// Saves a processing record
    @discardableResult
    func save(_ record: ProcessingRecord) throws -> ProcessingRecord {
        try database.write { db in
            try record.saved(db)
        }
    }
    
    /// Creates multiple records in a batch
    func saveBatch(_ records: [ProcessingRecord]) throws {
        try database.write { db in
            for record in records {
                _ = try record.saved(db)
            }
        }
    }
    
    // MARK: - Read Operations
    
    /// Gets a record by ID
    func get(id: String) throws -> ProcessingRecord? {
        try database.read { db in
            try ProcessingRecord.fetchOne(db, key: id)
        }
    }
    
    /// Checks if file was already processed (by checksum)
    func findByChecksum(_ checksum: String) throws -> ProcessingRecord? {
        try database.read { db in
            try ProcessingRecord
                .filter(Column("checksum") == checksum)
                .order(Column("processedAt").desc)
                .fetchOne(db)
        }
    }
    
    /// Returns processing history for a category
    func findByCategory(_ category: String, limit: Int = 100) throws -> [ProcessingRecord] {
        try database.read { db in
            try ProcessingRecord
                .filter(Column("assignedCategory") == category)
                .order(Column("processedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Returns records filtered by media kind
    func findByMediaKind(_ kind: MediaKind, limit: Int = 100) throws -> [ProcessingRecord] {
        try database.read { db in
            try ProcessingRecord
                .filter(Column("mediaKind") == kind.rawValue)
                .order(Column("processedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Returns recent processing records
    func getRecent(limit: Int = 50) throws -> [ProcessingRecord] {
        try database.read { db in
            try ProcessingRecord
                .order(Column("processedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Returns records that were overridden
    func getOverridden(limit: Int = 100) throws -> [ProcessingRecord] {
        try database.read { db in
            try ProcessingRecord
                .filter(Column("wasOverridden") == true)
                .order(Column("processedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Returns records from memory matches
    func getFromMemory(limit: Int = 100) throws -> [ProcessingRecord] {
        try database.read { db in
            try ProcessingRecord
                .filter(Column("wasFromMemory") == true)
                .order(Column("processedAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Counts total records
    func count() throws -> Int {
        try database.read { db in
            try ProcessingRecord.fetchCount(db)
        }
    }
    
    /// Counts records by category
    func countByCategory(_ category: String) throws -> Int {
        try database.read { db in
            try ProcessingRecord.filter(Column("assignedCategory") == category).fetchCount(db)
        }
    }
    
    // MARK: - Statistics
    
    /// Returns statistics for all categories
    func categoryStatistics() throws -> [CategoryStats] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT 
                    assignedCategory as category,
                    COUNT(*) as totalFiles,
                    AVG(confidence) as avgConfidence,
                    AVG(CASE WHEN wasOverridden THEN 1.0 ELSE 0.0 END) as overrideRate,
                    MAX(processedAt) as lastUsed
                FROM processing_records
                GROUP BY assignedCategory
                ORDER BY totalFiles DESC
                """)
            
            return rows.map { row in
                CategoryStats(
                    category: row["category"],
                    totalFiles: row["totalFiles"],
                    avgConfidence: row["avgConfidence"],
                    overrideRate: row["overrideRate"],
                    lastUsed: row["lastUsed"]
                )
            }
        }
    }
    
    /// Returns overall processing statistics
    func overallStatistics() throws -> RecordStatistics {
        try database.read { db in
            let total = try ProcessingRecord.fetchCount(db)
            let fromMemory = try ProcessingRecord.filter(Column("wasFromMemory") == true).fetchCount(db)
            let overridden = try ProcessingRecord.filter(Column("wasOverridden") == true).fetchCount(db)
            let avgConfidence = try Double.fetchOne(db, sql: "SELECT AVG(confidence) FROM processing_records") ?? 0.0
            
            return RecordStatistics(
                totalRecords: total,
                fromMemory: fromMemory,
                overridden: overridden,
                averageConfidence: avgConfidence
            )
        }
    }
    
    // MARK: - Update Operations
    
    /// Updates a record
    func update(_ record: ProcessingRecord) throws {
        try database.write { db in
            try record.update(db)
        }
    }
    
    /// Marks a record as overridden
    func markOverridden(id: String, newCategory: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE processing_records 
                    SET wasOverridden = 1, assignedCategory = ?
                    WHERE id = ?
                    """,
                arguments: [newCategory, id]
            )
        }
    }
    
    // MARK: - Delete Operations
    
    /// Deletes a record by ID
    func delete(id: String) throws -> Bool {
        try database.write { db in
            try ProcessingRecord.deleteOne(db, id: id)
        }
    }
    
    /// Deletes records older than a date
    func deleteOlderThan(_ date: Date) throws -> Int {
        try database.write { db in
            try ProcessingRecord.filter(Column("processedAt") < date).deleteAll(db)
        }
    }
    
    /// Deletes all records for a category
    func deleteByCategory(_ category: String) throws -> Int {
        try database.write { db in
            try ProcessingRecord.filter(Column("assignedCategory") == category).deleteAll(db)
        }
    }
}

// MARK: - Record Statistics

struct RecordStatistics: Sendable, Equatable {
    let totalRecords: Int
    let fromMemory: Int
    let overridden: Int
    let averageConfidence: Double
    
    var memoryHitRate: Double {
        guard totalRecords > 0 else { return 0 }
        return Double(fromMemory) / Double(totalRecords)
    }
    
    var overrideRate: Double {
        guard totalRecords > 0 else { return 0 }
        return Double(overridden) / Double(totalRecords)
    }
}

