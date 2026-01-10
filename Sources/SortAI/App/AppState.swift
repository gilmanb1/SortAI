// MARK: - Global Application State
// Reactive state management for SortAI

import Foundation
import SwiftUI
import Observation

// MARK: - Model Setup Status

/// Status of model setup during app initialization
enum ModelSetupStatus: Equatable {
    case checking
    case downloading(progress: Double)
    case ready
    case error(String)
    
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
    
    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
    
    var displayText: String {
        switch self {
        case .checking:
            return "Checking model availability..."
        case .downloading(let progress):
            return "Downloading model: \(Int(progress * 100))%"
        case .ready:
            return "Ready"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

@Observable
@MainActor
final class AppState {
    // Configuration manager
    let configManager: ConfigurationManager
    
    // Pipeline components
    var pipeline: SortAIPipeline?
    var isInitialized = false
    var lastError: String?
    
    // Model status
    var modelStatus: ModelSetupStatus = .checking
    var activeModel: String?
    var modelDownloadProgress: Double = 0
    var modelDownloadStatus: String = ""
    
    // Active workspace items
    var items: [ProcessingItem] = []
    var outputFolder: URL?
    var organizationMode: OrganizationMode = .copy
    
    // Selection state for bulk operations
    var selectedItemIds: Set<UUID> = []
    var lastSelectedItemId: UUID?  // For shift-click range selection
    var isBulkEditMode: Bool = false
    
    // Stats and Activity
    var totalProcessed: Int = 0
    var successCount: Int = 0
    var failureCount: Int = 0
    
    var activeCount: Int {
        items.filter { item in
            switch item.status {
            case .inspecting, .categorizing, .organizing: return true
            default: return false
            }
        }.count
    }
    
    var pendingReviewCount: Int {
        items.filter { $0.status == .reviewing }.count
    }
    
    var isProcessing: Bool {
        activeCount > 0
    }
    
    init(configManager: ConfigurationManager = .shared) {
        NSLog("📊 [DEBUG] AppState initializing...")
        self.configManager = configManager
        
        // Load output folder from config
        if let savedPath = configManager.config.lastOutputFolder {
            outputFolder = URL(fileURLWithPath: savedPath)
            NSLog("📊 [DEBUG] Loaded output folder: %@", savedPath)
        }
        
        // Set organization mode from config
        organizationMode = configManager.config.organization.defaultMode
        NSLog("📊 [DEBUG] Organization mode: %@", String(describing: organizationMode))
        
        Task {
            await initializePipeline()
        }
    }
    
    // MARK: - Initialization
    
    func initializePipeline() async {
        NSLog("🔧 [DEBUG] Initializing pipeline...")
        modelStatus = .checking
        
        // Check FFmpeg availability
        let ffmpegChecker = FFmpegAudioExtractor()
        let ffmpegStatus = await ffmpegChecker.checkAvailability()
        NSLog("🎬 [DEBUG] FFmpeg: %@", ffmpegStatus.statusDescription)
        
        do {
            let appConfig = configManager.config
            NSLog("🔧 [DEBUG] Config loaded")
            NSLog("📱 [DEBUG] Provider preference: %@", appConfig.aiProvider.preference.rawValue)
            
            // Configure Ollama model manager (for Ollama fallback)
            await OllamaModelManager.shared.setHost(appConfig.ollama.host)
            
            // v2.0: UnifiedCategorizationService handles provider availability internally
            // No need to pre-check Ollama - the cascade will handle unavailability gracefully
            
            // Register OllamaProvider with the global registry (for legacy compatibility)
            let ollamaProvider = OllamaProvider(
                host: appConfig.ollama.host,
                timeout: appConfig.ollama.timeout
            )
            await LLMProviderRegistry.shared.register(provider: ollamaProvider)
            
            // Create pipeline configuration with AI provider settings
            let pipelineConfig = SortAIPipelineConfiguration(
                brainConfig: appConfig.toBrainConfiguration(),
                embeddingDimensions: appConfig.memory.embeddingDimensions,
                memorySimilarityThreshold: appConfig.memory.similarityThreshold,
                useMemoryFirst: appConfig.memory.useMemoryFirst,
                useKnowledgeGraph: appConfig.knowledgeGraph.enabled,
                // v2.0: AI Provider settings for UnifiedCategorizationService
                providerPreference: appConfig.aiProvider.preference,
                escalationThreshold: appConfig.aiProvider.escalationThreshold,
                autoAcceptThreshold: appConfig.feedback.autoAcceptThreshold,
                autoInstallOllama: appConfig.aiProvider.autoInstallOllama
            )
            
            NSLog("🔧 [DEBUG] Creating pipeline with provider cascade...")
            pipeline = try await SortAIPipeline(configuration: pipelineConfig)
            isInitialized = true
            modelStatus = .ready
            
            // Display active provider info
            let preferenceDesc = appConfig.aiProvider.preference == .automatic 
                ? "Automatic (Apple Intelligence → Ollama → Local ML)"
                : appConfig.aiProvider.preference.rawValue
            NSLog("✅ [DEBUG] Pipeline initialized with provider preference: %@", preferenceDesc)
            
            // Set active model display based on preference
            switch appConfig.aiProvider.preference {
            case .automatic, .appleIntelligenceOnly:
                activeModel = "Apple Intelligence"
            case .preferOllama:
                activeModel = appConfig.ollama.documentModel
            case .cloud:
                activeModel = "Cloud (OpenAI)"
            }
            
        } catch {
            modelStatus = .error(error.localizedDescription)
            lastError = "Failed to initialize pipeline: \(error.localizedDescription)"
            NSLog("❌ [DEBUG] Pipeline initialization failed: %@", String(describing: error))
        }
    }
    
    /// Ensures the configured model is available, downloading if necessary
    private func ensureModelsAvailable(appConfig: AppConfiguration) async throws -> String {
        let requestedModel = appConfig.ollama.documentModel
        NSLog("🔍 [DEBUG] Checking availability of model: %@", requestedModel)
        
        modelStatus = .checking
        modelDownloadStatus = "Checking model availability..."
        
        // Define fallback models in order of preference
        let fallbacks = ["llama3.2", "llama3.1", "mistral", "phi3", "gemma2"]
        
        // Try to resolve the model (will download if needed)
        let resolvedModel = try await OllamaModelManager.shared.resolveModel(
            requested: requestedModel,
            fallbacks: fallbacks,
            autoDownload: true
        ) { [weak self] progress in
            Task { @MainActor in
                self?.modelStatus = .downloading(progress: progress.progress)
                self?.modelDownloadProgress = progress.progress
                self?.modelDownloadStatus = "\(progress.status): \(progress.progressPercent)%"
            }
        }
        
        return resolvedModel
    }
    
    func reloadPipeline() async {
        isInitialized = false
        pipeline = nil
        await initializePipeline()
    }
    
    // MARK: - Category Management
    
    /// Get existing categories from the knowledge graph
    func getExistingCategories() async -> [CategoryPath] {
        guard let pipeline = pipeline else {
            NSLog("⚠️ [AppState] Cannot get categories - pipeline not initialized")
            return []
        }
        
        let categories = await pipeline.getExistingCategories()
        NSLog("📋 [AppState] Retrieved %d existing categories", categories.count)
        return categories
    }
    
    // MARK: - Reactive Actions
    
    /// Adds new folders to the workspace and starts processing with controlled concurrency
    /// Uses progressive processing: quick categorization first, then full analysis
    func addFolders(_ urls: [URL]) {
        guard isInitialized, let pipeline = pipeline else { return }
        
        Task {
            let scanner = FolderScanner()
            var allFiles: [ScannedFile] = []
            
            // First, scan all folders to collect files
            for folder in urls {
                do {
                    let result = try await scanner.scan(folder: folder)
                    allFiles.append(contentsOf: result.files)
                } catch {
                    lastError = "Failed to scan folder \(folder.lastPathComponent): \(error.localizedDescription)"
                }
            }
            
            NSLog("📁 [AppState] Found \(allFiles.count) files to process")
            
            // Create all items first (for UI display)
            var itemsByURL: [URL: ProcessingItem] = [:]
            for file in allFiles {
                let item = ProcessingItem(url: file.url)
                item.startedAt = Date()
                items.insert(item, at: 0)
                itemsByURL[file.url] = item
            }
            
            // Sort items initially
            sortItemsByStatus()
            
            // Define progress callback for real-time UI updates
            let progressCallback: ProgressCallback = { [weak self] url, progress in
                guard let self = self, let item = itemsByURL[url] else { return }
                
                switch progress {
                case .quickCategorized(let category, let subcategory, let confidence):
                    item.quickCategory = category
                    item.quickSubcategory = subcategory
                    item.quickConfidence = confidence
                    item.status = .quickCategorizing
                    item.isRefining = true
                    item.progress = 0.1
                    
                case .inspecting:
                    item.status = .inspecting
                    item.progress = 0.3
                    
                case .inspectionCached:
                    item.status = .inspecting
                    item.progress = 0.5  // Skip ahead since we're using cache
                    
                case .categorizing:
                    item.status = .categorizing
                    item.progress = 0.6
                    
                case .completed(let result):
                    item.result = result
                    item.isRefining = false
                    item.progress = 0.9
                    
                    if result.brainResult.confidence >= 0.85 {
                        item.status = .accepted
                        Task { @MainActor in
                            do {
                                try await self.organizeItem(item)
                            } catch {
                                item.status = .failed("Organization failed: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        item.status = .reviewing
                        item.feedbackItem = FeedbackDisplayItem(
                            id: Int64(item.url.path.hashValue),
                            fileName: item.fileName,
                            filePath: item.url.path,
                            fileIcon: self.iconForFile(item.url),
                            categoryPath: result.brainResult.fullCategoryPath,  // Use full path!
                            confidence: result.brainResult.confidence,
                            rationale: result.brainResult.rationale.isEmpty ? "Needs review" : result.brainResult.rationale,
                            keywords: result.brainResult.tags,
                            status: .pending
                        )
                    }
                    
                    self.successCount += 1
                    self.totalProcessed += 1
                    
                case .failed(let error):
                    item.status = .failed(error)
                    item.isRefining = false
                    self.failureCount += 1
                }
                
                // Re-sort items to reflect new status
                self.sortItemsByStatus()
            }
            
            // Process through the pipeline with progress callback
            let fileURLs = allFiles.map { $0.url }
            do {
                _ = try await pipeline.processAll(urls: fileURLs, onProgress: progressCallback)
            } catch {
                lastError = "Processing failed: \(error.localizedDescription)"
                // Mark remaining queued items as failed
                for item in itemsByURL.values where item.status == .queued {
                    item.status = .failed(error.localizedDescription)
                    failureCount += 1
                }
            }
            
            NSLog("📁 [AppState] Finished processing \(allFiles.count) files")
        }
    }
    
    /// Sort items by their processing status (active at top, completed at bottom)
    func sortItemsByStatus() {
        items.sort { $0.status.sortPriority < $1.status.sortPriority }
    }
    
    /// Processes a single item through the reactive pipeline
    func processItem(_ item: ProcessingItem) {
        guard let pipeline = pipeline else { return }
        
        Task {
            do {
                item.status = .inspecting
                item.progress = 0.2
                
                // Pipeline process
                let result = try await pipeline.process(url: item.url)
                item.result = result
                item.progress = 0.8
                
                // Determine if we need review
                if result.brainResult.confidence >= 0.85 {
                    item.status = .accepted
                    try await organizeItem(item)
                } else {
                    item.status = .reviewing
                    // Create feedback display item with FULL category path from LLM
                    item.feedbackItem = FeedbackDisplayItem(
                        id: Int64(item.url.path.hashValue),
                        fileName: item.fileName,
                        filePath: item.url.path,
                        fileIcon: iconForFile(item.url),
                        categoryPath: result.brainResult.fullCategoryPath,  // Use full path!
                        confidence: result.brainResult.confidence,
                        rationale: result.brainResult.rationale.isEmpty ? "Needs review" : result.brainResult.rationale,
                        keywords: result.brainResult.tags,
                        status: .pending
                    )
                    
                    NSLog("📋 [AppState] Item needs review: %@ -> %@", 
                          item.fileName, 
                          result.brainResult.fullCategoryPath.description)
                }
            } catch {
                item.status = .failed(error.localizedDescription)
                failureCount += 1
            }
        }
    }
    
    /// Confirms a categorization and continues to organization
    func confirmItem(_ item: ProcessingItem, correctedPath: CategoryPath? = nil) {
        guard let result = item.result else { return }
        
        Task {
            do {
                item.status = .organizing
                
                // If corrected, update both the brain result AND feedbackItem
                if let newPath = correctedPath {
                    try await pipeline?.learnFromResult(result, correctedPath: newPath)
                    
                    // Get subcategories from the new path (everything after root)
                    let subcategories = Array(newPath.components.dropFirst())
                    
                    // Update result with correction (including all subcategories)
                    let updatedBrainResult = BrainResult(
                        category: newPath.root,
                        subcategory: subcategories.first,
                        confidence: 1.0,
                        rationale: "Manually corrected",
                        suggestedPath: nil,
                        tags: result.brainResult.tags,
                        allSubcategories: subcategories
                    )
                    item.result = ProcessingResult(
                        signature: result.signature,
                        brainResult: updatedBrainResult,
                        wasFromMemory: false
                    )
                    
                    // CRITICAL: Also update the feedbackItem so UI reflects the change
                    if var feedbackItem = item.feedbackItem {
                        feedbackItem.categoryPath = newPath
                        feedbackItem.status = .humanCorrected
                        item.feedbackItem = feedbackItem
                        NSLog("✅ [AppState] Updated feedbackItem category to: %@", newPath.description)
                    }
                } else if item.feedbackItem != nil {
                    // Just accept - update status but keep category
                    if var feedbackItem = item.feedbackItem {
                        feedbackItem.status = .humanAccepted
                        item.feedbackItem = feedbackItem
                    }
                }
                
                item.status = .accepted
                try await organizeItem(item)
            } catch {
                item.status = .failed(error.localizedDescription)
            }
        }
    }
    
    /// Organizes the file to its destination
    private func organizeItem(_ item: ProcessingItem) async throws {
        guard let output = outputFolder, let result = item.result else {
            return
        }
        
        item.status = .organizing
        item.progress = 0.9
        
        let organizer = FileOrganizer()
        let summary = try await organizer.organize(
            results: [result],
            to: output,
            mode: organizationMode
        )
        
        if summary.successCount > 0 {
            item.status = .completed
            item.progress = 1.0
            successCount += 1
            totalProcessed += 1
        } else {
            item.status = .failed("Organization failed")
            failureCount += 1
        }
    }
    
    func setOutputFolder(_ url: URL) {
        outputFolder = url
        configManager.update { config in
            config.lastOutputFolder = url.path
        }
        // Also sync to UserDefaults for @AppStorage compatibility
        UserDefaults.standard.set(url.path, forKey: "lastOutputFolder")
    }
    
    // MARK: - Batch Organization
    
    /// Items pending review
    var pendingReviewItems: [ProcessingItem] {
        items.filter { $0.status == .reviewing }
    }
    
    /// Items that are accepted but not yet organized
    var acceptedUnorganizedItems: [ProcessingItem] {
        items.filter { $0.status == .accepted }
    }
    
    /// Count of items accepted but not yet organized
    var acceptedUnorganizedCount: Int {
        acceptedUnorganizedItems.count
    }
    
    /// Whether there are items ready to be organized
    var hasItemsToOrganize: Bool {
        !pendingReviewItems.isEmpty || !acceptedUnorganizedItems.isEmpty
    }
    
    /// Accept and organize all pending review items
    func acceptAllPendingItems() {
        let pending = pendingReviewItems
        NSLog("📋 [AppState] Accepting all %d pending review items", pending.count)
        
        for item in pending {
            confirmItem(item)
        }
    }
    
    /// Organize all accepted items that haven't been organized yet
    func organizeAllAcceptedItems() {
        let accepted = acceptedUnorganizedItems
        NSLog("📋 [AppState] Organizing all %d accepted items", accepted.count)
        
        Task {
            for item in accepted {
                do {
                    try await organizeItem(item)
                } catch {
                    item.status = .failed("Organization failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Accept and organize a specific set of items by their IDs
    func confirmItems(_ itemIds: Set<Int64>) {
        let itemsToConfirm = items.filter { 
            if let feedbackId = $0.feedbackItem?.id {
                return itemIds.contains(feedbackId)
            }
            return false
        }
        
        NSLog("📋 [AppState] Confirming %d items from batch review", itemsToConfirm.count)
        
        for item in itemsToConfirm {
            confirmItem(item)
        }
    }
    
    /// Skip a set of items (mark as skipped without organizing)
    func skipItems(_ itemIds: Set<Int64>) {
        for item in items {
            if let feedbackId = item.feedbackItem?.id, itemIds.contains(feedbackId) {
                item.feedbackItem?.status = .skipped
                item.status = .completed  // Mark as done (skipped)
            }
        }
    }
    
    func reset() {
        items = []
        selectedItemIds = []
        lastSelectedItemId = nil
        isBulkEditMode = false
        successCount = 0
        failureCount = 0
        totalProcessed = 0
    }
    
    // MARK: - Selection Management
    
    /// Items currently selected for bulk operations
    var selectedItems: [ProcessingItem] {
        items.filter { selectedItemIds.contains($0.id) }
    }
    
    /// Number of selected items
    var selectionCount: Int {
        selectedItemIds.count
    }
    
    /// Whether any items are selected
    var hasSelection: Bool {
        !selectedItemIds.isEmpty
    }
    
    /// Unique root categories in the current selection
    var selectedRootCategories: [String: Int] {
        var counts: [String: Int] = [:]
        for item in selectedItems {
            let root = item.fullCategoryPath.root
            if !root.isEmpty {
                counts[root, default: 0] += 1
            }
        }
        return counts
    }
    
    /// Toggle selection for a single item
    func toggleSelection(_ item: ProcessingItem) {
        if selectedItemIds.contains(item.id) {
            selectedItemIds.remove(item.id)
        } else {
            selectedItemIds.insert(item.id)
        }
        lastSelectedItemId = item.id
    }
    
    /// Handle click with modifiers for selection
    /// - Parameters:
    ///   - item: The clicked item
    ///   - shiftHeld: Whether shift key is held (range select)
    ///   - cmdHeld: Whether command key is held (toggle select)
    func handleSelectionClick(_ item: ProcessingItem, shiftHeld: Bool, cmdHeld: Bool) {
        if shiftHeld, let lastId = lastSelectedItemId,
           let lastIndex = items.firstIndex(where: { $0.id == lastId }),
           let currentIndex = items.firstIndex(where: { $0.id == item.id }) {
            // Range selection
            let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
            for i in range {
                selectedItemIds.insert(items[i].id)
            }
        } else if cmdHeld {
            // Toggle single item
            toggleSelection(item)
        } else {
            // Single selection (clear others)
            selectedItemIds = [item.id]
            lastSelectedItemId = item.id
        }
    }
    
    /// Select all items
    func selectAll() {
        selectedItemIds = Set(items.map { $0.id })
    }
    
    /// Clear all selections
    func clearSelection() {
        selectedItemIds = []
        lastSelectedItemId = nil
    }
    
    /// Check if an item is selected
    func isSelected(_ item: ProcessingItem) -> Bool {
        selectedItemIds.contains(item.id)
    }
    
    // MARK: - Bulk Category Operations
    
    /// Re-root selected items to a new top-level category
    /// Preserves subcategories, only changes the root
    func rerootSelectedItems(to newRoot: String) {
        for item in selectedItems {
            let currentPath = item.fullCategoryPath
            
            // Build new path: new root + existing subcategories
            var newComponents = [newRoot]
            if currentPath.components.count > 1 {
                newComponents.append(contentsOf: currentPath.components.dropFirst())
            }
            let newPath = CategoryPath(components: newComponents)
            
            // Update the item's category
            updateItemCategory(item, to: newPath)
        }
        
        NSLog("📁 [AppState] Re-rooted \(selectedItems.count) items to '\(newRoot)'")
    }
    
    /// Update a single item's category path
    private func updateItemCategory(_ item: ProcessingItem, to newPath: CategoryPath) {
        // Update feedbackItem if it exists
        if item.feedbackItem != nil {
            item.feedbackItem?.categoryPath = newPath
        }
        
        // Update the result's brain result if it exists
        if let result = item.result {
            let updatedBrainResult = BrainResult(
                category: newPath.root,
                subcategory: newPath.components.dropFirst().first,
                confidence: result.brainResult.confidence,
                rationale: result.brainResult.rationale,
                tags: result.brainResult.tags
            )
            item.result = ProcessingResult(
                signature: result.signature,
                brainResult: updatedBrainResult,
                wasFromMemory: result.wasFromMemory
            )
        }
        
        // Update quick categorization
        item.quickCategory = newPath.root
        item.quickSubcategory = newPath.components.dropFirst().first
    }
    
    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "mp4", "mov", "avi", "mkv": return "film.fill"
        case "mp3", "m4a", "wav": return "music.note"
        case "jpg", "jpeg", "png", "gif": return "photo.fill"
        case "txt", "md": return "doc.text.fill"
        default: return "doc.fill"
        }
    }
}

