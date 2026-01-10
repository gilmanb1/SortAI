// MARK: - LLM Categorization Provider Protocol
// Unified interface for all AI providers (Apple Intelligence, Ollama, Cloud)
// Supports progressive degradation and user preference

import Foundation

// MARK: - Provider Preference

/// User preference for LLM provider selection
enum ProviderPreference: String, Codable, CaseIterable, Sendable {
    case automatic = "automatic"
    case appleIntelligenceOnly = "apple-intelligence-only"
    case preferOllama = "prefer-ollama"
    case cloud = "cloud"
    
    var displayName: String {
        switch self {
        case .automatic: return "Automatic (Recommended)"
        case .appleIntelligenceOnly: return "Apple Intelligence Only"
        case .preferOllama: return "Prefer Ollama"
        case .cloud: return "Cloud (OpenAI/Anthropic)"
        }
    }
    
    var description: String {
        switch self {
        case .automatic:
            return "Uses Apple Intelligence, falls back to Ollama for complex files"
        case .appleIntelligenceOnly:
            return "Never uses external LLMs"
        case .preferOllama:
            return "Uses Ollama first, Apple Intelligence as fallback"
        case .cloud:
            return "Requires API key"
        }
    }
}

// MARK: - Provider Identifier

/// Unique identifiers for each provider
enum LLMProviderIdentifier: String, Codable, Sendable {
    case appleIntelligence = "apple-intelligence"
    case ollama = "ollama"
    case openAI = "openai"
    case anthropic = "anthropic"
    case localML = "local-ml"
    
    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .ollama: return "Ollama"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .localML: return "Local ML"
        }
    }
    
    /// SF Symbol name for the provider badge
    var symbolName: String {
        switch self {
        case .appleIntelligence: return "apple.logo"
        case .ollama: return "llama"  // Will use emoji fallback
        case .openAI: return "cloud"
        case .anthropic: return "cloud"
        case .localML: return "cpu"
        }
    }
    
    /// Emoji fallback for providers without SF Symbols
    var emoji: String {
        switch self {
        case .appleIntelligence: return ""  // SF Symbol preferred
        case .ollama: return "🦙"
        case .openAI: return "☁️"
        case .anthropic: return "☁️"
        case .localML: return "💻"
        }
    }
    
    /// Priority for automatic mode (lower = higher priority)
    var defaultPriority: Int {
        switch self {
        case .appleIntelligence: return 1
        case .ollama: return 2
        case .openAI: return 3
        case .anthropic: return 4
        case .localML: return 100  // Always last
        }
    }
}

// MARK: - Categorization Result

/// Result from LLM categorization with provider metadata
struct CategorizationResult: Sendable {
    let categoryPath: CategoryPath
    let confidence: Double
    let rationale: String
    let extractedKeywords: [String]
    let provider: LLMProviderIdentifier
    let processingTime: TimeInterval
    let shouldEscalate: Bool
    let escalatedFrom: LLMProviderIdentifier?
    
    /// Convenience initializer without escalation
    init(
        categoryPath: CategoryPath,
        confidence: Double,
        rationale: String,
        extractedKeywords: [String],
        provider: LLMProviderIdentifier,
        processingTime: TimeInterval = 0,
        shouldEscalate: Bool = false
    ) {
        self.categoryPath = categoryPath
        self.confidence = confidence
        self.rationale = rationale
        self.extractedKeywords = extractedKeywords
        self.provider = provider
        self.processingTime = processingTime
        self.shouldEscalate = shouldEscalate
        self.escalatedFrom = nil
    }
    
    /// Create a new result with escalation info
    func withEscalation(from originalProvider: LLMProviderIdentifier) -> CategorizationResult {
        CategorizationResult(
            categoryPath: categoryPath,
            confidence: confidence,
            rationale: rationale,
            extractedKeywords: extractedKeywords,
            provider: provider,
            processingTime: processingTime,
            shouldEscalate: false,
            escalatedFrom: originalProvider
        )
    }
    
    private init(
        categoryPath: CategoryPath,
        confidence: Double,
        rationale: String,
        extractedKeywords: [String],
        provider: LLMProviderIdentifier,
        processingTime: TimeInterval,
        shouldEscalate: Bool,
        escalatedFrom: LLMProviderIdentifier?
    ) {
        self.categoryPath = categoryPath
        self.confidence = confidence
        self.rationale = rationale
        self.extractedKeywords = extractedKeywords
        self.provider = provider
        self.processingTime = processingTime
        self.shouldEscalate = shouldEscalate
        self.escalatedFrom = escalatedFrom
    }
}

// MARK: - Provider Capabilities

/// Describes what a provider supports
struct ProviderCapabilities: Sendable {
    let supportsModelSelection: Bool
    let supportsTemperature: Bool
    let supportsCustomPrompts: Bool
    let supportsStreaming: Bool
    let supportsEmbeddings: Bool
    let supportsStructuredOutput: Bool
    let maxContextLength: Int?
    
    static let appleIntelligence = ProviderCapabilities(
        supportsModelSelection: false,
        supportsTemperature: false,
        supportsCustomPrompts: false,
        supportsStreaming: true,
        supportsEmbeddings: true,
        supportsStructuredOutput: true,
        maxContextLength: 4096
    )
    
    static let ollama = ProviderCapabilities(
        supportsModelSelection: true,
        supportsTemperature: true,
        supportsCustomPrompts: true,
        supportsStreaming: true,
        supportsEmbeddings: true,
        supportsStructuredOutput: true,
        maxContextLength: nil  // Depends on model
    )
    
    static let openAI = ProviderCapabilities(
        supportsModelSelection: true,
        supportsTemperature: true,
        supportsCustomPrompts: true,
        supportsStreaming: true,
        supportsEmbeddings: true,
        supportsStructuredOutput: true,
        maxContextLength: 128000  // GPT-4o
    )
    
    static let localML = ProviderCapabilities(
        supportsModelSelection: false,
        supportsTemperature: false,
        supportsCustomPrompts: false,
        supportsStreaming: false,
        supportsEmbeddings: true,
        supportsStructuredOutput: false,
        maxContextLength: nil
    )
}

// MARK: - Provider Protocol

/// Protocol for all LLM categorization providers
protocol LLMCategorizationProvider: Actor, Sendable {
    /// Unique identifier for this provider
    nonisolated var identifier: LLMProviderIdentifier { get }
    
    /// Priority in automatic mode (lower = higher priority)
    nonisolated var priority: Int { get }
    
    /// Provider capabilities
    nonisolated var capabilities: ProviderCapabilities { get }
    
    /// Check if the provider is available and ready
    func isAvailable() async -> Bool
    
    /// Categorize a file based on its signature
    /// - Parameter signature: File metadata and content
    /// - Returns: Categorization result with confidence
    func categorize(signature: FileSignature) async throws -> CategorizationResult
    
    /// Extract entities from text (for GraphRAG)
    /// - Parameter text: Text to analyze
    /// - Returns: Extracted entities with types
    func extractEntities(from text: String) async throws -> [ExtractedEntity]
    
    /// Generate embedding for text
    /// - Parameter text: Text to embed
    /// - Returns: Embedding vector (512 dimensions)
    func generateEmbedding(for text: String) async throws -> [Float]
}

// MARK: - Default Implementations

extension LLMCategorizationProvider {
    /// Default entity extraction (returns empty - override in providers that support it)
    func extractEntities(from text: String) async throws -> [ExtractedEntity] {
        return []
    }
    
    /// Default embedding generation (throws - override in providers that support it)
    func generateEmbedding(for text: String) async throws -> [Float] {
        throw LLMCategorizationError.embeddingNotSupported(identifier)
    }
}

// MARK: - Extracted Entity

/// Entity extracted from text for GraphRAG
struct ExtractedEntity: Sendable, Hashable {
    let text: String
    let type: ExtractedEntityType
    let confidence: Double
    let startIndex: Int?
    let endIndex: Int?
    
    init(text: String, type: ExtractedEntityType, confidence: Double = 0.8, startIndex: Int? = nil, endIndex: Int? = nil) {
        self.text = text
        self.type = type
        self.confidence = confidence
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}

/// Types of entities that can be extracted
enum ExtractedEntityType: String, Codable, Sendable, CaseIterable {
    case person = "person"
    case organization = "organization"
    case location = "location"
    case date = "date"
    case keyword = "keyword"
    case topic = "topic"
    case product = "product"
    case event = "event"
    
    /// Convert to existing EntityType for KnowledgeGraph
    var toEntityType: EntityType {
        switch self {
        case .person: return .person
        case .organization: return .keyword  // Map to keyword for now
        case .location: return .keyword
        case .date: return .keyword
        case .keyword: return .keyword
        case .topic: return .topic
        case .product: return .keyword
        case .event: return .keyword
        }
    }
}

// MARK: - Categorization Errors

/// Errors specific to categorization providers
enum LLMCategorizationError: LocalizedError {
    case providerUnavailable(LLMProviderIdentifier)
    case allProvidersFailed(underlyingError: Error?)
    case embeddingNotSupported(LLMProviderIdentifier)
    case structuredOutputFailed(String)
    case invalidResponse(String)
    case timeout(LLMProviderIdentifier)
    case configurationMissing(String)
    case macOSVersionTooLow(required: String, current: String)
    
    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let id):
            return "Provider '\(id.displayName)' is not available"
        case .allProvidersFailed(let error):
            return "All AI providers failed. Last error: \(error?.localizedDescription ?? "Unknown")"
        case .embeddingNotSupported(let id):
            return "Provider '\(id.displayName)' does not support embeddings"
        case .structuredOutputFailed(let reason):
            return "Structured output generation failed: \(reason)"
        case .invalidResponse(let reason):
            return "Invalid response from provider: \(reason)"
        case .timeout(let id):
            return "Request to '\(id.displayName)' timed out"
        case .configurationMissing(let key):
            return "Required configuration missing: \(key)"
        case .macOSVersionTooLow(let required, let current):
            return "macOS \(required) required for Apple Intelligence (current: \(current))"
        }
    }
}

// MARK: - Provider Settings Availability

/// Indicates which settings are available for the current provider
struct ProviderSettingsAvailability: Sendable {
    let modelSelection: Bool
    let temperature: Bool
    let customPrompts: Bool
    let serverURL: Bool
    let apiKey: Bool
    
    static let appleIntelligence = ProviderSettingsAvailability(
        modelSelection: false,
        temperature: false,
        customPrompts: false,
        serverURL: false,
        apiKey: false
    )
    
    static let ollama = ProviderSettingsAvailability(
        modelSelection: true,
        temperature: true,
        customPrompts: true,
        serverURL: true,
        apiKey: false
    )
    
    static let cloud = ProviderSettingsAvailability(
        modelSelection: true,
        temperature: true,
        customPrompts: true,
        serverURL: false,
        apiKey: true
    )
}

