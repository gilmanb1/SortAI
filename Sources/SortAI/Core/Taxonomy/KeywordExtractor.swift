// MARK: - Keyword Extractor
// Extracts meaningful keywords from filenames for clustering

import Foundation
import NaturalLanguage

// MARK: - Keyword Extractor

/// Extracts and normalizes keywords from filenames
struct KeywordExtractor {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// Minimum keyword length to keep
        let minKeywordLength: Int
        
        /// Whether to apply stemming (Phase 2)
        let applyStemming: Bool
        
        /// Whether to remove common stopwords
        let removeStopwords: Bool
        
        /// Common file-related stopwords to remove
        let stopwords: Set<String>
        
        static let fast = Configuration(
            minKeywordLength: 3,
            applyStemming: false,
            removeStopwords: true,
            stopwords: defaultStopwords
        )
        
        static let quality = Configuration(
            minKeywordLength: 2,
            applyStemming: true,
            removeStopwords: true,
            stopwords: defaultStopwords
        )
        
        static let defaultStopwords: Set<String> = [
            "the", "and", "for", "with", "from", "this", "that", "your", "you",
            "are", "was", "were", "been", "being", "have", "has", "had", "having",
            "does", "did", "doing", "will", "would", "could", "should", "may",
            "might", "must", "shall", "can", "need", "our", "ours", "their",
            "download", "file", "files", "copy", "new", "old", "final", "draft",
            "version", "ver", "rev", "edit", "edited", "original", "backup",
            "tmp", "temp", "test", "sample", "example", "demo", "untitled"
        ]
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .fast) {
        self.config = configuration
    }
    
    // MARK: - Extraction
    
    /// Extract keywords from a single filename
    func extract(from filename: String) -> ExtractedKeywords {
        // Remove extension
        let baseName = removeExtension(filename)
        
        // Split into tokens
        var tokens = tokenize(baseName)
        
        // Filter and normalize
        tokens = tokens
            .map { $0.lowercased() }
            .filter { $0.count >= config.minKeywordLength }
            .filter { !isNumericOnly($0) }
        
        // Remove stopwords
        if config.removeStopwords {
            tokens = tokens.filter { !config.stopwords.contains($0) }
        }
        
        // Apply stemming if enabled
        var stemmed: [String] = []
        if config.applyStemming {
            stemmed = tokens.map { stem($0) }
        }
        
        // Extract date patterns
        let dateInfo = extractDateInfo(from: baseName)
        
        // Extract file type hints
        let fileType = inferFileType(from: filename)
        
        return ExtractedKeywords(
            original: filename,
            keywords: Set(tokens),
            stemmedKeywords: Set(stemmed),
            dateInfo: dateInfo,
            fileType: fileType
        )
    }
    
    /// Extract keywords from multiple filenames (batch)
    func extractBatch(from filenames: [String]) -> [ExtractedKeywords] {
        filenames.map { extract(from: $0) }
    }
    
    /// Extract keywords from TaxonomyScannedFile (preserves file reference)
    func extract(from file: TaxonomyScannedFile) -> ExtractedKeywords {
        let baseName = removeExtension(file.filename)
        var tokens = tokenize(baseName)
        
        tokens = tokens
            .map { $0.lowercased() }
            .filter { $0.count >= config.minKeywordLength }
            .filter { !config.stopwords.contains($0) }
        
        var stemmed: [String] = []
        if config.applyStemming {
            stemmed = tokens.map { stem($0) }
        }
        
        let dateInfo = extractDateInfo(from: baseName)
        let fileType = inferFileType(from: file.filename)
        
        return ExtractedKeywords(
            id: file.id,  // Use original file ID!
            original: file.filename,
            keywords: Set(tokens),
            stemmedKeywords: Set(stemmed),
            dateInfo: dateInfo,
            fileType: fileType,
            sourceURL: file.url,
            sourceFileId: file.id
        )
    }
    
    /// Extract keywords from multiple TaxonomyScannedFiles (batch, preserves file references)
    func extractBatch(from files: [TaxonomyScannedFile]) -> [ExtractedKeywords] {
        files.map { extract(from: $0) }
    }
    
    // MARK: - Tokenization
    
    /// Split filename into tokens
    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        
        // First, split on common delimiters
        let delimiterSplit = text.components(separatedBy: CharacterSet(charactersIn: "_-. ()[]{}"))
        
        for part in delimiterSplit {
            // Handle camelCase and PascalCase
            let camelSplit = splitCamelCase(part)
            tokens.append(contentsOf: camelSplit)
        }
        
        // Filter empty strings
        return tokens.filter { !$0.isEmpty }
    }
    
    /// Split camelCase and PascalCase into words
    private func splitCamelCase(_ text: String) -> [String] {
        var words: [String] = []
        var currentWord = ""
        
        for char in text {
            if char.isUppercase && !currentWord.isEmpty {
                // Check if previous was also uppercase (acronym)
                if let last = currentWord.last, last.isUppercase {
                    currentWord.append(char)
                } else {
                    words.append(currentWord)
                    currentWord = String(char)
                }
            } else if char.isNumber && !currentWord.isEmpty && !currentWord.last!.isNumber {
                words.append(currentWord)
                currentWord = String(char)
            } else {
                currentWord.append(char)
            }
        }
        
        if !currentWord.isEmpty {
            words.append(currentWord)
        }
        
        return words
    }
    
    // MARK: - Stemming
    
    /// Simple stemming using NaturalLanguage framework
    private func stem(_ word: String) -> String {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        
        var lemma = word
        tagger.enumerateTags(in: word.startIndex..<word.endIndex, unit: .word, scheme: .lemma) { tag, _ in
            if let tag = tag {
                lemma = tag.rawValue
            }
            return true
        }
        
        return lemma
    }
    
    // MARK: - Helpers
    
    private func removeExtension(_ filename: String) -> String {
        let url = URL(fileURLWithPath: filename)
        return url.deletingPathExtension().lastPathComponent
    }
    
    private func isNumericOnly(_ text: String) -> Bool {
        text.allSatisfy { $0.isNumber }
    }
    
    /// Extract date information from filename
    private func extractDateInfo(from text: String) -> DateInfo? {
        // Year patterns: 2024, 2023, etc.
        let yearPattern = #"(19|20)\d{2}"#
        if let yearMatch = text.range(of: yearPattern, options: .regularExpression) {
            let year = String(text[yearMatch])
            return DateInfo(year: Int(year), month: nil, day: nil, quarter: nil)
        }
        
        // Quarter patterns: Q1, Q2, Q3, Q4
        let quarterPattern = #"[Qq][1-4]"#
        if let quarterMatch = text.range(of: quarterPattern, options: .regularExpression) {
            let quarter = String(text[quarterMatch]).uppercased()
            return DateInfo(year: nil, month: nil, day: nil, quarter: quarter)
        }
        
        // Month patterns: Jan, Feb, January, etc.
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let lowerText = text.lowercased()
        for (index, month) in months.enumerated() {
            if lowerText.contains(month) {
                return DateInfo(year: nil, month: index + 1, day: nil, quarter: nil)
            }
        }
        
        return nil
    }
    
    /// Infer file type from extension
    private func inferFileType(from filename: String) -> FileTypeHint {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        
        switch ext {
        case "pdf", "doc", "docx", "txt", "rtf", "odt", "pages":
            return .document
        case "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v":
            return .video
        case "mp3", "wav", "aac", "flac", "m4a", "ogg", "wma":
            return .audio
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp", "heic", "svg":
            return .image
        case "zip", "rar", "7z", "tar", "gz", "bz2":
            return .archive
        case "app", "exe", "dmg", "pkg":
            return .application
        default:
            return .other
        }
    }
}

// MARK: - Supporting Types

/// Keywords extracted from a filename
struct ExtractedKeywords: Sendable, Identifiable {
    let id: UUID  // Can be original file ID for tracking
    let original: String
    let keywords: Set<String>
    let stemmedKeywords: Set<String>
    let dateInfo: DateInfo?
    let fileType: FileTypeHint
    
    // Original file reference for organization
    let sourceURL: URL?
    let sourceFileId: UUID?
    
    /// All keywords (stemmed if available, otherwise regular)
    var allKeywords: Set<String> {
        stemmedKeywords.isEmpty ? keywords : stemmedKeywords
    }
    
    /// Initialize with just a filename (legacy)
    init(original: String, keywords: Set<String>, stemmedKeywords: Set<String>, dateInfo: DateInfo?, fileType: FileTypeHint) {
        self.id = UUID()
        self.original = original
        self.keywords = keywords
        self.stemmedKeywords = stemmedKeywords
        self.dateInfo = dateInfo
        self.fileType = fileType
        self.sourceURL = nil
        self.sourceFileId = nil
    }
    
    /// Initialize with full file reference (for proper organization)
    init(id: UUID, original: String, keywords: Set<String>, stemmedKeywords: Set<String>, dateInfo: DateInfo?, fileType: FileTypeHint, sourceURL: URL, sourceFileId: UUID) {
        self.id = id
        self.original = original
        self.keywords = keywords
        self.stemmedKeywords = stemmedKeywords
        self.dateInfo = dateInfo
        self.fileType = fileType
        self.sourceURL = sourceURL
        self.sourceFileId = sourceFileId
    }
}

/// Date information extracted from filename
struct DateInfo: Sendable, Equatable {
    let year: Int?
    let month: Int?
    let day: Int?
    let quarter: String?
    
    var hasAnyDate: Bool {
        year != nil || month != nil || day != nil || quarter != nil
    }
}

/// File type hint based on extension
enum FileTypeHint: String, Sendable, CaseIterable {
    case document
    case video
    case audio
    case image
    case archive
    case application
    case other
    
    var displayName: String {
        switch self {
        case .document: return "Documents"
        case .video: return "Videos"
        case .audio: return "Audio"
        case .image: return "Images"
        case .archive: return "Archives"
        case .application: return "Applications"
        case .other: return "Other"
        }
    }
}

