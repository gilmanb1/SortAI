// MARK: - Configuration Tests
// Tests for unified AppConfiguration and ConfigurationManager

import XCTest
@testable import SortAI

// MARK: - AppConfiguration Tests

final class AppConfigurationTests: XCTestCase {
    
    // MARK: - Default Values
    
    func testDefaultConfigurationHasCorrectValues() {
        let config = AppConfiguration.default
        
        // Verify version (v2 = Apple Intelligence support)
        XCTAssertEqual(config.version, AppConfiguration.currentVersion)
        
        // Verify Ollama defaults
        XCTAssertEqual(config.ollama.host, "http://127.0.0.1:11434")
        XCTAssertEqual(config.ollama.documentModel, OllamaConfiguration.defaultModel)
        XCTAssertEqual(config.ollama.temperature, 0.3)
        XCTAssertEqual(config.ollama.maxTokens, 1000)
        XCTAssertEqual(config.ollama.timeout, 60.0)
        
        // Verify memory defaults
        XCTAssertEqual(config.memory.embeddingDimensions, 384)
        XCTAssertEqual(config.memory.similarityThreshold, 0.85)
        XCTAssertTrue(config.memory.useMemoryFirst)
        
        // Verify feedback defaults
        XCTAssertEqual(config.feedback.autoAcceptThreshold, 0.85)
        XCTAssertEqual(config.feedback.reviewThreshold, 0.5)
    }
    
    func testTestingConfigurationHasCorrectValues() {
        let config = AppConfiguration.testing
        
        XCTAssertEqual(config.environment, .testing)
        XCTAssertTrue(config.persistence.inMemory)
        XCTAssertEqual(config.audio.targetSpeechDuration, 45.0) // fast config
    }
    
    // MARK: - Validation
    
    func testValidConfigurationPassesValidation() {
        let config = AppConfiguration.default
        let errors = config.validate()
        XCTAssertTrue(errors.isEmpty, "Default configuration should be valid")
        XCTAssertTrue(config.isValid)
    }
    
    func testInvalidTemperatureFailsValidation() {
        var config = AppConfiguration.default
        config.ollama.temperature = -0.5
        
        let errors = config.validate()
        XCTAssertFalse(errors.isEmpty)
        XCTAssertFalse(config.isValid)
        
        XCTAssertTrue(errors.contains { error in
            if case .invalidValue(let key, _) = error {
                return key == "ollama.temperature"
            }
            return false
        })
    }
    
    func testInvalidMaxTokensFailsValidation() {
        var config = AppConfiguration.default
        config.ollama.maxTokens = 0
        
        let errors = config.validate()
        XCTAssertTrue(errors.contains { error in
            if case .invalidValue(let key, _) = error {
                return key == "ollama.maxTokens"
            }
            return false
        })
    }
    
    func testInvalidEmbeddingDimensionsFailsValidation() {
        var config = AppConfiguration.default
        config.memory.embeddingDimensions = 32 // Too small
        
        let errors = config.validate()
        XCTAssertTrue(errors.contains { error in
            if case .invalidValue(let key, _) = error {
                return key == "memory.embeddingDimensions"
            }
            return false
        })
    }
    
    func testInvalidThresholdsFailValidation() {
        var config = AppConfiguration.default
        config.feedback.autoAcceptThreshold = 0.3 // Less than reviewThreshold
        config.feedback.reviewThreshold = 0.5
        
        let errors = config.validate()
        XCTAssertTrue(errors.contains { error in
            if case .invalidValue(let key, _) = error {
                return key == "feedback.autoAcceptThreshold"
            }
            return false
        })
    }
    
    // MARK: - Codable
    
    func testConfigurationEncodeDecode() throws {
        let original = AppConfiguration.default
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AppConfiguration.self, from: data)
        
        XCTAssertEqual(original, decoded)
    }
    
    func testConfigurationEncodesAsReadableJSON() throws {
        let config = AppConfiguration.default
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let json = String(data: data, encoding: .utf8)!
        
        // Verify key sections are present
        XCTAssertTrue(json.contains("\"ollama\""))
        XCTAssertTrue(json.contains("\"memory\""))
        XCTAssertTrue(json.contains("\"feedback\""))
        XCTAssertTrue(json.contains("\"persistence\""))
    }
    
    func testPartialConfigurationDecoding() throws {
        // JSON with only some fields - should fail because all fields are required
        let partialJSON = """
        {
            "version": 1,
            "environment": "development"
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(AppConfiguration.self, from: partialJSON))
    }
    
    // MARK: - UserDefaults Migration
    
    func testFromUserDefaultsWithEmptyDefaults() {
        // Clear any existing values
        let defaults = UserDefaults.standard
        let keys = ["ollamaHost", "documentModel", "videoModel", "imageModel", "audioModel", 
                    "embeddingModel", "embeddingDimensions", "defaultOrganizationMode", "lastOutputFolder"]
        keys.forEach { defaults.removeObject(forKey: $0) }
        
        let config = AppConfiguration.fromUserDefaults()
        
        // Should have default values
        XCTAssertEqual(config.ollama.host, "http://127.0.0.1:11434")
        XCTAssertEqual(config.ollama.documentModel, OllamaConfiguration.defaultModel)
    }
    
    func testFromUserDefaultsWithSavedValues() {
        let defaults = UserDefaults.standard
        defaults.set("http://custom-host:11434", forKey: "ollamaHost")
        defaults.set("custom-model", forKey: "documentModel")
        defaults.set(512, forKey: "embeddingDimensions")
        
        defer {
            // Clean up
            defaults.removeObject(forKey: "ollamaHost")
            defaults.removeObject(forKey: "documentModel")
            defaults.removeObject(forKey: "embeddingDimensions")
        }
        
        let config = AppConfiguration.fromUserDefaults()
        
        XCTAssertEqual(config.ollama.host, "http://custom-host:11434")
        XCTAssertEqual(config.ollama.documentModel, "custom-model")
        XCTAssertEqual(config.memory.embeddingDimensions, 512)
    }
    
    func testSyncToUserDefaults() {
        var config = AppConfiguration.default
        config.ollama.host = "http://synced-host:11434"
        config.memory.embeddingDimensions = 768
        
        config.syncToUserDefaults()
        
        let defaults = UserDefaults.standard
        XCTAssertEqual(defaults.string(forKey: "ollamaHost"), "http://synced-host:11434")
        XCTAssertEqual(defaults.integer(forKey: "embeddingDimensions"), 768)
        
        // Clean up
        defaults.removeObject(forKey: "ollamaHost")
        defaults.removeObject(forKey: "embeddingDimensions")
    }
    
    // MARK: - Bridge Types
    
    func testToBrainConfiguration() {
        var config = AppConfiguration.default
        config.ollama.host = "http://test:11434"
        config.ollama.documentModel = "test-model"
        config.ollama.temperature = 0.7
        
        let brainConfig = config.toBrainConfiguration()
        
        XCTAssertEqual(brainConfig.host, "http://test:11434")
        XCTAssertEqual(brainConfig.documentModel, "test-model")
        XCTAssertEqual(brainConfig.temperature, 0.7)
    }
    
    func testToDatabaseConfiguration() {
        // Default config
        var config = AppConfiguration.default
        let dbConfig1 = config.toDatabaseConfiguration()
        XCTAssertFalse(dbConfig1.inMemory)
        
        // In-memory config
        config.persistence.inMemory = true
        let dbConfig2 = config.toDatabaseConfiguration()
        XCTAssertTrue(dbConfig2.inMemory)
        
        // Custom path config
        config.persistence.inMemory = false
        config.persistence.databasePath = "/custom/path.sqlite"
        let dbConfig3 = config.toDatabaseConfiguration()
        XCTAssertEqual(dbConfig3.path, "/custom/path.sqlite")
    }
    
    func testToAudioSamplerConfig() {
        var config = AppConfiguration.default
        config.audio.targetSpeechDuration = 120.0
        config.audio.speechEnergyThreshold = 0.05
        
        let audioConfig = config.toAudioSamplerConfig()
        
        XCTAssertEqual(audioConfig.targetSpeechDuration, 120.0)
        XCTAssertEqual(audioConfig.speechEnergyThreshold, 0.05)
    }
}

// MARK: - OllamaConfiguration Tests

final class OllamaConfigurationTests: XCTestCase {
    
    func testModelForMediaKind() {
        var config = OllamaConfiguration.default
        config.documentModel = "doc-model"
        config.videoModel = "video-model"
        config.imageModel = "image-model"
        config.audioModel = "audio-model"
        
        XCTAssertEqual(config.model(for: .document), "doc-model")
        XCTAssertEqual(config.model(for: .video), "video-model")
        XCTAssertEqual(config.model(for: .image), "image-model")
        XCTAssertEqual(config.model(for: .audio), "audio-model")
        XCTAssertEqual(config.model(for: .unknown), "doc-model") // Falls back to document
    }
    
    func testUniformConfiguration() {
        let config = OllamaConfiguration.uniform(host: "http://test:11434", model: "unified-model")
        
        XCTAssertEqual(config.host, "http://test:11434")
        XCTAssertEqual(config.documentModel, "unified-model")
        XCTAssertEqual(config.videoModel, "unified-model")
        XCTAssertEqual(config.imageModel, "unified-model")
        XCTAssertEqual(config.audioModel, "unified-model")
        XCTAssertEqual(config.embeddingModel, "unified-model")
    }
}

// MARK: - Configuration Domain Tests

final class ConfigurationDomainTests: XCTestCase {
    
    func testMemoryConfigurationDefaults() {
        let config = MemoryConfiguration.default
        
        XCTAssertEqual(config.embeddingDimensions, 384)
        XCTAssertEqual(config.similarityThreshold, 0.85)
        XCTAssertTrue(config.useMemoryFirst)
        XCTAssertEqual(config.maxPatterns, 10000)
        XCTAssertEqual(config.minPatternConfidence, 0.5)
    }
    
    func testKnowledgeGraphConfigurationDefaults() {
        let config = KnowledgeGraphConfiguration.default
        
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.maxSuggestions, 5)
        XCTAssertEqual(config.minRelationshipWeight, 0.1)
        XCTAssertTrue(config.learnFromFeedback)
    }
    
    func testFeedbackConfigurationDefaults() {
        let config = FeedbackConfiguration.default
        
        XCTAssertEqual(config.autoAcceptThreshold, 0.85)
        XCTAssertEqual(config.reviewThreshold, 0.5)
        XCTAssertEqual(config.maxPendingItems, 1000)
        XCTAssertEqual(config.retentionDays, 90)
    }
    
    func testAudioConfigurationDefaults() {
        let config = AudioConfiguration.default
        
        XCTAssertEqual(config.targetSpeechDuration, 90.0)
        XCTAssertEqual(config.outputSampleRate, 16000.0)
        XCTAssertEqual(config.maxScanDuration, 600.0)
    }
    
    func testAudioConfigurationFast() {
        let config = AudioConfiguration.fast
        
        XCTAssertEqual(config.targetSpeechDuration, 45.0)
        XCTAssertEqual(config.maxScanDuration, 300.0)
    }
    
    func testPersistenceConfigurationDefaults() {
        let config = PersistenceConfiguration.default
        
        XCTAssertNil(config.databasePath)
        XCTAssertFalse(config.inMemory)
        XCTAssertTrue(config.enableWAL)
        XCTAssertTrue(config.enableForeignKeys)
    }
    
    func testPersistenceConfigurationTesting() {
        let config = PersistenceConfiguration.testing
        
        XCTAssertEqual(config.databasePath, ":memory:")
        XCTAssertTrue(config.inMemory)
        XCTAssertFalse(config.enableWAL)
    }
    
    func testOrganizationConfigurationDefaults() {
        let config = OrganizationConfiguration.default
        
        XCTAssertEqual(config.defaultMode, .copy)
        XCTAssertFalse(config.createMetadataFiles)
        XCTAssertTrue(config.preserveTimestamps)
        XCTAssertEqual(config.maxFilenameLength, 200)
    }
    
    func testProcessingConfigurationDefaults() {
        let config = ProcessingConfiguration.default
        
        XCTAssertEqual(config.maxConcurrentTasks, 4)
        XCTAssertEqual(config.batchSize, 10)
        XCTAssertTrue(config.enableCache)
        XCTAssertEqual(config.cacheExpirationHours, 24)
    }
}

// MARK: - AppEnvironment Tests

final class AppEnvironmentTests: XCTestCase {
    
    func testAllEnvironmentCases() {
        let allCases = AppEnvironment.allCases
        
        XCTAssertTrue(allCases.contains(.development))
        XCTAssertTrue(allCases.contains(.staging))
        XCTAssertTrue(allCases.contains(.production))
        XCTAssertTrue(allCases.contains(.testing))
    }
    
    func testEnvironmentCodable() throws {
        let environments: [AppEnvironment] = [.development, .staging, .production, .testing]
        
        for env in environments {
            let encoder = JSONEncoder()
            let data = try encoder.encode(env)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(AppEnvironment.self, from: data)
            
            XCTAssertEqual(env, decoded)
        }
    }
}

// MARK: - ConfigurationError Tests

final class ConfigurationErrorTests: XCTestCase {
    
    func testErrorDescriptions() {
        let errors: [ConfigurationError] = [
            .fileNotFound("/path/to/config"),
            .invalidJSON("Unexpected token"),
            .invalidValue("test.key", "Must be positive"),
            .migrationFailed("Version incompatible"),
            .saveFailed("Permission denied")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
    
    func testErrorEquality() {
        let error1 = ConfigurationError.invalidValue("key1", "reason1")
        let error2 = ConfigurationError.invalidValue("key1", "reason1")
        let error3 = ConfigurationError.invalidValue("key2", "reason1")
        
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }
}

// MARK: - ConfigurationManager Tests

@MainActor
final class ConfigurationManagerTests: XCTestCase {
    
    var manager: ConfigurationManager!
    var tempConfigPath: URL!
    
    override func setUp() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        tempConfigPath = tempDir.appendingPathComponent("test-config-\(UUID().uuidString).json")
        manager = ConfigurationManager(configPath: tempConfigPath)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempConfigPath)
        manager = nil
    }
    
    func testInitialConfigurationIsDefault() {
        // When loading from non-existent file, should use defaults
        XCTAssertEqual(manager.config.version, AppConfiguration.currentVersion)
        XCTAssertFalse(manager.hasUnsavedChanges)
    }
    
    func testSaveAndReload() throws {
        // Modify config
        manager.update { config in
            config.ollama.host = "http://saved-host:11434"
        }
        
        XCTAssertTrue(manager.hasUnsavedChanges)
        
        // Save
        try manager.save()
        XCTAssertFalse(manager.hasUnsavedChanges)
        
        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempConfigPath.path))
        
        // Create new manager and verify it loads saved config
        let newManager = ConfigurationManager(configPath: tempConfigPath)
        XCTAssertEqual(newManager.config.ollama.host, "http://saved-host:11434")
    }
    
    func testUpdateValidation() {
        // Try to set invalid value
        manager.update { config in
            config.ollama.temperature = 5.0 // Invalid: > 2.0
        }
        
        // Should have error and config unchanged
        XCTAssertNotNil(manager.lastError)
        XCTAssertEqual(manager.config.ollama.temperature, 0.3) // Still default
    }
    
    func testUpdateOllamaConvenience() {
        manager.updateOllama { ollama in
            ollama.host = "http://new-host:11434"
            ollama.documentModel = "new-model"
        }
        
        XCTAssertEqual(manager.config.ollama.host, "http://new-host:11434")
        XCTAssertEqual(manager.config.ollama.documentModel, "new-model")
        XCTAssertTrue(manager.hasUnsavedChanges)
    }
    
    func testUpdateMemoryConvenience() {
        manager.updateMemory { memory in
            memory.embeddingDimensions = 512
            memory.similarityThreshold = 0.9
        }
        
        XCTAssertEqual(manager.config.memory.embeddingDimensions, 512)
        XCTAssertEqual(manager.config.memory.similarityThreshold, 0.9)
    }
    
    func testReset() {
        // Modify config
        manager.update { config in
            config.ollama.host = "http://modified-host:11434"
        }
        
        // Reset
        manager.reset()
        
        XCTAssertEqual(manager.config.ollama.host, "http://127.0.0.1:11434")
        XCTAssertTrue(manager.hasUnsavedChanges)
    }
    
    func testConvenienceAccessors() {
        XCTAssertEqual(manager.ollama.host, manager.config.ollama.host)
        XCTAssertEqual(manager.memory.embeddingDimensions, manager.config.memory.embeddingDimensions)
        XCTAssertEqual(manager.feedback.autoAcceptThreshold, manager.config.feedback.autoAcceptThreshold)
        XCTAssertEqual(manager.audio.targetSpeechDuration, manager.config.audio.targetSpeechDuration)
        XCTAssertEqual(manager.persistence.inMemory, manager.config.persistence.inMemory)
        XCTAssertEqual(manager.organization.defaultMode, manager.config.organization.defaultMode)
        XCTAssertEqual(manager.processing.maxConcurrentTasks, manager.config.processing.maxConcurrentTasks)
    }
    
    func testChangeHandlers() {
        var callCount = 0
        var lastConfig: AppConfiguration?
        
        manager.onConfigurationChange { config in
            callCount += 1
            lastConfig = config
        }
        
        manager.update { config in
            config.ollama.host = "http://changed:11434"
        }
        
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(lastConfig?.ollama.host, "http://changed:11434")
    }
    
    func testExportImport() throws {
        // Set custom values
        manager.update { config in
            config.ollama.host = "http://export-test:11434"
            config.memory.embeddingDimensions = 768
        }
        
        // Export
        let exportPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: exportPath) }
        
        try manager.export(to: exportPath)
        
        // Reset and import
        manager.reset()
        XCTAssertEqual(manager.config.ollama.host, "http://127.0.0.1:11434")
        
        try manager.import(from: exportPath)
        
        XCTAssertEqual(manager.config.ollama.host, "http://export-test:11434")
        XCTAssertEqual(manager.config.memory.embeddingDimensions, 768)
    }
    
    func testImportInvalidFileThrows() {
        let invalidPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).json")
        
        XCTAssertThrowsError(try manager.import(from: invalidPath))
    }
    
    func testImportInvalidConfigThrows() throws {
        // Create file with invalid JSON
        let invalidPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: invalidPath) }
        
        try "{ invalid json }".write(to: invalidPath, atomically: true, encoding: .utf8)
        
        XCTAssertThrowsError(try manager.import(from: invalidPath))
    }
    
    func testForTesting() {
        let testManager = ConfigurationManager.forTesting()
        XCTAssertEqual(testManager.config.environment, .testing)
        XCTAssertTrue(testManager.config.persistence.inMemory)
    }
}

