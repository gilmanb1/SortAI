// MARK: - Selection and Bulk Edit Tests
// Tests for multi-selection and bulk category editing functionality

import XCTest
@testable import SortAI

final class SelectionAndBulkEditTests: XCTestCase {
    
    // MARK: - Helper Methods
    
    /// Creates a ProcessingItem with the given category path
    @MainActor
    private func createTestItem(
        fileName: String,
        category: String,
        subcategory: String? = nil
    ) -> ProcessingItem {
        let url = URL(fileURLWithPath: "/test/\(fileName)")
        let item = ProcessingItem(url: url)
        item.quickCategory = category
        item.quickSubcategory = subcategory
        return item
    }
    
    // MARK: - Selection State Tests
    
    @MainActor
    func testInitialSelectionState() async {
        // Create a mock AppState for testing
        let items: [ProcessingItem] = [
            createTestItem(fileName: "file1.txt", category: "Work"),
            createTestItem(fileName: "file2.txt", category: "Personal"),
            createTestItem(fileName: "file3.txt", category: "Archive")
        ]
        
        // Verify initial state
        var selectedIds: Set<UUID> = []
        XCTAssertTrue(selectedIds.isEmpty)
        
        // Select one item
        selectedIds.insert(items[0].id)
        XCTAssertEqual(selectedIds.count, 1)
        XCTAssertTrue(selectedIds.contains(items[0].id))
    }
    
    @MainActor
    func testToggleSelection() async {
        let items: [ProcessingItem] = [
            createTestItem(fileName: "file1.txt", category: "Work"),
            createTestItem(fileName: "file2.txt", category: "Personal")
        ]
        
        var selectedIds: Set<UUID> = []
        
        // Toggle on
        if selectedIds.contains(items[0].id) {
            selectedIds.remove(items[0].id)
        } else {
            selectedIds.insert(items[0].id)
        }
        XCTAssertTrue(selectedIds.contains(items[0].id))
        
        // Toggle off
        if selectedIds.contains(items[0].id) {
            selectedIds.remove(items[0].id)
        } else {
            selectedIds.insert(items[0].id)
        }
        XCTAssertFalse(selectedIds.contains(items[0].id))
    }
    
    @MainActor
    func testSelectAll() async {
        let items: [ProcessingItem] = [
            createTestItem(fileName: "file1.txt", category: "Work"),
            createTestItem(fileName: "file2.txt", category: "Personal"),
            createTestItem(fileName: "file3.txt", category: "Archive")
        ]
        
        var selectedIds: Set<UUID> = []
        
        // Select all
        selectedIds = Set(items.map { $0.id })
        
        XCTAssertEqual(selectedIds.count, 3)
        for item in items {
            XCTAssertTrue(selectedIds.contains(item.id))
        }
    }
    
    @MainActor
    func testClearSelection() async {
        let items: [ProcessingItem] = [
            createTestItem(fileName: "file1.txt", category: "Work"),
            createTestItem(fileName: "file2.txt", category: "Personal")
        ]
        
        var selectedIds: Set<UUID> = Set(items.map { $0.id })
        XCTAssertEqual(selectedIds.count, 2)
        
        // Clear
        selectedIds.removeAll()
        XCTAssertTrue(selectedIds.isEmpty)
    }
    
    // MARK: - Range Selection Tests
    
    @MainActor
    func testShiftClickRangeSelection() async {
        let items: [ProcessingItem] = [
            createTestItem(fileName: "file1.txt", category: "Work"),
            createTestItem(fileName: "file2.txt", category: "Personal"),
            createTestItem(fileName: "file3.txt", category: "Archive"),
            createTestItem(fileName: "file4.txt", category: "Media"),
            createTestItem(fileName: "file5.txt", category: "Documents")
        ]
        
        var selectedIds: Set<UUID> = []
        var lastSelectedId: UUID? = nil
        
        // Click on item 1 (index 0)
        selectedIds = [items[0].id]
        lastSelectedId = items[0].id
        
        // Shift-click on item 4 (index 3)
        let currentIndex = 3
        if let lastId = lastSelectedId,
           let lastIndex = items.firstIndex(where: { $0.id == lastId }) {
            let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
            for i in range {
                selectedIds.insert(items[i].id)
            }
        }
        
        // Should select items 0, 1, 2, 3
        XCTAssertEqual(selectedIds.count, 4)
        XCTAssertTrue(selectedIds.contains(items[0].id))
        XCTAssertTrue(selectedIds.contains(items[1].id))
        XCTAssertTrue(selectedIds.contains(items[2].id))
        XCTAssertTrue(selectedIds.contains(items[3].id))
        XCTAssertFalse(selectedIds.contains(items[4].id))
    }
    
    @MainActor
    func testCommandClickAddsToSelection() async {
        let items: [ProcessingItem] = [
            createTestItem(fileName: "file1.txt", category: "Work"),
            createTestItem(fileName: "file2.txt", category: "Personal"),
            createTestItem(fileName: "file3.txt", category: "Archive")
        ]
        
        var selectedIds: Set<UUID> = []
        
        // Select item 0
        selectedIds.insert(items[0].id)
        
        // Cmd-click item 2
        if selectedIds.contains(items[2].id) {
            selectedIds.remove(items[2].id)
        } else {
            selectedIds.insert(items[2].id)
        }
        
        // Items 0 and 2 should be selected (not 1)
        XCTAssertEqual(selectedIds.count, 2)
        XCTAssertTrue(selectedIds.contains(items[0].id))
        XCTAssertFalse(selectedIds.contains(items[1].id))
        XCTAssertTrue(selectedIds.contains(items[2].id))
    }
    
    // MARK: - Reroot Tests
    
    @MainActor
    func testRerootPreservesSubcategories() async {
        let item = createTestItem(fileName: "project.txt", category: "Work", subcategory: "Projects")
        
        // Original path: Work / Projects
        XCTAssertEqual(item.fullCategoryPath.components, ["Work", "Projects"])
        
        // Reroot to "Personal"
        let currentPath = item.fullCategoryPath
        let subPath = Array(currentPath.components.dropFirst())
        let newPath = CategoryPath(components: ["Personal"] + subPath)
        
        // New path should be: Personal / Projects
        XCTAssertEqual(newPath.components, ["Personal", "Projects"])
        XCTAssertEqual(newPath.root, "Personal")
        XCTAssertEqual(newPath.leaf, "Projects")
    }
    
    @MainActor
    func testRerootSingleComponentPath() async {
        let item = createTestItem(fileName: "misc.txt", category: "Uncategorized")
        
        // Original path: Uncategorized
        XCTAssertEqual(item.fullCategoryPath.components, ["Uncategorized"])
        
        // Reroot to "Archive"
        let currentPath = item.fullCategoryPath
        let subPath = Array(currentPath.components.dropFirst())
        let newPath = CategoryPath(components: ["Archive"] + subPath)
        
        // New path should be: Archive (no subcategories)
        XCTAssertEqual(newPath.components, ["Archive"])
    }
    
    @MainActor
    func testRerootDeepPath() async {
        // Create item with deep path
        let item = ProcessingItem(url: URL(fileURLWithPath: "/test/deep.txt"))
        let brainResult = BrainResult(
            category: "Tech",
            subcategory: "Programming",
            confidence: 0.95,
            rationale: "Test"
        )
        item.result = ProcessingResult(
            signature: FileSignature(
                url: URL(fileURLWithPath: "/test/deep.txt"),
                kind: .document,
                title: "Deep Test",
                fileExtension: "txt",
                fileSizeBytes: 100,
                checksum: "abc"
            ),
            brainResult: brainResult,
            wasFromMemory: false
        )
        
        // Build the path manually for this test
        let currentPath = CategoryPath(components: ["Tech", "Programming"])
        let subPath = Array(currentPath.components.dropFirst())
        let newPath = CategoryPath(components: ["Education"] + subPath)
        
        // New path should be: Education / Programming
        XCTAssertEqual(newPath.components, ["Education", "Programming"])
        XCTAssertEqual(newPath.root, "Education")
    }
    
    // MARK: - Selected Root Categories Tests
    
    @MainActor
    func testSelectedRootCategoriesCount() async {
        let items: [ProcessingItem] = [
            createTestItem(fileName: "file1.txt", category: "Work"),
            createTestItem(fileName: "file2.txt", category: "Work"),
            createTestItem(fileName: "file3.txt", category: "Personal"),
            createTestItem(fileName: "file4.txt", category: "Work"),
            createTestItem(fileName: "file5.txt", category: "Archive")
        ]
        
        let selectedIds: Set<UUID> = Set(items.map { $0.id })
        let selectedItems = items.filter { selectedIds.contains($0.id) }
        
        // Count root categories
        var counts: [String: Int] = [:]
        for item in selectedItems {
            let root = item.fullCategoryPath.root
            if !root.isEmpty {
                counts[root, default: 0] += 1
            }
        }
        
        XCTAssertEqual(counts["Work"], 3)
        XCTAssertEqual(counts["Personal"], 1)
        XCTAssertEqual(counts["Archive"], 1)
    }
}

// MARK: - Integration Tests

final class BulkEditIntegrationTests: XCTestCase {
    
    @MainActor
    func testBulkEditWorkflow() async {
        // Test the complete workflow of selecting items and rerooting them
        
        // 1. Create items with various categories
        let items: [ProcessingItem] = [
            createTestItem(fileName: "report.pdf", category: "Work", subcategory: "Reports"),
            createTestItem(fileName: "proposal.docx", category: "Work", subcategory: "Proposals"),
            createTestItem(fileName: "photo.jpg", category: "Personal", subcategory: "Photos")
        ]
        
        // 2. Select work items
        var selectedIds: Set<UUID> = []
        selectedIds.insert(items[0].id)
        selectedIds.insert(items[1].id)
        
        XCTAssertEqual(selectedIds.count, 2)
        
        // 3. Get selected items
        let selectedItems = items.filter { selectedIds.contains($0.id) }
        
        // 4. Verify all selected items are from "Work"
        let rootCategories = Set(selectedItems.map { $0.fullCategoryPath.root })
        XCTAssertEqual(rootCategories, ["Work"])
        
        // 5. Compute new paths (reroot to "Archive")
        var newPaths: [UUID: CategoryPath] = [:]
        for item in selectedItems {
            let currentPath = item.fullCategoryPath
            let subPath = Array(currentPath.components.dropFirst())
            let newPath = CategoryPath(components: ["Archive"] + subPath)
            newPaths[item.id] = newPath
        }
        
        // 6. Verify new paths preserve subcategories
        XCTAssertEqual(newPaths[items[0].id]?.components, ["Archive", "Reports"])
        XCTAssertEqual(newPaths[items[1].id]?.components, ["Archive", "Proposals"])
    }
    
    @MainActor
    private func createTestItem(
        fileName: String,
        category: String,
        subcategory: String? = nil
    ) -> ProcessingItem {
        let url = URL(fileURLWithPath: "/test/\(fileName)")
        let item = ProcessingItem(url: url)
        item.quickCategory = category
        item.quickSubcategory = subcategory
        return item
    }
}

