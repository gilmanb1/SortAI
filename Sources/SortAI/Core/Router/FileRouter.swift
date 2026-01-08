// MARK: - File Router
// Routes files to appropriate inspection strategies based on UTType

import Foundation
import UniformTypeIdentifiers

// MARK: - Router Errors
enum RouterError: LocalizedError {
    case unsupportedFileType(String)
    case fileNotFound(URL)
    case accessDenied(URL)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let ext):
            return "Unsupported file type: \(ext)"
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .accessDenied(let url):
            return "Access denied: \(url.lastPathComponent)"
        }
    }
}

// MARK: - Inspection Strategy
enum InspectionStrategy: Sendable {
    case document(DocumentType)
    case video
    case image
    case audio
    
    enum DocumentType: Sendable {
        case pdf
        case plainText
        case richText
        case markdown
        case word
        case excel       // .xls, .xlsx
        case powerpoint  // .ppt, .pptx
        case sourceCode  // .swift, .py, .js, etc.
    }
}

// MARK: - File Router Actor
/// Thread-safe router that determines the appropriate inspection strategy
/// for incoming files based on their UTType.
actor FileRouter: FileRouting {
    // MARK: - Supported Types
    private static let documentTypes: Set<UTType> = [
        .pdf,
        .plainText,
        .rtf,
        .rtfd,
        .html,
        .xml,
        .json,
        .yaml
    ]
    
    private static let videoTypes: Set<UTType> = [
        .mpeg4Movie,
        .quickTimeMovie,
        .movie,
        .avi,
        .mpeg,
        .mpeg2Video
    ]
    
    private static let imageTypes: Set<UTType> = [
        .jpeg,
        .png,
        .gif,
        .heic,
        .webP,
        .tiff,
        .bmp
    ]
    
    private static let audioTypes: Set<UTType> = [
        .mp3,
        .wav,
        .aiff,
        .mpeg4Audio
    ]
    
    // Extension mappings for fallback
    private static let extensionToStrategy: [String: InspectionStrategy] = [
        // Documents
        "pdf": .document(.pdf),
        "txt": .document(.plainText),
        "text": .document(.plainText),
        "md": .document(.markdown),
        "markdown": .document(.markdown),
        "rtf": .document(.richText),
        "rtfd": .document(.richText),
        "doc": .document(.word),
        "docx": .document(.word),
        
        // Excel
        "xls": .document(.excel),
        "xlsx": .document(.excel),
        "csv": .document(.excel),
        "numbers": .document(.excel),
        
        // PowerPoint
        "ppt": .document(.powerpoint),
        "pptx": .document(.powerpoint),
        "key": .document(.powerpoint),  // Keynote
        
        // Source Code
        "swift": .document(.sourceCode),
        "py": .document(.sourceCode),
        "js": .document(.sourceCode),
        "ts": .document(.sourceCode),
        "java": .document(.sourceCode),
        "c": .document(.sourceCode),
        "cpp": .document(.sourceCode),
        "h": .document(.sourceCode),
        "hpp": .document(.sourceCode),
        "cs": .document(.sourceCode),
        "go": .document(.sourceCode),
        "rs": .document(.sourceCode),
        "rb": .document(.sourceCode),
        "php": .document(.sourceCode),
        "html": .document(.sourceCode),
        "css": .document(.sourceCode),
        "json": .document(.sourceCode),
        "xml": .document(.sourceCode),
        "yaml": .document(.sourceCode),
        "yml": .document(.sourceCode),
        "sh": .document(.sourceCode),
        "bash": .document(.sourceCode),
        "sql": .document(.sourceCode),
        
        // Videos
        "mp4": .video,
        "m4v": .video,
        "mov": .video,
        "avi": .video,
        "mkv": .video,
        "webm": .video,
        
        // Images
        "jpg": .image,
        "jpeg": .image,
        "png": .image,
        "gif": .image,
        "heic": .image,
        "webp": .image,
        "tiff": .image,
        "bmp": .image,
        
        // Audio
        "mp3": .audio,
        "m4a": .audio,
        "wav": .audio,
        "aiff": .audio,
        "flac": .audio
    ]
    
    // MARK: - Routing
    
    /// Determines the inspection strategy for a given file URL
    /// - Parameter url: The file URL to route
    /// - Returns: The appropriate inspection strategy
    /// - Throws: RouterError if file type is not supported
    func route(url: URL) throws -> InspectionStrategy {
        // Verify file exists and is accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw RouterError.fileNotFound(url)
        }
        
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw RouterError.accessDenied(url)
        }
        
        // Try UTType detection first (most reliable)
        if let utType = UTType(filenameExtension: url.pathExtension) {
            if let strategy = strategyFromUTType(utType) {
                return strategy
            }
        }
        
        // Fallback to extension-based detection
        let ext = url.pathExtension.lowercased()
        if let strategy = Self.extensionToStrategy[ext] {
            return strategy
        }
        
        // Try content-based detection as last resort
        if let strategy = try? detectFromContent(url: url) {
            return strategy
        }
        
        throw RouterError.unsupportedFileType(url.pathExtension)
    }
    
    /// Returns the MediaKind for a URL
    func mediaKind(for url: URL) -> MediaKind {
        guard let strategy = try? route(url: url) else {
            return .unknown
        }
        
        switch strategy {
        case .document: return .document
        case .video: return .video
        case .image: return .image
        case .audio: return .audio
        }
    }
    
    // MARK: - Private Helpers
    
    private func strategyFromUTType(_ utType: UTType) -> InspectionStrategy? {
        // Check document types
        if utType.conforms(to: .pdf) {
            return .document(.pdf)
        }
        if utType.conforms(to: .plainText) {
            return .document(.plainText)
        }
        if utType.conforms(to: .rtf) || utType.conforms(to: .rtfd) {
            return .document(.richText)
        }
        
        // Check video types
        for videoType in Self.videoTypes {
            if utType.conforms(to: videoType) {
                return .video
            }
        }
        
        // Check image types
        for imageType in Self.imageTypes {
            if utType.conforms(to: imageType) {
                return .image
            }
        }
        
        // Check audio types
        for audioType in Self.audioTypes {
            if utType.conforms(to: audioType) {
                return .audio
            }
        }
        
        return nil
    }
    
    private func detectFromContent(url: URL) throws -> InspectionStrategy? {
        // Read first bytes to detect magic numbers
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        
        guard let data = try handle.read(upToCount: 16) else {
            return nil
        }
        
        // PDF magic number: %PDF
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            return .document(.pdf)
        }
        
        // PNG magic number
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return .image
        }
        
        // JPEG magic number
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return .image
        }
        
        // MP4/MOV (ftyp box)
        if data.count >= 8 {
            let ftypCheck = data[4..<8]
            if ftypCheck.elementsEqual("ftyp".utf8) {
                return .video
            }
        }
        
        return nil
    }
}

