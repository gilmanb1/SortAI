// MARK: - File Signature
// Unified data structure that normalizes both Video and Text inputs
// so the Brain can process them identically.

import Foundation
import SwiftUI

// MARK: - Media Kind Enumeration
enum MediaKind: String, Codable, Sendable, CaseIterable {
    case document
    case video
    case image
    case audio
    case unknown
    
    var icon: String {
        switch self {
        case .document: return "doc.text.fill"
        case .video: return "video.fill"
        case .image: return "photo.fill"
        case .audio: return "waveform"
        case .unknown: return "questionmark.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .document: return .blue
        case .video: return .purple
        case .image: return .green
        case .audio: return .orange
        case .unknown: return .gray
        }
    }
}

// MARK: - File Signature (Core Data Structure)
/// Unified representation of extracted signals from any file type.
/// This struct normalizes both document and video inputs so the Brain
/// can process them using a single, consistent interface.
struct FileSignature: Codable, Sendable, Identifiable, Hashable {
    // MARK: Identity
    let id: UUID
    let url: URL
    let kind: MediaKind
    
    // MARK: Metadata
    let title: String
    let fileExtension: String
    let fileSizeBytes: Int64
    let checksum: String  // SHA-256 for deduplication
    let capturedAt: Date
    
    // MARK: Textual Signals (normalized for both kinds)
    /// For documents: extracted text content
    /// For videos: transcribed audio + OCR from frames
    let textualCue: String
    
    // MARK: Visual Signals (video/image specific)
    /// Scene classification tags from Vision framework
    let sceneTags: [String]
    /// Detected objects in frames
    let detectedObjects: [String]
    /// Dominant colors (hex strings)
    let dominantColors: [String]
    
    // MARK: Document-Specific
    let pageCount: Int?
    let wordCount: Int?
    let language: String?
    
    // MARK: Media-Specific
    let duration: TimeInterval?
    let frameCount: Int?
    let resolution: CGSize?
    let hasAudio: Bool?
    
    // MARK: Computed Properties
    var textPreview: String {
        String(textualCue.prefix(500))
    }
    
    var signalStrength: Double {
        // Calculate how much useful signal we extracted
        var score = 0.0
        if !textualCue.isEmpty { score += 0.4 }
        if !sceneTags.isEmpty { score += 0.3 }
        if !detectedObjects.isEmpty { score += 0.2 }
        if wordCount ?? 0 > 100 { score += 0.1 }
        return min(score, 1.0)
    }
    
    // MARK: Initialization
    init(
        id: UUID = UUID(),
        url: URL,
        kind: MediaKind,
        title: String,
        fileExtension: String,
        fileSizeBytes: Int64,
        checksum: String,
        capturedAt: Date = Date(),
        textualCue: String = "",
        sceneTags: [String] = [],
        detectedObjects: [String] = [],
        dominantColors: [String] = [],
        pageCount: Int? = nil,
        wordCount: Int? = nil,
        language: String? = nil,
        duration: TimeInterval? = nil,
        frameCount: Int? = nil,
        resolution: CGSize? = nil,
        hasAudio: Bool? = nil
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.title = title
        self.fileExtension = fileExtension
        self.fileSizeBytes = fileSizeBytes
        self.checksum = checksum
        self.capturedAt = capturedAt
        self.textualCue = textualCue
        self.sceneTags = sceneTags
        self.detectedObjects = detectedObjects
        self.dominantColors = dominantColors
        self.pageCount = pageCount
        self.wordCount = wordCount
        self.language = language
        self.duration = duration
        self.frameCount = frameCount
        self.resolution = resolution
        self.hasAudio = hasAudio
    }
}

// MARK: - Processing Result
/// Combines a FileSignature with the Brain's categorization result
struct ProcessingResult: Identifiable, Sendable {
    let id: UUID
    let signature: FileSignature
    let brainResult: BrainResult
    let wasFromMemory: Bool
    let processedAt: Date
    
    init(
        signature: FileSignature,
        brainResult: BrainResult,
        wasFromMemory: Bool = false
    ) {
        self.id = UUID()
        self.signature = signature
        self.brainResult = brainResult
        self.wasFromMemory = wasFromMemory
        self.processedAt = Date()
    }
}

// MARK: - Brain Result
/// The structured output from the LLM categorization
struct BrainResult: Sendable {
    let category: String
    let subcategory: String?
    let confidence: Double
    let rationale: String
    let suggestedPath: String?
    let tags: [String]
    
    /// All subcategories in the path (for deep hierarchies)
    /// e.g., for "Education / Magic / Card Tricks", this would be ["Magic", "Card Tricks"]
    let allSubcategories: [String]
    
    /// v2.0: The provider that generated this result
    let provider: LLMProviderIdentifier?
    
    /// The full category path as a CategoryPath object
    var fullCategoryPath: CategoryPath {
        CategoryPath(components: [category] + allSubcategories)
    }
    
    init(
        category: String,
        subcategory: String? = nil,
        confidence: Double,
        rationale: String,
        suggestedPath: String? = nil,
        tags: [String] = [],
        allSubcategories: [String]? = nil,
        provider: LLMProviderIdentifier? = nil
    ) {
        self.category = category
        self.subcategory = subcategory
        self.confidence = confidence
        self.rationale = rationale
        self.suggestedPath = suggestedPath
        self.tags = tags
        // Use allSubcategories if provided, otherwise fall back to single subcategory
        self.allSubcategories = allSubcategories ?? (subcategory.map { [$0] } ?? [])
        self.provider = provider
    }
}

extension BrainResult: Codable {
    enum CodingKeys: String, CodingKey {
        case category, subcategory, confidence, rationale, suggestedPath, tags, allSubcategories, provider
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(String.self, forKey: .category)
        subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory)
        confidence = try container.decode(Double.self, forKey: .confidence)
        rationale = try container.decode(String.self, forKey: .rationale)
        suggestedPath = try container.decodeIfPresent(String.self, forKey: .suggestedPath)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        // Load allSubcategories or fall back to single subcategory
        allSubcategories = try container.decodeIfPresent([String].self, forKey: .allSubcategories) 
            ?? (subcategory.map { [$0] } ?? [])
        provider = try container.decodeIfPresent(LLMProviderIdentifier.self, forKey: .provider)
    }
}

