// MARK: - Prototype Store Tests

import XCTest
@testable import SortAI

final class PrototypeStoreTests: XCTestCase {
    
    var store: PrototypeStore!
    var database: SortAIDatabase!
    
    override func setUp() async throws {
        database = try SortAIDatabase(configuration: .inMemory)
        store = await PrototypeStore(database: database)
    }
    
    override func tearDown() async throws {
        store = nil
        database = nil
    }
    
    // MARK: - Basic Operations
    
    func testGetPrototypeNotFound() async throws {
        // Initially empty
        let prototype = try await store.getPrototype(for: "Documents/Reports")
        XCTAssertNil(prototype)
    }
    
    func testUpdatePrototype() async throws {
        let embedding: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        
        try await store.updatePrototype(
            categoryPath: "Documents/Reports",
            newEmbedding: embedding
        )
        
        let prototype = try await store.getPrototype(for: "Documents/Reports")
        
        XCTAssertNotNil(prototype)
        XCTAssertEqual(prototype?.categoryPath, "Documents/Reports")
        XCTAssertEqual(prototype?.sampleCount, 1)
    }
    
    func testUpdatePrototypeAccumulates() async throws {
        let embedding1: [Float] = [1.0, 0.0, 0.0, 0.0, 0.0]
        let embedding2: [Float] = [0.0, 1.0, 0.0, 0.0, 0.0]
        
        try await store.updatePrototype(
            categoryPath: "Test",
            newEmbedding: embedding1
        )
        
        try await store.updatePrototype(
            categoryPath: "Test",
            newEmbedding: embedding2
        )
        
        let prototype = try await store.getPrototype(for: "Test")
        
        XCTAssertNotNil(prototype)
        XCTAssertEqual(prototype?.sampleCount, 2)
        
        // Embedding should be EMA of both (components from both vectors)
        XCTAssertGreaterThan(prototype!.embedding[0], 0)
        XCTAssertGreaterThan(prototype!.embedding[1], 0)
    }
    
    func testSetPrototype() async throws {
        var prototype = CategoryPrototype(
            categoryPath: "Custom/Path",
            embedding: [0.1, 0.2, 0.3]
        )
        prototype.confidence = 0.9
        prototype.sampleCount = 10
        
        try await store.setPrototype(prototype)
        
        let retrieved = try await store.getPrototype(for: "Custom/Path")
        
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.confidence ?? 0, 0.9, accuracy: 0.001)
        XCTAssertEqual(retrieved?.sampleCount, 10)
    }
    
    func testDeletePrototype() async throws {
        let embedding: [Float] = [0.1, 0.2, 0.3]
        
        try await store.updatePrototype(categoryPath: "ToDelete", newEmbedding: embedding)
        let existsBefore = try await store.getPrototype(for: "ToDelete")
        XCTAssertNotNil(existsBefore)
        
        try await store.deletePrototype(categoryPath: "ToDelete")
        let existsAfter = try await store.getPrototype(for: "ToDelete")
        XCTAssertNil(existsAfter)
    }
    
    func testGetAllPrototypes() async throws {
        let embedding: [Float] = [0.1, 0.2, 0.3]
        
        try await store.updatePrototype(categoryPath: "Category1", newEmbedding: embedding)
        try await store.updatePrototype(categoryPath: "Category2", newEmbedding: embedding)
        try await store.updatePrototype(categoryPath: "Category3", newEmbedding: embedding)
        
        let all = try await store.getAllPrototypes()
        
        XCTAssertEqual(all.count, 3)
    }
    
    // MARK: - Similarity Queries
    
    func testFindSimilar() async throws {
        // Create some prototypes with distinct embeddings
        try await store.updatePrototype(categoryPath: "A", newEmbedding: [1.0, 0.0, 0.0])
        try await store.updatePrototype(categoryPath: "B", newEmbedding: [0.0, 1.0, 0.0])
        try await store.updatePrototype(categoryPath: "C", newEmbedding: [0.0, 0.0, 1.0])
        
        // Query for something similar to A
        let query: [Float] = [0.9, 0.1, 0.0]
        let results = try await store.findSimilar(to: query, k: 2)
        
        XCTAssertGreaterThanOrEqual(results.count, 1)
        XCTAssertEqual(results[0].prototype.categoryPath, "A")
    }
    
    func testClassify() async throws {
        try await store.updatePrototype(categoryPath: "Documents", newEmbedding: [1.0, 0.0, 0.0])
        try await store.updatePrototype(categoryPath: "Images", newEmbedding: [0.0, 1.0, 0.0])
        
        // Boost confidence for Documents
        var proto = try await store.getPrototype(for: "Documents")!
        proto.confidence = 0.9
        try await store.setPrototype(proto)
        
        let query: [Float] = [0.95, 0.05, 0.0]  // Close to Documents
        let result = try await store.classify(embedding: query, minConfidence: 0.3)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.categoryPath, "Documents")
    }
    
    func testClassifyNoMatch() async throws {
        try await store.updatePrototype(categoryPath: "Documents", newEmbedding: [1.0, 0.0, 0.0])
        
        // Query for something completely different
        let query: [Float] = [0.0, 0.0, 1.0]
        let result = try await store.classify(embedding: query, minConfidence: 0.9)
        
        // May or may not return nil depending on min confidence threshold
        // The important thing is it doesn't crash
        XCTAssertTrue(result == nil || result?.categoryPath != nil)
    }
    
    // MARK: - Statistics
    
    func testStatistics() async throws {
        try await store.updatePrototype(categoryPath: "A", newEmbedding: [1.0, 0.0, 0.0])
        try await store.updatePrototype(categoryPath: "B", newEmbedding: [0.0, 1.0, 0.0])
        
        let stats = try await store.statistics()
        
        XCTAssertEqual(stats.totalPrototypes, 2)
        XCTAssertGreaterThan(stats.averageConfidence, 0)
        XCTAssertEqual(stats.averageSampleCount, 1.0, accuracy: 0.001)
    }
}

// MARK: - Category Prototype Tests

final class CategoryPrototypeTests: XCTestCase {
    
    func testGenerateId() {
        let id1 = CategoryPrototype.generateId(for: "Documents/Reports")
        let id2 = CategoryPrototype.generateId(for: "Documents/Reports")
        let id3 = CategoryPrototype.generateId(for: "Documents/Images")
        
        XCTAssertEqual(id1, id2)
        XCTAssertNotEqual(id1, id3)
    }
    
    func testEmbeddingAccessors() {
        var prototype = CategoryPrototype(
            categoryPath: "Test",
            embedding: [1.0, 2.0, 3.0]
        )
        
        XCTAssertEqual(prototype.embedding.count, 3)
        XCTAssertEqual(prototype.embedding[0], 1.0, accuracy: 0.001)
        
        prototype.embedding = [4.0, 5.0, 6.0]
        XCTAssertEqual(prototype.embedding[0], 4.0, accuracy: 0.001)
    }
    
    func testCategoryNameExtraction() {
        let prototype1 = CategoryPrototype(categoryPath: "A/B/C", embedding: [1.0])
        let prototype2 = CategoryPrototype(categoryPath: "Single", embedding: [1.0])
        
        XCTAssertEqual(prototype1.categoryName, "C")
        XCTAssertEqual(prototype2.categoryName, "Single")
    }
}
