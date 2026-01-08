// MARK: - Protocol and Mock Tests
// Tests for protocol conformance, mock implementations, and dependency injection

import XCTest
@testable import SortAI

// MARK: - Protocol Conformance Tests

final class ProtocolConformanceTests: XCTestCase {
    
    func testFileRouterConformsToFileRouting() {
        let router = FileRouter()
        XCTAssertTrue(router is any FileRouting)
    }
    
    func testMediaInspectorConformsToMediaInspecting() {
        let inspector = MediaInspector()
        XCTAssertTrue(inspector is any MediaInspecting)
    }
    
    func testBrainConformsToBrainCategorizing() {
        let brain = Brain()
        XCTAssertTrue(brain is any FileCategorizing)
    }
    
    func testEmbeddingGeneratorConformsToEmbeddingGenerating() {
        let generator = EmbeddingGenerator()
        XCTAssertTrue(generator is any EmbeddingGenerating)
    }
    
    func testMemoryStoreConformsToPatternMatching() throws {
        let store = try MemoryStore.inMemory()
        XCTAssertTrue(store is any PatternMatching)
    }
    
    func testKnowledgeGraphStoreConformsToKnowledgeGraphing() throws {
        let db = try SortAIDatabase.inMemory()
        let graph = try KnowledgeGraphStore(database: db)
        XCTAssertTrue(graph is any KnowledgeGraphing)
    }
    
    func testFileOrganizerConformsToFileOrganizing() {
        let organizer = FileOrganizer()
        XCTAssertTrue(organizer is any FileOrganizing)
    }
}

// MARK: - Mock File Router Tests

final class MockFileRouterTests: XCTestCase {
    
    var router: MockFileRouter!
    
    override func setUp() async throws {
        router = MockFileRouter()
    }
    
    func testDefaultRoutingByExtension() async throws {
        let pdfURL = URL(fileURLWithPath: "/test/file.pdf")
        let mp4URL = URL(fileURLWithPath: "/test/file.mp4")
        let jpgURL = URL(fileURLWithPath: "/test/file.jpg")
        let mp3URL = URL(fileURLWithPath: "/test/file.mp3")
        
        let pdfStrategy = try await router.route(url: pdfURL)
        let mp4Strategy = try await router.route(url: mp4URL)
        let jpgStrategy = try await router.route(url: jpgURL)
        let mp3Strategy = try await router.route(url: mp3URL)
        
        if case .document = pdfStrategy {} else {
            XCTFail("Expected document strategy for PDF")
        }
        XCTAssertEqual(mp4Strategy, .video)
        XCTAssertEqual(jpgStrategy, .image)
        XCTAssertEqual(mp3Strategy, .audio)
    }
    
    func testCustomRouteHandler() async throws {
        await router.setRouteHandler { _ in .video }
        
        let txtURL = URL(fileURLWithPath: "/test/file.txt")
        let strategy = try await router.route(url: txtURL)
        
        XCTAssertEqual(strategy, .video)
    }
    
    func testMediaKindForURL() async {
        let pdfURL = URL(fileURLWithPath: "/test/file.pdf")
        let mp4URL = URL(fileURLWithPath: "/test/file.mp4")
        
        let pdfKind = await router.mediaKind(for: pdfURL)
        let mp4Kind = await router.mediaKind(for: mp4URL)
        
        XCTAssertEqual(pdfKind, .document)
        XCTAssertEqual(mp4Kind, .video)
    }
    
    func testCallLogging() async throws {
        let url1 = URL(fileURLWithPath: "/test/a.pdf")
        let url2 = URL(fileURLWithPath: "/test/b.mp4")
        
        _ = try await router.route(url: url1)
        _ = await router.mediaKind(for: url2)
        
        let log = await router.getCallLog()
        XCTAssertEqual(log.count, 2)
        XCTAssertTrue(log[0].contains("route:a.pdf"))
        XCTAssertTrue(log[1].contains("mediaKind:b.mp4"))
    }
    
    func testUnsupportedExtensionThrows() async {
        let unknownURL = URL(fileURLWithPath: "/test/file.xyz")
        
        do {
            _ = try await router.route(url: unknownURL)
            XCTFail("Expected error for unsupported extension")
        } catch {
            XCTAssertTrue(error is RouterError)
        }
    }
}

// MARK: - Mock Media Inspector Tests

final class MockMediaInspectorTests: XCTestCase {
    
    var inspector: MockMediaInspector!
    
    override func setUp() async throws {
        inspector = MockMediaInspector()
    }
    
    func testDefaultInspection() async throws {
        let url = URL(fileURLWithPath: "/test/document.pdf")
        
        let signature = try await inspector.inspect(url: url)
        
        XCTAssertEqual(signature.url, url)
        XCTAssertEqual(signature.title, "document.pdf")
        XCTAssertTrue(signature.checksum.contains("mock-checksum"))
    }
    
    func testCustomInspectHandler() async throws {
        let customSignature = FileSignature(
            url: URL(fileURLWithPath: "/custom/file.txt"),
            kind: .document,
            title: "Custom Title",
            fileExtension: "txt",
            fileSizeBytes: 999,
            checksum: "custom-checksum",
            textualCue: "Custom content"
        )
        
        await inspector.setInspectHandler { _ in customSignature }
        
        let url = URL(fileURLWithPath: "/any/file.pdf")
        let result = try await inspector.inspect(url: url)
        
        XCTAssertEqual(result.title, "Custom Title")
        XCTAssertEqual(result.checksum, "custom-checksum")
    }
    
    func testCallLogging() async throws {
        let url1 = URL(fileURLWithPath: "/test/a.pdf")
        let url2 = URL(fileURLWithPath: "/test/b.txt")
        
        _ = try await inspector.inspect(url: url1)
        _ = try await inspector.inspect(url: url2)
        
        let log = await inspector.getCallLog()
        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log[0], url1)
        XCTAssertEqual(log[1], url2)
    }
}

// MARK: - Mock Categorizer Tests

final class MockCategorizerTests: XCTestCase {
    
    var categorizer: MockCategorizer!
    
    override func setUp() async throws {
        categorizer = MockCategorizer()
    }
    
    func testDefaultCategorization() async throws {
        let signature = FileSignature(
            url: URL(fileURLWithPath: "/test/file.pdf"),
            kind: .document,
            title: "Test File",
            fileExtension: "pdf",
            fileSizeBytes: 1024,
            checksum: "test-checksum"
        )
        
        let result = try await categorizer.categorize(signature: signature)
        
        XCTAssertEqual(result.categoryPath.root, "MockCategory")
        XCTAssertEqual(result.confidence, 0.9)
        XCTAssertTrue(result.extractedKeywords.contains("mock"))
    }
    
    func testCustomResult() async throws {
        let customResult = EnhancedBrainResult(
            categoryPath: CategoryPath(path: "Work/Projects"),
            confidence: 0.95,
            rationale: "Custom result",
            extractedKeywords: ["work", "project"],
            suggestedFromGraph: true
        )
        
        await categorizer.setDefaultResult(customResult)
        
        let signature = FileSignature(
            url: URL(fileURLWithPath: "/test/file.pdf"),
            kind: .document,
            title: "Test",
            fileExtension: "pdf",
            fileSizeBytes: 1024,
            checksum: "test"
        )
        
        let result = try await categorizer.categorize(signature: signature)
        
        XCTAssertEqual(result.categoryPath.root, "Work")
        XCTAssertEqual(result.confidence, 0.95)
        XCTAssertTrue(result.suggestedFromGraph)
    }
    
    func testHealthCheck() async {
        var isHealthy = await categorizer.healthCheck()
        XCTAssertTrue(isHealthy)
        
        await categorizer.setIsHealthy(false)
        isHealthy = await categorizer.healthCheck()
        XCTAssertFalse(isHealthy)
    }
    
    func testExistingCategories() async {
        let categories = [
            CategoryPath(path: "Work"),
            CategoryPath(path: "Personal"),
            CategoryPath(path: "Archive")
        ]
        
        await categorizer.setExistingCategories(categories)
        
        let result = await categorizer.getExistingCategories(limit: 2)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].root, "Work")
        XCTAssertEqual(result[1].root, "Personal")
    }
}

// MARK: - Mock Embedding Generator Tests

final class MockEmbeddingGeneratorTests: XCTestCase {
    
    var generator: MockEmbeddingGenerator!
    
    override func setUp() async throws {
        generator = MockEmbeddingGenerator(dimensions: 128)
    }
    
    func testDimensions() async {
        let dims = await generator.dimensions
        XCTAssertEqual(dims, 128)
    }
    
    func testDeterministicEmbedding() async throws {
        let text = "test document content"
        
        let embedding1 = try await generator.generateEmbedding(for: text)
        let embedding2 = try await generator.generateEmbedding(for: text)
        
        XCTAssertEqual(embedding1.count, 128)
        XCTAssertEqual(embedding1, embedding2) // Same text = same embedding
    }
    
    func testDifferentTextDifferentEmbedding() async throws {
        let text1 = "document about cats"
        let text2 = "spreadsheet with numbers"
        
        let embedding1 = try await generator.generateEmbedding(for: text1)
        let embedding2 = try await generator.generateEmbedding(for: text2)
        
        XCTAssertNotEqual(embedding1, embedding2)
    }
    
    func testEmbeddingForSignature() async throws {
        let signature = FileSignature(
            url: URL(fileURLWithPath: "/test/file.pdf"),
            kind: .document,
            title: "Test Document",
            fileExtension: "pdf",
            fileSizeBytes: 1024,
            checksum: "test-checksum",
            textualCue: "Sample document content"
        )
        
        let embedding = try await generator.generateEmbedding(for: signature)
        
        XCTAssertEqual(embedding.count, 128)
    }
    
    func testNormalizedEmbedding() async throws {
        let text = "test"
        let embedding = try await generator.generateEmbedding(for: text)
        
        // Check magnitude is approximately 1.0
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(magnitude, 1.0, accuracy: 0.001)
    }
}

// MARK: - Mock Pattern Matcher Tests

final class MockPatternMatcherTests: XCTestCase {
    
    var matcher: MockPatternMatcher!
    
    override func setUp() {
        matcher = MockPatternMatcher()
    }
    
    func testSaveAndFindPattern() throws {
        let signature = FileSignature(
            url: URL(fileURLWithPath: "/test/file.pdf"),
            kind: .document,
            title: "Test",
            fileExtension: "pdf",
            fileSizeBytes: 1024,
            checksum: "unique-checksum-123"
        )
        
        try matcher.savePattern(
            signature: signature,
            embedding: [Float](repeating: 0.1, count: 128),
            label: "Work/Projects",
            originalLabel: nil,
            confidence: 0.9
        )
        
        let found = try matcher.findByChecksum("unique-checksum-123")
        
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.label, "Work/Projects")
        XCTAssertEqual(found?.confidence, 0.9)
    }
    
    func testFindByChecksumNotFound() throws {
        let result = try matcher.findByChecksum("nonexistent")
        XCTAssertNil(result)
    }
    
    func testQueryNearest() throws {
        // Add a pattern
        let pattern = LearnedPattern(
            checksum: "test-checksum",
            embedding: [Float](repeating: 0.1, count: 128),
            label: "Category",
            originalLabel: nil,
            confidence: 0.85,
            createdAt: Date()
        )
        matcher.addPattern(pattern)
        
        // Query with high threshold
        let result = try matcher.queryNearest(
            embedding: [Float](repeating: 0.1, count: 128),
            threshold: 0.8
        )
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0.label, "Category")
        XCTAssertGreaterThanOrEqual(result?.1 ?? 0, 0.8)
    }
    
    func testQueryNearestBelowThreshold() throws {
        // Add a pattern
        let pattern = LearnedPattern(
            checksum: "test-checksum",
            embedding: [Float](repeating: 0.1, count: 128),
            label: "Category",
            originalLabel: nil,
            confidence: 0.85,
            createdAt: Date()
        )
        matcher.addPattern(pattern)
        
        // Query with very high threshold - mock returns 0.9 similarity
        let result = try matcher.queryNearest(
            embedding: [Float](repeating: 0.1, count: 128),
            threshold: 0.95
        )
        
        XCTAssertNil(result)
    }
    
    func testRecordHit() throws {
        try matcher.recordHit(patternId: "test-id")
        
        let log = matcher.getCallLog()
        XCTAssertTrue(log.contains("recordHit:test-id"))
    }
    
    func testCallLogging() throws {
        _ = try matcher.findByChecksum("abc")
        _ = try matcher.queryNearest(embedding: [], threshold: 0.5)
        
        let log = matcher.getCallLog()
        XCTAssertEqual(log.count, 2)
        XCTAssertTrue(log[0].contains("findByChecksum"))
        XCTAssertTrue(log[1].contains("queryNearest"))
    }
}

// MARK: - Mock Component Factory Tests

final class MockComponentFactoryTests: XCTestCase {
    
    func testCreateRouter() {
        let factory = MockComponentFactory()
        let router = factory.createRouter()
        
        XCTAssertTrue(router is MockFileRouter)
    }
    
    func testCreateInspector() {
        let factory = MockComponentFactory()
        let inspector = factory.createInspector()
        
        XCTAssertTrue(inspector is MockMediaInspector)
    }
    
    func testCreateCategorizer() {
        let factory = MockComponentFactory()
        let config = BrainConfiguration.default
        let categorizer = factory.createCategorizer(configuration: config)
        
        XCTAssertTrue(categorizer is MockCategorizer)
    }
    
    func testCreateEmbeddingGenerator() {
        let factory = MockComponentFactory()
        let config = BrainConfiguration.default
        let generator = factory.createEmbeddingGenerator(configuration: config, dimensions: 256)
        
        XCTAssertTrue(generator is MockEmbeddingGenerator)
    }
    
    func testCreatePatternMatcher() throws {
        let factory = MockComponentFactory()
        let matcher = try factory.createPatternMatcher(embeddingDimensions: 128, similarityThreshold: 0.8)
        
        XCTAssertTrue(matcher is MockPatternMatcher)
    }
    
    func testFactoryReturnsSameInstances() throws {
        let factory = MockComponentFactory()
        let config = BrainConfiguration.default
        
        let cat1 = factory.createCategorizer(configuration: config)
        let cat2 = factory.createCategorizer(configuration: config)
        
        // Should be the same instance
        XCTAssertTrue(cat1 as AnyObject === cat2 as AnyObject)
    }
}

// MARK: - Default Component Factory Tests

final class DefaultComponentFactoryTests: XCTestCase {
    
    func testCreateRouterReturnsFileRouter() {
        let factory = DefaultComponentFactory.shared
        let router = factory.createRouter()
        
        XCTAssertTrue(router is FileRouter)
    }
    
    func testCreateInspectorReturnsMediaInspector() {
        let factory = DefaultComponentFactory.shared
        let inspector = factory.createInspector()
        
        XCTAssertTrue(inspector is MediaInspector)
    }
    
    func testCreateCategorizerReturnsBrain() {
        let factory = DefaultComponentFactory.shared
        let config = BrainConfiguration.default
        let categorizer = factory.createCategorizer(configuration: config)
        
        XCTAssertTrue(categorizer is Brain)
    }
    
    func testCreateEmbeddingGeneratorReturnsEmbeddingGenerator() {
        let factory = DefaultComponentFactory.shared
        let config = BrainConfiguration.default
        let generator = factory.createEmbeddingGenerator(configuration: config, dimensions: 384)
        
        XCTAssertTrue(generator is EmbeddingGenerator)
    }
    
    func testCreatePatternMatcherReturnsMemoryStore() throws {
        let factory = DefaultComponentFactory.shared
        let matcher = try factory.createPatternMatcher(embeddingDimensions: 384, similarityThreshold: 0.85)
        
        XCTAssertTrue(matcher is MemoryStore)
    }
}

// MARK: - Recording Wrapper Tests

final class RecordingWrapperTests: XCTestCase {
    
    func testRecordingRouterLogsRouteCalls() async throws {
        let mockRouter = MockFileRouter()
        let recording = RecordingRouter(underlying: mockRouter)
        
        let url1 = URL(fileURLWithPath: "/test/a.pdf")
        let url2 = URL(fileURLWithPath: "/test/b.mp4")
        
        _ = try await recording.route(url: url1)
        _ = try await recording.route(url: url2)
        
        let calls = await recording.routeCalls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0], url1)
        XCTAssertEqual(calls[1], url2)
    }
    
    func testRecordingRouterLogsMediaKindCalls() async {
        let mockRouter = MockFileRouter()
        let recording = RecordingRouter(underlying: mockRouter)
        
        let url = URL(fileURLWithPath: "/test/file.jpg")
        _ = await recording.mediaKind(for: url)
        
        let calls = await recording.mediaKindCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0], url)
    }
    
    func testRecordingInspectorLogsInspectCalls() async throws {
        let mockInspector = MockMediaInspector()
        let recording = RecordingInspector(underlying: mockInspector)
        
        let url = URL(fileURLWithPath: "/test/document.pdf")
        _ = try await recording.inspect(url: url)
        
        let calls = await recording.inspectCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0], url)
    }
}

// MARK: - Helper Extensions for Tests

extension InspectionStrategy: Equatable {
    public static func == (lhs: InspectionStrategy, rhs: InspectionStrategy) -> Bool {
        switch (lhs, rhs) {
        case (.video, .video), (.image, .image), (.audio, .audio):
            return true
        case let (.document(lhsType), .document(rhsType)):
            return lhsType == rhsType
        default:
            return false
        }
    }
}

extension InspectionStrategy.DocumentType: Equatable {}

extension MockFileRouter {
    func setRouteHandler(_ handler: @escaping (URL) throws -> InspectionStrategy) {
        self.routeHandler = handler
    }
}

extension MockMediaInspector {
    func setInspectHandler(_ handler: @escaping (URL) async throws -> FileSignature) {
        self.inspectHandler = handler
    }
}

extension MockCategorizer {
    func setDefaultResult(_ result: EnhancedBrainResult) {
        self.defaultResult = result
    }
    
    func setIsHealthy(_ healthy: Bool) {
        self.isHealthy = healthy
    }
    
    func setExistingCategories(_ categories: [CategoryPath]) {
        self.existingCategories = categories
    }
}

