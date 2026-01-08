// MARK: - Pattern Repository
// Repository for learned patterns (vector embeddings from user corrections)

import Foundation
import GRDB

// MARK: - Pattern Repository

/// Manages LearnedPattern persistence operations
final class PatternRepository: Sendable {
    
    private let database: SortAIDatabase
    private let embeddingDimensions: Int
    private let similarityThreshold: Double
    
    init(database: SortAIDatabase, embeddingDimensions: Int = 384, similarityThreshold: Double = 0.85) {
        self.database = database
        self.embeddingDimensions = embeddingDimensions
        self.similarityThreshold = similarityThreshold
    }
    
    // MARK: - Create Operations
    
    /// Saves a new learned pattern
    @discardableResult
    func save(_ pattern: LearnedPattern) throws -> LearnedPattern {
        // Validate embedding dimensions
        let dims = pattern.embedding.count
        guard dims == embeddingDimensions else {
            throw DatabaseError.invalidData("Embedding dimension mismatch: expected \(embeddingDimensions), got \(dims)")
        }
        
        return try database.write { db in
            try pattern.saved(db)
        }
    }
    
    /// Creates or updates a pattern (upsert)
    @discardableResult
    func saveOrUpdate(_ pattern: LearnedPattern) throws -> LearnedPattern {
        let dims = pattern.embedding.count
        guard dims == embeddingDimensions else {
            throw DatabaseError.invalidData("Embedding dimension mismatch: expected \(embeddingDimensions), got \(dims)")
        }
        
        return try database.write { db in
            if try LearnedPattern.fetchOne(db, key: pattern.id) != nil {
                var updated = pattern
                updated.updatedAt = Date()
                try updated.update(db)
                return updated
            } else {
                return try pattern.inserted(db)
            }
        }
    }
    
    // MARK: - Read Operations
    
    /// Gets a pattern by ID
    func get(id: String) throws -> LearnedPattern? {
        try database.read { db in
            try LearnedPattern.fetchOne(db, key: id)
        }
    }
    
    /// Finds pattern by exact checksum match
    func findByChecksum(_ checksum: String) throws -> LearnedPattern? {
        try database.read { db in
            try LearnedPattern
                .filter(LearnedPattern.Columns.checksum == checksum)
                .fetchOne(db)
        }
    }
    
    /// Gets patterns by label
    func findByLabel(_ label: String) throws -> [LearnedPattern] {
        try database.read { db in
            try LearnedPattern
                .filter(LearnedPattern.Columns.label == label)
                .order(LearnedPattern.Columns.confidence.desc)
                .fetchAll(db)
        }
    }
    
    /// Gets all patterns
    func getAll(limit: Int = 1000) throws -> [LearnedPattern] {
        try database.read { db in
            try LearnedPattern
                .order(LearnedPattern.Columns.hitCount.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Gets all unique labels
    func getAllLabels() throws -> [String] {
        try database.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT DISTINCT label FROM learned_patterns ORDER BY label"
            )
        }
    }
    
    /// Counts patterns
    func count() throws -> Int {
        try database.read { db in
            try LearnedPattern.fetchCount(db)
        }
    }
    
    /// Alias for count() - counts all patterns
    func countAll() throws -> Int {
        try count()
    }
    
    /// Deletes all patterns
    func deleteAll() throws -> Int {
        try database.write { db in
            try LearnedPattern.deleteAll(db)
        }
    }
    
    // MARK: - Vector Similarity Operations
    
    /// Queries patterns by vector similarity (k-nearest neighbors)
    func queryNearest(
        to embedding: [Float],
        k: Int = 5,
        minSimilarity: Double? = nil
    ) throws -> [MemoryMatch] {
        guard embedding.count == embeddingDimensions else {
            throw DatabaseError.invalidData("Embedding dimension mismatch: expected \(embeddingDimensions), got \(embedding.count)")
        }
        
        let threshold = minSimilarity ?? similarityThreshold
        
        // Fetch all patterns and compute distances in memory
        // For large datasets, consider using sqlite-vss extension
        let patterns = try database.read { db in
            try LearnedPattern.fetchAll(db)
        }
        
        var matches: [MemoryMatch] = []
        
        for pattern in patterns {
            let distance = Self.cosineDistance(a: embedding, b: pattern.embedding)
            let similarity = 1.0 - (distance / 2.0)
            
            if similarity >= threshold {
                matches.append(MemoryMatch(pattern: pattern, distance: distance))
            }
        }
        
        // Sort by distance (ascending) and take top k
        return Array(matches.sorted { $0.distance < $1.distance }.prefix(k))
    }
    
    /// Finds the best matching pattern for a given embedding
    func findBestMatch(for embedding: [Float]) throws -> MemoryMatch? {
        let matches = try queryNearest(to: embedding, k: 1)
        return matches.first
    }
    
    // MARK: - Update Operations
    
    /// Updates a pattern
    func update(_ pattern: LearnedPattern) throws {
        var mutablePattern = pattern
        mutablePattern.updatedAt = Date()
        try database.write { db in
            try mutablePattern.update(db)
        }
    }
    
    /// Increments hit count for a pattern
    func recordHit(patternId: String) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE learned_patterns 
                    SET hitCount = hitCount + 1, updatedAt = ?
                    WHERE id = ?
                    """,
                arguments: [Date(), patternId]
            )
        }
    }
    
    /// Updates pattern confidence
    func updateConfidence(patternId: String, confidence: Double) throws {
        let clampedConfidence = min(1.0, max(0.0, confidence))
        try database.write { db in
            try db.execute(
                sql: "UPDATE learned_patterns SET confidence = ?, updatedAt = ? WHERE id = ?",
                arguments: [clampedConfidence, Date(), patternId]
            )
        }
    }
    
    // MARK: - Delete Operations
    
    /// Deletes a pattern by ID
    func delete(id: String) throws -> Bool {
        try database.write { db in
            try LearnedPattern.deleteOne(db, id: id)
        }
    }
    
    /// Deletes patterns below confidence threshold
    func pruneWeakPatterns(minConfidence: Double = 0.3, minHits: Int = 0) throws -> Int {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM learned_patterns 
                    WHERE confidence < ? AND hitCount <= ?
                    """,
                arguments: [minConfidence, minHits]
            )
            return db.changesCount
        }
    }
    
    /// Deletes all patterns for a label
    func deleteByLabel(_ label: String) throws -> Int {
        try database.write { db in
            try LearnedPattern.filter(LearnedPattern.Columns.label == label).deleteAll(db)
        }
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
        return 1.0 - similarity
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
    
    /// Removes patterns below confidence threshold with low hit counts
    func prune(minConfidence: Double = 0.3, minHits: Int = 0) throws -> Int {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM learned_patterns 
                    WHERE confidence < ? AND hitCount <= ?
                    """,
                arguments: [minConfidence, minHits]
            )
            return db.changesCount
        }
    }
}

