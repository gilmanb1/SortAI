// MARK: - Taxonomy Inference Engine
// Uses LLM to infer category taxonomy from filenames

import Foundation

// MARK: - Taxonomy Inference Engine

/// Engine for inferring taxonomy from filenames using LLM
/// Implements batch processing for efficiency with large file sets
actor TaxonomyInferenceEngine: TaxonomyInferring {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// Batch size for filename processing
        let batchSize: Int
        
        /// Confidence threshold for needing deep analysis
        let deepAnalysisThreshold: Double
        
        /// Maximum taxonomy depth
        let maxDepth: Int
        
        /// Minimum files required to create a category
        let minFilesForCategory: Int
        
        static let `default` = Configuration(
            batchSize: 100,
            deepAnalysisThreshold: 0.75,
            maxDepth: 5,
            minFilesForCategory: 2
        )
    }
    
    // MARK: - Properties
    
    private let provider: any LLMProvider
    private let config: Configuration
    private let decoder = JSONDecoder()
    
    // MARK: - Initialization
    
    init(provider: any LLMProvider, configuration: Configuration = .default) {
        self.provider = provider
        self.config = configuration
    }
    
    // MARK: - TaxonomyInferring Protocol
    
    /// Infer taxonomy from filenames
    func inferTaxonomy(
        from filenames: [String],
        rootName: String?,
        options: LLMOptions
    ) async throws -> TaxonomyTree {
        NSLog("🌳 [TaxonomyEngine] Starting taxonomy inference for \(filenames.count) files")
        NSLog("🌳 [TaxonomyEngine] Root name: \(rootName ?? "Files"), batch size: \(config.batchSize)")
        
        let overallStartTime = Date()
        
        guard !filenames.isEmpty else {
            NSLog("❌ [TaxonomyEngine] No files provided!")
            throw TaxonomyError.noFilesProvided
        }
        
        // Create taxonomy tree with root
        let actualRootName = rootName ?? "Files"
        let tree = TaxonomyTree(rootName: actualRootName, sourceFolderName: rootName)
        
        // For small file sets, process all at once
        if filenames.count <= config.batchSize {
            NSLog("📦 [TaxonomyEngine] Processing \(filenames.count) files in single batch")
            let batchStartTime = Date()
            do {
                let categories = try await inferCategoriesFromBatch(filenames: filenames, options: options)
                let duration = Date().timeIntervalSince(batchStartTime)
                NSLog("✅ [TaxonomyEngine] Single batch completed in %.2fs - \(categories.count) categories found", duration)
                applyCategories(categories, to: tree)
            } catch {
                let duration = Date().timeIntervalSince(batchStartTime)
                NSLog("❌ [TaxonomyEngine] Single batch FAILED after %.2fs: \(error.localizedDescription)", duration)
                throw error
            }
            let totalDuration = Date().timeIntervalSince(overallStartTime)
            NSLog("🏁 [TaxonomyEngine] Total inference time: %.2fs", totalDuration)
            return tree
        }
        
        // For large file sets, process in batches and merge
        var allCategories: [InferredCategory] = []
        
        let batches = filenames.chunked(into: config.batchSize)
        NSLog("📦 [TaxonomyEngine] Processing \(filenames.count) files in \(batches.count) batches")
        
        for (index, batch) in batches.enumerated() {
            NSLog("📦 [TaxonomyEngine] Processing batch \(index + 1)/\(batches.count) with \(batch.count) files")
            let batchStartTime = Date()
            do {
                let batchCategories = try await inferCategoriesFromBatch(filenames: batch, options: options)
                let duration = Date().timeIntervalSince(batchStartTime)
                NSLog("✅ [TaxonomyEngine] Batch \(index + 1) completed in %.2fs - \(batchCategories.count) categories", duration)
                allCategories.append(contentsOf: batchCategories)
            } catch {
                let duration = Date().timeIntervalSince(batchStartTime)
                NSLog("❌ [TaxonomyEngine] Batch \(index + 1) FAILED after %.2fs: \(error.localizedDescription)", duration)
                throw error
            }
        }
        
        // Deduplicate and merge similar categories
        NSLog("🔀 [TaxonomyEngine] Merging \(allCategories.count) categories from all batches")
        let mergedCategories = mergeSimilarCategories(allCategories)
        NSLog("✅ [TaxonomyEngine] Merged down to \(mergedCategories.count) unique categories")
        applyCategories(mergedCategories, to: tree)
        
        let totalDuration = Date().timeIntervalSince(overallStartTime)
        NSLog("🏁 [TaxonomyEngine] Total inference time: %.2fs for \(filenames.count) files", totalDuration)
        
        return tree
    }
    
    /// Categorize a single file within existing taxonomy
    func categorize(
        filename: String,
        within taxonomy: TaxonomyTree,
        options: LLMOptions
    ) async throws -> CategoryAssignment {
        
        let existingCategories = taxonomy.allCategories().map { $0.pathString }
        let prompt = buildCategorizationPrompt(
            filename: filename,
            existingCategories: existingCategories
        )
        
        let response = try await provider.completeJSON(prompt: prompt, options: options)
        return try parseCategorizationResponse(response, filename: filename)
    }
    
    /// Suggest refinements to taxonomy
    func suggestRefinements(
        for taxonomy: TaxonomyTree,
        based filenames: [String],
        options: LLMOptions
    ) async throws -> [TaxonomyRefinement] {
        
        let prompt = buildRefinementPrompt(taxonomy: taxonomy, filenames: filenames)
        let response = try await provider.completeJSON(prompt: prompt, options: options)
        return try parseRefinementResponse(response)
    }
    
    // MARK: - Batch Inference
    
    /// Infer categories from a batch of filenames
    private func inferCategoriesFromBatch(
        filenames: [String],
        options: LLMOptions
    ) async throws -> [InferredCategory] {
        NSLog("🤖 [TaxonomyEngine] Building inference prompt for \(filenames.count) files")
        
        let prompt = buildInferencePrompt(filenames: filenames)
        NSLog("🤖 [TaxonomyEngine] Prompt length: \(prompt.count) characters")
        NSLog("🤖 [TaxonomyEngine] Calling LLM provider (model: \(options.model))...")
        
        let llmStartTime = Date()
        let response: String
        do {
            response = try await provider.completeJSON(prompt: prompt, options: options)
            let llmDuration = Date().timeIntervalSince(llmStartTime)
            NSLog("✅ [TaxonomyEngine] LLM responded in %.2fs - response length: \(response.count) chars", llmDuration)
        } catch {
            let llmDuration = Date().timeIntervalSince(llmStartTime)
            NSLog("❌ [TaxonomyEngine] LLM call FAILED after %.2fs: \(error.localizedDescription)", llmDuration)
            throw error
        }
        
        NSLog("🔍 [TaxonomyEngine] Parsing LLM response...")
        do {
            let categories = try parseInferenceResponse(response)
            NSLog("✅ [TaxonomyEngine] Parsed \(categories.count) categories")
            return categories
        } catch {
            NSLog("❌ [TaxonomyEngine] Failed to parse response: \(error.localizedDescription)")
            NSLog("📄 [TaxonomyEngine] Raw response (first 500 chars): \(String(response.prefix(500)))")
            throw error
        }
    }
    
    // MARK: - Prompt Building
    
    /// Build prompt for taxonomy inference
    private func buildInferencePrompt(filenames: [String]) -> String {
        let fileList = filenames.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        
        return """
        You are a file organization expert. Analyze these filenames and create a hierarchical category taxonomy.

        TASK: Create a logical folder structure to organize these files based on their names.

        RULES:
        1. Create categories that are meaningful and practical
        2. Use "/" to separate hierarchy levels (e.g., "Work / Projects / 2024")
        3. Maximum depth: \(config.maxDepth) levels
        4. Minimum \(config.minFilesForCategory) files per category (group small categories together)
        5. Infer content type from filename patterns, extensions, dates, etc.
        6. Common top-level categories: Documents, Media, Projects, Personal, Work, Archives
        7. Be specific but not overly granular
        8. Consider date patterns (2024, Jan, Q1) for time-based organization

        FILENAMES TO ANALYZE:
        \(fileList)

        Return ONLY valid JSON in this format:
        {
            "categories": [
                {
                    "path": "Category / Subcategory",
                    "description": "Brief description of what goes here",
                    "confidence": 0.85,
                    "files": ["filename1.ext", "filename2.ext"]
                }
            ],
            "uncategorized": ["hard_to_categorize.file"],
            "reasoning": "Brief explanation of the taxonomy structure"
        }
        """
    }
    
    /// Build prompt for categorizing a single file
    private func buildCategorizationPrompt(filename: String, existingCategories: [String]) -> String {
        let categoryList = existingCategories.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        
        return """
        You are a file organization assistant. Categorize this file into the existing taxonomy.

        FILENAME: \(filename)

        EXISTING CATEGORIES:
        \(categoryList)

        RULES:
        1. Prefer existing categories if they fit
        2. You may suggest a new category path if nothing fits well
        3. Provide confidence (0.0-1.0) based on how certain you are
        4. If confidence < 0.75, mark as needing deep analysis

        Return ONLY valid JSON:
        {
            "filename": "\(filename)",
            "categoryPath": ["Top", "Sub1", "Sub2"],
            "confidence": 0.85,
            "alternativePaths": [["Alt1", "Sub"]],
            "rationale": "Why this category fits",
            "needsDeepAnalysis": false
        }
        """
    }
    
    /// Build prompt for taxonomy refinement suggestions
    private func buildRefinementPrompt(taxonomy: TaxonomyTree, filenames: [String]) -> String {
        let categoryList = taxonomy.allCategories()
            .map { "\($0.pathString) (\($0.totalFileCount) files)" }
            .joined(separator: "\n")
        
        let sampleFiles = filenames.prefix(50).joined(separator: "\n")
        
        return """
        You are a file organization expert. Review this taxonomy and suggest improvements.

        CURRENT TAXONOMY:
        \(categoryList)

        SAMPLE FILES:
        \(sampleFiles)

        Suggest refinements like:
        - Merge similar categories
        - Split large categories
        - Rename unclear categories
        - Create missing categories
        - Remove empty categories

        Return ONLY valid JSON:
        {
            "refinements": [
                {
                    "type": "merge|split|rename|move|delete|create",
                    "targetPath": ["Category", "Subcategory"],
                    "suggestedChange": "New name or target path",
                    "reason": "Why this change improves organization",
                    "confidence": 0.8
                }
            ]
        }
        """
    }
    
    // MARK: - Response Parsing
    
    /// Parse taxonomy inference response
    private func parseInferenceResponse(_ response: String) throws -> [InferredCategory] {
        let cleaned = cleanJSON(response)
        
        guard let data = cleaned.data(using: .utf8) else {
            throw TaxonomyError.invalidResponse("Invalid UTF-8")
        }
        
        struct InferenceResponse: Decodable {
            let categories: [CategoryResponse]
            let uncategorized: [String]?
            let reasoning: String?
            
            struct CategoryResponse: Decodable {
                let path: String
                let description: String?
                let confidence: Double?
                let files: [String]
            }
        }
        
        let parsed = try decoder.decode(InferenceResponse.self, from: data)
        
        var categories: [InferredCategory] = parsed.categories.map { cat in
            let pathComponents = cat.path.components(separatedBy: " / ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            
            return InferredCategory(
                path: pathComponents,
                description: cat.description ?? "",
                confidence: cat.confidence ?? 0.8,
                filenames: cat.files
            )
        }
        
        // Add uncategorized as special category
        if let uncategorized = parsed.uncategorized, !uncategorized.isEmpty {
            categories.append(InferredCategory(
                path: ["Uncategorized"],
                description: "Files that need manual review",
                confidence: 0.3,
                filenames: uncategorized
            ))
        }
        
        return categories
    }
    
    /// Parse categorization response
    private func parseCategorizationResponse(_ response: String, filename: String) throws -> CategoryAssignment {
        let cleaned = cleanJSON(response)
        
        guard let data = cleaned.data(using: .utf8) else {
            throw TaxonomyError.invalidResponse("Invalid UTF-8")
        }
        
        struct CategorizationResponse: Decodable {
            let filename: String
            let categoryPath: [String]
            let confidence: Double
            let alternativePaths: [[String]]?
            let rationale: String?
            let needsDeepAnalysis: Bool?
        }
        
        let parsed = try decoder.decode(CategorizationResponse.self, from: data)
        
        return CategoryAssignment(
            filename: parsed.filename,
            categoryPath: parsed.categoryPath,
            confidence: parsed.confidence,
            alternativePaths: parsed.alternativePaths ?? [],
            rationale: parsed.rationale ?? "",
            needsDeepAnalysis: parsed.needsDeepAnalysis ?? (parsed.confidence < config.deepAnalysisThreshold)
        )
    }
    
    /// Parse refinement response
    private func parseRefinementResponse(_ response: String) throws -> [TaxonomyRefinement] {
        let cleaned = cleanJSON(response)
        
        guard let data = cleaned.data(using: .utf8) else {
            throw TaxonomyError.invalidResponse("Invalid UTF-8")
        }
        
        struct RefinementResponse: Decodable {
            let refinements: [RefinementItem]
            
            struct RefinementItem: Decodable {
                let type: String
                let targetPath: [String]
                let suggestedChange: String
                let reason: String
                let confidence: Double?
            }
        }
        
        let parsed = try decoder.decode(RefinementResponse.self, from: data)
        
        return parsed.refinements.compactMap { item in
            guard let type = TaxonomyRefinement.RefinementType(rawValue: item.type) else {
                return nil
            }
            
            return TaxonomyRefinement(
                type: type,
                targetPath: item.targetPath,
                suggestedChange: item.suggestedChange,
                reason: item.reason,
                confidence: item.confidence ?? 0.7
            )
        }
    }
    
    /// Clean JSON response (remove markdown, etc.)
    private func cleanJSON(_ response: String) -> String {
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
    
    // MARK: - Category Management
    
    /// Apply inferred categories to taxonomy tree
    private func applyCategories(_ categories: [InferredCategory], to tree: TaxonomyTree) {
        for category in categories {
            let node = tree.findOrCreate(path: category.path)
            node.confidence = category.confidence
            
            // Assign files to the category
            for filename in category.filenames {
                let assignment = FileAssignment(
                    url: URL(fileURLWithPath: filename),  // Placeholder URL
                    filename: filename,
                    confidence: category.confidence,
                    needsDeepAnalysis: category.confidence < config.deepAnalysisThreshold,
                    source: .filename
                )
                node.assign(file: assignment)
            }
        }
    }
    
    /// Merge similar categories
    private func mergeSimilarCategories(_ categories: [InferredCategory]) -> [InferredCategory] {
        var merged: [String: InferredCategory] = [:]
        
        for category in categories {
            let key = category.path.joined(separator: "/").lowercased()
            
            if var existing = merged[key] {
                // Merge files and average confidence
                existing.filenames.append(contentsOf: category.filenames)
                existing.confidence = (existing.confidence + category.confidence) / 2
                merged[key] = existing
            } else {
                merged[key] = category
            }
        }
        
        return Array(merged.values)
    }
}

// MARK: - Supporting Types

/// Category inferred from filenames
struct InferredCategory: Sendable {
    let path: [String]
    let description: String
    var confidence: Double
    var filenames: [String]
    
    var pathString: String {
        path.joined(separator: " / ")
    }
}

/// Taxonomy inference errors
enum TaxonomyError: LocalizedError {
    case noFilesProvided
    case invalidResponse(String)
    case llmUnavailable
    case parsingFailed(String)
    case maxDepthExceeded
    
    var errorDescription: String? {
        switch self {
        case .noFilesProvided:
            return "No files provided for taxonomy inference"
        case .invalidResponse(let reason):
            return "Invalid LLM response: \(reason)"
        case .llmUnavailable:
            return "LLM provider is not available"
        case .parsingFailed(let reason):
            return "Failed to parse response: \(reason)"
        case .maxDepthExceeded:
            return "Maximum taxonomy depth exceeded"
        }
    }
}

// MARK: - Array Extension

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

