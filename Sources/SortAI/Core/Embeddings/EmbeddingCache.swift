// MARK: - Embedding Cache
// Persistent embedding cache keyed by filename + parent path hash
// Spec requirement: "Embedding cache keyed by filename + parent path hash; persisted for watch reuse"

import Foundation
import GRDB

// MARK: - Cache Key

/// Cache key combining filename and parent folder for unique identification
struct EmbeddingCacheKey: Hashable, Sendable, Codable {
    let filename: String
    let parentPath: String
    let fileSize: Int64?  // Optional size for additional uniqueness
    let modificationDate: Date?  // Optional for cache invalidation
    
    var hash: String {
        var hasher = Hasher()
        hasher.combine(filename.lowercased())
        hasher.combine(parentPath.lowercased())
        if let size = fileSize {
            hasher.combine(size)
        }
        let hashValue = hasher.finalize()
        return String(format: "%016llx", UInt64(bitPattern: Int64(hashValue)))
    }
    
    init(url: URL) {
        self.filename = url.lastPathComponent
        self.parentPath = url.deletingLastPathComponent().path
        
        // Get file attributes if available
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            self.fileSize = attrs[.size] as? Int64
            self.modificationDate = attrs[.modificationDate] as? Date
        } else {
            self.fileSize = nil
            self.modificationDate = nil
        }
    }
    
    init(filename: String, parentPath: String, fileSize: Int64? = nil, modificationDate: Date? = nil) {
        self.filename = filename
        self.parentPath = parentPath
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }
}

// MARK: - Cached Embedding

/// Cached embedding with metadata
struct CachedEmbedding: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "embedding_cache"
    
    var id: String  // Hash of cache key
    var filename: String
    var parentPath: String
    var embeddingData: Data  // Serialized [Float]
    var dimensions: Int
    var model: String  // Model used to generate embedding
    var embeddingType: EmbeddingType
    var createdAt: Date
    var lastAccessedAt: Date
    var hitCount: Int
    
    enum EmbeddingType: String, Codable, DatabaseValueConvertible {
        case filename  // From filename only
        case content   // From file content
        case hybrid    // Combined filename + content
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
        key: EmbeddingCacheKey,
        embedding: [Float],
        model: String,
        type: EmbeddingType
    ) {
        self.id = key.hash
        self.filename = key.filename
        self.parentPath = key.parentPath
        self.embeddingData = Self.encodeEmbedding(embedding)
        self.dimensions = embedding.count
        self.model = model
        self.embeddingType = type
        self.createdAt = Date()
        self.lastAccessedAt = Date()
        self.hitCount = 0
    }
    
    // MARK: - Column Definitions
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let filename = Column(CodingKeys.filename)
        static let parentPath = Column(CodingKeys.parentPath)
        static let embeddingData = Column(CodingKeys.embeddingData)
        static let dimensions = Column(CodingKeys.dimensions)
        static let model = Column(CodingKeys.model)
        static let embeddingType = Column(CodingKeys.embeddingType)
        static let createdAt = Column(CodingKeys.createdAt)
        static let lastAccessedAt = Column(CodingKeys.lastAccessedAt)
        static let hitCount = Column(CodingKeys.hitCount)
    }
}

// MARK: - Embedding Cache Actor

/// Thread-safe embedding cache with persistence
actor EmbeddingCache {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        let maxCacheSize: Int  // Maximum number of cached embeddings
        let ttlDays: Int  // Time-to-live for cache entries
        let pruneThreshold: Double  // Prune when cache reaches this % of max
        
        static let `default` = Configuration(
            maxCacheSize: 100_000,
            ttlDays: 90,
            pruneThreshold: 0.9
        )
    }
    
    // MARK: - Properties
    
    private let database: SortAIDatabase?
    private let config: Configuration
    
    // In-memory LRU cache for hot entries
    private var memoryCache: [String: CachedEmbedding] = [:]
    private var accessOrder: [String] = []
    private let memoryCacheLimit = 1000
    
    // Statistics
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    
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
    
    // MARK: - Cache Operations
    
    /// Retrieve embedding from cache
    func get(key: EmbeddingCacheKey) throws -> CachedEmbedding? {
        let hash = key.hash
        
        // Check memory cache first
        if var cached = memoryCache[hash] {
            cacheHits += 1
            cached.lastAccessedAt = Date()
            cached.hitCount += 1
            memoryCache[hash] = cached
            updateAccessOrder(hash)
            
            // Update in database
            try? updateAccessStats(id: hash)
            
            return cached
        }
        
        // Check database
        if let cached = try fetchFromDatabase(id: hash) {
            cacheHits += 1
            
            // Add to memory cache
            addToMemoryCache(cached)
            
            // Update access stats
            try updateAccessStats(id: hash)
            
            return cached
        }
        
        cacheMisses += 1
        return nil
    }
    
    /// Store embedding in cache
    func set(key: EmbeddingCacheKey, embedding: [Float], model: String, type: CachedEmbedding.EmbeddingType) throws {
        let cached = CachedEmbedding(key: key, embedding: embedding, model: model, type: type)
        
        // Add to memory cache
        addToMemoryCache(cached)
        
        // Persist to database
        try saveToDatabase(cached)
        
        // Check if pruning needed
        let count = try cacheCount()
        if Double(count) > Double(config.maxCacheSize) * config.pruneThreshold {
            Task {
                try? self.prune()
            }
        }
    }
    
    /// Check if embedding exists in cache
    func contains(key: EmbeddingCacheKey) throws -> Bool {
        let hash = key.hash
        if memoryCache[hash] != nil { return true }
        return try fetchFromDatabase(id: hash) != nil
    }
    
    /// Remove embedding from cache
    func remove(key: EmbeddingCacheKey) throws {
        let hash = key.hash
        memoryCache.removeValue(forKey: hash)
        accessOrder.removeAll { $0 == hash }
        try deleteFromDatabase(id: hash)
    }
    
    /// Clear entire cache
    func clear() throws {
        memoryCache.removeAll()
        accessOrder.removeAll()
        try clearDatabase()
        cacheHits = 0
        cacheMisses = 0
    }
    
    // MARK: - Statistics
    
    /// Get cache statistics
    func statistics() throws -> CacheStatistics {
        let dbCount = try cacheCount()
        let hitRate = (cacheHits + cacheMisses) > 0 
            ? Double(cacheHits) / Double(cacheHits + cacheMisses) 
            : 0.0
        
        return CacheStatistics(
            totalEntries: dbCount,
            memoryEntries: memoryCache.count,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses,
            hitRate: hitRate
        )
    }
    
    // MARK: - Maintenance
    
    /// Prune old/low-use entries
    func prune() throws {
        let cutoffDate = Calendar.current.date(
            byAdding: .day, 
            value: -config.ttlDays, 
            to: Date()
        ) ?? Date()
        
        // Remove expired entries
        try pruneExpired(before: cutoffDate)
        
        // If still over limit, remove least recently accessed
        let count = try cacheCount()
        if count > config.maxCacheSize {
            let excess = count - Int(Double(config.maxCacheSize) * 0.8)
            try pruneLRU(count: excess)
        }
        
        // Clear memory cache of pruned entries
        let validIds = Set(try getAllIds())
        memoryCache = memoryCache.filter { validIds.contains($0.key) }
        accessOrder = accessOrder.filter { validIds.contains($0) }
    }
    
    // MARK: - Private Helpers
    
    private func addToMemoryCache(_ cached: CachedEmbedding) {
        // Evict oldest if at limit
        while memoryCache.count >= memoryCacheLimit, let oldest = accessOrder.first {
            memoryCache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
        
        memoryCache[cached.id] = cached
        updateAccessOrder(cached.id)
    }
    
    private func updateAccessOrder(_ id: String) {
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)
    }
    
    // MARK: - Database Operations
    
    private func fetchFromDatabase(id: String) throws -> CachedEmbedding? {
        try requireDatabase().dbQueue.read { db in
            try CachedEmbedding.filter(CachedEmbedding.Columns.id == id).fetchOne(db)
        }
    }
    
    private func saveToDatabase(_ cached: CachedEmbedding) throws {
        try requireDatabase().dbQueue.write { db in
            try cached.save(db)
        }
    }
    
    private func deleteFromDatabase(id: String) throws {
        try requireDatabase().dbQueue.write { db in
            _ = try CachedEmbedding.filter(CachedEmbedding.Columns.id == id).deleteAll(db)
        }
    }
    
    private func clearDatabase() throws {
        try requireDatabase().dbQueue.write { db in
            _ = try CachedEmbedding.deleteAll(db)
        }
    }
    
    private func updateAccessStats(id: String) throws {
        try requireDatabase().dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE embedding_cache 
                    SET lastAccessedAt = ?, hitCount = hitCount + 1 
                    WHERE id = ?
                    """,
                arguments: [Date(), id]
            )
        }
    }
    
    private func cacheCount() throws -> Int {
        try requireDatabase().dbQueue.read { db in
            try CachedEmbedding.fetchCount(db)
        }
    }
    
    private func getAllIds() throws -> [String] {
        try requireDatabase().dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM embedding_cache")
        }
    }
    
    private func pruneExpired(before date: Date) throws {
        try requireDatabase().dbQueue.write { db in
            _ = try CachedEmbedding
                .filter(CachedEmbedding.Columns.lastAccessedAt < date)
                .deleteAll(db)
        }
    }
    
    private func pruneLRU(count: Int) throws {
        try requireDatabase().dbQueue.write { db in
            try db.execute(
                sql: """
                    DELETE FROM embedding_cache 
                    WHERE id IN (
                        SELECT id FROM embedding_cache 
                        ORDER BY hitCount ASC, lastAccessedAt ASC 
                        LIMIT ?
                    )
                    """,
                arguments: [count]
            )
        }
    }
    
    // MARK: - Re-embedding Support
    
    /// Get embeddings that need re-embedding with Apple Intelligence
    /// Returns embeddings not generated by the specified model
    func getEmbeddingsNeedingReembedding(
        excludingModel targetModel: String = "apple-nl-embedding",
        limit: Int = 100
    ) throws -> [CachedEmbedding] {
        try requireDatabase().dbQueue.read { db in
            try CachedEmbedding
                .filter(CachedEmbedding.Columns.model != targetModel)
                .order(CachedEmbedding.Columns.hitCount.desc)  // Prioritize frequently used
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Count embeddings that need re-embedding
    func countEmbeddingsNeedingReembedding(excludingModel targetModel: String = "apple-nl-embedding") throws -> Int {
        try requireDatabase().dbQueue.read { db in
            try CachedEmbedding
                .filter(CachedEmbedding.Columns.model != targetModel)
                .fetchCount(db)
        }
    }
    
    /// Update an existing embedding with new data
    func updateEmbedding(
        id: String,
        embedding: [Float],
        model: String,
        type: CachedEmbedding.EmbeddingType
    ) throws {
        try requireDatabase().dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE embedding_cache 
                    SET embeddingData = ?, dimensions = ?, model = ?, 
                        embeddingType = ?, lastAccessedAt = ?
                    WHERE id = ?
                    """,
                arguments: [
                    CachedEmbedding.encodeEmbedding(embedding),
                    embedding.count,
                    model,
                    type.rawValue,
                    Date(),
                    id
                ]
            )
        }
        
        // Update memory cache if present
        if var cached = memoryCache[id] {
            cached.embedding = embedding
            cached.model = model
            cached.embeddingType = type
            cached.lastAccessedAt = Date()
            memoryCache[id] = cached
        }
    }
    
    /// Get all unique models used in the cache
    func getUniqueModels() throws -> [String] {
        try requireDatabase().dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT model FROM embedding_cache ORDER BY model")
        }
    }
    
    /// Get statistics by model
    func statisticsByModel() throws -> [(model: String, count: Int, avgHitCount: Double)] {
        try requireDatabase().dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT model, COUNT(*) as count, AVG(hitCount) as avgHits
                FROM embedding_cache
                GROUP BY model
                ORDER BY count DESC
                """)
            return rows.map { row in
                (
                    model: row["model"] as String,
                    count: row["count"] as Int,
                    avgHitCount: row["avgHits"] as Double
                )
            }
        }
    }
}

// MARK: - EmbeddingCacheStore Conformance

extension EmbeddingCache: EmbeddingCacheStore {
    func getFilesNeedingReembedding(limit: Int) async throws -> [(id: Int64, text: String)] {
        let embeddings = try getEmbeddingsNeedingReembedding(limit: limit)
        return embeddings.compactMap { embedding in
            // Combine filename and parent path for text
            let text = "\(embedding.filename) \(embedding.parentPath)"
            // Use hash as pseudo-ID (convert to Int64)
            guard let idValue = Int64(embedding.id, radix: 16) else { return nil }
            return (id: idValue, text: text)
        }
    }
    
    func updateEmbedding(fileId: Int64, embedding: [Float]) async throws {
        // Convert Int64 back to hex string ID
        let id = String(format: "%016llx", UInt64(bitPattern: fileId))
        try updateEmbedding(id: id, embedding: embedding, model: "apple-nl-embedding", type: .hybrid)
    }
}

// MARK: - Cache Statistics

struct CacheStatistics: Sendable {
    let totalEntries: Int
    let memoryEntries: Int
    let cacheHits: Int
    let cacheMisses: Int
    let hitRate: Double
}

