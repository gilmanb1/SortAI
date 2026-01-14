// MARK: - SortAI Unified Database
// Single SQLite database managing all persistence for SortAI
// Consolidates: knowledge_graph.sqlite, memory.sqlite, feedback.sqlite

import Foundation
import GRDB

// MARK: - Database Errors

enum DatabaseError: LocalizedError {
    case notInitialized
    case initializationFailed(underlying: Error)
    case migrationFailed(String)
    case transactionFailed(String)
    case recordNotFound(String)
    case invalidData(String)
    case readOnlyMode
    case recoveryInProgress
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database not initialized"
        case .initializationFailed(let error):
            return "Database initialization failed: \(error.localizedDescription)"
        case .migrationFailed(let reason):
            return "Migration failed: \(reason)"
        case .transactionFailed(let reason):
            return "Transaction failed: \(reason)"
        case .recordNotFound(let identifier):
            return "Record not found: \(identifier)"
        case .invalidData(let reason):
            return "Invalid data: \(reason)"
        case .readOnlyMode:
            return "Database is in read-only mode due to recovery failure"
        case .recoveryInProgress:
            return "Database recovery is in progress"
        }
    }
}

// MARK: - Database Configuration

struct DatabaseConfiguration: Sendable {
    let path: String?
    let inMemory: Bool
    let enableWAL: Bool
    let enableForeignKeys: Bool
    
    static let `default` = DatabaseConfiguration(
        path: nil,
        inMemory: false,
        enableWAL: true,
        enableForeignKeys: true
    )
    
    static let inMemory = DatabaseConfiguration(
        path: ":memory:",
        inMemory: true,
        enableWAL: false,
        enableForeignKeys: true
    )
    
    static func custom(path: String) -> DatabaseConfiguration {
        DatabaseConfiguration(
            path: path,
            inMemory: false,
            enableWAL: true,
            enableForeignKeys: true
        )
    }
}

// MARK: - SortAI Database

/// Unified persistence layer for all SortAI data
/// Thread-safe database access using GRDB's DatabaseQueue
final class SortAIDatabase: @unchecked Sendable {
    
    // MARK: - Singleton (optional usage)
    
    // Using nonisolated(unsafe) because access is protected by NSLock
    nonisolated(unsafe) private static var _shared: SortAIDatabase?
    nonisolated(unsafe) private static var _state: DatabaseState = .healthy
    nonisolated(unsafe) private static var _lastError: Error?
    nonisolated(unsafe) private static var _recoveryService: DatabaseRecoveryService?
    private static let lock = NSLock()
    
    /// Current database state (thread-safe read)
    static var state: DatabaseState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }
    
    /// Last initialization error (thread-safe read)
    static var lastError: Error? {
        lock.lock()
        defer { lock.unlock() }
        return _lastError
    }
    
    /// Shared database instance with graceful error handling
    /// Returns nil if database is unavailable; check `state` for details
    static var sharedOrNil: SortAIDatabase? {
        lock.lock()
        defer { lock.unlock() }
        
        if _shared == nil && _state == .healthy {
            do {
                _shared = try SortAIDatabase(configuration: .default)
                _state = .healthy
                _lastError = nil
            } catch {
                _lastError = error
                _state = .unavailable(reason: error.localizedDescription)
                NSLog("❌ [SortAIDatabase] Initialization failed: \(error.localizedDescription)")
                // Don't fatalError - return nil and let caller handle
            }
        }
        return _shared
    }
    
    /// Shared database instance (throws if unavailable)
    /// Prefer `sharedOrNil` for graceful handling
    static var shared: SortAIDatabase {
        get throws {
            guard let db = sharedOrNil else {
                throw DatabaseError.initializationFailed(underlying: _lastError ?? DatabaseError.notInitialized)
            }
            return db
        }
    }
    
    /// Legacy accessor for backward compatibility
    /// ⚠️ DEPRECATED: Use `sharedOrNil` or `try shared` instead
    /// This will return the database if available, otherwise crash with helpful message
    @available(*, deprecated, message: "Use sharedOrNil or try shared instead")
    static var sharedLegacy: SortAIDatabase {
        // Try to get existing database
        if let db = sharedOrNil {
            return db
        }
        
        // Crash with helpful message (same as old fatalError behavior but more info)
        fatalError("""
            ❌ SortAI Database Initialization Failed
            
            The database could not be initialized.
            State: \(_state)
            Error: \(_lastError?.localizedDescription ?? "Unknown")
            
            Please check:
            1. Disk space availability
            2. Write permissions to ~/Library/Application Support/SortAI/
            3. Database file integrity
            
            To fix:
            - Use `SortAIDatabase.initializeAsync()` at app startup for automatic recovery
            - Or delete ~/Library/Application Support/SortAI/sortai.sqlite to reset
            """)
    }
    
    /// Resets the shared instance (useful for testing)
    static func resetShared() {
        lock.lock()
        defer { lock.unlock() }
        _shared = nil
        _state = .healthy
        _lastError = nil
        _recoveryService = nil
    }
    
    /// Initializes the database with automatic recovery support
    /// Call this at app startup instead of accessing `shared` directly
    static func initializeAsync() async -> (database: SortAIDatabase?, state: DatabaseState) {
        // Check if already initialized (sync helper)
        if let existing = getExistingIfInitialized() {
            return existing
        }
        
        // Attempt initialization with recovery
        let service = DatabaseRecoveryService()
        let result = await service.initializeWithRecovery()
        
        // Store result (sync helper)
        storeInitializationResult(
            database: result.database,
            state: result.finalState,
            success: result.success,
            service: service
        )
        
        if result.dataLost {
            NSLog("⚠️ [SortAIDatabase] Recovery succeeded but some data was lost")
            // Post notification for UI to show warning
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .databaseRecoveryDataLost,
                    object: nil,
                    userInfo: ["message": result.message]
                )
            }
        }
        
        return (result.database, result.finalState)
    }
    
    /// Helper for async initialization - checks if already initialized (sync, not async)
    private static func getExistingIfInitialized() -> (database: SortAIDatabase?, state: DatabaseState)? {
        lock.lock()
        defer { lock.unlock() }
        
        if let existing = _shared {
            return (existing, _state)
        }
        return nil
    }
    
    /// Helper for async initialization - stores result (sync, not async)
    private static func storeInitializationResult(
        database: SortAIDatabase?,
        state: DatabaseState,
        success: Bool,
        service: DatabaseRecoveryService
    ) {
        lock.lock()
        defer { lock.unlock() }
        
        _shared = database
        _state = state
        _lastError = success ? nil : DatabaseError.initializationFailed(underlying: DatabaseError.notInitialized)
        _recoveryService = service
    }
    
    /// Creates a backup of the current database
    static func createBackup() async throws -> URL {
        guard let service = _recoveryService else {
            let newService = DatabaseRecoveryService()
            return try await newService.createBackup()
        }
        return try await service.createBackup()
    }
    
    // MARK: - Properties
    
    let dbQueue: DatabaseQueue
    private let configuration: DatabaseConfiguration
    
    // Repository instances (lazy initialization)
    private var _entityRepository: EntityRepository?
    private var _patternRepository: PatternRepository?
    private var _feedbackRepository: FeedbackRepository?
    private var _recordRepository: RecordRepository?
    private var _movementLogRepository: MovementLogRepository?
    
    // MARK: - Repositories (Public Access)
    
    var entities: EntityRepository {
        if _entityRepository == nil {
            _entityRepository = EntityRepository(database: self)
        }
        return _entityRepository!
    }
    
    var patterns: PatternRepository {
        if _patternRepository == nil {
            _patternRepository = PatternRepository(database: self)
        }
        return _patternRepository!
    }
    
    var feedback: FeedbackRepository {
        if _feedbackRepository == nil {
            _feedbackRepository = FeedbackRepository(database: self)
        }
        return _feedbackRepository!
    }
    
    var records: RecordRepository {
        if _recordRepository == nil {
            _recordRepository = RecordRepository(database: self)
        }
        return _recordRepository!
    }
    
    var movementLog: MovementLogRepository {
        if _movementLogRepository == nil {
            _movementLogRepository = MovementLogRepository(database: self)
        }
        return _movementLogRepository!
    }
    
    // MARK: - Initialization
    
    init(configuration: DatabaseConfiguration = .default) throws {
        self.configuration = configuration
        
        let dbPath: String
        if configuration.inMemory {
            dbPath = ":memory:"
        } else if let customPath = configuration.path {
            dbPath = customPath
        } else {
            dbPath = try SortAIDatabase.defaultDatabasePath()
        }
        
        // Configure GRDB
        var grdbConfig = Configuration()
        grdbConfig.prepareDatabase { db in
            if configuration.enableWAL && !configuration.inMemory {
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
            }
            if configuration.enableForeignKeys {
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }
        }
        
        // Create directory if needed
        if !configuration.inMemory && dbPath != ":memory:" {
            let directory = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        self.dbQueue = try DatabaseQueue(path: dbPath, configuration: grdbConfig)
        try runMigrations()
    }
    
    /// Creates an in-memory database for testing
    static func inMemory() throws -> SortAIDatabase {
        try SortAIDatabase(configuration: .inMemory)
    }
    
    // MARK: - Default Path
    
    private static func defaultDatabasePath() throws -> String {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw DatabaseError.notInitialized
        }
        
        let sortAIDir = appSupport.appendingPathComponent("SortAI", isDirectory: true)
        try FileManager.default.createDirectory(at: sortAIDir, withIntermediateDirectories: true)
        
        return sortAIDir.appendingPathComponent("sortai.sqlite").path
    }
    
    // MARK: - Migrations
    
    private func runMigrations() throws {
        var migrator = DatabaseMigrator()
        
        // Prevent migration replays in production
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        
        // ============================================================
        // MIGRATION v1: Core Schema
        // Consolidates all tables from previous separate databases
        // ============================================================
        migrator.registerMigration("v1_core_schema") { db in
            
            // ----------------------------------------------------------
            // ENTITIES TABLE (from KnowledgeGraph)
            // Stores nodes in the knowledge graph: files, categories, keywords, etc.
            // ----------------------------------------------------------
            try db.create(table: "entities", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("type", .text).notNull()
                t.column("name", .text).notNull()
                t.column("normalizedName", .text).notNull()
                t.column("metadata", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("usageCount", .integer).notNull().defaults(to: 1)
            }
            
            // ----------------------------------------------------------
            // RELATIONSHIPS TABLE (from KnowledgeGraph)
            // Stores edges in the knowledge graph: category hierarchies, associations, etc.
            // ----------------------------------------------------------
            try db.create(table: "relationships", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("sourceId", .integer).notNull().references("entities", onDelete: .cascade)
                t.column("targetId", .integer).notNull().references("entities", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("weight", .double).notNull().defaults(to: 1.0)
                t.column("metadata", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            
            // ----------------------------------------------------------
            // EMBEDDINGS TABLE (from KnowledgeGraph)
            // Vector embeddings for similarity search
            // ----------------------------------------------------------
            try db.create(table: "embeddings", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("entityId", .integer).notNull().unique().references("entities", onDelete: .cascade)
                t.column("vector", .blob).notNull()
                t.column("dimensions", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            
            // ----------------------------------------------------------
            // LEARNED_PATTERNS TABLE (from MemoryStore)
            // Vector embeddings learned from user corrections
            // ----------------------------------------------------------
            try db.create(table: "learned_patterns", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("checksum", .text).notNull()
                t.column("embeddingData", .blob).notNull()
                t.column("label", .text).notNull()
                t.column("originalLabel", .text)
                t.column("confidence", .double).notNull().defaults(to: 1.0)
                t.column("hitCount", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            
            // ----------------------------------------------------------
            // PROCESSING_RECORDS TABLE (from MemoryStore)
            // History of all processed files
            // ----------------------------------------------------------
            try db.create(table: "processing_records", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("fileURL", .text).notNull()
                t.column("checksum", .text).notNull()
                t.column("mediaKind", .text).notNull()
                t.column("assignedCategory", .text).notNull()
                t.column("confidence", .double).notNull()
                t.column("wasFromMemory", .boolean).notNull().defaults(to: false)
                t.column("wasOverridden", .boolean).notNull().defaults(to: false)
                t.column("processedAt", .datetime).notNull()
            }
            
            // ----------------------------------------------------------
            // FEEDBACK_QUEUE TABLE (from FeedbackManager)
            // Human-in-the-loop review queue
            // ----------------------------------------------------------
            try db.create(table: "feedback_queue", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("fileURL", .text).notNull()
                t.column("fileName", .text).notNull()
                t.column("suggestedCategory", .text).notNull()
                t.column("suggestedSubcategories", .text).notNull()
                t.column("confidence", .double).notNull()
                t.column("rationale", .text).notNull()
                t.column("status", .text).notNull()
                t.column("humanCategory", .text)
                t.column("humanSubcategories", .text)
                t.column("feedbackNotes", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("reviewedAt", .datetime)
                t.column("extractedKeywords", .text).notNull()
                t.column("fileEntityId", .integer).references("entities", onDelete: .setNull)
            }
            
            // ----------------------------------------------------------
            // METADATA TABLE
            // Application-level key-value storage
            // ----------------------------------------------------------
            try db.create(table: "metadata", ifNotExists: true) { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        
        // ============================================================
        // MIGRATION v2: Performance Indexes
        // ============================================================
        migrator.registerMigration("v2_indexes") { db in
            // Entity indexes
            try db.create(index: "idx_entities_type", on: "entities", columns: ["type"], ifNotExists: true)
            try db.create(index: "idx_entities_normalized", on: "entities", columns: ["normalizedName"], ifNotExists: true)
            try db.create(index: "idx_entities_type_normalized", on: "entities", columns: ["type", "normalizedName"], unique: true, ifNotExists: true)
            
            // Relationship indexes
            try db.create(index: "idx_rel_source", on: "relationships", columns: ["sourceId"], ifNotExists: true)
            try db.create(index: "idx_rel_target", on: "relationships", columns: ["targetId"], ifNotExists: true)
            try db.create(index: "idx_rel_type", on: "relationships", columns: ["type"], ifNotExists: true)
            try db.create(index: "idx_rel_unique", on: "relationships", columns: ["sourceId", "targetId", "type"], unique: true, ifNotExists: true)
            
            // Embedding indexes
            try db.create(index: "idx_embeddings_entity", on: "embeddings", columns: ["entityId"], ifNotExists: true)
            
            // Pattern indexes
            try db.create(index: "idx_patterns_checksum", on: "learned_patterns", columns: ["checksum"], ifNotExists: true)
            try db.create(index: "idx_patterns_label", on: "learned_patterns", columns: ["label"], ifNotExists: true)
            try db.create(index: "idx_patterns_label_confidence", on: "learned_patterns", columns: ["label", "confidence"], ifNotExists: true)
            
            // Record indexes
            try db.create(index: "idx_records_checksum", on: "processing_records", columns: ["checksum"], ifNotExists: true)
            try db.create(index: "idx_records_category", on: "processing_records", columns: ["assignedCategory"], ifNotExists: true)
            try db.create(index: "idx_records_category_date", on: "processing_records", columns: ["assignedCategory", "processedAt"], ifNotExists: true)
            
            // Feedback indexes
            try db.create(index: "idx_feedback_status", on: "feedback_queue", columns: ["status"], ifNotExists: true)
            try db.create(index: "idx_feedback_confidence", on: "feedback_queue", columns: ["confidence"], ifNotExists: true)
            try db.create(index: "idx_feedback_created", on: "feedback_queue", columns: ["createdAt"], ifNotExists: true)
        }
        
        // ============================================================
        // MIGRATION v3: Movement Log Schema
        // Durable log of all file movement operations for undo and audit trail
        // ============================================================
        migrator.registerMigration("v3_movement_log") { db in
            // ----------------------------------------------------------
            // MOVEMENT_LOG TABLE
            // Tracks all file movement operations with full context
            // ----------------------------------------------------------
            try db.create(table: "movement_log", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull()
                t.column("source", .text).notNull()
                t.column("destination", .text).notNull()
                t.column("reason", .text).notNull()
                t.column("confidence", .double).notNull()
                t.column("mode", .text).notNull()  // full/degraded/offline
                t.column("provider", .text)
                t.column("providerVersion", .text)
                t.column("operationType", .text).notNull()  // move/copy/symlink
                t.column("undoable", .boolean).notNull().defaults(to: true)
                t.column("undoneAt", .datetime)
            }
            
            // Movement log indexes
            try db.create(index: "idx_movement_log_timestamp", on: "movement_log", columns: ["timestamp"], ifNotExists: true)
            try db.create(index: "idx_movement_log_source", on: "movement_log", columns: ["source"], ifNotExists: true)
            try db.create(index: "idx_movement_log_destination", on: "movement_log", columns: ["destination"], ifNotExists: true)
            try db.create(index: "idx_movement_log_undoable", on: "movement_log", columns: ["undoable", "undoneAt"], ifNotExists: true)
            try db.create(index: "idx_movement_log_mode", on: "movement_log", columns: ["mode"], ifNotExists: true)
        }
        
        // ============================================================
        // MIGRATION v4: Embedding Cache & Prototype Store
        // Spec requirement: "Embedding cache keyed by filename + parent path hash"
        // Spec requirement: "PrototypeStore with shared prototypes, EMA decay"
        // ============================================================
        migrator.registerMigration("v4_embedding_cache_prototypes") { db in
            // ----------------------------------------------------------
            // EMBEDDING_CACHE TABLE
            // Persistent cache for file embeddings keyed by filename+parent
            // ----------------------------------------------------------
            try db.create(table: "embedding_cache", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()  // Hash of cache key
                t.column("filename", .text).notNull()
                t.column("parentPath", .text).notNull()
                t.column("embeddingData", .blob).notNull()
                t.column("dimensions", .integer).notNull()
                t.column("model", .text).notNull()
                t.column("embeddingType", .text).notNull()  // filename/content/hybrid
                t.column("createdAt", .datetime).notNull()
                t.column("lastAccessedAt", .datetime).notNull()
                t.column("hitCount", .integer).notNull().defaults(to: 0)
            }
            
            // Embedding cache indexes
            try db.create(index: "idx_embedding_cache_filename", on: "embedding_cache", columns: ["filename"], ifNotExists: true)
            try db.create(index: "idx_embedding_cache_parent", on: "embedding_cache", columns: ["parentPath"], ifNotExists: true)
            try db.create(index: "idx_embedding_cache_accessed", on: "embedding_cache", columns: ["lastAccessedAt"], ifNotExists: true)
            try db.create(index: "idx_embedding_cache_model", on: "embedding_cache", columns: ["model"], ifNotExists: true)
            
            // ----------------------------------------------------------
            // CATEGORY_PROTOTYPES TABLE
            // EMA-averaged prototype vectors for category classification
            // ----------------------------------------------------------
            try db.create(table: "category_prototypes", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()  // Hash of category path
                t.column("categoryPath", .text).notNull()
                t.column("categoryName", .text).notNull()
                t.column("embeddingData", .blob).notNull()
                t.column("dimensions", .integer).notNull()
                t.column("sampleCount", .integer).notNull().defaults(to: 1)
                t.column("confidence", .double).notNull().defaults(to: 0.5)
                t.column("version", .integer).notNull().defaults(to: 1)
                t.column("scope", .text).notNull()  // folderScoped/shared/global
                t.column("linkedFolders", .text).notNull()  // JSON array
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            
            // Prototype indexes
            try db.create(index: "idx_prototype_category", on: "category_prototypes", columns: ["categoryPath"], ifNotExists: true)
            try db.create(index: "idx_prototype_name", on: "category_prototypes", columns: ["categoryName"], ifNotExists: true)
            try db.create(index: "idx_prototype_scope", on: "category_prototypes", columns: ["scope"], ifNotExists: true)
            try db.create(index: "idx_prototype_confidence", on: "category_prototypes", columns: ["confidence"], ifNotExists: true)
        }
        
        // ============================================================
        // MIGRATION v5: Inspection Cache
        // Two-tier cache for FileSignature inspection results
        // Tier 1: path+mtime (fast), Tier 2: checksum (survives renames)
        // ============================================================
        migrator.registerMigration("v5_inspection_cache") { db in
            try db.create(table: "inspection_cache", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()  // Hash key
                t.column("path", .text).notNull()
                t.column("checksum", .text).notNull()
                t.column("modificationTime", .datetime).notNull()
                t.column("signatureData", .blob).notNull()  // Serialized FileSignature
                t.column("createdAt", .datetime).notNull()
                t.column("lastAccessedAt", .datetime).notNull()
                t.column("hitCount", .integer).notNull().defaults(to: 0)
            }
            
            // Inspection cache indexes
            try db.create(index: "idx_inspection_cache_path", on: "inspection_cache", columns: ["path"], ifNotExists: true)
            try db.create(index: "idx_inspection_cache_checksum", on: "inspection_cache", columns: ["checksum"], ifNotExists: true)
            try db.create(index: "idx_inspection_cache_mtime", on: "inspection_cache", columns: ["path", "modificationTime"], ifNotExists: true)
            try db.create(index: "idx_inspection_cache_accessed", on: "inspection_cache", columns: ["lastAccessedAt"], ifNotExists: true)
        }
        
        try migrator.migrate(dbQueue)
    }
    
    // MARK: - Transaction Support
    
    /// Executes a read-only transaction
    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }
    
    /// Executes a write transaction
    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }
    
    /// Executes an async write transaction
    func writeAsync<T: Sendable>(_ block: @Sendable @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.write(block)
    }
    
    // MARK: - Maintenance
    
    /// Vacuums the database to reclaim space
    func vacuum() throws {
        try dbQueue.vacuum()
    }
    
    /// Returns database file size in bytes
    func databaseSize() throws -> Int64 {
        guard !configuration.inMemory else { return 0 }
        let path = try SortAIDatabase.defaultDatabasePath()
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    /// Returns statistics about database contents
    func statistics() throws -> DatabaseStatistics {
        try dbQueue.read { db in
            let entityCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM entities") ?? 0
            let relationshipCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM relationships") ?? 0
            let patternCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM learned_patterns") ?? 0
            let recordCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM processing_records") ?? 0
            let feedbackCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feedback_queue") ?? 0
            
            return DatabaseStatistics(
                entityCount: entityCount,
                relationshipCount: relationshipCount,
                patternCount: patternCount,
                recordCount: recordCount,
                feedbackCount: feedbackCount
            )
        }
    }
}

// MARK: - Database Statistics

struct DatabaseStatistics: Sendable, Equatable {
    let entityCount: Int
    let relationshipCount: Int
    let patternCount: Int
    let recordCount: Int
    let feedbackCount: Int
    
    var totalRecords: Int {
        entityCount + relationshipCount + patternCount + recordCount + feedbackCount
    }
}

// MARK: - Database Notifications

extension Notification.Name {
    /// Posted when database recovery resulted in data loss
    static let databaseRecoveryDataLost = Notification.Name("SortAI.databaseRecoveryDataLost")
    
    /// Posted when database state changes
    static let databaseStateChanged = Notification.Name("SortAI.databaseStateChanged")
    
    /// Posted when database recovery starts
    static let databaseRecoveryStarted = Notification.Name("SortAI.databaseRecoveryStarted")
    
    /// Posted when database recovery completes
    static let databaseRecoveryCompleted = Notification.Name("SortAI.databaseRecoveryCompleted")
}
