// MARK: - Unified Categorization Service
// Orchestrates the provider cascade: Apple Intelligence → Ollama → Cloud → Local ML
// Manages provider lifecycle, escalation, and settings availability

import Foundation
import Combine
import NaturalLanguage

// MARK: - Service State

/// Observable state for the unified categorization service
@Observable
final class UnifiedCategorizationState: @unchecked Sendable {
    /// Currently active provider
    var activeProvider: LLMProviderIdentifier = .appleIntelligence
    
    /// Whether escalation is in progress
    var isEscalating: Bool = false
    
    /// Available providers (checked at runtime)
    var availableProviders: Set<LLMProviderIdentifier> = []
    
    /// Last error message (if any)
    var lastError: String?
    
    /// Whether Ollama installation was offered
    var ollamaInstallOffered: Bool = false
    
    /// Processing statistics
    var totalCategorizations: Int = 0
    var escalationCount: Int = 0
    var averageProcessingTime: TimeInterval = 0
}

// MARK: - Unified Categorization Service

/// Central service managing all LLM providers with cascade logic
actor UnifiedCategorizationService {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        var preference: ProviderPreference
        var escalationThreshold: Double
        var autoAcceptThreshold: Double
        var autoInstallOllama: Bool
        var maxRetryAttempts: Int
        
        static let `default` = Configuration(
            preference: .automatic,
            escalationThreshold: 0.5,
            autoAcceptThreshold: 0.85,
            autoInstallOllama: true,
            maxRetryAttempts: 1
        )
    }
    
    // MARK: - Properties
    
    private var providers: [LLMProviderIdentifier: any LLMCategorizationProvider] = [:]
    private var config: Configuration
    private let ollamaInstaller: OllamaInstaller
    
    /// Observable state for UI binding
    let state = UnifiedCategorizationState()
    
    // Statistics
    private var processingTimes: [TimeInterval] = []
    private let maxStoredTimes = 100
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .default) async {
        self.config = configuration
        self.ollamaInstaller = OllamaInstaller()
        await initializeProviders()
    }
    
    /// Initialize all available providers
    private func initializeProviders() async {
        NSLog("🔄 [UnifiedService] Initializing providers...")
        
        // Apple Intelligence (macOS 26+)
        if #available(macOS 26.0, *) {
            let appleProvider = AppleIntelligenceProvider(
                configuration: .init(
                    escalationThreshold: config.escalationThreshold,
                    maxRetries: config.maxRetryAttempts,
                    sessionPoolSize: 3,
                    requestTimeout: 30.0
                )
            )
            providers[.appleIntelligence] = appleProvider
            
            if await appleProvider.isAvailable() {
                state.availableProviders.insert(.appleIntelligence)
                NSLog("✅ [UnifiedService] Apple Intelligence available")
            } else {
                NSLog("⚠️ [UnifiedService] Apple Intelligence not available")
            }
        } else {
            NSLog("⚠️ [UnifiedService] Apple Intelligence requires macOS 26+")
        }
        
        // Ollama
        let ollamaProvider = OllamaCategorizationProvider()
        providers[.ollama] = ollamaProvider
        
        if await ollamaProvider.isAvailable() {
            state.availableProviders.insert(.ollama)
            NSLog("✅ [UnifiedService] Ollama available")
        } else {
            NSLog("⚠️ [UnifiedService] Ollama not available")
        }
        
        // OpenAI (if API key configured)
        // TODO: Check for API key in configuration
        // providers[.openAI] = OpenAICategorization Provider()
        
        // Local ML (always available as fallback)
        let localMLProvider = LocalMLProvider()
        providers[.localML] = localMLProvider
        state.availableProviders.insert(.localML)
        NSLog("✅ [UnifiedService] Local ML available (fallback)")
        
        // Set initial active provider based on preference
        state.activeProvider = determineActiveProvider()
        NSLog("📱 [UnifiedService] Initialized with %d providers, active: %@",
              providers.count, state.activeProvider.displayName)
    }
    
    // MARK: - Configuration
    
    /// Update service configuration
    func updateConfiguration(_ newConfig: Configuration) {
        self.config = newConfig
        state.activeProvider = determineActiveProvider()
        NSLog("📋 [UnifiedService] Configuration updated, preference: %@", newConfig.preference.rawValue)
    }
    
    /// Set provider preference
    func setPreference(_ preference: ProviderPreference) {
        config.preference = preference
        state.activeProvider = determineActiveProvider()
        NSLog("📋 [UnifiedService] Preference set to: %@", preference.rawValue)
    }
    
    /// Set escalation threshold
    func setEscalationThreshold(_ threshold: Double) {
        config.escalationThreshold = threshold
    }
    
    // MARK: - Categorization
    
    /// Categorize a file using the provider cascade
    func categorize(signature: FileSignature) async throws -> CategorizationResult {
        let orderedProviders = getProvidersForPreference()
        var lastError: Error?
        var lastLowConfidenceResult: CategorizationResult?
        var escalatedFromProvider: LLMProviderIdentifier?
        
        state.totalCategorizations += 1
        
        for providerId in orderedProviders {
            guard let provider = providers[providerId] else { continue }
            
            // Check availability
            guard await provider.isAvailable() else {
                NSLog("⚠️ [UnifiedService] Provider %@ not available, skipping", providerId.displayName)
                
                // Special handling: offer Ollama installation
                if providerId == .ollama && config.autoInstallOllama && !state.ollamaInstallOffered {
                    await handleOllamaUnavailable()
                }
                continue
            }
            
            do {
                NSLog("🧠 [UnifiedService] Trying provider: %@", providerId.displayName)
                state.activeProvider = providerId
                
                var result = try await provider.categorize(signature: signature)
                
                // Track processing time
                recordProcessingTime(result.processingTime)
                
                // Check if we should escalate
                if result.shouldEscalate && config.preference == .automatic {
                    NSLog("📈 [UnifiedService] Low confidence (%.2f < %.2f), escalating...",
                          result.confidence, config.escalationThreshold)
                    
                    state.isEscalating = true
                    state.escalationCount += 1
                    lastLowConfidenceResult = result
                    escalatedFromProvider = providerId
                    continue
                }
                
                state.isEscalating = false
                
                // Add escalation info if we escalated
                if let originalProvider = escalatedFromProvider {
                    result = result.withEscalation(from: originalProvider)
                }
                
                return result
                
            } catch {
                NSLog("⚠️ [UnifiedService] Provider %@ failed: %@",
                      providerId.displayName, error.localizedDescription)
                lastError = error
                
                // Retry logic for transient errors
                if config.maxRetryAttempts > 0 {
                    do {
                        NSLog("🔄 [UnifiedService] Retrying %@...", providerId.displayName)
                        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s delay
                        
                        var result = try await provider.categorize(signature: signature)
                        recordProcessingTime(result.processingTime)
                        
                        if !result.shouldEscalate || config.preference != .automatic {
                            state.isEscalating = false
                            if let originalProvider = escalatedFromProvider {
                                result = result.withEscalation(from: originalProvider)
                            }
                            return result
                        }
                        
                        lastLowConfidenceResult = result
                        escalatedFromProvider = providerId
                        
                    } catch {
                        NSLog("⚠️ [UnifiedService] Retry failed: %@", error.localizedDescription)
                    }
                }
                
                continue
            }
        }
        
        state.isEscalating = false
        
        // If we have a low-confidence result, return it rather than failing
        if var result = lastLowConfidenceResult {
            NSLog("📊 [UnifiedService] Returning low-confidence result from %@", 
                  escalatedFromProvider?.displayName ?? "unknown")
            if let originalProvider = escalatedFromProvider {
                result = result.withEscalation(from: originalProvider)
            }
            return result
        }
        
        // All providers failed
        state.lastError = lastError?.localizedDescription ?? "All providers failed"
        throw LLMCategorizationError.allProvidersFailed(underlyingError: lastError)
    }
    
    // MARK: - Entity Extraction
    
    /// Extract entities using the best available provider
    func extractEntities(from text: String) async throws -> [ExtractedEntity] {
        let orderedProviders = getProvidersForPreference()
        
        for providerId in orderedProviders {
            guard let provider = providers[providerId],
                  await provider.isAvailable() else { continue }
            
            do {
                return try await provider.extractEntities(from: text)
            } catch {
                NSLog("⚠️ [UnifiedService] Entity extraction failed with %@: %@",
                      providerId.displayName, error.localizedDescription)
                continue
            }
        }
        
        return []  // Return empty if all fail
    }
    
    // MARK: - Embedding Generation
    
    /// Generate embedding using the best available provider
    func generateEmbedding(for text: String) async throws -> [Float] {
        let orderedProviders = getProvidersForPreference()
        
        for providerId in orderedProviders {
            guard let provider = providers[providerId],
                  provider.capabilities.supportsEmbeddings,
                  await provider.isAvailable() else { continue }
            
            do {
                return try await provider.generateEmbedding(for: text)
            } catch {
                NSLog("⚠️ [UnifiedService] Embedding generation failed with %@: %@",
                      providerId.displayName, error.localizedDescription)
                continue
            }
        }
        
        throw LLMCategorizationError.embeddingNotSupported(.localML)
    }
    
    // MARK: - Provider Management
    
    /// Get ordered list of providers based on preference
    private func getProvidersForPreference() -> [LLMProviderIdentifier] {
        switch config.preference {
        case .automatic:
            // Apple Intelligence → Ollama → Cloud → Local ML
            return [.appleIntelligence, .ollama, .openAI, .anthropic, .localML]
                .filter { providers[$0] != nil }
            
        case .appleIntelligenceOnly:
            // Only Apple Intelligence and local ML fallback
            return [.appleIntelligence, .localML]
                .filter { providers[$0] != nil }
            
        case .preferOllama:
            // Ollama → Apple Intelligence → Local ML
            return [.ollama, .appleIntelligence, .localML]
                .filter { providers[$0] != nil }
            
        case .cloud:
            // Cloud → Ollama → Apple Intelligence → Local ML
            return [.openAI, .anthropic, .ollama, .appleIntelligence, .localML]
                .filter { providers[$0] != nil }
        }
    }
    
    /// Determine the active provider based on preference and availability
    private func determineActiveProvider() -> LLMProviderIdentifier {
        let ordered = getProvidersForPreference()
        
        for providerId in ordered {
            if state.availableProviders.contains(providerId) {
                return providerId
            }
        }
        
        return .localML  // Always available
    }
    
    // MARK: - Ollama Installation
    
    /// Handle Ollama being unavailable
    private func handleOllamaUnavailable() async {
        state.ollamaInstallOffered = true
        
        if !ollamaInstaller.isInstalled() {
            // Show non-blocking notification
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .ollamaInstallationNeeded,
                    object: nil,
                    userInfo: ["installer": ollamaInstaller]
                )
            }
        } else if await !ollamaInstaller.isServerRunning() {
            // Ollama installed but not running - try to launch
            do {
                try await ollamaInstaller.launchOllama()
                state.availableProviders.insert(.ollama)
                NSLog("✅ [UnifiedService] Ollama server started")
            } catch {
                NSLog("❌ [UnifiedService] Failed to start Ollama: %@", error.localizedDescription)
            }
        }
    }
    
    // MARK: - Settings Availability
    
    /// Get settings availability for the current provider preference
    func getSettingsAvailability() -> ProviderSettingsAvailability {
        switch config.preference {
        case .automatic, .appleIntelligenceOnly:
            return .appleIntelligence
        case .preferOllama:
            return .ollama
        case .cloud:
            return .cloud
        }
    }
    
    /// Check if a specific provider is available
    func isProviderAvailable(_ provider: LLMProviderIdentifier) -> Bool {
        state.availableProviders.contains(provider)
    }
    
    // MARK: - Statistics
    
    private func recordProcessingTime(_ time: TimeInterval) {
        processingTimes.append(time)
        if processingTimes.count > maxStoredTimes {
            processingTimes.removeFirst()
        }
        
        state.averageProcessingTime = processingTimes.reduce(0, +) / Double(processingTimes.count)
    }
    
    /// Get service statistics
    func getStatistics() -> ServiceStatistics {
        ServiceStatistics(
            totalCategorizations: state.totalCategorizations,
            escalationCount: state.escalationCount,
            escalationRate: state.totalCategorizations > 0 
                ? Double(state.escalationCount) / Double(state.totalCategorizations) 
                : 0,
            averageProcessingTime: state.averageProcessingTime,
            availableProviders: Array(state.availableProviders),
            activeProvider: state.activeProvider
        )
    }
    
    /// Get the current provider cascade order based on preference (for testing)
    func getProviderOrder() -> [LLMProviderIdentifier] {
        getProvidersForPreference()
    }
    
    // MARK: - Health Check
    
    /// Refresh provider availability
    func refreshAvailability() async {
        NSLog("🔄 [UnifiedService] Refreshing provider availability...")
        
        var available = Set<LLMProviderIdentifier>()
        
        for (id, provider) in providers {
            if await provider.isAvailable() {
                available.insert(id)
            }
        }
        
        state.availableProviders = available
        state.activeProvider = determineActiveProvider()
        
        NSLog("✅ [UnifiedService] Available providers: %@",
              available.map { $0.displayName }.joined(separator: ", "))
    }
}

// MARK: - Service Statistics

struct ServiceStatistics: Sendable {
    let totalCategorizations: Int
    let escalationCount: Int
    let escalationRate: Double
    let averageProcessingTime: TimeInterval
    let availableProviders: [LLMProviderIdentifier]
    let activeProvider: LLMProviderIdentifier
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when Ollama installation is needed
    static let ollamaInstallationNeeded = Notification.Name("SortAI.ollamaInstallationNeeded")
    
    /// Posted when provider availability changes
    static let providerAvailabilityChanged = Notification.Name("SortAI.providerAvailabilityChanged")
}

// MARK: - Ollama Categorization Provider Wrapper

/// Wrapper around existing OllamaProvider to conform to LLMCategorizationProvider
actor OllamaCategorizationProvider: LLMCategorizationProvider {
    nonisolated let identifier = LLMProviderIdentifier.ollama
    nonisolated let priority = 2
    nonisolated let capabilities = ProviderCapabilities.ollama
    
    private let ollamaProvider: OllamaProvider
    private let modelManager: OllamaModelManager
    
    init() {
        self.ollamaProvider = OllamaProvider()
        self.modelManager = OllamaModelManager()
    }
    
    func isAvailable() async -> Bool {
        await ollamaProvider.isAvailable()
    }
    
    func categorize(signature: FileSignature) async throws -> CategorizationResult {
        let startTime = Date()
        
        // Build prompt similar to Brain
        let prompt = buildCategorizationPrompt(for: signature)
        
        // Get the best available model
        let model = await modelManager.getBestAvailableModel() ?? OllamaConfiguration.defaultModel
        let options = LLMOptions.default(model: model)
        
        // Get JSON response
        let response = try await ollamaProvider.completeJSON(prompt: prompt, options: options)
        
        // Parse response
        guard let data = response.data(using: .utf8) else {
            throw LLMCategorizationError.invalidResponse("Invalid UTF-8 response")
        }
        
        struct OllamaResponse: Decodable {
            let categoryPath: String
            let confidence: Double
            let rationale: String
            let keywords: [String]?
        }
        
        let parsed = try JSONDecoder().decode(OllamaResponse.self, from: data)
        let processingTime = Date().timeIntervalSince(startTime)
        
        return CategorizationResult(
            categoryPath: CategoryPath(path: parsed.categoryPath),
            confidence: parsed.confidence,
            rationale: parsed.rationale,
            extractedKeywords: parsed.keywords ?? [],
            provider: .ollama,
            processingTime: processingTime,
            shouldEscalate: false  // Ollama is the escalation target, don't escalate further
        )
    }
    
    func extractEntities(from text: String) async throws -> [ExtractedEntity] {
        // Use NLTagger for faster entity extraction with Ollama
        return extractEntitiesWithNLTagger(from: text)
    }
    
    func generateEmbedding(for text: String) async throws -> [Float] {
        try await ollamaProvider.embed(text: text)
    }
    
    private func buildCategorizationPrompt(for signature: FileSignature) -> String {
        var prompt = """
        You are a file categorization assistant. Categorize this file into a HIERARCHICAL category system.
        
        CATEGORY FORMAT: Use "/" to separate hierarchy levels. Examples:
        - "Education / Programming / Python"
        - "Entertainment / Magic / Card Tricks"
        
        FILE TO CATEGORIZE:
        Name: \(signature.title).\(signature.fileExtension)
        Type: \(signature.kind.rawValue)
        """
        
        if !signature.textualCue.isEmpty {
            prompt += "\n\nContent preview:\n\(signature.textualCue.prefix(800))"
        }
        
        prompt += """
        
        Return ONLY valid JSON:
        {
          "categoryPath": "Main / Sub1 / Sub2",
          "confidence": 0.85,
          "rationale": "Brief explanation",
          "keywords": ["keyword1", "keyword2"]
        }
        """
        
        return prompt
    }
    
    private func extractEntitiesWithNLTagger(from text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                            unit: .word,
                            scheme: .nameType,
                            options: options) { tag, tokenRange in
            if let tag = tag {
                let entityType: ExtractedEntityType? = switch tag {
                case .personalName: .person
                case .organizationName: .organization
                case .placeName: .location
                default: nil
                }
                
                if let type = entityType {
                    entities.append(ExtractedEntity(
                        text: String(text[tokenRange]),
                        type: type,
                        confidence: 0.8
                    ))
                }
            }
            return true
        }
        
        return entities
    }
}

// MARK: - Local ML Provider

/// Fallback provider using native Apple frameworks (Vision, NaturalLanguage)
/// Always available, capped confidence at 0.85
actor LocalMLProvider: LLMCategorizationProvider {
    nonisolated let identifier = LLMProviderIdentifier.localML
    nonisolated let priority = 100  // Lowest priority
    nonisolated let capabilities = ProviderCapabilities.localML
    
    private let quickCategorizer = QuickCategorizer()
    private let embeddingGenerator = NGramEmbeddingGenerator()
    
    func isAvailable() async -> Bool {
        true  // Always available
    }
    
    func categorize(signature: FileSignature) async throws -> CategorizationResult {
        let startTime = Date()
        
        // Use QuickCategorizer for pattern-based categorization
        let quickResult = await quickCategorizer.categorize(url: signature.url)
        
        // Build category path from result
        var components = [quickResult.category]
        if let sub = quickResult.subcategory {
            components.append(sub)
        }
        let categoryPath = CategoryPath(components: components)
        
        // Cap confidence at 0.85 for local ML
        let cappedConfidence = min(quickResult.confidence, 0.85)
        let processingTime = Date().timeIntervalSince(startTime)
        
        return CategorizationResult(
            categoryPath: categoryPath,
            confidence: cappedConfidence,
            rationale: "Categorized using local pattern matching (\(quickResult.source.rawValue))",
            extractedKeywords: extractKeywords(from: signature),
            provider: .localML,
            processingTime: processingTime,
            shouldEscalate: cappedConfidence < 0.5  // Always suggest escalation for low confidence
        )
    }
    
    func extractEntities(from text: String) async throws -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text
        
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                            unit: .word,
                            scheme: .nameType,
                            options: options) { tag, tokenRange in
            if let tag = tag {
                let entityType: ExtractedEntityType? = switch tag {
                case .personalName: .person
                case .organizationName: .organization
                case .placeName: .location
                default: nil
                }
                
                if let type = entityType {
                    entities.append(ExtractedEntity(
                        text: String(text[tokenRange]),
                        type: type,
                        confidence: 0.7
                    ))
                }
            }
            return true
        }
        
        return entities
    }
    
    func generateEmbedding(for text: String) async throws -> [Float] {
        // Use NGram embedding, padded to 512 dimensions
        var embedding = embeddingGenerator.embed(filename: text)
        
        // Pad to 512 dimensions
        if embedding.count < 512 {
            embedding.append(contentsOf: [Float](repeating: 0, count: 512 - embedding.count))
        } else if embedding.count > 512 {
            embedding = Array(embedding.prefix(512))
        }
        
        return embedding
    }
    
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
        
        // From tags
        keywords.formUnion(signature.sceneTags.map { $0.lowercased() })
        keywords.formUnion(signature.detectedObjects.map { $0.lowercased() })
        
        return Array(keywords).sorted()
    }
}

