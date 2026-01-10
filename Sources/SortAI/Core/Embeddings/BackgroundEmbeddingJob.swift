// MARK: - Background Embedding Job
// Manages background re-embedding of files with Apple Intelligence
// Spec requirement: "Background job to re-embed existing files with Apple Intelligence"

import Foundation
import Combine

// MARK: - Job Status

/// Status of the background embedding job
enum EmbeddingJobStatus: Sendable, Equatable {
    case idle
    case preparing
    case running(progress: EmbeddingJobProgress)
    case paused(progress: EmbeddingJobProgress)
    case completed(summary: EmbeddingJobSummary)
    case failed(error: String)
    case cancelled
    
    var isActive: Bool {
        switch self {
        case .preparing, .running: return true
        default: return false
        }
    }
}

/// Progress information for the embedding job
struct EmbeddingJobProgress: Sendable, Equatable {
    let totalFiles: Int
    let processedFiles: Int
    let currentFile: String?
    let startTime: Date
    let estimatedCompletion: Date?
    
    var percentComplete: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(processedFiles) / Double(totalFiles)
    }
    
    var filesRemaining: Int {
        totalFiles - processedFiles
    }
    
    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }
    
    var filesPerSecond: Double {
        guard elapsedTime > 0 else { return 0 }
        return Double(processedFiles) / elapsedTime
    }
}

/// Summary of a completed embedding job
struct EmbeddingJobSummary: Sendable, Equatable {
    let totalProcessed: Int
    let successful: Int
    let failed: Int
    let skipped: Int
    let duration: TimeInterval
    let newModel: String
    
    var successRate: Double {
        guard totalProcessed > 0 else { return 0 }
        return Double(successful) / Double(totalProcessed)
    }
}

// MARK: - Background Embedding Job

/// Class that manages background re-embedding of files with Apple Intelligence
/// Uses @MainActor for UI updates and internal serialization
@MainActor
final class BackgroundEmbeddingJob: ObservableObject {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        let batchSize: Int
        let delayBetweenBatches: TimeInterval
        let respectBatteryStatus: Bool
        let pauseOnLowBattery: Bool
        let lowBatteryThreshold: Double
        let maxConcurrentTasks: Int
        
        static let `default` = Configuration(
            batchSize: 50,
            delayBetweenBatches: 0.5,
            respectBatteryStatus: true,
            pauseOnLowBattery: true,
            lowBatteryThreshold: 0.2,
            maxConcurrentTasks: 4
        )
        
        static let aggressive = Configuration(
            batchSize: 100,
            delayBetweenBatches: 0.1,
            respectBatteryStatus: false,
            pauseOnLowBattery: false,
            lowBatteryThreshold: 0.1,
            maxConcurrentTasks: 8
        )
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var status: EmbeddingJobStatus = .idle
    @Published private(set) var lastError: String?
    
    // MARK: - Properties
    
    private let embeddingService: AppleNLEmbeddingService
    private let embeddingCache: EmbeddingCache
    private let config: Configuration
    private var currentTask: Task<Void, Never>?
    private var processedCount = 0
    private var successCount = 0
    private var failedCount = 0
    private var skippedCount = 0
    private var startTime: Date?
    
    /// Model identifier for Apple Intelligence embeddings
    private let targetModel = "apple-nl-embedding"
    
    // MARK: - Initialization
    
    init(
        embeddingService: AppleNLEmbeddingService,
        embeddingCache: EmbeddingCache,
        configuration: Configuration = .default
    ) {
        self.embeddingService = embeddingService
        self.embeddingCache = embeddingCache
        self.config = configuration
    }
    
    // MARK: - Public API
    
    /// Start the background re-embedding job
    func start() async {
        guard !status.isActive else {
            NSLog("⚠️ [BackgroundEmbeddingJob] Job already running")
            return
        }
        
        NSLog("🚀 [BackgroundEmbeddingJob] Starting re-embedding job")
        status = .preparing
        
        // Reset counters
        processedCount = 0
        successCount = 0
        failedCount = 0
        skippedCount = 0
        startTime = Date()
        lastError = nil
        
        // Get total count
        let totalCount: Int
        do {
            totalCount = try await embeddingCache.countEmbeddingsNeedingReembedding(excludingModel: targetModel)
        } catch {
            status = .failed(error: "Failed to count embeddings: \(error.localizedDescription)")
            lastError = error.localizedDescription
            return
        }
        
        if totalCount == 0 {
            NSLog("✅ [BackgroundEmbeddingJob] All embeddings already use Apple Intelligence")
            status = .completed(summary: EmbeddingJobSummary(
                totalProcessed: 0,
                successful: 0,
                failed: 0,
                skipped: 0,
                duration: 0,
                newModel: targetModel
            ))
            return
        }
        
        NSLog("📊 [BackgroundEmbeddingJob] Found %d embeddings to re-embed", totalCount)
        
        // Start the job
        currentTask = Task { [weak self] in
            await self?.runJob(totalCount: totalCount)
        }
    }
    
    /// Pause the job
    func pause() {
        guard case .running(let progress) = status else { return }
        NSLog("⏸️ [BackgroundEmbeddingJob] Pausing job")
        status = .paused(progress: progress)
    }
    
    /// Resume a paused job
    func resume() async {
        guard case .paused = status else { return }
        NSLog("▶️ [BackgroundEmbeddingJob] Resuming job")
        
        let totalCount: Int
        do {
            totalCount = try await embeddingCache.countEmbeddingsNeedingReembedding(excludingModel: targetModel) + processedCount
        } catch {
            status = .failed(error: "Failed to count remaining: \(error.localizedDescription)")
            return
        }
        
        currentTask = Task { [weak self] in
            await self?.runJob(totalCount: totalCount)
        }
    }
    
    /// Cancel the job
    func cancel() {
        NSLog("❌ [BackgroundEmbeddingJob] Cancelling job")
        currentTask?.cancel()
        currentTask = nil
        status = .cancelled
    }
    
    /// Get current progress
    func getProgress() -> EmbeddingJobProgress? {
        switch status {
        case .running(let progress), .paused(let progress):
            return progress
        default:
            return nil
        }
    }
    
    /// Check if re-embedding is needed
    func needsReembedding() async -> Bool {
        do {
            let count = try await embeddingCache.countEmbeddingsNeedingReembedding(excludingModel: targetModel)
            return count > 0
        } catch {
            return false
        }
    }
    
    /// Get statistics about embeddings by model
    func getModelStatistics() async -> [(model: String, count: Int, avgHitCount: Double)] {
        do {
            return try await embeddingCache.statisticsByModel()
        } catch {
            return []
        }
    }
    
    // MARK: - Private Implementation
    
    private func runJob(totalCount: Int) async {
        let startTime = self.startTime ?? Date()
        
        while !Task.isCancelled {
            // Check if paused
            if case .paused = status {
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
                continue
            }
            
            // Check battery if configured
            if config.respectBatteryStatus {
                if let batteryLevel = getBatteryLevel(), batteryLevel < config.lowBatteryThreshold {
                    if config.pauseOnLowBattery {
                        NSLog("🔋 [BackgroundEmbeddingJob] Pausing due to low battery (%.0f%%)", batteryLevel * 100)
                        let progress = makeProgress(total: totalCount, startTime: startTime)
                        status = .paused(progress: progress)
                        continue
                    }
                }
            }
            
            // Get next batch
            let batch: [CachedEmbedding]
            do {
                batch = try await embeddingCache.getEmbeddingsNeedingReembedding(
                    excludingModel: targetModel,
                    limit: config.batchSize
                )
            } catch {
                status = .failed(error: "Failed to fetch batch: \(error.localizedDescription)")
                lastError = error.localizedDescription
                return
            }
            
            // Check if done
            if batch.isEmpty {
                break
            }
            
            // Update status
            let progress = makeProgress(total: totalCount, startTime: startTime, currentFile: batch.first?.filename)
            status = .running(progress: progress)
            
            // Process batch
            await processBatch(batch)
            
            // Delay between batches
            try? await Task.sleep(nanoseconds: UInt64(config.delayBetweenBatches * 1_000_000_000))
        }
        
        // Job completed
        let duration = Date().timeIntervalSince(startTime)
        let summary = EmbeddingJobSummary(
            totalProcessed: processedCount,
            successful: successCount,
            failed: failedCount,
            skipped: skippedCount,
            duration: duration,
            newModel: targetModel
        )
        
        NSLog("✅ [BackgroundEmbeddingJob] Completed: %d processed, %d successful, %d failed, %d skipped in %.1fs",
              processedCount, successCount, failedCount, skippedCount, duration)
        
        status = .completed(summary: summary)
    }
    
    private func processBatch(_ batch: [CachedEmbedding]) async {
        await withTaskGroup(of: Bool.self) { group in
            for embedding in batch {
                group.addTask { [weak self] in
                    guard let self = self else { return false }
                    return await self.processEmbedding(embedding)
                }
            }
            
            for await success in group {
                processedCount += 1
                if success {
                    successCount += 1
                } else {
                    failedCount += 1
                }
            }
        }
    }
    
    private func processEmbedding(_ cached: CachedEmbedding) async -> Bool {
        // Build text from filename and parent path
        let text = "\(cached.filename) \(cached.parentPath)"
        
        // Generate new embedding with Apple Intelligence
        let newEmbedding = await embeddingService.embed(text: text)
        
        // Validate embedding
        guard !newEmbedding.isEmpty, newEmbedding.count > 0 else {
            NSLog("⚠️ [BackgroundEmbeddingJob] Empty embedding for: %@", cached.filename)
            return false
        }
        
        // Check if embedding is meaningful (not all zeros)
        let hasContent = newEmbedding.contains { $0 != 0 }
        guard hasContent else {
            NSLog("⚠️ [BackgroundEmbeddingJob] Zero embedding for: %@", cached.filename)
            skippedCount += 1
            return false
        }
        
        // Update the embedding
        do {
            try await embeddingCache.updateEmbedding(
                id: cached.id,
                embedding: newEmbedding,
                model: targetModel,
                type: .hybrid
            )
            return true
        } catch {
            NSLog("❌ [BackgroundEmbeddingJob] Failed to update %@: %@", cached.filename, error.localizedDescription)
            return false
        }
    }
    
    private func makeProgress(total: Int, startTime: Date, currentFile: String? = nil) -> EmbeddingJobProgress {
        let elapsed = Date().timeIntervalSince(startTime)
        let rate = processedCount > 0 ? elapsed / Double(processedCount) : 0
        let remaining = total - processedCount
        let estimatedRemaining = rate * Double(remaining)
        
        return EmbeddingJobProgress(
            totalFiles: total,
            processedFiles: processedCount,
            currentFile: currentFile,
            startTime: startTime,
            estimatedCompletion: estimatedRemaining > 0 ? Date().addingTimeInterval(estimatedRemaining) : nil
        )
    }
    
    private func getBatteryLevel() -> Double? {
        // Use IOKit to get battery level on macOS
        // Simplified implementation - in production would use proper IOKit calls
        return nil  // Return nil if battery info unavailable (desktop Mac)
    }
}

// MARK: - Singleton Access

extension BackgroundEmbeddingJob {
    /// Shared instance for app-wide access
    static let shared: BackgroundEmbeddingJob = {
        BackgroundEmbeddingJob(
            embeddingService: AppleNLEmbeddingService(),
            embeddingCache: EmbeddingCache()
        )
    }()
}

