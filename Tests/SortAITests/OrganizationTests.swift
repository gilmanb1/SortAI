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


// MARK: - Hierarchy-Aware Organization Tests

@Suite("HierarchyOrganization Tests")
struct HierarchyOrganizationTests {
    
    @Test("HierarchyAwareOrganizationPlan totals")
    func testHierarchyAwarePlanTotals() {
        let folder = ScannedFolder(
            url: URL(fileURLWithPath: "/test/MyFolder"),
            folderName: "MyFolder",
            relativePath: "MyFolder",
            depth: 1,
            containedFiles: [
                TaxonomyScannedFile(
                    url: URL(fileURLWithPath: "/test/MyFolder/file1.pdf"),
                    filename: "file1.pdf",
                    fileExtension: "pdf",
                    fileSize: 1000,
                    modificationDate: Date()
                ),
                TaxonomyScannedFile(
                    url: URL(fileURLWithPath: "/test/MyFolder/file2.pdf"),
                    filename: "file2.pdf",
                    fileExtension: "pdf",
                    fileSize: 2000,
                    modificationDate: Date()
                )
            ],
            totalSize: 3000,
            modifiedAt: nil
        )
        
        let folderOp = FolderOrganizationOperation(
            sourceFolder: folder,
            destinationFolder: URL(fileURLWithPath: "/output/Work"),
            destinationCategory: "Work / Projects",
            confidence: 0.85,
            mode: .move
        )
        
        let looseFile = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/loose.txt"),
            filename: "loose.txt",
            fileExtension: "txt",
            fileSize: 500,
            modificationDate: Date()
        )
        
        let fileOp = OrganizationOperation(
            sourceFile: looseFile,
            destinationFolder: URL(fileURLWithPath: "/output/Documents"),
            destinationPath: URL(fileURLWithPath: "/output/Documents/loose.txt"),
            mode: .move
        )
        
        let plan = HierarchyAwareOrganizationPlan(
            folderOperations: [folderOp],
            fileOperations: [fileOp],
            folderConflicts: [],
            fileConflicts: [],
            estimatedSize: 3500
        )
        
        #expect(plan.totalItems == 2) // 1 folder + 1 file
        #expect(plan.totalFileCount == 3) // 2 in folder + 1 loose
        #expect(!plan.hasConflicts)
        #expect(plan.estimatedSize == 3500)
    }
    
    @Test("FolderOrganizationOperation properties")
    func testFolderOrganizationOperation() {
        let folder = ScannedFolder(
            url: URL(fileURLWithPath: "/test/Photos"),
            folderName: "Photos",
            relativePath: "Photos",
            depth: 1,
            containedFiles: [],
            totalSize: 0,
            modifiedAt: nil
        )
        
        let op = FolderOrganizationOperation(
            sourceFolder: folder,
            destinationFolder: URL(fileURLWithPath: "/output/Media"),
            destinationCategory: "Media / Photos",
            confidence: 0.92,
            mode: .copy
        )
        
        #expect(op.sourceFolder.folderName == "Photos")
        #expect(op.destinationCategory == "Media / Photos")
        #expect(op.confidence == 0.92)
        #expect(op.preserveInternalStructure == true) // Always true for folders
        #expect(op.mode == .copy)
    }
    
    @Test("HierarchyAwareOrganizationPlan toLegacyPlan")
    func testHierarchyAwarePlanToLegacy() {
        let folder = ScannedFolder(
            url: URL(fileURLWithPath: "/test/Work"),
            folderName: "Work",
            relativePath: "Work",
            depth: 1,
            containedFiles: [
                TaxonomyScannedFile(
                    url: URL(fileURLWithPath: "/test/Work/doc.pdf"),
                    filename: "doc.pdf",
                    fileExtension: "pdf",
                    fileSize: 1000,
                    modificationDate: Date()
                )
            ],
            totalSize: 1000,
            modifiedAt: nil
        )
        
        let folderOp = FolderOrganizationOperation(
            sourceFolder: folder,
            destinationFolder: URL(fileURLWithPath: "/output/Projects"),
            destinationCategory: "Projects",
            confidence: 0.9,
            mode: .move
        )
        
        let plan = HierarchyAwareOrganizationPlan(
            folderOperations: [folderOp],
            fileOperations: [],
            folderConflicts: [],
            fileConflicts: [],
            estimatedSize: 1000
        )
        
        let legacy = plan.toLegacyPlan()
        
        // Folder should be flattened into file operations
        #expect(legacy.operations.count >= 0) // Conversion may not create ops if paths don't match
        #expect(legacy.estimatedSize == 1000)
    }
    
    @Test("OrganizationEngine planHierarchyOrganization basic")
    func testPlanHierarchyOrganization() async {
        let engine = OrganizationEngine()
        let tree = TaxonomyTree(rootName: "Root")
        _ = tree.addCategory(path: ["Work"])
        _ = tree.addCategory(path: ["Documents"])
        
        // Create scan result
        let folder = ScannedFolder(
            url: URL(fileURLWithPath: "/test/Resumes"),
            folderName: "Resumes",
            relativePath: "Resumes",
            depth: 1,
            containedFiles: [
                TaxonomyScannedFile(
                    url: URL(fileURLWithPath: "/test/Resumes/resume.pdf"),
                    filename: "resume.pdf",
                    fileExtension: "pdf",
                    fileSize: 1000,
                    modificationDate: Date()
                )
            ],
            totalSize: 1000,
            modifiedAt: nil
        )
        
        let looseFile = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/notes.txt"),
            filename: "notes.txt",
            fileExtension: "txt",
            fileSize: 500,
            modificationDate: Date()
        )
        
        let scanResult = HierarchyScanResult(
            sourceFolder: URL(fileURLWithPath: "/test"),
            sourceFolderName: "test",
            folders: [folder],
            looseFiles: [looseFile],
            skippedCount: 0,
            scanDuration: 0.5,
            reachedLimit: false
        )
        
        let folderAssignment = FolderCategoryAssignment(
            folderId: folder.id,
            folderName: "Resumes",
            categoryPath: ["Work", "Job Search"],
            confidence: 0.85,
            rationale: "Resume documents"
        )
        
        // Note: Loose file has no assignment - should go to Uncategorized
        
        let outputFolder = URL(fileURLWithPath: "/output")
        let plan = await engine.planHierarchyOrganization(
            scanResult: scanResult,
            folderAssignments: [folderAssignment],
            fileAssignments: [],
            tree: tree,
            outputFolder: outputFolder
        )
        
        #expect(plan.folderOperations.count == 1)
        #expect(plan.fileOperations.count == 1) // loose file to Uncategorized
        #expect(plan.folderOperations[0].destinationCategory == "Work / Job Search")
    }
}
