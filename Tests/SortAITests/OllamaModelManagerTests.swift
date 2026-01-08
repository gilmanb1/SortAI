// MARK: - Ollama Model Manager Tests
// Tests for model availability checking, matching, and fallback logic

import XCTest
@testable import SortAI

final class OllamaModelManagerTests: XCTestCase {
    
    // MARK: - Model Matching Tests
    
    func testFindMatchingModelExactMatch() async {
        let manager = OllamaModelManager()
        let availableModels = ["deepseek-r1:8b", "llama3.2:latest", "mistral:7b"]
        
        // Exact match
        let result = await manager.findMatchingModel("deepseek-r1:8b", in: availableModels)
        XCTAssertEqual(result, "deepseek-r1:8b")
    }
    
    func testFindMatchingModelPrefixWithTag() async {
        let manager = OllamaModelManager()
        let availableModels = ["deepseek-r1:8b", "deepseek-r1:70b", "llama3.2:latest"]
        
        // "deepseek-r1" should match "deepseek-r1:8b" (first match with colon)
        let result = await manager.findMatchingModel("deepseek-r1", in: availableModels)
        XCTAssertEqual(result, "deepseek-r1:8b")
    }
    
    func testFindMatchingModelCaseInsensitive() async {
        let manager = OllamaModelManager()
        let availableModels = ["DeepSeek-R1:8b", "Llama3.2:latest"]
        
        // Case-insensitive match
        let result = await manager.findMatchingModel("deepseek-r1:8b", in: availableModels)
        XCTAssertEqual(result, "DeepSeek-R1:8b")
    }
    
    func testFindMatchingModelPrefixMatch() async {
        let manager = OllamaModelManager()
        let availableModels = ["llama3.2:latest", "mistral:7b"]
        
        // "llama3.2" should match "llama3.2:latest"
        let result = await manager.findMatchingModel("llama3.2", in: availableModels)
        XCTAssertEqual(result, "llama3.2:latest")
    }
    
    func testFindMatchingModelNoMatch() async {
        let manager = OllamaModelManager()
        let availableModels = ["llama3.2:latest", "mistral:7b"]
        
        // No matching model
        let result = await manager.findMatchingModel("gpt-4", in: availableModels)
        XCTAssertNil(result)
    }
    
    func testFindMatchingModelEmptyList() async {
        let manager = OllamaModelManager()
        let availableModels: [String] = []
        
        let result = await manager.findMatchingModel("deepseek-r1", in: availableModels)
        XCTAssertNil(result)
    }
    
    func testFindMatchingModelWithSimilarNames() async {
        let manager = OllamaModelManager()
        let availableModels = ["deepseek-coder:6.7b", "deepseek-r1:8b", "deepseek-r1:70b"]
        
        // Should match the first one with colon prefix
        let result = await manager.findMatchingModel("deepseek-r1", in: availableModels)
        XCTAssertEqual(result, "deepseek-r1:8b")
    }
    
    // MARK: - Model Status Tests
    
    func testModelStatusEquality() {
        XCTAssertEqual(OllamaModelStatus.available, OllamaModelStatus.available)
        XCTAssertEqual(OllamaModelStatus.notFound, OllamaModelStatus.notFound)
        XCTAssertEqual(OllamaModelStatus.downloading(progress: 0.5), OllamaModelStatus.downloading(progress: 0.5))
        XCTAssertNotEqual(OllamaModelStatus.downloading(progress: 0.5), OllamaModelStatus.downloading(progress: 0.7))
        XCTAssertEqual(OllamaModelStatus.error("test"), OllamaModelStatus.error("test"))
    }
    
    // MARK: - Download Progress Tests
    
    func testModelDownloadProgressCalculation() {
        let progress = ModelDownloadProgress(
            modelName: "deepseek-r1:8b",
            status: "downloading",
            completed: 500_000_000,
            total: 1_000_000_000
        )
        
        XCTAssertEqual(progress.progress, 0.5)
        XCTAssertEqual(progress.progressPercent, 50)
        XCTAssertFalse(progress.isComplete)
    }
    
    func testModelDownloadProgressComplete() {
        let progress = ModelDownloadProgress(
            modelName: "deepseek-r1:8b",
            status: "success",
            completed: 1_000_000_000,
            total: 1_000_000_000
        )
        
        XCTAssertEqual(progress.progress, 1.0)
        XCTAssertEqual(progress.progressPercent, 100)
        XCTAssertTrue(progress.isComplete)
    }
    
    func testModelDownloadProgressZeroTotal() {
        let progress = ModelDownloadProgress(
            modelName: "test",
            status: "starting",
            completed: 0,
            total: 0
        )
        
        XCTAssertEqual(progress.progress, 0)
        XCTAssertEqual(progress.progressPercent, 0)
    }
    
    // MARK: - Error Tests
    
    func testOllamaModelErrors() {
        let errors: [OllamaModelError] = [
            .invalidHost("invalid-url"),
            .serverUnavailable,
            .modelNotFound("gpt-4"),
            .downloadFailed("timeout"),
            .noModelsAvailable,
            .serverError("500")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
    
    func testOllamaModelErrorEquality() {
        XCTAssertEqual(OllamaModelError.serverUnavailable, OllamaModelError.serverUnavailable)
        XCTAssertEqual(OllamaModelError.modelNotFound("test"), OllamaModelError.modelNotFound("test"))
        XCTAssertNotEqual(OllamaModelError.modelNotFound("a"), OllamaModelError.modelNotFound("b"))
    }
    
    // MARK: - Model Info Tests
    
    func testOllamaModelInfoDecoding() throws {
        let json = """
        {
            "modelfile": "FROM llama3.2",
            "parameters": "stop \\\"[INST]\\\"",
            "template": "{{ .Prompt }}",
            "details": {
                "parent_model": "llama3.2",
                "format": "gguf",
                "family": "llama",
                "families": ["llama"],
                "parameter_size": "8B",
                "quantization_level": "Q4_0"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let info = try JSONDecoder().decode(OllamaModelInfo.self, from: data)
        
        XCTAssertEqual(info.modelfile, "FROM llama3.2")
        XCTAssertEqual(info.details?.family, "llama")
        XCTAssertEqual(info.details?.parameterSize, "8B")
        XCTAssertEqual(info.details?.quantizationLevel, "Q4_0")
    }
    
    // MARK: - Integration Tests (require Ollama server)
    
    func testOllamaServerAvailabilityCheck() async {
        let manager = OllamaModelManager()
        
        // This test checks if Ollama is running - it's informational
        let isAvailable = await manager.isOllamaAvailable()
        if isAvailable {
            NSLog("✅ Ollama server is available")
        } else {
            NSLog("⚠️ Ollama server is not running (this is expected in CI)")
        }
        // Don't assert - this is environment-dependent
    }
    
    func testListModelsIfServerAvailable() async throws {
        let manager = OllamaModelManager()
        
        guard await manager.isOllamaAvailable() else {
            NSLog("⏭️ Skipping test - Ollama not available")
            throw XCTSkip("Ollama server not available")
        }
        
        let models = try await manager.listAvailableModels()
        XCTAssertFalse(models.isEmpty, "Should have at least one model installed")
        NSLog("📋 Available models: %@", models.joined(separator: ", "))
    }
    
    func testResolveModelIfServerAvailable() async throws {
        let manager = OllamaModelManager()
        
        guard await manager.isOllamaAvailable() else {
            NSLog("⏭️ Skipping test - Ollama not available")
            throw XCTSkip("Ollama server not available")
        }
        
        // Try to resolve the default model with fallbacks
        let resolved = try await manager.resolveModel(
            requested: OllamaConfiguration.defaultModel,
            fallbacks: ["llama3.2", "mistral"],
            autoDownload: false // Don't download in tests
        )
        
        XCTAssertFalse(resolved.isEmpty)
        NSLog("✅ Resolved model: %@", resolved)
    }
}

// MARK: - Model Setup Status Tests

final class ModelSetupStatusTests: XCTestCase {
    
    func testStatusIsReady() {
        XCTAssertTrue(ModelSetupStatus.ready.isReady)
        XCTAssertFalse(ModelSetupStatus.checking.isReady)
        XCTAssertFalse(ModelSetupStatus.downloading(progress: 0.5).isReady)
        XCTAssertFalse(ModelSetupStatus.error("test").isReady)
    }
    
    func testStatusIsDownloading() {
        XCTAssertFalse(ModelSetupStatus.ready.isDownloading)
        XCTAssertFalse(ModelSetupStatus.checking.isDownloading)
        XCTAssertTrue(ModelSetupStatus.downloading(progress: 0.5).isDownloading)
        XCTAssertFalse(ModelSetupStatus.error("test").isDownloading)
    }
    
    func testStatusDisplayText() {
        XCTAssertEqual(ModelSetupStatus.checking.displayText, "Checking model availability...")
        XCTAssertEqual(ModelSetupStatus.downloading(progress: 0.5).displayText, "Downloading model: 50%")
        XCTAssertEqual(ModelSetupStatus.ready.displayText, "Ready")
        XCTAssertTrue(ModelSetupStatus.error("Network error").displayText.contains("Network error"))
    }
    
    func testStatusEquality() {
        XCTAssertEqual(ModelSetupStatus.ready, ModelSetupStatus.ready)
        XCTAssertEqual(ModelSetupStatus.checking, ModelSetupStatus.checking)
        XCTAssertEqual(ModelSetupStatus.downloading(progress: 0.5), ModelSetupStatus.downloading(progress: 0.5))
        XCTAssertNotEqual(ModelSetupStatus.downloading(progress: 0.5), ModelSetupStatus.downloading(progress: 0.7))
        XCTAssertEqual(ModelSetupStatus.error("a"), ModelSetupStatus.error("a"))
        XCTAssertNotEqual(ModelSetupStatus.error("a"), ModelSetupStatus.error("b"))
    }
}

