// MARK: - SortAI Tests
// Comprehensive test suite following the incremental testing plan

import XCTest
@testable import SortAI

// MARK: - Phase 1: Foundation Tests

final class FileSignatureTests: XCTestCase {
    
    func testFileSignatureInitialization() {
        let signature = FileSignature(
            url: URL(fileURLWithPath: "/test/document.pdf"),
            kind: .document,
            title: "Test Document",
            fileExtension: "pdf",
            fileSizeBytes: 1024,
            checksum: "abc123",
            textualCue: "This is test content"
        )
        
        XCTAssertEqual(signature.kind, .document)
        XCTAssertEqual(signature.title, "Test Document")
        XCTAssertEqual(signature.fileExtension, "pdf")
        XCTAssertFalse(signature.textualCue.isEmpty)
    }
    
    func testFileSignatureVideoProperties() {
        let signature = FileSignature(
            url: URL(fileURLWithPath: "/test/video.mp4"),
            kind: .video,
            title: "Test Video",
            fileExtension: "mp4",
            fileSizeBytes: 10_000_000,
            checksum: "def456",
            sceneTags: ["outdoor", "nature", "sunset"],
            detectedObjects: ["person", "dog"],
            duration: 120.5,
            frameCount: 3600,
            resolution: CGSize(width: 1920, height: 1080),
            hasAudio: true
        )
        
        XCTAssertEqual(signature.kind, .video)
        XCTAssertEqual(signature.sceneTags.count, 3)
        XCTAssertEqual(signature.duration, 120.5)
        XCTAssertTrue(signature.hasAudio ?? false)
    }
    
    func testMediaKindIcon() {
        XCTAssertEqual(MediaKind.document.icon, "doc.text.fill")
        XCTAssertEqual(MediaKind.video.icon, "video.fill")
        XCTAssertEqual(MediaKind.image.icon, "photo.fill")
    }
}

final class FileRouterTests: XCTestCase {
    
    var router: FileRouter!
    
    override func setUp() async throws {
        router = FileRouter()
    }
    
    func testDocumentRouting() async throws {
        // Create temp PDF file
        let tempDir = FileManager.default.temporaryDirectory
        let pdfURL = tempDir.appendingPathComponent("test.pdf")
        
        // Write minimal PDF content
        let pdfContent = "%PDF-1.0\n%%EOF"
        try pdfContent.write(to: pdfURL, atomically: true, encoding: .utf8)
        
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        
        let strategy = try await router.route(url: pdfURL)
        
        if case .document(let type) = strategy {
            XCTAssertEqual(type, .pdf)
        } else {
            XCTFail("Expected document strategy for PDF")
        }
    }
    
    func testTextFileRouting() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let txtURL = tempDir.appendingPathComponent("test.txt")
        
        try "Hello World".write(to: txtURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: txtURL) }
        
        let strategy = try await router.route(url: txtURL)
        
        if case .document(let type) = strategy {
            XCTAssertEqual(type, .plainText)
        } else {
            XCTFail("Expected document strategy for TXT")
        }
    }
    
    func testUnsupportedFileType() async {
        let tempDir = FileManager.default.temporaryDirectory
        let unknownURL = tempDir.appendingPathComponent("test.xyz")
        
        try? "data".write(to: unknownURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: unknownURL) }
        
        do {
            _ = try await router.route(url: unknownURL)
            XCTFail("Should throw for unsupported type")
        } catch {
            XCTAssertTrue(error is RouterError)
        }
    }
    
    func testMediaKindDetection() async {
        let pdfURL = URL(fileURLWithPath: "/test/doc.pdf")
        let mp4URL = URL(fileURLWithPath: "/test/video.mp4")
        
        // Note: These will fail if files don't exist, which is expected
        // In real tests, create actual files
        let pdfKind = await router.mediaKind(for: pdfURL)
        let mp4Kind = await router.mediaKind(for: mp4URL)
        
        // Files don't exist so should return unknown
        XCTAssertEqual(pdfKind, .unknown)
        XCTAssertEqual(mp4Kind, .unknown)
    }
}

final class FileHasherTests: XCTestCase {
    
    func testSHA256Consistency() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hash_test.txt")
        
        try "Consistent content for hashing".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let hash1 = try await FileHasher.sha256(url: tempURL)
        let hash2 = try await FileHasher.sha256(url: tempURL)
        
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1.count, 64) // SHA-256 produces 64 hex chars
    }
    
    func testQuickHash() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick_hash_test.txt")
        
        try "Content".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let quickHash = try FileHasher.quickHash(url: tempURL)
        XCTAssertFalse(quickHash.isEmpty)
    }
}

// MARK: - Phase 2: Eye (MediaInspector) Tests

final class MediaInspectorTests: XCTestCase {
    
    var inspector: MediaInspector!
    
    override func setUp() async throws {
        inspector = MediaInspector()
    }
    
    func testTextFileInspection() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("inspect_test.txt")
        
        let content = """
        This is a test document with multiple lines.
        It contains some text that should be extracted.
        The inspector should detect this as a text file.
        """
        
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let signature = try await inspector.inspect(url: tempURL)
        
        XCTAssertEqual(signature.kind, .document)
        XCTAssertTrue(signature.textualCue.contains("test document"))
        XCTAssertFalse(signature.checksum.isEmpty)
    }
    
    func testSignatureSignalStrength() {
        let weakSignature = FileSignature(
            url: URL(fileURLWithPath: "/test.txt"),
            kind: .document,
            title: "Test",
            fileExtension: "txt",
            fileSizeBytes: 100,
            checksum: "abc"
        )
        
        let strongSignature = FileSignature(
            url: URL(fileURLWithPath: "/test.mp4"),
            kind: .video,
            title: "Test",
            fileExtension: "mp4",
            fileSizeBytes: 1000000,
            checksum: "def",
            textualCue: "Transcribed speech content here with more than 100 words " + String(repeating: "word ", count: 100),
            sceneTags: ["nature", "outdoor"],
            detectedObjects: ["person"],
            wordCount: 150
        )
        
        XCTAssertLessThan(weakSignature.signalStrength, strongSignature.signalStrength)
    }
}

// MARK: - Phase 3: Memory (MemoryStore) Tests

final class MemoryStoreTests: XCTestCase {
    
    var store: MemoryStore!
    
    override func setUp() async throws {
        store = try MemoryStore.inMemory(embeddingDimensions: 128)
    }
    
    func testPatternSaveAndRetrieve() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        
        let pattern = LearnedPattern(
            checksum: "test_checksum_123",
            embedding: embedding,
            label: "work-documents"
        )
        
        try store.savePattern(pattern)
        
        let retrieved = try store.findByChecksum("test_checksum_123")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.label, "work-documents")
    }
    
    func testVectorSimilarityQuery() throws {
        // Save a pattern
        let embedding1 = [Float](repeating: 0.5, count: 128)
        let pattern1 = LearnedPattern(
            checksum: "check1",
            embedding: embedding1,
            label: "category-a"
        )
        try store.savePattern(pattern1)
        
        // Query with similar embedding
        var queryEmbedding = [Float](repeating: 0.5, count: 128)
        queryEmbedding[0] = 0.6  // Slightly different
        
        let matches = try store.queryNearest(to: queryEmbedding, k: 5, minSimilarity: 0.5)
        
        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(matches.first?.pattern.label, "category-a")
    }
    
    func testCosineDistance() {
        let a: [Float] = [1.0, 0.0, 0.0]
        let b: [Float] = [1.0, 0.0, 0.0]
        let c: [Float] = [-1.0, 0.0, 0.0]
        
        let identical = MemoryStore.cosineDistance(a: a, b: b)
        let opposite = MemoryStore.cosineDistance(a: a, b: c)
        
        XCTAssertEqual(identical, 0.0, accuracy: 0.001)
        XCTAssertEqual(opposite, 2.0, accuracy: 0.001)
    }
    
    func testEmbeddingDimensionValidation() throws {
        let wrongDimensions = [Float](repeating: 0.5, count: 64)  // Wrong size
        
        let pattern = LearnedPattern(
            checksum: "wrong",
            embedding: wrongDimensions,
            label: "test"
        )
        
        XCTAssertThrowsError(try store.savePattern(pattern)) { error in
            // Can throw either MemoryStoreError or DatabaseError (from unified persistence layer)
            XCTAssertTrue(error is MemoryStoreError || error is DatabaseError)
        }
    }
    
    func testHitCountIncrement() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        let pattern = LearnedPattern(
            id: "hit-test",
            checksum: "hit_check",
            embedding: embedding,
            label: "test",
            hitCount: 0
        )
        
        try store.savePattern(pattern)
        try store.recordHit(patternId: "hit-test")
        try store.recordHit(patternId: "hit-test")
        
        // Verify hit count increased (would need to fetch and check)
        let patterns = try store.patternsForLabel("test")
        XCTAssertEqual(patterns.first?.hitCount, 2)
    }
    
    func testProcessingRecords() throws {
        let record = ProcessingRecord(
            fileURL: URL(fileURLWithPath: "/test/file.pdf"),
            checksum: "rec_checksum",
            mediaKind: .document,
            assignedCategory: "work",
            confidence: 0.95
        )
        
        try store.saveRecord(record)
        
        let retrieved = try store.wasProcessed(checksum: "rec_checksum")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.assignedCategory, "work")
    }
    
    func testCategoryStatistics() throws {
        // Add some records
        for i in 0..<5 {
            let record = ProcessingRecord(
                fileURL: URL(fileURLWithPath: "/test/file\(i).pdf"),
                checksum: "stat_check_\(i)",
                mediaKind: .document,
                assignedCategory: "work",
                confidence: Double(80 + i) / 100.0
            )
            try store.saveRecord(record)
        }
        
        let stats = try store.categoryStatistics()
        let workStats = stats.first { $0.category == "work" }
        
        XCTAssertNotNil(workStats)
        XCTAssertEqual(workStats?.totalFiles, 5)
    }
}

// MARK: - Phase 4: Brain Tests

final class BrainTests: XCTestCase {
    
    func testBrainResultParsing() throws {
        let jsonString = """
        {
            "category": "work-documents",
            "subcategory": "reports",
            "confidence": 0.92,
            "rationale": "Contains business terminology",
            "suggestedPath": "work/reports",
            "tags": ["business", "quarterly"]
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let result = try JSONDecoder().decode(BrainResult.self, from: data)
        
        XCTAssertEqual(result.category, "work-documents")
        XCTAssertEqual(result.subcategory, "reports")
        XCTAssertEqual(result.confidence, 0.92, accuracy: 0.01)
        XCTAssertEqual(result.tags.count, 2)
    }
    
    func testBrainResultMinimalParsing() throws {
        let jsonString = """
        {
            "category": "personal",
            "confidence": 0.75,
            "rationale": "Personal content detected"
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        let result = try JSONDecoder().decode(BrainResult.self, from: data)
        
        XCTAssertEqual(result.category, "personal")
        XCTAssertNil(result.subcategory)
    }
}

// MARK: - Integration Tests

final class PipelineIntegrationTests: XCTestCase {
    
    func testLearnedPatternSerialization() {
        let original = [Float]([0.1, 0.2, 0.3, 0.4, 0.5])
        let data = LearnedPattern.encodeEmbedding(original)
        let decoded = LearnedPattern.decodeEmbedding(data)
        
        XCTAssertEqual(original.count, decoded.count)
        for (a, b) in zip(original, decoded) {
            XCTAssertEqual(a, b, accuracy: 0.0001)
        }
    }
    
    func testProcessingResultCreation() {
        let signature = FileSignature(
            url: URL(fileURLWithPath: "/test.pdf"),
            kind: .document,
            title: "Test",
            fileExtension: "pdf",
            fileSizeBytes: 1000,
            checksum: "abc123"
        )
        
        let brainResult = BrainResult(
            category: "work",
            confidence: 0.9,
            rationale: "Test"
        )
        
        let result = ProcessingResult(
            signature: signature,
            brainResult: brainResult,
            wasFromMemory: false
        )
        
        XCTAssertFalse(result.wasFromMemory)
        XCTAssertEqual(result.brainResult.category, "work")
    }
}

// MARK: - Embedding Tests

final class EmbeddingTests: XCTestCase {
    
    func testSimpleEmbeddingGeneration() async throws {
        // Note: dimension depends on whether Ollama is available
        // - With Ollama: uses embedding model dimension (e.g., 3072 for nomic-embed-text)
        // - Without Ollama: falls back to simple hash embedding with requested dimension
        let generator = EmbeddingGenerator(dimensions: 128)
        
        let embedding1 = try await generator.embed(text: "Hello world")
        let embedding2 = try await generator.embed(text: "Hello world")
        
        // Verify embeddings are non-empty and consistent
        XCTAssertGreaterThan(embedding1.count, 0)
        XCTAssertEqual(embedding1.count, embedding2.count, "Embeddings should have consistent dimensions")
        
        // Same text should produce same embedding
        XCTAssertEqual(embedding1, embedding2)
    }
    
    func testEmbeddingSimilarity() async throws {
        let generator = EmbeddingGenerator(dimensions: 128)
        
        let embedding1 = try await generator.embed(text: "The quick brown fox")
        let embedding2 = try await generator.embed(text: "The quick brown dog")
        let embedding3 = try await generator.embed(text: "Something completely different about databases")
        
        // All embeddings should have same dimension
        XCTAssertEqual(embedding1.count, embedding2.count)
        XCTAssertEqual(embedding2.count, embedding3.count)
        
        let dist12 = MemoryStore.cosineDistance(a: embedding1, b: embedding2)
        let dist13 = MemoryStore.cosineDistance(a: embedding1, b: embedding3)
        
        // Similar texts should have smaller distance
        XCTAssertLessThan(dist12, dist13)
    }
}

