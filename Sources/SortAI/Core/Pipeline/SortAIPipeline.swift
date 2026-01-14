// MARK: - SortAI Pipeline
// Orchestrates the Eye -> Memory -> Knowledge Graph -> Brain flow

import Foundation

// MARK: - Pipeline Errors

enum PipelineError: LocalizedError {
    case notInitialized
    case inspectionFailed(String)
    case brainUnavailable
    case memoryCorrupted
    case knowledgeGraphUnavailable
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Pipeline not initialized"
        case .inspectionFailed(let reason):
            return "File inspection failed: \(reason)"
        case .brainUnavailable:
            return "Brain (Ollama) is not available"
        case .memoryCorrupted:
            return "Memory store is corrupted"
        case .knowledgeGraphUnavailable:
            return "Knowledge graph is not available"
        }
    }
}

// MARK: - Pipeline Configuration

struct SortAIPipelineConfiguration: Sendable {
    let brainConfig: BrainConfiguration
    let embeddingDimensions: Int
    let memorySimilarityThreshold: Double
    let useMemoryFirst: Bool
    let useKnowledgeGraph: Bool
    
    // v2.0: AI Provider settings
    let providerPreference: ProviderPreference
    let escalationThreshold: Double
    let autoAcceptThreshold: Double
    let autoInstallOllama: Bool
    
    static let `default` = SortAIPipelineConfiguration(
        brainConfig: .default,
        embeddingDimensions: 384,
        memorySimilarityThreshold: 0.85,
        useMemoryFirst: true,
        useKnowledgeGraph: true,
        providerPreference: .automatic,
        escalationThreshold: 0.5,
        autoAcceptThreshold: 0.85,
        autoInstallOllama: true
    )
}

// MARK: - SortAI Pipeline

/// Main orchestrator that connects Eye -> Memory -> Knowledge Graph -> Unified Categorization
/// Follows the data flow: File Input -> Router -> Eye -> Memory Check -> Graph -> AI Provider Cascade -> Output
/// Supports dependency injection via protocol-typed components for testing
actor SortAIPipeline: FileProcessing {
    
    // MARK: - Components (Protocol-Typed for DI)
    
    private let inspector: any MediaInspecting
    private let brain: any FileCategorizing  // Legacy: kept for knowledge graph updates
    private let memoryStore: any PatternMatching
    private let embeddingGenerator: any EmbeddingGenerating
    private let config: SortAIPipelineConfiguration
    
    // v2.0: Unified categorization service with provider cascade
    private var categorizationService: UnifiedCategorizationService?
    
    // Concrete types for knowledge graph (optional)
    private var knowledgeGraph: KnowledgeGraphStore?
    private var feedbackManager: FeedbackManager?
    
    // Keep reference to concrete Brain for knowledge graph updates only
    private var concreteBrain: Brain?
    
    // Performance optimization components
    private let quickCategorizer = QuickCategorizer()
    private let inspectionCache = InspectionCache()
    
    // MARK: - State
    
    private var isInitialized = false
    private var processedCount = 0
    private var memoryHitCount = 0
    private var graphHitCount = 0
    private var cacheHitCount = 0
    
    // MARK: - Initialization (Production)
    
    /// Creates a pipeline with default production components
    init(configuration: SortAIPipelineConfiguration = .default) async throws {
        self.config = configuration
        
        // Create production components
        let inspector = MediaInspector()
        let brain = Brain(configuration: configuration.brainConfig)
        let memoryStore = try MemoryStore(
            embeddingDimensions: configuration.embeddingDimensions,
            similarityThreshold: configuration.memorySimilarityThreshold
        )
        let embeddingGenerator = EmbeddingGenerator(
            configuration: configuration.brainConfig,
            dimensions: configuration.embeddingDimensions
        )
        
        self.inspector = inspector
        self.brain = brain
        self.memoryStore = memoryStore
        self.embeddingGenerator = embeddingGenerator
        self.concreteBrain = brain
        
        // v2.0: Create unified categorization service with provider cascade
        // Apple Intelligence → Ollama → Cloud → Local ML
        let serviceConfig = UnifiedCategorizationService.Configuration(
            preference: configuration.providerPreference,
            escalationThreshold: configuration.escalationThreshold,
            autoAcceptThreshold: configuration.autoAcceptThreshold,
            autoInstallOllama: configuration.autoInstallOllama,
            maxRetryAttempts: 1
        )
        let service = await UnifiedCategorizationService(configuration: serviceConfig)
        self.categorizationService = service
        
        // Connect service to Brain for legacy compatibility
        await brain.setCategorizationService(service)
        
        NSLog("✅ [Pipeline] UnifiedCategorizationService created with preference: %@", 
              configuration.providerPreference.rawValue)
        
        // Initialize knowledge graph if enabled
        if configuration.useKnowledgeGraph {
            do {
                knowledgeGraph = try KnowledgeGraphStore()
                feedbackManager = try await FeedbackManager(knowledgeGraph: knowledgeGraph!)
                await brain.setKnowledgeGraph(knowledgeGraph!)
                
                // Also set knowledge graph on the service's graph enhancer
                // (service handles this internally when categorizing)
                
                NSLog("✅ [Pipeline] Knowledge graph initialized")
            } catch {
                NSLog("⚠️ [Pipeline] Could not initialize knowledge graph: %@", error.localizedDescription)
            }
        }
        
        // Provider availability is handled internally by UnifiedCategorizationService
        // No need for explicit Ollama health check - the cascade handles this
        let stats = await service.getStatistics()
        NSLog("📱 [Pipeline] Providers available: %@", 
              stats.availableProviders.map { $0.displayName }.joined(separator: ", "))
        
        isInitialized = true
    }
    
    // MARK: - Initialization (Dependency Injection)
    
    /// Creates a pipeline with injected components for testing or customization
    /// - Parameters:
    ///   - configuration: Pipeline configuration
    ///   - inspector: Media inspection component
    ///   - categorizer: File categorization component (Brain)
    ///   - patternMatcher: Pattern matching component (MemoryStore)
    ///   - embeddingGenerator: Embedding generation component
    init(
        configuration: SortAIPipelineConfiguration,
        inspector: any MediaInspecting,
        categorizer: any FileCategorizing,
        patternMatcher: any PatternMatching,
        embeddingGenerator: any EmbeddingGenerating
    ) {
        self.config = configuration
        self.inspector = inspector
        self.brain = categorizer
        self.memoryStore = patternMatcher
        self.embeddingGenerator = embeddingGenerator
        self.concreteBrain = nil
        self.knowledgeGraph = nil
        self.feedbackManager = nil
        self.isInitialized = true
    }
    
    /// Creates a pipeline using a component factory
    /// - Parameters:
    ///   - configuration: Pipeline configuration
    ///   - factory: Factory for creating components
    init(
        configuration: SortAIPipelineConfiguration,
        factory: any ComponentFactory
    ) throws {
        self.config = configuration
        self.inspector = factory.createInspector()
        self.brain = factory.createCategorizer(configuration: configuration.brainConfig)
        self.memoryStore = try factory.createPatternMatcher(
            embeddingDimensions: configuration.embeddingDimensions,
            similarityThreshold: configuration.memorySimilarityThreshold
        )
        self.embeddingGenerator = factory.createEmbeddingGenerator(
            configuration: configuration.brainConfig,
            dimensions: configuration.embeddingDimensions
        )
        self.concreteBrain = nil
        self.knowledgeGraph = nil
        self.feedbackManager = nil
        self.isInitialized = true
    }
    
    // MARK: - Main Processing
    
    /// Processes a single file through the complete pipeline
    /// Flow: File -> Eye (inspection) -> Memory (check) || Brain (categorize) -> Result
    /// OPTIMIZED: Memory lookup and Brain categorization run in parallel
    func process(url: URL) async throws -> ProcessingResult {
        guard isInitialized else {
            throw PipelineError.notInitialized
        }
        
        // Step 1: Eye - Extract signals (this is the main time consumer)
        let signature: FileSignature
        do {
            signature = try await inspector.inspect(url: url)
        } catch {
            throw PipelineError.inspectionFailed(error.localizedDescription)
        }
        
        // Step 2: Quick exact match check (fast - just DB lookup)
        if let existingPattern = try? memoryStore.findByChecksum(signature.checksum) {
            // Record hit (non-critical - log failures)
            do {
                try memoryStore.recordHit(patternId: existingPattern.id)
            } catch {
                NSLog("⚠️ [Pipeline] Failed to record memory hit: \(error.localizedDescription)")
            }
            memoryHitCount += 1
            
            // Parse the stored label back into a CategoryPath
            // The label is stored as "Main / Sub1 / Sub2" format
            let storedPath = CategoryPath(path: existingPattern.label, separator: " / ")
            let subcategories = Array(storedPath.components.dropFirst())
            
            return ProcessingResult(
                signature: signature,
                brainResult: BrainResult(
                    category: storedPath.root,
                    subcategory: subcategories.first,
                    confidence: existingPattern.confidence,
                    rationale: "Matched from memory (exact file)",
                    allSubcategories: subcategories
                ),
                wasFromMemory: true
            )
        }
        
        // Step 3: Run memory similarity check AND brain categorization in PARALLEL
        // This way we don't wait for memory if it's slow
        async let memoryTask: (LearnedPattern, Double)? = performMemoryLookup(signature: signature)
        async let brainTask: BrainResult = performBrainCategorization(signature: signature)
        
        // Wait for both to complete
        let (memoryMatch, brainResult) = await (try? memoryTask, brainTask)
        
        // Use memory if it has a high-confidence match
        if let match = memoryMatch, match.1 >= config.memorySimilarityThreshold {
            // Record hit (non-critical - log failures)
            do {
                try memoryStore.recordHit(patternId: match.0.id)
            } catch {
                NSLog("⚠️ [Pipeline] Failed to record memory hit (similarity): \(error.localizedDescription)")
            }
            memoryHitCount += 1
            
            // Parse the stored label back into a CategoryPath
            let storedPath = CategoryPath(path: match.0.label, separator: " / ")
            let subcategories = Array(storedPath.components.dropFirst())
            
            let result = ProcessingResult(
                signature: signature,
                brainResult: BrainResult(
                    category: storedPath.root,
                    subcategory: subcategories.first,
                    confidence: match.1,
                    rationale: "Matched from memory (\(Int(match.1 * 100))% similar)",
                    allSubcategories: subcategories
                ),
                wasFromMemory: true
            )
            
            // Add to feedback queue for tracking (non-critical - log failures)
            do {
                _ = try await feedbackManager?.addToQueue(
                    fileURL: url,
                    category: result.brainResult.category,
                    subcategories: result.brainResult.allSubcategories,
                    confidence: result.brainResult.confidence,
                    rationale: result.brainResult.rationale.isEmpty ? "From memory" : result.brainResult.rationale,
                    keywords: result.brainResult.tags
                )
            } catch {
                NSLog("⚠️ [Pipeline] Failed to add memory match to feedback queue: \(error.localizedDescription)")
            }
            
            return result
        }
        
        // Use brain result
        let result = ProcessingResult(
            signature: signature,
            brainResult: brainResult,
            wasFromMemory: false
        )
        
        // Add to feedback queue (handles learning and auto-acceptance internally, log failures)
        do {
            _ = try await feedbackManager?.addToQueue(
                fileURL: url,
                category: brainResult.category,
                subcategories: brainResult.allSubcategories,
                confidence: brainResult.confidence,
                rationale: brainResult.rationale.isEmpty ? "From LLM" : brainResult.rationale,
                keywords: brainResult.tags
            )
        } catch {
            NSLog("⚠️ [Pipeline] Failed to add brain result to feedback queue: \(error.localizedDescription)")
        }
        
        // Save to memory record
        // Save processing record (only if concrete MemoryStore available)
        if let concreteMemory = memoryStore as? MemoryStore {
            let record = ProcessingRecord(
                fileURL: url,
                checksum: signature.checksum,
                mediaKind: signature.kind,
                assignedCategory: brainResult.category,
                confidence: brainResult.confidence,
                wasFromMemory: false
            )
            try? concreteMemory.saveRecord(record)
        }
        
        // Save pattern for high-confidence auto-accepted results
        // This enables instant recognition by checksum on future encounters
        await saveAutoAcceptedPattern(signature: signature, brainResult: brainResult)
        
        processedCount += 1
        return result
    }
    
    /// Memory lookup helper - returns pattern and similarity score
    private func performMemoryLookup(signature: FileSignature) async throws -> (LearnedPattern, Double)? {
        guard config.useMemoryFirst else { return nil }
        
        let embedding = try await embeddingGenerator.generateEmbedding(for: signature)
        return try? memoryStore.queryNearest(embedding: embedding, threshold: config.memorySimilarityThreshold)
    }
    
    /// Categorization helper - uses UnifiedCategorizationService with provider cascade
    /// Provider cascade: Apple Intelligence → Ollama → Cloud → Local ML
    private func performBrainCategorization(signature: FileSignature) async -> BrainResult {
        // v2.0: Use unified service directly for provider cascade
        if let service = categorizationService {
            do {
                let result = try await service.categorize(signature: signature)
                
                // Log which provider was used
                NSLog("✅ [Pipeline] Categorized with %@: %@ (%.1f%%)",
                      result.provider.displayName,
                      result.categoryPath.description,
                      result.confidence * 100)
                
                // Convert CategorizationResult to BrainResult for backward compatibility
                return BrainResult(
                    category: result.categoryPath.root,
                    subcategory: result.categoryPath.components.dropFirst().first,
                    confidence: result.confidence,
                    rationale: result.rationale,
                    suggestedPath: result.categoryPath.description,
                    tags: result.extractedKeywords,
                    allSubcategories: Array(result.categoryPath.components.dropFirst()),
                    provider: result.provider  // Track which provider was used
                )
            } catch {
                NSLog("⚠️ [Pipeline] Categorization failed: %@", error.localizedDescription)
                return BrainResult(
                    category: "Uncategorized",
                    subcategory: "Error",
                    confidence: 0.0,
                    rationale: "Categorization failed: \(error.localizedDescription)"
                )
            }
        }
        
        // Fallback: Use Brain directly (legacy path)
        do {
            let enhanced = try await brain.categorize(signature: signature)
            return BrainResult(
                category: enhanced.category,
                subcategory: enhanced.subcategories.first,
                confidence: enhanced.confidence,
                rationale: enhanced.rationale,
                suggestedPath: enhanced.categoryPath.description,
                tags: enhanced.extractedKeywords,
                allSubcategories: enhanced.subcategories
            )
        } catch {
            return BrainResult(
                category: "Uncategorized",
                subcategory: "Error",
                confidence: 0.0,
                rationale: "Brain unavailable: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Knowledge Graph Learning
    
    /// Learns from human feedback and updates the knowledge graph
    func learnFromFeedback(item: FeedbackItem, accepted: Bool, correctedPath: CategoryPath? = nil) async throws {
        guard let feedback = feedbackManager else { return }
        
        if accepted {
            try await feedback.acceptSuggestion(itemId: item.id!)
        } else if let newPath = correctedPath {
            _ = try await feedback.createNewCategory(
                itemId: item.id!,
                categoryPath: newPath
            )
        }
    }
    
    /// Gets pending feedback items for review
    func getPendingFeedback() throws -> [FeedbackItem] {
        guard let feedback = feedbackManager else { return [] }
        return try feedback.getPendingItems()
    }
    
    /// Gets feedback queue statistics
    func getFeedbackStats() throws -> QueueStatistics {
        guard let feedback = feedbackManager else {
            return QueueStatistics(
                pendingReview: 0,
                autoAccepted: 0,
                humanAccepted: 0,
                humanCorrected: 0,
                total: 0
            )
        }
        return try feedback.getQueueStats()
    }
    
    /// Gets existing categories from the knowledge graph
    func getExistingCategories() async -> [CategoryPath] {
        await brain.getExistingCategories(limit: 50)
    }
    
    /// Maximum concurrent file processing tasks (prevents resource exhaustion)
    private static let maxConcurrentProcessing = 5
    
    /// Batch size for strict batch processing (all complete before next batch starts)
    private static let batchSize = 5
    
    /// Processes multiple files with controlled concurrency and progress callbacks
    /// Uses strict batch processing: complete batch N before starting batch N+1
    /// Reports progress via callback for real-time UI updates
    func processAll(
        urls: [URL],
        onProgress: ProgressCallback? = nil
    ) async throws -> [ProcessingResult] {
        guard !urls.isEmpty else { return [] }
        
        let batchSize = Self.batchSize
        NSLog("📁 [Pipeline] Processing \(urls.count) files in batches of \(batchSize)")
        
        var allResults: [ProcessingResult] = []
        
        // Process in strict batches
        for batchStart in stride(from: 0, to: urls.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, urls.count)
            let batchURLs = Array(urls[batchStart..<batchEnd])
            
            NSLog("📁 [Pipeline] Starting batch \(batchStart/batchSize + 1): files \(batchStart+1)-\(batchEnd) of \(urls.count)")
            
            // Process this batch with progress reporting
            let batchResults = try await processBatch(
                urls: batchURLs,
                onProgress: onProgress
            )
            
            allResults.append(contentsOf: batchResults)
            
            NSLog("📁 [Pipeline] Batch \(batchStart/batchSize + 1) complete: \(batchResults.count) results")
        }
        
        return allResults
    }
    
    /// Process a single batch of files concurrently
    /// Uses non-throwing task group to ensure one file failure doesn't stop others
    private func processBatch(
        urls: [URL],
        onProgress: ProgressCallback?
    ) async throws -> [ProcessingResult] {
        
        // Use regular TaskGroup (non-throwing) to ensure failures don't cancel other tasks
        return await withTaskGroup(of: (Int, ProcessingResult?).self) { group in
            var results = [ProcessingResult?](repeating: nil, count: urls.count)
            
            // Start all tasks in this batch
            for (index, url) in urls.enumerated() {
                group.addTask {
                    do {
                        let result = try await self.processWithProgress(
                            url: url,
                            onProgress: onProgress
                        )
                        return (index, result)
                    } catch {
                        // Log the error but don't stop other tasks
                        NSLog("⚠️ [Pipeline] File processing failed: \(url.lastPathComponent) - \(error.localizedDescription)")
                        
                        // Report failure via progress callback (already done in processWithProgress,
                        // but ensure it's called even for unexpected errors)
                        await onProgress?(url, .failed(error.localizedDescription))
                        
                        return (index, nil)
                    }
                }
            }
            
            // Wait for ALL tasks in batch to complete (failures included)
            for await (index, result) in group {
                results[index] = result
            }
            
            return results.compactMap { $0 }
        }
    }
    
    /// Process a single file with progress reporting
    func processWithProgress(
        url: URL,
        onProgress: ProgressCallback?
    ) async throws -> ProcessingResult {
        
        // Step 1: Quick categorization (immediate feedback)
        let quickResult = await quickCategorizer.categorize(url: url)
        await onProgress?(url, .quickCategorized(
            category: quickResult.category,
            subcategory: quickResult.subcategory,
            confidence: quickResult.confidence
        ))
        
        // Step 2: Check inspection cache
        let cachedSignature = try? await inspectionCache.get(url: url)
        
        let signature: FileSignature
        if let cached = cachedSignature {
            NSLog("⚡ [Pipeline] Cache hit for \(url.lastPathComponent)")
            signature = cached
            cacheHitCount += 1
            await onProgress?(url, .inspectionCached)
        } else {
            // Step 3: Full inspection (slow for video/audio)
            await onProgress?(url, .inspecting)
            
            do {
                signature = try await inspector.inspect(url: url)
                // Cache the result
                try? await inspectionCache.set(url: url, signature: signature)
            } catch {
                await onProgress?(url, .failed("Inspection failed: \(error.localizedDescription)"))
                throw PipelineError.inspectionFailed(error.localizedDescription)
            }
        }
        
        // Step 4: Memory/Brain categorization
        await onProgress?(url, .categorizing)
        
        // Check exact match first
        if let existingPattern = try? memoryStore.findByChecksum(signature.checksum) {
            try? memoryStore.recordHit(patternId: existingPattern.id)
            memoryHitCount += 1
            
            // Parse the stored label back into a CategoryPath
            let storedPath = CategoryPath(path: existingPattern.label, separator: " / ")
            let subcategories = Array(storedPath.components.dropFirst())
            
            let result = ProcessingResult(
                signature: signature,
                brainResult: BrainResult(
                    category: storedPath.root,
                    subcategory: subcategories.first,
                    confidence: existingPattern.confidence,
                    rationale: "Matched from memory (exact file)",
                    allSubcategories: subcategories
                ),
                wasFromMemory: true
            )
            
            await onProgress?(url, .completed(result))
            return result
        }
        
        // Run memory similarity and brain categorization in parallel
        async let memoryTask: (LearnedPattern, Double)? = performMemoryLookup(signature: signature)
        async let brainTask: BrainResult = performBrainCategorization(signature: signature)
        
        let (memoryMatch, brainResult) = await (try? memoryTask, brainTask)
        
        // Use memory if high confidence match
        if let match = memoryMatch, match.1 >= config.memorySimilarityThreshold {
            try? memoryStore.recordHit(patternId: match.0.id)
            memoryHitCount += 1
            
            // Parse the stored label back into a CategoryPath
            let storedPath = CategoryPath(path: match.0.label, separator: " / ")
            let subcategories = Array(storedPath.components.dropFirst())
            
            let result = ProcessingResult(
                signature: signature,
                brainResult: BrainResult(
                    category: storedPath.root,
                    subcategory: subcategories.first,
                    confidence: match.1,
                    rationale: "Matched from memory (\(Int(match.1 * 100))% similar)",
                    allSubcategories: subcategories
                ),
                wasFromMemory: true
            )
            
            _ = try? await feedbackManager?.addToQueue(
                fileURL: url,
                category: result.brainResult.category,
                subcategories: result.brainResult.allSubcategories,  // Use ALL subcategories
                confidence: result.brainResult.confidence,
                rationale: result.brainResult.rationale.isEmpty ? "From memory" : result.brainResult.rationale,
                keywords: result.brainResult.tags
            )
            
            await onProgress?(url, .completed(result))
            return result
        }
        
        // Use brain result
        let result = ProcessingResult(
            signature: signature,
            brainResult: brainResult,
            wasFromMemory: false
        )
        
        _ = try? await feedbackManager?.addToQueue(
            fileURL: url,
            category: brainResult.category,
            subcategories: brainResult.allSubcategories,  // Use ALL subcategories
            confidence: brainResult.confidence,
            rationale: brainResult.rationale.isEmpty ? "From LLM" : brainResult.rationale,
            keywords: brainResult.tags
        )
        
        // Save processing record
        if let concreteMemory = memoryStore as? MemoryStore {
            let record = ProcessingRecord(
                fileURL: url,
                checksum: signature.checksum,
                mediaKind: signature.kind,
                assignedCategory: brainResult.category,
                confidence: brainResult.confidence,
                wasFromMemory: false
            )
            try? concreteMemory.saveRecord(record)
        }
        
        // Save pattern for high-confidence auto-accepted results
        // This enables instant recognition by checksum on future encounters
        await saveAutoAcceptedPattern(signature: signature, brainResult: brainResult)
        
        processedCount += 1
        await onProgress?(url, .completed(result))
        return result
    }
    
    /// Legacy processAll without progress callback
    func processAll(urls: [URL]) async throws -> [ProcessingResult] {
        try await processAll(urls: urls, onProgress: nil)
    }
    
    // MARK: - Learning (Undo Corrections)
    
    /// Learns from user correction and stores in memory + knowledge graph
    func learnCorrection(signature: FileSignature, correctedPath: CategoryPath) async throws {
        let embedding = try await embeddingGenerator.generateEmbedding(for: signature)
        let correctedLabel = correctedPath.description
        
        // Save to memory store using protocol method
        try memoryStore.savePattern(
            signature: signature,
            embedding: embedding,
            label: correctedLabel,
            originalLabel: nil,
            confidence: 1.0
        )
        
        // Save to knowledge graph (GraphRAG)
        if let graph = knowledgeGraph {
            // Create category in graph
            _ = try graph.getOrCreateCategoryPath(correctedPath)
            
            // Learn from keywords in title
            let keywords = signature.title
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 }
            
            let categoryEntity = try graph.getOrCreateCategoryPath(correctedPath)
            for keyword in keywords {
                try graph.learnKeywordSuggestion(
                    keyword: keyword,
                    categoryId: categoryEntity.id!,
                    weight: 0.8  // Human corrections are strong signals
                )
            }
        }
        
        // Update brain's recent categories (only if concrete Brain available)
        if let concreteBrain = concreteBrain {
            await concreteBrain.addRecentCategory(correctedPath)
        }
    }
    
    /// Saves a pattern for an auto-accepted high-confidence result
    /// This enables future instant recognition by checksum lookup
    private func saveAutoAcceptedPattern(signature: FileSignature, brainResult: BrainResult) async {
        // Only save patterns for high confidence results (>= 0.85)
        // Uses memorySimilarityThreshold as the bar for "trustworthy enough to remember"
        guard brainResult.confidence >= config.memorySimilarityThreshold else { return }
        
        do {
            // Generate embedding for this file
            let embedding = try await embeddingGenerator.generateEmbedding(for: signature)
            let label = brainResult.fullCategoryPath.description
            
            // Save to memory store - this enables checksum-based instant lookup
            try memoryStore.savePattern(
                signature: signature,
                embedding: embedding,
                label: label,
                originalLabel: nil,
                confidence: brainResult.confidence
            )
            
            NSLog("💾 [Pipeline] Saved auto-accepted pattern: %@ -> %@ (checksum: %@)",
                  signature.title, label, String(signature.checksum.prefix(8)))
            
            // Also update brain's recent categories for better suggestions
            if let concreteBrain = concreteBrain {
                await concreteBrain.addRecentCategory(brainResult.fullCategoryPath)
            }
        } catch {
            // Non-fatal - pattern saving is optional for auto-accepted files
            NSLog("⚠️ [Pipeline] Failed to save auto-accepted pattern: %@", error.localizedDescription)
        }
    }
    
    /// Learns from a complete result with correction (uses CategoryPath)
    func learnFromResult(_ result: ProcessingResult, correctedPath: CategoryPath?) async throws {
        guard let correctedPath = correctedPath else { return }
        
        let embedding = try await embeddingGenerator.generateEmbedding(for: result.signature)
        let correctedLabel = correctedPath.description
        
        // Save to memory store using protocol method
        try memoryStore.savePattern(
            signature: result.signature,
            embedding: embedding,
            label: correctedLabel,
            originalLabel: result.brainResult.category,
            confidence: 1.0
        )
        
        // Save to knowledge graph
        if let graph = knowledgeGraph {
            let categoryEntity = try graph.getOrCreateCategoryPath(correctedPath)
            
            // Record as human confirmed
            let fileEntity = try graph.findOrCreateEntity(
                type: .file,
                name: result.signature.title,
                metadata: ["path": result.signature.url.path]
            )
            try graph.recordHumanConfirmation(fileId: fileEntity.id!, categoryId: categoryEntity.id!)
            
            // Learn keywords
            for keyword in result.brainResult.tags {
                try graph.learnKeywordSuggestion(
                    keyword: keyword,
                    categoryId: categoryEntity.id!,
                    weight: 0.7
                )
            }
        }
        
        // Update processing record as overridden (only if concrete MemoryStore available)
        if let concreteMemory = memoryStore as? MemoryStore {
            let record = ProcessingRecord(
                fileURL: result.signature.url,
                checksum: result.signature.checksum,
                mediaKind: result.signature.kind,
                assignedCategory: correctedLabel,
                confidence: 1.0,
                wasFromMemory: false,
                wasOverridden: true
            )
            try concreteMemory.saveRecord(record)
        }
        
        // Update brain's recent categories (only if concrete Brain available)
        if let concreteBrain = concreteBrain {
            await concreteBrain.addRecentCategory(correctedPath)
        }
    }
    
    /// Legacy: Learns from string label (converts to CategoryPath)
    func learnFromResult(_ result: ProcessingResult, correctedLabel: String) async throws {
        let path = CategoryPath(path: correctedLabel)
        try await learnFromResult(result, correctedPath: path)
    }
    
    // MARK: - Statistics
    
    var statistics: PipelineStatistics {
        get async {
            // Get memory stats (only if concrete MemoryStore available)
            var patternCount = 0
            var recordCount = 0
            var categoryStats: [CategoryStats] = []
            if let concreteMemory = memoryStore as? MemoryStore {
                patternCount = (try? concreteMemory.patternCount()) ?? 0
                recordCount = (try? concreteMemory.recordCount()) ?? 0
                categoryStats = (try? concreteMemory.categoryStatistics()) ?? []
            }
            
            // Get graph statistics if available
            var graphStats: GraphStatistics?
            if let graph = knowledgeGraph {
                graphStats = try? graph.getStatistics()
            }
            
            return PipelineStatistics(
                totalProcessed: processedCount,
                memoryHits: memoryHitCount,
                graphHits: graphHitCount,
                memoryHitRate: processedCount > 0 ? Double(memoryHitCount) / Double(processedCount) : 0,
                learnedPatterns: patternCount,
                totalRecords: recordCount,
                categoryBreakdown: categoryStats,
                graphStatistics: graphStats
            )
        }
    }
    
    /// Protocol method for getting statistics
    func getStatistics() async -> (Int, Int, Int) {
        return (processedCount, memoryHitCount, graphHitCount)
    }
    
    // MARK: - Health
    
    func healthCheck() async -> PipelineHealth {
        let brainHealthy = await brain.healthCheck()
        let memoryHealthy: Bool
        if let concreteMemory = memoryStore as? MemoryStore {
            memoryHealthy = (try? concreteMemory.patternCount()) != nil
        } else {
            memoryHealthy = true // Assume healthy for mocked stores
        }
        let graphHealthy = knowledgeGraph != nil
        
        let status: PipelineHealth.Status
        if brainHealthy && memoryHealthy && graphHealthy {
            status = .healthy
        } else if memoryHealthy || graphHealthy {
            status = .degraded
        } else {
            status = .unhealthy
        }
        
        return PipelineHealth(
            isInitialized: isInitialized,
            brainAvailable: brainHealthy,
            memoryAvailable: memoryHealthy,
            graphAvailable: graphHealthy,
            status: status
        )
    }
}

// MARK: - Supporting Types

struct PipelineStatistics: Sendable {
    let totalProcessed: Int
    let memoryHits: Int
    let graphHits: Int
    let memoryHitRate: Double
    let learnedPatterns: Int
    let totalRecords: Int
    let categoryBreakdown: [CategoryStats]
    let graphStatistics: GraphStatistics?
    
    var combinedHitRate: Double {
        guard totalProcessed > 0 else { return 0 }
        return Double(memoryHits + graphHits) / Double(totalProcessed)
    }
}

struct PipelineHealth: Sendable {
    let isInitialized: Bool
    let brainAvailable: Bool
    let memoryAvailable: Bool
    let graphAvailable: Bool
    let status: Status
    
    enum Status {
        case healthy
        case degraded
        case unhealthy
    }
    
    var description: String {
        switch status {
        case .healthy: return "All systems operational"
        case .degraded: return "Running with reduced functionality"
        case .unhealthy: return "System unavailable"
        }
    }
}

