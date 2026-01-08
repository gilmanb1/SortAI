// MARK: - Concurrency Manager
// Memory-aware concurrency controller that adjusts processing based on system resources
// Monitors thermal state and memory pressure to prevent system overload

import Foundation

// MARK: - Memory Pressure Level

enum MemoryPressureLevel: String, Sendable {
    case low = "Low"
    case nominal = "Nominal"
    case fair = "Fair"
    case serious = "Serious"
    case critical = "Critical"
    
    /// Recommended concurrency limit for this pressure level
    var recommendedConcurrency: Int {
        switch self {
        case .low: return 4
        case .nominal: return 2
        case .fair: return 1
        case .serious, .critical: return 1
        }
    }
}

// MARK: - Concurrency Stats

struct ConcurrencyStats: Sendable {
    let activeExtractions: Int
    let queuedExtractions: Int
    let pressureLevel: MemoryPressureLevel
    let currentLimit: Int
    let thermalState: ProcessInfo.ThermalState
}

// MARK: - Concurrency Manager Actor

/// Manages concurrent audio extractions with memory pressure awareness
actor ConcurrencyManager {
    
    // MARK: - Singleton
    
    static let shared = ConcurrencyManager()
    
    // MARK: - Properties
    
    private var activeCount: Int = 0
    private var queuedTasks: [UUID] = []
    private var configuredLimit: Int = 0  // 0 = auto-detect
    private let processInfo = ProcessInfo.processInfo
    
    // MARK: - Initialization
    
    private init() {
        NSLog("⚡️ [ConcurrencyManager] Initialized with auto-detect mode")
        // Log system info asynchronously
        Task {
            await logSystemInfo()
        }
    }
    
    // MARK: - Configuration
    
    /// Set maximum concurrent extractions (0 = auto-detect based on memory)
    func setLimit(_ limit: Int) {
        configuredLimit = max(0, limit)
        let mode = limit == 0 ? "auto-detect" : "\(limit)"
        NSLog("⚡️ [ConcurrencyManager] Concurrency limit set to: \(mode)")
    }
    
    /// Get current effective concurrency limit
    func getCurrentLimit() -> Int {
        if configuredLimit > 0 {
            return configuredLimit
        }
        return detectConcurrencyLimit()
    }
    
    // MARK: - Task Management
    
    /// Request permission to start an extraction task
    /// Suspends if at capacity until a slot becomes available
    func acquireSlot() async -> UUID {
        let taskId = UUID()
        
        // Wait until we have capacity
        while activeCount >= getCurrentLimit() {
            queuedTasks.append(taskId)
            NSLog("⏳ [ConcurrencyManager] Task \(taskId) queued (\(queuedTasks.count) in queue)")
            
            // Wait a bit before checking again
            try? await Task.sleep(for: .milliseconds(500))
            
            // Check if still queued (might have been granted while sleeping)
            if !queuedTasks.contains(taskId) {
                break
            }
        }
        
        // Remove from queue if present
        queuedTasks = queuedTasks.filter { $0 != taskId }
        
        // Grant slot
        activeCount += 1
        NSLog("▶️  [ConcurrencyManager] Slot acquired for task \(taskId) (active: \(activeCount)/\(getCurrentLimit()))")
        
        return taskId
    }
    
    /// Release a slot when extraction completes
    func releaseSlot(taskId: UUID) async {
        activeCount = max(0, activeCount - 1)
        NSLog("✅ [ConcurrencyManager] Slot released for task \(taskId) (active: \(activeCount)/\(getCurrentLimit()))")
        
        // Wake up queued tasks
        if !queuedTasks.isEmpty {
            NSLog("⏭️  [ConcurrencyManager] Waking up \(queuedTasks.count) queued task(s)")
        }
    }
    
    /// Execute a task with automatic slot management
    func execute<T>(
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        let taskId = await acquireSlot()
        defer {
            Task {
                await releaseSlot(taskId: taskId)
            }
        }
        return try await operation()
    }
    
    // MARK: - Statistics
    
    /// Get current concurrency statistics
    func getStats() -> ConcurrencyStats {
        ConcurrencyStats(
            activeExtractions: activeCount,
            queuedExtractions: queuedTasks.count,
            pressureLevel: detectMemoryPressure(),
            currentLimit: getCurrentLimit(),
            thermalState: processInfo.thermalState
        )
    }
    
    /// Log current system and concurrency state
    func logStats() {
        let stats = getStats()
        NSLog("📊 [ConcurrencyManager] Active: \(stats.activeExtractions)/\(stats.currentLimit), Queued: \(stats.queuedExtractions), Pressure: \(stats.pressureLevel.rawValue), Thermal: \(thermalStateName(stats.thermalState))")
    }
    
    // MARK: - Memory Pressure Detection
    
    /// Detect current memory pressure level
    private func detectMemoryPressure() -> MemoryPressureLevel {
        // Use thermal state as a proxy for memory pressure
        // More sophisticated implementations could use memory footprint APIs
        switch processInfo.thermalState {
        case .nominal:
            return .low
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .nominal
        }
    }
    
    /// Automatically determine concurrency limit based on system state
    private func detectConcurrencyLimit() -> Int {
        let pressure = detectMemoryPressure()
        let thermalLimit = pressure.recommendedConcurrency
        
        // Consider processor count as well
        let processorCount = processInfo.activeProcessorCount
        let processorLimit = max(1, processorCount / 2)  // Use half of available cores
        
        // Take the minimum to be conservative
        return min(thermalLimit, processorLimit)
    }
    
    // MARK: - System Info
    
    private func logSystemInfo() {
        let processorCount = processInfo.activeProcessorCount
        let physicalMemory = processInfo.physicalMemory
        let memoryGB = Double(physicalMemory) / (1024 * 1024 * 1024)
        
        NSLog("💻 [ConcurrencyManager] System: \(processorCount) cores, \(String(format: "%.1f", memoryGB)) GB RAM")
    }
    
    private func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: - Convenience Extensions

extension ConcurrencyManager {
    
    /// Execute multiple operations with automatic concurrency management
    func executeBatch<T: Sendable>(
        operations: [@Sendable () async throws -> T]
    ) async throws -> [T] {
        try await withThrowingTaskGroup(of: (Int, T).self) { group in
            for (index, operation) in operations.enumerated() {
                group.addTask {
                    let result = try await self.execute(operation: operation)
                    return (index, result)
                }
            }
            
            var results = [(Int, T)]()
            for try await result in group {
                results.append(result)
            }
            
            // Sort by original index to maintain order
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }
}

