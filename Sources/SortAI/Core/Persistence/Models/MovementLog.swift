// MARK: - Movement Log
// Durable log of all file movement operations for undo and audit trail

import Foundation
import GRDB

// MARK: - Movement Log Entry

/// Represents a single file movement operation in the log
struct MovementLogEntry: Codable, Sendable, Identifiable {
    var id: String
    var timestamp: Date
    var source: String  // Source file path
    var destination: String  // Destination file path
    var reason: String  // Categorization reason
    var confidence: Double
    var mode: LLMMode  // full/degraded/offline
    var provider: String?  // LLM provider identifier
    var providerVersion: String?  // Optional provider version
    var operationType: OperationType
    var undoable: Bool
    var undoneAt: Date?
    
    enum LLMMode: String, Codable, DatabaseValueConvertible {
        case full
        case degraded
        case offline
    }
    
    enum OperationType: String, Codable, DatabaseValueConvertible {
        case move
        case copy
        case symlink
    }
    
    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        source: URL,
        destination: URL,
        reason: String,
        confidence: Double,
        mode: LLMMode,
        provider: String? = nil,
        providerVersion: String? = nil,
        operationType: OperationType,
        undoable: Bool = true,
        undoneAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source.path
        self.destination = destination.path
        self.reason = reason
        self.confidence = confidence
        self.mode = mode
        self.provider = provider
        self.providerVersion = providerVersion
        self.operationType = operationType
        self.undoable = undoable
        self.undoneAt = undoneAt
    }
    
    /// Returns source as URL
    var sourceURL: URL {
        URL(fileURLWithPath: source)
    }
    
    /// Returns destination as URL
    var destinationURL: URL {
        URL(fileURLWithPath: destination)
    }
}

// MARK: - GRDB Conformance

extension MovementLogEntry: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "movement_log" }
    
    // Define columns for type-safe queries
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let timestamp = Column(CodingKeys.timestamp)
        static let source = Column(CodingKeys.source)
        static let destination = Column(CodingKeys.destination)
        static let reason = Column(CodingKeys.reason)
        static let confidence = Column(CodingKeys.confidence)
        static let mode = Column(CodingKeys.mode)
        static let provider = Column(CodingKeys.provider)
        static let providerVersion = Column(CodingKeys.providerVersion)
        static let operationType = Column(CodingKeys.operationType)
        static let undoable = Column(CodingKeys.undoable)
        static let undoneAt = Column(CodingKeys.undoneAt)
    }
}

