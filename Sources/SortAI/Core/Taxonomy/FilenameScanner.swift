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
        
        // MARK: - Hierarchy Settings
        
        /// Whether to respect folder hierarchy (treat sub-folders as units)
        let respectHierarchy: Bool
        
        /// Minimum depth to treat as folder unit (1 = immediate children of scan root)
        let minDepthForFolder: Int
        
        /// Minimum files in a folder to treat it as a unit (folders with fewer files become loose)
        let minFilesForFolder: Int
        
        /// Full initializer with all parameters
        init(
            maxFiles: Int,
            includeHidden: Bool,
            excludedExtensions: Set<String>,
            excludedDirectories: Set<String>,
            minFileSize: Int64,
            respectHierarchy: Bool = true,
            minDepthForFolder: Int = 1,
            minFilesForFolder: Int = 1
        ) {
            self.maxFiles = maxFiles
            self.includeHidden = includeHidden
            self.excludedExtensions = excludedExtensions
            self.excludedDirectories = excludedDirectories
            self.minFileSize = minFileSize
            self.respectHierarchy = respectHierarchy
            self.minDepthForFolder = minDepthForFolder
            self.minFilesForFolder = minFilesForFolder
        }
        
        static let `default` = Configuration(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".localized", ".gitignore", ".gitattributes"],
            excludedDirectories: ["node_modules", ".git", ".svn", "__pycache__", ".cache", "build", "dist"],
            minFileSize: 100,  // Skip files smaller than 100 bytes
            respectHierarchy: true,
            minDepthForFolder: 1,
            minFilesForFolder: 1
        )
        
        /// Configuration for flat scanning (legacy behavior)
        static let flat = Configuration(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [".ds_store", ".localized", ".gitignore", ".gitattributes"],
            excludedDirectories: ["node_modules", ".git", ".svn", "__pycache__", ".cache", "build", "dist"],
            minFileSize: 100,
            respectHierarchy: false,
            minDepthForFolder: 1,
            minFilesForFolder: 1
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
    
    // MARK: - Hierarchy-Aware Scanning
    
    /// Scan a folder with hierarchy awareness
    /// - Sub-folders become folder units (moved as complete units)
    /// - Loose files at root level are analyzed individually
    /// - Parameter folderURL: The folder to scan
    /// - Returns: HierarchyScanResult with folders and loose files separated
    func scanWithHierarchy(folder folderURL: URL) async throws -> HierarchyScanResult {
        NSLog("🔍 [Scanner] Starting hierarchy-aware scan of: \(folderURL.path)")
        NSLog("🔍 [Scanner] Config: respectHierarchy=\(config.respectHierarchy), minDepth=\(config.minDepthForFolder), minFiles=\(config.minFilesForFolder)")
        
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
        
        let startTime = Date()
        var folders: [ScannedFolder] = []
        var looseFiles: [TaxonomyScannedFile] = []
        var skippedCount = 0
        
        // Get immediate children of the scan root
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: config.includeHidden ? [] : [.skipsHiddenFiles]
            )
        } catch {
            throw ScanError.enumerationFailed
        }
        
        NSLog("🔍 [Scanner] Found \(contents.count) immediate children")
        
        // Process each immediate child
        for itemURL in contents {
            // Check excluded directories
            let itemName = itemURL.lastPathComponent
            if config.excludedDirectories.contains(itemName) {
                skippedCount += 1
                continue
            }
            
            let resourceValues = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
            
            // Skip hidden items if configured
            if !config.includeHidden && (resourceValues?.isHidden == true) {
                skippedCount += 1
                continue
            }
            
            if resourceValues?.isDirectory == true {
                // This is a sub-folder - scan it as a unit
                let scannedFolder = try await scanFolderAsUnit(
                    url: itemURL,
                    relativeTo: folderURL,
                    depth: 1
                )
                
                // Only treat as folder unit if it meets minimum file threshold
                if scannedFolder.fileCount >= config.minFilesForFolder {
                    folders.append(scannedFolder)
                    NSLog("📁 [Scanner] Folder unit: '\(scannedFolder.folderName)' (\(scannedFolder.fileCount) files)")
                } else if scannedFolder.fileCount > 0 {
                    // Flatten: add contained files as loose files
                    looseFiles.append(contentsOf: scannedFolder.containedFiles)
                    NSLog("📄 [Scanner] Flattened folder: '\(scannedFolder.folderName)' (\(scannedFolder.fileCount) files below threshold)")
                }
                // Empty folders are silently skipped
                
            } else {
                // This is a loose file at root level
                if let file = try? scanSingleFile(url: itemURL, relativeTo: folderURL) {
                    looseFiles.append(file)
                } else {
                    skippedCount += 1
                }
            }
            
            // Check limits
            let totalFiles = folders.reduce(0) { $0 + $1.fileCount } + looseFiles.count
            if totalFiles >= config.maxFiles {
                NSLog("⚠️ [Scanner] Reached file limit: \(config.maxFiles)")
                break
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let totalFiles = folders.reduce(0) { $0 + $1.fileCount } + looseFiles.count
        
        NSLog("✅ [Scanner] Hierarchy scan complete in %.2fs", duration)
        NSLog("✅ [Scanner] Result: \(folders.count) folders, \(looseFiles.count) loose files, \(totalFiles) total files")
        
        return HierarchyScanResult(
            sourceFolder: folderURL,
            sourceFolderName: folderURL.lastPathComponent,
            folders: folders,
            looseFiles: looseFiles,
            skippedCount: skippedCount,
            scanDuration: duration,
            reachedLimit: totalFiles >= config.maxFiles
        )
    }
    
    /// Scan a folder and all its contents as a unit
    /// - Parameters:
    ///   - url: The folder URL
    ///   - rootURL: The scan root for computing relative paths
    ///   - depth: Current depth level
    /// - Returns: ScannedFolder containing all files recursively
    private func scanFolderAsUnit(
        url: URL,
        relativeTo rootURL: URL,
        depth: Int
    ) async throws -> ScannedFolder {
        var containedFiles: [TaxonomyScannedFile] = []
        var latestModification: Date?
        
        // Recursively enumerate all files in this folder
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isHiddenKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentTypeKey
        ]
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: config.includeHidden ? [] : [.skipsHiddenFiles]
        ) else {
            throw ScanError.enumerationFailed
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            // Skip excluded directories
            if config.excludedDirectories.contains(fileURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            
            guard let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }
            
            // Skip directories (we're flattening into this folder)
            if resourceValues.isDirectory == true {
                continue
            }
            
            // Skip non-regular files
            guard resourceValues.isRegularFile == true else {
                continue
            }
            
            // Check extension exclusions
            let ext = fileURL.pathExtension.lowercased()
            let filename = fileURL.lastPathComponent.lowercased()
            if config.excludedExtensions.contains(".\(ext)") ||
               config.excludedExtensions.contains(filename) {
                continue
            }
            
            // Check minimum file size
            if let size = resourceValues.fileSize, size < config.minFileSize {
                continue
            }
            
            // Track latest modification
            if let modDate = resourceValues.contentModificationDate {
                if latestModification == nil || modDate > latestModification! {
                    latestModification = modDate
                }
            }
            
            // Create scanned file record
            let scannedFile = TaxonomyScannedFile(
                url: fileURL,
                filename: fileURL.lastPathComponent,
                fileExtension: fileURL.pathExtension,
                relativePath: fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: ""),
                fileSize: Int64(resourceValues.fileSize ?? 0),
                createdAt: resourceValues.creationDate,
                modifiedAt: resourceValues.contentModificationDate,
                contentType: resourceValues.contentType
            )
            
            containedFiles.append(scannedFile)
            
            // Safety limit per folder
            if containedFiles.count >= config.maxFiles {
                break
            }
        }
        
        let totalSize = containedFiles.reduce(0) { $0 + $1.fileSize }
        let relativePath = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        
        return ScannedFolder(
            url: url,
            folderName: url.lastPathComponent,
            relativePath: relativePath,
            depth: depth,
            containedFiles: containedFiles,
            totalSize: totalSize,
            modifiedAt: latestModification
        )
    }
    
    /// Scan a single file and return its metadata
    private func scanSingleFile(url: URL, relativeTo rootURL: URL) throws -> TaxonomyScannedFile? {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentTypeKey
        ]
        
        let resourceValues = try url.resourceValues(forKeys: resourceKeys)
        
        // Must be a regular file
        guard resourceValues.isRegularFile == true else {
            return nil
        }
        
        // Check extension exclusions
        let ext = url.pathExtension.lowercased()
        let filename = url.lastPathComponent.lowercased()
        if config.excludedExtensions.contains(".\(ext)") ||
           config.excludedExtensions.contains(filename) {
            return nil
        }
        
        // Check minimum file size
        if let size = resourceValues.fileSize, size < config.minFileSize {
            return nil
        }
        
        return TaxonomyScannedFile(
            url: url,
            filename: url.lastPathComponent,
            fileExtension: url.pathExtension,
            relativePath: url.path.replacingOccurrences(of: rootURL.path + "/", with: ""),
            fileSize: Int64(resourceValues.fileSize ?? 0),
            createdAt: resourceValues.creationDate,
            modifiedAt: resourceValues.contentModificationDate,
            contentType: resourceValues.contentType
        )
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

// MARK: - Hierarchy-Aware Types

/// A folder that will be moved as a complete unit during organization
/// Internal structure is preserved - all contained files stay together
struct ScannedFolder: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let folderName: String
    let relativePath: String          // Path relative to scan root
    let depth: Int                     // How deep in folder tree (1 = immediate child of root)
    let containedFiles: [TaxonomyScannedFile]
    let totalSize: Int64
    let modifiedAt: Date?
    
    /// Number of files in this folder (including nested)
    var fileCount: Int { containedFiles.count }
    
    /// Formatted total size for display
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    /// Dominant file types in this folder (for categorization hints)
    var dominantFileTypes: [UTType] {
        let types = containedFiles.compactMap { $0.contentType }
        let grouped = Dictionary(grouping: types) { $0 }
        return grouped.sorted { $0.value.count > $1.value.count }
            .prefix(3)
            .map { $0.key }
    }
    
    /// Build context string for LLM categorization
    var suggestedContext: String {
        let fileTypeGroups = Dictionary(grouping: containedFiles) { file -> String in
            if file.isImage { return "image" }
            if file.isVideo { return "video" }
            if file.isAudio { return "audio" }
            if file.isDocument { return "document" }
            return "other"
        }
        
        let summary = fileTypeGroups.map { "\($0.value.count) \($0.key)(s)" }
            .joined(separator: ", ")
        
        return "Folder '\(folderName)' contains \(summary)"
    }
    
    init(
        id: UUID = UUID(),
        url: URL,
        folderName: String,
        relativePath: String,
        depth: Int,
        containedFiles: [TaxonomyScannedFile],
        totalSize: Int64,
        modifiedAt: Date?
    ) {
        self.id = id
        self.url = url
        self.folderName = folderName
        self.relativePath = relativePath
        self.depth = depth
        self.containedFiles = containedFiles
        self.totalSize = totalSize
        self.modifiedAt = modifiedAt
    }
}

/// Unified type representing either a folder unit or an individual file
/// Used for displaying and processing scan results in the UI
enum ScanUnit: Identifiable, Sendable {
    case folder(ScannedFolder)        // Folder moves as unit
    case file(TaxonomyScannedFile)    // Individual file moves separately
    
    var id: UUID {
        switch self {
        case .folder(let f): return f.id
        case .file(let f): return f.id
        }
    }
    
    var displayName: String {
        switch self {
        case .folder(let f): return f.folderName
        case .file(let f): return f.filename
        }
    }
    
    var url: URL {
        switch self {
        case .folder(let f): return f.url
        case .file(let f): return f.url
        }
    }
    
    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
    
    var totalSize: Int64 {
        switch self {
        case .folder(let f): return f.totalSize
        case .file(let f): return f.fileSize
        }
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

/// Result of hierarchy-aware scanning
/// Separates sub-folders (as units) from loose files (analyzed individually)
struct HierarchyScanResult: Sendable {
    let sourceFolder: URL
    let sourceFolderName: String
    let folders: [ScannedFolder]           // Sub-folders to move as units
    let looseFiles: [TaxonomyScannedFile]  // Files not in sub-folders
    let skippedCount: Int
    let scanDuration: TimeInterval
    let reachedLimit: Bool
    
    /// Total items (folders + loose files)
    var totalItems: Int { folders.count + looseFiles.count }
    
    /// Total size of all items
    var totalSize: Int64 {
        let folderSize = folders.reduce(0) { $0 + $1.totalSize }
        let fileSize = looseFiles.reduce(0) { $0 + $1.fileSize }
        return folderSize + fileSize
    }
    
    /// Formatted total size
    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    /// Total file count (including files inside folders)
    var totalFileCount: Int {
        let folderFiles = folders.reduce(0) { $0 + $1.fileCount }
        return folderFiles + looseFiles.count
    }
    
    /// Convert to unified ScanUnit array for UI display
    var allUnits: [ScanUnit] {
        let folderUnits = folders.map { ScanUnit.folder($0) }
        let fileUnits = looseFiles.map { ScanUnit.file($0) }
        return folderUnits + fileUnits
    }
    
    /// Convert to legacy TaxonomyScanResult (flattens folders)
    /// Useful for compatibility with existing code paths
    func toLegacyScanResult() -> TaxonomyScanResult {
        let allFiles = folders.flatMap { $0.containedFiles } + looseFiles
        return TaxonomyScanResult(
            folderURL: sourceFolder,
            folderName: sourceFolderName,
            files: allFiles,
            directoryCount: folders.count,
            skippedCount: skippedCount,
            scanDuration: scanDuration,
            reachedLimit: reachedLimit
        )
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

