// MARK: - Safe File Organizer Tests
// Tests for enhanced organizer with safety features

import Testing
import Foundation
@testable import SortAI

@Suite("Safe File Organizer Tests")
struct SafeFileOrganizerTests {
    
    // MARK: - Collision Resolution Tests
    
    @Test("macOS collision naming style")
    func testMacOSCollisionStyle() {
        let style = CollisionNamingStyle.macOS
        let url = URL(fileURLWithPath: "/test/file.pdf")
        
        #expect(style.generateName(for: url, counter: 1) == "file (1).pdf")
        #expect(style.generateName(for: url, counter: 2) == "file (2).pdf")
        #expect(style.generateName(for: url, counter: 10) == "file (10).pdf")
    }
    
    @Test("Numbered collision naming style")
    func testNumberedCollisionStyle() {
        let style = CollisionNamingStyle.numbered
        let url = URL(fileURLWithPath: "/test/file.pdf")
        
        #expect(style.generateName(for: url, counter: 1) == "file-1.pdf")
        #expect(style.generateName(for: url, counter: 2) == "file-2.pdf")
    }
    
    @Test("Timestamped collision naming style")
    func testTimestampedCollisionStyle() {
        let style = CollisionNamingStyle.timestamped
        let url = URL(fileURLWithPath: "/test/file.pdf")
        
        let name = style.generateName(for: url, counter: 1)
        #expect(name.hasPrefix("file-"))
        #expect(name.hasSuffix(".pdf"))
        #expect(name.contains("-"))
    }
    
    @Test("Collision style with no extension")
    func testCollisionStyleNoExtension() {
        let style = CollisionNamingStyle.macOS
        let url = URL(fileURLWithPath: "/test/README")
        
        #expect(style.generateName(for: url, counter: 1) == "README (1)")
    }
    
    // MARK: - Configuration Tests
    
    @Test("Default configuration")
    func testDefaultConfiguration() {
        let config = SafeFileOrganizerConfiguration.default
        
        #expect(config.mode == .copy)
        #expect(config.preferSymlinks == false)
        #expect(config.noDelete == true)
        #expect(config.autoResolveCollisions == true)
        #expect(config.logMovements == true)
        #expect(config.enableUndo == true)
    }
    
    @Test("Safest configuration")
    func testSafestConfiguration() {
        let config = SafeFileOrganizerConfiguration.safest
        
        #expect(config.mode == .symlink)
        #expect(config.preferSymlinks == true)
        #expect(config.noDelete == true)
        #expect(config.autoResolveCollisions == true)
        #expect(config.logMovements == true)
        #expect(config.enableUndo == true)
    }
    
    // MARK: - Organization Result Tests
    
    @Test("Organization result calculations")
    func testOrganizationResultCalculations() {
        let file1 = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/file1.txt"),
            filename: "file1.txt",
            fileExtension: "txt",
            fileSize: 100,
            modificationDate: Date()
        )
        
        let file2 = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/file2.txt"),
            filename: "file2.txt",
            fileExtension: "txt",
            fileSize: 200,
            modificationDate: Date()
        )
        
        let successful = [
            SafeOrganizationOperation(
                file: file1,
                source: file1.url,
                destination: URL(fileURLWithPath: "/output/file1.txt"),
                mode: .copy,
                category: "Documents",
                confidence: 0.9,
                collision: nil
            )
        ]
        
        let failed = [
            SafeOrganizationFailure(
                file: file2,
                reason: "Test failure",
                error: nil
            )
        ]
        
        let result = SafeOrganizationResult(
            successful: successful,
            failed: failed,
            collisionsResolved: [],
            totalFiles: 2
        )
        
        #expect(result.successCount == 1)
        #expect(result.failureCount == 1)
        #expect(result.collisionCount == 0)
        #expect(result.successRate == 0.5)
    }
    
    @Test("Organization result with all successful")
    func testOrganizationResultAllSuccessful() {
        let result = SafeOrganizationResult(
            successful: [/* mock operations */],
            failed: [],
            collisionsResolved: [],
            totalFiles: 0
        )
        
        #expect(result.successRate == 0)
    }
    
    // MARK: - Error Tests
    
    @Test("Safe organizer error descriptions")
    func testSafeOrganizerErrors() {
        let deleteError = SafeOrganizerError.deleteNotAllowed
        #expect(deleteError.errorDescription?.contains("no-delete") == true)
        
        let undoError = SafeOrganizerError.undoNotEnabled
        #expect(undoError.errorDescription?.contains("Undo") == true)
        
        let collisionError = SafeOrganizerError.collisionResolutionFailed("test")
        #expect(collisionError.errorDescription?.contains("collision") == true)
        
        let invalidError = SafeOrganizerError.invalidOperation("test")
        #expect(invalidError.errorDescription?.contains("Invalid") == true)
    }
    
    // MARK: - Integration Tests
    
    @Test("Safe organizer initialization")
    func testSafeOrganizerInitialization() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let dbPath = tempDir.appendingPathComponent("test.db")
        let config = DatabaseConfiguration(
            path: dbPath.path,
            inMemory: false,
            enableWAL: true,
            enableForeignKeys: true
        )
        let database = try SortAIDatabase(configuration: config)
        let undoStack = UndoStack()
        
        let organizer = SafeFileOrganizer(
            configuration: .default,
            database: database,
            undoStack: undoStack
        )
        
        // Just verify it initializes
        let canUndo = await organizer.canUndo
        #expect(canUndo == false)
    }
    
    @Test("Undo/redo availability")
    func testUndoRedoAvailability() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let dbPath = tempDir.appendingPathComponent("test.db")
        let config = DatabaseConfiguration(
            path: dbPath.path,
            inMemory: false,
            enableWAL: true,
            enableForeignKeys: true
        )
        let database = try SortAIDatabase(configuration: config)
        let undoStack = UndoStack()
        
        let organizer = SafeFileOrganizer(
            configuration: .default,
            database: database,
            undoStack: undoStack
        )
        
        // Initially no undo/redo available
        let canUndo = await organizer.canUndo
        let canRedo = await organizer.canRedo
        let undoCount = await organizer.undoCount
        
        #expect(canUndo == false)
        #expect(canRedo == false)
        #expect(undoCount == 0)
    }
    
    @Test("Undo not enabled error")
    func testUndoNotEnabledError() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let dbPath = tempDir.appendingPathComponent("test.db")
        let dbConfig = DatabaseConfiguration(
            path: dbPath.path,
            inMemory: false,
            enableWAL: true,
            enableForeignKeys: true
        )
        let database = try SortAIDatabase(configuration: dbConfig)
        let undoStack = UndoStack()
        
        let config = SafeFileOrganizerConfiguration(
            mode: .copy,
            preferSymlinks: false,
            noDelete: true,
            autoResolveCollisions: true,
            collisionStyle: .macOS,
            logMovements: true,
            enableUndo: false  // Undo disabled
        )
        
        let organizer = SafeFileOrganizer(
            configuration: config,
            database: database,
            undoStack: undoStack
        )
        
        // Attempting undo should throw error
        do {
            _ = try await organizer.undoLastOperation()
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected error
            #expect(error is SafeOrganizerError)
        }
    }
}

// MARK: - Collision Resolution Tests

@Suite("Collision Resolution Tests")
struct CollisionResolutionTests {
    
    @Test("Collision resolution structure")
    func testCollisionResolutionStructure() {
        let original = URL(fileURLWithPath: "/test/file.txt")
        let resolved = URL(fileURLWithPath: "/test/file (1).txt")
        
        let collision = CollisionResolution(
            originalPath: original,
            resolvedPath: resolved,
            strategy: "Auto-rename"
        )
        
        #expect(collision.originalPath == original)
        #expect(collision.resolvedPath == resolved)
        #expect(collision.strategy == "Auto-rename")
    }
}

// MARK: - Safe Organization Operation Tests

@Suite("Safe Organization Operation Tests")
struct SafeOrganizationOperationTests {
    
    @Test("Safe organization operation structure")
    func testSafeOrganizationOperation() {
        let file = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/file.txt"),
            filename: "file.txt",
            fileExtension: "txt",
            fileSize: 100,
            modificationDate: Date()
        )
        
        let operation = SafeOrganizationOperation(
            file: file,
            source: file.url,
            destination: URL(fileURLWithPath: "/output/file.txt"),
            mode: .copy,
            category: "Documents",
            confidence: 0.85,
            collision: nil
        )
        
        #expect(operation.file.id == file.id)
        #expect(operation.source == file.url)
        #expect(operation.mode == .copy)
        #expect(operation.category == "Documents")
        #expect(operation.confidence == 0.85)
        #expect(operation.collision == nil)
    }
    
    @Test("Safe organization operation with collision")
    func testSafeOrganizationOperationWithCollision() {
        let file = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/file.txt"),
            filename: "file.txt",
            fileExtension: "txt",
            fileSize: 100,
            modificationDate: Date()
        )
        
        let collision = CollisionResolution(
            originalPath: URL(fileURLWithPath: "/output/file.txt"),
            resolvedPath: URL(fileURLWithPath: "/output/file (1).txt"),
            strategy: "Auto-rename"
        )
        
        let operation = SafeOrganizationOperation(
            file: file,
            source: file.url,
            destination: URL(fileURLWithPath: "/output/file (1).txt"),
            mode: .copy,
            category: "Documents",
            confidence: 0.85,
            collision: collision
        )
        
        #expect(operation.collision != nil)
        #expect(operation.collision?.strategy == "Auto-rename")
    }
}

