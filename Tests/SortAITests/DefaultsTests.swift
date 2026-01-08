// MARK: - Defaults and Configuration Persistence Tests
// Tests for UserDefaults registration and configuration persistence

import XCTest
@testable import SortAI

final class DefaultsTests: XCTestCase {
    
    // MARK: - Default Model Tests
    
    func testDefaultModelIsDeepseekR1() {
        // The default model should be deepseek-r1:8b
        XCTAssertEqual(OllamaConfiguration.defaultModel, "deepseek-r1:8b")
    }
    
    func testDefaultOllamaConfigurationUsesDeepseekR1() {
        let config = OllamaConfiguration.default
        
        XCTAssertEqual(config.documentModel, "deepseek-r1:8b")
        XCTAssertEqual(config.videoModel, "deepseek-r1:8b")
        XCTAssertEqual(config.imageModel, "deepseek-r1:8b")
        XCTAssertEqual(config.audioModel, "deepseek-r1:8b")
        XCTAssertEqual(config.embeddingModel, "deepseek-r1:8b")
    }
    
    func testUniformConfigurationDefaultsToDeepseekR1() {
        // When no model is specified, uniform() should use deepseek-r1
        let config = OllamaConfiguration.uniform()
        
        XCTAssertEqual(config.documentModel, "deepseek-r1:8b")
        XCTAssertEqual(config.videoModel, "deepseek-r1:8b")
        XCTAssertEqual(config.imageModel, "deepseek-r1:8b")
        XCTAssertEqual(config.audioModel, "deepseek-r1:8b")
        XCTAssertEqual(config.embeddingModel, "deepseek-r1:8b")
    }
    
    func testUniformConfigurationAcceptsCustomModel() {
        let config = OllamaConfiguration.uniform(model: "custom-model")
        
        XCTAssertEqual(config.documentModel, "custom-model")
        XCTAssertEqual(config.videoModel, "custom-model")
        XCTAssertEqual(config.imageModel, "custom-model")
        XCTAssertEqual(config.audioModel, "custom-model")
        XCTAssertEqual(config.embeddingModel, "custom-model")
    }
    
    // MARK: - AppConfiguration Tests
    
    func testAppConfigurationDefaultUsesDeepseekR1() {
        let config = AppConfiguration.default
        let expectedModel = OllamaConfiguration.defaultModel
        
        XCTAssertEqual(config.ollama.documentModel, expectedModel)
        XCTAssertEqual(config.ollama.videoModel, expectedModel)
        XCTAssertEqual(config.ollama.imageModel, expectedModel)
        XCTAssertEqual(config.ollama.audioModel, expectedModel)
        XCTAssertEqual(config.ollama.embeddingModel, expectedModel)
    }
    
    func testAppConfigurationTestingUsesDeepseekR1() {
        let config = AppConfiguration.testing
        let expectedModel = OllamaConfiguration.defaultModel
        
        // Testing config should also use the default model
        XCTAssertEqual(config.ollama.documentModel, expectedModel)
        XCTAssertEqual(config.ollama.videoModel, expectedModel)
    }
    
    // MARK: - SortAIDefaultsKey Tests
    
    func testDefaultsKeysAreDefined() {
        // Verify all key constants are non-empty strings
        XCTAssertFalse(SortAIDefaultsKey.ollamaHost.isEmpty)
        XCTAssertFalse(SortAIDefaultsKey.documentModel.isEmpty)
        XCTAssertFalse(SortAIDefaultsKey.videoModel.isEmpty)
        XCTAssertFalse(SortAIDefaultsKey.imageModel.isEmpty)
        XCTAssertFalse(SortAIDefaultsKey.audioModel.isEmpty)
        XCTAssertFalse(SortAIDefaultsKey.embeddingModel.isEmpty)
        XCTAssertFalse(SortAIDefaultsKey.embeddingDimensions.isEmpty)
        XCTAssertFalse(SortAIDefaultsKey.defaultOrganizationMode.isEmpty)
    }
    
    func testDefaultsKeysAreUnique() {
        let keys = [
            SortAIDefaultsKey.ollamaHost,
            SortAIDefaultsKey.documentModel,
            SortAIDefaultsKey.videoModel,
            SortAIDefaultsKey.imageModel,
            SortAIDefaultsKey.audioModel,
            SortAIDefaultsKey.embeddingModel,
            SortAIDefaultsKey.embeddingDimensions,
            SortAIDefaultsKey.defaultOrganizationMode,
            SortAIDefaultsKey.organizationDestination,
            SortAIDefaultsKey.enableDeepAnalysis,
            SortAIDefaultsKey.enableWatchMode,
        ]
        
        // All keys should be unique
        let uniqueKeys = Set(keys)
        XCTAssertEqual(keys.count, uniqueKeys.count, "Duplicate keys found")
    }
    
    // MARK: - SortAIDefaults Tests
    
    func testSortAIDefaultsDefaultModel() {
        XCTAssertEqual(SortAIDefaults.defaultModel, "deepseek-r1:8b")
    }
    
    func testRegisterDefaultsDoesNotCrash() {
        // Should not throw or crash
        SortAIDefaults.registerDefaults()
    }
    
    func testRegisteredDefaultsAreAccessible() {
        // Register defaults
        SortAIDefaults.registerDefaults()
        
        // Access the registered defaults
        let defaults = UserDefaults.standard
        
        // These should return the registered defaults (unless user has set custom values)
        let host = defaults.string(forKey: SortAIDefaultsKey.ollamaHost)
        XCTAssertNotNil(host)
        
        // Note: We can't assert exact values because UserDefaults might have
        // user-set values from previous runs. We just verify access doesn't fail.
    }
    
    // MARK: - Model Selection Tests
    
    func testModelForMediaKind() {
        let config = OllamaConfiguration.default
        let expectedModel = OllamaConfiguration.defaultModel
        
        XCTAssertEqual(config.model(for: .document), expectedModel)
        XCTAssertEqual(config.model(for: .video), expectedModel)
        XCTAssertEqual(config.model(for: .image), expectedModel)
        XCTAssertEqual(config.model(for: .audio), expectedModel)
        XCTAssertEqual(config.model(for: .unknown), expectedModel)
    }
    
    func testModelForMediaKindWithCustomConfig() {
        var config = OllamaConfiguration.default
        config.documentModel = "doc-model"
        config.videoModel = "video-model"
        config.imageModel = "image-model"
        config.audioModel = "audio-model"
        
        XCTAssertEqual(config.model(for: .document), "doc-model")
        XCTAssertEqual(config.model(for: .video), "video-model")
        XCTAssertEqual(config.model(for: .image), "image-model")
        XCTAssertEqual(config.model(for: .audio), "audio-model")
    }
    
    // MARK: - BrainConfiguration Bridge Tests
    
    func testToBrainConfigurationPreservesModels() {
        let appConfig = AppConfiguration.default
        let brainConfig = appConfig.toBrainConfiguration()
        let expectedModel = OllamaConfiguration.defaultModel
        
        XCTAssertEqual(brainConfig.documentModel, expectedModel)
        XCTAssertEqual(brainConfig.videoModel, expectedModel)
        XCTAssertEqual(brainConfig.imageModel, expectedModel)
        XCTAssertEqual(brainConfig.audioModel, expectedModel)
        XCTAssertEqual(brainConfig.embeddingModel, expectedModel)
    }
    
    // MARK: - Configuration Persistence Tests
    
    @MainActor
    func testConfigurationManagerUsesDeepseekR1() async {
        // Create a test configuration manager
        let manager = ConfigurationManager.forTesting()
        let expectedModel = OllamaConfiguration.defaultModel
        
        // The config should use the default model
        XCTAssertEqual(manager.config.ollama.documentModel, expectedModel)
        XCTAssertEqual(manager.config.ollama.videoModel, expectedModel)
        XCTAssertEqual(manager.config.ollama.imageModel, expectedModel)
        XCTAssertEqual(manager.config.ollama.audioModel, expectedModel)
        XCTAssertEqual(manager.config.ollama.embeddingModel, expectedModel)
    }
    
    @MainActor
    func testConfigurationUpdatePreservesModel() async {
        let manager = ConfigurationManager.forTesting()
        let expectedModel = OllamaConfiguration.defaultModel
        
        // Update the host but not the model
        manager.updateOllama { ollama in
            ollama.host = "http://custom-host:11434"
        }
        
        // Models should still be the default
        XCTAssertEqual(manager.config.ollama.host, "http://custom-host:11434")
        XCTAssertEqual(manager.config.ollama.documentModel, expectedModel)
    }
    
    @MainActor
    func testConfigurationSaveAndReload() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test-config-\(UUID().uuidString).json")
        let expectedModel = OllamaConfiguration.defaultModel
        
        // Create a fresh configuration and save it
        let freshConfig = AppConfiguration.default
        
        // Verify the fresh default config uses the default model
        XCTAssertEqual(freshConfig.ollama.documentModel, expectedModel)
        XCTAssertEqual(freshConfig.ollama.videoModel, expectedModel)
        
        // Encode and save the fresh config
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(freshConfig)
        try data.write(to: configPath, options: .atomic)
        
        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
        
        // Load the saved file and verify model persisted correctly
        let loadedData = try Data(contentsOf: configPath)
        let loadedConfig = try JSONDecoder().decode(AppConfiguration.self, from: loadedData)
        
        XCTAssertEqual(loadedConfig.ollama.documentModel, expectedModel)
        XCTAssertEqual(loadedConfig.ollama.videoModel, expectedModel)
        
        // Cleanup
        try? FileManager.default.removeItem(at: configPath)
    }
}

// MARK: - Integration Tests

final class DefaultsIntegrationTests: XCTestCase {
    
    @MainActor
    func testFullConfigurationFlow() async throws {
        // Register defaults first (as the app would)
        SortAIDefaults.registerDefaults()
        
        // Create a configuration manager
        let manager = ConfigurationManager.forTesting()
        
        // Verify initial state
        XCTAssertEqual(manager.config.ollama.documentModel, "deepseek-r1")
        
        // Simulate user changing models
        manager.updateOllama { ollama in
            ollama.documentModel = "custom-model"
        }
        
        // Verify change
        XCTAssertEqual(manager.config.ollama.documentModel, "custom-model")
        XCTAssertTrue(manager.hasUnsavedChanges)
        
        // Save changes
        try manager.save()
        XCTAssertFalse(manager.hasUnsavedChanges)
    }
    
    @MainActor
    func testConfigurationReset() async throws {
        let manager = ConfigurationManager.forTesting()
        
        // Change model
        manager.updateOllama { ollama in
            ollama.documentModel = "custom-model"
        }
        
        // Reset
        manager.resetOllama()
        
        // Should be back to default
        XCTAssertEqual(manager.config.ollama.documentModel, "deepseek-r1")
    }
}

