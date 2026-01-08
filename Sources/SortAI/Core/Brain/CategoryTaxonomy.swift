// MARK: - Category Taxonomy
// Defines valid categories and subcategories for constrained LLM output

import Foundation

/// Defines a hierarchical category taxonomy for file organization
struct CategoryTaxonomy: Sendable {
    
    /// Main categories with their allowed subcategories
    static let categories: [String: [String]] = [
        // Magic content (primary use case)
        "Magic": [
            "Card Magic",
            "Coin Magic",
            "Stage Illusions",
            "Close-up Magic",
            "Mentalism",
            "Street Magic",
            "Parlor Magic",
            "Kids Magic",
            "Comedy Magic",
            "Tutorial",
            "Masterclass",
            "Performance",
            "Lecture",
            "History",
            "Theory",
            "Props",
            "Gimmicks",
            "Sleight of Hand",
            "Other"
        ],
        
        // Education
        "Education": [
            "Tutorial",
            "Course",
            "Lecture",
            "Workshop",
            "Demonstration",
            "How-to",
            "Training",
            "Other"
        ],
        
        // Entertainment
        "Entertainment": [
            "Performance",
            "Show",
            "Documentary",
            "Interview",
            "Behind the Scenes",
            "Other"
        ],
        
        // Documents
        "Documents": [
            "PDF",
            "Manual",
            "Instructions",
            "Notes",
            "Script",
            "Other"
        ],
        
        // Images
        "Images": [
            "Photos",
            "Screenshots",
            "Diagrams",
            "Artwork",
            "Other"
        ],
        
        // Uncategorized (fallback)
        "Uncategorized": [
            "Unknown",
            "Mixed Content",
            "Other"
        ]
    ]
    
    /// Returns all main categories
    static var mainCategories: [String] {
        Array(categories.keys).sorted()
    }
    
    /// Returns subcategories for a main category
    static func subcategories(for mainCategory: String) -> [String] {
        categories[mainCategory] ?? ["Other"]
    }
    
    /// Validates and normalizes a category/subcategory pair
    static func normalize(category: String, subcategory: String?) -> (category: String, subcategory: String) {
        // Find best matching main category
        let normalizedCategory = mainCategories.first { 
            category.lowercased().contains($0.lowercased()) || $0.lowercased().contains(category.lowercased())
        } ?? "Uncategorized"
        
        // Find best matching subcategory
        let subs = subcategories(for: normalizedCategory)
        let normalizedSub = subs.first {
            (subcategory ?? "").lowercased().contains($0.lowercased()) || $0.lowercased().contains((subcategory ?? "").lowercased())
        } ?? subs.first ?? "Other"
        
        return (normalizedCategory, normalizedSub)
    }
    
    /// Creates a compact category list for prompts
    static func compactPromptList() -> String {
        var result = "VALID CATEGORIES:\n"
        for (main, subs) in categories.sorted(by: { $0.key < $1.key }) {
            result += "- \(main): \(subs.prefix(5).joined(separator: ", "))\n"
        }
        return result
    }
}

// MARK: - Filename Parser

/// Extracts hints from filenames to aid categorization
struct FilenameParser {
    
    /// Known magic-related terms in filenames
    private static let magicTerms: Set<String> = [
        "magic", "magician", "trick", "illusion", "sleight", "card", "coin",
        "deck", "shuffle", "force", "palm", "pass", "switch", "vanish",
        "appear", "levitation", "mentalism", "mind", "prediction",
        "masterclass", "lecture", "penguin", "theory11", "ellusionist",
        "murphy", "magic", "cups", "balls", "rope", "ring", "silk",
        "regal", "vernon", "tamariz", "ascanio", "erdnase", "marlo",
        "blaine", "angel", "copperfield", "houdini", "penn", "teller"
    ]
    
    /// Card magic specific terms
    private static let cardMagicTerms: Set<String> = [
        "card", "deck", "shuffle", "force", "palm", "pass", "switch",
        "double", "lift", "control", "false", "cut", "deal", "spread",
        "fan", "spring", "packet", "ace", "king", "queen", "jack",
        "bicycle", "bee", "tally", "acaan", "triumph", "ambitious"
    ]
    
    /// Coin magic specific terms
    private static let coinMagicTerms: Set<String> = [
        "coin", "coins", "half", "dollar", "silver", "copper", "shell",
        "okito", "boston", "matrix", "miser", "dream", "spellbound",
        "retention", "vanish", "production", "classic", "palm"
    ]
    
    /// Stage magic specific terms
    private static let stageMagicTerms: Set<String> = [
        "stage", "illusion", "big", "levitation", "sawing", "metamorphosis",
        "zig", "zag", "box", "cabinet", "assistant", "dove", "production"
    ]
    
    /// Parses a filename and returns categorization hints
    static func parse(filename: String) -> FilenameHints {
        let normalized = filename.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        
        let words = Set(normalized.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
        
        // Check for magic-related content
        let magicScore = words.intersection(magicTerms).count
        let cardScore = words.intersection(cardMagicTerms).count
        let coinScore = words.intersection(coinMagicTerms).count
        let stageScore = words.intersection(stageMagicTerms).count
        
        var suggestedCategory: String?
        var suggestedSubcategory: String?
        var confidence: Double = 0.0
        var keywords: [String] = []
        
        if magicScore > 0 || cardScore > 0 || coinScore > 0 || stageScore > 0 {
            suggestedCategory = "Magic"
            
            // Determine most likely subcategory
            if cardScore > coinScore && cardScore > stageScore {
                suggestedSubcategory = "Card Magic"
                confidence = min(0.9, 0.5 + Double(cardScore) * 0.1)
            } else if coinScore > cardScore && coinScore > stageScore {
                suggestedSubcategory = "Coin Magic"
                confidence = min(0.9, 0.5 + Double(coinScore) * 0.1)
            } else if stageScore > cardScore && stageScore > coinScore {
                suggestedSubcategory = "Stage Illusions"
                confidence = min(0.9, 0.5 + Double(stageScore) * 0.1)
            } else {
                // Check for other magic subcategories
                if normalized.contains("masterclass") || normalized.contains("lecture") {
                    suggestedSubcategory = "Masterclass"
                    confidence = 0.8
                } else if normalized.contains("tutorial") || normalized.contains("instruction") {
                    suggestedSubcategory = "Tutorial"
                    confidence = 0.8
                } else if normalized.contains("performance") || normalized.contains("show") {
                    suggestedSubcategory = "Performance"
                    confidence = 0.7
                } else {
                    suggestedSubcategory = "Close-up Magic"
                    confidence = 0.5
                }
            }
            
            keywords = Array(words.intersection(magicTerms).union(words.intersection(cardMagicTerms))
                .union(words.intersection(coinMagicTerms)).union(words.intersection(stageMagicTerms)))
        }
        
        return FilenameHints(
            suggestedCategory: suggestedCategory,
            suggestedSubcategory: suggestedSubcategory,
            confidence: confidence,
            keywords: keywords,
            cleanedName: normalized.components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty && $0.count > 2 }
                .joined(separator: " ")
        )
    }
}

/// Hints extracted from a filename
struct FilenameHints: Sendable {
    let suggestedCategory: String?
    let suggestedSubcategory: String?
    let confidence: Double
    let keywords: [String]
    let cleanedName: String
    
    var hasSuggestion: Bool {
        suggestedCategory != nil
    }
}

