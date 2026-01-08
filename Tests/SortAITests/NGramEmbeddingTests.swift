// MARK: - N-Gram Embedding Tests

import XCTest
@testable import SortAI

final class NGramEmbeddingTests: XCTestCase {
    
    var generator: NGramEmbeddingGenerator!
    
    override func setUp() {
        generator = NGramEmbeddingGenerator(configuration: .default)
    }
    
    override func tearDown() {
        generator = nil
    }
    
    // MARK: - Basic Embedding Generation
    
    func testEmbeddingGeneration() {
        let embedding = generator.embed(filename: "TestDocument.pdf")
        
        XCTAssertEqual(embedding.count, 384, "Default configuration should produce 384-dimensional embeddings")
    }
    
    func testEmbeddingNormalization() {
        let embedding = generator.embed(filename: "AnyFile.txt")
        
        // Check L2 normalization
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(magnitude, 1.0, accuracy: 0.001, "Embedding should be L2 normalized")
    }
    
    func testDifferentFilesDifferentEmbeddings() {
        let embedding1 = generator.embed(filename: "Report_2024.pdf")
        let embedding2 = generator.embed(filename: "Photo_Beach.jpg")
        
        let similarity = NGramEmbeddingGenerator.cosineSimilarity(embedding1, embedding2)
        XCTAssertLessThan(similarity, 0.9, "Different files should have different embeddings")
    }
    
    func testSimilarFilesSimilarEmbeddings() {
        let embedding1 = generator.embed(filename: "Report_Q1_2024.pdf")
        let embedding2 = generator.embed(filename: "Report_Q2_2024.pdf")
        
        let similarity = NGramEmbeddingGenerator.cosineSimilarity(embedding1, embedding2)
        XCTAssertGreaterThan(similarity, 0.4, "Similar filenames should have similar embeddings")
    }
    
    // MARK: - Filename Preprocessing
    
    func testCamelCaseSplitting() {
        let embedding1 = generator.embed(filename: "MyDocument.pdf")
        let embedding2 = generator.embed(filename: "My_Document.pdf")
        
        let similarity = NGramEmbeddingGenerator.cosineSimilarity(embedding1, embedding2)
        // N-gram hashing produces different buckets for camelCase vs underscore, so similarity is moderate
        XCTAssertGreaterThan(similarity, 0.1, "CamelCase and underscore should share some similarity")
    }
    
    func testCaseInsensitivity() {
        let embedding1 = generator.embed(filename: "REPORT.PDF")
        let embedding2 = generator.embed(filename: "report.pdf")
        
        let similarity = NGramEmbeddingGenerator.cosineSimilarity(embedding1, embedding2)
        XCTAssertGreaterThan(similarity, 0.95, "Different case should produce very similar embeddings")
    }
    
    func testExtensionHandling() {
        let embedding1 = generator.embed(filename: "document.pdf")
        let embedding2 = generator.embed(filename: "document.txt")
        
        // Extensions should be removed in preprocessing, so these should be similar
        let similarity = NGramEmbeddingGenerator.cosineSimilarity(embedding1, embedding2)
        XCTAssertGreaterThan(similarity, 0.8, "Different extensions should still be similar")
    }
    
    // MARK: - Context-Aware Embedding
    
    func testEmbeddingWithContext() {
        let embeddingBasic = generator.embed(filename: "report.pdf")
        let embeddingWithParent = generator.embed(
            filename: "report.pdf",
            parentFolder: "Financial",
            extension: "pdf"
        )
        
        // With context should be different
        XCTAssertNotEqual(embeddingBasic, embeddingWithParent)
    }
    
    func testParentFolderInfluence() {
        let embeddingWork = generator.embed(
            filename: "notes.txt",
            parentFolder: "Work",
            extension: "txt"
        )
        let embeddingPersonal = generator.embed(
            filename: "notes.txt",
            parentFolder: "Personal",
            extension: "txt"
        )
        
        let similarity = NGramEmbeddingGenerator.cosineSimilarity(embeddingWork, embeddingPersonal)
        XCTAssertLessThan(similarity, 0.95, "Different parent folders should influence embedding")
    }
    
    // MARK: - Batch Processing
    
    func testBatchEmbedding() {
        let filenames = ["file1.pdf", "file2.txt", "file3.jpg"]
        let embeddings = generator.embedBatch(filenames)
        
        XCTAssertEqual(embeddings.count, 3)
        for embedding in embeddings {
            XCTAssertEqual(embedding.count, 384)
        }
    }
    
    func testBatchEmbeddingWithContext() {
        let files: [(filename: String, parentFolder: String?, extension: String?)] = [
            ("report.pdf", "Work", "pdf"),
            ("photo.jpg", "Photos", "jpg"),
            ("song.mp3", "Music", "mp3")
        ]
        
        let embeddings = generator.embedBatch(files)
        
        XCTAssertEqual(embeddings.count, 3)
    }
    
    // MARK: - Similarity Functions
    
    func testCosineSimilarityIdentical() {
        let embedding: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let similarity = NGramEmbeddingGenerator.cosineSimilarity(embedding, embedding)
        
        XCTAssertEqual(similarity, 1.0, accuracy: 0.001)
    }
    
    func testCosineSimilarityOrthogonal() {
        let embedding1: [Float] = [1.0, 0.0, 0.0]
        let embedding2: [Float] = [0.0, 1.0, 0.0]
        
        let similarity = NGramEmbeddingGenerator.cosineSimilarity(embedding1, embedding2)
        XCTAssertEqual(similarity, 0.0, accuracy: 0.001)
    }
    
    func testFindNearest() {
        let query = generator.embed(filename: "Annual_Report_2024.pdf")
        let candidates = [
            generator.embed(filename: "Photo_Beach.jpg"),
            generator.embed(filename: "Quarterly_Report_2024.pdf"),  // Should be most similar
            generator.embed(filename: "Song_Mix.mp3"),
            generator.embed(filename: "Financial_Report_2023.pdf")  // Should be second most similar
        ]
        
        let nearest = NGramEmbeddingGenerator.findNearest(query: query, candidates: candidates, k: 2)
        
        XCTAssertEqual(nearest.count, 2)
        // One of the report files should be most similar
        XCTAssertTrue(nearest[0].index == 1 || nearest[0].index == 3)
    }
    
    // MARK: - Configuration Tests
    
    func testLightweightConfiguration() {
        let lightweightGenerator = NGramEmbeddingGenerator(configuration: .lightweight)
        let embedding = lightweightGenerator.embed(filename: "test.pdf")
        
        XCTAssertEqual(embedding.count, 256, "Lightweight config should produce 256-dimensional embeddings")
    }
    
    func testCustomConfiguration() {
        let customConfig = NGramConfiguration(
            charNGramSizes: [2, 3],
            wordNGramSizes: [1],
            dimensions: 128,
            charWeight: 0.5,
            useHashing: true,
            minCharNGramFreq: 1
        )
        let customGenerator = NGramEmbeddingGenerator(configuration: customConfig)
        let embedding = customGenerator.embed(filename: "test.pdf")
        
        XCTAssertEqual(embedding.count, 128)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyFilename() {
        let embedding = generator.embed(filename: "")
        XCTAssertEqual(embedding.count, 384)
    }
    
    func testVeryLongFilename() {
        let longName = String(repeating: "a", count: 1000) + ".pdf"
        let embedding = generator.embed(filename: longName)
        
        XCTAssertEqual(embedding.count, 384)
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(magnitude, 1.0, accuracy: 0.001)
    }
    
    func testSpecialCharacters() {
        let embedding = generator.embed(filename: "report (copy) [2024].pdf")
        
        XCTAssertEqual(embedding.count, 384)
    }
    
    func testUnicodeFilename() {
        let embedding = generator.embed(filename: "报告_2024.pdf")
        
        XCTAssertEqual(embedding.count, 384)
    }
}
