// MARK: - Memory Store (The Memory)
// Persistence for learned patterns and processing history using unified SortAIDatabase

import Foundation
import GRDB

// MARK: - Memory Store Errors

enum MemoryStoreError: LocalizedError {
    case databaseNotInitialized
    case embeddingDimensionMismatch(expected: Int, got: Int)
    case patternNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .databaseNotInitialized:
            return "Database not initialized"
        case .embeddingDimensionMismatch(let expected, let got):
            return "Embedding dimension mismatch: expected \(expected), got \(got)"
        case .patternNotFound(let id):
            return "Pattern not found: \(id)"
        }
    }
}

// MARK: - Memory Query Result

struct MemoryMatch: Sendable {
    let pattern: LearnedPattern
    let distance: Double  // Cosine distance (0 = identical, 2 = opposite)
    
    var similarity: Double {
        1.0 - (distance / 2.0)  // Convert to 0-1 similarity
    }
}

// MARK: - Memory Store

/// The "Memory" of SortAI - stores learned patterns as vector embeddings
/// Uses the unified SortAIDatabase for persistence
final class MemoryStore: PatternMatching, Sendable {
    
    // MARK: - Properties
    
    private let database: SortAIDatabase
    private let patternRepository: PatternRepository
    private let recordRepository: RecordRepository
    private let embeddingDimensions: Int
    private let similarityThreshold: Double
    
    // MARK: - Initialization
    
    /// Initialize with the unified SortAIDatabase
    init(
        database: SortAIDatabase? = nil,
        embeddingDimensions: Int = 384,
        similarityThreshold: Double = 0.85
    ) throws {
        self.database = database ?? SortAIDatabase.shared
        self.embeddingDimensions = embeddingDimensions
        self.similarityThreshold = similarityThreshold
        self.patternRepository = PatternRepository(
            database: self.database,
            embeddingDimensions: embeddingDimensions,
            similarityThreshold: similarityThreshold
        )
        self.recordRepository = self.database.records
    }
    
    /// Legacy initializer for backward compatibility
    @available(*, deprecated, message: "Use init(database:embeddingDimensions:similarityThreshold:) instead. Path is ignored.")
    convenience init(
        path: String?,
        embeddingDimensions: Int = 384,
        similarityThreshold: Double = 0.85
    ) throws {
        try self.init(database: nil, embeddingDimensions: embeddingDimensions, similarityThreshold: similarityThreshold)
    }
    
    /// In-memory database for testing
    static func inMemory(embeddingDimensions: Int = 384) throws -> MemoryStore {
        let db = try SortAIDatabase.inMemory()
        return try MemoryStore(database: db, embeddingDimensions: embeddingDimensions)
    }
    
    // MARK: - Pattern Operations
    
    /// Saves a new learned pattern from user correction
    func savePattern(_ pattern: LearnedPattern) throws {
        try patternRepository.save(pattern)
    }
    
    /// Updates an existing pattern (e.g., increment hit count)
    func updatePattern(_ pattern: LearnedPattern) throws {
        try patternRepository.update(pattern)
    }
    
    /// Finds pattern by exact checksum match
    func findByChecksum(_ checksum: String) throws -> LearnedPattern? {
        try patternRepository.findByChecksum(checksum)
    }
    
    /// Queries patterns by vector similarity (k-nearest neighbors)
    func queryNearest(
        to embedding: [Float],
        k: Int = 5,
        minSimilarity: Double? = nil
    ) throws -> [MemoryMatch] {
        try patternRepository.queryNearest(to: embedding, k: k, minSimilarity: minSimilarity)
    }
    
    /// Finds the best matching pattern for a given embedding
    func findBestMatch(for embedding: [Float]) throws -> MemoryMatch? {
        let matches = try queryNearest(to: embedding, k: 1)
        return matches.first
    }
    
    /// Increments hit count for a pattern
    func recordHit(patternId: String) throws {
        try patternRepository.recordHit(patternId: patternId)
    }
    
    // MARK: - Protocol Conformance (PatternMatching)
    
    /// Protocol method - queries for nearest pattern above threshold
    func queryNearest(embedding: [Float], threshold: Double) throws -> (LearnedPattern, Double)? {
        let matches = try queryNearest(to: embedding, k: 1, minSimilarity: threshold)
        guard let match = matches.first else { return nil }
        return (match.pattern, match.similarity)
    }
    
    /// Protocol method - saves a pattern from a categorization result
    func savePattern(
        signature: FileSignature,
        embedding: [Float],
        label: String,
        originalLabel: String?,
        confidence: Double
    ) throws {
        let pattern = LearnedPattern(
            checksum: signature.checksum,
            embedding: embedding,
            label: label,
            originalLabel: originalLabel,
            confidence: confidence,
            createdAt: Date()
        )
        try savePattern(pattern)
    }
    
    /// Deletes a pattern
    func deletePattern(id: String) throws {
        _ = try patternRepository.delete(id: id)
    }
    
    /// Returns all patterns for a given label
    func patternsForLabel(_ label: String) throws -> [LearnedPattern] {
        try patternRepository.findByLabel(label)
    }
    
    /// Returns all unique labels
    func allLabels() throws -> [String] {
        try patternRepository.getAllLabels()
    }
    
    // MARK: - Processing Records
    
    /// Saves a processing record
    func saveRecord(_ record: ProcessingRecord) throws {
        try recordRepository.save(record)
    }
    
    /// Checks if file was already processed (by checksum)
    func wasProcessed(checksum: String) throws -> ProcessingRecord? {
        try recordRepository.findByChecksum(checksum)
    }
    
    /// Returns processing history for a category
    func historyForCategory(_ category: String, limit: Int = 100) throws -> [ProcessingRecord] {
        try recordRepository.findByCategory(category, limit: limit)
    }
    
    // MARK: - Statistics
    
    /// Returns statistics for all categories
    func categoryStatistics() throws -> [CategoryStats] {
        try recordRepository.categoryStatistics()
    }
    
    /// Returns total pattern count
    func patternCount() throws -> Int {
        try patternRepository.count()
    }
    
    /// Returns total record count
    func recordCount() throws -> Int {
        try recordRepository.count()
    }
    
    // MARK: - Vector Math
    
    /// Computes cosine distance between two vectors
    /// Returns 0 for identical vectors, 2 for opposite vectors
    static func cosineDistance(a: [Float], b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 2.0 }
        
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 2.0 }
        
        let similarity = Double(dot / denom)
        return 1.0 - similarity  // Convert to distance
    }
    
    /// Computes Euclidean distance between two vectors
    static func euclideanDistance(a: [Float], b: [Float]) -> Double {
        guard a.count == b.count else { return .infinity }
        
        var sum: Float = 0
        for i in 0..<a.count {
            let diff = a[i] - b[i]
            sum += diff * diff
        }
        
        return Double(sqrt(sum))
    }
    
    // MARK: - Maintenance
    
    /// Removes old patterns below confidence threshold
    func pruneWeakPatterns(minConfidence: Double = 0.3, minHits: Int = 0) throws -> Int {
        try patternRepository.prune(minConfidence: minConfidence, minHits: minHits)
    }
    
    /// Vacuum database to reclaim space
    func vacuum() throws {
        try database.vacuum()
    }
}

