// MARK: - OpenAI Provider
// Cloud LLM provider implementation for OpenAI API
// Spec requirement: "LLMRoutingService with provider registry (Ollama + OpenAI)"

import Foundation

// MARK: - OpenAI Provider Configuration

struct OpenAIProviderConfiguration: Sendable {
    let apiKey: String
    let model: String
    let embeddingModel: String
    let baseURL: String
    let timeout: TimeInterval
    let maxTokens: Int
    let temperature: Double
    
    static func `default`(apiKey: String) -> OpenAIProviderConfiguration {
        OpenAIProviderConfiguration(
            apiKey: apiKey,
            model: "gpt-4o-mini",  // Cost-effective for categorization
            embeddingModel: "text-embedding-3-small",
            baseURL: "https://api.openai.com/v1",
            timeout: 30.0,
            maxTokens: 1000,
            temperature: 0.3
        )
    }
    
    static func premium(apiKey: String) -> OpenAIProviderConfiguration {
        OpenAIProviderConfiguration(
            apiKey: apiKey,
            model: "gpt-4o",  // Higher quality
            embeddingModel: "text-embedding-3-large",
            baseURL: "https://api.openai.com/v1",
            timeout: 60.0,
            maxTokens: 2000,
            temperature: 0.2
        )
    }
}

// MARK: - OpenAI Provider

/// OpenAI API provider for cloud LLM inference
actor OpenAIProvider: LLMProvider {
    
    nonisolated let identifier: String = "openai"
    
    private let config: OpenAIProviderConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var cachedModels: [LLMModel]?
    private var lastHealthCheck: Date?
    private var isHealthy: Bool = true
    
    // MARK: - Initialization
    
    init(configuration: OpenAIProviderConfiguration) {
        self.config = configuration
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout * 2
        self.session = URLSession(configuration: sessionConfig)
    }
    
    // MARK: - LLMProvider Protocol Implementation
    
    func isAvailable() async -> Bool {
        // Skip if checked recently
        if let lastCheck = lastHealthCheck,
           Date().timeIntervalSince(lastCheck) < 60 {
            return isHealthy
        }
        
        do {
            let models = try await availableModels()
            isHealthy = !models.isEmpty
            lastHealthCheck = Date()
            return isHealthy
        } catch {
            NSLog("❌ [OpenAI] Health check failed: \(error.localizedDescription)")
            isHealthy = false
            lastHealthCheck = Date()
            return false
        }
    }
    
    func complete(prompt: String, options: LLMOptions) async throws -> String {
        let messages = [
            ChatMessage(role: "system", content: "You are a helpful assistant."),
            ChatMessage(role: "user", content: prompt)
        ]
        
        let requestBody = ChatCompletionRequest(
            model: options.model,
            messages: messages,
            temperature: options.temperature,
            max_tokens: options.maxTokens,
            response_format: nil
        )
        
        let url = URL(string: "\(config.baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            throw OpenAIError.rateLimited(retryAfter: parseRetryAfter(response))
        }
        
        guard httpResponse.statusCode == 200 else {
            throw OpenAIError.httpError(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }
        
        let completionResponse = try decoder.decode(ChatCompletionResponse.self, from: data)
        
        guard let choice = completionResponse.choices.first else {
            throw OpenAIError.noChoices
        }
        
        return choice.message.content
    }
    
    func completeJSON(prompt: String, options: LLMOptions) async throws -> String {
        let messages = [
            ChatMessage(role: "system", content: "You are a file categorization assistant. Respond only with valid JSON."),
            ChatMessage(role: "user", content: prompt)
        ]
        
        let requestBody = ChatCompletionRequest(
            model: options.model,
            messages: messages,
            temperature: options.temperature,
            max_tokens: options.maxTokens,
            response_format: ResponseFormat(type: "json_object")
        )
        
        let url = URL(string: "\(config.baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            throw OpenAIError.rateLimited(retryAfter: parseRetryAfter(response))
        }
        
        guard httpResponse.statusCode == 200 else {
            throw OpenAIError.httpError(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }
        
        let completionResponse = try decoder.decode(ChatCompletionResponse.self, from: data)
        
        guard let choice = completionResponse.choices.first else {
            throw OpenAIError.noChoices
        }
        
        return choice.message.content
    }
    
    func embed(text: String) async throws -> [Float] {
        let requestBody = EmbeddingRequest(
            model: config.embeddingModel,
            input: text
        )
        
        let url = URL(string: "\(config.baseURL)/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        // Handle rate limiting
        if httpResponse.statusCode == 429 {
            throw OpenAIError.rateLimited(retryAfter: parseRetryAfter(response))
        }
        
        guard httpResponse.statusCode == 200 else {
            throw OpenAIError.httpError(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }
        
        let embeddingResponse = try decoder.decode(EmbeddingResponse.self, from: data)
        
        guard let embedding = embeddingResponse.data.first else {
            throw OpenAIError.noEmbedding
        }
        
        return embedding.embedding.map { Float($0) }
    }
    
    func availableModels() async throws -> [LLMModel] {
        if let cached = cachedModels {
            return cached
        }
        
        let url = URL(string: "\(config.baseURL)/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw OpenAIError.httpError(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }
        
        let modelsResponse = try decoder.decode(ModelsResponse.self, from: data)
        
        // Filter to GPT and embedding models
        let models = modelsResponse.data
            .filter { $0.id.contains("gpt") || $0.id.contains("embedding") }
            .map { 
                LLMModel(
                    id: $0.id, 
                    name: $0.id, 
                    size: nil, 
                    contextLength: nil, 
                    capabilities: $0.id.contains("embedding") ? [.embedding] : [.chat, .completion, .jsonMode]
                )
            }
        
        cachedModels = models
        return models
    }
    
    func warmup(model: String) async {
        // OpenAI API doesn't require warmup - models are always available
        NSLog("🔥 [OpenAI] Warmup requested for model: \(model) (no-op for cloud API)")
    }
    
    // MARK: - Helpers
    
    private func parseRetryAfter(_ response: URLResponse) -> TimeInterval? {
        guard let httpResponse = response as? HTTPURLResponse,
              let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After"),
              let seconds = Double(retryAfter) else {
            return nil
        }
        return seconds
    }
}

// MARK: - Request/Response Types

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let max_tokens: Int
    let response_format: ResponseFormat?
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ResponseFormat: Encodable {
    let type: String
}

private struct ChatCompletionResponse: Decodable {
    let id: String
    let model: String
    let choices: [Choice]
    let usage: Usage?
    
    struct Choice: Decodable {
        let message: ChatMessage
        let finish_reason: String?
    }
    
    struct Usage: Decodable {
        let prompt_tokens: Int
        let completion_tokens: Int
        let total_tokens: Int
    }
}

private struct ModelsResponse: Decodable {
    let data: [ModelData]
    
    struct ModelData: Decodable {
        let id: String
    }
}

private struct EmbeddingRequest: Encodable {
    let model: String
    let input: String
}

private struct EmbeddingResponse: Decodable {
    let data: [EmbeddingData]
    
    struct EmbeddingData: Decodable {
        let embedding: [Double]
    }
}

// MARK: - Errors

enum OpenAIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case rateLimited(retryAfter: TimeInterval?)
    case noChoices
    case noEmbedding
    case invalidAPIKey
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .httpError(let code, let body):
            return "HTTP \(code): \(body ?? "Unknown error")"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(Int(seconds)) seconds"
            }
            return "Rate limited by OpenAI API"
        case .noChoices:
            return "No completion choices returned"
        case .noEmbedding:
            return "No embedding returned"
        case .invalidAPIKey:
            return "Invalid or missing OpenAI API key"
        }
    }
}

// MARK: - Convenience Extension

extension OpenAIProvider {
    
    /// Categorize a file using OpenAI
    func categorizeFile(
        filename: String,
        existingCategories: [String],
        maxDepth: Int = 5
    ) async throws -> CategoryAssignment {
        let categoriesJson = existingCategories.isEmpty 
            ? "[]" 
            : try String(data: encoder.encode(existingCategories), encoding: .utf8) ?? "[]"
        
        let prompt = """
        Categorize this file into a hierarchical category structure.
        
        Filename: \(filename)
        Existing categories: \(categoriesJson)
        Maximum depth: \(maxDepth)
        
        Respond with JSON:
        {
            "category_path": ["Level1", "Level2", ...],
            "confidence": 0.0-1.0,
            "reasoning": "Brief explanation"
        }
        """
        
        let response = try await completeJSON(prompt: prompt, options: .default(model: config.model))
        
        struct CategorizeResponse: Decodable {
            let category_path: [String]
            let confidence: Double
            let reasoning: String
        }
        
        let responseData = response.data(using: String.Encoding.utf8) ?? Data()
        let categorizeResponse = try decoder.decode(CategorizeResponse.self, from: responseData)
        
        return CategoryAssignment(
            filename: filename,
            categoryPath: categorizeResponse.category_path,
            confidence: categorizeResponse.confidence,
            rationale: categorizeResponse.reasoning,
            needsDeepAnalysis: categorizeResponse.confidence < 0.85
        )
    }
}
