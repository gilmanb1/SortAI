// MARK: - Learned Pattern Model
// Vector embedding storage for user corrections

import Foundation
import GRDB

/// Represents a learned pattern from user corrections (Undo actions)
/// Stored as vector embeddings to prevent repeat classification errors
struct LearnedPattern: Codable, Sendable, Identifiable {
    var id: String
    var checksum: String          // File checksum for exact match lookup
    var embeddingData: Data       // Serialized Float array
    var label: String             // Corrected category label
    var originalLabel: String?    // What the Brain originally predicted
    var confidence: Double        // Confidence in this pattern
    var hitCount: Int             // How many times this pattern was matched
    var createdAt: Date
    var updatedAt: Date
    
    // MARK: - Embedding Accessors
    
    var embedding: [Float] {
        get {
            LearnedPattern.decodeEmbedding(embeddingData)
        }
        set {
            embeddingData = LearnedPattern.encodeEmbedding(newValue)
        }
    }
    
    // MARK: - Initialization
    
    init(
        id: String = UUID().uuidString,
        checksum: String,
        embedding: [Float],
        label: String,
        originalLabel: String? = nil,
        confidence: Double = 1.0,
        hitCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.checksum = checksum
        self.embeddingData = LearnedPattern.encodeEmbedding(embedding)
        self.label = label
        self.originalLabel = originalLabel
        self.confidence = confidence
        self.hitCount = hitCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // MARK: - Embedding Serialization
    
    static func encodeEmbedding(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
    
    static func decodeEmbedding(_ data: Data) -> [Float] {
        data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }
}

// MARK: - GRDB Conformance

extension LearnedPattern: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "learned_patterns" }
    
    // Define columns for type-safe queries
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let checksum = Column(CodingKeys.checksum)
        static let embeddingData = Column(CodingKeys.embeddingData)
        static let label = Column(CodingKeys.label)
        static let originalLabel = Column(CodingKeys.originalLabel)
        static let confidence = Column(CodingKeys.confidence)
        static let hitCount = Column(CodingKeys.hitCount)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

// MARK: - Processing History

/// Tracks all processed files for analytics and deduplication
struct ProcessingRecord: Codable, Sendable, Identifiable {
    var id: String
    var fileURL: String
    var checksum: String
    var mediaKind: String
    var assignedCategory: String
    var confidence: Double
    var wasFromMemory: Bool
    var wasOverridden: Bool
    var processedAt: Date
    
    init(
        id: String = UUID().uuidString,
        fileURL: URL,
        checksum: String,
        mediaKind: MediaKind,
        assignedCategory: String,
        confidence: Double,
        wasFromMemory: Bool = false,
        wasOverridden: Bool = false,
        processedAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL.absoluteString
        self.checksum = checksum
        self.mediaKind = mediaKind.rawValue
        self.assignedCategory = assignedCategory
        self.confidence = confidence
        self.wasFromMemory = wasFromMemory
        self.wasOverridden = wasOverridden
        self.processedAt = processedAt
    }
}

extension ProcessingRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "processing_records" }
}

// MARK: - Category Statistics

/// Aggregated statistics per category
struct CategoryStats: Codable, Sendable {
    let category: String
    let totalFiles: Int
    let avgConfidence: Double
    let overrideRate: Double
    let lastUsed: Date?
}

