// MARK: - Continuous Watch Manager
// FSEvents-based file system watcher with quiet-period batching, in-use detection, and backpressure

import Foundation
import CoreServices

// MARK: - Watch Event

/// Event types from file system monitoring
enum WatchEvent: Sendable {
    case fileAdded(URL)
    case fileModified(URL)
    case fileRemoved(URL)
    case fileMoved(from: URL, to: URL)
}

// MARK: - Watch Status

/// Current status of the watch manager
enum WatchStatus: String, Sendable {
    case stopped = "Stopped"
    case starting = "Starting"
    case watching = "Watching"
    case paused = "Paused"
    case processing = "Processing"
    case error = "Error"
}

/// Detailed watch statistics
struct WatchStatistics: Sendable {
    let status: WatchStatus
    let watchedFolders: [URL]
    let queuedFiles: Int
    let processingFiles: Int
    let totalProcessed: Int
    let totalSkipped: Int
    let lastEventTime: Date?
    let uptime: TimeInterval
    let averageProcessingTime: TimeInterval
    let isBackpressureActive: Bool
}

// MARK: - Watch Configuration

struct ContinuousWatchConfiguration: Sendable {
    /// Quiet period (seconds) - wait after last file modification before processing
    let quietPeriod: TimeInterval
    
    /// Maximum files to queue before backpressure kicks in
    let maxQueueSize: Int
    
    /// Maximum concurrent processing tasks
    let maxConcurrentProcessing: Int
    
    /// Large file threshold (bytes) - files above this get special handling
    let largeFileThreshold: Int64
    
    /// Skip files larger than this (bytes) - 0 means no limit
    let maximumFileSize: Int64
    
    /// File extensions to watch (empty = all)
    let watchedExtensions: Set<String>
    
    /// Directories to exclude from watching
    let excludedDirectories: Set<String>
    
    /// Partial download indicators to skip
    let partialDownloadPatterns: Set<String>
    
    /// Whether to check if files are in use before processing
    let checkFileInUse: Bool
    
    /// Whether to enable backpressure (pause processing when queue is full)
    let enableBackpressure: Bool
    
    /// Minimum free CPU percentage before processing (0-100, 0 = no limit)
    let minFreeCPUPercent: Double
    
    /// Minimum free memory MB before processing (0 = no limit)
    let minFreeMemoryMB: Int
    
    static let `default` = ContinuousWatchConfiguration(
        quietPeriod: 3.0,
        maxQueueSize: 100,
        maxConcurrentProcessing: 2,
        largeFileThreshold: 100 * 1024 * 1024, // 100 MB
        maximumFileSize: 0, // No limit
        watchedExtensions: [],
        excludedDirectories: ["node_modules", ".git", ".svn", "__pycache__", ".DS_Store"],
        partialDownloadPatterns: [".part", ".crdownload", ".download", ".tmp"],
        checkFileInUse: true,
        enableBackpressure: true,
        minFreeCPUPercent: 0,
        minFreeMemoryMB: 0
    )
    
    static let aggressive = ContinuousWatchConfiguration(
        quietPeriod: 1.0,
        maxQueueSize: 200,
        maxConcurrentProcessing: 4,
        largeFileThreshold: 50 * 1024 * 1024,
        maximumFileSize: 0,
        watchedExtensions: [],
        excludedDirectories: ["node_modules", ".git"],
        partialDownloadPatterns: [".part", ".crdownload"],
        checkFileInUse: false,
        enableBackpressure: false,
        minFreeCPUPercent: 0,
        minFreeMemoryMB: 0
    )
    
    static let conservative = ContinuousWatchConfiguration(
        quietPeriod: 10.0,
        maxQueueSize: 50,
        maxConcurrentProcessing: 1,
        largeFileThreshold: 200 * 1024 * 1024,
        maximumFileSize: 500 * 1024 * 1024, // 500 MB max
        watchedExtensions: [],
        excludedDirectories: ["node_modules", ".git", ".svn", "__pycache__", ".DS_Store", "Library", "Applications"],
        partialDownloadPatterns: [".part", ".crdownload", ".download", ".tmp", ".temp"],
        checkFileInUse: true,
        enableBackpressure: true,
        minFreeCPUPercent: 20.0,
        minFreeMemoryMB: 500
    )
}

// MARK: - Queued File

/// A file queued for processing with metadata
struct QueuedWatchFile: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let detectedAt: Date
    var lastModified: Date
    let fileSize: Int64
    var processingAttempts: Int
    var isLargeFile: Bool
    
    init(url: URL, fileSize: Int64, isLargeFile: Bool) {
        self.id = UUID()
        self.url = url
        self.detectedAt = Date()
        self.lastModified = Date()
        self.fileSize = fileSize
        self.processingAttempts = 0
        self.isLargeFile = isLargeFile
    }
}

// MARK: - Continuous Watch Manager

/// Actor managing continuous file system monitoring with FSEvents
actor ContinuousWatchManager {
    
    // MARK: - Properties
    
    private let config: ContinuousWatchConfiguration
    
    private var status: WatchStatus = .stopped
    private var watchedFolders: [URL] = []
    private nonisolated(unsafe) var eventStream: FSEventStreamRef?
    
    // Queue management
    private var fileQueue: [QueuedWatchFile] = []
    private var processingFiles: Set<UUID> = []
    
    // Statistics
    private var totalProcessed: Int = 0
    private var totalSkipped: Int = 0
    private var lastEventTime: Date?
    private var startTime: Date?
    private var processingTimes: [TimeInterval] = []
    
    // Callbacks
    private var fileReadyCallback: (@Sendable (QueuedWatchFile) -> Void)?
    private var statusCallback: (@Sendable (WatchStatistics) -> Void)?
    
    // Quiet period timer
    private var quietPeriodTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init(configuration: ContinuousWatchConfiguration = .default) {
        self.config = configuration
    }
    
    deinit {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
    
    // MARK: - Control
    
    /// Start watching folders
    func startWatching(folders: [URL]) throws {
        guard status == .stopped else {
            throw WatchError.alreadyWatching
        }
        
        guard !folders.isEmpty else {
            throw WatchError.noFoldersSpecified
        }
        
        status = .starting
        watchedFolders = folders
        startTime = Date()
        
        NSLog("👁️ [Watch] Starting to watch \(folders.count) folders")
        for folder in folders {
            NSLog("👁️ [Watch]   - \(folder.path)")
        }
        
        // Start FSEvents stream
        try startFSEventsStream(for: folders)
        
        status = .watching
        NSLog("✅ [Watch] Now watching")
        
        notifyStatusUpdate()
    }
    
    /// Stop watching
    func stopWatching() {
        guard status != .stopped else { return }
        
        NSLog("🛑 [Watch] Stopping")
        
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        
        quietPeriodTask?.cancel()
        quietPeriodTask = nil
        
        status = .stopped
        fileQueue.removeAll()
        processingFiles.removeAll()
        
        NSLog("✅ [Watch] Stopped")
        notifyStatusUpdate()
    }
    
    /// Pause watching (stops accepting new files, keeps existing queue)
    func pause() {
        guard status == .watching else { return }
        
        status = .paused
        NSLog("⏸️ [Watch] Paused")
        notifyStatusUpdate()
    }
    
    /// Resume watching
    func resume() {
        guard status == .paused else { return }
        
        status = .watching
        NSLog("▶️ [Watch] Resumed")
        notifyStatusUpdate()
    }
    
    // MARK: - Callbacks
    
    /// Set callback for when files are ready to process
    func onFileReady(_ callback: @escaping @Sendable (QueuedWatchFile) -> Void) {
        self.fileReadyCallback = callback
    }
    
    /// Set callback for status updates
    func onStatusUpdate(_ callback: @escaping @Sendable (WatchStatistics) -> Void) {
        self.statusCallback = callback
        notifyStatusUpdate()
    }
    
    // MARK: - Status
    
    /// Get current statistics
    func getStatistics() -> WatchStatistics {
        let uptime = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let avgTime = processingTimes.isEmpty ? 0 : processingTimes.reduce(0, +) / Double(processingTimes.count)
        
        return WatchStatistics(
            status: status,
            watchedFolders: watchedFolders,
            queuedFiles: fileQueue.count,
            processingFiles: processingFiles.count,
            totalProcessed: totalProcessed,
            totalSkipped: totalSkipped,
            lastEventTime: lastEventTime,
            uptime: uptime,
            averageProcessingTime: avgTime,
            isBackpressureActive: isBackpressureActive()
        )
    }
    
    // MARK: - File Processing
    
    /// Mark a file as processing started
    func markProcessingStarted(fileId: UUID) {
        processingFiles.insert(fileId)
        notifyStatusUpdate()
    }
    
    /// Mark a file as processing completed
    func markProcessingCompleted(fileId: UUID, duration: TimeInterval, success: Bool) {
        processingFiles.remove(fileId)
        
        if let index = fileQueue.firstIndex(where: { $0.id == fileId }) {
            fileQueue.remove(at: index)
        }
        
        if success {
            totalProcessed += 1
            processingTimes.append(duration)
            
            // Keep only last 100 times for average calculation
            if processingTimes.count > 100 {
                processingTimes.removeFirst()
            }
        } else {
            totalSkipped += 1
        }
        
        notifyStatusUpdate()
    }
    
    // MARK: - Private Methods
    
    private func startFSEventsStream(for folders: [URL]) throws {
        let paths = folders.map { $0.path as CFString } as CFArray
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let callback: FSEventStreamCallback = { (
            streamRef: ConstFSEventStreamRef,
            clientCallBackInfo: UnsafeMutableRawPointer?,
            numEvents: Int,
            eventPaths: UnsafeMutableRawPointer,
            eventFlags: UnsafePointer<FSEventStreamEventFlags>,
            eventIds: UnsafePointer<FSEventStreamEventId>
        ) in
            let manager = Unmanaged<ContinuousWatchManager>.fromOpaque(clientCallBackInfo!).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            
            // Copy flags array to avoid data races
            let flagsArray = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))
            
            Task {
                await manager.handleFSEvents(paths: paths, flags: flagsArray)
            }
        }
        
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            config.quietPeriod / 2, // Check more frequently than quiet period
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else {
            throw WatchError.failedToCreateStream
        }
        
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            throw WatchError.failedToStartStream
        }
        
        eventStream = stream
    }
    
    private func handleFSEvents(paths: [String], flags: [FSEventStreamEventFlags]) async {
        guard status == .watching else { return }
        
        lastEventTime = Date()
        
        for i in 0..<min(paths.count, flags.count) {
            let path = paths[i]
            let flag = flags[i]
            let url = URL(fileURLWithPath: path)
            
            // Check if file was created or modified
            if flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0 ||
               flag & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
                await handleFileEvent(url: url)
            }
        }
        
        // Start quiet period timer
        startQuietPeriodTimer()
    }
    
    private func handleFileEvent(url: URL) async {
        // Check if should be excluded
        if shouldExclude(url: url) {
            return
        }
        
        // Check if it's a partial download
        if isPartialDownload(url: url) {
            NSLog("⏳ [Watch] Skipping partial download: \(url.lastPathComponent)")
            return
        }
        
        // Get file info
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return
        }
        
        // Check file size limits
        if config.maximumFileSize > 0 && fileSize > config.maximumFileSize {
            NSLog("⚠️ [Watch] Skipping file exceeding size limit: \(url.lastPathComponent) (\(fileSize) bytes)")
            totalSkipped += 1
            return
        }
        
        // Check if file is in use
        if config.checkFileInUse && isFileInUse(url: url) {
            NSLog("🔒 [Watch] Skipping file in use: \(url.lastPathComponent)")
            return
        }
        
        // Check backpressure
        if isBackpressureActive() {
            NSLog("🚦 [Watch] Backpressure active, deferring: \(url.lastPathComponent)")
            return
        }
        
        // Check system resources
        if !hasAdequateResources() {
            NSLog("⚠️ [Watch] Insufficient resources, deferring: \(url.lastPathComponent)")
            return
        }
        
        let isLarge = fileSize > config.largeFileThreshold
        
        // Add or update in queue
        if let index = fileQueue.firstIndex(where: { $0.url == url }) {
            fileQueue[index].lastModified = Date()
        } else {
            let queuedFile = QueuedWatchFile(url: url, fileSize: fileSize, isLargeFile: isLarge)
            fileQueue.append(queuedFile)
            
            if isLarge {
                NSLog("📦 [Watch] Queued large file: \(url.lastPathComponent) (\(formatBytes(fileSize)))")
            } else {
                NSLog("📥 [Watch] Queued: \(url.lastPathComponent)")
            }
        }
        
        notifyStatusUpdate()
    }
    
    private func startQuietPeriodTimer() {
        quietPeriodTask?.cancel()
        
        quietPeriodTask = Task {
            try? await Task.sleep(for: .seconds(config.quietPeriod))
            
            guard !Task.isCancelled else { return }
            await processQueuedFiles()
        }
    }
    
    private func processQueuedFiles() async {
        let now = Date()
        var readyFiles: [QueuedWatchFile] = []
        
        // Find files that haven't been modified for the quiet period
        for file in fileQueue {
            let timeSinceModified = now.timeIntervalSince(file.lastModified)
            if timeSinceModified >= config.quietPeriod && !processingFiles.contains(file.id) {
                readyFiles.append(file)
            }
        }
        
        if !readyFiles.isEmpty {
            status = .processing
            NSLog("🔄 [Watch] Processing \(readyFiles.count) ready files")
            
            for file in readyFiles {
                fileReadyCallback?(file)
            }
            
            status = .watching
        }
        
        notifyStatusUpdate()
    }
    
    // MARK: - Helper Methods
    
    private func shouldExclude(url: URL) -> Bool {
        let path = url.path
        
        // Check excluded directories
        for excluded in config.excludedDirectories {
            if path.contains("/\(excluded)/") || path.hasSuffix("/\(excluded)") {
                return true
            }
        }
        
        // Check file extensions if whitelist is specified
        if !config.watchedExtensions.isEmpty {
            let ext = url.pathExtension.lowercased()
            if !config.watchedExtensions.contains(ext) {
                return true
            }
        }
        
        return false
    }
    
    private func isPartialDownload(url: URL) -> Bool {
        let filename = url.lastPathComponent.lowercased()
        
        for pattern in config.partialDownloadPatterns {
            if filename.hasSuffix(pattern) {
                return true
            }
        }
        
        return false
    }
    
    private func isFileInUse(url: URL) -> Bool {
        // Try to open the file exclusively
        let fd = open(url.path, O_RDONLY | O_EXLOCK | O_NONBLOCK)
        if fd == -1 {
            return true // File is in use
        }
        close(fd)
        return false
    }
    
    private func isBackpressureActive() -> Bool {
        guard config.enableBackpressure else { return false }
        return fileQueue.count >= config.maxQueueSize
    }
    
    private func hasAdequateResources() -> Bool {
        // Check CPU
        if config.minFreeCPUPercent > 0 {
            // Simplified CPU check - in production, use host_processor_info
            // For now, always return true
        }
        
        // Check memory
        if config.minFreeMemoryMB > 0 {
            // Simplified memory check - in production, use mach_host.h
            // For now, always return true
        }
        
        return true
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func notifyStatusUpdate() {
        let stats = getStatistics()
        statusCallback?(stats)
    }
}

// MARK: - Error

enum WatchError: Error, LocalizedError {
    case alreadyWatching
    case noFoldersSpecified
    case failedToCreateStream
    case failedToStartStream
    case invalidConfiguration(String)
    
    var errorDescription: String? {
        switch self {
        case .alreadyWatching:
            return "Already watching folders"
        case .noFoldersSpecified:
            return "No folders specified to watch"
        case .failedToCreateStream:
            return "Failed to create FSEvents stream"
        case .failedToStartStream:
            return "Failed to start FSEvents stream"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
}

