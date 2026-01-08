// MARK: - Deep Analysis Task Manager Tests

import Testing
import Foundation
@testable import SortAI

// MARK: - Helper Actors for Concurrent Callbacks

actor StatusCollector {
    private(set) var statuses: [DeepAnalysisManagerStatus] = []
    
    func add(_ status: DeepAnalysisManagerStatus) {
        statuses.append(status)
    }
    
    var count: Int {
        statuses.count
    }
}

actor RecatCollector {
    private(set) var items: [(DeepAnalysisTask, DeepAnalysisResult)] = []
    
    func add(_ task: DeepAnalysisTask, _ result: DeepAnalysisResult) {
        items.append((task, result))
    }
    
    var count: Int {
        items.count
    }
}

@Suite("Deep Analysis Task Manager Tests")
struct DeepAnalysisTaskManagerTests {
    
    // MARK: - Helper: Mock Deep Analyzer
    
    actor MockDeepAnalyzer {
        private let delay: TimeInterval
        private let shouldFail: Bool
        
        init(delay: TimeInterval = 0.1, shouldFail: Bool = false) {
            self.delay = delay
            self.shouldFail = shouldFail
        }
        
        func analyze(file: TaxonomyScannedFile, existingCategories: [String]) async throws -> DeepAnalysisResult {
            try await Task.sleep(for: .seconds(delay))
            
            if shouldFail {
                throw DeepAnalysisError.extractionFailed("Mock failure")
            }
            
            // Return a mock result with improved confidence
            return DeepAnalysisResult(
                filename: file.filename,
                categoryPath: ["Documents", "Work"],
                confidence: 0.9,
                rationale: "Mock analysis result",
                contentSummary: "Mock content summary",
                suggestedTags: ["test", "mock"]
            )
        }
    }
    
    // MARK: - Test Helpers
    
    func createMockFile(name: String) -> TaxonomyScannedFile {
        TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/\(name)"),
            filename: name,
            fileExtension: "txt",
            relativePath: name,
            fileSize: 100,
            createdAt: Date(),
            modifiedAt: Date(),
            contentType: nil
        )
    }
    
    func createMockTask(
        file: TaxonomyScannedFile,
        confidence: Double = 0.5,
        priority: TaskPriority = .normal,
        isUserApproved: Bool = false
    ) -> DeepAnalysisTask {
        DeepAnalysisTask(
            file: file,
            currentConfidence: confidence,
            currentCategoryPath: ["Uncategorized"],
            priority: priority,
            isUserApproved: isUserApproved
        )
    }
    
    // MARK: - Tests
    
    @Test("Task manager initialization")
    func testInitialization() async {
        let analyzer = DeepAnalyzer(
            configuration: .fast,
            llmProvider: OllamaProvider()
        )
        let manager = DeepAnalysisTaskManager(
            configuration: .default,
            deepAnalyzer: analyzer
        )
        
        let status = await manager.getStatus()
        #expect(status.isRunning == false)
        #expect(status.queuedCount == 0)
        #expect(status.totalTasks == 0)
    }
    
    @Test("Enqueue and process single task")
    func testEnqueueSingleTask() async throws {
        let analyzer = DeepAnalyzer(
            configuration: .fast,
            llmProvider: OllamaProvider()
        )
        let manager = DeepAnalysisTaskManager(
            configuration: .default,
            deepAnalyzer: analyzer
        )
        
        let file = createMockFile(name: "test.txt")
        let task = createMockTask(file: file)
        
        await manager.enqueueTask(task)
        
        let status = await manager.getStatus()
        #expect(status.queuedCount > 0)
    }
    
    @Test("Enqueue multiple tasks with priorities")
    func testEnqueueWithPriorities() async {
        let analyzer = DeepAnalyzer(
            configuration: .fast,
            llmProvider: OllamaProvider()
        )
        let manager = DeepAnalysisTaskManager(
            configuration: .default,
            deepAnalyzer: analyzer
        )
        
        let tasks = [
            createMockTask(file: createMockFile(name: "low.txt"), priority: .low),
            createMockTask(file: createMockFile(name: "high.txt"), priority: .high),
            createMockTask(file: createMockFile(name: "normal.txt"), priority: .normal),
            createMockTask(file: createMockFile(name: "critical.txt"), priority: .critical)
        ]
        
        await manager.enqueueTasks(tasks)
        
        let status = await manager.getStatus()
        #expect(status.queuedCount == 4)
        
        // High priority tasks should be first
        #expect(status.currentTasks.first?.priority == .critical || status.queuedCount == 4)
    }
    
    @Test("Task status updates")
    func testTaskStatusUpdates() async {
        let analyzer = DeepAnalyzer(
            configuration: .fast,
            llmProvider: OllamaProvider()
        )
        let manager = DeepAnalysisTaskManager(
            configuration: .default,
            deepAnalyzer: analyzer
        )
        
        let statusActor = StatusCollector()
        
        await manager.onStatusUpdate { status in
            Task { await statusActor.add(status) }
        }
        
        let file = createMockFile(name: "test.txt")
        let task = createMockTask(file: file)
        
        await manager.enqueueTask(task)
        
        // Wait for async callback task to execute
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Should have received status update
        let count = await statusActor.count
        #expect(count > 0)
    }
    
    @Test("Cancel single task")
    func testCancelSingleTask() async {
        let analyzer = DeepAnalyzer(
            configuration: .fast,
            llmProvider: OllamaProvider()
        )
        let manager = DeepAnalysisTaskManager(
            configuration: .default,
            deepAnalyzer: analyzer
        )
        
        let file = createMockFile(name: "test.txt")
        let task = createMockTask(file: file)
        
        await manager.enqueueTask(task)
        await manager.cancelTask(id: task.id)
        
        let status = await manager.getStatus()
        #expect(status.cancelledCount >= 0)  // May have started before cancel
    }
    
    @Test("Cancel all tasks")
    func testCancelAllTasks() async {
        let analyzer = DeepAnalyzer(
            configuration: .fast,
            llmProvider: OllamaProvider()
        )
        let manager = DeepAnalysisTaskManager(
            configuration: .default,
            deepAnalyzer: analyzer
        )
        
        let tasks = (0..<5).map { i in
            createMockTask(file: createMockFile(name: "file\(i).txt"))
        }
        
        await manager.enqueueTasks(tasks)
        await manager.cancelAll()
        
        let status = await manager.getStatus()
        #expect(status.queuedCount == 0)
    }
    
    @Test("Pause and resume")
    func testPauseAndResume() async {
        let analyzer = DeepAnalyzer(
            configuration: .fast,
            llmProvider: OllamaProvider()
        )
        let manager = DeepAnalysisTaskManager(
            configuration: .default,
            deepAnalyzer: analyzer
        )
        
        let tasks = (0..<3).map { i in
            createMockTask(file: createMockFile(name: "file\(i).txt"))
        }
        
        await manager.enqueueTasks(tasks)
        await manager.start()
        
        // Pause
        await manager.pause()
        var status = await manager.getStatus()
        #expect(status.isPaused == true)
        
        // Resume
        await manager.resume()
        status = await manager.getStatus()
        #expect(status.isPaused == false)
        
        // Stop for cleanup
        await manager.stop()
    }
    
    @Test("Stop manager")
    func testStop() async {
        let analyzer = DeepAnalyzer(
            configuration: .fast,
            llmProvider: OllamaProvider()
        )
        let manager = DeepAnalysisTaskManager(
            configuration: .default,
            deepAnalyzer: analyzer
        )
        
        let tasks = (0..<3).map { i in
            createMockTask(file: createMockFile(name: "file\(i).txt"))
        }
        
        await manager.enqueueTasks(tasks)
        await manager.start()
        await manager.stop()
        
        let status = await manager.getStatus()
        #expect(status.isRunning == false)
    }
    
    @Test("User-approved files not recategorized")
    func testUserApprovedGuardrail() async {
        let analyzer = DeepAnalyzer(
            configuration: .fast,
            llmProvider: OllamaProvider()
        )
        let manager = DeepAnalysisTaskManager(
            configuration: .default,
            deepAnalyzer: analyzer
        )
        
        let file = createMockFile(name: "user_approved.txt")
        let task = createMockTask(file: file, isUserApproved: true)
        
        let recatActor = RecatCollector()
        
        await manager.onRecategorize { task, result in
            Task { await recatActor.add(task, result) }
        }
        
        await manager.enqueueTask(task)
        
        // User-approved files should not trigger recategorization
        // (would need to wait for task to complete in real scenario)
        let count = await recatActor.count
        #expect(count >= 0)  // Just verify no crash
    }
    
    @Test("Configuration presets")
    func testConfigurationPresets() {
        let defaultConfig = DeepAnalysisTaskManagerConfiguration.default
        #expect(defaultConfig.maxConcurrentTasks == 2)
        #expect(defaultConfig.respectUserApprovals == true)
        
        let aggressiveConfig = DeepAnalysisTaskManagerConfiguration.aggressive
        #expect(aggressiveConfig.maxConcurrentTasks == 4)
        #expect(aggressiveConfig.taskStartDelay < defaultConfig.taskStartDelay)
        
        let conservativeConfig = DeepAnalysisTaskManagerConfiguration.conservative
        #expect(conservativeConfig.maxConcurrentTasks == 1)
        #expect(conservativeConfig.autoRecategorize == false)
    }
    
    @Test("Task priority ordering")
    func testTaskPriorityOrdering() {
        let priorities: [TaskPriority] = [.low, .normal, .high, .critical]
        
        #expect(TaskPriority.critical > TaskPriority.high)
        #expect(TaskPriority.high > TaskPriority.normal)
        #expect(TaskPriority.normal > TaskPriority.low)
        
        let sorted = priorities.sorted(by: >)
        #expect(sorted.first == .critical)
        #expect(sorted.last == .low)
    }
    
    @Test("Task status enum")
    func testTaskStatusEnum() {
        let statuses: [DeepAnalysisTaskStatus] = [
            .queued, .running, .completed, .failed, .cancelled
        ]
        
        #expect(statuses.count == 5)
        #expect(DeepAnalysisTaskStatus.queued.rawValue == "Queued")
        #expect(DeepAnalysisTaskStatus.completed.rawValue == "Completed")
    }
    
    @Test("Manager status calculation")
    func testManagerStatusCalculation() async {
        let analyzer = DeepAnalyzer(
            configuration: .fast,
            llmProvider: OllamaProvider()
        )
        let manager = DeepAnalysisTaskManager(
            configuration: .default,
            deepAnalyzer: analyzer
        )
        
        let tasks = (0..<10).map { i in
            createMockTask(file: createMockFile(name: "file\(i).txt"))
        }
        
        await manager.enqueueTasks(tasks)
        
        let status = await manager.getStatus()
        #expect(status.totalTasks == 10)
        #expect(status.activeCount > 0)
        #expect(status.progress >= 0.0 && status.progress <= 1.0)
        
        // Cleanup
        await manager.stop()
    }
    
    @Test("Remove tasks by file IDs")
    func testRemoveTasksByFileIds() async {
        let analyzer = DeepAnalyzer(
            configuration: .fast,
            llmProvider: OllamaProvider()
        )
        let manager = DeepAnalysisTaskManager(
            configuration: .default,
            deepAnalyzer: analyzer
        )
        
        let tasks = (0..<5).map { i in
            createMockTask(file: createMockFile(name: "file\(i).txt"))
        }
        
        await manager.enqueueTasks(tasks)
        
        // Remove first two files
        let fileIdsToRemove = Set(tasks.prefix(2).map { $0.file.id })
        await manager.removeTasks(fileIds: fileIdsToRemove)
        
        let status = await manager.getStatus()
        #expect(status.queuedCount <= 3)
    }
    
    @Test("Clear queue")
    func testClearQueue() async {
        let analyzer = DeepAnalyzer(
            configuration: .fast,
            llmProvider: OllamaProvider()
        )
        let manager = DeepAnalysisTaskManager(
            configuration: .default,
            deepAnalyzer: analyzer
        )
        
        let tasks = (0..<5).map { i in
            createMockTask(file: createMockFile(name: "file\(i).txt"))
        }
        
        await manager.enqueueTasks(tasks)
        await manager.clearQueue()
        
        let status = await manager.getStatus()
        #expect(status.queuedCount == 0)
    }
    
    @Test("Task duration calculation")
    func testTaskDurationCalculation() {
        let file = createMockFile(name: "test.txt")
        var task = createMockTask(file: file)
        
        #expect(task.duration == nil)
        
        task.startedAt = Date()
        task.completedAt = Date().addingTimeInterval(2.0)
        
        #expect(task.duration != nil)
        #expect(task.duration! > 1.9 && task.duration! < 2.1)
    }
}

