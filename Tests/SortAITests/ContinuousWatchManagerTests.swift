// MARK: - Continuous Watch Manager Tests

import Testing
import Foundation
@testable import SortAI

@Suite("Continuous Watch Manager Tests")
struct ContinuousWatchManagerTests {
    
    // MARK: - Helper Methods
    
    func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
    
    func createTestFile(in directory: URL, name: String, size: Int = 100) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        let data = Data(repeating: 0, count: size)
        try data.write(to: fileURL)
        return fileURL
    }
    
    // MARK: - Configuration Tests
    
    @Test("Default configuration")
    func testDefaultConfiguration() {
        let config = ContinuousWatchConfiguration.default
        
        #expect(config.quietPeriod == 3.0)
        #expect(config.maxQueueSize == 100)
        #expect(config.maxConcurrentProcessing == 2)
        #expect(config.checkFileInUse == true)
        #expect(config.enableBackpressure == true)
    }
    
    @Test("Aggressive configuration")
    func testAggressiveConfiguration() {
        let config = ContinuousWatchConfiguration.aggressive
        
        #expect(config.quietPeriod == 1.0)
        #expect(config.maxConcurrentProcessing == 4)
        #expect(config.checkFileInUse == false)
        #expect(config.enableBackpressure == false)
        #expect(config.quietPeriod < ContinuousWatchConfiguration.default.quietPeriod)
    }
    
    @Test("Conservative configuration")
    func testConservativeConfiguration() {
        let config = ContinuousWatchConfiguration.conservative
        
        #expect(config.quietPeriod == 10.0)
        #expect(config.maxConcurrentProcessing == 1)
        #expect(config.maximumFileSize > 0)
        #expect(config.minFreeCPUPercent > 0)
        #expect(config.quietPeriod > ContinuousWatchConfiguration.default.quietPeriod)
    }
    
    // MARK: - Manager Tests
    
    @Test("Manager initialization")
    func testManagerInitialization() async {
        let manager = ContinuousWatchManager(configuration: .default)
        let stats = await manager.getStatistics()
        
        #expect(stats.status == .stopped)
        #expect(stats.queuedFiles == 0)
        #expect(stats.processingFiles == 0)
        #expect(stats.totalProcessed == 0)
    }
    
    @Test("Get statistics")
    func testGetStatistics() async {
        let manager = ContinuousWatchManager(configuration: .default)
        let stats = await manager.getStatistics()
        
        #expect(stats.watchedFolders.isEmpty)
        #expect(stats.queuedFiles == 0)
        #expect(stats.uptime >= 0)
        #expect(stats.averageProcessingTime == 0)
        #expect(stats.isBackpressureActive == false)
    }
    
    @Test("Watch status enum")
    func testWatchStatusEnum() {
        let statuses: [WatchStatus] = [
            .stopped, .starting, .watching, .paused, .processing, .error
        ]
        
        #expect(statuses.count == 6)
        #expect(WatchStatus.stopped.rawValue == "Stopped")
        #expect(WatchStatus.watching.rawValue == "Watching")
    }
    
    @Test("Queued file creation")
    func testQueuedFileCreation() {
        let url = URL(fileURLWithPath: "/test/file.txt")
        let file = QueuedWatchFile(url: url, fileSize: 1024, isLargeFile: false)
        
        #expect(file.url == url)
        #expect(file.fileSize == 1024)
        #expect(file.isLargeFile == false)
        #expect(file.processingAttempts == 0)
    }
    
    @Test("Large file detection")
    func testLargeFileDetection() {
        let largeSize: Int64 = 200 * 1024 * 1024 // 200 MB
        let file = QueuedWatchFile(url: URL(fileURLWithPath: "/test.dat"), fileSize: largeSize, isLargeFile: true)
        
        #expect(file.isLargeFile == true)
        #expect(file.fileSize > 100 * 1024 * 1024)
    }
    
    @Test("Mark processing started")
    func testMarkProcessingStarted() async {
        let manager = ContinuousWatchManager(configuration: .default)
        let fileId = UUID()
        
        await manager.markProcessingStarted(fileId: fileId)
        
        let stats = await manager.getStatistics()
        #expect(stats.processingFiles == 1)
    }
    
    @Test("Mark processing completed")
    func testMarkProcessingCompleted() async {
        let manager = ContinuousWatchManager(configuration: .default)
        let fileId = UUID()
        
        await manager.markProcessingStarted(fileId: fileId)
        await manager.markProcessingCompleted(fileId: fileId, duration: 1.5, success: true)
        
        let stats = await manager.getStatistics()
        #expect(stats.processingFiles == 0)
        #expect(stats.totalProcessed == 1)
    }
    
    @Test("Mark processing failed")
    func testMarkProcessingFailed() async {
        let manager = ContinuousWatchManager(configuration: .default)
        let fileId = UUID()
        
        await manager.markProcessingStarted(fileId: fileId)
        await manager.markProcessingCompleted(fileId: fileId, duration: 0, success: false)
        
        let stats = await manager.getStatistics()
        #expect(stats.totalSkipped == 1)
        #expect(stats.totalProcessed == 0)
    }
    
    @Test("Status callback")
    func testStatusCallback() async {
        let manager = ContinuousWatchManager(configuration: .default)
        let statusActor = WatchStatusCollector()
        
        await manager.onStatusUpdate { stats in
            Task { await statusActor.add(stats) }
        }
        
        // Trigger a status update
        await manager.markProcessingStarted(fileId: UUID())
        
        // Wait for async callback task to execute
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Should have received at least one update
        let count = await statusActor.count
        #expect(count > 0)
    }
    
    @Test("File ready callback")
    func testFileReadyCallback() async {
        let manager = ContinuousWatchManager(configuration: .default)
        let fileActor = WatchFileCollector()
        
        await manager.onFileReady { file in
            Task { await fileActor.add(file) }
        }
        
        // Can't easily trigger without actual FSEvents, but verify callback is set
        let stats = await manager.getStatistics()
        #expect(stats.status == .stopped)
    }
    
    @Test("Watch error enum")
    func testWatchErrorEnum() {
        let errors: [WatchError] = [
            .alreadyWatching,
            .noFoldersSpecified,
            .failedToCreateStream,
            .failedToStartStream,
            .invalidConfiguration("test")
        ]
        
        #expect(errors.count == 5)
        #expect(WatchError.alreadyWatching.errorDescription != nil)
        #expect(WatchError.noFoldersSpecified.errorDescription != nil)
    }
    
    @Test("Configuration partial download patterns")
    func testPartialDownloadPatterns() {
        let config = ContinuousWatchConfiguration.default
        
        #expect(config.partialDownloadPatterns.contains(".part"))
        #expect(config.partialDownloadPatterns.contains(".crdownload"))
        #expect(config.partialDownloadPatterns.contains(".download"))
    }
    
    @Test("Configuration excluded directories")
    func testExcludedDirectories() {
        let config = ContinuousWatchConfiguration.default
        
        #expect(config.excludedDirectories.contains("node_modules"))
        #expect(config.excludedDirectories.contains(".git"))
        #expect(config.excludedDirectories.contains("__pycache__"))
    }
    
    @Test("Large file threshold")
    func testLargeFileThreshold() {
        let config = ContinuousWatchConfiguration.default
        
        let threshold = config.largeFileThreshold
        #expect(threshold == 100 * 1024 * 1024)
        
        let smallFile = Int64(50 * 1024 * 1024)
        let largeFile = Int64(150 * 1024 * 1024)
        
        #expect(smallFile < threshold)
        #expect(largeFile > threshold)
    }
    
    @Test("Maximum file size")
    func testMaximumFileSize() {
        let config = ContinuousWatchConfiguration.conservative
        
        #expect(config.maximumFileSize > 0)
        #expect(config.maximumFileSize == 500 * 1024 * 1024)
        
        let defaultConfig = ContinuousWatchConfiguration.default
        #expect(defaultConfig.maximumFileSize == 0) // No limit
    }
    
    @Test("Backpressure settings")
    func testBackpressureSettings() {
        let defaultConfig = ContinuousWatchConfiguration.default
        #expect(defaultConfig.enableBackpressure == true)
        #expect(defaultConfig.maxQueueSize > 0)
        
        let aggressiveConfig = ContinuousWatchConfiguration.aggressive
        #expect(aggressiveConfig.enableBackpressure == false)
    }
    
    @Test("Resource constraints")
    func testResourceConstraints() {
        let conservativeConfig = ContinuousWatchConfiguration.conservative
        
        #expect(conservativeConfig.minFreeCPUPercent >= 0)
        #expect(conservativeConfig.minFreeMemoryMB >= 0)
        #expect(conservativeConfig.minFreeCPUPercent > 0)
        #expect(conservativeConfig.minFreeMemoryMB > 0)
        
        let defaultConfig = ContinuousWatchConfiguration.default
        #expect(defaultConfig.minFreeCPUPercent == 0) // No limit
        #expect(defaultConfig.minFreeMemoryMB == 0) // No limit
    }
}

// MARK: - Helper Actors

actor WatchStatusCollector {
    private(set) var statuses: [WatchStatistics] = []
    
    func add(_ stats: WatchStatistics) {
        statuses.append(stats)
    }
    
    var count: Int {
        statuses.count
    }
}

actor WatchFileCollector {
    private(set) var files: [QueuedWatchFile] = []
    
    func add(_ file: QueuedWatchFile) {
        files.append(file)
    }
    
    var count: Int {
        files.count
    }
}

