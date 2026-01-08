// MARK: - Deep Analysis Task Manager
// Advanced task queue manager for background deep analysis with cancellation, priority, and guardrails

import Foundation

// MARK: - Task Status

/// Status of a deep analysis task
enum DeepAnalysisTaskStatus: String, Sendable {
    case queued = "Queued"
    case running = "Running"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

/// Priority level for analysis tasks
enum TaskPriority: Int, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Analysis Task

/// Represents a single deep analysis task
struct DeepAnalysisTask: Identifiable, Sendable {
    let id: UUID
    let file: TaxonomyScannedFile
    let currentConfidence: Double
    let currentCategoryPath: [String]
    let priority: TaskPriority
    var status: DeepAnalysisTaskStatus
    let queuedAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var error: String?
    var result: DeepAnalysisResult?
    
    /// Whether this file has been user-approved (should not auto-recategorize)
    let isUserApproved: Bool
    
    init(
        id: UUID = UUID(),
        file: TaxonomyScannedFile,
        currentConfidence: Double,
        currentCategoryPath: [String],
        priority: TaskPriority = .normal,
        isUserApproved: Bool = false
    ) {
        self.id = id
        self.file = file
        self.currentConfidence = currentConfidence
        self.currentCategoryPath = currentCategoryPath
        self.priority = priority
        self.status = .queued
        self.queuedAt = Date()
        self.isUserApproved = isUserApproved
    }
    
    var duration: TimeInterval? {
        guard let started = startedAt, let completed = completedAt else { return nil }
        return completed.timeIntervalSince(started)
    }
}

// MARK: - Task Manager Status

/// Overall status of the task manager
struct DeepAnalysisManagerStatus: Sendable {
    let isRunning: Bool
    let isPaused: Bool
    let queuedCount: Int
    let runningCount: Int
    let completedCount: Int
    let failedCount: Int
    let cancelledCount: Int
    let totalTasks: Int
    let currentTasks: [DeepAnalysisTask]
    let progress: Double
    let estimatedTimeRemaining: TimeInterval?
    
    var activeCount: Int {
        queuedCount + runningCount
    }
}

// MARK: - Task Manager Configuration

struct DeepAnalysisTaskManagerConfiguration: Sendable {
    /// Maximum concurrent analysis tasks
    let maxConcurrentTasks: Int
    
    /// Delay between task starts (throttling)
    let taskStartDelay: TimeInterval
    
    /// Whether to auto-recategorize based on results
    let autoRecategorize: Bool
    
    /// Minimum confidence improvement to trigger recategorization
    let minConfidenceImprovement: Double
    
    /// Whether to respect user-approved placements (never override)
    let respectUserApprovals: Bool
    
    /// Maximum retries for failed tasks
    let maxRetries: Int
    
    /// Timeout for individual tasks
    let taskTimeout: TimeInterval
    
    /// Whether to persist queue state
    let persistQueue: Bool
    
    static let `default` = DeepAnalysisTaskManagerConfiguration(
        maxConcurrentTasks: 2,
        taskStartDelay: 0.1,
        autoRecategorize: true,
        minConfidenceImprovement: 0.15,
        respectUserApprovals: true,
        maxRetries: 2,
        taskTimeout: 120.0,
        persistQueue: false
    )
    
    static let aggressive = DeepAnalysisTaskManagerConfiguration(
        maxConcurrentTasks: 4,
        taskStartDelay: 0.05,
        autoRecategorize: true,
        minConfidenceImprovement: 0.10,
        respectUserApprovals: true,
        maxRetries: 1,
        taskTimeout: 60.0,
        persistQueue: false
    )
    
    static let conservative = DeepAnalysisTaskManagerConfiguration(
        maxConcurrentTasks: 1,
        taskStartDelay: 0.5,
        autoRecategorize: false,
        minConfidenceImprovement: 0.20,
        respectUserApprovals: true,
        maxRetries: 3,
        taskTimeout: 180.0,
        persistQueue: true
    )
}

// MARK: - Deep Analysis Task Manager

/// Actor managing a queue of deep analysis tasks with priority, cancellation, and status tracking
actor DeepAnalysisTaskManager {
    
    // MARK: - Properties
    
    private let config: DeepAnalysisTaskManagerConfiguration
    private let deepAnalyzer: DeepAnalyzer
    
    private var taskQueue: [DeepAnalysisTask] = []
    private var runningTasks: [UUID: Task<Void, Never>] = [:]
    private var completedTasks: [DeepAnalysisTask] = []
    
    private var isRunning: Bool = false
    private var isPaused: Bool = false
    
    private var managementTask: Task<Void, Never>?
    
    // Callbacks
    private var statusCallback: (@Sendable (DeepAnalysisManagerStatus) -> Void)?
    private var taskCompletedCallback: (@Sendable (DeepAnalysisTask) -> Void)?
    private var recategorizeCallback: (@Sendable (DeepAnalysisTask, DeepAnalysisResult) -> Void)?
    
    // Statistics
    private var totalProcessed: Int = 0
    private var totalFailed: Int = 0
    private var totalCancelled: Int = 0
    private var averageTaskDuration: TimeInterval = 0
    
    // MARK: - Initialization
    
    init(
        configuration: DeepAnalysisTaskManagerConfiguration = .default,
        deepAnalyzer: DeepAnalyzer
    ) {
        self.config = configuration
        self.deepAnalyzer = deepAnalyzer
    }
    
    // MARK: - Queue Management
    
    /// Add tasks to the queue
    func enqueueTasks(_ tasks: [DeepAnalysisTask]) {
        taskQueue.append(contentsOf: tasks)
        sortQueue()
        
        NSLog("📋 [TaskManager] Enqueued \(tasks.count) tasks (total: \(taskQueue.count))")
        
        // Start processing if not running
        if !isRunning && !taskQueue.isEmpty {
            start()
        } else {
            notifyStatusUpdate()
        }
    }
    
    /// Add a single task
    func enqueueTask(_ task: DeepAnalysisTask) async {
        enqueueTasks([task])
    }
    
    /// Remove tasks by file ID
    func removeTasks(fileIds: Set<UUID>) {
        let beforeCount = taskQueue.count
        taskQueue.removeAll { fileIds.contains($0.file.id) }
        
        // Cancel running tasks
        for (taskId, runningTask) in runningTasks {
            if let task = taskQueue.first(where: { $0.id == taskId }),
               fileIds.contains(task.file.id) {
                runningTask.cancel()
                runningTasks.removeValue(forKey: taskId)
            }
        }
        
        let removed = beforeCount - taskQueue.count
        if removed > 0 {
            NSLog("🗑️ [TaskManager] Removed \(removed) tasks")
            notifyStatusUpdate()
        }
    }
    
    /// Clear all queued tasks (doesn't affect running tasks)
    func clearQueue() {
        let count = taskQueue.count
        taskQueue.removeAll()
        NSLog("🗑️ [TaskManager] Cleared \(count) queued tasks")
        notifyStatusUpdate()
    }
    
    /// Cancel a specific task
    func cancelTask(id: UUID) {
        // Remove from queue
        if let index = taskQueue.firstIndex(where: { $0.id == id }) {
            var task = taskQueue.remove(at: index)
            task.status = .cancelled
            completedTasks.append(task)
            totalCancelled += 1
            NSLog("❌ [TaskManager] Cancelled task: \(task.file.filename)")
        }
        
        // Cancel if running
        if let runningTask = runningTasks[id] {
            runningTask.cancel()
            runningTasks.removeValue(forKey: id)
        }
        
        notifyStatusUpdate()
    }
    
    /// Cancel all tasks
    func cancelAll() {
        let queuedCount = taskQueue.count
        let runningCount = runningTasks.count
        
        // Mark queued tasks as cancelled
        for task in taskQueue {
            var cancelled = task
            cancelled.status = .cancelled
            completedTasks.append(cancelled)
        }
        totalCancelled += queuedCount
        taskQueue.removeAll()
        
        // Cancel running tasks
        for (_, task) in runningTasks {
            task.cancel()
        }
        runningTasks.removeAll()
        
        NSLog("❌ [TaskManager] Cancelled all tasks (queued: \(queuedCount), running: \(runningCount))")
        notifyStatusUpdate()
    }
    
    // MARK: - Execution Control
    
    /// Start processing the queue
    func start() {
        guard !isRunning else {
            NSLog("⚠️ [TaskManager] Already running")
            return
        }
        
        isRunning = true
        isPaused = false
        
        NSLog("▶️ [TaskManager] Starting task manager (queue: \(taskQueue.count))")
        
        managementTask = Task {
            await runManagementLoop()
        }
        
        notifyStatusUpdate()
    }
    
    /// Pause processing (running tasks continue, no new starts)
    func pause() {
        guard isRunning && !isPaused else { return }
        
        isPaused = true
        NSLog("⏸️ [TaskManager] Paused (running tasks will complete)")
        notifyStatusUpdate()
    }
    
    /// Resume processing
    func resume() {
        guard isRunning && isPaused else { return }
        
        isPaused = false
        NSLog("▶️ [TaskManager] Resumed")
        notifyStatusUpdate()
    }
    
    /// Stop processing (cancels running tasks)
    func stop() {
        guard isRunning else { return }
        
        isRunning = false
        isPaused = false
        
        managementTask?.cancel()
        managementTask = nil
        
        // Cancel all running tasks
        for (_, task) in runningTasks {
            task.cancel()
        }
        runningTasks.removeAll()
        
        NSLog("🛑 [TaskManager] Stopped")
        notifyStatusUpdate()
    }
    
    // MARK: - Status & Callbacks
    
    /// Get current status
    func getStatus() -> DeepAnalysisManagerStatus {
        let queuedCount = taskQueue.filter { $0.status == .queued }.count
        let runningCount = runningTasks.count
        let completedCount = completedTasks.filter { $0.status == .completed }.count
        let failedCount = completedTasks.filter { $0.status == .failed }.count
        let cancelledCount = completedTasks.filter { $0.status == .cancelled }.count
        
        let totalTasks = taskQueue.count + runningTasks.count + completedTasks.count
        let progress = totalTasks > 0 ? Double(completedCount + failedCount + cancelledCount) / Double(totalTasks) : 0
        
        let estimatedRemaining: TimeInterval? = {
            guard averageTaskDuration > 0 && queuedCount > 0 else { return nil }
            return averageTaskDuration * Double(queuedCount)
        }()
        
        let currentRunning = taskQueue.filter { runningTasks.keys.contains($0.id) }
        
        return DeepAnalysisManagerStatus(
            isRunning: isRunning,
            isPaused: isPaused,
            queuedCount: queuedCount,
            runningCount: runningCount,
            completedCount: completedCount,
            failedCount: failedCount,
            cancelledCount: cancelledCount,
            totalTasks: totalTasks,
            currentTasks: currentRunning,
            progress: progress,
            estimatedTimeRemaining: estimatedRemaining
        )
    }
    
    /// Set status update callback
    func onStatusUpdate(_ callback: @escaping @Sendable (DeepAnalysisManagerStatus) -> Void) {
        self.statusCallback = callback
        notifyStatusUpdate()
    }
    
    /// Set task completed callback
    func onTaskCompleted(_ callback: @escaping @Sendable (DeepAnalysisTask) -> Void) {
        self.taskCompletedCallback = callback
    }
    
    /// Set recategorize callback
    func onRecategorize(_ callback: @escaping @Sendable (DeepAnalysisTask, DeepAnalysisResult) -> Void) {
        self.recategorizeCallback = callback
    }
    
    // MARK: - Private Methods
    
    private func sortQueue() {
        taskQueue.sort { task1, task2 in
            // First by priority
            if task1.priority != task2.priority {
                return task1.priority > task2.priority
            }
            // Then by confidence (lower confidence first)
            return task1.currentConfidence < task2.currentConfidence
        }
    }
    
    private func runManagementLoop() async {
        NSLog("🔄 [TaskManager] Management loop started")
        
        while isRunning && !Task.isCancelled {
            // Check if we can start new tasks
            if !isPaused && runningTasks.count < config.maxConcurrentTasks {
                // Get next task from queue
                if let nextTaskIndex = taskQueue.firstIndex(where: { $0.status == .queued }) {
                    var task = taskQueue[nextTaskIndex]
                    
                    // Start the task
                    task.status = .running
                    task.startedAt = Date()
                    taskQueue[nextTaskIndex] = task
                    
                    NSLog("🚀 [TaskManager] Starting task: \(task.file.filename) (priority: \(task.priority.rawValue))")
                    
                    let taskHandle = Task {
                        await executeTask(task)
                    }
                    
                    runningTasks[task.id] = taskHandle
                    notifyStatusUpdate()
                    
                    // Throttle task starts
                    try? await Task.sleep(for: .seconds(config.taskStartDelay))
                }
            }
            
            // Check if we're done
            if taskQueue.isEmpty && runningTasks.isEmpty {
                NSLog("✅ [TaskManager] All tasks completed")
                isRunning = false
                notifyStatusUpdate()
                break
            }
            
            // Sleep briefly before next iteration
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        NSLog("🔄 [TaskManager] Management loop ended")
    }
    
    private func executeTask(_ task: DeepAnalysisTask) async {
        var updatedTask = task
        
        do {
            // Get existing categories
            let existingCategories = taskQueue
                .flatMap { $0.currentCategoryPath }
                .reduce(into: Set<String>()) { $0.insert($1) }
                .sorted()
            
            // Execute deep analysis with timeout
            let result = try await withThrowingTaskGroup(of: DeepAnalysisResult.self) { group in
                group.addTask {
                    try await self.deepAnalyzer.analyze(
                        file: task.file,
                        existingCategories: Array(existingCategories)
                    )
                }
                
                // Timeout task
                group.addTask {
                    try await Task.sleep(for: .seconds(self.config.taskTimeout))
                    throw DeepAnalysisError.timeout
                }
                
                // Return first result (or throw if timeout wins)
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            
            updatedTask.result = result
            updatedTask.status = .completed
            updatedTask.completedAt = Date()
            
            // Update statistics
            totalProcessed += 1
            if let duration = updatedTask.duration {
                averageTaskDuration = (averageTaskDuration * Double(totalProcessed - 1) + duration) / Double(totalProcessed)
            }
            
            NSLog("✅ [TaskManager] Completed: \(task.file.filename) (\(String(format: "%.0f", result.confidence * 100))%)")
            
            // Check if recategorization is needed
            if shouldRecategorize(task: updatedTask, result: result) {
                NSLog("📁 [TaskManager] Recategorization recommended: \(task.file.filename)")
                recategorizeCallback?(updatedTask, result)
            }
            
        } catch {
            updatedTask.status = .failed
            updatedTask.error = error.localizedDescription
            updatedTask.completedAt = Date()
            totalFailed += 1
            
            NSLog("❌ [TaskManager] Failed: \(task.file.filename) - \(error.localizedDescription)")
        }
        
        // Move to completed
        if let index = taskQueue.firstIndex(where: { $0.id == task.id }) {
            taskQueue.remove(at: index)
        }
        completedTasks.append(updatedTask)
        runningTasks.removeValue(forKey: task.id)
        
        // Notify
        taskCompletedCallback?(updatedTask)
        notifyStatusUpdate()
    }
    
    private func shouldRecategorize(task: DeepAnalysisTask, result: DeepAnalysisResult) -> Bool {
        // Never recategorize user-approved files
        if config.respectUserApprovals && task.isUserApproved {
            NSLog("🔒 [TaskManager] Skipping recategorization (user-approved): \(task.file.filename)")
            return false
        }
        
        // Check if auto-recategorize is enabled
        guard config.autoRecategorize else { return false }
        
        // Check confidence improvement
        let confidenceImproved = result.confidence > task.currentConfidence + config.minConfidenceImprovement
        
        // Check category change
        let categoryChanged = result.categoryPath != task.currentCategoryPath
        
        // Recategorize if confidence improved OR category changed with better confidence
        return (confidenceImproved || categoryChanged) && result.confidence > task.currentConfidence
    }
    
    private func notifyStatusUpdate() {
        let status = getStatus()
        statusCallback?(status)
    }
}

// MARK: - Error

enum DeepAnalysisTaskManagerError: Error, LocalizedError {
    case timeout
    case queueFull
    case taskNotFound(UUID)
    case invalidState(String)
    
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Task timed out"
        case .queueFull:
            return "Task queue is full"
        case .taskNotFound(let id):
            return "Task not found: \(id)"
        case .invalidState(let message):
            return "Invalid state: \(message)"
        }
    }
}

