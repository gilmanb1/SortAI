// MARK: - Database Recovery Service
// Handles database initialization failures with automatic recovery
// Implements: integrity checks, backup restoration, and graceful degradation

import Foundation
import GRDB

// MARK: - Database State

/// Application-wide database state for UI and logic coordination
enum DatabaseState: Equatable, Sendable {
    /// Database is healthy and fully operational
    case healthy
    
    /// Database initialization failed, recovery in progress
    case recovering(RecoveryPhase)
    
    /// Recovery failed, running in read-only mode
    case readOnly(reason: String)
    
    /// Database completely unavailable
    case unavailable(reason: String)
    
    var isOperational: Bool {
        switch self {
        case .healthy, .readOnly:
            return true
        case .recovering, .unavailable:
            return false
        }
    }
    
    var canWrite: Bool {
        self == .healthy
    }
    
    var displayMessage: String {
        switch self {
        case .healthy:
            return "Database operational"
        case .recovering(let phase):
            return "Recovering database: \(phase.displayName)"
        case .readOnly(let reason):
            return "Read-only mode: \(reason)"
        case .unavailable(let reason):
            return "Database unavailable: \(reason)"
        }
    }
}

/// Recovery phases for progress tracking
enum RecoveryPhase: Equatable, Sendable {
    case detectingError
    case runningIntegrityCheck
    case attemptingRepair
    case restoringFromBackup
    case creatingFreshDatabase
    case completed
    case failed
    
    var displayName: String {
        switch self {
        case .detectingError: return "Detecting issue..."
        case .runningIntegrityCheck: return "Checking database integrity..."
        case .attemptingRepair: return "Attempting repair..."
        case .restoringFromBackup: return "Restoring from backup..."
        case .creatingFreshDatabase: return "Creating fresh database..."
        case .completed: return "Recovery complete"
        case .failed: return "Recovery failed"
        }
    }
    
    var progress: Double {
        switch self {
        case .detectingError: return 0.1
        case .runningIntegrityCheck: return 0.3
        case .attemptingRepair: return 0.5
        case .restoringFromBackup: return 0.7
        case .creatingFreshDatabase: return 0.9
        case .completed: return 1.0
        case .failed: return 1.0
        }
    }
}

// MARK: - Database Initialization Errors

/// Specific errors that can occur during database initialization
enum DatabaseInitializationError: LocalizedError {
    case diskFull(available: Int64, required: Int64)
    case permissionDenied(path: String)
    case corrupted(details: String)
    case sqliteMissing(details: String)
    case walRecoveryFailed
    case migrationFailed(version: String, error: String)
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .diskFull(let available, let required):
            let availableMB = available / 1_000_000
            let requiredMB = required / 1_000_000
            return "Disk full: \(availableMB)MB available, \(requiredMB)MB required"
        case .permissionDenied(let path):
            return "Permission denied: Cannot write to \(path)"
        case .corrupted(let details):
            return "Database corrupted: \(details)"
        case .sqliteMissing(let details):
            return "SQLite configuration error: \(details)"
        case .walRecoveryFailed:
            return "Failed to recover from WAL journal"
        case .migrationFailed(let version, let error):
            return "Migration \(version) failed: \(error)"
        case .unknownError(let error):
            return "Database error: \(error.localizedDescription)"
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .diskFull, .permissionDenied:
            return false  // User must fix
        case .corrupted, .walRecoveryFailed, .migrationFailed:
            return true   // Can attempt auto-recovery
        case .sqliteMissing, .unknownError:
            return false  // Need developer fix
        }
    }
    
    var userActionRequired: String? {
        switch self {
        case .diskFull:
            return "Free up disk space and restart SortAI"
        case .permissionDenied(let path):
            return "Grant write permission to \(path)"
        case .corrupted, .walRecoveryFailed, .migrationFailed:
            return nil  // Auto-recovery possible
        case .sqliteMissing:
            return "Please reinstall SortAI"
        case .unknownError:
            return "Please report this issue"
        }
    }
}

// MARK: - Recovery Result

struct RecoveryResult: Sendable {
    let success: Bool
    let database: SortAIDatabase?
    let finalState: DatabaseState
    let message: String
    let dataLost: Bool
}

// MARK: - Database Recovery Service

/// Handles database initialization failures with automatic recovery
actor DatabaseRecoveryService {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        let maxBackups: Int
        let backupDirectory: URL
        let maxRecoveryAttempts: Int
        
        static var `default`: Configuration {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            
            return Configuration(
                maxBackups: 7,
                backupDirectory: appSupport.appendingPathComponent("SortAI/backups", isDirectory: true),
                maxRecoveryAttempts: 3
            )
        }
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private(set) var currentState: DatabaseState = .healthy
    private(set) var currentPhase: RecoveryPhase = .completed
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .default) {
        self.config = configuration
    }
    
    // MARK: - Database Initialization with Recovery
    
    /// Attempts to initialize the database with automatic recovery on failure
    func initializeWithRecovery(configuration: DatabaseConfiguration = .default) async -> RecoveryResult {
        NSLog("🔄 [DatabaseRecovery] Starting database initialization with recovery support")
        
        // First attempt: normal initialization
        do {
            let database = try SortAIDatabase(configuration: configuration)
            currentState = .healthy
            NSLog("✅ [DatabaseRecovery] Database initialized successfully")
            return RecoveryResult(
                success: true,
                database: database,
                finalState: .healthy,
                message: "Database initialized successfully",
                dataLost: false
            )
        } catch {
            NSLog("⚠️ [DatabaseRecovery] Initial initialization failed: \(error.localizedDescription)")
            return await attemptRecovery(originalError: error, configuration: configuration)
        }
    }
    
    // MARK: - Recovery Flow
    
    private func attemptRecovery(originalError: Error, configuration: DatabaseConfiguration) async -> RecoveryResult {
        currentState = .recovering(.detectingError)
        currentPhase = .detectingError
        
        // Step 1: Classify the error
        let classifiedError = classifyError(originalError)
        NSLog("🔍 [DatabaseRecovery] Error classified as: \(classifiedError)")
        
        // Step 2: Check if user action is required
        if !classifiedError.isRecoverable {
            let message = classifiedError.userActionRequired ?? classifiedError.errorDescription ?? "Unknown error"
            currentState = .unavailable(reason: message)
            return RecoveryResult(
                success: false,
                database: nil,
                finalState: currentState,
                message: message,
                dataLost: false
            )
        }
        
        // Step 3: Run integrity check
        currentPhase = .runningIntegrityCheck
        currentState = .recovering(.runningIntegrityCheck)
        
        let dbPath = try? getDatabasePath(configuration: configuration)
        if let path = dbPath {
            let integrityResult = await runIntegrityCheck(at: path)
            NSLog("🔍 [DatabaseRecovery] Integrity check result: \(integrityResult)")
            
            // Step 4: Attempt repair if integrity check found issues
            if !integrityResult.isOK {
                currentPhase = .attemptingRepair
                currentState = .recovering(.attemptingRepair)
                
                if await attemptRepair(at: path) {
                    // Retry initialization after repair
                    do {
                        let database = try SortAIDatabase(configuration: configuration)
                        currentState = .healthy
                        currentPhase = .completed
                        NSLog("✅ [DatabaseRecovery] Database repaired and initialized")
                        return RecoveryResult(
                            success: true,
                            database: database,
                            finalState: .healthy,
                            message: "Database repaired successfully",
                            dataLost: false
                        )
                    } catch {
                        NSLog("⚠️ [DatabaseRecovery] Repair did not fix the issue")
                    }
                }
            }
            
            // Step 5: Try restoring from backup
            currentPhase = .restoringFromBackup
            currentState = .recovering(.restoringFromBackup)
            
            if let restoredDB = await attemptRestoreFromBackup(configuration: configuration) {
                currentState = .healthy
                currentPhase = .completed
                NSLog("✅ [DatabaseRecovery] Database restored from backup")
                return RecoveryResult(
                    success: true,
                    database: restoredDB,
                    finalState: .healthy,
                    message: "Database restored from backup",
                    dataLost: true  // Some recent data may be lost
                )
            }
        }
        
        // Step 6: Create fresh database as last resort
        currentPhase = .creatingFreshDatabase
        currentState = .recovering(.creatingFreshDatabase)
        
        // Move corrupted database aside
        if let path = dbPath {
            let corruptedPath = path + ".corrupted.\(Date().timeIntervalSince1970)"
            try? FileManager.default.moveItem(atPath: path, toPath: corruptedPath)
            NSLog("📦 [DatabaseRecovery] Moved corrupted database to: \(corruptedPath)")
        }
        
        // Create fresh database
        do {
            let freshDB = try SortAIDatabase(configuration: configuration)
            currentState = .healthy
            currentPhase = .completed
            NSLog("✅ [DatabaseRecovery] Created fresh database")
            return RecoveryResult(
                success: true,
                database: freshDB,
                finalState: .healthy,
                message: "Created new database (previous data could not be recovered)",
                dataLost: true
            )
        } catch {
            // Complete failure
            currentPhase = .failed
            currentState = .unavailable(reason: error.localizedDescription)
            NSLog("❌ [DatabaseRecovery] Failed to create fresh database: \(error)")
            return RecoveryResult(
                success: false,
                database: nil,
                finalState: currentState,
                message: "Database recovery failed: \(error.localizedDescription)",
                dataLost: false
            )
        }
    }
    
    // MARK: - Error Classification
    
    private func classifyError(_ error: Error) -> DatabaseInitializationError {
        let message = error.localizedDescription.lowercased()
        
        // Check for disk full
        if message.contains("no space") || message.contains("disk full") {
            let available = getAvailableDiskSpace()
            return .diskFull(available: available, required: 10_000_000)  // 10MB minimum
        }
        
        // Check for permission issues
        if message.contains("permission") || message.contains("access denied") {
            let path = try? getDatabasePath(configuration: .default)
            return .permissionDenied(path: path ?? "unknown")
        }
        
        // Check for corruption
        if message.contains("corrupt") || message.contains("malformed") || message.contains("not a database") {
            return .corrupted(details: message)
        }
        
        // Check for SQLite issues
        if message.contains("sqlite") && (message.contains("missing") || message.contains("not found")) {
            return .sqliteMissing(details: message)
        }
        
        // Check for WAL issues
        if message.contains("wal") || message.contains("journal") {
            return .walRecoveryFailed
        }
        
        // Check for migration issues
        if message.contains("migration") {
            return .migrationFailed(version: "unknown", error: message)
        }
        
        return .unknownError(error)
    }
    
    // MARK: - Integrity Check
    
    struct IntegrityCheckResult: Sendable {
        let isOK: Bool
        let issues: [String]
    }
    
    private func runIntegrityCheck(at path: String) async -> IntegrityCheckResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return IntegrityCheckResult(isOK: false, issues: ["Database file does not exist"])
        }
        
        do {
            // Open database directly for integrity check
            var grdbConfig = GRDB.Configuration()
            grdbConfig.readonly = true
            let db = try DatabaseQueue(path: path, configuration: grdbConfig)
            
            // Use async read to avoid Sendable issues
            let rows: [String] = try await db.read { database in
                try String.fetchAll(database, sql: "PRAGMA integrity_check")
            }
            
            if rows.count == 1 && rows[0] == "ok" {
                NSLog("✅ [DatabaseRecovery] Integrity check passed")
                return IntegrityCheckResult(isOK: true, issues: [])
            } else {
                NSLog("⚠️ [DatabaseRecovery] Integrity check found issues: \(rows)")
                return IntegrityCheckResult(isOK: false, issues: rows)
            }
            
        } catch {
            return IntegrityCheckResult(isOK: false, issues: [error.localizedDescription])
        }
    }
    
    // MARK: - Repair Attempts
    
    private func attemptRepair(at path: String) async -> Bool {
        NSLog("🔧 [DatabaseRecovery] Attempting database repair at: \(path)")
        
        do {
            let grdbConfig = GRDB.Configuration()
            let db = try DatabaseQueue(path: path, configuration: grdbConfig)
            
            // Try VACUUM to rebuild the database using async write
            try await db.write { database in
                try database.execute(sql: "VACUUM")
            }
            
            NSLog("✅ [DatabaseRecovery] VACUUM completed successfully")
            return true
            
        } catch {
            NSLog("⚠️ [DatabaseRecovery] Repair failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Backup Management
    
    /// Creates a backup of the current database
    func createBackup() async throws -> URL {
        let dbPath = try getDatabasePath(configuration: .default)
        
        // Ensure backup directory exists
        try FileManager.default.createDirectory(at: config.backupDirectory, withIntermediateDirectories: true)
        
        // Generate backup filename with timestamp
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupName = "sortai_backup_\(timestamp).sqlite"
        let backupURL = config.backupDirectory.appendingPathComponent(backupName)
        
        // Copy database file
        try FileManager.default.copyItem(atPath: dbPath, toPath: backupURL.path)
        
        // Copy WAL and SHM files if they exist
        let walPath = dbPath + "-wal"
        let shmPath = dbPath + "-shm"
        
        if FileManager.default.fileExists(atPath: walPath) {
            try FileManager.default.copyItem(atPath: walPath, toPath: backupURL.path + "-wal")
        }
        if FileManager.default.fileExists(atPath: shmPath) {
            try FileManager.default.copyItem(atPath: shmPath, toPath: backupURL.path + "-shm")
        }
        
        NSLog("✅ [DatabaseRecovery] Backup created: \(backupURL.lastPathComponent)")
        
        // Rotate old backups
        await rotateBackups()
        
        return backupURL
    }
    
    /// Lists available backups sorted by date (newest first)
    func listBackups() async -> [URL] {
        guard FileManager.default.fileExists(atPath: config.backupDirectory.path) else {
            return []
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: config.backupDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            return contents
                .filter { $0.pathExtension == "sqlite" && $0.lastPathComponent.hasPrefix("sortai_backup_") }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return date1 > date2
                }
        } catch {
            NSLog("⚠️ [DatabaseRecovery] Failed to list backups: \(error)")
            return []
        }
    }
    
    /// Attempts to restore from the most recent valid backup
    private func attemptRestoreFromBackup(configuration: DatabaseConfiguration) async -> SortAIDatabase? {
        let backups = await listBackups()
        
        for backup in backups {
            NSLog("🔄 [DatabaseRecovery] Trying backup: \(backup.lastPathComponent)")
            
            // Verify backup integrity
            let integrityResult = await runIntegrityCheck(at: backup.path)
            if !integrityResult.isOK {
                NSLog("⚠️ [DatabaseRecovery] Backup failed integrity check, skipping")
                continue
            }
            
            // Try to restore
            do {
                let dbPath = try getDatabasePath(configuration: configuration)
                
                // Remove existing corrupted database
                try? FileManager.default.removeItem(atPath: dbPath)
                try? FileManager.default.removeItem(atPath: dbPath + "-wal")
                try? FileManager.default.removeItem(atPath: dbPath + "-shm")
                
                // Copy backup to database location
                try FileManager.default.copyItem(atPath: backup.path, toPath: dbPath)
                
                // Copy WAL if exists
                let backupWAL = backup.path + "-wal"
                if FileManager.default.fileExists(atPath: backupWAL) {
                    try FileManager.default.copyItem(atPath: backupWAL, toPath: dbPath + "-wal")
                }
                
                // Try to open the restored database
                let database = try SortAIDatabase(configuration: configuration)
                NSLog("✅ [DatabaseRecovery] Successfully restored from: \(backup.lastPathComponent)")
                return database
                
            } catch {
                NSLog("⚠️ [DatabaseRecovery] Failed to restore from \(backup.lastPathComponent): \(error)")
                continue
            }
        }
        
        NSLog("❌ [DatabaseRecovery] No valid backups found")
        return nil
    }
    
    /// Removes old backups keeping only the most recent ones
    private func rotateBackups() async {
        let backups = await listBackups()
        
        if backups.count > config.maxBackups {
            let toDelete = backups.suffix(from: config.maxBackups)
            for backup in toDelete {
                do {
                    try FileManager.default.removeItem(at: backup)
                    try? FileManager.default.removeItem(atPath: backup.path + "-wal")
                    try? FileManager.default.removeItem(atPath: backup.path + "-shm")
                    NSLog("🗑️ [DatabaseRecovery] Deleted old backup: \(backup.lastPathComponent)")
                } catch {
                    NSLog("⚠️ [DatabaseRecovery] Failed to delete old backup: \(error)")
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func getDatabasePath(configuration: DatabaseConfiguration) throws -> String {
        if let customPath = configuration.path {
            return customPath
        }
        
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw DatabaseError.notInitialized
        }
        
        return appSupport
            .appendingPathComponent("SortAI", isDirectory: true)
            .appendingPathComponent("sortai.sqlite")
            .path
    }
    
    private func getAvailableDiskSpace() -> Int64 {
        do {
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                return 0
            }
            
            let values = try appSupport.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            return Int64(values.volumeAvailableCapacity ?? 0)
        } catch {
            return 0
        }
    }
}

// MARK: - Backup Scheduler

/// Manages automatic database backups
actor BackupScheduler {
    private let recoveryService: DatabaseRecoveryService
    private var backupTask: Task<Void, Never>?
    private var isRunning = false
    
    init(recoveryService: DatabaseRecoveryService) {
        self.recoveryService = recoveryService
    }
    
    /// Starts the automatic backup scheduler (daily backups)
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        backupTask = Task {
            while !Task.isCancelled {
                // Wait 24 hours
                do {
                    try await Task.sleep(nanoseconds: 24 * 60 * 60 * 1_000_000_000)
                    
                    // Create backup
                    do {
                        let backupURL = try await recoveryService.createBackup()
                        NSLog("✅ [BackupScheduler] Automatic backup created: \(backupURL.lastPathComponent)")
                    } catch {
                        NSLog("⚠️ [BackupScheduler] Automatic backup failed: \(error)")
                    }
                } catch {
                    // Task cancelled
                    break
                }
            }
        }
        
        NSLog("✅ [BackupScheduler] Started automatic backup scheduler")
    }
    
    /// Stops the automatic backup scheduler
    func stop() {
        backupTask?.cancel()
        backupTask = nil
        isRunning = false
        NSLog("🛑 [BackupScheduler] Stopped automatic backup scheduler")
    }
    
    /// Triggers an immediate backup
    func backupNow() async throws -> URL {
        try await recoveryService.createBackup()
    }
}
