// MARK: - LLM Provider Protocol
// Abstract interface for Large Language Model providers
// Enables switching between Ollama, OpenAI, Anthropic, etc.

import Foundation

// MARK: - LLM Provider Protocol

/// Protocol defining the interface for LLM providers
/// Implementations can wrap Ollama, OpenAI, Anthropic, or any other LLM service
protocol LLMProvider: Actor, Sendable {
    
    /// Provider identifier (e.g., "ollama", "openai", "anthropic")
    nonisolated var identifier: String { get }
    
    /// Check if the provider is available and ready
    func isAvailable() async -> Bool
    
    /// Generate a completion for the given prompt
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options (temperature, max tokens, etc.)
    /// - Returns: The generated text response
    func complete(prompt: String, options: LLMOptions) async throws -> String
    
    /// Generate a JSON-structured completion
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options
    /// - Returns: The generated JSON string
    func completeJSON(prompt: String, options: LLMOptions) async throws -> String
    
    /// Generate embeddings for text
    /// - Parameter text: The text to embed
    /// - Returns: Vector embedding
    func embed(text: String) async throws -> [Float]
    
    /// List available models
    func availableModels() async throws -> [LLMModel]
    
    /// Warm up the specified model (pre-load into memory)
    func warmup(model: String) async
}

// MARK: - LLM Options

/// Configuration options for LLM generation
struct LLMOptions: Sendable, Equatable {
    let model: String
    let temperature: Double
    let maxTokens: Int
    let topP: Double?
    let stopSequences: [String]?
    
    static func `default`(model: String) -> LLMOptions {
        LLMOptions(
            model: model,
            temperature: 0.3,
            maxTokens: 2000,
            topP: 0.9,
            stopSequences: nil
        )
    }
    
    static func creative(model: String) -> LLMOptions {
        LLMOptions(
            model: model,
            temperature: 0.8,
            maxTokens: 2000,
            topP: 0.95,
            stopSequences: nil
        )
    }
    
    static func deterministic(model: String) -> LLMOptions {
        LLMOptions(
            model: model,
            temperature: 0.0,
            maxTokens: 1000,
            topP: 1.0,
            stopSequences: nil
        )
    }
}

// MARK: - LLM Model

/// Represents an available LLM model
struct LLMModel: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let size: Int64?  // Size in bytes
    let contextLength: Int?
    let capabilities: Set<LLMCapability>
    
    enum LLMCapability: String, Sendable {
        case chat
        case completion
        case embedding
        case vision
        case codeGeneration
        case jsonMode
    }
}

// MARK: - LLM Errors

enum LLMError: LocalizedError {
    case providerUnavailable(String)
    case modelNotFound(String)
    case connectionFailed(String)
    case invalidResponse(String)
    case rateLimited(retryAfter: TimeInterval?)
    case contextLengthExceeded(maxTokens: Int)
    case timeout
    case embeddingFailed(String)
    case jsonParsingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let provider):
            return "LLM provider '\(provider)' is not available"
        case .modelNotFound(let model):
            return "Model '\(model)' not found"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .invalidResponse(let reason):
            return "Invalid response: \(reason)"
        case .rateLimited(let retryAfter):
            if let delay = retryAfter {
                return "Rate limited. Retry after \(Int(delay)) seconds"
            }
            return "Rate limited"
        case .contextLengthExceeded(let maxTokens):
            return "Context length exceeded. Maximum: \(maxTokens) tokens"
        case .timeout:
            return "Request timed out"
        case .embeddingFailed(let reason):
            return "Embedding failed: \(reason)"
        case .jsonParsingFailed(let reason):
            return "JSON parsing failed: \(reason)"
        }
    }
}

// MARK: - LLM Response

/// Structured response from LLM completion
struct LLMResponse: Sendable {
    let text: String
    let model: String
    let usage: LLMUsage?
    let finishReason: FinishReason
    
    enum FinishReason: String, Sendable {
        case stop
        case length
        case contentFilter
        case error
    }
}

/// Token usage statistics
struct LLMUsage: Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

// MARK: - Provider Registry

/// Registry for managing multiple LLM providers
actor LLMProviderRegistry {
    
    static let shared = LLMProviderRegistry()
    
    private var providers: [String: any LLMProvider] = [:]
    private var defaultProviderId: String?
    
    private init() {}
    
    /// Register a provider
    func register(provider: any LLMProvider) {
        providers[provider.identifier] = provider
        if defaultProviderId == nil {
            defaultProviderId = provider.identifier
        }
    }
    
    /// Get a provider by identifier
    func provider(id: String) -> (any LLMProvider)? {
        providers[id]
    }
    
    /// Get the default provider
    func defaultProvider() -> (any LLMProvider)? {
        guard let id = defaultProviderId else { return nil }
        return providers[id]
    }
    
    /// Set the default provider
    func setDefault(id: String) {
        if providers[id] != nil {
            defaultProviderId = id
        }
    }
    
    /// List all registered providers
    func allProviders() -> [String] {
        Array(providers.keys)
    }
    
    /// Check availability of all providers
    func checkAvailability() async -> [String: Bool] {
        var results: [String: Bool] = [:]
        for (id, provider) in providers {
            results[id] = await provider.isAvailable()
        }
        return results
    }
}

// MARK: - Taxonomy Inference Protocol

/// Specialized protocol for taxonomy inference from filenames
protocol TaxonomyInferring: Actor {
    /// Infer a taxonomy from a list of filenames
    /// - Parameters:
    ///   - filenames: List of filenames to analyze
    ///   - rootName: Optional root category name (from folder)
    ///   - options: LLM options
    /// - Returns: Inferred taxonomy tree
    func inferTaxonomy(
        from filenames: [String],
        rootName: String?,
        options: LLMOptions
    ) async throws -> TaxonomyTree
    
    /// Categorize a single file within an existing taxonomy
    /// - Parameters:
    ///   - filename: The filename to categorize
    ///   - taxonomy: Existing taxonomy structure
    ///   - options: LLM options
    /// - Returns: Category assignment with confidence
    func categorize(
        filename: String,
        within taxonomy: TaxonomyTree,
        options: LLMOptions
    ) async throws -> CategoryAssignment
    
    /// Suggest refinements to existing taxonomy based on files
    func suggestRefinements(
        for taxonomy: TaxonomyTree,
        based filenames: [String],
        options: LLMOptions
    ) async throws -> [TaxonomyRefinement]
}

// MARK: - Category Assignment

/// Result of categorizing a file
struct CategoryAssignment: Sendable, Identifiable {
    let id: UUID
    let filename: String
    let categoryPath: [String]  // e.g., ["Work", "Projects", "2024"]
    let confidence: Double
    let alternativePaths: [[String]]  // Other possible categorizations
    let rationale: String
    let needsDeepAnalysis: Bool  // True if confidence < threshold
    
    init(
        filename: String,
        categoryPath: [String],
        confidence: Double,
        alternativePaths: [[String]] = [],
        rationale: String = "",
        needsDeepAnalysis: Bool = false
    ) {
        self.id = UUID()
        self.filename = filename
        self.categoryPath = categoryPath
        self.confidence = confidence
        self.alternativePaths = alternativePaths
        self.rationale = rationale
        self.needsDeepAnalysis = needsDeepAnalysis
    }
    
    /// Returns the full path as a string (e.g., "Work / Projects / 2024")
    var pathString: String {
        categoryPath.joined(separator: " / ")
    }
}

// MARK: - Taxonomy Refinement

/// Suggested change to taxonomy structure
struct TaxonomyRefinement: Sendable, Identifiable {
    let id: UUID
    let type: RefinementType
    let targetPath: [String]
    let suggestedChange: String
    let reason: String
    let confidence: Double
    
    enum RefinementType: String, Sendable {
        case merge      // Merge two similar categories
        case split      // Split a category into subcategories
        case rename     // Rename a category
        case move       // Move a category to different parent
        case delete     // Remove empty/unused category
        case create     // Create new category
    }
    
    init(
        type: RefinementType,
        targetPath: [String],
        suggestedChange: String,
        reason: String,
        confidence: Double
    ) {
        self.id = UUID()
        self.type = type
        self.targetPath = targetPath
        self.suggestedChange = suggestedChange
        self.reason = reason
        self.confidence = confidence
    }
}

