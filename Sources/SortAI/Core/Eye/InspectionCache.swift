// MARK: - Inspection Cache
// Two-tier caching for FileSignature inspection results
// Tier 1: Path + mtime (fast, invalidates on edit)
// Tier 2: Checksum (survives renames/moves)

import Foundation
import GRDB

// MARK: - Cache Key Types

/// Tier 1 key: path + modification time
struct PathCacheKey: Hashable, Sendable {
    let path: String
    let modificationTime: Date
    
    init(url: URL) throws {
        self.path = url.path
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        self.modificationTime = (attrs[.modificationDate] as? Date) ?? Date.distantPast
    }
    
    var hash: String {
        "\(path)|\(modificationTime.timeIntervalSince1970)"
    }
}

/// Tier 2 key: checksum
struct ChecksumCacheKey: Hashable, Sendable {
    let checksum: String
}

// MARK: - Cached Inspection Record

/// Persisted inspection result
struct CachedInspection: Codable, Sendable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "inspection_cache"
    
    var id: String  // Hash key
    var path: String
    var checksum: String
    var modificationTime: Date
    var signatureData: Data  // Serialized FileSignature
    var createdAt: Date
    var lastAccessedAt: Date
    var hitCount: Int
    
    // MARK: - FileSignature Serialization
    
    static func encode(_ signature: FileSignature) throws -> Data {
        try JSONEncoder().encode(signature)
    }
    
    static func decode(_ data: Data) throws -> FileSignature {
        try JSONDecoder().decode(FileSignature.self, from: data)
    }
}

// MARK: - Inspection Cache Actor

/// Thread-safe two-tier inspection cache
/// Dramatically speeds up re-processing of previously seen files
actor InspectionCache {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        let maxCacheSize: Int
        let ttlDays: Int
        let memoryCacheLimit: Int
        
        static let `default` = Configuration(
            maxCacheSize: 50_000,
            ttlDays: 30,
            memoryCacheLimit: 500
        )
    }
    
    // MARK: - Properties
    
    private let database: SortAIDatabase?
    private let config: Configuration
    
    // In-memory LRU cache for hot entries
    private var memoryCache: [String: FileSignature] = [:]
    private var accessOrder: [String] = []
    
    // Statistics
    private var tier1Hits: Int = 0
    private var tier2Hits: Int = 0
    private var misses: Int = 0
    
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
    
    // MARK: - Cache Lookup
    
    /// Look up cached inspection result
    /// Checks Tier 1 (path+mtime) first, then Tier 2 (checksum)
    func get(url: URL, checksum: String? = nil) throws -> FileSignature? {
        // Tier 1: Path + mtime (fastest)
        if let pathKey = try? PathCacheKey(url: url) {
            let hash = pathKey.hash
            
            // Check memory cache
            if let cached = memoryCache[hash] {
                tier1Hits += 1
                updateAccessOrder(hash)
                return cached
            }
            
            // Check database by path+mtime
            if let cached = try fetchByPath(path: pathKey.path, mtime: pathKey.modificationTime) {
                tier1Hits += 1
                let signature = try CachedInspection.decode(cached.signatureData)
                addToMemoryCache(hash: hash, signature: signature)
                try updateAccessStats(id: cached.id)
                return signature
            }
        }
        
        // Tier 2: Checksum (survives renames)
        if let checksum = checksum {
            if let cached = try fetchByChecksum(checksum: checksum) {
                tier2Hits += 1
                let signature = try CachedInspection.decode(cached.signatureData)
                
                // Also cache under current path for future fast lookups
                if let pathKey = try? PathCacheKey(url: url) {
                    addToMemoryCache(hash: pathKey.hash, signature: signature)
                }
                
                try updateAccessStats(id: cached.id)
                return signature
            }
        }
        
        misses += 1
        return nil
    }
    
    /// Store inspection result in cache
    func set(url: URL, signature: FileSignature) throws {
        guard let pathKey = try? PathCacheKey(url: url) else { return }
        
        let hash = pathKey.hash
        let signatureData = try CachedInspection.encode(signature)
        
        let cached = CachedInspection(
            id: hash,
            path: pathKey.path,
            checksum: signature.checksum,
            modificationTime: pathKey.modificationTime,
            signatureData: signatureData,
            createdAt: Date(),
            lastAccessedAt: Date(),
            hitCount: 0
        )
        
        // Add to memory cache
        addToMemoryCache(hash: hash, signature: signature)
        
        // Persist to database
        try saveToDatabase(cached)
        
        // Check if pruning needed
        let count = try cacheCount()
        if count > config.maxCacheSize {
            Task { try? self.prune() }
        }
    }
    
    /// Invalidate cache entry for a path
    func invalidate(url: URL) throws {
        if let pathKey = try? PathCacheKey(url: url) {
            memoryCache.removeValue(forKey: pathKey.hash)
            accessOrder.removeAll { $0 == pathKey.hash }
        }
        
        try requireDatabase().write { db in
            try db.execute(sql: "DELETE FROM inspection_cache WHERE path = ?", arguments: [url.path])
        }
    }
    
    /// Invalidate all entries for files that no longer exist
    func pruneNonexistent() async throws {
        let entries = try requireDatabase().read { db in
            try CachedInspection.fetchAll(db)
        }
        
        var deletedCount = 0
        for entry in entries {
            if !FileManager.default.fileExists(atPath: entry.path) {
                try requireDatabase().write { db in
                    try db.execute(sql: "DELETE FROM inspection_cache WHERE id = ?", arguments: [entry.id])
                }
                memoryCache.removeValue(forKey: entry.id)
                deletedCount += 1
            }
        }
        
        if deletedCount > 0 {
            NSLog("🗑️ [InspectionCache] Pruned \(deletedCount) non-existent file entries")
        }
    }
    
    // MARK: - Statistics
    
    var statistics: CacheStatistics {
        let total = tier1Hits + tier2Hits + misses
        return CacheStatistics(
            tier1Hits: tier1Hits,
            tier2Hits: tier2Hits,
            misses: misses,
            hitRate: total > 0 ? Double(tier1Hits + tier2Hits) / Double(total) : 0,
            memoryCacheSize: memoryCache.count
        )
    }
    
    struct CacheStatistics: Sendable {
        let tier1Hits: Int
        let tier2Hits: Int
        let misses: Int
        let hitRate: Double
        let memoryCacheSize: Int
    }
    
    // MARK: - Private Helpers
    
    private func fetchByPath(path: String, mtime: Date) throws -> CachedInspection? {
        try requireDatabase().read { db in
            try CachedInspection
                .filter(Column("path") == path)
                .filter(Column("modificationTime") == mtime)
                .fetchOne(db)
        }
    }
    
    private func fetchByChecksum(checksum: String) throws -> CachedInspection? {
        try requireDatabase().read { db in
            try CachedInspection
                .filter(Column("checksum") == checksum)
                .order(Column("lastAccessedAt").desc)
                .fetchOne(db)
        }
    }
    
    private func saveToDatabase(_ cached: CachedInspection) throws {
        try requireDatabase().write { db in
            try cached.save(db)
        }
    }
    
    private func updateAccessStats(id: String) throws {
        try requireDatabase().write { db in
            try db.execute(sql: """
                UPDATE inspection_cache 
                SET lastAccessedAt = ?, hitCount = hitCount + 1
                WHERE id = ?
            """, arguments: [Date(), id])
        }
    }
    
    private func cacheCount() throws -> Int {
        try requireDatabase().read { db in
            try CachedInspection.fetchCount(db)
        }
    }
    
    private func prune() throws {
        // Remove oldest entries beyond max size
        let cutoff = Date().addingTimeInterval(-Double(config.ttlDays) * 24 * 60 * 60)
        
        try requireDatabase().write { db in
            // First, delete expired entries
            try db.execute(sql: "DELETE FROM inspection_cache WHERE lastAccessedAt < ?", arguments: [cutoff])
            
            // Then, if still over limit, delete least recently used
            let count = try CachedInspection.fetchCount(db)
            if count > config.maxCacheSize {
                let toDelete = count - config.maxCacheSize
                try db.execute(sql: """
                    DELETE FROM inspection_cache 
                    WHERE id IN (
                        SELECT id FROM inspection_cache 
                        ORDER BY lastAccessedAt ASC 
                        LIMIT ?
                    )
                """, arguments: [toDelete])
            }
        }
        
        NSLog("🗑️ [InspectionCache] Pruned cache to \(config.maxCacheSize) entries")
    }
    
    private func addToMemoryCache(hash: String, signature: FileSignature) {
        if memoryCache.count >= config.memoryCacheLimit {
            // Evict oldest
            if let oldest = accessOrder.first {
                memoryCache.removeValue(forKey: oldest)
                accessOrder.removeFirst()
            }
        }
        
        memoryCache[hash] = signature
        accessOrder.removeAll { $0 == hash }
        accessOrder.append(hash)
    }
    
    private func updateAccessOrder(_ hash: String) {
        accessOrder.removeAll { $0 == hash }
        accessOrder.append(hash)
    }
}

