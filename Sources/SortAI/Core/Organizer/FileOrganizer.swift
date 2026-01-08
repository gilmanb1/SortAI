// MARK: - File Organizer
// Creates structured folder hierarchy and organizes files by category

import Foundation

// MARK: - Organization Result

struct OrganizationResult: Sendable, Identifiable {
    let id: UUID
    let sourceFile: URL
    let destinationFile: URL
    let category: String
    let subcategory: String?
    let success: Bool
    let error: String?
    
    init(
        sourceFile: URL,
        destinationFile: URL,
        category: String,
        subcategory: String? = nil,
        success: Bool = true,
        error: String? = nil
    ) {
        self.id = UUID()
        self.sourceFile = sourceFile
        self.destinationFile = destinationFile
        self.category = category
        self.subcategory = subcategory
        self.success = success
        self.error = error
    }
}

struct OrganizationSummary: Sendable {
    let outputFolder: URL
    let totalFiles: Int
    let successCount: Int
    let failureCount: Int
    let categoriesCreated: Set<String>
    let results: [OrganizationResult]
    
    var successRate: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(successCount) / Double(totalFiles)
    }
}

// MARK: - Organization Mode

enum OrganizationMode: String, CaseIterable, Codable, Sendable {
    case copy = "Copy"
    case move = "Move"
    case symlink = "Symlink"
    
    var description: String {
        switch self {
        case .copy: return "Copy files to new location"
        case .move: return "Move files to new location"
        case .symlink: return "Create symbolic links"
        }
    }
}

// MARK: - File Organizer Actor

actor FileOrganizer: FileOrganizing {
    
    private let fileManager = FileManager.default
    
    // MARK: - Create Output Structure
    
    /// Creates the organized folder structure and moves/copies files
    func organize(
        results: [ProcessingResult],
        to outputFolder: URL,
        mode: OrganizationMode = .copy
    ) async throws -> OrganizationSummary {
        // Create output folder if needed
        try fileManager.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        
        var organizationResults: [OrganizationResult] = []
        var categoriesCreated = Set<String>()
        var successCount = 0
        var failureCount = 0
        
        for result in results {
            // Use full category path from BrainResult
            let fullPath = result.brainResult.fullCategoryPath
            
            // Build destination path using ALL components
            var destinationFolder = outputFolder
            for component in fullPath.components {
                destinationFolder = destinationFolder.appendingPathComponent(sanitizeFolderName(component))
            }
            
            // For backwards compatibility, keep track of category/subcategory
            let category = sanitizeFolderName(fullPath.root)
            let subcategory = fullPath.components.count > 1 
                ? sanitizeFolderName(fullPath.components.last!) 
                : nil
            
            // Create category folder
            try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            categoriesCreated.insert(category)
            
            // Determine destination file path
            let sourceFile = result.signature.url
            var destinationFile = destinationFolder.appendingPathComponent(sourceFile.lastPathComponent)
            
            // Handle name conflicts
            destinationFile = resolveNameConflict(destinationFile)
            
            // Perform the file operation
            do {
                switch mode {
                case .copy:
                    try fileManager.copyItem(at: sourceFile, to: destinationFile)
                case .move:
                    try fileManager.moveItem(at: sourceFile, to: destinationFile)
                case .symlink:
                    try fileManager.createSymbolicLink(at: destinationFile, withDestinationURL: sourceFile)
                }
                
                organizationResults.append(OrganizationResult(
                    sourceFile: sourceFile,
                    destinationFile: destinationFile,
                    category: category,
                    subcategory: subcategory
                ))
                successCount += 1
                
            } catch {
                organizationResults.append(OrganizationResult(
                    sourceFile: sourceFile,
                    destinationFile: destinationFile,
                    category: category,
                    subcategory: subcategory,
                    success: false,
                    error: error.localizedDescription
                ))
                failureCount += 1
            }
        }
        
        return OrganizationSummary(
            outputFolder: outputFolder,
            totalFiles: results.count,
            successCount: successCount,
            failureCount: failureCount,
            categoriesCreated: categoriesCreated,
            results: organizationResults
        )
    }
    
    // MARK: - Preview Structure
    
    /// Generates a preview of the folder structure without actually creating it
    func previewStructure(results: [ProcessingResult]) -> [String: [String]] {
        var structure: [String: [String]] = [:]
        
        for result in results {
            // Use full category path for preview
            let fullPath = result.brainResult.fullCategoryPath
            let fileName = result.signature.url.lastPathComponent
            
            // Build path string from all components
            let path = fullPath.components.map { sanitizeFolderName($0) }.joined(separator: "/")
            
            if structure[path] == nil {
                structure[path] = []
            }
            structure[path]?.append(fileName)
        }
        
        return structure
    }
    
    // MARK: - Helpers
    
    /// Sanitizes folder name for filesystem compatibility
    private func sanitizeFolderName(_ name: String) -> String {
        // Replace invalid characters
        var sanitized = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "|", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Convert to lowercase with hyphens
        sanitized = sanitized.lowercased()
        
        // Replace spaces with hyphens
        sanitized = sanitized.replacingOccurrences(of: " ", with: "-")
        
        // Remove consecutive hyphens
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }
        
        // Limit length
        if sanitized.count > 50 {
            sanitized = String(sanitized.prefix(50))
        }
        
        // Ensure not empty
        if sanitized.isEmpty {
            sanitized = "uncategorized"
        }
        
        return sanitized
    }
    
    /// Resolves name conflicts by adding a number suffix
    private func resolveNameConflict(_ url: URL) -> URL {
        var resultURL = url
        var counter = 1
        
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let parentDir = url.deletingLastPathComponent()
        
        while fileManager.fileExists(atPath: resultURL.path) {
            let newName = "\(baseName)-\(counter)"
            resultURL = parentDir
                .appendingPathComponent(newName)
                .appendingPathExtension(ext)
            counter += 1
        }
        
        return resultURL
    }
}

