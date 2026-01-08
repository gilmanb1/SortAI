// MARK: - Quick Categorizer
// Fast filename-based categorization for immediate UI feedback
// Used as first pass before full content analysis

import Foundation

/// Quick categorization result (filename-only analysis)
struct QuickCategoryResult: Sendable {
    let category: String
    let subcategory: String?
    let confidence: Double
    let source: Source
    
    enum Source: String, Sendable {
        case filename = "Filename analysis"
        case fileType = "File type"
        case cached = "Previously seen"
    }
    
    /// Low-confidence placeholder indicating refinement is needed
    var needsRefinement: Bool {
        confidence < 0.7
    }
}

/// Fast categorizer that provides immediate results based on filename patterns
/// This runs before full content analysis to give users instant feedback
actor QuickCategorizer {
    
    // MARK: - Pattern Database
    
    /// Common filename patterns mapped to categories
    private let filenamePatterns: [(pattern: String, category: String, subcategory: String?)] = [
        // Videos
        ("(?i)screen.?record", "Videos", "Screen Recordings"),
        ("(?i)zoom_\\d+", "Videos", "Meetings"),
        ("(?i)meeting|call|conference", "Videos", "Meetings"),
        ("(?i)tutorial|lesson|course", "Videos", "Education"),
        ("(?i)trailer|teaser", "Videos", "Entertainment"),
        ("(?i)vlog|daily|day.?\\d+", "Videos", "Personal"),
        ("(?i)wedding|birthday|graduation|party", "Videos", "Events"),
        ("(?i)vacation|trip|travel|holiday", "Videos", "Travel"),
        ("(?i)workout|exercise|fitness|gym", "Videos", "Fitness"),
        ("(?i)recipe|cooking|food|kitchen", "Videos", "Cooking"),
        ("(?i)unboxing|review|haul", "Videos", "Reviews"),
        ("(?i)gaming|gameplay|stream", "Videos", "Gaming"),
        
        // Audio
        ("(?i)podcast|episode|ep\\d+", "Audio", "Podcasts"),
        ("(?i)interview|conversation", "Audio", "Interviews"),
        ("(?i)audiobook|chapter", "Audio", "Audiobooks"),
        ("(?i)lecture|class|seminar", "Audio", "Education"),
        ("(?i)song|track|album|music", "Audio", "Music"),
        ("(?i)voice.?memo|recording|note", "Audio", "Voice Memos"),
        
        // Documents
        ("(?i)invoice|receipt|bill", "Documents", "Financial"),
        ("(?i)contract|agreement|terms", "Documents", "Legal"),
        ("(?i)resume|cv|curriculum", "Documents", "Career"),
        ("(?i)report|analysis|summary", "Documents", "Reports"),
        ("(?i)manual|guide|instructions", "Documents", "Manuals"),
        ("(?i)presentation|slides|deck", "Documents", "Presentations"),
        ("(?i)spreadsheet|budget|expenses", "Documents", "Spreadsheets"),
        ("(?i)notes|journal|diary", "Documents", "Notes"),
        ("(?i)letter|correspondence", "Documents", "Correspondence"),
        
        // Images
        ("(?i)screenshot|screen.?shot", "Images", "Screenshots"),
        ("(?i)photo|pic|img|image", "Images", "Photos"),
        ("(?i)selfie|portrait|headshot", "Images", "Portraits"),
        ("(?i)meme|funny|joke", "Images", "Memes"),
        ("(?i)wallpaper|background", "Images", "Wallpapers"),
        ("(?i)logo|icon|badge", "Images", "Graphics"),
        ("(?i)diagram|chart|graph", "Images", "Diagrams"),
        ("(?i)scan|scanned", "Images", "Scans"),
        
        // Code/Development
        ("(?i)\\.swift$|\\.py$|\\.js$|\\.ts$|\\.java$|\\.cpp$|\\.c$|\\.h$", "Development", "Source Code"),
        ("(?i)readme|changelog|license", "Development", "Documentation"),
        ("(?i)config|settings|\\.env|\\.json|\\.yaml|\\.yml", "Development", "Configuration"),
        
        // Archives
        ("(?i)\\.zip$|\\.tar$|\\.gz$|\\.7z$|\\.rar$", "Archives", nil),
        ("(?i)backup|bak", "Archives", "Backups"),
        
        // Downloads (generic)
        ("(?i)download|dl_|downloaded", "Downloads", nil),
    ]
    
    /// File extension to category mapping
    private let extensionCategories: [String: (category: String, subcategory: String?)] = [
        // Video
        "mp4": ("Videos", nil),
        "mov": ("Videos", nil),
        "avi": ("Videos", nil),
        "mkv": ("Videos", nil),
        "wmv": ("Videos", nil),
        "flv": ("Videos", nil),
        "webm": ("Videos", nil),
        "m4v": ("Videos", nil),
        
        // Audio
        "mp3": ("Audio", "Music"),
        "m4a": ("Audio", nil),
        "wav": ("Audio", nil),
        "aac": ("Audio", nil),
        "flac": ("Audio", "Music"),
        "ogg": ("Audio", nil),
        "wma": ("Audio", nil),
        "aiff": ("Audio", "Music"),
        
        // Documents
        "pdf": ("Documents", nil),
        "doc": ("Documents", "Word"),
        "docx": ("Documents", "Word"),
        "txt": ("Documents", "Text"),
        "md": ("Documents", "Markdown"),
        "rtf": ("Documents", nil),
        "pages": ("Documents", nil),
        
        // Spreadsheets
        "xls": ("Documents", "Spreadsheets"),
        "xlsx": ("Documents", "Spreadsheets"),
        "csv": ("Documents", "Data"),
        "numbers": ("Documents", "Spreadsheets"),
        
        // Presentations
        "ppt": ("Documents", "Presentations"),
        "pptx": ("Documents", "Presentations"),
        "key": ("Documents", "Presentations"),
        
        // Images
        "jpg": ("Images", "Photos"),
        "jpeg": ("Images", "Photos"),
        "png": ("Images", nil),
        "gif": ("Images", nil),
        "webp": ("Images", nil),
        "heic": ("Images", "Photos"),
        "heif": ("Images", "Photos"),
        "raw": ("Images", "Photos"),
        "tiff": ("Images", nil),
        "bmp": ("Images", nil),
        "svg": ("Images", "Graphics"),
        "psd": ("Images", "Design"),
        "ai": ("Images", "Design"),
        
        // Code
        "swift": ("Development", "Swift"),
        "py": ("Development", "Python"),
        "js": ("Development", "JavaScript"),
        "ts": ("Development", "TypeScript"),
        "java": ("Development", "Java"),
        "cpp": ("Development", "C++"),
        "c": ("Development", "C"),
        "h": ("Development", "C/C++"),
        "go": ("Development", "Go"),
        "rs": ("Development", "Rust"),
        "rb": ("Development", "Ruby"),
        "php": ("Development", "PHP"),
        "html": ("Development", "Web"),
        "css": ("Development", "Web"),
        "json": ("Development", "Data"),
        "xml": ("Development", "Data"),
        "yaml": ("Development", "Config"),
        "yml": ("Development", "Config"),
        
        // Archives
        "zip": ("Archives", nil),
        "tar": ("Archives", nil),
        "gz": ("Archives", nil),
        "7z": ("Archives", nil),
        "rar": ("Archives", nil),
        "dmg": ("Archives", "Disk Images"),
        "iso": ("Archives", "Disk Images"),
    ]
    
    // MARK: - Quick Categorization
    
    /// Performs fast categorization based on filename and extension only
    /// Returns immediately - no file content analysis
    func categorize(url: URL) async -> QuickCategoryResult {
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()
        
        // Try filename pattern matching first (higher confidence)
        if let patternMatch = matchFilenamePattern(filename) {
            return QuickCategoryResult(
                category: patternMatch.category,
                subcategory: patternMatch.subcategory,
                confidence: 0.65,  // Medium confidence - needs refinement
                source: .filename
            )
        }
        
        // Fall back to extension-based categorization
        if let extMatch = extensionCategories[ext] {
            return QuickCategoryResult(
                category: extMatch.category,
                subcategory: extMatch.subcategory,
                confidence: 0.45,  // Lower confidence - definitely needs refinement
                source: .fileType
            )
        }
        
        // Unknown - will be categorized by content analysis
        return QuickCategoryResult(
            category: "Uncategorized",
            subcategory: nil,
            confidence: 0.1,
            source: .fileType
        )
    }
    
    /// Match filename against known patterns
    private func matchFilenamePattern(_ filename: String) -> (category: String, subcategory: String?)? {
        for (pattern, category, subcategory) in filenamePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: filename, options: [], range: NSRange(filename.startIndex..., in: filename)) != nil {
                return (category, subcategory)
            }
        }
        return nil
    }
    
    /// Estimate processing time for a file based on type and size
    func estimateProcessingTime(url: URL, fileSize: Int64) -> TimeInterval {
        let ext = url.pathExtension.lowercased()
        
        // Video files take longest
        let videoExtensions = ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v"]
        if videoExtensions.contains(ext) {
            // Rough estimate: ~5s base + 1s per 100MB
            return 5.0 + Double(fileSize) / 100_000_000.0
        }
        
        // Audio files are medium
        let audioExtensions = ["mp3", "m4a", "wav", "aac", "flac", "ogg", "wma", "aiff"]
        if audioExtensions.contains(ext) {
            return 3.0 + Double(fileSize) / 200_000_000.0
        }
        
        // Images need vision analysis
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "tiff", "bmp"]
        if imageExtensions.contains(ext) {
            return 1.0 + Double(fileSize) / 500_000_000.0
        }
        
        // Documents are fast
        return 0.5
    }
}

