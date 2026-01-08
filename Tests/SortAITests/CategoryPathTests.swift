// MARK: - CategoryPath Tests
// Tests for CategoryPath struct and related functionality

import XCTest
@testable import SortAI

final class CategoryPathTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testCategoryPathFromComponents() {
        let path = CategoryPath(components: ["Work", "Projects", "SortAI"])
        
        XCTAssertEqual(path.components.count, 3)
        XCTAssertEqual(path.root, "Work")
        XCTAssertEqual(path.leaf, "SortAI")
        XCTAssertEqual(path.depth, 3)
    }
    
    func testCategoryPathFromStringWithDefaultSeparator() {
        let path = CategoryPath(path: "Work/Projects/SortAI")
        
        XCTAssertEqual(path.components.count, 3)
        XCTAssertEqual(path.components, ["Work", "Projects", "SortAI"])
    }
    
    func testCategoryPathFromStringWithCustomSeparator() {
        let path = CategoryPath(path: "Work > Projects > SortAI", separator: " > ")
        
        XCTAssertEqual(path.components.count, 3)
        XCTAssertEqual(path.components, ["Work", "Projects", "SortAI"])
    }
    
    func testCategoryPathTrimsWhitespace() {
        let path = CategoryPath(components: ["  Work  ", " Projects ", "  SortAI  "])
        
        XCTAssertEqual(path.components, ["Work", "Projects", "SortAI"])
    }
    
    func testCategoryPathFromStringFiltersEmptyComponents() {
        let path = CategoryPath(path: "Work//Projects///SortAI")
        
        XCTAssertEqual(path.components.count, 3)
        XCTAssertEqual(path.components, ["Work", "Projects", "SortAI"])
    }
    
    func testEmptyCategoryPath() {
        let path = CategoryPath(components: [])
        
        XCTAssertEqual(path.depth, 0)
        XCTAssertEqual(path.root, "")
        XCTAssertEqual(path.leaf, "")
        XCTAssertNil(path.parent)
    }
    
    // MARK: - Description Tests
    
    func testCategoryPathDescription() {
        let path = CategoryPath(components: ["Work", "Projects", "SortAI"])
        
        XCTAssertEqual(path.description, "Work / Projects / SortAI")
    }
    
    func testSingleComponentDescription() {
        let path = CategoryPath(components: ["Work"])
        
        XCTAssertEqual(path.description, "Work")
    }
    
    // MARK: - Parent Tests
    
    func testCategoryPathParent() {
        let path = CategoryPath(components: ["Work", "Projects", "SortAI"])
        let parent = path.parent
        
        XCTAssertNotNil(parent)
        XCTAssertEqual(parent?.components, ["Work", "Projects"])
    }
    
    func testCategoryPathParentChain() {
        let path = CategoryPath(components: ["Work", "Projects", "SortAI"])
        
        let parent1 = path.parent
        XCTAssertEqual(parent1?.components, ["Work", "Projects"])
        
        let parent2 = parent1?.parent
        XCTAssertEqual(parent2?.components, ["Work"])
        
        let parent3 = parent2?.parent
        XCTAssertNil(parent3)
    }
    
    func testSingleComponentHasNoParent() {
        let path = CategoryPath(components: ["Work"])
        
        XCTAssertNil(path.parent)
    }
    
    // MARK: - Appending Tests
    
    func testAppendingComponent() {
        let path = CategoryPath(components: ["Work", "Projects"])
        let extended = path.appending("SortAI")
        
        XCTAssertEqual(extended.components, ["Work", "Projects", "SortAI"])
    }
    
    func testAppendingToEmptyPath() {
        let path = CategoryPath(components: [])
        let extended = path.appending("Work")
        
        XCTAssertEqual(extended.components, ["Work"])
    }
    
    // MARK: - Descendant Tests
    
    func testIsDescendant() {
        let ancestor = CategoryPath(components: ["Work", "Projects"])
        let descendant = CategoryPath(components: ["Work", "Projects", "SortAI"])
        
        XCTAssertTrue(descendant.isDescendant(of: ancestor))
    }
    
    func testIsNotDescendantOfSelf() {
        let path = CategoryPath(components: ["Work", "Projects"])
        
        XCTAssertFalse(path.isDescendant(of: path))
    }
    
    func testIsNotDescendantOfDifferentBranch() {
        let path1 = CategoryPath(components: ["Work", "Projects"])
        let path2 = CategoryPath(components: ["Personal", "Projects"])
        
        XCTAssertFalse(path1.isDescendant(of: path2))
    }
    
    func testIsNotDescendantOfChild() {
        let parent = CategoryPath(components: ["Work"])
        let child = CategoryPath(components: ["Work", "Projects"])
        
        XCTAssertFalse(parent.isDescendant(of: child))
    }
    
    // MARK: - Hashable Tests
    
    func testCategoryPathHashable() {
        let path1 = CategoryPath(components: ["Work", "Projects"])
        let path2 = CategoryPath(components: ["Work", "Projects"])
        let path3 = CategoryPath(components: ["Personal", "Projects"])
        
        XCTAssertEqual(path1, path2)
        XCTAssertNotEqual(path1, path3)
        
        var set: Set<CategoryPath> = []
        set.insert(path1)
        set.insert(path2)
        set.insert(path3)
        
        XCTAssertEqual(set.count, 2)
    }
    
    // MARK: - Codable Tests
    
    func testCategoryPathCodable() throws {
        let original = CategoryPath(components: ["Work", "Projects", "SortAI"])
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CategoryPath.self, from: data)
        
        XCTAssertEqual(original, decoded)
    }
}

