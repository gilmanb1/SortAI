// MARK: - File Move Command
// Command pattern for undoable file operations

import Foundation

// MARK: - File Move Command Protocol

/// Protocol for undoable file operations
protocol FileMoveCommand: Sendable {
    /// Unique identifier for this command
    var id: UUID { get }
    
    /// Source file URL
    var source: URL { get }
    
    /// Destination file URL
    var destination: URL { get }
    
    /// Execute the command
    func execute() async throws
    
    /// Undo the command
    func undo() async throws
    
    /// Whether this command can be undone
    var canUndo: Bool { get }
    
    /// Description of the operation
    var description: String { get }
}

// MARK: - Move File Command

/// Command for moving a file
struct MoveFileCommand: FileMoveCommand {
    let id: UUID
    let source: URL
    let destination: URL
    
    var canUndo: Bool { true }
    
    var description: String {
        "Move \(source.lastPathComponent) to \(destination.deletingLastPathComponent().lastPathComponent)"
    }
    
    init(source: URL, destination: URL) {
        self.id = UUID()
        self.source = source
        self.destination = destination
    }
    
    func execute() async throws {
        let fileManager = FileManager.default
        
        // Ensure destination directory exists
        let destDir = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Move the file
        try fileManager.moveItem(at: source, to: destination)
    }
    
    func undo() async throws {
        let fileManager = FileManager.default
        
        // Move back to original location
        // Ensure source directory exists (in case it was deleted)
        let sourceDir = source.deletingLastPathComponent()
        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        // Move back
        try fileManager.moveItem(at: destination, to: source)
    }
}

// MARK: - Copy File Command

/// Command for copying a file
struct CopyFileCommand: FileMoveCommand {
    let id: UUID
    let source: URL
    let destination: URL
    
    var canUndo: Bool { true }
    
    var description: String {
        "Copy \(source.lastPathComponent) to \(destination.deletingLastPathComponent().lastPathComponent)"
    }
    
    init(source: URL, destination: URL) {
        self.id = UUID()
        self.source = source
        self.destination = destination
    }
    
    func execute() async throws {
        let fileManager = FileManager.default
        
        // Ensure destination directory exists
        let destDir = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Copy the file
        try fileManager.copyItem(at: source, to: destination)
    }
    
    func undo() async throws {
        let fileManager = FileManager.default
        
        // Delete the copied file
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
    }
}

// MARK: - Symlink File Command

/// Command for creating a symbolic link
struct SymlinkFileCommand: FileMoveCommand {
    let id: UUID
    let source: URL
    let destination: URL
    
    var canUndo: Bool { true }
    
    var description: String {
        "Create symlink \(destination.lastPathComponent) -> \(source.path)"
    }
    
    init(source: URL, destination: URL) {
        self.id = UUID()
        self.source = source
        self.destination = destination
    }
    
    func execute() async throws {
        let fileManager = FileManager.default
        
        // Ensure destination directory exists
        let destDir = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Create symlink
        try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
    }
    
    func undo() async throws {
        let fileManager = FileManager.default
        
        // Remove the symlink
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
    }
}

// MARK: - Undo Stack

/// Manages a stack of undoable file operations
actor UndoStack {
    
    private var undoStack: [FileMoveCommand] = []
    private var redoStack: [FileMoveCommand] = []
    private let maxStackSize: Int
    
    init(maxStackSize: Int = 100) {
        self.maxStackSize = maxStackSize
    }
    
    /// Pushes a command onto the undo stack and executes it
    func pushAndExecute(_ command: FileMoveCommand) async throws {
        // Execute the command
        try await command.execute()
        
        // Add to undo stack
        undoStack.append(command)
        
        // Clear redo stack when new command is executed
        redoStack.removeAll()
        
        // Limit stack size
        if undoStack.count > maxStackSize {
            undoStack.removeFirst()
        }
    }
    
    /// Undoes the last command
    func undo() async throws -> FileMoveCommand? {
        guard let command = undoStack.popLast() else {
            return nil
        }
        
        guard command.canUndo else {
            // Put it back if can't undo
            undoStack.append(command)
            return nil
        }
        
        // Undo the command
        try await command.undo()
        
        // Move to redo stack
        redoStack.append(command)
        
        return command
    }
    
    /// Redoes the last undone command
    func redo() async throws -> FileMoveCommand? {
        guard let command = redoStack.popLast() else {
            return nil
        }
        
        // Re-execute the command
        try await command.execute()
        
        // Move back to undo stack
        undoStack.append(command)
        
        return command
    }
    
    /// Gets the current undo stack (for inspection)
    func getUndoStack() -> [FileMoveCommand] {
        undoStack
    }
    
    /// Gets the current redo stack (for inspection)
    func getRedoStack() -> [FileMoveCommand] {
        redoStack
    }
    
    /// Clears both stacks
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
    
    /// Checks if undo is available
    var canUndo: Bool {
        !undoStack.isEmpty && (undoStack.last?.canUndo ?? false)
    }
    
    /// Checks if redo is available
    var canRedo: Bool {
        !redoStack.isEmpty
    }
    
    /// Gets count of undoable commands
    var undoCount: Int {
        undoStack.count
    }
    
    /// Gets count of redoable commands
    var redoCount: Int {
        redoStack.count
    }
}

