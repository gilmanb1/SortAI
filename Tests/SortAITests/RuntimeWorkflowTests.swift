// MARK: - Runtime Workflow Tests
// Tests that use actual test files to verify end-to-end workflow

import XCTest
@testable import SortAI

final class RuntimeWorkflowTests: XCTestCase {
    
    // MARK: - Test Directory Discovery
    
    /// Dynamically finds the test files directory relative to the test bundle
    private var testFilesDir: URL {
        // Try to find Tests/Fixtures/TestFiles relative to the project root
        // This works whether running from Xcode or swift test
        let fileManager = FileManager.default
        
        // Option 1: Use Bundle to find the source root
        #if DEBUG
        if let bundlePath = Bundle(for: RuntimeWorkflowTests.self).resourcePath {
            let projectRoot = URL(fileURLWithPath: bundlePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let testDir = projectRoot.appendingPathComponent("Tests/Fixtures/TestFiles")
            if fileManager.fileExists(atPath: testDir.path) {
                return testDir
            }
        }
        #endif
        
        // Option 2: Search from current directory upward
        var currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        for _ in 0..<5 {
            let testDir = currentDir.appendingPathComponent("Tests/Fixtures/TestFiles")
            if fileManager.fileExists(atPath: testDir.path) {
                return testDir
            }
            currentDir = currentDir.deletingLastPathComponent()
        }
        
        // Fallback to relative path (works when running from project root)
        return URL(fileURLWithPath: "Tests/Fixtures/TestFiles")
    }
    
    // MARK: - File Processing Tests
    
    func testProcessingItemCreationFromTestFiles() async throws {
        // Test creating ProcessingItems from various file types
        let testFilesDir = self.testFilesDir
        
        // Test with a few different file types
        let testFiles = [
            "Meeting_Notes_Jan_15_2024.txt",
            "PHOTO_Family_Reunion_2023.jpg",
            "Conference_Keynote_2024.mp4"
        ]
        
        for fileName in testFiles {
            let fileURL = testFilesDir.appendingPathComponent(fileName)
            
            // Only test if file exists
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                continue
            }
            
            await MainActor.run {
                let item = ProcessingItem(url: fileURL)
                
                XCTAssertNotNil(item.id)
                XCTAssertEqual(item.url, fileURL)
                XCTAssertEqual(item.status, .queued)
            }
        }
    }
    
    // MARK: - Category Path Assignment Tests
    
    @MainActor
    func testManualCategoryAssignment() async throws {
        let item = ProcessingItem(url: URL(fileURLWithPath: "/test/document.pdf"))
        
        // Initially no category
        XCTAssertTrue(item.fullCategoryPath.components.isEmpty)
        
        // Assign quick category
        item.quickCategory = "Work"
        XCTAssertEqual(item.fullCategoryPath.components, ["Work"])
        
        // Add subcategory
        item.quickSubcategory = "Reports"
        XCTAssertEqual(item.fullCategoryPath.components, ["Work", "Reports"])
    }
    
    @MainActor
    func testCategoryPathRerootingWorkflow() async throws {
        // Create items with different categories
        let items = [
            createItem(fileName: "report1.pdf", category: "Work", subcategory: "Reports"),
            createItem(fileName: "report2.pdf", category: "Work", subcategory: "Finance"),
            createItem(fileName: "photo.jpg", category: "Personal", subcategory: "Photos")
        ]
        
        // Verify original paths
        XCTAssertEqual(items[0].fullCategoryPath.description, "Work / Reports")
        XCTAssertEqual(items[1].fullCategoryPath.description, "Work / Finance")
        XCTAssertEqual(items[2].fullCategoryPath.description, "Personal / Photos")
        
        // Simulate rerooting work items to Archive
        for item in items where item.fullCategoryPath.root == "Work" {
            let currentPath = item.fullCategoryPath
            let subPath = Array(currentPath.components.dropFirst())
            let newRoot = "Archive"
            
            // Update the item's category
            item.quickCategory = newRoot
            item.quickSubcategory = subPath.first
        }
        
        // Verify rerooted paths
        XCTAssertEqual(items[0].fullCategoryPath.description, "Archive / Reports")
        XCTAssertEqual(items[1].fullCategoryPath.description, "Archive / Finance")
        XCTAssertEqual(items[2].fullCategoryPath.description, "Personal / Photos") // Unchanged
    }
    
    // MARK: - Batch Selection Tests
    
    @MainActor
    func testBatchSelectionByCategory() async throws {
        // Create items with mixed categories
        let items = [
            createItem(fileName: "doc1.txt", category: "Work"),
            createItem(fileName: "doc2.txt", category: "Work"),
            createItem(fileName: "photo1.jpg", category: "Personal"),
            createItem(fileName: "doc3.txt", category: "Work"),
            createItem(fileName: "photo2.jpg", category: "Personal")
        ]
        
        // Select all Work items
        var selectedIds: Set<UUID> = []
        for item in items where item.fullCategoryPath.root == "Work" {
            selectedIds.insert(item.id)
        }
        
        XCTAssertEqual(selectedIds.count, 3)
        
        // Get selected items
        let selectedItems = items.filter { selectedIds.contains($0.id) }
        
        // All selected should be Work category
        for item in selectedItems {
            XCTAssertEqual(item.fullCategoryPath.root, "Work")
        }
    }
    
    // MARK: - File Router Tests with Test Files
    
    func testFileRouterWithTestFiles() async throws {
        let router = FileRouter()
        
        // Test routing for different file types
        let testCases: [(fileName: String, expectedKind: MediaKind)] = [
            ("Meeting_Notes_Jan_15_2024.txt", .document),
            ("PHOTO_Family_Reunion_2023.jpg", .image),
            ("Conference_Keynote_2024.mp4", .video)
        ]
        
        let testFilesDir = self.testFilesDir
        
        for testCase in testCases {
            let fileURL = testFilesDir.appendingPathComponent(testCase.fileName)
            
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                continue
            }
            
            let kind = await router.mediaKind(for: fileURL)
            XCTAssertEqual(kind, testCase.expectedKind, "File \(testCase.fileName) should be \(testCase.expectedKind)")
        }
    }
    
    // MARK: - Magic Folder Tests
    
    func testMagicFolderFileTypes() async throws {
        // Use environment variable or default to ~/Desktop/Magic
        // This test is optional and skips if the folder doesn't exist
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let magicDir = ProcessInfo.processInfo.environment["SORTAI_TEST_MAGIC_DIR"]
            .map { URL(fileURLWithPath: $0) }
            ?? homeDir.appendingPathComponent("Desktop/Magic")
        let router = FileRouter()
        
        guard FileManager.default.fileExists(atPath: magicDir.path) else {
            throw XCTSkip("Magic folder not available (set SORTAI_TEST_MAGIC_DIR env var)")
        }
        
        // Test a subset of files from Magic folder
        let testFiles = [
            "52_wonders.pdf",  // PDF
            "ace1.png",       // Image
            "panic.mp4"       // Video
        ]
        
        for fileName in testFiles {
            let fileURL = magicDir.appendingPathComponent(fileName)
            
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                continue
            }
            
            let kind = await router.mediaKind(for: fileURL)
            XCTAssertNotEqual(kind, .unknown, "File \(fileName) should be recognized")
        }
    }
    
    // MARK: - Status Transition Tests
    
    @MainActor
    func testProcessingItemStatusTransitions() async throws {
        let item = ProcessingItem(url: URL(fileURLWithPath: "/test/file.txt"))
        
        // Initial state
        XCTAssertEqual(item.status, .queued)
        
        // Transition to inspecting
        item.status = .inspecting
        XCTAssertEqual(item.status, .inspecting)
        
        // Transition to categorizing
        item.status = .categorizing
        XCTAssertEqual(item.status, .categorizing)
        
        // Transition to reviewing (needs human input)
        item.status = .reviewing
        XCTAssertEqual(item.status, .reviewing)
        
        // Transition to accepted
        item.status = .accepted
        XCTAssertEqual(item.status, .accepted)
        
        // Transition to organizing
        item.status = .organizing
        XCTAssertEqual(item.status, .organizing)
        
        // Transition to completed
        item.status = .completed
        XCTAssertEqual(item.status, .completed)
    }
    
    @MainActor
    func testProcessingItemErrorState() async throws {
        let item = ProcessingItem(url: URL(fileURLWithPath: "/nonexistent/file.xyz"))
        
        // Simulate error with message
        item.status = .failed("File not found")
        
        if case .failed(let errorMessage) = item.status {
            XCTAssertEqual(errorMessage, "File not found")
        } else {
            XCTFail("Expected failed status")
        }
    }
    
    // MARK: - Helpers
    
    @MainActor
    private func createItem(fileName: String, category: String, subcategory: String? = nil) -> ProcessingItem {
        let item = ProcessingItem(url: URL(fileURLWithPath: "/test/\(fileName)"))
        item.quickCategory = category
        item.quickSubcategory = subcategory
        return item
    }
}

// MARK: - Performance Tests

final class PerformanceTests: XCTestCase {
    
    @MainActor
    func testBulkSelectionPerformance() async throws {
        // Create 50 items (typical batch size)
        var items: [ProcessingItem] = []
        for i in 0..<50 {
            let item = ProcessingItem(url: URL(fileURLWithPath: "/test/file\(i).txt"))
            item.quickCategory = ["Work", "Personal", "Archive"][i % 3]
            items.append(item)
        }
        
        // Measure selection performance
        measure {
            var selectedIds: Set<UUID> = []
            
            // Select all
            selectedIds = Set(items.map { $0.id })
            XCTAssertEqual(selectedIds.count, 50)
            
            // Clear all
            selectedIds.removeAll()
            XCTAssertEqual(selectedIds.count, 0)
            
            // Select by category
            for item in items where item.fullCategoryPath.root == "Work" {
                selectedIds.insert(item.id)
            }
            // Approximately 17 items (50/3 rounded)
            XCTAssertGreaterThan(selectedIds.count, 15)
        }
    }
    
    func testCategoryPathCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                let _ = CategoryPath(components: ["Level1", "Level2", "Level3", "Level4", "Level5"])
            }
        }
    }
    
    func testCategoryPathDescriptionPerformance() {
        let paths = (0..<1000).map { i in
            CategoryPath(components: ["Category\(i)", "Sub\(i)", "Detail\(i)"])
        }
        
        measure {
            for path in paths {
                let _ = path.description
            }
        }
    }
}

