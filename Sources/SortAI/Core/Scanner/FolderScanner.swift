// MARK: - Folder Scanner
// Recursively scans folders and collects files for processing

import Foundation
import UniformTypeIdentifiers

// MARK: - Scan Result

struct ScanResult: Sendable {
    let sourceFolder: URL
    let files: [ScannedFile]
    let skippedCount: Int
    let totalSize: Int64
    
    var fileCount: Int { files.count }
}

struct ScannedFile: Sendable, Identifiable {
    let id: UUID
    let url: URL
    let relativePath: String  // Path relative to source folder
    let size: Int64
    let modificationDate: Date
    let utType: UTType?
    
    init(url: URL, relativeTo sourceFolder: URL) {
        self.id = UUID()
        self.url = url
        self.relativePath = url.path.replacingOccurrences(of: sourceFolder.path + "/", with: "")
        
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.size = attrs?[.size] as? Int64 ?? 0
        self.modificationDate = attrs?[.modificationDate] as? Date ?? Date()
        self.utType = UTType(filenameExtension: url.pathExtension)
    }
}

// MARK: - Folder Scanner Actor

actor FolderScanner {
    
    // Supported file types for processing
    private let supportedExtensions: Set<String> = [
        // Documents
        "pdf", "txt", "md", "rtf", "doc", "docx", "pages",
        "html", "htm", "xml", "json", "yaml", "yml",
        // Videos
        "mp4", "mov", "m4v", "avi", "mkv", "webm",
        // Images
        "jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "bmp",
        // Audio
        "mp3", "m4a", "wav", "aiff", "flac", "aac"
    ]
    
    // Folders to skip during scanning
    private let skipFolders: Set<String> = [
        ".git", ".svn", ".hg",
        "node_modules", ".build", "build",
        "__pycache__", ".pytest_cache",
        ".DS_Store", ".Spotlight-V100", ".Trashes",
        "Library", ".Trash"
    ]
    
    // MARK: - Scanning
    
    /// Scans a folder recursively and returns all supported files
    func scan(folder: URL) async throws -> ScanResult {
        // Run the synchronous file enumeration on a background thread
        try await Task.detached(priority: .userInitiated) {
            try self.scanSync(folder: folder)
        }.value
    }
    
    /// Synchronous scan implementation
    nonisolated private func scanSync(folder: URL) throws -> ScanResult {
        var files: [ScannedFile] = []
        var skippedCount = 0
        var totalSize: Int64 = 0
        
        let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) { url, error in
            // Skip errors and continue
            print("Scan warning: \(error.localizedDescription) at \(url.path)")
            return true
        }
        
        guard let enumerator = enumerator else {
            throw ScannerError.cannotAccessFolder(folder)
        }
        
        for case let fileURL as URL in enumerator {
            // Skip directories in skip list
            if skipFolders.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            
            // Check if it's a regular file
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }
            
            // Check if file type is supported
            let ext = fileURL.pathExtension.lowercased()
            if supportedExtensions.contains(ext) {
                let scannedFile = ScannedFile(url: fileURL, relativeTo: folder)
                files.append(scannedFile)
                totalSize += scannedFile.size
            } else {
                skippedCount += 1
            }
        }
        
        return ScanResult(
            sourceFolder: folder,
            files: files,
            skippedCount: skippedCount,
            totalSize: totalSize
        )
    }
    
    /// Scans multiple folders
    func scan(folders: [URL]) async throws -> [ScanResult] {
        var results: [ScanResult] = []
        
        for folder in folders {
            let result = try await scan(folder: folder)
            results.append(result)
        }
        
        return results
    }
}

// MARK: - Scanner Errors

enum ScannerError: LocalizedError {
    case cannotAccessFolder(URL)
    case notADirectory(URL)
    
    var errorDescription: String? {
        switch self {
        case .cannotAccessFolder(let url):
            return "Cannot access folder: \(url.lastPathComponent)"
        case .notADirectory(let url):
            return "Not a directory: \(url.lastPathComponent)"
        }
    }
}

