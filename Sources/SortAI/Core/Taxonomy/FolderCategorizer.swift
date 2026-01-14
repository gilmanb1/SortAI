// MARK: - Folder Categorizer
// Categorizes folders as units by analyzing their contents

import Foundation

// MARK: - Folder Category Assignment

/// Result of categorizing a folder unit
struct FolderCategoryAssignment: Identifiable, Sendable {
    let id: UUID
    let folderId: UUID                // ScannedFolder.id
    let folderName: String
    let categoryPath: [String]        // e.g., ["Work", "Job Search", "Application Materials"]
    let confidence: Double
    let rationale: String
    let alternativePaths: [[String]]  // Other possible categories
    
    /// Path as display string
    var pathString: String {
        categoryPath.joined(separator: " / ")
    }
    
    init(
        id: UUID = UUID(),
        folderId: UUID,
        folderName: String,
        categoryPath: [String],
        confidence: Double,
        rationale: String,
        alternativePaths: [[String]] = []
    ) {
        self.id = id
        self.folderId = folderId
        self.folderName = folderName
        self.categoryPath = categoryPath
        self.confidence = confidence
        self.rationale = rationale
        self.alternativePaths = alternativePaths
    }
}

// MARK: - Folder Categorizer Actor

/// Categorizes folder units by analyzing their contents
/// Uses LLM to determine the best category for moving the folder as a unit
actor FolderCategorizer {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// Confidence threshold below which we flag for review
        let reviewThreshold: Double
        
        /// Maximum files to include in context (for large folders)
        let maxFilesInContext: Int
        
        /// Include file type summary in prompt
        let includeFileTypeSummary: Bool
        
        /// Include folder name analysis
        let analyzeFolderName: Bool
        
        static let `default` = Configuration(
            reviewThreshold: 0.75,
            maxFilesInContext: 50,
            includeFileTypeSummary: true,
            analyzeFolderName: true
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
    
    // MARK: - Categorization
    
    /// Categorize a single folder within an existing taxonomy
    func categorize(
        folder: ScannedFolder,
        within taxonomy: TaxonomyTree,
        options: LLMOptions
    ) async throws -> FolderCategoryAssignment {
        NSLog("📁 [FolderCategorizer] Categorizing folder: \(folder.folderName) (\(folder.fileCount) files)")
        
        let existingCategories = taxonomy.allCategories().map { $0.pathString }
        let prompt = buildCategorizationPrompt(folder: folder, existingCategories: existingCategories)
        
        let response = try await provider.completeJSON(prompt: prompt, options: options)
        let assignment = try parseCategorizationResponse(response, folder: folder)
        
        NSLog("📁 [FolderCategorizer] Result: \(assignment.pathString) (confidence: \(Int(assignment.confidence * 100))%)")
        
        return assignment
    }
    
    /// Categorize multiple folders in batch
    func categorizeBatch(
        folders: [ScannedFolder],
        within taxonomy: TaxonomyTree,
        options: LLMOptions,
        progressCallback: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [FolderCategoryAssignment] {
        NSLog("📁 [FolderCategorizer] Starting batch categorization of \(folders.count) folders")
        
        var assignments: [FolderCategoryAssignment] = []
        
        for (index, folder) in folders.enumerated() {
            do {
                let assignment = try await categorize(folder: folder, within: taxonomy, options: options)
                assignments.append(assignment)
            } catch {
                NSLog("❌ [FolderCategorizer] Failed to categorize '\(folder.folderName)': \(error.localizedDescription)")
                // Create a low-confidence fallback assignment
                let fallback = FolderCategoryAssignment(
                    folderId: folder.id,
                    folderName: folder.folderName,
                    categoryPath: ["Uncategorized"],
                    confidence: 0.3,
                    rationale: "Categorization failed: \(error.localizedDescription)"
                )
                assignments.append(fallback)
            }
            
            progressCallback?(index + 1, folders.count)
        }
        
        NSLog("📁 [FolderCategorizer] Batch complete: \(assignments.count) folders categorized")
        return assignments
    }
    
    // MARK: - Prompt Building
    
    /// Build LLM prompt for folder categorization
    private func buildCategorizationPrompt(folder: ScannedFolder, existingCategories: [String]) -> String {
        // Get file list (limited for large folders)
        let fileList = folder.containedFiles
            .prefix(config.maxFilesInContext)
            .enumerated()
            .map { "\($0.offset + 1). \($0.element.filename)" }
            .joined(separator: "\n")
        
        // Build file type summary if enabled
        var fileTypeSummary = ""
        if config.includeFileTypeSummary {
            let typeGroups = Dictionary(grouping: folder.containedFiles) { file -> String in
                if file.isImage { return "image" }
                if file.isVideo { return "video" }
                if file.isAudio { return "audio" }
                if file.isDocument { return "document" }
                return "other"
            }
            
            fileTypeSummary = typeGroups
                .map { "\($0.value.count) \($0.key)(s)" }
                .joined(separator: ", ")
        }
        
        // Build category list
        let categoryList = existingCategories.isEmpty
            ? "No existing categories - suggest new ones"
            : existingCategories.prefix(30).joined(separator: "\n")
        
        return """
        You are a file organization expert. Analyze this FOLDER and determine what category it belongs to.
        
        The folder will be MOVED AS A UNIT - all files inside will stay together in their current structure.
        
        FOLDER NAME: \(folder.folderName)
        
        FILE COUNT: \(folder.fileCount) files
        \(fileTypeSummary.isEmpty ? "" : "FILE TYPES: \(fileTypeSummary)")
        
        CONTAINED FILES:
        \(fileList)
        \(folder.fileCount > config.maxFilesInContext ? "... and \(folder.fileCount - config.maxFilesInContext) more files" : "")
        
        EXISTING CATEGORIES (prefer these if they fit):
        \(categoryList)
        
        RULES:
        1. Analyze the folder NAME and its CONTENTS together
        2. Choose the most appropriate category based on the dominant theme
        3. Use "/" to separate hierarchy levels (e.g., "Work / Projects / 2024")
        4. Confidence should reflect how well the folder fits the category
        5. Provide alternatives if the primary choice isn't clear-cut
        
        Return ONLY valid JSON:
        {
            "categoryPath": ["Top Level", "Sub Category", "Specific"],
            "confidence": 0.85,
            "rationale": "Brief explanation of why this category fits",
            "alternatives": [
                ["Alternative", "Path", "One"],
                ["Alternative", "Path", "Two"]
            ]
        }
        """
    }
    
    // MARK: - Response Parsing
    
    /// Parse LLM categorization response
    private func parseCategorizationResponse(_ response: String, folder: ScannedFolder) throws -> FolderCategoryAssignment {
        let cleaned = cleanJSON(response)
        
        guard let data = cleaned.data(using: .utf8) else {
            throw FolderCategorizationError.invalidResponse("Invalid UTF-8")
        }
        
        struct Response: Decodable {
            let categoryPath: [String]
            let confidence: Double
            let rationale: String?
            let alternatives: [[String]]?
        }
        
        let parsed = try decoder.decode(Response.self, from: data)
        
        return FolderCategoryAssignment(
            folderId: folder.id,
            folderName: folder.folderName,
            categoryPath: parsed.categoryPath,
            confidence: parsed.confidence,
            rationale: parsed.rationale ?? "",
            alternativePaths: parsed.alternatives ?? []
        )
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
}

// MARK: - Quick Folder Categorization (Non-LLM)

extension FolderCategorizer {
    
    /// Quickly categorize a folder using rules (no LLM call)
    /// Useful for initial sorting or when LLM is unavailable
    static func quickCategorize(folder: ScannedFolder) -> FolderCategoryAssignment {
        let folderName = folder.folderName.lowercased()
        var categoryPath: [String] = []
        var confidence: Double = 0.6
        var rationale = ""
        
        // Analyze folder name for common patterns
        if folderName.contains("resume") || folderName.contains("cv") {
            categoryPath = ["Work", "Job Search", "Application Materials"]
            rationale = "Folder name suggests job application materials"
            confidence = 0.85
        } else if folderName.contains("photo") || folderName.contains("picture") || folderName.contains("image") {
            categoryPath = ["Media", "Photos"]
            rationale = "Folder name suggests photo collection"
            confidence = 0.8
        } else if folderName.contains("video") || folderName.contains("movie") || folderName.contains("film") {
            categoryPath = ["Media", "Videos"]
            rationale = "Folder name suggests video collection"
            confidence = 0.8
        } else if folderName.contains("music") || folderName.contains("song") || folderName.contains("audio") {
            categoryPath = ["Media", "Music"]
            rationale = "Folder name suggests music collection"
            confidence = 0.8
        } else if folderName.contains("project") || folderName.contains("work") {
            categoryPath = ["Work", "Projects"]
            rationale = "Folder name suggests work project"
            confidence = 0.7
        } else if folderName.contains("document") || folderName.contains("doc") {
            categoryPath = ["Documents"]
            rationale = "Folder name suggests documents"
            confidence = 0.7
        } else if folderName.contains("backup") || folderName.contains("archive") {
            categoryPath = ["Archives"]
            rationale = "Folder name suggests backup or archive"
            confidence = 0.75
        } else if folderName.contains("download") {
            categoryPath = ["Downloads"]
            rationale = "Folder name suggests downloads"
            confidence = 0.7
        } else {
            // Analyze file types as fallback
            let typeGroups = Dictionary(grouping: folder.containedFiles) { file -> String in
                if file.isImage { return "image" }
                if file.isVideo { return "video" }
                if file.isAudio { return "audio" }
                if file.isDocument { return "document" }
                return "other"
            }
            
            // Find dominant type
            let dominant = typeGroups.max(by: { $0.value.count < $1.value.count })
            
            switch dominant?.key {
            case "image":
                categoryPath = ["Media", "Photos"]
                rationale = "Folder primarily contains images"
                confidence = 0.65
            case "video":
                categoryPath = ["Media", "Videos"]
                rationale = "Folder primarily contains videos"
                confidence = 0.65
            case "audio":
                categoryPath = ["Media", "Music"]
                rationale = "Folder primarily contains audio files"
                confidence = 0.65
            case "document":
                categoryPath = ["Documents"]
                rationale = "Folder primarily contains documents"
                confidence = 0.65
            default:
                categoryPath = ["Uncategorized", folder.folderName]
                rationale = "Could not determine category from folder name or contents"
                confidence = 0.4
            }
        }
        
        return FolderCategoryAssignment(
            folderId: folder.id,
            folderName: folder.folderName,
            categoryPath: categoryPath,
            confidence: confidence,
            rationale: rationale
        )
    }
}

// MARK: - Errors

enum FolderCategorizationError: LocalizedError {
    case invalidResponse(String)
    case noProvider
    case timeout
    case folderNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let reason):
            return "Invalid categorization response: \(reason)"
        case .noProvider:
            return "No LLM provider available for folder categorization"
        case .timeout:
            return "Folder categorization timed out"
        case .folderNotFound:
            return "Folder not found"
        }
    }
}
