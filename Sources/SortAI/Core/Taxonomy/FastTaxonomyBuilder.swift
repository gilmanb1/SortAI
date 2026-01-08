// MARK: - Fast Taxonomy Builder
// Two-phase taxonomy building: instant rule-based + async LLM refinement

import Foundation

// MARK: - Fast Taxonomy Builder

/// Builds taxonomy in two phases:
/// Phase 1: Instant rule-based clustering (<1 second)
/// Phase 2: Async LLM refinement (background)
actor FastTaxonomyBuilder {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// Target number of categories for Phase 1
        let targetCategoryCount: Int
        
        /// Whether to separate file types within themes (Videos, PDFs, etc.)
        let separateFileTypes: Bool
        
        /// Whether to run Phase 2 automatically
        let autoRefine: Bool
        
        /// Model to use for refinement
        let refinementModel: String
        
        /// Maximum files to send to LLM per refinement batch
        let refinementBatchSize: Int
        
        static let `default` = Configuration(
            targetCategoryCount: 7,
            separateFileTypes: true,
            autoRefine: true,
            refinementModel: "llama3.2",
            refinementBatchSize: 50
        )
    }
    
    // MARK: - Callbacks
    
    /// Callback for taxonomy updates during refinement
    typealias TaxonomyUpdateCallback = @Sendable (TaxonomyTree, RefinementProgress) -> Void
    
    // MARK: - Properties
    
    private let config: Configuration
    private let extractor: KeywordExtractor
    private let semanticClusterer: SemanticThemeClusterer
    private var llmProvider: (any LLMProvider)?
    
    private var refinementTask: Task<Void, Never>?
    private var isRefining: Bool = false
    
    // MARK: - Initialization
    
    init(
        configuration: Configuration = .default,
        llmProvider: (any LLMProvider)? = nil
    ) {
        self.config = configuration
        self.extractor = KeywordExtractor(configuration: .fast)
        self.semanticClusterer = SemanticThemeClusterer(
            configuration: .withTargetCount(
                configuration.targetCategoryCount,
                separateTypes: configuration.separateFileTypes
            )
        )
        self.llmProvider = llmProvider
    }
    
    /// Set or update the LLM provider
    func setLLMProvider(_ provider: any LLMProvider) {
        self.llmProvider = provider
    }
    
    // MARK: - Phase 1: Instant Semantic Clustering
    
    /// Build initial taxonomy instantly using semantic theme clustering
    /// This completes in <1 second for 1000s of files
    func buildInstant(
        from filenames: [String],
        rootName: String?
    ) async -> TaxonomyTree {
        NSLog("⚡️ [FastTaxonomy] Phase 1: Starting semantic clustering for \(filenames.count) files")
        NSLog("⚡️ [FastTaxonomy] Configuration: targetCategoryCount=\(config.targetCategoryCount), separateFileTypes=\(config.separateFileTypes)")
        let startTime = Date()
        
        // Extract keywords from all filenames
        let keywords = extractor.extractBatch(from: filenames)
        let extractTime = Date().timeIntervalSince(startTime)
        NSLog("⚡️ [FastTaxonomy] Keyword extraction: %.3fs", extractTime)
        
        // Cluster by semantic themes (not file type)
        let clusterStartTime = Date()
        let themesClusters = await semanticClusterer.cluster(keywords: keywords)
        let clusterTime = Date().timeIntervalSince(clusterStartTime)
        NSLog("⚡️ [FastTaxonomy] Semantic clustering: %.3fs - created \(themesClusters.count) themes", clusterTime)
        
        // Build taxonomy tree from theme clusters
        let tree = buildTreeFromThemes(themesClusters, rootName: rootName)
        
        let totalTime = Date().timeIntervalSince(startTime)
        NSLog("✅ [FastTaxonomy] Phase 1 complete in %.3fs - \(tree.categoryCount) categories, \(tree.totalFileCount) files", totalTime)
        
        return tree
    }
    
    /// Build initial taxonomy from TaxonomyScannedFile objects (preserves file references for organization)
    func buildInstant(
        from files: [TaxonomyScannedFile],
        rootName: String?
    ) async -> TaxonomyTree {
        NSLog("⚡️ [FastTaxonomy] Phase 1: Starting semantic clustering for \(files.count) files (with URLs)")
        NSLog("⚡️ [FastTaxonomy] Configuration: targetCategoryCount=\(config.targetCategoryCount), separateFileTypes=\(config.separateFileTypes)")
        let startTime = Date()
        
        // Extract keywords from all files (preserving file references)
        let keywords = extractor.extractBatch(from: files)
        let extractTime = Date().timeIntervalSince(startTime)
        NSLog("⚡️ [FastTaxonomy] Keyword extraction: %.3fs", extractTime)
        
        // Cluster by semantic themes (not file type)
        let clusterStartTime = Date()
        let themesClusters = await semanticClusterer.cluster(keywords: keywords)
        let clusterTime = Date().timeIntervalSince(clusterStartTime)
        NSLog("⚡️ [FastTaxonomy] Semantic clustering: %.3fs - created \(themesClusters.count) themes", clusterTime)
        
        // Build taxonomy tree from theme clusters (preserving file refs)
        let tree = buildTreeFromThemes(themesClusters, rootName: rootName)
        
        let totalTime = Date().timeIntervalSince(startTime)
        NSLog("✅ [FastTaxonomy] Phase 1 complete in %.3fs - \(tree.categoryCount) categories, \(tree.totalFileCount) files", totalTime)
        
        return tree
    }
    
    // MARK: - Phase 2: Async LLM Refinement
    
    /// Start background refinement of taxonomy using LLM
    func startRefinement(
        taxonomy: TaxonomyTree,
        onUpdate: @escaping TaxonomyUpdateCallback
    ) {
        // Try to get provider from registry if not injected
        Task {
            if llmProvider == nil {
                // Try ollama first, then default
                if let ollamaProvider = await LLMProviderRegistry.shared.provider(id: "ollama") {
                    llmProvider = ollamaProvider
                    NSLog("✅ [FastTaxonomy] Got OllamaProvider from registry")
                } else if let defaultProv = await LLMProviderRegistry.shared.defaultProvider() {
                    llmProvider = defaultProv
                    NSLog("✅ [FastTaxonomy] Got default provider from registry")
                }
            }
            
            guard let provider = llmProvider else {
                NSLog("⚠️ [FastTaxonomy] No LLM provider available for refinement (not in registry)")
                return
            }
            
            await startRefinementInternal(taxonomy: taxonomy, provider: provider, onUpdate: onUpdate)
        }
    }
    
    private func startRefinementInternal(
        taxonomy: TaxonomyTree,
        provider: any LLMProvider,
        onUpdate: @escaping TaxonomyUpdateCallback
    ) async {
        guard !isRefining else {
            NSLog("⚠️ [FastTaxonomy] Refinement already in progress")
            return
        }
        
        NSLog("✅ [FastTaxonomy] LLM provider available: \(provider.identifier)")
        isRefining = true
        
        refinementTask = Task {
            await performRefinement(taxonomy: taxonomy, provider: provider, onUpdate: onUpdate)
            isRefining = false
        }
    }
    
    /// Cancel ongoing refinement
    func cancelRefinement() {
        refinementTask?.cancel()
        refinementTask = nil
        isRefining = false
    }
    
    // MARK: - Refinement Implementation
    
    private func performRefinement(
        taxonomy: TaxonomyTree,
        provider: any LLMProvider,
        onUpdate: @escaping TaxonomyUpdateCallback
    ) async {
        NSLog("🔄 [FastTaxonomy] Phase 2: Starting LLM refinement")
        let startTime = Date()
        
        // Get all categories that need refinement (not user-edited)
        let categories = taxonomy.allCategories().filter { !$0.isUserEdited }
        let totalCategories = categories.count
        var refinedCount = 0
        
        // Process in batches to avoid overwhelming the LLM
        for category in categories {
            guard !Task.isCancelled else {
                NSLog("🛑 [FastTaxonomy] Refinement cancelled")
                return
            }
            
            // Skip if user has edited this category
            guard !category.isUserEdited else { continue }
            
            // Mark as refining
            await MainActor.run {
                category.refinementState = .refining
            }
            
            // Refine this category
            do {
                let refinedName = try await refineCategory(category, provider: provider)
                
                await MainActor.run {
                    if !category.isUserEdited {
                        category.suggestedName = refinedName
                        category.refinementState = .refined
                    }
                }
                
                refinedCount += 1
                
                // Report progress
                let progress = RefinementProgress(
                    totalCategories: totalCategories,
                    refinedCategories: refinedCount,
                    currentCategory: category.name,
                    phase: .refiningNames
                )
                onUpdate(taxonomy, progress)
                
            } catch {
                NSLog("⚠️ [FastTaxonomy] Failed to refine category '\(category.name)': \(error.localizedDescription)")
                await MainActor.run {
                    category.refinementState = .initial
                }
            }
            
            // Small delay to avoid rate limiting
            try? await Task.sleep(for: .milliseconds(100))
        }
        
        // Final pass: suggest merges
        if !Task.isCancelled {
            await suggestMerges(taxonomy: taxonomy, provider: provider, onUpdate: onUpdate)
        }
        
        let totalTime = Date().timeIntervalSince(startTime)
        NSLog("✅ [FastTaxonomy] Phase 2 complete in %.2fs - refined \(refinedCount) categories", totalTime)
        
        // Final update
        let finalProgress = RefinementProgress(
            totalCategories: totalCategories,
            refinedCategories: refinedCount,
            currentCategory: nil,
            phase: .complete
        )
        onUpdate(taxonomy, finalProgress)
    }
    
    /// Refine a single category name using LLM
    private func refineCategory(
        _ category: TaxonomyNode,
        provider: any LLMProvider
    ) async throws -> String {
        let filenames = category.assignedFiles.prefix(20).map { $0.filename }
        
        let prompt = """
        Suggest a SHORT, descriptive folder name (2-4 words max) for files like these:
        \(filenames.joined(separator: "\n"))
        
        Current name: \(category.name)
        
        Return ONLY the suggested name, nothing else. Be concise.
        """
        
        let options = LLMOptions(
            model: config.refinementModel,
            temperature: 0.3,
            maxTokens: 50,
            topP: nil,
            stopSequences: nil
        )
        
        let response = try await provider.complete(prompt: prompt, options: options)
        
        // Clean up response
        return response
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .components(separatedBy: "\n").first ?? category.name
    }
    
    /// Suggest and apply category merges
    private func suggestMerges(
        taxonomy: TaxonomyTree,
        provider: any LLMProvider,
        onUpdate: @escaping TaxonomyUpdateCallback
    ) async {
        // Find categories that are candidates for merging (small, non-user-edited)
        let allCategories = taxonomy.allCategories()
        let mergeCandidates = allCategories.filter { $0.totalFileCount < 5 && !$0.isUserEdited && !$0.isRoot }
        
        guard mergeCandidates.count > 1 else {
            NSLog("🔀 [FastTaxonomy] Not enough merge candidates (found \(mergeCandidates.count))")
            return
        }
        
        NSLog("🔀 [FastTaxonomy] Finding merge suggestions for \(mergeCandidates.count) small categories")
        
        // Build category list with context
        let categoryList = mergeCandidates.map { cat -> String in
            let files = cat.assignedFiles.prefix(5).map { $0.filename }.joined(separator: ", ")
            return "- \(cat.name) (\(cat.totalFileCount) files): \(files)"
        }.joined(separator: "\n")
        
        let prompt = """
        Analyze these small categories and suggest which should be merged together.
        Categories:
        \(categoryList)
        
        Rules:
        1. Only merge categories that are semantically related
        2. Suggest a good name for the merged category
        3. Return ONLY in this exact format, one per line:
           SOURCE1 + SOURCE2 -> MERGED_NAME
        4. Maximum 5 suggestions
        5. If categories shouldn't be merged, return "NO_MERGES"
        
        Examples:
        Card Tricks + Card Magic -> Card Magic
        Cooking + Recipes -> Cooking & Recipes
        """
        
        let options = LLMOptions(
            model: config.refinementModel,
            temperature: 0.3,
            maxTokens: 300,
            topP: nil,
            stopSequences: nil
        )
        
        do {
            let response = try await provider.complete(prompt: prompt, options: options)
            NSLog("🔀 [FastTaxonomy] LLM merge response: \(response)")
            
            // Parse and apply merge suggestions
            let suggestions = parseMergeSuggestions(response)
            
            for suggestion in suggestions {
                guard !Task.isCancelled else { return }
                
                await applyMerge(
                    suggestion: suggestion,
                    taxonomy: taxonomy,
                    provider: provider,
                    onUpdate: onUpdate
                )
            }
            
        } catch {
            NSLog("⚠️ [FastTaxonomy] Failed to get merge suggestions: \(error.localizedDescription)")
        }
    }
    
    /// Parse merge suggestions from LLM response
    private func parseMergeSuggestions(_ response: String) -> [MergeSuggestion] {
        var suggestions: [MergeSuggestion] = []
        
        let lines = response.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "NO_MERGES" }
        
        for line in lines {
            // Parse format: "SOURCE1 + SOURCE2 -> MERGED_NAME"
            if let arrowRange = line.range(of: "->") ?? line.range(of: "→") {
                let leftPart = String(line[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let mergedName = String(line[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                
                // Split sources by "+"
                let sources = leftPart.components(separatedBy: "+")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                
                if sources.count >= 2 && !mergedName.isEmpty {
                    suggestions.append(MergeSuggestion(
                        sourceCategories: sources,
                        mergedName: mergedName
                    ))
                    NSLog("🔀 [FastTaxonomy] Parsed merge: \(sources) -> \(mergedName)")
                }
            }
        }
        
        return suggestions
    }
    
    /// Apply a single merge suggestion
    private func applyMerge(
        suggestion: MergeSuggestion,
        taxonomy: TaxonomyTree,
        provider: any LLMProvider,
        onUpdate: @escaping TaxonomyUpdateCallback
    ) async {
        NSLog("🔀 [FastTaxonomy] Applying merge: \(suggestion.sourceCategories) -> \(suggestion.mergedName)")
        
        // Find source nodes (case-insensitive match)
        let sourceNodes = suggestion.sourceCategories.compactMap { sourceName -> TaxonomyNode? in
            taxonomy.allCategories().first { 
                $0.name.lowercased() == sourceName.lowercased() && !$0.isUserEdited 
            }
        }
        
        guard sourceNodes.count >= 2 else {
            NSLog("⚠️ [FastTaxonomy] Could not find enough source nodes for merge")
            return
        }
        
        // Collect all files from source categories
        var allFiles: [FileAssignment] = []
        for node in sourceNodes {
            allFiles.append(contentsOf: node.allFilesRecursive())
        }
        
        guard !allFiles.isEmpty else {
            NSLog("⚠️ [FastTaxonomy] No files to merge")
            return
        }
        
        NSLog("🔀 [FastTaxonomy] Merging \(allFiles.count) files into '\(suggestion.mergedName)'")
        
        // Create or find the merged category at the same level as the first source
        let parentNode = sourceNodes.first?.parent ?? taxonomy.root
        
        await MainActor.run {
            // Create new merged node
            let mergedNode = TaxonomyNode(
                name: suggestion.mergedName,
                parent: parentNode,
                isUserCreated: false
            )
            mergedNode.refinementState = .refining
            parentNode.addChild(mergedNode)
            
            // Remove source nodes (but keep their files for reassignment)
            for sourceNode in sourceNodes {
                sourceNode.parent?.removeChild(sourceNode)
            }
        }
        
        // Find the newly created merged node
        guard let mergedNode = taxonomy.allCategories().first(where: { $0.name == suggestion.mergedName }) else {
            NSLog("⚠️ [FastTaxonomy] Could not find merged node")
            return
        }
        
        // Infer sub-structure for the merged category
        await inferSubStructure(
            for: mergedNode,
            files: allFiles,
            provider: provider
        )
        
        await MainActor.run {
            mergedNode.refinementState = .refined
        }
        
        // Notify UI of update
        let progress = RefinementProgress(
            totalCategories: taxonomy.categoryCount,
            refinedCategories: taxonomy.allCategories().filter { $0.refinementState == .refined }.count,
            currentCategory: suggestion.mergedName,
            phase: .merging
        )
        onUpdate(taxonomy, progress)
        
        NSLog("✅ [FastTaxonomy] Merge complete: '\(suggestion.mergedName)' with \(mergedNode.totalFileCount) files")
    }
    
    /// Infer sub-structure for a category using LLM
    private func inferSubStructure(
        for node: TaxonomyNode,
        files: [FileAssignment],
        provider: any LLMProvider
    ) async {
        guard files.count > 3 else {
            // Too few files, just assign directly
            await MainActor.run {
                for file in files {
                    node.assignFile(file)
                }
            }
            return
        }
        
        NSLog("🏗️ [FastTaxonomy] Inferring sub-structure for '\(node.name)' with \(files.count) files")
        
        let fileList = files.prefix(30).map { $0.filename }.joined(separator: "\n")
        
        let prompt = """
        Group these files into 2-4 logical subcategories:
        \(fileList)
        
        Return ONLY in this JSON format:
        {
          "subcategories": [
            {"name": "SubcategoryName", "files": ["file1.pdf", "file2.mp4"]}
          ]
        }
        """
        
        let options = LLMOptions(
            model: config.refinementModel,
            temperature: 0.3,
            maxTokens: 500,
            topP: nil,
            stopSequences: nil
        )
        
        do {
            let response = try await provider.complete(prompt: prompt, options: options)
            
            // Parse JSON response
            if let jsonData = response.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let subcategoriesRaw = json["subcategories"] as? [[String: Any]] {
                
                // Extract data into Sendable structures before MainActor
                struct SubcategoryData: Sendable {
                    let name: String
                    let fileNames: [String]
                }
                
                let subcategories: [SubcategoryData] = subcategoriesRaw.compactMap { subcat in
                    guard let name = subcat["name"] as? String,
                          let fileNames = subcat["files"] as? [String] else { return nil }
                    return SubcategoryData(name: name, fileNames: fileNames)
                }
                
                let subcatCount = subcategories.count
                
                await MainActor.run {
                    var assignedFiles = Set<String>()
                    
                    for subcat in subcategories {
                        // Create subcategory node
                        let subNode = TaxonomyNode(name: subcat.name, parent: node, isUserCreated: false)
                        subNode.refinementState = .refined
                        node.addChild(subNode)
                        
                        // Assign files to subcategory
                        for fileName in subcat.fileNames {
                            if let file = files.first(where: { $0.filename.lowercased() == fileName.lowercased() }) {
                                subNode.assignFile(file)
                                assignedFiles.insert(fileName.lowercased())
                            }
                        }
                    }
                    
                    // Assign any remaining files directly to parent
                    for file in files {
                        if !assignedFiles.contains(file.filename.lowercased()) {
                            node.assignFile(file)
                        }
                    }
                }
                
                NSLog("✅ [FastTaxonomy] Created \(subcatCount) subcategories for '\(node.name)'")
                
            } else {
                // Fallback: assign all files directly
                NSLog("⚠️ [FastTaxonomy] Could not parse sub-structure response, assigning files directly")
                await MainActor.run {
                    for file in files {
                        node.assignFile(file)
                    }
                }
            }
            
        } catch {
            NSLog("⚠️ [FastTaxonomy] Failed to infer sub-structure: \(error.localizedDescription)")
            await MainActor.run {
                for file in files {
                    node.assignFile(file)
                }
            }
        }
    }
    
    // MARK: - Merge Suggestion Model
    
    private struct MergeSuggestion {
        let sourceCategories: [String]
        let mergedName: String
    }
    
    // MARK: - Tree Building
    
    /// Convert theme clusters to taxonomy tree with hierarchy:
    /// Theme → SubTheme → [FileType] (if separateFileTypes is true)
    private func buildTreeFromThemes(
        _ themes: [ThemeCluster],
        rootName: String?
    ) -> TaxonomyTree {
        let tree = TaxonomyTree(
            rootName: rootName ?? "Files",
            sourceFolderName: rootName
        )
        
        for theme in themes {
            // Create top-level theme node
            let themeNode = tree.findOrCreate(path: [theme.name])
            themeNode.confidence = 0.7
            themeNode.refinementState = .initial
            
            if theme.hasSubThemes {
                // Build sub-theme hierarchy
                for subTheme in theme.subThemes {
                    if config.separateFileTypes && !subTheme.fileTypeGroups.isEmpty {
                        // SubTheme → FileType hierarchy
                        for (fileType, files) in subTheme.fileTypeGroups {
                            let path = [theme.name, subTheme.name, fileType.displayName]
                            let node = tree.findOrCreate(path: path)
                            node.confidence = 0.7
                            node.refinementState = .initial
                            
                            assignFilesToNode(files, node: node)
                        }
                    } else {
                        // Just SubTheme, no file type separation
                        let path = [theme.name, subTheme.name]
                        let node = tree.findOrCreate(path: path)
                        node.confidence = 0.7
                        node.refinementState = .initial
                        
                        assignFilesToNode(subTheme.files, node: node)
                    }
                }
            } else if config.separateFileTypes && !theme.fileTypeGroups.isEmpty {
                // Theme → FileType hierarchy (no sub-themes)
                for (fileType, files) in theme.fileTypeGroups {
                    let path = [theme.name, fileType.displayName]
                    let node = tree.findOrCreate(path: path)
                    node.confidence = 0.7
                    node.refinementState = .initial
                    
                    assignFilesToNode(files, node: node)
                }
            } else {
                // Flat: just assign files directly to theme
                assignFilesToNode(theme.files, node: themeNode)
            }
        }
        
        return tree
    }
    
    /// Helper to assign files to a node
    private func assignFilesToNode(_ files: [ExtractedKeywords], node: TaxonomyNode) {
        for file in files {
            // Use proper file URL if available, otherwise create from filename
            let fileURL = file.sourceURL ?? URL(fileURLWithPath: file.original)
            let fileId = file.sourceFileId ?? file.id
            
            let assignment = FileAssignment(
                id: UUID(),
                fileId: fileId,  // Original file's ID for lookup during organization!
                categoryId: node.id,
                url: fileURL,
                filename: file.original,
                confidence: 0.7,
                needsDeepAnalysis: false,
                source: .filename
            )
            node.assign(file: assignment)
        }
    }
    
    /// Legacy method for backwards compatibility
    private func buildTreeFromClusters(
        _ clusters: [FileCluster],
        rootName: String?
    ) -> TaxonomyTree {
        let tree = TaxonomyTree(
            rootName: rootName ?? "Files",
            sourceFolderName: rootName
        )
        
        for cluster in clusters {
            let categoryName = cluster.suggestedName ?? cluster.name
            let node = tree.findOrCreate(path: [categoryName])
            
            node.confidence = 0.7
            node.refinementState = .initial
            
            for file in cluster.files {
                let assignment = FileAssignment(
                    url: URL(fileURLWithPath: file.original),
                    filename: file.original,
                    confidence: 0.7,
                    needsDeepAnalysis: false,
                    source: .filename
                )
                node.assign(file: assignment)
            }
        }
        
        return tree
    }
}

// MARK: - Refinement Progress

/// Progress information for refinement updates
struct RefinementProgress: Sendable {
    let totalCategories: Int
    let refinedCategories: Int
    let currentCategory: String?
    let phase: Phase
    
    enum Phase: String, Sendable {
        case refiningNames = "Refining category names..."
        case suggestingMerges = "Analyzing merge candidates..."
        case merging = "Merging categories..."
        case inferringStructure = "Organizing files..."
        case complete = "Refinement complete"
    }
    
    var percentage: Double {
        guard totalCategories > 0 else { return 0 }
        return Double(refinedCategories) / Double(totalCategories)
    }
    
    var isComplete: Bool {
        phase == .complete
    }
}


