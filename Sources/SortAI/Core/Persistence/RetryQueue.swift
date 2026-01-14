// MARK: - Retry Queue
// Handles retry logic for database operations that may transiently fail
// Replaces silent `try?` with tracked, retriable operations

import Foundation

// MARK: - Retry Policy

/// Configuration for retry behavior
struct RetryPolicy: Sendable {
    /// Maximum number of retry attempts
    let maxAttempts: Int
    
    /// Initial delay between retries
    let initialDelay: TimeInterval
    
    /// Multiplier for exponential backoff
    let backoffMultiplier: Double
    
    /// Maximum delay between retries
    let maxDelay: TimeInterval
    
    /// Whether to use jitter to prevent thundering herd
    let useJitter: Bool
    
    /// Default policy: 3 attempts with exponential backoff
    static let `default` = RetryPolicy(
        maxAttempts: 3,
        initialDelay: 0.1,
        backoffMultiplier: 2.0,
        maxDelay: 2.0,
        useJitter: true
    )
    
    /// Aggressive retry policy for critical operations
    static let aggressive = RetryPolicy(
        maxAttempts: 5,
        initialDelay: 0.05,
        backoffMultiplier: 1.5,
        maxDelay: 1.0,
        useJitter: true
    )
    
    /// Patient retry policy for non-urgent operations
    static let patient = RetryPolicy(
        maxAttempts: 3,
        initialDelay: 1.0,
        backoffMultiplier: 2.0,
        maxDelay: 30.0,
        useJitter: true
    )
    
    /// Calculate delay for a given attempt (0-indexed)
    func delayForAttempt(_ attempt: Int) -> TimeInterval {
        var delay = initialDelay * pow(backoffMultiplier, Double(attempt))
        delay = min(delay, maxDelay)
        
        if useJitter {
            // Add ±20% jitter
            let jitter = delay * Double.random(in: -0.2...0.2)
            delay += jitter
        }
        
        return max(0, delay)
    }
}

// MARK: - Retry Result

/// Result of a retry operation
enum RetryResult<T: Sendable>: Sendable {
    case success(T)
    case failed(attempts: Int, lastError: Error)
    case abandoned(reason: String)
}

// MARK: - Queued Operation

/// A tracked operation waiting to be retried
struct QueuedOperation: Sendable, Identifiable {
    let id: UUID
    let name: String
    let priority: OperationPriority
    let createdAt: Date
    var attempts: Int
    var lastAttempt: Date?
    var lastError: String?
    var nextRetry: Date?
    
    enum OperationPriority: Int, Sendable, Comparable {
        case low = 0
        case normal = 1
        case high = 2
        case critical = 3
        
        static func < (lhs: OperationPriority, rhs: OperationPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

// MARK: - Retry Statistics

/// Statistics about retry operations
struct RetryStatistics: Sendable {
    var totalAttempts: Int = 0
    var successfulRetries: Int = 0
    var failedRetries: Int = 0
    var abandonedOperations: Int = 0
    var averageAttemptsPerSuccess: Double = 0
    var totalTimeWaited: TimeInterval = 0
    
    mutating func recordSuccess(attempts: Int, timeWaited: TimeInterval) {
        totalAttempts += attempts
        successfulRetries += 1
        totalTimeWaited += timeWaited
        
        // Update rolling average
        let total = successfulRetries + failedRetries
        averageAttemptsPerSuccess = Double(totalAttempts) / max(1.0, Double(total))
    }
    
    mutating func recordFailure(attempts: Int, timeWaited: TimeInterval) {
        totalAttempts += attempts
        failedRetries += 1
        totalTimeWaited += timeWaited
    }
    
    mutating func recordAbandon() {
        abandonedOperations += 1
    }
}

// MARK: - Retry Queue Actor

/// Actor that manages retrying failed operations with exponential backoff
actor RetryQueue {
    
    // MARK: - Properties
    
    private var pendingOperations: [UUID: QueuedOperation] = [:]
    private var statistics = RetryStatistics()
    private var isProcessing = false
    private let policy: RetryPolicy
    
    /// Maximum number of operations to queue before dropping oldest
    private let maxQueueSize: Int
    
    // MARK: - Initialization
    
    init(policy: RetryPolicy = .default, maxQueueSize: Int = 100) {
        self.policy = policy
        self.maxQueueSize = maxQueueSize
    }
    
    // MARK: - Public API
    
    /// Execute an operation with automatic retry on failure
    /// - Parameters:
    ///   - name: Human-readable operation name for logging
    ///   - priority: Priority level for retry scheduling
    ///   - operation: The async throwing operation to execute
    /// - Returns: The result of the operation, or throws after max retries
    func execute<T: Sendable>(
        name: String,
        priority: QueuedOperation.OperationPriority = .normal,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?
        let startTime = Date()
        
        while attempt < policy.maxAttempts {
            do {
                let result = try await operation()
                
                // Record successful retry if not first attempt
                if attempt > 0 {
                    let elapsed = Date().timeIntervalSince(startTime)
                    statistics.recordSuccess(attempts: attempt + 1, timeWaited: elapsed)
                    NSLog("✅ [RetryQueue] '\(name)' succeeded after \(attempt + 1) attempts")
                }
                
                return result
                
            } catch {
                lastError = error
                attempt += 1
                
                if attempt < policy.maxAttempts {
                    let delay = policy.delayForAttempt(attempt - 1)
                    NSLog("⚠️ [RetryQueue] '\(name)' failed (attempt \(attempt)/\(policy.maxAttempts)): \(error.localizedDescription). Retrying in \(String(format: "%.2f", delay))s")
                    
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        // All retries exhausted
        let elapsed = Date().timeIntervalSince(startTime)
        statistics.recordFailure(attempts: attempt, timeWaited: elapsed)
        NSLog("❌ [RetryQueue] '\(name)' failed after \(attempt) attempts: \(lastError?.localizedDescription ?? "unknown")")
        
        throw RetryError.exhausted(
            operationName: name,
            attempts: attempt,
            lastError: lastError ?? RetryError.unknown
        )
    }
    
    /// Execute an operation with retry, returning nil instead of throwing on failure
    /// Use this for non-critical operations where failure is acceptable
    func executeOrNil<T: Sendable>(
        name: String,
        priority: QueuedOperation.OperationPriority = .low,
        operation: @Sendable () async throws -> T
    ) async -> T? {
        do {
            return try await execute(name: name, priority: priority, operation: operation)
        } catch {
            NSLog("⚠️ [RetryQueue] '\(name)' failed silently (non-critical): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Execute an operation, falling back to a default value on failure
    func executeWithFallback<T: Sendable>(
        name: String,
        fallback: T,
        priority: QueuedOperation.OperationPriority = .normal,
        operation: @Sendable () async throws -> T
    ) async -> T {
        do {
            return try await execute(name: name, priority: priority, operation: operation)
        } catch {
            NSLog("⚠️ [RetryQueue] '\(name)' failed, using fallback value")
            return fallback
        }
    }
    
    /// Queue an operation for background retry (fire-and-forget)
    /// This is nonisolated so it can be called without await from sync contexts
    nonisolated func queueForRetry(
        name: String,
        priority: QueuedOperation.OperationPriority = .normal,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        Task {
            await _queueForRetryInternal(name: name, priority: priority, operation: operation)
        }
    }
    
    /// Internal queue implementation
    private func _queueForRetryInternal(
        name: String,
        priority: QueuedOperation.OperationPriority,
        operation: @escaping @Sendable () async throws -> Void
    ) {
        let opId = UUID()
        let queuedOp = QueuedOperation(
            id: opId,
            name: name,
            priority: priority,
            createdAt: Date(),
            attempts: 0,
            lastAttempt: nil,
            lastError: nil,
            nextRetry: Date()
        )
        
        // Enforce queue size limit
        if pendingOperations.count >= maxQueueSize {
            // Remove oldest low-priority operation
            let oldest = pendingOperations.values
                .filter { $0.priority <= priority }
                .sorted { $0.createdAt < $1.createdAt }
                .first
            
            if let toRemove = oldest {
                pendingOperations.removeValue(forKey: toRemove.id)
                statistics.recordAbandon()
                NSLog("⚠️ [RetryQueue] Queue full, abandoned: '\(toRemove.name)'")
            }
        }
        
        pendingOperations[opId] = queuedOp
        NSLog("📥 [RetryQueue] Queued '\(name)' for background retry")
        
        // Schedule background execution
        Task {
            await processQueuedOperation(id: opId, operation: operation)
        }
    }
    
    /// Get current retry statistics
    func getStatistics() -> RetryStatistics {
        statistics
    }
    
    /// Get pending operations
    func getPendingOperations() -> [QueuedOperation] {
        Array(pendingOperations.values).sorted { $0.priority > $1.priority }
    }
    
    /// Cancel a pending operation
    func cancelOperation(id: UUID) {
        if let op = pendingOperations.removeValue(forKey: id) {
            statistics.recordAbandon()
            NSLog("🚫 [RetryQueue] Cancelled: '\(op.name)'")
        }
    }
    
    /// Cancel all pending operations
    func cancelAll() {
        let count = pendingOperations.count
        pendingOperations.removeAll()
        statistics.abandonedOperations += count
        NSLog("🚫 [RetryQueue] Cancelled all \(count) pending operations")
    }
    
    // MARK: - Private Methods
    
    private func processQueuedOperation(
        id: UUID,
        operation: @escaping @Sendable () async throws -> Void
    ) async {
        guard var queuedOp = pendingOperations[id] else { return }
        
        while queuedOp.attempts < policy.maxAttempts {
            // Update attempt info
            queuedOp.attempts += 1
            queuedOp.lastAttempt = Date()
            pendingOperations[id] = queuedOp
            
            do {
                try await operation()
                
                // Success - remove from queue
                pendingOperations.removeValue(forKey: id)
                statistics.recordSuccess(attempts: queuedOp.attempts, timeWaited: 0)
                NSLog("✅ [RetryQueue] Background '\(queuedOp.name)' succeeded after \(queuedOp.attempts) attempts")
                return
                
            } catch {
                queuedOp.lastError = error.localizedDescription
                
                if queuedOp.attempts < policy.maxAttempts {
                    let delay = policy.delayForAttempt(queuedOp.attempts - 1)
                    queuedOp.nextRetry = Date().addingTimeInterval(delay)
                    pendingOperations[id] = queuedOp
                    
                    NSLog("⚠️ [RetryQueue] Background '\(queuedOp.name)' failed (\(queuedOp.attempts)/\(policy.maxAttempts))")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    
                    // Re-fetch in case it was cancelled
                    guard let updated = pendingOperations[id] else { return }
                    queuedOp = updated
                }
            }
        }
        
        // All retries exhausted
        pendingOperations.removeValue(forKey: id)
        statistics.recordFailure(attempts: queuedOp.attempts, timeWaited: 0)
        NSLog("❌ [RetryQueue] Background '\(queuedOp.name)' failed after \(queuedOp.attempts) attempts")
    }
}

// MARK: - Retry Error

enum RetryError: LocalizedError {
    case exhausted(operationName: String, attempts: Int, lastError: Error)
    case cancelled(operationName: String)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .exhausted(let name, let attempts, let error):
            return "'\(name)' failed after \(attempts) attempts: \(error.localizedDescription)"
        case .cancelled(let name):
            return "'\(name)' was cancelled"
        case .unknown:
            return "Unknown retry error"
        }
    }
}

// MARK: - Convenience Extensions

extension RetryQueue {
    /// Create a shared retry queue instance for database operations
    static let databaseOperations = RetryQueue(policy: .default, maxQueueSize: 50)
    
    /// Create a retry queue for network operations
    static let networkOperations = RetryQueue(policy: .patient, maxQueueSize: 20)
    
    /// Create a retry queue for file operations
    static let fileOperations = RetryQueue(policy: .aggressive, maxQueueSize: 100)
}

// MARK: - Database Retry Helpers
// 
// Example usage of RetryQueue with database operations:
//
// ```swift
// // For critical database operations, use retry queue:
// let result = try await RetryQueue.databaseOperations.execute(name: "fetchData") {
//     try database.read { db in
//         try MyRecord.fetchAll(db)
//     }
// }
//
// // For non-critical operations, use executeOrNil:
// let optionalResult = await RetryQueue.databaseOperations.executeOrNil(name: "optionalFetch") {
//     try database.read { db in
//         try MyRecord.fetchOne(db, key: id)
//     }
// }
// ```
