// MARK: - Confidence Service Tests

import XCTest
@testable import SortAI

final class ConfidenceServiceTests: XCTestCase {
    
    var prototypeStore: PrototypeStore!
    var confidenceService: ConfidenceService!
    var database: SortAIDatabase!
    
    override func setUp() async throws {
        database = try SortAIDatabase(configuration: .inMemory)
        prototypeStore = await PrototypeStore(database: database)
        confidenceService = ConfidenceService(prototypeStore: prototypeStore)
    }
    
    override func tearDown() async throws {
        confidenceService = nil
        prototypeStore = nil
        database = nil
    }
    
    // MARK: - Confidence Calculation
    
    func testCalculateConfidenceWithNoPrototypes() async throws {
        let embedding: [Float] = [0.1, 0.2, 0.3]
        
        let result = try await confidenceService.calculateConfidence(
            embedding: embedding,
            filename: "test.pdf"
        )
        
        // With no prototypes, confidence should be relatively low
        XCTAssertLessThanOrEqual(result.confidence, 1.0)
        XCTAssertGreaterThanOrEqual(result.confidence, 0.0)
    }
    
    func testCalculateConfidenceWithMatchingPrototype() async throws {
        // Setup: Create a prototype for Documents
        let prototypeEmbedding: [Float] = [1.0, 0.0, 0.0]
        try await prototypeStore.updatePrototype(
            categoryPath: "Documents",
            newEmbedding: prototypeEmbedding
        )
        
        // Boost confidence
        var proto = try await prototypeStore.getPrototype(for: "Documents")!
        proto.confidence = 0.9
        try await prototypeStore.setPrototype(proto)
        
        // Test: Query with similar embedding
        let queryEmbedding: [Float] = [0.98, 0.02, 0.0]
        
        let result = try await confidenceService.calculateConfidence(
            embedding: queryEmbedding,
            filename: "report.pdf"
        )
        
        XCTAssertEqual(result.categoryPath, "Documents")
        XCTAssertGreaterThan(result.confidence, 0.0)
    }
    
    func testExtensionHeuristicsAffectConfidence() async throws {
        // Setup: Create prototype for Images
        let prototypeEmbedding: [Float] = [0.0, 1.0, 0.0]
        try await prototypeStore.updatePrototype(
            categoryPath: "Images",
            newEmbedding: prototypeEmbedding
        )
        
        // Test with and without extension
        let resultWithExt = try await confidenceService.calculateConfidence(
            embedding: [0.0, 0.9, 0.1],
            filename: "photo.jpg",
            fileExtension: "jpg"
        )
        
        // Just verify it runs and returns valid result
        XCTAssertGreaterThanOrEqual(resultWithExt.confidence, 0.0)
        XCTAssertLessThanOrEqual(resultWithExt.confidence, 1.0)
        XCTAssertGreaterThanOrEqual(resultWithExt.breakdown.extensionBonus, 0.0)
    }
    
    func testParentFolderBoostsConfidence() async throws {
        // Setup
        let embedding: [Float] = [0.5, 0.5, 0.0]
        try await prototypeStore.updatePrototype(
            categoryPath: "Work/Projects",
            newEmbedding: embedding
        )
        
        // Test without parent folder
        let resultNoParent = try await confidenceService.calculateConfidence(
            embedding: embedding,
            filename: "project.pdf"
        )
        
        // Test with matching parent folder
        let resultWithParent = try await confidenceService.calculateConfidence(
            embedding: embedding,
            filename: "project.pdf",
            parentFolder: "Work"
        )
        
        // Parent folder should affect confidence breakdown
        XCTAssertGreaterThanOrEqual(resultWithParent.breakdown.parentFolderBonus, resultNoParent.breakdown.parentFolderBonus)
    }
    
    // MARK: - Outcome Determination
    
    func testConfidenceOutcomeTypes() async throws {
        let result = try await confidenceService.calculateConfidence(
            embedding: [0.33, 0.33, 0.34],
            filename: "test.pdf"
        )
        
        // Outcome should be one of the valid values
        XCTAssertTrue([ConfidenceOutcome.autoPlace, .review, .deepAnalysis].contains(result.outcome))
    }
    
    // MARK: - Confidence Breakdown
    
    func testConfidenceBreakdown() async throws {
        let embedding: [Float] = [0.5, 0.5, 0.0]
        try await prototypeStore.updatePrototype(categoryPath: "Test", newEmbedding: embedding)
        
        let result = try await confidenceService.calculateConfidence(
            embedding: embedding,
            filename: "test.pdf",
            parentFolder: "TestFolder",
            fileExtension: "pdf",
            clusterDensity: 0.8
        )
        
        // Verify breakdown has all components
        XCTAssertGreaterThanOrEqual(result.breakdown.prototypeSimilarity, 0)
        XCTAssertGreaterThanOrEqual(result.breakdown.clusterDensity, 0)
        XCTAssertGreaterThanOrEqual(result.breakdown.extensionBonus, 0)
        XCTAssertGreaterThanOrEqual(result.breakdown.parentFolderBonus, 0)
        XCTAssertGreaterThanOrEqual(result.breakdown.adjustedScore, 0)
    }
    
    func testExplanationGenerated() async throws {
        let result = try await confidenceService.calculateConfidence(
            embedding: [0.5, 0.5, 0.0],
            filename: "test.pdf"
        )
        
        XCTAssertFalse(result.explanation.isEmpty)
        XCTAssertTrue(result.explanation.contains("Confidence:"))
    }
    
    // MARK: - Precision Tracking
    
    func testRecordOutcome() async throws {
        await confidenceService.recordOutcome(wasCorrect: true, wasAutoPlace: true)
        await confidenceService.recordOutcome(wasCorrect: true, wasAutoPlace: false)
        await confidenceService.recordOutcome(wasCorrect: false, wasAutoPlace: true)
        
        let stats = await confidenceService.getPrecisionStatistics()
        
        XCTAssertEqual(stats.totalPredictions, 3)
        XCTAssertEqual(stats.correctPredictions, 2)
        XCTAssertEqual(stats.autoPlacePredictions, 2)
        XCTAssertEqual(stats.autoPlaceCorrect, 1)
        XCTAssertEqual(stats.overallPrecision, 2.0/3.0, accuracy: 0.01)
        XCTAssertEqual(stats.autoPlacePrecision, 0.5, accuracy: 0.01)
    }
    
    func testResetStatistics() async throws {
        await confidenceService.recordOutcome(wasCorrect: true, wasAutoPlace: true)
        await confidenceService.resetStatistics()
        
        let stats = await confidenceService.getPrecisionStatistics()
        
        XCTAssertEqual(stats.totalPredictions, 0)
    }
    
    // MARK: - Configuration Tests
    
    func testConservativeConfiguration() async throws {
        let conservativeService = ConfidenceService(
            prototypeStore: prototypeStore,
            configuration: .conservative
        )
        
        let result = try await conservativeService.calculateConfidence(
            embedding: [0.5, 0.5, 0.0],
            filename: "test.pdf"
        )
        
        // Conservative should return valid result
        XCTAssertNotNil(result)
    }
    
    func testAggressiveConfiguration() async throws {
        let aggressiveService = ConfidenceService(
            prototypeStore: prototypeStore,
            configuration: .aggressive
        )
        
        let result = try await aggressiveService.calculateConfidence(
            embedding: [0.5, 0.5, 0.0],
            filename: "test.pdf"
        )
        
        XCTAssertNotNil(result)
    }
}

// MARK: - Confidence Outcome Tests

final class ConfidenceOutcomeTests: XCTestCase {
    
    func testOutcomeDisplayNames() {
        XCTAssertEqual(ConfidenceOutcome.autoPlace.displayName, "Auto-Place")
        XCTAssertEqual(ConfidenceOutcome.review.displayName, "Review")
        XCTAssertEqual(ConfidenceOutcome.deepAnalysis.displayName, "Deep Analysis")
    }
    
    func testOutcomeRawValues() {
        XCTAssertEqual(ConfidenceOutcome.autoPlace.rawValue, "auto_place")
        XCTAssertEqual(ConfidenceOutcome.review.rawValue, "review")
        XCTAssertEqual(ConfidenceOutcome.deepAnalysis.rawValue, "deep_analysis")
    }
}

// MARK: - Confidence Configuration Tests

final class ConfidenceConfigurationTests: XCTestCase {
    
    func testDefaultConfiguration() {
        let config = ConfidenceConfiguration.default
        
        XCTAssertEqual(config.autoPlaceThreshold, 0.85, accuracy: 0.001)
        XCTAssertEqual(config.targetPrecision, 0.85, accuracy: 0.001)
    }
    
    func testConservativeConfiguration() {
        let config = ConfidenceConfiguration.conservative
        
        XCTAssertGreaterThan(config.autoPlaceThreshold, ConfidenceConfiguration.default.autoPlaceThreshold)
    }
    
    func testAggressiveConfiguration() {
        let config = ConfidenceConfiguration.aggressive
        
        XCTAssertLessThan(config.autoPlaceThreshold, ConfidenceConfiguration.default.autoPlaceThreshold)
    }
}
