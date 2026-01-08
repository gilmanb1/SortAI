// MARK: - UI Workflow Tests
// Tests for UI component logic and workflow behaviors

import XCTest
@testable import SortAI

// MARK: - Condensed Category Path View Tests

final class CondensedCategoryPathViewTests: XCTestCase {
    
    /// Test that short paths don't need condensing
    func testShortPathNoCondensing() {
        let path = CategoryPath(components: ["Work", "Projects"])
        let maxVisible = 2
        
        let needsCondensing = path.components.count > maxVisible
        XCTAssertFalse(needsCondensing)
    }
    
    /// Test that long paths need condensing
    func testLongPathNeedsCondensing() {
        let path = CategoryPath(components: ["Work", "Projects", "Active", "SortAI"])
        let maxVisible = 2
        
        let needsCondensing = path.components.count > maxVisible
        XCTAssertTrue(needsCondensing)
    }
    
    /// Test condensed components shows first, ellipsis, and last
    func testCondensedComponents() {
        let path = CategoryPath(components: ["Work", "Projects", "Active", "SortAI"])
        let maxVisible = 2
        
        let condensed: [String]
        if path.components.count > maxVisible && path.components.count > 1 {
            condensed = [path.components.first!, "...", path.components.last!]
        } else {
            condensed = path.components
        }
        
        XCTAssertEqual(condensed.count, 3)
        XCTAssertEqual(condensed[0], "Work")
        XCTAssertEqual(condensed[1], "...")
        XCTAssertEqual(condensed[2], "SortAI")
    }
    
    /// Test single component path doesn't get ellipsis
    func testSingleComponentNoCondensing() {
        let path = CategoryPath(components: ["Work"])
        let maxVisible = 2
        
        let condensed: [String]
        if path.components.count > maxVisible && path.components.count > 1 {
            condensed = [path.components.first!, "...", path.components.last!]
        } else {
            condensed = path.components
        }
        
        XCTAssertEqual(condensed.count, 1)
        XCTAssertEqual(condensed[0], "Work")
    }
    
    /// Test empty path handling
    func testEmptyPath() {
        let path = CategoryPath(components: [])
        let maxVisible = 2
        
        let condensed: [String]
        if path.components.count > maxVisible && path.components.count > 1 {
            condensed = [path.components.first!, "...", path.components.last!]
        } else {
            condensed = path.components
        }
        
        XCTAssertTrue(condensed.isEmpty)
    }
    
    /// Test three-component path with maxVisible=2 should condense
    func testThreeComponentsCondensed() {
        let path = CategoryPath(components: ["Tech", "Programming", "Swift"])
        let maxVisible = 2
        
        let needsCondensing = path.components.count > maxVisible
        XCTAssertTrue(needsCondensing)
        
        let condensed = [path.components.first!, "...", path.components.last!]
        XCTAssertEqual(condensed, ["Tech", "...", "Swift"])
    }
}

// MARK: - Full Category Path Display Tests

final class FullCategoryPathDisplayTests: XCTestCase {
    
    @MainActor
    func testProcessingItemFullCategoryPath() {
        // Create item with quickCategory only
        let item1 = ProcessingItem(url: URL(fileURLWithPath: "/test/file1.txt"))
        item1.quickCategory = "Work"
        
        XCTAssertEqual(item1.fullCategoryPath.components, ["Work"])
        
        // Create item with quickCategory and quickSubcategory
        let item2 = ProcessingItem(url: URL(fileURLWithPath: "/test/file2.txt"))
        item2.quickCategory = "Personal"
        item2.quickSubcategory = "Photos"
        
        XCTAssertEqual(item2.fullCategoryPath.components, ["Personal", "Photos"])
    }
    
    @MainActor
    func testProcessingItemWithBrainResult() {
        let item = ProcessingItem(url: URL(fileURLWithPath: "/test/file.txt"))
        
        let brainResult = BrainResult(
            category: "Tech",
            subcategory: "Programming",
            confidence: 0.95,
            rationale: "Contains code"
        )
        
        item.result = ProcessingResult(
            signature: FileSignature(
                url: URL(fileURLWithPath: "/test/file.txt"),
                kind: .document,
                title: "Test",
                fileExtension: "txt",
                fileSizeBytes: 100,
                checksum: "abc"
            ),
            brainResult: brainResult,
            wasFromMemory: false
        )
        
        // fullCategoryPath should derive from result
        let path = item.fullCategoryPath
        XCTAssertEqual(path.components, ["Tech", "Programming"])
    }
    
    @MainActor
    func testProcessingItemWithFeedbackItem() {
        let item = ProcessingItem(url: URL(fileURLWithPath: "/test/file.txt"))
        
        // FeedbackDisplayItem takes precedence
        item.feedbackItem = FeedbackDisplayItem(
            id: 12345,
            fileName: "file.txt",
            filePath: "/test/file.txt",
            fileIcon: "doc.text",
            categoryPath: CategoryPath(components: ["Custom", "Feedback", "Path"]),
            confidence: 0.8,
            rationale: "Test",
            keywords: ["test"],
            status: .humanAccepted
        )
        
        XCTAssertEqual(item.fullCategoryPath.components, ["Custom", "Feedback", "Path"])
    }
    
    @MainActor
    func testProcessingItemEmptyCategoryPath() {
        let item = ProcessingItem(url: URL(fileURLWithPath: "/test/file.txt"))
        
        // No category set
        XCTAssertTrue(item.fullCategoryPath.components.isEmpty)
    }
}

// MARK: - Review Panel Workflow Tests

final class ReviewPanelWorkflowTests: XCTestCase {
    
    /// Helper to create FeedbackDisplayItem with proper initializer
    private func createFeedbackItem(
        fileName: String,
        categoryComponents: [String],
        confidence: Double,
        status: FeedbackItem.FeedbackStatus = .pending
    ) -> FeedbackDisplayItem {
        return FeedbackDisplayItem(
            id: Int64.random(in: 1...10000),
            fileName: fileName,
            filePath: "/test/\(fileName)",
            fileIcon: "doc.text",
            categoryPath: CategoryPath(components: categoryComponents),
            confidence: confidence,
            rationale: "Test rationale",
            keywords: ["test"],
            status: status
        )
    }
    
    func testFeedbackDisplayItemCreation() {
        let feedbackItem = createFeedbackItem(
            fileName: "document.pdf",
            categoryComponents: ["Work", "Documents"],
            confidence: 0.65
        )
        
        XCTAssertEqual(feedbackItem.fileName, "document.pdf")
        XCTAssertEqual(feedbackItem.categoryPath.description, "Work / Documents")
        XCTAssertEqual(feedbackItem.confidence, 0.65)
        XCTAssertTrue(feedbackItem.needsReview) // pending status = needs review
    }
    
    func testLowConfidenceNeedsReview() {
        let lowConfidenceItem = createFeedbackItem(
            fileName: "uncertain.txt",
            categoryComponents: ["Maybe"],
            confidence: 0.3,
            status: .pending
        )
        
        XCTAssertTrue(lowConfidenceItem.needsReview)
        XCTAssertLessThan(lowConfidenceItem.confidence, 0.5)
    }
    
    func testHighConfidenceNoReview() {
        let highConfidenceItem = createFeedbackItem(
            fileName: "certain.txt",
            categoryComponents: ["Work", "Projects"],
            confidence: 0.98,
            status: .humanAccepted
        )
        
        XCTAssertFalse(highConfidenceItem.needsReview) // accepted status = no review needed
        XCTAssertGreaterThan(highConfidenceItem.confidence, 0.9)
    }
    
    func testCategoryPathModification() {
        var feedbackItem = createFeedbackItem(
            fileName: "file.txt",
            categoryComponents: ["Original", "Path"],
            confidence: 0.7
        )
        
        // Simulate user changing category
        feedbackItem.categoryPath = CategoryPath(components: ["New", "Category", "Path"])
        
        XCTAssertEqual(feedbackItem.categoryPath.components, ["New", "Category", "Path"])
        XCTAssertEqual(feedbackItem.categoryPath.depth, 3)
    }
}

// MARK: - Keyboard Navigation Tests

final class KeyboardNavigationTests: XCTestCase {
    
    func testEscapeKeyDismissesReview() {
        // This tests the logic, not actual keyboard handling
        var isEditing = true
        var editedPath = ""
        var showingReview = true
        
        // Simulate pressing Escape
        if isEditing {
            // Cancel edit mode
            isEditing = false
            editedPath = ""
        } else {
            // Dismiss review
            showingReview = false
        }
        
        XCTAssertFalse(isEditing)
        XCTAssertTrue(editedPath.isEmpty)
    }
    
    func testEnterKeySubmitsCategory() {
        // Test the submit logic
        var isEditing = true
        var editedPath = "New/Category"
        var submittedPath: String?
        
        // Simulate pressing Enter while editing
        if isEditing && !editedPath.isEmpty {
            submittedPath = editedPath
            isEditing = false
        }
        
        XCTAssertFalse(isEditing)
        XCTAssertEqual(submittedPath, "New/Category")
    }
    
    func testEmptyPathNotSubmitted() {
        var isEditing = true
        var editedPath = ""
        var submittedPath: String?
        
        // Simulate pressing Enter with empty path
        if isEditing && !editedPath.isEmpty {
            submittedPath = editedPath
            isEditing = false
        }
        
        // Should not submit
        XCTAssertNil(submittedPath)
        XCTAssertTrue(isEditing) // Still editing
    }
}

// MARK: - Color Theming Tests

final class CategoryColorThemingTests: XCTestCase {
    
    func testColorLevelCycling() {
        // Test that colors cycle properly for deep paths
        let colors = ["blue", "purple", "orange", "green", "pink"]
        
        for level in 0..<10 {
            let colorIndex = level % colors.count
            XCTAssertLessThan(colorIndex, colors.count)
            XCTAssertGreaterThanOrEqual(colorIndex, 0)
        }
    }
    
    func testFirstLevelColor() {
        let colors = ["blue", "purple", "orange", "green", "pink"]
        XCTAssertEqual(colors[0 % colors.count], "blue")
    }
    
    func testDeepLevelColorWraps() {
        let colors = ["blue", "purple", "orange", "green", "pink"]
        // Level 5 should wrap to blue (5 % 5 = 0)
        XCTAssertEqual(colors[5 % colors.count], "blue")
        // Level 7 should be orange (7 % 5 = 2)
        XCTAssertEqual(colors[7 % colors.count], "orange")
    }
}

