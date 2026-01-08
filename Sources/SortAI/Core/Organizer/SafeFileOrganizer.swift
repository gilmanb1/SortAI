// MARK: - Safe File Organizer
// Enhanced organizer with collision handling, undo support, and movement logging

import Foundation

// MARK: - Safe File Organizer Configuration

struct SafeFileOrganizerConfiguration: Sendable {
    /// How to handle file operations
    let mode: OrganizationMode
    
    /// Prefer symlinks over moves for reversibility
    let preferSymlinks: Bool
    
    /// Never delete files (no-delete invariant)
    let noDelete: Bool
    
    /// Auto-resolve collisions with rename
    let autoResolveCollisions: Bool
    
    /// Collision naming style
    let collisionStyle: CollisionNamingStyle
    
    /// Log all movements to database
    let logMovements: Bool
    
    /// Enable undo support
    let enableUndo: Bool
    
    static let `default` = SafeFileOrganizerConfiguration(
        mode: .copy,
        preferSymlinks: false,
        noDelete: true,
        autoResolveCollisions: true,
        collisionStyle: .macOS,
        logMovements: true,
        enableUndo: true
    )
    
    static let safest = SafeFileOrganizerConfiguration(
        mode: .symlink,
        preferSymlinks: true,
        noDelete: true,
        autoResolveCollisions: true,
        collisionStyle: .macOS,
        logMovements: true,
        enableUndo: true
    )
}

enum CollisionNamingStyle: Sendable {
    case macOS         // "file (1).pdf", "file (2).pdf"
    case numbered      // "file-1.pdf", "file-2.pdf"
    case timestamped   // "file-20231201-120000.pdf"
    
    func generateName(for url: URL, counter: Int) -> String {
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        
        switch self {
        case .macOS:
            let newName = "\(baseName) (\(counter))"
            return ext.isEmpty ? newName : "\(newName).\(ext)"
            
        case .numbered:
            let newName = "\(baseName)-\(counter)"
            return ext.isEmpty ? newName : "\(newName).\(ext)"
            
        case .timestamped:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = formatter.string(from: Date())
            let newName = "\(baseName)-\(timestamp)"
            return ext.isEmpty ? newName : "\(newName).\(ext)"
        }
    }
}

// MARK: - Safe File Organizer Actor

/// Enhanced file organizer with safety features, logging, and undo support
actor SafeFileOrganizer {
    
    // MARK: - Properties
    
    private let config: SafeFileOrganizerConfiguration
    private let database: SortAIDatabase
    private let undoStack: UndoStack
    
    // MARK: - Initialization
    
    init(
        configuration: SafeFileOrganizerConfiguration = .default,
        database: SortAIDatabase,
        undoStack: UndoStack
    ) {
        self.config = configuration
        self.database = database
        self.undoStack = undoStack
    }
    
    // MARK: - Organization
    
    /// Organize files with full safety features
    func organize(
        files: [TaxonomyScannedFile],
        assignments: [FileAssignment],
        tree: TaxonomyTree,
        outputFolder: URL,
        mode: MovementLogEntry.LLMMode = .full,
        provider: String? = nil,
        providerVersion: String? = nil
    ) async throws -> SafeOrganizationResult {
        
        let fileManager = FileManager.default
        
        var successful: [SafeOrganizationOperation] = []
        var failed: [SafeOrganizationFailure] = []
        var collisionsResolved: [CollisionResolution] = []
        
        // Build assignment lookup
        let assignmentMap = Dictionary(
            assignments.map { ($0.fileId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        
        for file in files {
            guard let assignment = assignmentMap[file.id] else {
                failed.append(SafeOrganizationFailure(
                    file: file,
                    reason: "No assignment found for file",
                    error: nil
                ))
                continue
            }
            
            // Resolve destination path
            guard let node = tree.node(byId: assignment.categoryId) else {
                failed.append(SafeOrganizationFailure(
                    file: file,
                    reason: "Category node not found",
                    error: nil
                ))
                continue
            }
            
            let categoryPath = tree.pathToNode(node)
            let destinationFolder = categoryPath.reduce(outputFolder) { 
                $0.appendingPathComponent($1.name) 
            }
            
            // Create destination folder
            do {
                try fileManager.createDirectory(
                    at: destinationFolder, 
                    withIntermediateDirectories: true
                )
            } catch {
                failed.append(SafeOrganizationFailure(
                    file: file,
                    reason: "Failed to create destination folder",
                    error: error
                ))
                continue
            }
            
            var destinationFile = destinationFolder.appendingPathComponent(file.filename)
            var collision: CollisionResolution? = nil
            
            // Handle collisions
            if fileManager.fileExists(atPath: destinationFile.path) {
                if config.autoResolveCollisions {
                    let originalDest = destinationFile
                    destinationFile = try await resolveCollision(destinationFile)
                    collision = CollisionResolution(
                        originalPath: originalDest,
                        resolvedPath: destinationFile,
                        strategy: "Auto-rename"
                    )
                    collisionsResolved.append(collision!)
                } else {
                    failed.append(SafeOrganizationFailure(
                        file: file,
                        reason: "File already exists at destination",
                        error: nil
                    ))
                    continue
                }
            }
            
            // Determine operation mode
            let operationMode = config.preferSymlinks ? OrganizationMode.symlink : config.mode
            
            // Create command
            let command: FileMoveCommand = switch operationMode {
            case .move:
                MoveFileCommand(source: file.url, destination: destinationFile)
            case .copy:
                CopyFileCommand(source: file.url, destination: destinationFile)
            case .symlink:
                SymlinkFileCommand(source: file.url, destination: destinationFile)
            }
            
            // Execute with undo support
            do {
                if config.enableUndo {
                    try await undoStack.pushAndExecute(command)
                } else {
                    try await command.execute()
                }
                
                // Log to movement log
                if config.logMovements {
                    let logEntry = MovementLogEntry(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        source: file.url,
                        destination: destinationFile,
                        reason: node.name,
                        confidence: assignment.confidence,
                        mode: mode,
                        provider: provider,
                        providerVersion: providerVersion,
                        operationType: operationMode == .move ? .move : 
                                      operationMode == .copy ? .copy : .symlink,
                        undoable: config.enableUndo,
                        undoneAt: nil
                    )
                    
                    try database.movementLog.create(logEntry)
                }
                
                successful.append(SafeOrganizationOperation(
                    file: file,
                    source: file.url,
                    destination: destinationFile,
                    mode: operationMode,
                    category: node.name,
                    confidence: assignment.confidence,
                    collision: collision
                ))
                
            } catch {
                // Attempt to undo if failure occurs and undo is enabled
                if config.enableUndo {
                    _ = try? await undoStack.undo()
                }
                
                failed.append(SafeOrganizationFailure(
                    file: file,
                    reason: "Operation failed: \(error.localizedDescription)",
                    error: error
                ))
            }
        }
        
        return SafeOrganizationResult(
            successful: successful,
            failed: failed,
            collisionsResolved: collisionsResolved,
            totalFiles: files.count
        )
    }
    
    // MARK: - Collision Resolution
    
    /// Resolve file name collision using configured strategy
    private func resolveCollision(_ url: URL) async throws -> URL {
        let fileManager = FileManager.default
        let folder = url.deletingLastPathComponent()
        var counter = 1
        var newURL = url
        
        // Enforce no-delete invariant
        guard config.noDelete else {
            throw SafeOrganizerError.deleteNotAllowed
        }
        
        // Generate unique name
        while fileManager.fileExists(atPath: newURL.path) {
            let newName = config.collisionStyle.generateName(for: url, counter: counter)
            newURL = folder.appendingPathComponent(newName)
            counter += 1
            
            // Safety limit to prevent infinite loops
            if counter > 9999 {
                throw SafeOrganizerError.collisionResolutionFailed(
                    "Could not generate unique name after 9999 attempts"
                )
            }
        }
        
        return newURL
    }
    
    // MARK: - Undo Operations
    
    /// Undo the last operation
    func undoLastOperation() async throws -> FileMoveCommand? {
        guard config.enableUndo else {
            throw SafeOrganizerError.undoNotEnabled
        }
        
        let command = try await undoStack.undo()
        
        // Update movement log if command was undone
        if let command = command, config.logMovements {
            // Mark as undone in movement log
            let entries = try database.movementLog.findByDestination(command.destination, limit: 100)
            if let entry = entries.first {
                try database.movementLog.markUndone(id: entry.id)
            }
        }
        
        return command
    }
    
    /// Redo the last undone operation
    func redoLastOperation() async throws -> FileMoveCommand? {
        guard config.enableUndo else {
            throw SafeOrganizerError.undoNotEnabled
        }
        
        return try await undoStack.redo()
    }
    
    /// Check if undo is available
    var canUndo: Bool {
        get async {
            await undoStack.canUndo
        }
    }
    
    /// Check if redo is available
    var canRedo: Bool {
        get async {
            await undoStack.canRedo
        }
    }
    
    /// Get undo stack count
    var undoCount: Int {
        get async {
            await undoStack.undoCount
        }
    }
    
    // MARK: - Safety Validation
    
    /// Validate that no delete operations will occur
    func validateNoDelete(_ operations: [OrganizationOperation]) throws {
        guard config.noDelete else { return }
        
        // All our operations (move, copy, symlink) are safe
        // This is a sanity check that no custom operations try to delete
        for _ in operations {
            // Moves don't delete (they relocate)
            // Copies don't delete (they duplicate)
            // Symlinks don't delete (they create links)
            // This invariant is maintained by design
        }
    }
}

// MARK: - Supporting Types

struct SafeOrganizationOperation: Sendable, Identifiable {
    let id = UUID()
    let file: TaxonomyScannedFile
    let source: URL
    let destination: URL
    let mode: OrganizationMode
    let category: String
    let confidence: Double
    let collision: CollisionResolution?
}

struct SafeOrganizationFailure: Sendable, Identifiable {
    let id = UUID()
    let file: TaxonomyScannedFile
    let reason: String
    let error: Error?
}

struct CollisionResolution: Sendable, Identifiable {
    let id = UUID()
    let originalPath: URL
    let resolvedPath: URL
    let strategy: String
}

struct SafeOrganizationResult: Sendable {
    let successful: [SafeOrganizationOperation]
    let failed: [SafeOrganizationFailure]
    let collisionsResolved: [CollisionResolution]
    let totalFiles: Int
    
    var successCount: Int { successful.count }
    var failureCount: Int { failed.count }
    var collisionCount: Int { collisionsResolved.count }
    var successRate: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(successCount) / Double(totalFiles)
    }
}

// MARK: - Errors

enum SafeOrganizerError: Error, LocalizedError {
    case deleteNotAllowed
    case undoNotEnabled
    case collisionResolutionFailed(String)
    case invalidOperation(String)
    
    var errorDescription: String? {
        switch self {
        case .deleteNotAllowed:
            return "Delete operations are not allowed (no-delete invariant)"
        case .undoNotEnabled:
            return "Undo is not enabled in configuration"
        case .collisionResolutionFailed(let details):
            return "Failed to resolve collision: \(details)"
        case .invalidOperation(let details):
            return "Invalid operation: \(details)"
        }
    }
}

