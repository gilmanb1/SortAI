// MARK: - Category Browser Tests
// Tests for category retrieval and the CategoryBrowserView functionality

import XCTest
@testable import SortAI

final class CategoryBrowserTests: XCTestCase {
    
    // MARK: - CategoryPath Tests
    
    func testCategoryPathParsing() {
        // Test parsing from slash-separated string
        let path = CategoryPath(path: "Work / Projects / Active")
        XCTAssertEqual(path.components, ["Work", "Projects", "Active"])
        XCTAssertEqual(path.root, "Work")
        XCTAssertEqual(path.description, "Work / Projects / Active")
    }
    
    func testCategoryPathParsingWithExtraSpaces() {
        // Should handle extra spaces gracefully
        let path = CategoryPath(path: "  Work  /  Projects  ")
        XCTAssertEqual(path.components, ["Work", "Projects"])
    }
    
    func testCategoryPathSingleComponent() {
        let path = CategoryPath(path: "Documents")
        XCTAssertEqual(path.components, ["Documents"])
        XCTAssertEqual(path.root, "Documents")
    }
    
    func testCategoryPathEmpty() {
        let path = CategoryPath(path: "")
        XCTAssertTrue(path.components.isEmpty || path.components == [""])
    }
    
    func testCategoryPathEquality() {
        let path1 = CategoryPath(components: ["A", "B", "C"])
        let path2 = CategoryPath(components: ["A", "B", "C"])
        let path3 = CategoryPath(components: ["A", "B"])
        
        XCTAssertEqual(path1, path2)
        XCTAssertNotEqual(path1, path3)
    }
    
    // MARK: - SortAIPipeline Category Tests
    
    func testMockCategorizerGetExistingCategoriesReturnsEmptyWhenNoCategories() async throws {
        // Create a mock categorizer (implements FileCategorizing)
        let mockCategorizer = MockCategorizer()
        
        // A fresh mock should return empty categories
        let categories = await mockCategorizer.getExistingCategories(limit: 50)
        XCTAssertEqual(categories.count, 0)
    }
    
    func testMockCategorizerGetExistingCategories() async {
        let mockCategorizer = MockCategorizer()
        
        // Add some existing categories to the mock
        await mockCategorizer.setExistingCategories([
            CategoryPath(components: ["Work", "Documents"]),
            CategoryPath(components: ["Personal", "Photos"]),
            CategoryPath(components: ["Media", "Videos"])
        ])
        
        let categories = await mockCategorizer.getExistingCategories(limit: 50)
        XCTAssertEqual(categories.count, 3)
        XCTAssertTrue(categories.contains(CategoryPath(components: ["Work", "Documents"])))
    }
    
    func testMockCategorizerGetExistingCategoriesRespectLimit() async {
        let mockCategorizer = MockCategorizer()
        
        // Add many categories
        let manyCategories = (1...100).map {
            CategoryPath(components: ["Category\($0)"])
        }
        await mockCategorizer.setExistingCategories(manyCategories)
        
        let limitedCategories = await mockCategorizer.getExistingCategories(limit: 10)
        XCTAssertEqual(limitedCategories.count, 10)
    }
    
    // MARK: - FeedbackDisplayItem Tests
    
    func testFeedbackDisplayItemCreation() {
        let item = FeedbackDisplayItem(
            id: 1,
            fileName: "test.pdf",
            filePath: "/path/to/test.pdf",
            fileIcon: "doc.fill",
            categoryPath: CategoryPath(components: ["Documents", "Work"]),
            confidence: 0.85,
            rationale: "Contains work-related content",
            keywords: ["report", "quarterly", "budget"],
            status: .pending
        )
        
        XCTAssertEqual(item.fileName, "test.pdf")
        XCTAssertEqual(item.categoryPath.root, "Documents")
        XCTAssertEqual(item.confidence, 0.85)
        XCTAssertTrue(item.needsReview)
    }
    
    func testFeedbackDisplayItemNeedsReview() {
        var item = FeedbackDisplayItem(
            id: 1,
            fileName: "test.pdf",
            filePath: "/path/to/test.pdf",
            fileIcon: "doc.fill",
            categoryPath: CategoryPath(components: ["Documents"]),
            confidence: 0.5,
            rationale: "Low confidence",
            keywords: [],
            status: .pending
        )
        
        XCTAssertTrue(item.needsReview)
        
        item.status = .humanAccepted
        XCTAssertFalse(item.needsReview)
        
        item.status = .humanCorrected
        XCTAssertFalse(item.needsReview)
    }
    
    // MARK: - Category Filtering Tests
    
    func testFilterCategoriesForRootOnly() {
        let categories = [
            CategoryPath(components: ["Work"]),
            CategoryPath(components: ["Work", "Projects"]),
            CategoryPath(components: ["Personal"]),
            CategoryPath(components: ["Personal", "Photos", "2024"]),
            CategoryPath(components: ["Media"])
        ]
        
        let rootOnly = categories.filter { $0.components.count == 1 }
        XCTAssertEqual(rootOnly.count, 3)
        XCTAssertTrue(rootOnly.contains(CategoryPath(components: ["Work"])))
        XCTAssertTrue(rootOnly.contains(CategoryPath(components: ["Personal"])))
        XCTAssertTrue(rootOnly.contains(CategoryPath(components: ["Media"])))
    }
    
    func testSearchFilterCategories() {
        let categories = [
            CategoryPath(components: ["Work", "Documents"]),
            CategoryPath(components: ["Work", "Projects"]),
            CategoryPath(components: ["Personal", "Photos"]),
            CategoryPath(components: ["Media", "Videos"])
        ]
        
        let searchText = "work"
        let filtered = categories.filter {
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
        
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.root == "Work" })
    }
    
    func testSearchFilterCategoriesNoMatch() {
        let categories = [
            CategoryPath(components: ["Work", "Documents"]),
            CategoryPath(components: ["Personal", "Photos"])
        ]
        
        let searchText = "nonexistent"
        let filtered = categories.filter {
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
        
        XCTAssertEqual(filtered.count, 0)
    }
    
    // MARK: - AppState Category Tests
    
    @MainActor
    func testAppStateGetExistingCategoriesReturnsEmptyWhenNotInitialized() async {
        let appState = AppState()
        
        // Before pipeline initialization, should return empty
        let categories = await appState.getExistingCategories()
        XCTAssertEqual(categories.count, 0)
    }
}

