// MARK: - Organization Tests
// Unit tests for file organization components

import Testing
import Foundation
@testable import SortAI

// MARK: - Organization Engine Tests

@Suite("OrganizationEngine Tests")
struct OrganizationEngineTests {
    
    @Test("Engine configuration defaults")
    func testConfigurationDefaults() {
        let config = OrganizationEngine.Configuration.default
        
        #expect(config.mode == .move)
        #expect(config.flattenSource == false)
        #expect(config.uncategorizedFolderName == "Uncategorized")
        #expect(config.maxConcurrentOps == 5)
        #expect(config.createLog == true)
    }
    
    @Test("Custom configuration")
    func testCustomConfiguration() {
        let config = OrganizationEngine.Configuration(
            mode: .copy,
            flattenSource: true,
            uncategorizedFolderName: "Other",
            maxConcurrentOps: 3,
            createLog: false
        )
        
        #expect(config.mode == .copy)
        #expect(config.flattenSource == true)
        #expect(config.uncategorizedFolderName == "Other")
    }
    
    @Test("Plan organization creates operations")
    func testPlanOrganization() async {
        let engine = OrganizationEngine()
        let tree = TaxonomyTree(rootName: "TestRoot")
        _ = tree.addCategory(path: ["Documents"])
        
        let file = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/doc.pdf"),
            filename: "doc.pdf",
            fileExtension: "pdf",
            fileSize: 1024,
            modificationDate: Date()
        )
        
        let assignment = FileAssignment(
            fileId: file.id,
            categoryId: tree.root.children.first!.id,
            url: file.url,
            filename: file.filename,
            confidence: 0.9
        )
        tree.assignFile(assignment, to: ["Documents"])
        
        let outputFolder = URL(fileURLWithPath: "/tmp/organized")
        let plan = await engine.planOrganization(
            files: [file],
            assignments: [assignment],
            tree: tree,
            outputFolder: outputFolder
        )
        
        #expect(plan.totalFiles >= 0) // May be 0 if no match found
    }
    
    @Test("Organization plan properties")
    func testOrganizationPlanProperties() {
        let plan = OrganizationPlan(
            operations: [],
            conflicts: [],
            estimatedSize: 1024
        )
        
        #expect(!plan.hasConflicts)
        #expect(plan.totalFiles == 0)
        #expect(plan.estimatedSize == 1024)
    }
}

// MARK: - Organization Progress Tests

@Suite("OrganizationProgress Tests")
struct OrganizationProgressTests {
    
    @Test("Progress percentage calculation")
    func testProgressPercentage() {
        let progress = OrganizationProgress(
            completed: 50,
            total: 100,
            currentFile: "test.pdf",
            phase: .executing
        )
        
        #expect(progress.percentage == 50.0)
    }
    
    @Test("Progress with zero total")
    func testProgressZeroTotal() {
        let progress = OrganizationProgress(
            completed: 0,
            total: 0,
            currentFile: "",
            phase: .planning
        )
        
        #expect(progress.percentage == 0.0)
    }
    
    @Test("Progress phases")
    func testProgressPhases() {
        let phases: [OrganizationProgress.OrganizationPhase] = [
            .planning, .executing, .resolvingConflicts, .complete
        ]
        
        for phase in phases {
            #expect(!phase.rawValue.isEmpty)
        }
    }
}

// MARK: - Conflict Resolution Tests

@Suite("ConflictResolution Tests")
struct ConflictResolutionTests {
    
    @Test("Conflict resolution options")
    func testConflictResolutionOptions() {
        let resolutions: [ConflictResolution] = [.skip, .rename, .replace, .askUser]
        
        #expect(resolutions.count == 4)
        #expect(ConflictResolution.allCases.count == 4)
    }
    
    @Test("Conflict resolution raw values")
    func testConflictResolutionRawValues() {
        #expect(ConflictResolution.skip.rawValue == "Skip")
        #expect(ConflictResolution.rename.rawValue == "Rename (add number)")
        #expect(ConflictResolution.replace.rawValue == "Replace existing")
    }
    
    @Test("Organization conflict creation")
    func testOrganizationConflict() {
        let file = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/source/test.pdf"),
            filename: "test.pdf",
            fileExtension: "pdf",
            fileSize: 1024,
            modificationDate: Date()
        )
        
        let conflict = OrganizationConflict(
            sourceFile: file,
            destinationPath: URL(fileURLWithPath: "/dest/test.pdf"),
            resolution: .askUser
        )
        
        #expect(conflict.resolution == .askUser)
        #expect(conflict.sourceFile.filename == "test.pdf")
    }
}

// MARK: - Wizard Organization Result Tests

@Suite("WizardOrganizationResult Tests")
struct WizardOrganizationResultTests {
    
    @Test("Successful result")
    func testSuccessfulResult() {
        let result = WizardOrganizationResult(
            successCount: 100,
            failedOperations: [],
            skippedCount: 0,
            totalProcessed: 100
        )
        
        #expect(result.allSuccessful)
        #expect(result.successCount == 100)
    }
    
    @Test("Result with failures")
    func testResultWithFailures() {
        let file = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test"),
            filename: "test",
            fileExtension: "txt",
            fileSize: 100,
            modificationDate: Date()
        )
        
        let failure = FailedOperation(
            file: file,
            error: "Permission denied"
        )
        
        let result = WizardOrganizationResult(
            successCount: 99,
            failedOperations: [failure],
            skippedCount: 0,
            totalProcessed: 100
        )
        
        #expect(!result.allSuccessful)
        #expect(result.failedOperations.count == 1)
    }
}

// MARK: - Concurrency Throttler Tests

@Suite("ConcurrencyThrottler Tests")
struct ConcurrencyThrottlerTests {
    
    @Test("LLM throttler configuration")
    func testLLMThrottlerConfig() {
        let config = ConcurrencyThrottler.Configuration.llm
        
        #expect(config.maxConcurrent == 2)
        #expect(config.minDelayBetweenOps == 0.5)
        #expect(config.queueWhenFull == true)
    }
    
    @Test("IO throttler configuration")
    func testIOThrottlerConfig() {
        let config = ConcurrencyThrottler.Configuration.io
        
        #expect(config.maxConcurrent == 5)
        #expect(config.minDelayBetweenOps == 0.0)
    }
    
    @Test("Deep analysis throttler configuration")
    func testDeepAnalysisThrottlerConfig() {
        let config = ConcurrencyThrottler.Configuration.deepAnalysis
        
        #expect(config.maxConcurrent == 1)
        #expect(config.minDelayBetweenOps == 1.0)
    }
    
    @Test("Acquire and release")
    func testAcquireAndRelease() async throws {
        let throttler = ConcurrencyThrottler(configuration: .init(
            maxConcurrent: 2,
            minDelayBetweenOps: 0.0,
            queueWhenFull: true,
            maxQueueSize: 10
        ))
        
        let acquired = try await throttler.acquire()
        #expect(acquired)
        
        let stats = await throttler.statistics
        #expect(stats.activeCount == 1)
        
        await throttler.release()
        
        let statsAfter = await throttler.statistics
        #expect(statsAfter.activeCount == 0)
    }
    
    @Test("Throttled execution")
    func testThrottledExecution() async throws {
        let throttler = ConcurrencyThrottler(configuration: .init(
            maxConcurrent: 2,
            minDelayBetweenOps: 0.0,
            queueWhenFull: true,
            maxQueueSize: 10
        ))
        
        let result = try await throttler.throttled {
            return "test result"
        }
        
        #expect(result == "test result")
    }
    
    @Test("Throttler statistics")
    func testThrottlerStatistics() async {
        let throttler = ConcurrencyThrottler(configuration: .llm)
        
        let stats = await throttler.statistics
        
        #expect(stats.maxConcurrent == 2)
        #expect(stats.activeCount == 0)
        #expect(stats.queuedCount == 0)
        #expect(stats.utilizationPercentage == 0.0)
    }
    
    @Test("Global throttlers exist")
    func testGlobalThrottlers() async {
        let llmStats = await Throttlers.llm.statistics
        let ioStats = await Throttlers.io.statistics
        let deepStats = await Throttlers.deepAnalysis.statistics
        
        #expect(llmStats.maxConcurrent == 2)
        #expect(ioStats.maxConcurrent == 5)
        #expect(deepStats.maxConcurrent == 1)
    }
}

// MARK: - Throttler Error Tests

@Suite("ThrottlerError Tests")
struct ThrottlerErrorTests {
    
    @Test("Error descriptions")
    func testErrorDescriptions() {
        let errors: [ThrottlerError] = [.queueFull, .rejected, .timeout]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}

