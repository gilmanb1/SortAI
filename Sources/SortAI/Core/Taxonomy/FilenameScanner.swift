// MARK: - Filename Scanner
// Recursively collects filenames from a folder for taxonomy inference

import Foundation
import UniformTypeIdentifiers

// MARK: - Filename Scanner

/// Scans folders recursively to collect filenames for taxonomy inference
/// Does NOT read file contents - only collects metadata needed for filename-based categorization
actor FilenameScanner {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// Maximum number of files to scan
        let maxFiles: Int
        
        /// Whether to include hidden files
        let includeHidden: Bool
        
        /// File extensions to exclude (e.g., [".ds_store", ".gitignore"])
        let excludedExtensions: Set<String>
        
        /// Directory names to skip (e.g., ["node_modules", ".git"])
        let excludedDirectories: Set<String>
        
        /// Minimum file size (bytes) - skip tiny files
        let minFileSize: Int64
        
        static let `default` = Configuration(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".localized", ".gitignore", ".gitattributes"],
            excludedDirectories: ["node_modules", ".git", ".svn", "__pycache__", ".cache", "build", "dist"],
            minFileSize: 100  // Skip files smaller than 100 bytes
        )
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .default) {
        self.config = configuration
    }
    
    // MARK: - Scanning
    
    /// Scan a folder and return collected file info
    /// - Parameter folderURL: The folder to scan
    /// - Returns: Scan result with file info and statistics
    func scan(folder folderURL: URL) async throws -> TaxonomyScanResult {
        NSLog("🔍 [Scanner] Starting scan of folder: \(folderURL.path)")
        NSLog("🔍 [Scanner] Config: maxFiles=\(config.maxFiles), includeHidden=\(config.includeHidden)")
        
        guard fileManager.fileExists(atPath: folderURL.path) else {
            NSLog("❌ [Scanner] Folder not found: \(folderURL.path)")
            throw ScanError.folderNotFound(folderURL.path)
        }
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            NSLog("❌ [Scanner] Not a directory: \(folderURL.path)")
            throw ScanError.notADirectory(folderURL.path)
        }
        
        var files: [TaxonomyScannedFile] = []
        var skippedCount = 0
        var directoryCount = 0
        let startTime = Date()
        
        // Use efficient file enumeration
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentTypeKey,
            .localizedNameKey
        ]
        
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: config.includeHidden ? [] : [.skipsHiddenFiles]
        ) else {
            throw ScanError.enumerationFailed
        }
        
        // Collect URLs synchronously first (enumerator not async-compatible)
        NSLog("🔍 [Scanner] Enumerating files...")
        var allURLs: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            allURLs.append(fileURL)
            if allURLs.count >= config.maxFiles * 2 { break }  // Safety limit
        }
        
        let enumerationDuration = Date().timeIntervalSince(startTime)
        NSLog("🔍 [Scanner] Enumerated \(allURLs.count) items in %.2fs", enumerationDuration)
        
        for fileURL in allURLs {
            // Check file limit
            if files.count >= config.maxFiles {
                break
            }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
                
                // Skip directories (but count them)
                if resourceValues.isDirectory == true {
                    directoryCount += 1
                    continue
                }
                
                // Skip non-regular files
                guard resourceValues.isRegularFile == true else {
                    skippedCount += 1
                    continue
                }
                
                // Check extension exclusions
                let ext = fileURL.pathExtension.lowercased()
                let filename = fileURL.lastPathComponent.lowercased()
                if config.excludedExtensions.contains(".\(ext)") ||
                   config.excludedExtensions.contains(filename) {
                    skippedCount += 1
                    continue
                }
                
                // Check minimum file size
                if let size = resourceValues.fileSize, size < config.minFileSize {
                    skippedCount += 1
                    continue
                }
                
                // Create scanned file record
                let scannedFile = TaxonomyScannedFile(
                    url: fileURL,
                    filename: fileURL.lastPathComponent,
                    fileExtension: fileURL.pathExtension,
                    relativePath: fileURL.path.replacingOccurrences(of: folderURL.path + "/", with: ""),
                    fileSize: Int64(resourceValues.fileSize ?? 0),
                    createdAt: resourceValues.creationDate,
                    modifiedAt: resourceValues.contentModificationDate,
                    contentType: resourceValues.contentType
                )
                
                files.append(scannedFile)
                
            } catch {
                skippedCount += 1
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        NSLog("✅ [Scanner] Scan complete in %.2fs", duration)
        NSLog("✅ [Scanner] Files: \(files.count), Directories: \(directoryCount), Skipped: \(skippedCount)")
        
        return TaxonomyScanResult(
            folderURL: folderURL,
            folderName: folderURL.lastPathComponent,
            files: files,
            directoryCount: directoryCount,
            skippedCount: skippedCount,
            scanDuration: duration,
            reachedLimit: files.count >= config.maxFiles
        )
    }
    
    /// Extract just filenames for LLM processing (optimized for batch inference)
    func extractFilenames(from scanResult: TaxonomyScanResult) -> [String] {
        scanResult.files.map { $0.filename }
    }
    
    /// Group files by extension for analysis
    func groupByExtension(files: [TaxonomyScannedFile]) -> [String: [TaxonomyScannedFile]] {
        Dictionary(grouping: files) { $0.fileExtension.lowercased() }
    }
    
    /// Group files by inferred type (document, image, video, audio, other)
    func groupByType(files: [TaxonomyScannedFile]) -> [FileTypeGroup: [TaxonomyScannedFile]] {
        Dictionary(grouping: files) { file -> FileTypeGroup in
            guard let contentType = file.contentType else {
                return inferTypeFromExtension(file.fileExtension)
            }
            
            if contentType.conforms(to: .image) { return .image }
            if contentType.conforms(to: .video) || contentType.conforms(to: .movie) { return .video }
            if contentType.conforms(to: .audio) { return .audio }
            if contentType.conforms(to: .pdf) || contentType.conforms(to: .text) ||
               contentType.conforms(to: .presentation) || contentType.conforms(to: .spreadsheet) {
                return .document
            }
            if contentType.conforms(to: .archive) { return .archive }
            if contentType.conforms(to: .executable) || contentType.conforms(to: .application) {
                return .application
            }
            
            return .other
        }
    }
    
    private func inferTypeFromExtension(_ ext: String) -> FileTypeGroup {
        let lower = ext.lowercased()
        
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic", "svg"]
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v"]
        let audioExtensions = ["mp3", "wav", "aac", "flac", "m4a", "ogg", "wma"]
        let documentExtensions = ["pdf", "doc", "docx", "txt", "rtf", "odt", "xls", "xlsx", "ppt", "pptx"]
        let archiveExtensions = ["zip", "rar", "7z", "tar", "gz", "bz2"]
        let appExtensions = ["app", "exe", "dmg", "pkg"]
        
        if imageExtensions.contains(lower) { return .image }
        if videoExtensions.contains(lower) { return .video }
        if audioExtensions.contains(lower) { return .audio }
        if documentExtensions.contains(lower) { return .document }
        if archiveExtensions.contains(lower) { return .archive }
        if appExtensions.contains(lower) { return .application }
        
        return .other
    }
}

// MARK: - Supporting Types

/// Information about a scanned file for taxonomy inference
struct TaxonomyScannedFile: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let filename: String
    let fileExtension: String
    let relativePath: String
    let fileSize: Int64
    let createdAt: Date?
    let modifiedAt: Date?
    let contentType: UTType?
    
    /// Full initializer
    init(
        url: URL,
        filename: String,
        fileExtension: String,
        relativePath: String,
        fileSize: Int64,
        createdAt: Date?,
        modifiedAt: Date?,
        contentType: UTType?
    ) {
        self.id = UUID()
        self.url = url
        self.filename = filename
        self.fileExtension = fileExtension
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.contentType = contentType
    }
    
    /// Simplified initializer for tests and simple usage
    init(
        url: URL,
        filename: String,
        fileExtension: String,
        fileSize: Int64,
        modificationDate: Date
    ) {
        self.id = UUID()
        self.url = url
        self.filename = filename
        self.fileExtension = fileExtension
        self.relativePath = filename
        self.fileSize = fileSize
        self.createdAt = modificationDate
        self.modifiedAt = modificationDate
        self.contentType = UTType(filenameExtension: fileExtension)
    }
    
    /// File size formatted for display
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    /// Name without extension
    var baseName: String {
        if fileExtension.isEmpty {
            return filename
        }
        return String(filename.dropLast(fileExtension.count + 1))
    }
    
    // MARK: - File Type Helpers
    
    /// Whether this is an image file
    var isImage: Bool {
        if let type = contentType {
            return type.conforms(to: .image)
        }
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic", "svg"]
        return imageExtensions.contains(fileExtension.lowercased())
    }
    
    /// Whether this is a video file
    var isVideo: Bool {
        if let type = contentType {
            return type.conforms(to: .video) || type.conforms(to: .movie)
        }
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v"]
        return videoExtensions.contains(fileExtension.lowercased())
    }
    
    /// Whether this is an audio file
    var isAudio: Bool {
        if let type = contentType {
            return type.conforms(to: .audio)
        }
        let audioExtensions = ["mp3", "wav", "aac", "flac", "m4a", "ogg", "wma"]
        return audioExtensions.contains(fileExtension.lowercased())
    }
    
    /// Whether this is a document file
    var isDocument: Bool {
        if let type = contentType {
            return type.conforms(to: .pdf) || type.conforms(to: .text) ||
                   type.conforms(to: .presentation) || type.conforms(to: .spreadsheet)
        }
        let docExtensions = ["pdf", "doc", "docx", "txt", "rtf", "odt", "xls", "xlsx", "ppt", "pptx"]
        return docExtensions.contains(fileExtension.lowercased())
    }
}

/// Result of scanning a folder for taxonomy inference
struct TaxonomyScanResult: Sendable {
    let folderURL: URL
    let folderName: String
    let files: [TaxonomyScannedFile]
    let directoryCount: Int
    let skippedCount: Int
    let scanDuration: TimeInterval
    let reachedLimit: Bool
    
    /// Total file count
    var fileCount: Int { files.count }
    
    /// Total size of all files
    var totalSize: Int64 {
        files.reduce(0) { $0 + $1.fileSize }
    }
    
    /// Formatted total size
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    /// Simplified initializer for tests
    init(
        files: [TaxonomyScannedFile],
        totalSize: Int64,
        directoryCount: Int,
        scanDuration: TimeInterval,
        reachedLimit: Bool
    ) {
        self.folderURL = URL(fileURLWithPath: "/test")
        self.folderName = "test"
        self.files = files
        self.directoryCount = directoryCount
        self.skippedCount = 0
        self.scanDuration = scanDuration
        self.reachedLimit = reachedLimit
    }
    
    /// Full initializer
    init(
        folderURL: URL,
        folderName: String,
        files: [TaxonomyScannedFile],
        directoryCount: Int,
        skippedCount: Int,
        scanDuration: TimeInterval,
        reachedLimit: Bool
    ) {
        self.folderURL = folderURL
        self.folderName = folderName
        self.files = files
        self.directoryCount = directoryCount
        self.skippedCount = skippedCount
        self.scanDuration = scanDuration
        self.reachedLimit = reachedLimit
    }
}

/// File type groups for organization
enum FileTypeGroup: String, Sendable, CaseIterable {
    case document
    case image
    case video
    case audio
    case archive
    case application
    case other
    
    var displayName: String {
        switch self {
        case .document: return "Documents"
        case .image: return "Images"
        case .video: return "Videos"
        case .audio: return "Audio"
        case .archive: return "Archives"
        case .application: return "Applications"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .document: return "doc.text"
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        case .archive: return "archivebox"
        case .application: return "app"
        case .other: return "questionmark.folder"
        }
    }
}

/// Scanner errors
enum ScanError: LocalizedError {
    case folderNotFound(String)
    case notADirectory(String)
    case enumerationFailed
    case accessDenied(String)
    
    var errorDescription: String? {
        switch self {
        case .folderNotFound(let path):
            return "Folder not found: \(path)"
        case .notADirectory(let path):
            return "Not a directory: \(path)"
        case .enumerationFailed:
            return "Failed to enumerate folder contents"
        case .accessDenied(let path):
            return "Access denied to: \(path)"
        }
    }
}

