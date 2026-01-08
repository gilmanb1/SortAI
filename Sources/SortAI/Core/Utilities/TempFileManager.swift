// MARK: - Temp File Manager
// Centralized temporary file management with automatic cleanup
// Tracks temp files, handles orphan cleanup on startup, immediate/deferred cleanup

import Foundation

// MARK: - Temp File Info

struct TempFileInfo: Sendable, Hashable {
    let url: URL
    let createdAt: Date
    let purpose: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url.path)
    }
    
    static func == (lhs: TempFileInfo, rhs: TempFileInfo) -> Bool {
        lhs.url.path == rhs.url.path
    }
}

// MARK: - Temp File Manager Actor

/// Thread-safe temporary file manager
/// Tracks all temp files created by the app and ensures cleanup
actor TempFileManager {
    
    // MARK: - Singleton
    
    static let shared = TempFileManager()
    
    // MARK: - Properties
    
    private var trackedFiles: Set<TempFileInfo> = []
    private let tempDirectory: URL
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    private init() {
        // Use dedicated temp directory for SortAI
        self.tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("SortAI_Temp", isDirectory: true)
        
        // Ensure directory exists
        try? fileManager.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        
        NSLog("🗂️  [TempFileManager] Initialized at: \(tempDirectory.path)")
    }
    
    // MARK: - Public Interface
    
    /// Create a temporary file with unique UUID-based name
    /// - Parameters:
    ///   - ext: File extension (without dot)
    ///   - purpose: Description of file purpose (for logging)
    /// - Returns: URL of created temp file
    func createTempFile(extension ext: String, purpose: String = "audio") -> URL {
        let filename = "sortai_\(purpose)_\(UUID().uuidString).\(ext)"
        let url = tempDirectory.appendingPathComponent(filename)
        
        let info = TempFileInfo(url: url, createdAt: Date(), purpose: purpose)
        trackedFiles.insert(info)
        
        NSLog("📝 [TempFileManager] Created temp file: \(filename) (purpose: \(purpose))")
        return url
    }
    
    /// Track an existing temp file
    func track(_ url: URL, purpose: String = "unknown") {
        let info = TempFileInfo(url: url, createdAt: Date(), purpose: purpose)
        trackedFiles.insert(info)
        NSLog("👁️  [TempFileManager] Tracking: \(url.lastPathComponent)")
    }
    
    /// Stop tracking a file (doesn't delete it)
    func untrack(_ url: URL) {
        trackedFiles = trackedFiles.filter { $0.url.path != url.path }
    }
    
    /// Clean up a specific temp file immediately
    func cleanup(_ url: URL) async {
        untrack(url)
        
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                NSLog("🗑️  [TempFileManager] Cleaned up: \(url.lastPathComponent)")
            }
        } catch {
            NSLog("⚠️  [TempFileManager] Failed to cleanup \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
    
    /// Clean up all tracked files
    func cleanupAll() {
        let filesToClean = trackedFiles
        trackedFiles.removeAll()
        
        var successCount = 0
        var failCount = 0
        
        for info in filesToClean {
            do {
                if fileManager.fileExists(atPath: info.url.path) {
                    try fileManager.removeItem(at: info.url)
                    successCount += 1
                }
            } catch {
                failCount += 1
                NSLog("⚠️  [TempFileManager] Failed to cleanup \(info.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        if successCount > 0 || failCount > 0 {
            NSLog("🗑️  [TempFileManager] Cleaned up \(successCount) files, \(failCount) failed")
        }
    }
    
    /// Clean up files older than specified age
    func cleanupOlderThan(_ age: TimeInterval) async {
        let cutoff = Date().addingTimeInterval(-age)
        let oldFiles = trackedFiles.filter { $0.createdAt < cutoff }
        
        for info in oldFiles {
            await cleanup(info.url)
        }
        
        if !oldFiles.isEmpty {
            NSLog("🗑️  [TempFileManager] Cleaned up \(oldFiles.count) old files")
        }
    }
    
    /// Purge orphaned temp files from previous runs (call on startup)
    func purgeOrphanedFiles() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        var orphanedCount = 0
        let trackedPaths = Set(trackedFiles.map { $0.url.path })
        
        for fileURL in contents {
            // Skip if currently tracked
            if trackedPaths.contains(fileURL.path) {
                continue
            }
            
            // Delete orphaned file
            do {
                try fileManager.removeItem(at: fileURL)
                orphanedCount += 1
            } catch {
                NSLog("⚠️  [TempFileManager] Failed to purge orphan \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        if orphanedCount > 0 {
            NSLog("🗑️  [TempFileManager] Purged \(orphanedCount) orphaned files from previous runs")
        }
    }
    
    /// Get statistics about tracked files
    func getStats() -> TempFileStats {
        let totalSize: Int64 = trackedFiles.reduce(0) { sum, info in
            guard let attrs = try? fileManager.attributesOfItem(atPath: info.url.path),
                  let size = attrs[.size] as? Int64 else {
                return sum
            }
            return sum + size
        }
        
        let byPurpose = Dictionary(grouping: trackedFiles, by: { $0.purpose })
            .mapValues { $0.count }
        
        return TempFileStats(
            totalFiles: trackedFiles.count,
            totalSizeBytes: totalSize,
            byPurpose: byPurpose,
            oldestFile: trackedFiles.min(by: { $0.createdAt < $1.createdAt })
        )
    }
}

// MARK: - Supporting Types

struct TempFileStats: Sendable {
    let totalFiles: Int
    let totalSizeBytes: Int64
    let byPurpose: [String: Int]
    let oldestFile: TempFileInfo?
    
    var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
}

// MARK: - Convenience Extensions

extension TempFileManager {
    
    /// Create temp file and automatically clean up after block execution
    func withTempFile<T>(
        extension ext: String,
        purpose: String = "audio",
        block: @Sendable (URL) async throws -> T
    ) async rethrows -> T {
        let url = createTempFile(extension: ext, purpose: purpose)
        defer {
            Task {
                await cleanup(url)
            }
        }
        return try await block(url)
    }
    
    /// Create multiple temp files and clean up all after block execution
    func withTempFiles<T>(
        count: Int,
        extension ext: String,
        purpose: String = "audio",
        block: @Sendable ([URL]) async throws -> T
    ) async rethrows -> T {
        let urls = (0..<count).map { _ in
            createTempFile(extension: ext, purpose: "\(purpose)_batch")
        }
        
        defer {
            Task {
                for url in urls {
                    await cleanup(url)
                }
            }
        }
        
        return try await block(urls)
    }
}

