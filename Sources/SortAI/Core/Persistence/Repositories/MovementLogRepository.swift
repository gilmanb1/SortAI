// MARK: - Movement Log Repository
// Repository for movement log entries (file operation history)

import Foundation
import GRDB

// MARK: - Movement Log Repository

/// Manages MovementLogEntry persistence operations
final class MovementLogRepository: Sendable {
    
    private let database: SortAIDatabase
    
    init(database: SortAIDatabase) {
        self.database = database
    }
    
    // MARK: - Create Operations
    
    /// Creates a new movement log entry
    @discardableResult
    func create(_ entry: MovementLogEntry) throws -> MovementLogEntry {
        try database.write { db in
            try entry.inserted(db)
        }
    }
    
    /// Creates multiple entries in a batch
    func createBatch(_ entries: [MovementLogEntry]) throws {
        try database.write { db in
            for entry in entries {
                _ = try entry.inserted(db)
            }
        }
    }
    
    // MARK: - Read Operations
    
    /// Gets an entry by ID
    func find(id: String) throws -> MovementLogEntry? {
        try database.read { db in
            try MovementLogEntry.fetchOne(db, key: id)
        }
    }
    
    /// Finds entries by source path
    func findBySource(_ source: URL, limit: Int = 100) throws -> [MovementLogEntry] {
        try database.read { db in
            try MovementLogEntry
                .filter(Column("source") == source.path)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Finds entries by destination path
    func findByDestination(_ destination: URL, limit: Int = 100) throws -> [MovementLogEntry] {
        try database.read { db in
            try MovementLogEntry
                .filter(Column("destination") == destination.path)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Finds all undoable entries (not yet undone)
    func findUndoable(limit: Int = 100) throws -> [MovementLogEntry] {
        try database.read { db in
            try MovementLogEntry
                .filter(Column("undoable") == true)
                .filter(Column("undoneAt") == nil)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Gets recent entries
    func getRecent(limit: Int = 50) throws -> [MovementLogEntry] {
        try database.read { db in
            try MovementLogEntry
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Gets entries by mode (full/degraded/offline)
    func findByMode(_ mode: MovementLogEntry.LLMMode, limit: Int = 100) throws -> [MovementLogEntry] {
        try database.read { db in
            try MovementLogEntry
                .filter(Column("mode") == mode.rawValue)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Gets entries by operation type
    func findByOperationType(_ type: MovementLogEntry.OperationType, limit: Int = 100) throws -> [MovementLogEntry] {
        try database.read { db in
            try MovementLogEntry
                .filter(Column("operationType") == type.rawValue)
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Counts total entries
    func count() throws -> Int {
        try database.read { db in
            try MovementLogEntry.fetchCount(db)
        }
    }
    
    /// Counts undoable entries
    func countUndoable() throws -> Int {
        try database.read { db in
            try MovementLogEntry
                .filter(Column("undoable") == true)
                .filter(Column("undoneAt") == nil)
                .fetchCount(db)
        }
    }
    
    // MARK: - Update Operations
    
    /// Updates an entry
    func update(_ entry: MovementLogEntry) throws {
        try database.write { db in
            try entry.update(db)
        }
    }
    
    /// Marks an entry as undone
    func markUndone(id: String, timestamp: Date = Date()) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE movement_log 
                    SET undoneAt = ?
                    WHERE id = ? AND undoable = 1
                    """,
                arguments: [timestamp, id]
            )
        }
    }
    
    // MARK: - Delete Operations
    
    /// Deletes an entry by ID
    func delete(id: String) throws -> Bool {
        try database.write { db in
            try MovementLogEntry.deleteOne(db, key: id)
        }
    }
    
    /// Deletes entries older than retention period (default 90 days)
    func cleanupOldEntries(retentionDays: Int = 90) throws -> Int {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        return try database.write { db in
            try MovementLogEntry
                .filter(Column("timestamp") < cutoffDate)
                .deleteAll(db)
        }
    }
    
    /// Deletes all undone entries older than a date
    func deleteUndoneOlderThan(_ date: Date) throws -> Int {
        try database.write { db in
            try MovementLogEntry
                .filter(Column("undoneAt") != nil)
                .filter(Column("undoneAt") < date)
                .deleteAll(db)
        }
    }
    
    // MARK: - Statistics
    
    /// Returns statistics about movement log
    func statistics() throws -> MovementLogStatistics {
        try database.read { db in
            let total = try MovementLogEntry.fetchCount(db)
            let undoable = try MovementLogEntry
                .filter(Column("undoable") == true)
                .filter(Column("undoneAt") == nil)
                .fetchCount(db)
            let undone = try MovementLogEntry
                .filter(Column("undoneAt") != nil)
                .fetchCount(db)
            
            let avgConfidence = try Double.fetchOne(
                db,
                sql: "SELECT AVG(confidence) FROM movement_log"
            ) ?? 0.0
            
            return MovementLogStatistics(
                totalEntries: total,
                undoableEntries: undoable,
                undoneEntries: undone,
                averageConfidence: avgConfidence
            )
        }
    }
}

// MARK: - Movement Log Statistics

struct MovementLogStatistics: Sendable, Equatable {
    let totalEntries: Int
    let undoableEntries: Int
    let undoneEntries: Int
    let averageConfidence: Double
    
    var undoneRate: Double {
        guard totalEntries > 0 else { return 0 }
        return Double(undoneEntries) / Double(totalEntries)
    }
}

