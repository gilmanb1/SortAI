// MARK: - Functional Organization Tests
// End-to-end tests using real-world test files

import Testing
import Foundation
@testable import SortAI

// MARK: - Helper Actor for Progress Counting

actor ProgressCounter {
    private(set) var count: Int = 0
    
    func increment() {
        count += 1
    }
}

@Suite("Functional Organization Tests", .serialized)
struct FunctionalOrganizationTests {
    
    // MARK: - Test Helpers
    
    /// Get path to test fixtures
    static func testFixturesPath() -> URL {
        let currentFile = URL(fileURLWithPath: #filePath)
        let testsDir = currentFile.deletingLastPathComponent().deletingLastPathComponent()
        return testsDir.appendingPathComponent("Fixtures/TestFiles")
    }
    
    /// Get path for test output
    static func testOutputPath() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SortAI_FunctionalTests_\(UUID().uuidString)")
    }
    
    /// Reset test files to flat structure
    static func resetTestFiles() throws {
        let fixturesPath = testFixturesPath()
        let fileManager = FileManager.default
        
        // Get all files recursively
        guard let enumerator = fileManager.enumerator(
            at: fixturesPath,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var filesToMove: [URL] = []
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if resourceValues.isRegularFile == true && fileURL.lastPathComponent != ".gitkeep" {
                // Only process files not in root
                if fileURL.deletingLastPathComponent().path != fixturesPath.path {
                    filesToMove.append(fileURL)
                }
            }
        }
        
        // Move all files back to root (flat structure)
        for fileURL in filesToMove {
            let destURL = fixturesPath.appendingPathComponent(fileURL.lastPathComponent)
            
            // Remove destination if exists
            if fileManager.fileExists(atPath: destURL.path) {
                try? fileManager.removeItem(at: destURL)
            }
            
            try fileManager.moveItem(at: fileURL, to: destURL)
        }
        
        // Remove empty directories
        if let dirEnumerator = fileManager.enumerator(
            at: fixturesPath,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) {
            var dirsToRemove: [URL] = []
            for case let dirURL as URL in dirEnumerator {
                let resourceValues = try dirURL.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true && dirURL.path != fixturesPath.path {
                    dirsToRemove.append(dirURL)
                }
            }
            
            // Remove in reverse order (deepest first)
            for dir in dirsToRemove.reversed() {
                try? fileManager.removeItem(at: dir)
            }
        }
    }
    
    /// Count files in directory
    static func countFiles(in directory: URL) -> Int {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        var count = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
               resourceValues.isRegularFile == true && fileURL.lastPathComponent != ".gitkeep" {
                count += 1
            }
        }
        return count
    }
    
    // MARK: - Tests
    
    @Test("Scan test fixtures directory")
    func testScanFixturesDirectory() async throws {
        let fixturesPath = Self.testFixturesPath()
        
        // Ensure files are in flat structure
        try Self.resetTestFiles()
        
        // Scan the directory (with minimal file size filter for tests)
        let scanner = FilenameScanner(configuration: .init(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".gitignore"],
            excludedDirectories: [],
            minFileSize: 1  // Allow small test files
        ))
        let scanResult = try await scanner.scan(folder: fixturesPath)
        let files = scanResult.files
        
        // Verify we found files (should be ~100)
        #expect(files.count > 50, "Should find at least 50 test files")
        
        // Verify files have proper attributes
        #expect(files.allSatisfy { !$0.filename.isEmpty })
        #expect(files.allSatisfy { $0.fileSize >= 0 })
        
        NSLog("📊 Scanned \(files.count) test files from fixtures")
    }
    
    @Test("Build taxonomy from test files")
    func testBuildTaxonomyFromTestFiles() async throws {
        let fixturesPath = Self.testFixturesPath()
        
        // Reset to flat structure
        try Self.resetTestFiles()
        
        // Scan files (with minimal file size filter for tests)
        let scanner = FilenameScanner(configuration: .init(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".gitignore"],
            excludedDirectories: [],
            minFileSize: 1  // Allow small test files
        ))
        let scanResult = try await scanner.scan(folder: fixturesPath)
        let files = scanResult.files
        
        #expect(files.count > 50)
        
        // Build taxonomy
        let builder = FastTaxonomyBuilder(
            configuration: .init(
                targetCategoryCount: 7,
                separateFileTypes: false,
                autoRefine: false,
                refinementModel: "llama3.2",
                refinementBatchSize: 50
            )
        )
        
        let tree = await builder.buildInstant(from: files, rootName: "TestFiles")
        
        // Verify taxonomy was built
        #expect(tree.categoryCount > 1, "Should create multiple categories")
        #expect(tree.totalFileCount == files.count, "All files should be assigned")
        #expect(tree.maxDepth > 0, "Should have some depth")
        #expect(tree.maxDepth <= 7, "Should respect reasonable depth limits")
        
        NSLog("📊 Built taxonomy: \(tree.categoryCount) categories, depth: \(tree.maxDepth)")
        NSLog("📊 Categories: \(tree.allCategories().map { $0.name }.joined(separator: ", "))")
    }
    
    @Test("Organize test files and validate structure")
    func testOrganizeTestFilesAndValidate() async throws {
        let fixturesPath = Self.testFixturesPath()
        let outputPath = Self.testOutputPath()
        
        defer {
            // Cleanup output
            try? FileManager.default.removeItem(at: outputPath)
            // Reset test files
            try? Self.resetTestFiles()
        }
        
        // Reset to flat structure
        try Self.resetTestFiles()
        
        // Scan files (with minimal file size filter for tests)
        let scanner = FilenameScanner(configuration: .init(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".gitignore"],
            excludedDirectories: [],
            minFileSize: 1  // Allow small test files
        ))
        let scanResult = try await scanner.scan(folder: fixturesPath)
        let files = scanResult.files
        
        #expect(files.count > 50)
        
        // Build taxonomy
        let builder = FastTaxonomyBuilder(
            configuration: .init(
                targetCategoryCount: 7,
                separateFileTypes: false,
                autoRefine: false,
                refinementModel: "llama3.2",
                refinementBatchSize: 50
            )
        )
        
        let tree = await builder.buildInstant(from: files, rootName: "TestFiles")
        let assignments = tree.allAssignments()
        
        // Organize files (use copy mode to preserve source files for other tests)
        let engine = OrganizationEngine(configuration: .init(
            mode: .copy,
            flattenSource: false,
            uncategorizedFolderName: "Uncategorized",
            maxConcurrentOps: 5,
            createLog: true
        ))
        let plan = await engine.planOrganization(
            files: files,
            assignments: assignments,
            tree: tree,
            outputFolder: outputPath
        )
        
        #expect(plan.totalFiles > 0)
        #expect(plan.operations.count > 0)
        
        // Execute organization
        let progressActor = ProgressCounter()
        let result = try await engine.execute(plan: plan) { progress in
            Task { await progressActor.increment() }
        }
        
        // Verify results
        #expect(result.successCount > 0, "Should successfully organize some files")
        #expect(result.totalProcessed == plan.totalFiles)
        
        let progressCount = await progressActor.count
        #expect(progressCount > 0, "Should report progress")
        
        // Verify output structure
        let outputFileCount = Self.countFiles(in: outputPath)
        #expect(outputFileCount > 0, "Should create organized files")
        
        // Verify categories were created
        let categories = try FileManager.default.contentsOfDirectory(at: outputPath, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }
        
        #expect(!categories.isEmpty, "Should create category directories")
        
        NSLog("✅ Organized \(result.successCount) files into \(categories.count) categories")
        NSLog("📂 Categories: \(categories.map { $0.lastPathComponent }.joined(separator: ", "))")
    }
    
    @Test("Test depth enforcement on real files")
    func testDepthEnforcementOnRealFiles() async throws {
        let fixturesPath = Self.testFixturesPath()
        
        // Reset to flat structure
        try Self.resetTestFiles()
        
        // Scan files (with minimal file size filter for tests)
        let scanner = FilenameScanner(configuration: .init(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".gitignore"],
            excludedDirectories: [],
            minFileSize: 1  // Allow small test files
        ))
        let scanResult = try await scanner.scan(folder: fixturesPath)
        let files = scanResult.files
        
        // Build taxonomy
        let builder = FastTaxonomyBuilder(configuration: .default)
        let tree = await builder.buildInstant(from: files, rootName: "TestFiles")
        
        // Test depth enforcement
        let config = TaxonomyDepthConfiguration(
            minDepth: 2,
            maxDepth: 5,
            depthEnforcement: .advisory,
            showDepthWarnings: true
        )
        let enforcer = TaxonomyDepthEnforcer(configuration: config)
        
        let validation = await enforcer.validate(tree)
        
        // Log results
        NSLog("📏 Depth validation: maxDepth=\(validation.currentMaxDepth), violations=\(validation.violations.count), warnings=\(validation.warnings.count)")
        
        // Should generally be valid with default settings
        if !validation.isValid {
            NSLog("⚠️ Depth violations detected (expected with some test data)")
        }
    }
    
    @Test("Test safe organizer with test files")
    func testSafeOrganizerWithTestFiles() async throws {
        let fixturesPath = Self.testFixturesPath()
        let outputPath = Self.testOutputPath()
        
        // Ensure output directory exists
        try FileManager.default.createDirectory(at: outputPath, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: outputPath)
            try? Self.resetTestFiles()
        }
        
        // Reset to flat structure
        try Self.resetTestFiles()
        
        // Scan files (with minimal file size filter for tests)
        let scanner = FilenameScanner(configuration: .init(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".gitignore"],
            excludedDirectories: [],
            minFileSize: 1  // Allow small test files
        ))
        let scanResult = try await scanner.scan(folder: fixturesPath)
        let files = scanResult.files
        
        // Build taxonomy
        let builder = FastTaxonomyBuilder(configuration: .default)
        let tree = await builder.buildInstant(from: files, rootName: "TestFiles")
        
        // Verify we have files and categories
        #expect(files.count > 50, "Should have scanned files")
        #expect(tree.categoryCount > 1, "Should have created categories")
        
        // Setup database and undo stack
        let dbConfig = DatabaseConfiguration(
            path: outputPath.appendingPathComponent("test.db").path,
            inMemory: false,
            enableWAL: true,
            enableForeignKeys: true
        )
        let database = try SortAIDatabase(configuration: dbConfig)
        let undoStack = UndoStack()
        
        // Create safe organizer with default configuration
        let organizer = SafeFileOrganizer(
            configuration: .default,
            database: database,
            undoStack: undoStack
        )
        
        // Create assignments from tree
        let assignments = tree.allAssignments()
        
        // Organize files using SafeFileOrganizer
        let result = try await organizer.organize(
            files: files,
            assignments: assignments,
            tree: tree,
            outputFolder: outputPath,
            mode: .full,
            provider: "test",
            providerVersion: "1.0"
        )
        
        // Verify results
        #expect(result.successCount > 0, "Should successfully organize files")
        #expect(result.successCount + result.failureCount == files.count)
        #expect(result.successRate > 0.5, "Should have reasonable success rate")
        
        // Verify movement log entries
        let logEntries = try database.movementLog.getRecent(limit: 100)
        #expect(!logEntries.isEmpty, "Should create movement log entries")
        #expect(logEntries.count <= result.successCount)
        
        NSLog("✅ Safe organizer: \(result.successCount) successful, \(result.failureCount) failed, \(result.collisionCount) collisions")
    }
    
    @Test("Verify test files reset after organization")
    func testFilesResetAfterOrganization() async throws {
        let fixturesPath = Self.testFixturesPath()
        let outputPath = Self.testOutputPath()
        
        defer {
            try? FileManager.default.removeItem(at: outputPath)
        }
        
        // Get initial file count
        try Self.resetTestFiles()
        let initialCount = Self.countFiles(in: fixturesPath)
        
        // Scan and organize
        let scanner = FilenameScanner()
        let scanResult = try await scanner.scan(folder: fixturesPath)
        let files = scanResult.files
        
        let builder = FastTaxonomyBuilder(configuration: .default)
        let tree = await builder.buildInstant(from: files, rootName: "TestFiles")
        let assignments = tree.allAssignments()
        
        // Use copy mode to preserve source files for other tests
        let engine = OrganizationEngine(configuration: .init(
            mode: .copy,
            flattenSource: false,
            uncategorizedFolderName: "Uncategorized",
            maxConcurrentOps: 5,
            createLog: true
        ))
        let plan = await engine.planOrganization(
            files: files,
            assignments: assignments,
            tree: tree,
            outputFolder: outputPath
        )
        
        _ = try await engine.execute(plan: plan) { _ in }
        
        // Reset files
        try Self.resetTestFiles()
        
        // Verify count matches
        let finalCount = Self.countFiles(in: fixturesPath)
        #expect(finalCount == initialCount, "File count should match after reset")
        
        // Verify flat structure (no subdirectories except hidden)
        let contents = try FileManager.default.contentsOfDirectory(
            at: fixturesPath,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        
        let directories = contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true &&
            !url.lastPathComponent.hasPrefix(".")
        }
        
        #expect(directories.isEmpty, "Should have no subdirectories after reset")
        
        NSLog("✅ Reset verified: \(finalCount) files in flat structure")
    }
    
    @Test("Test expected category detection")
    func testExpectedCategoryDetection() async throws {
        let fixturesPath = Self.testFixturesPath()
        
        try Self.resetTestFiles()
        
        // Scan files (with minimal file size filter for tests)
        let scanner = FilenameScanner(configuration: .init(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".gitignore"],
            excludedDirectories: [],
            minFileSize: 1  // Allow small test files
        ))
        let scanResult = try await scanner.scan(folder: fixturesPath)
        let files = scanResult.files
        
        // Build taxonomy
        let builder = FastTaxonomyBuilder(
            configuration: .init(
                targetCategoryCount: 10,  // More categories for better detection
                separateFileTypes: false,
                autoRefine: false,
                refinementModel: "llama3.2",
                refinementBatchSize: 50
            )
        )
        
        let tree = await builder.buildInstant(from: files, rootName: "TestFiles")
        
        // Expected categories based on our test data
        let expectedKeywords = [
            "photo", "image", "img", "picture",
            "video", "movie", "recording",
            "work", "document", "report", "business",
            "recipe", "food", "meal",
            "travel", "trip", "vacation",
            "financial", "bank", "tax", "investment"
        ]
        
        let categoryNames = tree.allCategories().map { $0.name.lowercased() }
        
        // Check if we detected at least some expected categories
        let detectedExpected = expectedKeywords.filter { keyword in
            categoryNames.contains { $0.contains(keyword) }
        }
        
        #expect(detectedExpected.count > 0, "Should detect some expected categories")
        
        NSLog("📊 Detected expected categories: \(detectedExpected.joined(separator: ", "))")
        NSLog("📊 All categories: \(categoryNames.joined(separator: ", "))")
    }
}

