// MARK: - Apple Intelligence LLM Adapter
// Adapts Apple Intelligence to conform to LLMProvider protocol
// for use with TaxonomyInferenceEngine and other LLM-dependent components

import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Apple Intelligence LLM Adapter (macOS 26+)

#if canImport(FoundationModels)
@available(macOS 26.0, *)
actor AppleIntelligenceLLMAdapter: LLMProvider {
    
    // MARK: - LLMProvider Properties
    
    nonisolated let identifier: String = "apple-intelligence"
    
    // MARK: - Internal Properties
    
    private var session: LanguageModelSession?
    private var cachedAvailability: Bool?
    private var availabilityCacheTime: Date?
    private let availabilityCacheDuration: TimeInterval = 300  // 5 minutes
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - LLMProvider Protocol
    
    func isAvailable() async -> Bool {
        // Check if we have a valid cached result (within 5 minutes)
        if let cached = cachedAvailability,
           let cacheTime = availabilityCacheTime,
           Date().timeIntervalSince(cacheTime) < availabilityCacheDuration {
            return cached
        }
        
        // Use simple property check
        let supported = LanguageModelSession.isSupported
        
        // Cache the result with timestamp
        cachedAvailability = supported
        availabilityCacheTime = Date()
        
        if supported {
            NSLog("✅ [AppleIntelligenceLLM] Available (LanguageModelSession.isSupported = true)")
        } else {
            NSLog("⚠️ [AppleIntelligenceLLM] Not supported on this device")
        }
        
        return supported
    }
    
    func complete(prompt: String, options: LLMOptions) async throws -> String {
        let session = try await getOrCreateSession()
        
        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            // Retry once on failure
            NSLog("⚠️ [AppleIntelligenceLLM] First attempt failed, retrying: \(error.localizedDescription)")
            self.session = nil  // Reset session
            let freshSession = try await getOrCreateSession()
            let response = try await freshSession.respond(to: prompt)
            return response.content
        }
    }
    
    func completeJSON(prompt: String, options: LLMOptions) async throws -> String {
        // Add JSON instruction to prompt
        let jsonPrompt = """
        \(prompt)
        
        IMPORTANT: Respond with ONLY valid JSON. No markdown, no explanation, no code blocks - just the raw JSON object.
        """
        
        let session = try await getOrCreateSession()
        
        do {
            let response = try await session.respond(to: jsonPrompt)
            return extractJSON(from: response.content)
        } catch {
            // Retry once on failure
            NSLog("⚠️ [AppleIntelligenceLLM] First JSON attempt failed, retrying: \(error.localizedDescription)")
            self.session = nil  // Reset session
            let freshSession = try await getOrCreateSession()
            let response = try await freshSession.respond(to: jsonPrompt)
            return extractJSON(from: response.content)
        }
    }
    
    func embed(text: String) async throws -> [Float] {
        // Use NaturalLanguage framework for embeddings
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            throw LLMError.embeddingFailed("Word embedding not available for English")
        }
        
        // Tokenize and average word vectors
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = text
        
        var vectors: [[Double]] = []
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                            unit: .word,
                            scheme: .tokenType,
                            options: [.omitWhitespace, .omitPunctuation]) { _, range in
            let word = String(text[range]).lowercased()
            if let vector = embedding.vector(for: word) {
                vectors.append(vector)
            }
            return true
        }
        
        guard !vectors.isEmpty else {
            // Return zero vector if no words found
            return [Float](repeating: 0, count: 512)
        }
        
        // Average all word vectors
        let dimension = vectors[0].count
        var averaged = [Double](repeating: 0, count: dimension)
        
        for vector in vectors {
            for i in 0..<min(dimension, vector.count) {
                averaged[i] += vector[i]
            }
        }
        
        let count = Double(vectors.count)
        var result = averaged.map { Float($0 / count) }
        
        // Pad or truncate to 512 dimensions
        if result.count < 512 {
            result.append(contentsOf: [Float](repeating: 0, count: 512 - result.count))
        } else if result.count > 512 {
            result = Array(result.prefix(512))
        }
        
        return result
    }
    
    func availableModels() async throws -> [LLMModel] {
        return [
            LLMModel(
                id: "apple-intelligence",
                name: "Apple Intelligence",
                size: nil,
                contextLength: 4096,
                capabilities: [.chat, .completion, .jsonMode]
            )
        ]
    }
    
    func warmup(model: String) async {
        // Pre-create session
        do {
            _ = try await getOrCreateSession()
            NSLog("✅ [AppleIntelligenceLLM] Session warmed up")
        } catch {
            NSLog("⚠️ [AppleIntelligenceLLM] Warmup failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Helpers
    
    private func getOrCreateSession() async throws -> LanguageModelSession {
        if let session = session {
            return session
        }
        
        let newSession = LanguageModelSession()
        self.session = newSession
        return newSession
    }
    
    /// Extract JSON from response that might contain markdown code blocks
    private func extractJSON(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        
        // Try to extract JSON object or array
        if let startBrace = cleaned.firstIndex(of: "{"),
           let endBrace = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[startBrace...endBrace])
        } else if let startBracket = cleaned.firstIndex(of: "["),
                  let endBracket = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[startBracket...endBracket])
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif

// MARK: - Stub for Older macOS

/// Stub provider for macOS < 26 that always returns unavailable
actor AppleIntelligenceLLMStub: LLMProvider {
    nonisolated let identifier: String = "apple-intelligence-unavailable"
    
    func isAvailable() async -> Bool {
        return false
    }
    
    func complete(prompt: String, options: LLMOptions) async throws -> String {
        throw LLMError.providerUnavailable("Apple Intelligence requires macOS 26.0+")
    }
    
    func completeJSON(prompt: String, options: LLMOptions) async throws -> String {
        throw LLMError.providerUnavailable("Apple Intelligence requires macOS 26.0+")
    }
    
    func embed(text: String) async throws -> [Float] {
        throw LLMError.providerUnavailable("Apple Intelligence requires macOS 26.0+")
    }
    
    func availableModels() async throws -> [LLMModel] {
        return []
    }
    
    func warmup(model: String) async {
        // No-op
    }
}

// MARK: - Factory

/// Factory for creating the appropriate Apple Intelligence LLM provider
enum AppleIntelligenceLLMFactory {
    
    /// Create an Apple Intelligence LLM provider
    /// Returns the real implementation on macOS 26+, stub otherwise
    static func create() -> any LLMProvider {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return AppleIntelligenceLLMAdapter()
        }
        #endif
        return AppleIntelligenceLLMStub()
    }
    
    /// Check if Apple Intelligence is available on this system
    static func isAvailable() async -> Bool {
        let provider = create()
        return await provider.isAvailable()
    }
}

