// MARK: - Embedding Cache Tests

import XCTest
@testable import SortAI

final class EmbeddingCacheTests: XCTestCase {
    
    var cache: EmbeddingCache!
    var database: SortAIDatabase!
    
    override func setUp() async throws {
        // Create in-memory database for testing
        database = try SortAIDatabase(configuration: .inMemory)
        cache = await EmbeddingCache(database: database)
    }
    
    override func tearDown() async throws {
        try await cache.clear()
        cache = nil
        database = nil
    }
    
    // MARK: - Cache Key Tests
    
    func testCacheKeyHash() {
        let key1 = EmbeddingCacheKey(filename: "test.pdf", parentPath: "/Users/test/Documents")
        let key2 = EmbeddingCacheKey(filename: "test.pdf", parentPath: "/Users/test/Documents")
        let key3 = EmbeddingCacheKey(filename: "test.pdf", parentPath: "/Users/test/Downloads")
        
        XCTAssertEqual(key1.hash, key2.hash, "Same filename and parent should produce same hash")
        XCTAssertNotEqual(key1.hash, key3.hash, "Different parent should produce different hash")
    }
    
    func testCacheKeyFromURL() {
        let url = URL(fileURLWithPath: "/Users/test/Documents/report.pdf")
        let key = EmbeddingCacheKey(url: url)
        
        XCTAssertEqual(key.filename, "report.pdf")
        XCTAssertEqual(key.parentPath, "/Users/test/Documents")
    }
    
    // MARK: - Basic Cache Operations
    
    func testSetAndGet() async throws {
        let key = EmbeddingCacheKey(filename: "test.pdf", parentPath: "/tmp")
        let embedding: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        
        try await cache.set(key: key, embedding: embedding, model: "test-model", type: .filename)
        
        let cached = try await cache.get(key: key)
        
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.filename, "test.pdf")
        XCTAssertEqual(cached?.model, "test-model")
        XCTAssertEqual(cached?.embeddingType, .filename)
        XCTAssertEqual(cached?.embedding.count, 5)
    }
    
    func testCacheMiss() async throws {
        let key = EmbeddingCacheKey(filename: "nonexistent.pdf", parentPath: "/tmp")
        
        let cached = try await cache.get(key: key)
        
        XCTAssertNil(cached)
    }
    
    func testContains() async throws {
        let key = EmbeddingCacheKey(filename: "exists.pdf", parentPath: "/tmp")
        let embedding: [Float] = [0.1, 0.2, 0.3]
        
        let existsBefore = try await cache.contains(key: key)
        XCTAssertFalse(existsBefore)
        
        try await cache.set(key: key, embedding: embedding, model: "test", type: .filename)
        
        let existsAfter = try await cache.contains(key: key)
        XCTAssertTrue(existsAfter)
    }
    
    func testRemove() async throws {
        let key = EmbeddingCacheKey(filename: "remove-me.pdf", parentPath: "/tmp")
        let embedding: [Float] = [0.1, 0.2, 0.3]
        
        try await cache.set(key: key, embedding: embedding, model: "test", type: .filename)
        let existsAfterSet = try await cache.contains(key: key)
        XCTAssertTrue(existsAfterSet)
        
        try await cache.remove(key: key)
        let existsAfterRemove = try await cache.contains(key: key)
        XCTAssertFalse(existsAfterRemove)
    }
    
    func testClear() async throws {
        let key1 = EmbeddingCacheKey(filename: "file1.pdf", parentPath: "/tmp")
        let key2 = EmbeddingCacheKey(filename: "file2.pdf", parentPath: "/tmp")
        let embedding: [Float] = [0.1, 0.2, 0.3]
        
        try await cache.set(key: key1, embedding: embedding, model: "test", type: .filename)
        try await cache.set(key: key2, embedding: embedding, model: "test", type: .filename)
        
        try await cache.clear()
        
        let exists1 = try await cache.contains(key: key1)
        let exists2 = try await cache.contains(key: key2)
        XCTAssertFalse(exists1)
        XCTAssertFalse(exists2)
    }
    
    // MARK: - Statistics Tests
    
    func testStatistics() async throws {
        let key1 = EmbeddingCacheKey(filename: "file1.pdf", parentPath: "/tmp")
        let key2 = EmbeddingCacheKey(filename: "file2.pdf", parentPath: "/tmp")
        let embedding: [Float] = [0.1, 0.2, 0.3]
        
        try await cache.set(key: key1, embedding: embedding, model: "test", type: .filename)
        try await cache.set(key: key2, embedding: embedding, model: "test", type: .filename)
        
        let stats = try await cache.statistics()
        
        XCTAssertEqual(stats.totalEntries, 2)
    }
    
    // MARK: - Embedding Types
    
    func testDifferentEmbeddingTypes() async throws {
        let keyFilename = EmbeddingCacheKey(filename: "test.pdf", parentPath: "/tmp/filename")
        let keyContent = EmbeddingCacheKey(filename: "test.pdf", parentPath: "/tmp/content")
        let keyHybrid = EmbeddingCacheKey(filename: "test.pdf", parentPath: "/tmp/hybrid")
        
        let embedding: [Float] = [0.1, 0.2, 0.3]
        
        try await cache.set(key: keyFilename, embedding: embedding, model: "test", type: .filename)
        try await cache.set(key: keyContent, embedding: embedding, model: "test", type: .content)
        try await cache.set(key: keyHybrid, embedding: embedding, model: "test", type: .hybrid)
        
        let cachedFilename = try await cache.get(key: keyFilename)
        let cachedContent = try await cache.get(key: keyContent)
        let cachedHybrid = try await cache.get(key: keyHybrid)
        
        XCTAssertEqual(cachedFilename?.embeddingType, .filename)
        XCTAssertEqual(cachedContent?.embeddingType, .content)
        XCTAssertEqual(cachedHybrid?.embeddingType, .hybrid)
    }
    
    // MARK: - Embedding Data Integrity
    
    func testEmbeddingDataIntegrity() async throws {
        let key = EmbeddingCacheKey(filename: "integrity.pdf", parentPath: "/tmp")
        let originalEmbedding: [Float] = [0.123456, -0.789012, 0.345678, -0.901234, 0.567890]
        
        try await cache.set(key: key, embedding: originalEmbedding, model: "test", type: .filename)
        
        let cached = try await cache.get(key: key)
        
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.embedding.count, originalEmbedding.count)
        
        if let cachedEmbedding = cached?.embedding {
            for (i, value) in originalEmbedding.enumerated() {
                XCTAssertEqual(cachedEmbedding[i], value, accuracy: 0.0001)
            }
        }
    }
}

// MARK: - Cached Embedding Encoding Tests

final class CachedEmbeddingEncodingTests: XCTestCase {
    
    func testEmbeddingEncoding() {
        let original: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]
        let encoded = CachedEmbedding.encodeEmbedding(original)
        let decoded = CachedEmbedding.decodeEmbedding(encoded)
        
        XCTAssertEqual(original.count, decoded.count)
        for (a, b) in zip(original, decoded) {
            XCTAssertEqual(a, b, accuracy: 0.0001)
        }
    }
    
    func testLargeEmbeddingEncoding() {
        let original = (0..<384).map { Float($0) / 384.0 }
        let encoded = CachedEmbedding.encodeEmbedding(original)
        let decoded = CachedEmbedding.decodeEmbedding(encoded)
        
        XCTAssertEqual(original.count, decoded.count)
        for (a, b) in zip(original, decoded) {
            XCTAssertEqual(a, b, accuracy: 0.0001)
        }
    }
    
    func testEmptyEmbeddingEncoding() {
        let original: [Float] = []
        let encoded = CachedEmbedding.encodeEmbedding(original)
        let decoded = CachedEmbedding.decodeEmbedding(encoded)
        
        XCTAssertTrue(decoded.isEmpty)
    }
}
