// MARK: - Organization Engine
// Executes file organization based on verified taxonomy

import Foundation

// MARK: - Organization Engine

/// Executes file organization operations based on taxonomy assignments
actor OrganizationEngine {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// How to handle existing files at destination
        let mode: OrganizationMode
        
        /// Whether to flatten nested source folders
        let flattenSource: Bool
        
        /// Prefix for uncategorized folder
        let uncategorizedFolderName: String
        
        /// Maximum concurrent file operations
        let maxConcurrentOps: Int
        
        /// Whether to create a log of operations
        let createLog: Bool
        
        static let `default` = Configuration(
            mode: .move,
            flattenSource: false,
            uncategorizedFolderName: "Uncategorized",
            maxConcurrentOps: 5,
            createLog: true
        )
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private let fileManager = FileManager.default
    private var operations: [OrganizationOperation] = []
    private var conflicts: [OrganizationConflict] = []
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .default) {
        self.config = configuration
    }
    
    // MARK: - Planning
    
    /// Plan organization operations without executing
    func planOrganization(
        files: [TaxonomyScannedFile],
        assignments: [FileAssignment],
        tree: TaxonomyTree,
        outputFolder: URL
    ) async -> OrganizationPlan {
        var plannedOps: [OrganizationOperation] = []
        var detectedConflicts: [OrganizationConflict] = []
        var unassigned: [TaxonomyScannedFile] = []
        
        // Build assignment lookup
        let assignmentMap = Dictionary(
            assignments.map { ($0.fileId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        
        for file in files {
            guard let assignment = assignmentMap[file.id] else {
                unassigned.append(file)
                continue
            }
            
            // Resolve destination path
            guard let node = tree.node(byId: assignment.categoryId) else {
                unassigned.append(file)
                continue
            }
            
            let categoryPath = tree.pathToNode(node)
            let destinationFolder = categoryPath.reduce(outputFolder) { $0.appendingPathComponent($1.name) }
            let destinationFile = destinationFolder.appendingPathComponent(file.filename)
            
            // Check for conflicts
            if fileManager.fileExists(atPath: destinationFile.path) {
                detectedConflicts.append(OrganizationConflict(
                    sourceFile: file,
                    destinationPath: destinationFile,
                    resolution: .askUser
                ))
            } else {
                plannedOps.append(OrganizationOperation(
                    sourceFile: file,
                    destinationFolder: destinationFolder,
                    destinationPath: destinationFile,
                    mode: config.mode
                ))
            }
        }
        
        // Handle unassigned files
        if !unassigned.isEmpty {
            let uncategorizedFolder = outputFolder.appendingPathComponent(config.uncategorizedFolderName)
            
            for file in unassigned {
                let dest = uncategorizedFolder.appendingPathComponent(file.filename)
                
                if fileManager.fileExists(atPath: dest.path) {
                    detectedConflicts.append(OrganizationConflict(
                        sourceFile: file,
                        destinationPath: dest,
                        resolution: .askUser
                    ))
                } else {
                    plannedOps.append(OrganizationOperation(
                        sourceFile: file,
                        destinationFolder: uncategorizedFolder,
                        destinationPath: dest,
                        mode: config.mode
                    ))
                }
            }
        }
        
        return OrganizationPlan(
            operations: plannedOps,
            conflicts: detectedConflicts,
            estimatedSize: plannedOps.reduce(0) { $0 + $1.sourceFile.fileSize }
        )
    }
    
    /// Update conflict resolutions
    func resolveConflicts(_ resolutions: [UUID: ConflictResolution]) async {
        for conflict in conflicts {
            if let resolution = resolutions[conflict.id] {
                conflict.resolution = resolution
            }
        }
    }
    
    // MARK: - Hierarchy-Aware Planning
    
    /// Plan organization with hierarchy awareness
    /// Folders move as complete units, loose files move individually
    func planHierarchyOrganization(
        scanResult: HierarchyScanResult,
        folderAssignments: [FolderCategoryAssignment],
        fileAssignments: [FileAssignment],
        tree: TaxonomyTree,
        outputFolder: URL
    ) async -> HierarchyAwareOrganizationPlan {
        NSLog("📋 [OrganizationEngine] Planning hierarchy-aware organization")
        NSLog("📋 [OrganizationEngine] \(scanResult.folders.count) folders, \(scanResult.looseFiles.count) loose files")
        
        var folderOps: [FolderOrganizationOperation] = []
        var fileOps: [OrganizationOperation] = []
        var folderConflicts: [FolderOrganizationConflict] = []
        var fileConflicts: [OrganizationConflict] = []
        
        // Build assignment lookups
        let folderAssignmentMap = Dictionary(
            folderAssignments.map { ($0.folderId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        
        let fileAssignmentMap = Dictionary(
            fileAssignments.map { ($0.fileId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        
        // Plan folder operations
        for folder in scanResult.folders {
            guard let assignment = folderAssignmentMap[folder.id] else {
                // Unassigned folder - use Uncategorized
                let destFolder = outputFolder.appendingPathComponent(config.uncategorizedFolderName)
                let destPath = destFolder.appendingPathComponent(folder.folderName)
                
                if fileManager.fileExists(atPath: destPath.path) {
                    folderConflicts.append(FolderOrganizationConflict(
                        sourceFolder: folder,
                        destinationPath: destPath,
                        resolution: .askUser
                    ))
                } else {
                    folderOps.append(FolderOrganizationOperation(
                        sourceFolder: folder,
                        destinationFolder: destFolder,
                        destinationCategory: config.uncategorizedFolderName,
                        confidence: 0.3,
                        mode: config.mode
                    ))
                }
                continue
            }
            
            // Build destination from category path
            let categoryPath = assignment.categoryPath
            let destFolder = categoryPath.reduce(outputFolder) { $0.appendingPathComponent($1) }
            let destPath = destFolder.appendingPathComponent(folder.folderName)
            
            // Check for conflicts
            if fileManager.fileExists(atPath: destPath.path) {
                folderConflicts.append(FolderOrganizationConflict(
                    sourceFolder: folder,
                    destinationPath: destPath,
                    resolution: .askUser
                ))
            } else {
                folderOps.append(FolderOrganizationOperation(
                    sourceFolder: folder,
                    destinationFolder: destFolder,
                    destinationCategory: categoryPath.joined(separator: " / "),
                    confidence: assignment.confidence,
                    mode: config.mode
                ))
            }
        }
        
        // Plan loose file operations (same as regular planning)
        for file in scanResult.looseFiles {
            guard let assignment = fileAssignmentMap[file.id] else {
                // Unassigned file
                let uncategorizedFolder = outputFolder.appendingPathComponent(config.uncategorizedFolderName)
                let dest = uncategorizedFolder.appendingPathComponent(file.filename)
                
                if fileManager.fileExists(atPath: dest.path) {
                    fileConflicts.append(OrganizationConflict(
                        sourceFile: file,
                        destinationPath: dest,
                        resolution: .askUser
                    ))
                } else {
                    fileOps.append(OrganizationOperation(
                        sourceFile: file,
                        destinationFolder: uncategorizedFolder,
                        destinationPath: dest,
                        mode: config.mode
                    ))
                }
                continue
            }
            
            // Build destination from category
            guard let node = tree.node(byId: assignment.categoryId) else {
                let uncategorizedFolder = outputFolder.appendingPathComponent(config.uncategorizedFolderName)
                let dest = uncategorizedFolder.appendingPathComponent(file.filename)
                
                if fileManager.fileExists(atPath: dest.path) {
                    fileConflicts.append(OrganizationConflict(
                        sourceFile: file,
                        destinationPath: dest,
                        resolution: .askUser
                    ))
                } else {
                    fileOps.append(OrganizationOperation(
                        sourceFile: file,
                        destinationFolder: uncategorizedFolder,
                        destinationPath: dest,
                        mode: config.mode
                    ))
                }
                continue
            }
            
            let categoryPath = tree.pathToNode(node)
            let destFolder = categoryPath.reduce(outputFolder) { $0.appendingPathComponent($1.name) }
            let destFile = destFolder.appendingPathComponent(file.filename)
            
            if fileManager.fileExists(atPath: destFile.path) {
                fileConflicts.append(OrganizationConflict(
                    sourceFile: file,
                    destinationPath: destFile,
                    resolution: .askUser
                ))
            } else {
                fileOps.append(OrganizationOperation(
                    sourceFile: file,
                    destinationFolder: destFolder,
                    destinationPath: destFile,
                    mode: config.mode
                ))
            }
        }
        
        let totalSize = folderOps.reduce(0) { $0 + $1.sourceFolder.totalSize } +
                        fileOps.reduce(0) { $0 + $1.sourceFile.fileSize }
        
        NSLog("📋 [OrganizationEngine] Plan complete: \(folderOps.count) folder ops, \(fileOps.count) file ops")
        NSLog("📋 [OrganizationEngine] Conflicts: \(folderConflicts.count) folder, \(fileConflicts.count) file")
        
        return HierarchyAwareOrganizationPlan(
            folderOperations: folderOps,
            fileOperations: fileOps,
            folderConflicts: folderConflicts,
            fileConflicts: fileConflicts,
            estimatedSize: totalSize
        )
    }
    
    // MARK: - Execution
    
    /// Execute the organization plan
    func execute(
        plan: OrganizationPlan,
        progressCallback: @escaping @Sendable (OrganizationProgress) -> Void
    ) async throws -> WizardOrganizationResult {
        var successCount = 0
        var failedOps: [FailedOperation] = []
        var skippedCount = 0
        
        let totalOps = plan.operations.count + plan.conflicts.count
        
        // Execute planned operations
        for (index, op) in plan.operations.enumerated() {
            do {
                try await executeOperation(op)
                successCount += 1
            } catch {
                failedOps.append(FailedOperation(
                    file: op.sourceFile,
                    error: error.localizedDescription
                ))
            }
            
            progressCallback(OrganizationProgress(
                completed: index + 1,
                total: totalOps,
                currentFile: op.sourceFile.filename,
                phase: .executing
            ))
        }
        
        // Handle resolved conflicts
        for (index, conflict) in plan.conflicts.enumerated() {
            switch conflict.resolution {
            case .skip:
                skippedCount += 1
                
            case .rename:
                let newDest = generateUniqueFilename(for: conflict.destinationPath)
                let op = OrganizationOperation(
                    sourceFile: conflict.sourceFile,
                    destinationFolder: conflict.destinationPath.deletingLastPathComponent(),
                    destinationPath: newDest,
                    mode: config.mode
                )
                do {
                    try await executeOperation(op)
                    successCount += 1
                } catch {
                    failedOps.append(FailedOperation(
                        file: conflict.sourceFile,
                        error: error.localizedDescription
                    ))
                }
                
            case .replace:
                // Remove existing file first
                try? fileManager.removeItem(at: conflict.destinationPath)
                let op = OrganizationOperation(
                    sourceFile: conflict.sourceFile,
                    destinationFolder: conflict.destinationPath.deletingLastPathComponent(),
                    destinationPath: conflict.destinationPath,
                    mode: config.mode
                )
                do {
                    try await executeOperation(op)
                    successCount += 1
                } catch {
                    failedOps.append(FailedOperation(
                        file: conflict.sourceFile,
                        error: error.localizedDescription
                    ))
                }
                
            case .askUser:
                skippedCount += 1
            }
            
            progressCallback(OrganizationProgress(
                completed: plan.operations.count + index + 1,
                total: totalOps,
                currentFile: conflict.sourceFile.filename,
                phase: .resolvingConflicts
            ))
        }
        
        // Write log if configured
        if config.createLog {
            await writeLog(
                operations: plan.operations,
                conflicts: plan.conflicts,
                failures: failedOps
            )
        }
        
        return WizardOrganizationResult(
            successCount: successCount,
            failedOperations: failedOps,
            skippedCount: skippedCount,
            totalProcessed: totalOps
        )
    }
    
    // MARK: - Private Methods
    
    private func executeOperation(_ op: OrganizationOperation) async throws {
        // Create destination folder if needed
        try fileManager.createDirectory(
            at: op.destinationFolder,
            withIntermediateDirectories: true
        )
        
        switch op.mode {
        case .move:
            try fileManager.moveItem(at: op.sourceFile.url, to: op.destinationPath)
            
        case .copy:
            try fileManager.copyItem(at: op.sourceFile.url, to: op.destinationPath)
            
        case .symlink:
            try fileManager.createSymbolicLink(
                at: op.destinationPath,
                withDestinationURL: op.sourceFile.url
            )
        }
    }
    
    private func generateUniqueFilename(for url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        
        var counter = 1
        var newURL = url
        
        while fileManager.fileExists(atPath: newURL.path) {
            let newName = ext.isEmpty ? "\(filename) (\(counter))" : "\(filename) (\(counter)).\(ext)"
            newURL = folder.appendingPathComponent(newName)
            counter += 1
        }
        
        return newURL
    }
    
    private func writeLog(
        operations: [OrganizationOperation],
        conflicts: [OrganizationConflict],
        failures: [FailedOperation]
    ) async {
        let log = """
        SortAI Organization Log
        Date: \(Date())
        
        === SUCCESSFUL OPERATIONS (\(operations.count - failures.count)) ===
        \(operations.map { "[\($0.mode)] \($0.sourceFile.filename) -> \($0.destinationPath.path)" }.joined(separator: "\n"))
        
        === CONFLICTS (\(conflicts.count)) ===
        \(conflicts.map { "[\($0.resolution)] \($0.sourceFile.filename) -> \($0.destinationPath.path)" }.joined(separator: "\n"))
        
        === FAILURES (\(failures.count)) ===
        \(failures.map { "[FAILED] \($0.file.filename): \($0.error)" }.joined(separator: "\n"))
        """
        
        if let logFolder = operations.first?.destinationFolder.deletingLastPathComponent() {
            let logFile = logFolder.appendingPathComponent("sortai_log_\(Date().timeIntervalSince1970).txt")
            try? log.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Supporting Types

struct OrganizationOperation: Sendable {
    let sourceFile: TaxonomyScannedFile
    let destinationFolder: URL
    let destinationPath: URL
    let mode: OrganizationMode
}

final class OrganizationConflict: @unchecked Sendable, Identifiable {
    let id = UUID()
    let sourceFile: TaxonomyScannedFile
    let destinationPath: URL
    var resolution: ConflictResolution
    
    init(sourceFile: TaxonomyScannedFile, destinationPath: URL, resolution: ConflictResolution) {
        self.sourceFile = sourceFile
        self.destinationPath = destinationPath
        self.resolution = resolution
    }
}

enum ConflictResolution: String, CaseIterable, Sendable {
    case skip = "Skip"
    case rename = "Rename (add number)"
    case replace = "Replace existing"
    case askUser = "Ask user"
}

struct OrganizationPlan: Sendable {
    let operations: [OrganizationOperation]
    let conflicts: [OrganizationConflict]
    let estimatedSize: Int64
    
    var hasConflicts: Bool { !conflicts.isEmpty }
    var totalFiles: Int { operations.count + conflicts.count }
}

struct OrganizationProgress: Sendable {
    let completed: Int
    let total: Int
    let currentFile: String
    let phase: OrganizationPhase
    
    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total) * 100
    }
    
    enum OrganizationPhase: String, Sendable {
        case planning = "Planning..."
        case executing = "Organizing files..."
        case resolvingConflicts = "Resolving conflicts..."
        case complete = "Complete"
    }
}

struct WizardOrganizationResult: Sendable {
    let successCount: Int
    let failedOperations: [FailedOperation]
    let skippedCount: Int
    let totalProcessed: Int
    
    var allSuccessful: Bool { failedOperations.isEmpty }
}

struct FailedOperation: Sendable {
    let file: TaxonomyScannedFile
    let error: String
}


// MARK: - Hierarchy-Aware Organization Types

/// Operation for moving a folder as a complete unit
struct FolderOrganizationOperation: Sendable, Identifiable {
    let id: UUID
    let sourceFolder: ScannedFolder
    let destinationFolder: URL          // Where the folder will be moved to
    let destinationCategory: String     // Category name for display
    let confidence: Double
    let preserveInternalStructure: Bool // Always true for folder units
    let mode: OrganizationMode
    
    init(
        id: UUID = UUID(),
        sourceFolder: ScannedFolder,
        destinationFolder: URL,
        destinationCategory: String,
        confidence: Double,
        mode: OrganizationMode
    ) {
        self.id = id
        self.sourceFolder = sourceFolder
        self.destinationFolder = destinationFolder
        self.destinationCategory = destinationCategory
        self.confidence = confidence
        self.preserveInternalStructure = true
        self.mode = mode
    }
}

/// Conflict when organizing a folder
final class FolderOrganizationConflict: @unchecked Sendable, Identifiable {
    let id = UUID()
    let sourceFolder: ScannedFolder
    let destinationPath: URL
    var resolution: ConflictResolution
    
    init(sourceFolder: ScannedFolder, destinationPath: URL, resolution: ConflictResolution) {
        self.sourceFolder = sourceFolder
        self.destinationPath = destinationPath
        self.resolution = resolution
    }
}

/// Organization plan that respects folder hierarchy
/// Separates folder operations from individual file operations
struct HierarchyAwareOrganizationPlan: Sendable {
    let folderOperations: [FolderOrganizationOperation]
    let fileOperations: [OrganizationOperation]
    let folderConflicts: [FolderOrganizationConflict]
    let fileConflicts: [OrganizationConflict]
    let estimatedSize: Int64
    
    /// Total number of items to organize
    var totalItems: Int {
        folderOperations.count + fileOperations.count
    }
    
    /// Total file count (including files inside folders)
    var totalFileCount: Int {
        let folderFiles = folderOperations.reduce(0) { $0 + $1.sourceFolder.fileCount }
        return folderFiles + fileOperations.count
    }
    
    /// Whether there are any conflicts to resolve
    var hasConflicts: Bool {
        !folderConflicts.isEmpty || !fileConflicts.isEmpty
    }
    
    /// Convert to legacy OrganizationPlan (flattens folders into individual file ops)
    func toLegacyPlan() -> OrganizationPlan {
        var allFileOps = fileOperations
        
        // Flatten folder operations into file operations
        for folderOp in folderOperations {
            for file in folderOp.sourceFolder.containedFiles {
                let destPath = folderOp.destinationFolder
                    .appendingPathComponent(folderOp.sourceFolder.folderName)
                    .appendingPathComponent(file.relativePath.replacingOccurrences(
                        of: folderOp.sourceFolder.relativePath + "/",
                        with: ""
                    ))
                
                allFileOps.append(OrganizationOperation(
                    sourceFile: file,
                    destinationFolder: destPath.deletingLastPathComponent(),
                    destinationPath: destPath,
                    mode: folderOp.mode
                ))
            }
        }
        
        // Combine conflicts
        let allConflicts = fileConflicts
        
        return OrganizationPlan(
            operations: allFileOps,
            conflicts: allConflicts,
            estimatedSize: estimatedSize
        )
    }
}
