// MARK: - Brain (LLM Integration)
// Ollama-based categorization with dynamic taxonomy and GraphRAG learning

import Foundation

// MARK: - Brain Errors

enum BrainError: LocalizedError {
    case connectionFailed(String)
    case invalidResponse
    case jsonParsingFailed(String)
    case modelNotAvailable(String)
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Failed to connect to Ollama: \(reason)"
        case .invalidResponse:
            return "Invalid response from LLM"
        case .jsonParsingFailed(let reason):
            return "Failed to parse JSON response: \(reason)"
        case .modelNotAvailable(let model):
            return "Model '\(model)' is not available"
        case .timeout:
            return "Request timed out"
        }
    }
}

// MARK: - Enhanced Brain Result

/// Result from LLM categorization with flexible hierarchy
struct EnhancedBrainResult: Sendable {
    let categoryPath: CategoryPath
    let confidence: Double
    let rationale: String
    let extractedKeywords: [String]
    let suggestedFromGraph: Bool  // True if suggested by knowledge graph
    
    var category: String { categoryPath.root }
    var subcategories: [String] { Array(categoryPath.components.dropFirst()) }
}

// MARK: - Ollama API Types

struct OllamaRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let format: String
    let options: OllamaOptions?
    
    struct OllamaOptions: Encodable {
        let temperature: Double?
        let top_p: Double?
        let num_predict: Int?
    }
}

struct OllamaResponse: Decodable {
    let model: String
    let response: String
    let done: Bool
    let totalDuration: Int64?
    let loadDuration: Int64?
    let promptEvalCount: Int?
    let evalCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case model, response, done
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}

// MARK: - Brain Configuration

struct BrainConfiguration: Sendable {
    let host: String
    let documentModel: String      // Model for documents (PDF, text, etc.)
    let videoModel: String         // Model for video files
    let imageModel: String         // Model for images
    let audioModel: String         // Model for audio files
    let embeddingModel: String     // Model for generating embeddings
    let temperature: Double
    let maxTokens: Int
    let timeout: TimeInterval
    
    /// Returns the appropriate model for a given media kind
    func model(for kind: MediaKind) -> String {
        switch kind {
        case .document: return documentModel
        case .video: return videoModel
        case .image: return imageModel
        case .audio: return audioModel
        case .unknown: return documentModel  // Default fallback
        }
    }
    
    static let `default` = BrainConfiguration(
        host: "http://127.0.0.1:11434",  // Use IPv4 explicitly to avoid IPv6 connection errors
        documentModel: "llama3.2",
        videoModel: "llama3.2",
        imageModel: "llama3.2",
        audioModel: "llama3.2",
        embeddingModel: "llama3.2",
        temperature: 0.3,
        maxTokens: 1000,
        timeout: 60.0
    )
    
    /// Creates a configuration with a single model for all types
    static func uniform(host: String, model: String, temperature: Double = 0.3, maxTokens: Int = 1000, timeout: TimeInterval = 60.0) -> BrainConfiguration {
        BrainConfiguration(
            host: host,
            documentModel: model,
            videoModel: model,
            imageModel: model,
            audioModel: model,
            embeddingModel: model,
            temperature: temperature,
            maxTokens: maxTokens,
            timeout: timeout
        )
    }
}

// MARK: - Brain Actor

/// The "Brain" of SortAI - uses Ollama to categorize files based on extracted signals
/// Integrates with GraphRAG knowledge graph for learning and suggestions
actor Brain: FileCategorizing {
    
    // MARK: - Properties
    
    private let config: BrainConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // Knowledge graph for learned patterns (optional - set via setKnowledgeGraph)
    private var knowledgeGraph: KnowledgeGraphStore?
    
    // Recent categories for context (fallback when no graph)
    private var recentCategories: [CategoryPath] = []
    private let maxRecentCategories = 20
    
    // MARK: - Initialization
    
    init(configuration: BrainConfiguration = .default) {
        self.config = configuration
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout * 2
        self.session = URLSession(configuration: sessionConfig)
    }
    
    /// Sets the knowledge graph for GraphRAG-based suggestions
    func setKnowledgeGraph(_ graph: KnowledgeGraphStore) {
        self.knowledgeGraph = graph
    }
    
    // MARK: - Public Interface
    
    /// Categorizes a file based on its extracted signature
    /// Uses knowledge graph suggestions when available, falls back to pure LLM
    func categorize(signature: FileSignature) async throws -> EnhancedBrainResult {
        // Extract keywords from signature for graph lookup
        let keywords = extractKeywords(from: signature)
        
        // Try to get suggestions from knowledge graph first
        var graphSuggestions: [(Entity, Double)] = []
        if let graph = knowledgeGraph {
            graphSuggestions = try graph.getSuggestedCategories(for: keywords, limit: 3)
        }
        
        // Build prompt with graph context
        let prompt = buildDynamicPrompt(for: signature, keywords: keywords, graphSuggestions: graphSuggestions)
        let model = config.model(for: signature.kind)
        let response = try await query(prompt: prompt, model: model)
        
        return try parseEnhancedResponse(response, keywords: keywords, hadGraphSuggestions: !graphSuggestions.isEmpty)
    }
    
    /// Legacy categorization method for compatibility
    func categorizeLegacy(signature: FileSignature) async throws -> BrainResult {
        let prompt = buildPrompt(for: signature)
        let model = config.model(for: signature.kind)
        let response = try await query(prompt: prompt, model: model)
        return try parseResponse(response)
    }
    
    /// Returns the model that will be used for a given media kind
    func modelForKind(_ kind: MediaKind) -> String {
        config.model(for: kind)
    }
    
    /// Gets existing categories from the knowledge graph
    func getExistingCategories(limit: Int = 50) async -> [CategoryPath] {
        guard let graph = knowledgeGraph else {
            return recentCategories
        }
        
        do {
            let categories = try graph.getAllCategories(limit: limit)
            return categories.compactMap { entity in
                CategoryPath(path: entity.name)
            }
        } catch {
            return recentCategories
        }
    }
    
    /// Adds a category to recent categories (used when no graph)
    func addRecentCategory(_ path: CategoryPath) {
        if !recentCategories.contains(path) {
            recentCategories.insert(path, at: 0)
            if recentCategories.count > maxRecentCategories {
                recentCategories.removeLast()
            }
        }
    }
    
    // MARK: - Keyword Extraction
    
    private func extractKeywords(from signature: FileSignature) -> [String] {
        var keywords: Set<String> = []
        
        // From filename
        let filenameWords = signature.title
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .components(separatedBy: .whitespaces)
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 }
        keywords.formUnion(filenameWords)
        
        // From scene tags
        keywords.formUnion(signature.sceneTags.map { $0.lowercased() })
        
        // From detected objects
        keywords.formUnion(signature.detectedObjects.map { $0.lowercased() })
        
        // From text content (first 500 chars, extract significant words)
        if !signature.textualCue.isEmpty {
            let textWords = String(signature.textualCue.prefix(500))
                .components(separatedBy: .whitespacesAndNewlines)
                .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count > 4 }  // Longer words are more meaningful
                .prefix(20)
            keywords.formUnion(textWords)
        }
        
        return Array(keywords).sorted()
    }
    
    /// Checks if Ollama is available
    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(config.host)/api/tags") else {
            return false
        }
        
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    /// Warms up all configured models by sending a minimal prompt
    /// This pre-loads models into memory, eliminating the 2s load time on first use
    func warmup() async {
        let models = Set([
            config.documentModel,
            config.videoModel,
            config.imageModel,
            config.audioModel
        ])
        
        await withTaskGroup(of: Void.self) { group in
            for model in models {
                group.addTask {
                    // Send minimal prompt to load model into memory
                    _ = try? await self.query(prompt: "hi", model: model)
                }
            }
        }
    }
    
    /// Lists available models
    func availableModels() async throws -> [String] {
        guard let url = URL(string: "\(config.host)/api/tags") else {
            throw BrainError.connectionFailed("Invalid host URL")
        }
        
        let (data, _) = try await session.data(from: url)
        
        struct TagsResponse: Decodable {
            struct Model: Decodable {
                let name: String
            }
            let models: [Model]
        }
        
        let response = try decoder.decode(TagsResponse.self, from: data)
        return response.models.map { $0.name }
    }
    
    // MARK: - Prompt Building
    
    /// Builds a dynamic prompt using knowledge graph suggestions
    private func buildDynamicPrompt(
        for signature: FileSignature,
        keywords: [String],
        graphSuggestions: [(Entity, Double)]
    ) -> String {
        var prompt = """
        You are a file categorization assistant. Your job is to categorize files into a HIERARCHICAL category system.
        
        CATEGORY FORMAT: Use "/" to separate hierarchy levels. Examples:
        - "Education / Programming / Python"
        - "Entertainment / Magic / Card Tricks"
        - "Documents / Technical / Manuals"
        - "Video / Tutorials / Software"
        
        You can create categories at ANY depth that makes sense. Be specific but not overly granular.
        
        """
        
        // Add existing categories from graph or recent
        let existingCategories = graphSuggestions.isEmpty ? recentCategories : []
        if !existingCategories.isEmpty {
            prompt += "EXISTING CATEGORIES (prefer these if they fit):\n"
            for (index, path) in existingCategories.prefix(10).enumerated() {
                prompt += "  \(index + 1). \(path.description)\n"
            }
            prompt += "\n"
        }
        
        // Add graph-based suggestions if available
        if !graphSuggestions.isEmpty {
            prompt += "SUGGESTED CATEGORIES (based on similar files):\n"
            for (entity, weight) in graphSuggestions {
                let confidence = Int(weight * 100)
                prompt += "  - \(entity.name) (\(confidence)% match)\n"
            }
            prompt += "You may use one of these suggestions or create a new category if none fit well.\n\n"
        }
        
        // Important rules
        prompt += """
        RULES:
        1. NEVER use inappropriate categories (adult, explicit, nsfw, etc.)
        2. Use the filename as a STRONG hint for categorization
        3. If unsure, create a reasonable category - humans will correct if needed
        4. Be consistent with existing categories when possible
        5. Confidence should reflect how certain you are (0.0-1.0)
        
        """
        
        // File info
        prompt += "FILE TO CATEGORIZE:\n"
        prompt += "Name: \(signature.title).\(signature.fileExtension)\n"
        prompt += "Type: \(signature.kind.rawValue)\n"
        
        // Add metadata based on type
        switch signature.kind {
        case .video:
            if let d = signature.duration { prompt += "Duration: \(formatDuration(d))\n" }
            if !signature.sceneTags.isEmpty {
                let safeTags = filterSafeTags(signature.sceneTags)
                if !safeTags.isEmpty {
                    prompt += "Visual themes: \(safeTags.prefix(5).joined(separator: ", "))\n"
                }
            }
            if !signature.detectedObjects.isEmpty {
                prompt += "Objects detected: \(signature.detectedObjects.prefix(5).joined(separator: ", "))\n"
            }
        case .document:
            if let p = signature.pageCount { prompt += "Pages: \(p)\n" }
        case .image:
            if !signature.sceneTags.isEmpty {
                let safeTags = filterSafeTags(signature.sceneTags)
                if !safeTags.isEmpty {
                    prompt += "Image content: \(safeTags.prefix(5).joined(separator: ", "))\n"
                }
            }
        case .audio:
            if let d = signature.duration { prompt += "Duration: \(formatDuration(d))\n" }
        case .unknown:
            break
        }
        
        // Add extracted keywords
        if !keywords.isEmpty {
            prompt += "Keywords: \(keywords.prefix(10).joined(separator: ", "))\n"
        }
        
        // Add text content preview
        if !signature.textualCue.isEmpty {
            let preview = String(signature.textualCue.prefix(400))
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            prompt += "Content preview: \(preview)\n"
        }
        
        // JSON format instruction
        prompt += """
        
        Return ONLY valid JSON in this format:
        {
          "categoryPath": "Main / Sub1 / Sub2",
          "confidence": 0.85,
          "rationale": "Brief explanation of why this category fits",
          "keywords": ["relevant", "keywords", "extracted"]
        }
        """
        
        return prompt
    }
    
    /// Legacy prompt builder for compatibility
    private func buildPrompt(for signature: FileSignature) -> String {
        var prompt = "Categorize this file. Return JSON only.\n"
        prompt += "File: \(signature.title).\(signature.fileExtension) (\(signature.kind.rawValue))"
        
        if !signature.textualCue.isEmpty {
            let preview = String(signature.textualCue.prefix(500))
            prompt += "\nContent: \(preview)"
        }
        
        prompt += "\n\nJSON: {\"category\":\"x\",\"subcategory\":\"y\",\"confidence\":0.9,\"rationale\":\"why\",\"tags\":[]}"
        
        return prompt
    }
    
    /// Filters out inappropriate tags
    private func filterSafeTags(_ tags: [String]) -> [String] {
        let blocked = ["adult", "explicit", "nsfw", "mature", "xxx"]
        return tags.filter { tag in
            let lower = tag.lowercased()
            return !blocked.contains { lower.contains($0) }
        }
    }
    
    // MARK: - API Communication
    
    private func query(prompt: String, model: String) async throws -> String {
        guard let url = URL(string: "\(config.host)/api/generate") else {
            throw BrainError.connectionFailed("Invalid host URL")
        }
        
        // Log the prompt being sent
        NSLog("🔵 [Brain] ===== PROMPT TO LLM =====")
        NSLog("🔵 [Brain] Model: \(model)")
        NSLog("🔵 [Brain] Temperature: \(config.temperature)")
        NSLog("🔵 [Brain] Max Tokens: \(config.maxTokens)")
        NSLog("🔵 [Brain] --- Prompt Start ---")
        NSLog("%@", prompt)
        NSLog("🔵 [Brain] --- Prompt End ---")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let ollamaRequest = OllamaRequest(
            model: model,
            prompt: prompt,
            stream: false,
            format: "json",
            options: OllamaRequest.OllamaOptions(
                temperature: config.temperature,
                top_p: 0.9,
                num_predict: config.maxTokens
            )
        )
        
        request.httpBody = try encoder.encode(ollamaRequest)
        
        let startTime = Date()
        let (data, response) = try await session.data(for: request)
        let elapsed = Date().timeIntervalSince(startTime)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrainError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 404 {
                throw BrainError.modelNotAvailable(model)
            }
            throw BrainError.connectionFailed("HTTP \(httpResponse.statusCode)")
        }
        
        let ollamaResponse = try decoder.decode(OllamaResponse.self, from: data)
        
        // Log the raw response received
        NSLog("🟢 [Brain] ===== RAW LLM RESPONSE =====")
        NSLog("🟢 [Brain] Duration: \(String(format: "%.2f", elapsed))s")
        NSLog("🟢 [Brain] Response Length: \(ollamaResponse.response.count) chars")
        if let promptTokens = ollamaResponse.promptEvalCount {
            NSLog("🟢 [Brain] Prompt Tokens: \(promptTokens)")
        }
        if let completionTokens = ollamaResponse.evalCount {
            NSLog("🟢 [Brain] Completion Tokens: \(completionTokens)")
        }
        NSLog("🟢 [Brain] --- Response Start ---")
        NSLog("%@", ollamaResponse.response)
        NSLog("🟢 [Brain] --- Response End ---")
        
        return ollamaResponse.response
    }
    
    // MARK: - Response Parsing
    
    /// Parses the enhanced response format with flexible category paths
    private func parseEnhancedResponse(_ response: String, keywords: [String], hadGraphSuggestions: Bool) throws -> EnhancedBrainResult {
        let cleaned = cleanResponse(response)
        
        guard let data = cleaned.data(using: .utf8) else {
            throw BrainError.jsonParsingFailed("Invalid UTF-8")
        }
        
        // Try to parse the new format first
        struct EnhancedResponse: Decodable {
            let categoryPath: String
            let confidence: Double
            let rationale: String
            let keywords: [String]?
        }
        
        do {
            let parsed = try decoder.decode(EnhancedResponse.self, from: data)
            
            // Validate the category path
            var categoryPath = CategoryPath(path: parsed.categoryPath)
            
            // Check for blocked categories
            if isBlockedCategory(categoryPath) {
                NSLog("⚠️ [Brain] Blocked inappropriate category '\(categoryPath.description)' - replacing with Uncategorized")
                categoryPath = CategoryPath(components: ["Uncategorized", "Needs Review"])
            }
            
            // Add to recent categories
            addRecentCategory(categoryPath)
            
            let result = EnhancedBrainResult(
                categoryPath: categoryPath,
                confidence: parsed.confidence,
                rationale: parsed.rationale,
                extractedKeywords: parsed.keywords ?? keywords,
                suggestedFromGraph: hadGraphSuggestions
            )
            
            // Log the parsed result
            NSLog("🟣 [Brain] ===== PARSED RESULT =====")
            NSLog("🟣 [Brain] Category Path: \(result.categoryPath.description)")
            NSLog("🟣 [Brain] Confidence: \(String(format: "%.2f", result.confidence))")
            NSLog("🟣 [Brain] Rationale: \(result.rationale)")
            NSLog("🟣 [Brain] Keywords: \(result.extractedKeywords.joined(separator: ", "))")
            NSLog("🟣 [Brain] Graph Suggested: \(result.suggestedFromGraph)")
            
            return result
        } catch {
            // Try legacy format as fallback
            do {
                let legacy = try decoder.decode(BrainResult.self, from: data)
                var components = [legacy.category]
                if let sub = legacy.subcategory {
                    components.append(sub)
                }
                let categoryPath = CategoryPath(components: components)
                
                addRecentCategory(categoryPath)
                
                let result = EnhancedBrainResult(
                    categoryPath: categoryPath,
                    confidence: legacy.confidence,
                    rationale: legacy.rationale.isEmpty ? "No rationale provided" : legacy.rationale,
                    extractedKeywords: legacy.tags,
                    suggestedFromGraph: hadGraphSuggestions
                )
                
                // Log the parsed result (legacy format)
                NSLog("🟣 [Brain] ===== PARSED RESULT (Legacy Format) =====")
                NSLog("🟣 [Brain] Category Path: \(result.categoryPath.description)")
                NSLog("🟣 [Brain] Confidence: \(String(format: "%.2f", result.confidence))")
                NSLog("🟣 [Brain] Rationale: \(result.rationale)")
                NSLog("🟣 [Brain] Keywords: \(result.extractedKeywords.joined(separator: ", "))")
                
                return result
            } catch {
                NSLog("❌ [Brain] JSON parsing failed: \(error.localizedDescription)")
                NSLog("❌ [Brain] Cleaned response was: \(cleaned)")
                throw BrainError.jsonParsingFailed(error.localizedDescription)
            }
        }
    }
    
    /// Legacy response parser for compatibility
    private func parseResponse(_ response: String) throws -> BrainResult {
        let cleaned = cleanResponse(response)
        
        guard let data = cleaned.data(using: .utf8) else {
            throw BrainError.jsonParsingFailed("Invalid UTF-8")
        }
        
        do {
            var result = try decoder.decode(BrainResult.self, from: data)
            
            // Check for blocked categories
            if isBlockedCategory(result.category) || isBlockedCategory(result.subcategory ?? "") {
                result = BrainResult(
                    category: "Uncategorized",
                    subcategory: "Needs Review",
                    confidence: 0.3,
                    rationale: "Category blocked - needs manual review",
                    tags: result.tags
                )
            }
            
            return result
        } catch {
            throw BrainError.jsonParsingFailed(error.localizedDescription)
        }
    }
    
    /// Cleans up LLM response (removes markdown, trims whitespace)
    private func cleanResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks
        if cleaned.hasPrefix("```") {
            if let start = cleaned.range(of: "\n"),
               let end = cleaned.range(of: "```", options: .backwards) {
                cleaned = String(cleaned[start.upperBound..<end.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return cleaned
    }
    
    /// Checks if a category contains blocked terms
    private func isBlockedCategory(_ category: String) -> Bool {
        let blocked = ["adult", "explicit", "nsfw", "mature", "xxx", "porn", "erotic"]
        let lower = category.lowercased()
        return blocked.contains { lower.contains($0) }
    }
    
    /// Checks if a category path contains blocked terms
    private func isBlockedCategory(_ path: CategoryPath) -> Bool {
        path.components.contains { isBlockedCategory($0) }
    }
    
    // MARK: - Utilities
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Embedding Generator

/// Generates text embeddings for memory storage
/// Can use Ollama embeddings API or a local model
actor EmbeddingGenerator: EmbeddingGenerating {
    
    private let config: BrainConfiguration
    private let session: URLSession
    let dimensions: Int
    
    init(configuration: BrainConfiguration = .default, dimensions: Int = 384) {
        self.config = configuration
        self.dimensions = dimensions
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: sessionConfig)
    }
    
    /// Generates embedding for text
    func embed(text: String) async throws -> [Float] {
        // Try Ollama embeddings API first
        if let embedding = try? await ollamaEmbed(text: text) {
            return embedding
        }
        
        // Fallback to simple hash-based embedding (for development)
        return simpleEmbed(text: text)
    }
    
    /// Generates embedding for a FileSignature
    func embed(signature: FileSignature) async throws -> [Float] {
        // Combine relevant text fields
        var combined = signature.title
        combined += " " + signature.textualCue.prefix(1000)
        combined += " " + signature.sceneTags.joined(separator: " ")
        combined += " " + signature.detectedObjects.joined(separator: " ")
        
        return try await embed(text: combined)
    }
    
    // MARK: - Protocol Conformance
    
    /// Protocol method - generates embedding for text
    func generateEmbedding(for text: String) async throws -> [Float] {
        try await embed(text: text)
    }
    
    /// Protocol method - generates embedding for signature
    func generateEmbedding(for signature: FileSignature) async throws -> [Float] {
        try await embed(signature: signature)
    }
    
    // MARK: - Ollama Embeddings
    
    private func ollamaEmbed(text: String) async throws -> [Float] {
        guard let url = URL(string: "\(config.host)/api/embeddings") else {
            throw BrainError.connectionFailed("Invalid URL")
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
        
        let embedRequest = EmbedRequest(model: config.embeddingModel, prompt: text)
        request.httpBody = try JSONEncoder().encode(embedRequest)
        
        let (data, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(EmbedResponse.self, from: data)
        
        return response.embedding
    }
    
    // MARK: - Fallback Embedding
    
    /// Simple hash-based embedding for development/testing
    private func simpleEmbed(text: String) -> [Float] {
        // Tokenize and hash
        let tokens = text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
        
        var embedding = [Float](repeating: 0, count: dimensions)
        
        for (i, token) in tokens.enumerated() {
            let hash = token.hashValue
            let index = abs(hash) % dimensions
            let value = Float(hash % 1000) / 1000.0
            embedding[index] += value * (1.0 / Float(i + 1))  // Weight by position
        }
        
        // Normalize
        let magnitude = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        if magnitude > 0 {
            embedding = embedding.map { $0 / magnitude }
        }
        
        return embedding
    }
}

