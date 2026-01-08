// MARK: - Concurrency Throttler
// Rate limiting and concurrency control for LLM and I/O operations

import Foundation

// MARK: - Concurrency Throttler

/// Controls concurrent access to limited resources (LLM, I/O)
/// Prevents system overload during batch operations
actor ConcurrencyThrottler {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// Maximum concurrent operations
        let maxConcurrent: Int
        
        /// Minimum delay between operations (rate limiting)
        let minDelayBetweenOps: TimeInterval
        
        /// Whether to queue requests or reject when at capacity
        let queueWhenFull: Bool
        
        /// Maximum queue size (only if queueWhenFull is true)
        let maxQueueSize: Int
        
        static let llm = Configuration(
            maxConcurrent: 2,
            minDelayBetweenOps: 0.5,
            queueWhenFull: true,
            maxQueueSize: 100
        )
        
        static let io = Configuration(
            maxConcurrent: 5,
            minDelayBetweenOps: 0.0,
            queueWhenFull: true,
            maxQueueSize: 500
        )
        
        static let deepAnalysis = Configuration(
            maxConcurrent: 1,
            minDelayBetweenOps: 1.0,
            queueWhenFull: true,
            maxQueueSize: 50
        )
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private var activeCount: Int = 0
    private var queuedCount: Int = 0
    private var lastOperationTime: Date = .distantPast
    private var totalOperations: Int = 0
    private var totalWaitTime: TimeInterval = 0
    
    // MARK: - Initialization
    
    init(configuration: Configuration) {
        self.config = configuration
    }
    
    // MARK: - Throttling
    
    /// Acquire a slot to perform an operation
    /// Returns true when slot is available, false if rejected
    func acquire() async throws -> Bool {
        // Check if at capacity
        if activeCount >= config.maxConcurrent {
            if !config.queueWhenFull {
                return false
            }
            
            // Check queue size
            if queuedCount >= config.maxQueueSize {
                throw ThrottlerError.queueFull
            }
            
            // Queue and wait
            queuedCount += 1
            let startWait = Date()
            
            while activeCount >= config.maxConcurrent {
                try await Task.sleep(for: .milliseconds(50))
            }
            
            queuedCount -= 1
            totalWaitTime += Date().timeIntervalSince(startWait)
        }
        
        // Apply rate limiting
        let timeSinceLast = Date().timeIntervalSince(lastOperationTime)
        if timeSinceLast < config.minDelayBetweenOps {
            let delay = config.minDelayBetweenOps - timeSinceLast
            try await Task.sleep(for: .milliseconds(Int(delay * 1000)))
        }
        
        activeCount += 1
        lastOperationTime = Date()
        totalOperations += 1
        
        return true
    }
    
    /// Release a slot after operation completes
    func release() {
        activeCount = max(0, activeCount - 1)
    }
    
    /// Execute an operation with automatic acquire/release
    func throttled<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        guard try await acquire() else {
            throw ThrottlerError.rejected
        }
        
        defer { release() }
        return try await operation()
    }
    
    // MARK: - Statistics
    
    /// Current statistics
    var statistics: ThrottlerStatistics {
        ThrottlerStatistics(
            activeCount: activeCount,
            queuedCount: queuedCount,
            totalOperations: totalOperations,
            averageWaitTime: totalOperations > 0 ? totalWaitTime / Double(totalOperations) : 0,
            maxConcurrent: config.maxConcurrent
        )
    }
    
    /// Reset statistics
    func resetStatistics() {
        totalOperations = 0
        totalWaitTime = 0
    }
}

// MARK: - Throttler Statistics

struct ThrottlerStatistics: Sendable {
    let activeCount: Int
    let queuedCount: Int
    let totalOperations: Int
    let averageWaitTime: TimeInterval
    let maxConcurrent: Int
    
    var utilizationPercentage: Double {
        guard maxConcurrent > 0 else { return 0 }
        return Double(activeCount) / Double(maxConcurrent) * 100
    }
}

// MARK: - Throttler Errors

enum ThrottlerError: LocalizedError {
    case queueFull
    case rejected
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .queueFull:
            return "Operation queue is full"
        case .rejected:
            return "Operation rejected (at capacity)"
        case .timeout:
            return "Operation timed out waiting for slot"
        }
    }
}

// MARK: - Global Throttlers

/// Shared throttlers for common resources
enum Throttlers {
    /// LLM API throttler (prevents overloading Ollama)
    static let llm = ConcurrencyThrottler(configuration: .llm)
    
    /// File I/O throttler
    static let io = ConcurrencyThrottler(configuration: .io)
    
    /// Deep analysis throttler (most restrictive)
    static let deepAnalysis = ConcurrencyThrottler(configuration: .deepAnalysis)
}

// MARK: - Convenience Extensions

extension ConcurrencyThrottler {
    /// Execute multiple operations with throttling
    func throttledBatch<T: Sendable, R: Sendable>(
        items: [T],
        operation: @Sendable @escaping (T) async throws -> R,
        progressCallback: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [R] {
        var results: [R] = []
        
        for (index, item) in items.enumerated() {
            let result = try await throttled {
                try await operation(item)
            }
            results.append(result)
            progressCallback?(index + 1, items.count)
        }
        
        return results
    }
}

