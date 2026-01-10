// MARK: - Apple Intelligence Provider
// On-device LLM using Apple's Foundation Models framework (macOS 26+)
// Zero dependencies, always available on supported hardware

import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Generable Types for Structured Output

#if canImport(FoundationModels)

/// Structured response for file categorization
@available(macOS 26.0, *)
@Generable
struct FileCategoryResponse: Sendable {
    @Guide(description: "The category path using '/' separator, e.g., 'Documents / Financial / Reports'")
    var categoryPath: String
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    var confidence: Double
    
    @Guide(description: "Brief explanation for why this category was chosen")
    var rationale: String
    
    @Guide(description: "Relevant keywords extracted from the file")
    var keywords: [String]
}

/// Structured response for entity extraction
@available(macOS 26.0, *)
@Generable
struct EntityExtractionResponse: Sendable {
    @Guide(description: "List of entities found in the text")
    var entities: [ExtractedEntityItem]
}

/// Individual entity item
@available(macOS 26.0, *)
@Generable
struct ExtractedEntityItem: Sendable {
    @Guide(description: "The entity text as it appears")
    var text: String
    
    @Guide(description: "Entity type: person, organization, location, date, keyword, topic, product, event")
    var type: String
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    var confidence: Double
}

/// Structured response for relationship extraction (GraphRAG)
@available(macOS 26.0, *)
@Generable
struct RelationshipExtractionResponse: Sendable {
    @Guide(description: "List of relationships between entities")
    var relationships: [ExtractedRelationshipItem]
}

/// Individual relationship item
@available(macOS 26.0, *)
@Generable
struct ExtractedRelationshipItem: Sendable {
    @Guide(description: "Source entity name")
    var source: String
    
    @Guide(description: "Target entity name")
    var target: String
    
    @Guide(description: "Relationship type: works_for, located_in, related_to, mentions, authored_by, part_of")
    var relationshipType: String
    
    @Guide(description: "Confidence score from 0.0 to 1.0")
    var confidence: Double
}

/// Structured response for document summarization (used for embeddings)
@available(macOS 26.0, *)
@Generable
struct DocumentSummaryResponse: Sendable {
    @Guide(description: "Concise summary of the document in 2-3 sentences")
    var summary: String
    
    @Guide(description: "Main topics covered")
    var topics: [String]
    
    @Guide(description: "Key entities mentioned")
    var keyEntities: [String]
}

#endif

// MARK: - Apple Intelligence Provider

/// LLM provider using Apple's on-device Foundation Models
/// Available on macOS 26+ with Apple Silicon
@available(macOS 26.0, *)
actor AppleIntelligenceProvider: LLMCategorizationProvider {
    
    // MARK: - Protocol Properties
    
    nonisolated let identifier = LLMProviderIdentifier.appleIntelligence
    nonisolated let priority = 1  // Highest priority (default)
    nonisolated let capabilities = ProviderCapabilities.appleIntelligence
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        let escalationThreshold: Double
        let maxRetries: Int
        let sessionPoolSize: Int
        let requestTimeout: TimeInterval
        
        static let `default` = Configuration(
            escalationThreshold: 0.5,
            maxRetries: 1,
            sessionPoolSize: 3,
            requestTimeout: 30.0
        )
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private var sessionPool: [LanguageModelSession] = []
    private var sessionIndex = 0
    private var isInitialized = false
    private var availabilityChecked = false
    private var cachedAvailability: Bool = false
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .default) {
        self.config = configuration
    }
    
    // MARK: - Availability Check
    
    func isAvailable() async -> Bool {
        // Return cached result if we've already checked
        if availabilityChecked {
            return cachedAvailability
        }
        
        // macOS 26+ is guaranteed by the @available annotation on this actor
        // Try to initialize a session to verify Apple Intelligence is actually available
        do {
            let testSession = LanguageModelSession()
            // Quick test to verify it works
            _ = try await testSession.respond(to: "test")
            
            cachedAvailability = true
            availabilityChecked = true
            NSLog("✅ [AppleIntelligence] Available and ready")
            return true
        } catch {
            NSLog("❌ [AppleIntelligence] Not available: \(error.localizedDescription)")
            cachedAvailability = false
            availabilityChecked = true
            return false
        }
    }
    
    // MARK: - Session Management
    
    /// Get or create a session from the pool
    private func getSession() async throws -> LanguageModelSession {
        // Initialize pool if needed
        if !isInitialized {
            try await initializeSessionPool()
        }
        
        // Round-robin through sessions
        let session = sessionPool[sessionIndex]
        sessionIndex = (sessionIndex + 1) % sessionPool.count
        return session
    }
    
    private func initializeSessionPool() async throws {
        guard sessionPool.isEmpty else { return }
        
        NSLog("🔄 [AppleIntelligence] Initializing session pool (size: \(config.sessionPoolSize))")
        
        for i in 0..<config.sessionPoolSize {
            let session = LanguageModelSession()
            sessionPool.append(session)
            NSLog("✅ [AppleIntelligence] Session \(i + 1) created")
        }
        
        isInitialized = true
    }
    
    // MARK: - Categorization
    
    func categorize(signature: FileSignature) async throws -> CategorizationResult {
        let startTime = Date()
        var lastError: Error = LLMCategorizationError.providerUnavailable(.appleIntelligence)
        
        // Retry loop
        for attempt in 0...config.maxRetries {
            do {
                let session = try await getSession()
                let prompt = buildCategorizationPrompt(for: signature)
                
                NSLog("🧠 [AppleIntelligence] Categorizing: \(signature.url.lastPathComponent) (attempt \(attempt + 1))")
                
                let response = try await session.respond(
                    to: prompt,
                    generating: FileCategoryResponse.self
                )
                
                let result = response.content
                let processingTime = Date().timeIntervalSince(startTime)
                
                // Validate and clean the category path
                var categoryPath = CategoryPath(path: result.categoryPath)
                if categoryPath.components.isEmpty {
                    categoryPath = CategoryPath(components: ["Uncategorized"])
                }
                
                let shouldEscalate = result.confidence < config.escalationThreshold
                
                NSLog("✅ [AppleIntelligence] Result: \(categoryPath.description) (conf: \(String(format: "%.2f", result.confidence)), time: \(String(format: "%.2f", processingTime))s)")
                
                return CategorizationResult(
                    categoryPath: categoryPath,
                    confidence: result.confidence,
                    rationale: result.rationale,
                    extractedKeywords: result.keywords,
                    provider: .appleIntelligence,
                    processingTime: processingTime,
                    shouldEscalate: shouldEscalate
                )
                
            } catch {
                lastError = error
                NSLog("⚠️ [AppleIntelligence] Attempt \(attempt + 1) failed: \(error.localizedDescription)")
                
                if attempt < config.maxRetries {
                    // Brief delay before retry
                    try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s
                }
            }
        }
        
        throw lastError
    }
    
    // MARK: - Entity Extraction
    
    func extractEntities(from text: String) async throws -> [ExtractedEntity] {
        let session = try await getSession()
        
        let prompt = """
        Extract all named entities from this text. Include:
        - People (person)
        - Organizations (organization)
        - Locations (location)
        - Dates (date)
        - Important keywords (keyword)
        - Topics/themes (topic)
        - Products mentioned (product)
        - Events (event)
        
        Text:
        \(text.prefix(3000))
        """
        
        NSLog("🔍 [AppleIntelligence] Extracting entities from \(text.count) chars")
        
        let response = try await session.respond(
            to: prompt,
            generating: EntityExtractionResponse.self
        )
        
        let entities = response.content.entities.map { item in
            ExtractedEntity(
                text: item.text,
                type: ExtractedEntityType(rawValue: item.type.lowercased()) ?? .keyword,
                confidence: item.confidence
            )
        }
        
        NSLog("✅ [AppleIntelligence] Extracted \(entities.count) entities")
        return entities
    }
    
    // MARK: - Relationship Extraction (GraphRAG)
    
    /// Extract relationships between entities for knowledge graph
    func extractRelationships(from text: String, entities: [ExtractedEntity]) async throws -> [ExtractedRelationshipItem] {
        let session = try await getSession()
        
        let entityList = entities.map { "\($0.text) (\($0.type.rawValue))" }.joined(separator: ", ")
        
        let prompt = """
        Given these entities and the source text, identify relationships between them.
        
        Entities: \(entityList)
        
        Text:
        \(text.prefix(2000))
        
        Identify relationships using these types:
        - works_for: person works for organization
        - located_in: entity is located in place
        - related_to: general relationship
        - mentions: document mentions entity
        - authored_by: document authored by person
        - part_of: entity is part of another
        """
        
        NSLog("🔗 [AppleIntelligence] Extracting relationships for \(entities.count) entities")
        
        let response = try await session.respond(
            to: prompt,
            generating: RelationshipExtractionResponse.self
        )
        
        NSLog("✅ [AppleIntelligence] Extracted \(response.content.relationships.count) relationships")
        return response.content.relationships
    }
    
    // MARK: - Embedding Generation
    
    func generateEmbedding(for text: String) async throws -> [Float] {
        // First, summarize the document for better embedding
        let session = try await getSession()
        
        let summaryPrompt = """
        Summarize this text concisely, focusing on the main topics and key entities:
        
        \(text.prefix(4000))
        """
        
        let summaryResponse = try await session.respond(
            to: summaryPrompt,
            generating: DocumentSummaryResponse.self
        )
        
        // Combine summary elements for embedding
        let embeddingText = [
            summaryResponse.content.summary,
            "Topics: " + summaryResponse.content.topics.joined(separator: ", "),
            "Entities: " + summaryResponse.content.keyEntities.joined(separator: ", ")
        ].joined(separator: " ")
        
        // Use NLEmbedding for actual vector generation
        return try await generateNLEmbedding(for: embeddingText)
    }
    
    /// Generate embedding using NaturalLanguage framework
    private func generateNLEmbedding(for text: String) async throws -> [Float] {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            throw LLMCategorizationError.embeddingNotSupported(.appleIntelligence)
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
            // Fallback: return zero vector
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
    
    // MARK: - Prompt Building
    
    private func buildCategorizationPrompt(for signature: FileSignature) -> String {
        var prompt = """
        You are a file categorization assistant. Categorize this file into a HIERARCHICAL category system.
        
        CATEGORY FORMAT: Use "/" to separate hierarchy levels. Examples:
        - "Education / Programming / Python"
        - "Entertainment / Magic / Card Tricks"
        - "Documents / Technical / Manuals"
        - "Video / Tutorials / Software"
        
        Create categories at appropriate depth (typically 2-4 levels). Be specific but not overly granular.
        
        RULES:
        1. NEVER use inappropriate categories (adult, explicit, nsfw, etc.)
        2. Use the filename as a STRONG hint for categorization
        3. If unsure, create a reasonable category based on available signals
        4. Confidence should reflect how certain you are (0.0-1.0)
        
        FILE TO CATEGORIZE:
        Name: \(signature.title).\(signature.fileExtension)
        Type: \(signature.kind.rawValue)
        """
        
        // Add metadata based on file type
        switch signature.kind {
        case .video:
            if let duration = signature.duration {
                prompt += "\nDuration: \(formatDuration(duration))"
            }
            if !signature.sceneTags.isEmpty {
                let safeTags = signature.sceneTags.filter { !isBlockedTag($0) }
                if !safeTags.isEmpty {
                    prompt += "\nVisual themes: \(safeTags.prefix(5).joined(separator: ", "))"
                }
            }
            if !signature.detectedObjects.isEmpty {
                prompt += "\nObjects detected: \(signature.detectedObjects.prefix(5).joined(separator: ", "))"
            }
            
        case .document:
            if let pageCount = signature.pageCount {
                prompt += "\nPages: \(pageCount)"
            }
            
        case .image:
            if !signature.sceneTags.isEmpty {
                let safeTags = signature.sceneTags.filter { !isBlockedTag($0) }
                if !safeTags.isEmpty {
                    prompt += "\nImage content: \(safeTags.prefix(5).joined(separator: ", "))"
                }
            }
            
        case .audio:
            if let duration = signature.duration {
                prompt += "\nDuration: \(formatDuration(duration))"
            }
            
        case .unknown:
            break
        }
        
        // Add text content preview
        if !signature.textualCue.isEmpty {
            let preview = String(signature.textualCue.prefix(800))
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            prompt += "\n\nContent preview:\n\(preview)"
        }
        
        return prompt
    }
    
    // MARK: - Helpers
    
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
    
    private func isBlockedTag(_ tag: String) -> Bool {
        let blocked = ["adult", "explicit", "nsfw", "mature", "xxx"]
        let lower = tag.lowercased()
        return blocked.contains { lower.contains($0) }
    }
}

// MARK: - Fallback for Older macOS

/// Stub provider for macOS < 26 that always returns unavailable
@available(macOS, deprecated: 26.0, message: "Use AppleIntelligenceProvider directly on macOS 26+")
actor AppleIntelligenceProviderStub: LLMCategorizationProvider {
    nonisolated let identifier = LLMProviderIdentifier.appleIntelligence
    nonisolated let priority = 1
    nonisolated let capabilities = ProviderCapabilities.appleIntelligence
    
    func isAvailable() async -> Bool {
        return false
    }
    
    func categorize(signature: FileSignature) async throws -> CategorizationResult {
        throw LLMCategorizationError.macOSVersionTooLow(
            required: "26.0",
            current: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
    
    func extractEntities(from text: String) async throws -> [ExtractedEntity] {
        throw LLMCategorizationError.macOSVersionTooLow(
            required: "26.0",
            current: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
    
    func generateEmbedding(for text: String) async throws -> [Float] {
        throw LLMCategorizationError.macOSVersionTooLow(
            required: "26.0",
            current: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
}

