// MARK: - Prototype Store
// Category prototype vectors with EMA decay and shared prototypes
// Spec requirement: "PrototypeStore with shared prototypes (linked folders), EMA decay, version tagging"

import Foundation
import GRDB

// MARK: - Category Prototype

/// Prototype vector for a category with EMA-updated embedding
struct CategoryPrototype: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "category_prototypes"
    
    var id: String  // Category path hash
    let categoryPath: String  // Full category path (e.g., "Work/Projects/Active")
    let categoryName: String  // Last component of path
    var embeddingData: Data  // EMA-averaged embedding
    let dimensions: Int
    var sampleCount: Int  // Number of files that contributed
    var confidence: Double  // Confidence in this prototype
    var version: Int  // Version for tracking updates
    var scope: PrototypeScope  // Folder-scoped or shared
    var linkedFolders: [String]  // Paths of folders sharing this prototype
    var createdAt: Date
    var updatedAt: Date
    
    // MARK: - Scope
    
    enum PrototypeScope: String, Codable, DatabaseValueConvertible {
        case folderScoped  // Only applies to one folder
        case shared  // Shared across linked folders
        case global  // Global prototype (system default)
    }
    
    // MARK: - Embedding Accessors
    
    var embedding: [Float] {
        get { Self.decodeEmbedding(embeddingData) }
        set { embeddingData = Self.encodeEmbedding(newValue) }
    }
    
    static func encodeEmbedding(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
    
    static func decodeEmbedding(_ data: Data) -> [Float] {
        data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }
    
    // MARK: - Initialization
    
    init(
        categoryPath: String,
        embedding: [Float],
        scope: PrototypeScope = .folderScoped,
        linkedFolders: [String] = []
    ) {
        self.id = Self.generateId(for: categoryPath)
        self.categoryPath = categoryPath
        self.categoryName = categoryPath.components(separatedBy: "/").last ?? categoryPath
        self.embeddingData = Self.encodeEmbedding(embedding)
        self.dimensions = embedding.count
        self.sampleCount = 1
        self.confidence = 0.5
        self.version = 1
        self.scope = scope
        self.linkedFolders = linkedFolders
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    static func generateId(for categoryPath: String) -> String {
        var hasher = Hasher()
        hasher.combine(categoryPath.lowercased())
        return String(format: "%016llx", UInt64(bitPattern: Int64(hasher.finalize())))
    }
    
    // MARK: - Column Definitions
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let categoryPath = Column(CodingKeys.categoryPath)
        static let categoryName = Column(CodingKeys.categoryName)
        static let embeddingData = Column(CodingKeys.embeddingData)
        static let dimensions = Column(CodingKeys.dimensions)
        static let sampleCount = Column(CodingKeys.sampleCount)
        static let confidence = Column(CodingKeys.confidence)
        static let version = Column(CodingKeys.version)
        static let scope = Column(CodingKeys.scope)
        static let linkedFolders = Column(CodingKeys.linkedFolders)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

// MARK: - Prototype Store Actor

/// Thread-safe store for category prototypes with EMA updates
actor PrototypeStore {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// EMA decay factor (higher = slower adaptation, more stable)
        /// α in: new_prototype = α * old_prototype + (1 - α) * new_embedding
        let emaDecay: Float
        
        /// Minimum samples before prototype is considered reliable
        let minSamplesForReliability: Int
        
        /// Maximum confidence value
        let maxConfidence: Double
        
        /// Confidence boost per new sample
        let confidenceBoostPerSample: Double
        
        /// Confidence decay rate (per day without updates)
        let confidenceDecayRate: Double
        
        static let `default` = Configuration(
            emaDecay: 0.9,
            minSamplesForReliability: 3,
            maxConfidence: 0.95,
            confidenceBoostPerSample: 0.05,
            confidenceDecayRate: 0.01
        )
        
        static let aggressive = Configuration(
            emaDecay: 0.7,
            minSamplesForReliability: 2,
            maxConfidence: 0.95,
            confidenceBoostPerSample: 0.1,
            confidenceDecayRate: 0.02
        )
        
        static let conservative = Configuration(
            emaDecay: 0.95,
            minSamplesForReliability: 5,
            maxConfidence: 0.9,
            confidenceBoostPerSample: 0.03,
            confidenceDecayRate: 0.005
        )
    }
    
    // MARK: - Properties
    
    private let database: SortAIDatabase?
    private let config: Configuration
    
    // In-memory cache
    private var prototypeCache: [String: CategoryPrototype] = [:]
    private var cacheLoaded: Bool = false
    
    // MARK: - Initialization
    
    init(database: SortAIDatabase? = nil, configuration: Configuration = .default) {
        self.database = database ?? SortAIDatabase.sharedOrNil
        self.config = configuration
    }
    
    /// Whether persistence is available
    private var hasPersistence: Bool {
        database != nil
    }
    
    /// Gets the database, throwing if unavailable
    private func requireDatabase() throws -> SortAIDatabase {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return db
    }
    
    // MARK: - Prototype Operations
    
    /// Get prototype for a category
    func getPrototype(for categoryPath: String) async throws -> CategoryPrototype? {
        try await ensureCacheLoaded()
        let id = CategoryPrototype.generateId(for: categoryPath)
        return prototypeCache[id]
    }
    
    /// Get all prototypes
    func getAllPrototypes() async throws -> [CategoryPrototype] {
        try await ensureCacheLoaded()
        return Array(prototypeCache.values)
    }
    
    /// Update prototype with new embedding using EMA
    func updatePrototype(
        categoryPath: String,
        newEmbedding: [Float],
        isUserConfirmed: Bool = false
    ) async throws {
        try await ensureCacheLoaded()
        let id = CategoryPrototype.generateId(for: categoryPath)
        
        if var existing = prototypeCache[id] {
            // EMA update
            existing.embedding = emaUpdate(
                old: existing.embedding,
                new: newEmbedding,
                alpha: config.emaDecay
            )
            existing.sampleCount += 1
            existing.version += 1
            existing.updatedAt = Date()
            
            // Boost confidence for user-confirmed updates
            if isUserConfirmed {
                existing.confidence = min(
                    config.maxConfidence,
                    existing.confidence + config.confidenceBoostPerSample * 2
                )
            } else {
                existing.confidence = min(
                    config.maxConfidence,
                    existing.confidence + config.confidenceBoostPerSample
                )
            }
            
            prototypeCache[id] = existing
            try savePrototype(existing)
        } else {
            // Create new prototype
            var prototype = CategoryPrototype(
                categoryPath: categoryPath,
                embedding: newEmbedding
            )
            prototype.confidence = isUserConfirmed ? 0.7 : 0.5
            
            prototypeCache[id] = prototype
            try savePrototype(prototype)
        }
    }
    
    /// Create or update prototype with explicit embedding
    func setPrototype(_ prototype: CategoryPrototype) async throws {
        try await ensureCacheLoaded()
        prototypeCache[prototype.id] = prototype
        try savePrototype(prototype)
    }
    
    /// Delete prototype
    func deletePrototype(categoryPath: String) async throws {
        try await ensureCacheLoaded()
        let id = CategoryPrototype.generateId(for: categoryPath)
        prototypeCache.removeValue(forKey: id)
        try deleteFromDatabase(id: id)
    }
    
    // MARK: - Similarity Queries
    
    /// Find most similar prototypes to a query embedding
    func findSimilar(
        to embedding: [Float],
        k: Int = 5,
        minSimilarity: Double = 0.0
    ) async throws -> [(prototype: CategoryPrototype, similarity: Double)] {
        try await ensureCacheLoaded()
        
        var results: [(CategoryPrototype, Double)] = []
        
        for prototype in prototypeCache.values {
            let similarity = cosineSimilarity(embedding, prototype.embedding)
            if similarity >= minSimilarity {
                results.append((prototype, similarity))
            }
        }
        
        return results
            .sorted { $0.1 > $1.1 }
            .prefix(k)
            .map { $0 }
    }
    
    /// Find best matching category for an embedding
    func classify(
        embedding: [Float],
        minConfidence: Double = 0.5
    ) async throws -> (categoryPath: String, similarity: Double, confidence: Double)? {
        let matches = try await findSimilar(to: embedding, k: 1, minSimilarity: 0.3)
        
        guard let best = matches.first else { return nil }
        
        // Combine prototype confidence with similarity
        let adjustedConfidence = best.prototype.confidence * best.similarity
        
        guard adjustedConfidence >= minConfidence else { return nil }
        
        return (best.prototype.categoryPath, best.similarity, adjustedConfidence)
    }
    
    // MARK: - Shared Prototypes
    
    /// Link folders to share prototypes
    func linkFolders(_ folderPaths: [String], forCategory categoryPath: String) async throws {
        try await ensureCacheLoaded()
        let id = CategoryPrototype.generateId(for: categoryPath)
        
        guard var prototype = prototypeCache[id] else {
            throw PrototypeStoreError.prototypeNotFound(categoryPath)
        }
        
        prototype.scope = .shared
        prototype.linkedFolders = Array(Set(prototype.linkedFolders + folderPaths))
        prototype.updatedAt = Date()
        
        prototypeCache[id] = prototype
        try savePrototype(prototype)
    }
    
    /// Unlink a folder from shared prototypes
    func unlinkFolder(_ folderPath: String, fromCategory categoryPath: String) async throws {
        try await ensureCacheLoaded()
        let id = CategoryPrototype.generateId(for: categoryPath)
        
        guard var prototype = prototypeCache[id] else { return }
        
        prototype.linkedFolders.removeAll { $0 == folderPath }
        if prototype.linkedFolders.isEmpty {
            prototype.scope = .folderScoped
        }
        prototype.updatedAt = Date()
        
        prototypeCache[id] = prototype
        try savePrototype(prototype)
    }
    
    // MARK: - Maintenance
    
    /// Apply confidence decay to all prototypes
    func applyConfidenceDecay() async throws {
        try await ensureCacheLoaded()
        
        for id in prototypeCache.keys {
            guard var prototype = prototypeCache[id] else { continue }
            
            let daysSinceUpdate = Date().timeIntervalSince(prototype.updatedAt) / 86400
            let decay = config.confidenceDecayRate * daysSinceUpdate
            
            prototype.confidence = max(0.1, prototype.confidence - decay)
            prototypeCache[id] = prototype
        }
        
        // Batch save
        try saveAllPrototypes()
    }
    
    /// Prune low-confidence prototypes
    func pruneWeak(minConfidence: Double = 0.2, minSamples: Int = 1) async throws -> Int {
        try await ensureCacheLoaded()
        
        var pruned = 0
        for (id, prototype) in prototypeCache {
            if prototype.confidence < minConfidence && prototype.sampleCount < minSamples {
                prototypeCache.removeValue(forKey: id)
                try deleteFromDatabase(id: id)
                pruned += 1
            }
        }
        
        return pruned
    }
    
    // MARK: - Statistics
    
    /// Get prototype statistics
    func statistics() async throws -> PrototypeStatistics {
        try await ensureCacheLoaded()
        
        let prototypes = Array(prototypeCache.values)
        let avgConfidence = prototypes.isEmpty ? 0 : prototypes.map { $0.confidence }.reduce(0, +) / Double(prototypes.count)
        let avgSamples = prototypes.isEmpty ? 0 : Double(prototypes.map { $0.sampleCount }.reduce(0, +)) / Double(prototypes.count)
        let sharedCount = prototypes.filter { $0.scope == .shared }.count
        
        return PrototypeStatistics(
            totalPrototypes: prototypes.count,
            sharedPrototypes: sharedCount,
            averageConfidence: avgConfidence,
            averageSampleCount: avgSamples,
            reliableCount: prototypes.filter { $0.sampleCount >= config.minSamplesForReliability }.count
        )
    }
    
    // MARK: - Private Helpers
    
    private func ensureCacheLoaded() async throws {
        guard !cacheLoaded else { return }
        let prototypes = try loadAllPrototypes()
        for prototype in prototypes {
            prototypeCache[prototype.id] = prototype
        }
        cacheLoaded = true
    }
    
    private func emaUpdate(old: [Float], new: [Float], alpha: Float) -> [Float] {
        guard old.count == new.count else { return new }
        
        var result = [Float](repeating: 0, count: old.count)
        for i in 0..<old.count {
            result[i] = alpha * old[i] + (1 - alpha) * new[i]
        }
        
        // L2 normalize
        let magnitude = sqrt(result.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            result = result.map { $0 / magnitude }
        }
        
        return result
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? Double(dot / denom) : 0
    }
    
    // MARK: - Database Operations
    
    private func loadAllPrototypes() throws -> [CategoryPrototype] {
        guard hasPersistence else { return [] }
        return try requireDatabase().dbQueue.read { db in
            try CategoryPrototype.fetchAll(db)
        }
    }
    
    private func savePrototype(_ prototype: CategoryPrototype) throws {
        guard hasPersistence else { return }
        try requireDatabase().dbQueue.write { db in
            try prototype.save(db)
        }
    }
    
    private func saveAllPrototypes() throws {
        guard hasPersistence else { return }
        // Capture prototypes locally to avoid actor isolation issues
        let prototypes = Array(prototypeCache.values)
        try requireDatabase().dbQueue.write { db in
            for prototype in prototypes {
                try prototype.save(db)
            }
        }
    }
    
    private func deleteFromDatabase(id: String) throws {
        guard hasPersistence else { return }
        try requireDatabase().dbQueue.write { db in
            _ = try CategoryPrototype.filter(CategoryPrototype.Columns.id == id).deleteAll(db)
        }
    }
}

// MARK: - Errors

enum PrototypeStoreError: LocalizedError {
    case prototypeNotFound(String)
    case dimensionMismatch(expected: Int, got: Int)
    
    var errorDescription: String? {
        switch self {
        case .prototypeNotFound(let path):
            return "Prototype not found for category: \(path)"
        case .dimensionMismatch(let expected, let got):
            return "Embedding dimension mismatch: expected \(expected), got \(got)"
        }
    }
}

// MARK: - Statistics

struct PrototypeStatistics: Sendable {
    let totalPrototypes: Int
    let sharedPrototypes: Int
    let averageConfidence: Double
    let averageSampleCount: Double
    let reliableCount: Int
}

