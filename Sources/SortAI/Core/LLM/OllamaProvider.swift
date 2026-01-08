// MARK: - Ollama LLM Provider
// Implementation of LLMProvider for local Ollama instance

import Foundation

// MARK: - Ollama Provider

/// LLM provider implementation for Ollama (local inference)
actor OllamaProvider: LLMProvider {
    
    // MARK: - Properties
    
    nonisolated let identifier = "ollama"
    
    private let host: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let timeout: TimeInterval
    
    // MARK: - Initialization
    
    init(host: String = "http://127.0.0.1:11434", timeout: TimeInterval = 300.0) {
        self.host = host
        self.timeout = timeout
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - LLMProvider Protocol
    
    func isAvailable() async -> Bool {
        NSLog("🔌 [OllamaProvider] Checking availability at: \(host)")
        guard let url = URL(string: "\(host)/api/tags") else {
            NSLog("❌ [OllamaProvider] Invalid URL: \(host)/api/tags")
            return false
        }
        
        do {
            let startTime = Date()
            let (_, response) = try await session.data(from: url)
            let duration = Date().timeIntervalSince(startTime)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            NSLog("✅ [OllamaProvider] Available check completed in %.2fs - Status: \(statusCode)", duration)
            return statusCode == 200
        } catch {
            NSLog("❌ [OllamaProvider] Availability check failed: \(error.localizedDescription)")
            return false
        }
    }
    
    func complete(prompt: String, options: LLMOptions) async throws -> String {
        NSLog("📝 [OllamaProvider] Starting text completion - model: \(options.model), prompt length: \(prompt.count)")
        let startTime = Date()
        do {
            let response = try await sendRequest(prompt: prompt, options: options, jsonFormat: false)
            let duration = Date().timeIntervalSince(startTime)
            NSLog("✅ [OllamaProvider] Text completion done in %.2fs - response length: \(response.text.count)", duration)
            return response.text
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            NSLog("❌ [OllamaProvider] Text completion FAILED after %.2fs: \(error.localizedDescription)", duration)
            throw error
        }
    }
    
    func completeJSON(prompt: String, options: LLMOptions) async throws -> String {
        NSLog("📝 [OllamaProvider] Starting JSON completion - model: \(options.model), prompt length: \(prompt.count)")
        let startTime = Date()
        do {
            let response = try await sendRequest(prompt: prompt, options: options, jsonFormat: true)
            let duration = Date().timeIntervalSince(startTime)
            NSLog("✅ [OllamaProvider] JSON completion done in %.2fs - response length: \(response.text.count)", duration)
            return response.text
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            NSLog("❌ [OllamaProvider] JSON completion FAILED after %.2fs: \(error.localizedDescription)", duration)
            throw error
        }
    }
    
    func embed(text: String) async throws -> [Float] {
        guard let url = URL(string: "\(host)/api/embeddings") else {
            throw LLMError.connectionFailed("Invalid URL")
        }
        
        struct EmbedRequest: Encodable {
            let model: String
            let prompt: String
        }
        
        struct EmbedResponse: Decodable {
            let embedding: [Float]
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use a model known for good embeddings
        let embedRequest = EmbedRequest(model: "llama3.2", prompt: text)
        request.httpBody = try encoder.encode(embedRequest)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("No HTTP response")
        }
        
        if httpResponse.statusCode != 200 {
            throw LLMError.embeddingFailed("HTTP \(httpResponse.statusCode)")
        }
        
        let embedResponse = try decoder.decode(EmbedResponse.self, from: data)
        return embedResponse.embedding
    }
    
    func availableModels() async throws -> [LLMModel] {
        guard let url = URL(string: "\(host)/api/tags") else {
            throw LLMError.connectionFailed("Invalid URL")
        }
        
        struct TagsResponse: Decodable {
            struct Model: Decodable {
                let name: String
                let size: Int64?
                let details: Details?
                
                struct Details: Decodable {
                    let parameterSize: String?
                    let quantizationLevel: String?
                    
                    enum CodingKeys: String, CodingKey {
                        case parameterSize = "parameter_size"
                        case quantizationLevel = "quantization_level"
                    }
                }
            }
            let models: [Model]
        }
        
        let (data, _) = try await session.data(from: url)
        let response = try decoder.decode(TagsResponse.self, from: data)
        
        return response.models.map { model in
            var capabilities: Set<LLMModel.LLMCapability> = [.completion, .chat]
            
            // Infer capabilities from model name
            let lowerName = model.name.lowercased()
            if lowerName.contains("embed") {
                capabilities.insert(.embedding)
            }
            if lowerName.contains("vision") || lowerName.contains("llava") {
                capabilities.insert(.vision)
            }
            if lowerName.contains("code") || lowerName.contains("deepseek") {
                capabilities.insert(.codeGeneration)
            }
            
            // All recent models support JSON mode
            capabilities.insert(.jsonMode)
            
            return LLMModel(
                id: model.name,
                name: model.name,
                size: model.size,
                contextLength: nil,  // Ollama doesn't expose this directly
                capabilities: capabilities
            )
        }
    }
    
    func warmup(model: String) async {
        // Send minimal prompt to load model into memory
        let options = LLMOptions.deterministic(model: model)
        _ = try? await complete(prompt: "hi", options: options)
    }
    
    // MARK: - Private Methods
    
    private func sendRequest(
        prompt: String,
        options: LLMOptions,
        jsonFormat: Bool
    ) async throws -> LLMResponse {
        NSLog("🌐 [OllamaProvider] Preparing request to \(host)/api/generate")
        NSLog("🌐 [OllamaProvider] Model: \(options.model), JSON mode: \(jsonFormat), timeout: \(timeout)s")
        
        guard let url = URL(string: "\(host)/api/generate") else {
            NSLog("❌ [OllamaProvider] Invalid URL: \(host)/api/generate")
            throw LLMError.connectionFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct OllamaRequest: Encodable {
            let model: String
            let prompt: String
            let stream: Bool
            let format: String?
            let options: Options?
            
            struct Options: Encodable {
                let temperature: Double?
                let top_p: Double?
                let num_predict: Int?
                let stop: [String]?
            }
        }
        
        let ollamaRequest = OllamaRequest(
            model: options.model,
            prompt: prompt,
            stream: false,
            format: jsonFormat ? "json" : nil,
            options: OllamaRequest.Options(
                temperature: options.temperature,
                top_p: options.topP,
                num_predict: options.maxTokens,
                stop: options.stopSequences
            )
        )
        
        request.httpBody = try encoder.encode(ollamaRequest)
        
        // Log the full prompt in copy-pastable format
        NSLog("📤 [OllamaProvider] ====== PROMPT (\(prompt.count) chars) ======")
        print("""
        
        ========== OLLAMA PROMPT START ==========
        \(prompt)
        ========== OLLAMA PROMPT END ==========
        
        """)
        
        let requestStartTime = Date()
        NSLog("📤 [OllamaProvider] Sending request to Ollama...")
        
        let (data, response) = try await session.data(for: request)
        
        let requestDuration = Date().timeIntervalSince(requestStartTime)
        NSLog("📥 [OllamaProvider] Response received in %.2fs - data size: \(data.count) bytes", requestDuration)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            NSLog("❌ [OllamaProvider] No HTTP response object")
            throw LLMError.invalidResponse("No HTTP response")
        }
        
        NSLog("📊 [OllamaProvider] HTTP Status: \(httpResponse.statusCode)")
        
        switch httpResponse.statusCode {
        case 200:
            break
        case 404:
            NSLog("❌ [OllamaProvider] Model not found: \(options.model)")
            throw LLMError.modelNotFound(options.model)
        case 429:
            NSLog("⚠️ [OllamaProvider] Rate limited!")
            throw LLMError.rateLimited(retryAfter: nil)
        default:
            NSLog("❌ [OllamaProvider] HTTP error: \(httpResponse.statusCode)")
            throw LLMError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }
        
        struct OllamaResponse: Decodable {
            let model: String
            let response: String
            let done: Bool
            let totalDuration: Int64?
            let promptEvalCount: Int?
            let evalCount: Int?
            
            enum CodingKeys: String, CodingKey {
                case model, response, done
                case totalDuration = "total_duration"
                case promptEvalCount = "prompt_eval_count"
                case evalCount = "eval_count"
            }
        }
        
        let ollamaResponse = try decoder.decode(OllamaResponse.self, from: data)
        
        // Log the full response in copy-pastable format
        NSLog("📥 [OllamaProvider] ====== RESPONSE (\(ollamaResponse.response.count) chars) ======")
        print("""
        
        ========== OLLAMA RESPONSE START ==========
        \(ollamaResponse.response)
        ========== OLLAMA RESPONSE END ==========
        
        """)
        
        // Log performance stats
        if let duration = ollamaResponse.totalDuration {
            let durationSecs = Double(duration) / 1_000_000_000.0
            NSLog("📊 [OllamaProvider] Stats: total_duration=%.2fs, prompt_tokens=%d, completion_tokens=%d",
                  durationSecs,
                  ollamaResponse.promptEvalCount ?? 0,
                  ollamaResponse.evalCount ?? 0)
            print("📊 Ollama Stats: \(String(format: "%.2f", durationSecs))s, \(ollamaResponse.promptEvalCount ?? 0) prompt tokens, \(ollamaResponse.evalCount ?? 0) completion tokens")
        }
        
        return LLMResponse(
            text: ollamaResponse.response,
            model: ollamaResponse.model,
            usage: LLMUsage(
                promptTokens: ollamaResponse.promptEvalCount ?? 0,
                completionTokens: ollamaResponse.evalCount ?? 0,
                totalTokens: (ollamaResponse.promptEvalCount ?? 0) + (ollamaResponse.evalCount ?? 0)
            ),
            finishReason: ollamaResponse.done ? .stop : .error
        )
    }
}

// MARK: - Ollama Provider Configuration (internal to this provider)

struct OllamaProviderConfig: Sendable {
    let host: String
    let defaultModel: String
    let embeddingModel: String
    let timeout: TimeInterval
    let maxConcurrentRequests: Int
    
    static let `default` = OllamaProviderConfig(
        host: "http://127.0.0.1:11434",
        defaultModel: "llama3.2",
        embeddingModel: "llama3.2",
        timeout: 120.0,
        maxConcurrentRequests: 2
    )
}

