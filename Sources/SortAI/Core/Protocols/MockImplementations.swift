// MARK: - Mock Implementations
// Test doubles for protocol-based components
// Enables isolated unit testing and custom behavior injection

import Foundation

// MARK: - Mock File Router

/// Mock file router for testing
/// Returns configurable inspection strategies
actor MockFileRouter: FileRouting {
    
    var routeHandler: ((URL) throws -> InspectionStrategy)?
    var mediaKindHandler: ((URL) -> MediaKind)?
    
    private var callLog: [String] = []
    
    func route(url: URL) throws -> InspectionStrategy {
        callLog.append("route:\(url.lastPathComponent)")
        if let handler = routeHandler {
            return try handler(url)
        }
        // Default based on extension
        switch url.pathExtension.lowercased() {
        case "pdf", "txt", "md": return .document(.plainText)
        case "mp4", "mov": return .video
        case "jpg", "png": return .image
        case "mp3", "wav": return .audio
        default: throw RouterError.unsupportedFileType(url.pathExtension)
        }
    }
    
    func mediaKind(for url: URL) -> MediaKind {
        callLog.append("mediaKind:\(url.lastPathComponent)")
        if let handler = mediaKindHandler {
            return handler(url)
        }
        switch url.pathExtension.lowercased() {
        case "pdf", "txt", "md": return .document
        case "mp4", "mov": return .video
        case "jpg", "png": return .image
        case "mp3", "wav": return .audio
        default: return .unknown
        }
    }
    
    func getCallLog() -> [String] { callLog }
    func clearCallLog() { callLog.removeAll() }
}

// MARK: - Mock Media Inspector

/// Mock media inspector for testing
/// Returns configurable file signatures
actor MockMediaInspector: MediaInspecting {
    
    var inspectHandler: ((URL) async throws -> FileSignature)?
    var defaultSignature: FileSignature?
    
    private var callLog: [URL] = []
    
    func inspect(url: URL) async throws -> FileSignature {
        callLog.append(url)
        
        if let handler = inspectHandler {
            return try await handler(url)
        }
        
        if let signature = defaultSignature {
            return signature
        }
        
        // Return a minimal signature
        return FileSignature(
            url: url,
            kind: .document,
            title: url.lastPathComponent,
            fileExtension: url.pathExtension,
            fileSizeBytes: 1024,
            checksum: "mock-checksum-\(url.hashValue)",
            textualCue: "Mock content for \(url.lastPathComponent)",
            wordCount: 100,
            language: "en"
        )
    }
    
    func getCallLog() -> [URL] { callLog }
    func clearCallLog() { callLog.removeAll() }
}

// MARK: - Mock Categorizer

/// Mock categorizer for testing
/// Returns configurable categorization results
actor MockCategorizer: FileCategorizing {
    
    var categorizeHandler: ((FileSignature) async throws -> EnhancedBrainResult)?
    var defaultResult: EnhancedBrainResult?
    var isHealthy: Bool = true
    var existingCategories: [CategoryPath] = []
    
    private var callLog: [String] = []
    
    func categorize(signature: FileSignature) async throws -> EnhancedBrainResult {
        callLog.append("categorize:\(signature.title)")
        
        if let handler = categorizeHandler {
            return try await handler(signature)
        }
        
        if let result = defaultResult {
            return result
        }
        
        // Return a default result
        return EnhancedBrainResult(
            categoryPath: CategoryPath(path: "MockCategory/Subcategory"),
            confidence: 0.9,
            rationale: "Mock categorization",
            extractedKeywords: ["mock", "test"],
            suggestedFromGraph: false
        )
    }
    
    func healthCheck() async -> Bool {
        callLog.append("healthCheck")
        return isHealthy
    }
    
    func getExistingCategories(limit: Int) async -> [CategoryPath] {
        callLog.append("getExistingCategories:\(limit)")
        return Array(existingCategories.prefix(limit))
    }
    
    // Test helpers
    func setExistingCategories(_ categories: [CategoryPath]) {
        existingCategories = categories
    }
    
    func getCallLog() -> [String] { callLog }
    func clearCallLog() { callLog.removeAll() }
}

// MARK: - Mock Embedding Generator

/// Mock embedding generator for testing
/// Returns configurable embedding vectors
actor MockEmbeddingGenerator: EmbeddingGenerating {
    
    let dimensions: Int
    var embedHandler: ((String) async throws -> [Float])?
    
    private var callLog: [String] = []
    
    init(dimensions: Int = 384) {
        self.dimensions = dimensions
    }
    
    func generateEmbedding(for text: String) async throws -> [Float] {
        callLog.append("embed:\(text.prefix(50))")
        
        if let handler = embedHandler {
            return try await handler(text)
        }
        
        // Return a deterministic embedding based on text hash
        return generateDeterministicEmbedding(from: text)
    }
    
    func generateEmbedding(for signature: FileSignature) async throws -> [Float] {
        let combined = "\(signature.title) \(signature.textualCue.prefix(100))"
        return try await generateEmbedding(for: combined)
    }
    
    private func generateDeterministicEmbedding(from text: String) -> [Float] {
        var embedding = [Float](repeating: 0, count: dimensions)
        let hash = text.hashValue
        
        for i in 0..<dimensions {
            let seed = hash &+ i
            embedding[i] = Float(sin(Double(seed)))
        }
        
        // Normalize
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            embedding = embedding.map { $0 / magnitude }
        }
        
        return embedding
    }
    
    func getCallLog() -> [String] { callLog }
    func clearCallLog() { callLog.removeAll() }
}

// MARK: - Mock Pattern Matcher

/// Mock pattern matcher for testing
/// Returns configurable pattern matches
final class MockPatternMatcher: PatternMatching, @unchecked Sendable {
    
    private let lock = NSLock()
    private var _patterns: [LearnedPattern] = []
    private var _callLog: [String] = []
    
    var patterns: [LearnedPattern] {
        lock.lock()
        defer { lock.unlock() }
        return _patterns
    }
    
    func queryNearest(embedding: [Float], threshold: Double) throws -> (LearnedPattern, Double)? {
        lock.lock()
        defer { lock.unlock() }
        _callLog.append("queryNearest:threshold=\(threshold)")
        
        // Return first pattern if any exist and similarity is above threshold
        guard let pattern = _patterns.first else { return nil }
        let similarity = 0.9 // Mock high similarity
        return similarity >= threshold ? (pattern, similarity) : nil
    }
    
    func findByChecksum(_ checksum: String) throws -> LearnedPattern? {
        lock.lock()
        defer { lock.unlock() }
        _callLog.append("findByChecksum:\(checksum)")
        return _patterns.first { $0.checksum == checksum }
    }
    
    func recordHit(patternId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        _callLog.append("recordHit:\(patternId)")
    }
    
    func savePattern(
        signature: FileSignature,
        embedding: [Float],
        label: String,
        originalLabel: String?,
        confidence: Double
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        _callLog.append("savePattern:\(label)")
        
        let pattern = LearnedPattern(
            checksum: signature.checksum,
            embedding: embedding,
            label: label,
            originalLabel: originalLabel,
            confidence: confidence,
            createdAt: Date()
        )
        _patterns.append(pattern)
    }
    
    func addPattern(_ pattern: LearnedPattern) {
        lock.lock()
        defer { lock.unlock() }
        _patterns.append(pattern)
    }
    
    func getCallLog() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return _callLog
    }
    
    func clearCallLog() {
        lock.lock()
        defer { lock.unlock() }
        _callLog.removeAll()
    }
}

// MARK: - Mock Component Factory

/// Factory that creates mock components for testing
final class MockComponentFactory: ComponentFactory, @unchecked Sendable {
    
    let mockRouter = MockFileRouter()
    let mockInspector = MockMediaInspector()
    var mockCategorizer: MockCategorizer?
    var mockEmbeddingGenerator: MockEmbeddingGenerator?
    var mockPatternMatcher: MockPatternMatcher?
    
    init() {}
    
    func createRouter() -> any FileRouting {
        mockRouter
    }
    
    func createInspector() -> any MediaInspecting {
        mockInspector
    }
    
    func createCategorizer(configuration: BrainConfiguration) -> any FileCategorizing {
        if mockCategorizer == nil {
            mockCategorizer = MockCategorizer()
        }
        return mockCategorizer!
    }
    
    func createEmbeddingGenerator(configuration: BrainConfiguration, dimensions: Int) -> any EmbeddingGenerating {
        if mockEmbeddingGenerator == nil {
            mockEmbeddingGenerator = MockEmbeddingGenerator(dimensions: dimensions)
        }
        return mockEmbeddingGenerator!
    }
    
    func createPatternMatcher(embeddingDimensions: Int, similarityThreshold: Double) throws -> any PatternMatching {
        if mockPatternMatcher == nil {
            mockPatternMatcher = MockPatternMatcher()
        }
        return mockPatternMatcher!
    }
}

// MARK: - Recording Wrappers

/// Wrapper that records calls to the underlying component
actor RecordingRouter: FileRouting {
    private let underlying: any FileRouting
    private(set) var routeCalls: [URL] = []
    private(set) var mediaKindCalls: [URL] = []
    
    init(underlying: any FileRouting) {
        self.underlying = underlying
    }
    
    func route(url: URL) async throws -> InspectionStrategy {
        routeCalls.append(url)
        return try await underlying.route(url: url)
    }
    
    func mediaKind(for url: URL) async -> MediaKind {
        mediaKindCalls.append(url)
        return await underlying.mediaKind(for: url)
    }
}

/// Wrapper that records calls to the underlying inspector
actor RecordingInspector: MediaInspecting {
    private let underlying: any MediaInspecting
    private(set) var inspectCalls: [URL] = []
    
    init(underlying: any MediaInspecting) {
        self.underlying = underlying
    }
    
    func inspect(url: URL) async throws -> FileSignature {
        inspectCalls.append(url)
        return try await underlying.inspect(url: url)
    }
}

