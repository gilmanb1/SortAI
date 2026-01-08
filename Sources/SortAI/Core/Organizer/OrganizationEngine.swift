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

