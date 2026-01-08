// MARK: - LLM Provider Tests
// Unit tests for the LLM abstraction layer

import Testing
import Foundation
@testable import SortAI

// MARK: - LLM Options Tests

@Suite("LLMOptions Tests")
struct LLMOptionsTests {
    
    @Test("Default options")
    func testDefaultOptions() {
        let options = LLMOptions.default(model: "llama3.2")
        
        #expect(options.model == "llama3.2")
        #expect(options.temperature == 0.3)
        #expect(options.maxTokens == 2000)
        #expect(options.topP == 0.9)
    }
    
    @Test("Creative options")
    func testCreativeOptions() {
        let options = LLMOptions.creative(model: "mistral")
        
        #expect(options.model == "mistral")
        #expect(options.temperature == 0.8)
        #expect(options.topP == 0.95)
    }
    
    @Test("Deterministic options")
    func testDeterministicOptions() {
        let options = LLMOptions.deterministic(model: "llama3.2")
        
        #expect(options.temperature == 0.0)
        #expect(options.topP == 1.0)
    }
    
    @Test("Custom options")
    func testCustomOptions() {
        let options = LLMOptions(
            model: "custom-model",
            temperature: 0.5,
            maxTokens: 4096,
            topP: 0.85,
            stopSequences: ["END"]
        )
        
        #expect(options.model == "custom-model")
        #expect(options.temperature == 0.5)
        #expect(options.maxTokens == 4096)
        #expect(options.topP == 0.85)
        #expect(options.stopSequences == ["END"])
    }
    
    @Test("Options equality")
    func testOptionsEquality() {
        let options1 = LLMOptions.default(model: "test")
        let options2 = LLMOptions.default(model: "test")
        let options3 = LLMOptions.creative(model: "test")
        
        #expect(options1 == options2)
        #expect(options1 != options3)
    }
}

// MARK: - LLM Model Tests

@Suite("LLMModel Tests")
struct LLMModelTests {
    
    @Test("Model properties")
    func testModelProperties() {
        let model = LLMModel(
            id: "llama3.2:latest",
            name: "Llama 3.2",
            size: 4_000_000_000, // 4 GB
            contextLength: 8192,
            capabilities: [.chat, .completion, .embedding]
        )
        
        #expect(model.id == "llama3.2:latest")
        #expect(model.name == "Llama 3.2")
        #expect(model.contextLength == 8192)
        #expect(model.capabilities.contains(.chat))
        #expect(model.capabilities.contains(.embedding))
    }
    
    @Test("Model capabilities")
    func testModelCapabilities() {
        let allCapabilities: [LLMModel.LLMCapability] = [
            .chat, .completion, .embedding, .vision, .codeGeneration, .jsonMode
        ]
        
        for capability in allCapabilities {
            #expect(!capability.rawValue.isEmpty)
        }
    }
}

// MARK: - LLM Error Tests

@Suite("LLMError Tests")
struct LLMErrorTests {
    
    @Test("Error descriptions")
    func testErrorDescriptions() {
        let errors: [LLMError] = [
            .modelNotFound("test"),
            .connectionFailed("timeout"),
            .rateLimited(retryAfter: 60),
            .invalidResponse("bad json"),
            .timeout,
            .providerUnavailable("ollama"),
            .contextLengthExceeded(maxTokens: 4096),
            .embeddingFailed("dimension mismatch"),
            .jsonParsingFailed("invalid syntax")
        ]
        
        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
        }
    }
    
    @Test("Rate limited error with retry")
    func testRateLimitedError() {
        let error = LLMError.rateLimited(retryAfter: 30)
        
        #expect(error.errorDescription?.contains("30") == true)
    }
    
    @Test("Context length error")
    func testContextLengthError() {
        let error = LLMError.contextLengthExceeded(maxTokens: 8192)
        
        #expect(error.errorDescription?.contains("8192") == true)
    }
}

// MARK: - LLM Response Tests

@Suite("LLMResponse Tests")
struct LLMResponseTests {
    
    @Test("Response creation")
    func testResponseCreation() {
        let usage = LLMUsage(promptTokens: 100, completionTokens: 50, totalTokens: 150)
        let response = LLMResponse(
            text: "Hello, world!",
            model: "llama3.2",
            usage: usage,
            finishReason: .stop
        )
        
        #expect(response.text == "Hello, world!")
        #expect(response.model == "llama3.2")
        #expect(response.finishReason == .stop)
        #expect(response.usage?.totalTokens == 150)
    }
    
    @Test("Finish reasons")
    func testFinishReasons() {
        let reasons: [LLMResponse.FinishReason] = [.stop, .length, .contentFilter, .error]
        
        for reason in reasons {
            #expect(!reason.rawValue.isEmpty)
        }
    }
}

// MARK: - LLM Usage Tests

@Suite("LLMUsage Tests")
struct LLMUsageTests {
    
    @Test("Usage calculation")
    func testUsageCalculation() {
        let usage = LLMUsage(promptTokens: 100, completionTokens: 200, totalTokens: 300)
        
        #expect(usage.promptTokens == 100)
        #expect(usage.completionTokens == 200)
        #expect(usage.totalTokens == 300)
    }
}

// MARK: - Category Assignment Tests

@Suite("CategoryAssignment Tests")
struct CategoryAssignmentTests {
    
    @Test("Assignment creation")
    func testAssignmentCreation() {
        let assignment = CategoryAssignment(
            filename: "test_document.pdf",
            categoryPath: ["Work", "Projects", "2024"],
            confidence: 0.95,
            rationale: "Contains work-related content"
        )
        
        #expect(assignment.filename == "test_document.pdf")
        #expect(assignment.categoryPath.count == 3)
        #expect(assignment.confidence == 0.95)
        #expect(assignment.pathString == "Work / Projects / 2024")
    }
    
    @Test("Assignment with alternatives")
    func testAssignmentWithAlternatives() {
        let assignment = CategoryAssignment(
            filename: "photo.jpg",
            categoryPath: ["Personal", "Photos"],
            confidence: 0.75,
            alternativePaths: [["Work", "Marketing"], ["Archive", "2023"]],
            needsDeepAnalysis: true
        )
        
        #expect(assignment.alternativePaths.count == 2)
        #expect(assignment.needsDeepAnalysis)
    }
}

// MARK: - Taxonomy Refinement Tests

@Suite("TaxonomyRefinement Tests")
struct TaxonomyRefinementTests {
    
    @Test("Refinement types")
    func testRefinementTypes() {
        let types: [TaxonomyRefinement.RefinementType] = [
            .merge, .split, .rename, .move, .delete, .create
        ]
        
        for type in types {
            #expect(!type.rawValue.isEmpty)
        }
    }
    
    @Test("Refinement creation")
    func testRefinementCreation() {
        let refinement = TaxonomyRefinement(
            type: .merge,
            targetPath: ["Work", "Projects"],
            suggestedChange: "Merge with 'Work/Tasks'",
            reason: "Similar content types",
            confidence: 0.85
        )
        
        #expect(refinement.type == .merge)
        #expect(refinement.targetPath.count == 2)
        #expect(refinement.confidence == 0.85)
    }
}

// MARK: - Provider Registry Tests

@Suite("LLMProviderRegistry Tests")
struct LLMProviderRegistryTests {
    
    @Test("Shared instance exists")
    func testSharedInstanceExists() async {
        let registry = LLMProviderRegistry.shared
        
        // Verify we can access the shared instance
        let providers = await registry.allProviders()
        #expect(providers is [String])
    }
}

// MARK: - Ollama Provider Tests

@Suite("OllamaProvider Tests")
struct OllamaProviderTests {
    
    @Test("Provider identifier")
    func testProviderIdentifier() async {
        let provider = OllamaProvider()
        
        // Can access nonisolated property
        #expect(provider.identifier == "ollama")
    }
    
    @Test("Provider is available check")
    func testProviderIsAvailableCheck() async {
        let provider = OllamaProvider()
        
        // This may return false if Ollama isn't running
        _ = await provider.isAvailable()
        // Just verify it doesn't crash
    }
}
