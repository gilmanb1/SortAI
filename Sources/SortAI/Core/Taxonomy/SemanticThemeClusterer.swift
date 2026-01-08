// MARK: - Semantic Theme Clusterer
// Clusters files by semantic theme first, then optionally by file type

import Foundation

// MARK: - Semantic Theme Clusterer

/// Clusters files by semantic themes rather than file type
/// Produces hierarchies like: Magic → Card Magic → Videos, PDFs
actor SemanticThemeClusterer {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// Target number of top-level themes
        let targetThemeCount: Int
        
        /// Whether to separate file types within themes
        let separateFileTypes: Bool
        
        /// Minimum files to form a theme
        let minFilesPerTheme: Int
        
        /// Minimum similarity to merge keywords into same theme
        let themeSimilarityThreshold: Double
        
        /// Minimum files for a sub-theme
        let minFilesPerSubTheme: Int
        
        /// Maximum hierarchy depth
        let maxDepth: Int
        
        static let `default` = Configuration(
            targetThemeCount: 7,
            separateFileTypes: true,
            minFilesPerTheme: 3,
            themeSimilarityThreshold: 0.15,
            minFilesPerSubTheme: 2,
            maxDepth: 3
        )
        
        static func withTargetCount(_ count: Int, separateTypes: Bool = true) -> Configuration {
            Configuration(
                targetThemeCount: max(3, min(count, 15)),
                separateFileTypes: separateTypes,
                minFilesPerTheme: 3,
                themeSimilarityThreshold: 0.15,
                minFilesPerSubTheme: 2,
                maxDepth: 3
            )
        }
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    
    // Common semantic groupings for theme detection
    private let semanticGroups: [String: Set<String>] = [
        "magic": ["magic", "trick", "tricks", "illusion", "card", "cards", "coin", "coins", 
                  "sleight", "prestidigitation", "magician", "performance", "routine"],
        "cooking": ["recipe", "recipes", "cooking", "food", "chef", "kitchen", "baking", 
                   "ingredients", "meal", "dinner", "lunch", "breakfast"],
        "music": ["music", "song", "songs", "album", "artist", "band", "concert", 
                 "audio", "track", "playlist", "guitar", "piano"],
        "programming": ["code", "coding", "programming", "developer", "software", "app",
                       "swift", "python", "javascript", "api", "function", "class"],
        "photography": ["photo", "photos", "photography", "camera", "image", "images",
                       "picture", "pictures", "portrait", "landscape"],
        "video": ["video", "videos", "movie", "movies", "film", "footage", "clip"],
        "document": ["document", "documents", "report", "paper", "memo", "letter"],
        "project": ["project", "projects", "work", "task", "plan", "planning"],
        "personal": ["personal", "private", "family", "home", "vacation", "travel"],
        "finance": ["finance", "financial", "budget", "invoice", "tax", "bank", "money"],
        "education": ["tutorial", "tutorials", "lesson", "lessons", "course", "learn",
                     "learning", "training", "education", "study"]
    ]
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .default) {
        self.config = configuration
    }
    
    // MARK: - Main Clustering
    
    /// Cluster files by semantic theme
    func cluster(keywords: [ExtractedKeywords]) -> [ThemeCluster] {
        guard !keywords.isEmpty else { return [] }
        
        NSLog("🎯 [SemanticCluster] Starting semantic clustering of \(keywords.count) files")
        
        // Step 1: Build keyword frequency map across all files
        let keywordFrequency = buildKeywordFrequency(keywords)
        NSLog("🎯 [SemanticCluster] Found \(keywordFrequency.count) unique keywords")
        
        // Step 2: Identify dominant themes from keywords
        var themes = identifyThemes(from: keywordFrequency, files: keywords)
        NSLog("🎯 [SemanticCluster] Identified \(themes.count) initial themes")
        
        // Step 3: Assign files to themes
        themes = assignFilesToThemes(keywords, themes: themes)
        
        // Step 4: Handle unassigned files
        let (assignedThemes, uncategorized) = handleUnassignedFiles(keywords, themes: themes)
        themes = assignedThemes
        
        // Step 5: Merge small themes
        themes = mergeSmallThemes(themes)
        
        // Step 6: Build sub-themes within each theme
        themes = buildSubThemes(themes)
        
        // Step 7: Optionally separate by file type
        if config.separateFileTypes {
            themes = separateByFileType(themes)
        }
        
        // Step 8: Add uncategorized if any
        if !uncategorized.isEmpty {
            let uncatTheme = ThemeCluster(
                name: "Uncategorized",
                keywords: [],
                files: uncategorized,
                subThemes: [],
                fileTypeGroups: config.separateFileTypes ? groupByFileType(uncategorized) : [:]
            )
            themes.append(uncatTheme)
        }
        
        // Sort by file count
        themes.sort { $0.totalFileCount > $1.totalFileCount }
        
        NSLog("✅ [SemanticCluster] Final: \(themes.count) themes with \(themes.reduce(0) { $0 + $1.totalFileCount }) files")
        
        return themes
    }
    
    // MARK: - Keyword Frequency
    
    private func buildKeywordFrequency(_ files: [ExtractedKeywords]) -> [String: Int] {
        var frequency: [String: Int] = [:]
        
        for file in files {
            for keyword in file.keywords {
                frequency[keyword, default: 0] += 1
            }
        }
        
        return frequency
    }
    
    // MARK: - Theme Identification
    
    private func identifyThemes(from frequency: [String: Int], files: [ExtractedKeywords]) -> [ThemeCluster] {
        NSLog("🎯 [SemanticCluster] Target theme count: \(config.targetThemeCount)")
        
        // Collect all potential themes with their scores
        var potentialThemes: [(theme: ThemeCluster, score: Int)] = []
        _ = Set<String>() // Placeholder for potential future keyword tracking
        
        // First, check for known semantic groups
        for (themeName, themeKeywords) in semanticGroups {
            let matchingKeywords = themeKeywords.filter { frequency[$0] != nil }
            let totalFrequency = matchingKeywords.reduce(0) { $0 + (frequency[$1] ?? 0) }
            
            if totalFrequency >= config.minFilesPerTheme {
                let theme = ThemeCluster(
                    name: themeName.capitalized,
                    keywords: matchingKeywords,
                    files: [],
                    subThemes: [],
                    fileTypeGroups: [:]
                )
                potentialThemes.append((theme, totalFrequency))
            }
        }
        
        NSLog("🎯 [SemanticCluster] Found \(potentialThemes.count) matching semantic groups")
        
        // Then, find themes from high-frequency keywords not in known groups
        let allUsedKeywords = Set(potentialThemes.flatMap { $0.theme.keywords })
        let sortedKeywords = frequency
            .filter { !allUsedKeywords.contains($0.key) && $0.value >= config.minFilesPerTheme }
            .sorted { $0.value > $1.value }
        
        // Add keyword-based themes (limit to prevent explosion)
        for (keyword, count) in sortedKeywords.prefix(20) {
            // Find related keywords
            var relatedKeywords = Set([keyword])
            for (otherKeyword, _) in frequency where otherKeyword != keyword {
                if jaccardSimilarity(keyword, otherKeyword) > config.themeSimilarityThreshold {
                    relatedKeywords.insert(otherKeyword)
                }
            }
            
            let theme = ThemeCluster(
                name: keyword.capitalized,
                keywords: relatedKeywords,
                files: [],
                subThemes: [],
                fileTypeGroups: [:]
            )
            potentialThemes.append((theme, count))
        }
        
        // Sort all potential themes by score and take top N based on target
        let sortedThemes = potentialThemes.sorted { $0.score > $1.score }
        let selectedThemes = sortedThemes.prefix(config.targetThemeCount).map { $0.theme }
        
        NSLog("🎯 [SemanticCluster] Selected \(selectedThemes.count) themes from \(potentialThemes.count) candidates (target: \(config.targetThemeCount))")
        
        return Array(selectedThemes)
    }
    
    // MARK: - File Assignment
    
    private func assignFilesToThemes(_ files: [ExtractedKeywords], themes: [ThemeCluster]) -> [ThemeCluster] {
        var updatedThemes = themes
        var assignedFiles = Set<UUID>()
        
        for file in files {
            var bestThemeIndex: Int?
            var bestScore: Double = 0
            
            for (index, theme) in updatedThemes.enumerated() {
                let score = themeMatchScore(file: file, theme: theme)
                if score > bestScore && score > 0.1 {
                    bestScore = score
                    bestThemeIndex = index
                }
            }
            
            if let index = bestThemeIndex {
                updatedThemes[index].files.append(file)
                assignedFiles.insert(file.id)
            }
        }
        
        return updatedThemes
    }
    
    private func themeMatchScore(file: ExtractedKeywords, theme: ThemeCluster) -> Double {
        let intersection = file.keywords.intersection(theme.keywords)
        guard !intersection.isEmpty else { return 0 }
        
        // Jaccard-like score
        let union = file.keywords.union(theme.keywords)
        return Double(intersection.count) / Double(union.count)
    }
    
    // MARK: - Unassigned Files
    
    private func handleUnassignedFiles(_ allFiles: [ExtractedKeywords], themes: [ThemeCluster]) -> ([ThemeCluster], [ExtractedKeywords]) {
        let assignedIds = Set(themes.flatMap { $0.files.map { $0.id } })
        let unassigned = allFiles.filter { !assignedIds.contains($0.id) }
        
        guard !unassigned.isEmpty else { return (themes, []) }
        
        NSLog("🎯 [SemanticCluster] \(unassigned.count) files unassigned, attempting to cluster")
        
        // Try to create new themes from unassigned files
        var updatedThemes = themes
        var remainingUnassigned: [ExtractedKeywords] = []
        
        // Group unassigned by their top keyword
        var keywordGroups: [String: [ExtractedKeywords]] = [:]
        for file in unassigned {
            if let topKeyword = file.keywords.max(by: { $0.count < $1.count }) {
                keywordGroups[topKeyword, default: []].append(file)
            } else {
                remainingUnassigned.append(file)
            }
        }
        
        // Create themes for groups that meet minimum size
        for (keyword, files) in keywordGroups {
            if files.count >= config.minFilesPerTheme {
                let newTheme = ThemeCluster(
                    name: keyword.capitalized,
                    keywords: [keyword],
                    files: files,
                    subThemes: [],
                    fileTypeGroups: [:]
                )
                updatedThemes.append(newTheme)
            } else {
                remainingUnassigned.append(contentsOf: files)
            }
        }
        
        return (updatedThemes, remainingUnassigned)
    }
    
    // MARK: - Theme Merging
    
    private func mergeSmallThemes(_ themes: [ThemeCluster]) -> [ThemeCluster] {
        var result: [ThemeCluster] = []
        var smallThemes: [ThemeCluster] = []
        
        for theme in themes {
            if theme.files.count >= config.minFilesPerTheme {
                result.append(theme)
            } else {
                smallThemes.append(theme)
            }
        }
        
        // Try to merge small themes with similar ones
        for small in smallThemes {
            var merged = false
            
            for (index, theme) in result.enumerated() {
                let similarity = jaccardSimilarity(small.keywords, theme.keywords)
                if similarity > 0.2 {
                    // Merge into this theme
                    result[index].files.append(contentsOf: small.files)
                    result[index].keywords.formUnion(small.keywords)
                    merged = true
                    break
                }
            }
            
            if !merged {
                // Keep as separate theme even if small
                result.append(small)
            }
        }
        
        return result
    }
    
    // MARK: - Sub-Theme Building
    
    private func buildSubThemes(_ themes: [ThemeCluster]) -> [ThemeCluster] {
        return themes.map { theme in
            guard theme.files.count >= config.minFilesPerSubTheme * 2 else {
                return theme
            }
            
            // Find potential sub-themes by clustering files within this theme
            let subThemes = clusterIntoSubThemes(theme.files, parentKeywords: theme.keywords)
            
            var updated = theme
            if subThemes.count > 1 {
                updated.subThemes = subThemes
            }
            
            return updated
        }
    }
    
    private func clusterIntoSubThemes(_ files: [ExtractedKeywords], parentKeywords: Set<String>) -> [SubTheme] {
        // Find keywords that differentiate files within this theme
        var keywordGroups: [String: [ExtractedKeywords]] = [:]
        
        for file in files {
            // Find the most distinctive keyword (not a parent keyword)
            let distinctiveKeywords = file.keywords.subtracting(parentKeywords)
            if let topKeyword = distinctiveKeywords.max(by: { $0.count < $1.count }) {
                keywordGroups[topKeyword, default: []].append(file)
            }
        }
        
        // Convert to sub-themes
        var subThemes: [SubTheme] = []
        var assignedFiles = Set<UUID>()
        
        for (keyword, groupFiles) in keywordGroups.sorted(by: { $0.value.count > $1.value.count }) {
            let unassignedFiles = groupFiles.filter { !assignedFiles.contains($0.id) }
            
            if unassignedFiles.count >= config.minFilesPerSubTheme {
                let subTheme = SubTheme(
                    name: keyword.capitalized,
                    keywords: [keyword],
                    files: unassignedFiles
                )
                subThemes.append(subTheme)
                assignedFiles.formUnion(unassignedFiles.map { $0.id })
            }
        }
        
        // Handle files not in any sub-theme
        let remainingFiles = files.filter { !assignedFiles.contains($0.id) }
        if !remainingFiles.isEmpty && subThemes.count > 0 {
            let otherSubTheme = SubTheme(
                name: "Other",
                keywords: [],
                files: remainingFiles
            )
            subThemes.append(otherSubTheme)
        }
        
        return subThemes
    }
    
    // MARK: - File Type Separation
    
    private func separateByFileType(_ themes: [ThemeCluster]) -> [ThemeCluster] {
        return themes.map { theme in
            var updated = theme
            updated.fileTypeGroups = groupByFileType(theme.files)
            
            // Also update sub-themes
            updated.subThemes = theme.subThemes.map { subTheme in
                var updatedSub = subTheme
                updatedSub.fileTypeGroups = groupByFileType(subTheme.files)
                return updatedSub
            }
            
            return updated
        }
    }
    
    private func groupByFileType(_ files: [ExtractedKeywords]) -> [FileTypeHint: [ExtractedKeywords]] {
        Dictionary(grouping: files) { $0.fileType }
    }
    
    // MARK: - Similarity Helpers
    
    private func jaccardSimilarity(_ word1: String, _ word2: String) -> Double {
        let set1 = Set(word1.lowercased())
        let set2 = Set(word2.lowercased())
        
        let intersection = set1.intersection(set2).count
        let union = set1.union(set2).count
        
        return union > 0 ? Double(intersection) / Double(union) : 0
    }
    
    private func jaccardSimilarity(_ set1: Set<String>, _ set2: Set<String>) -> Double {
        let intersection = set1.intersection(set2).count
        let union = set1.union(set2).count
        
        return union > 0 ? Double(intersection) / Double(union) : 0
    }
}

// MARK: - Theme Cluster

/// A semantic theme cluster
struct ThemeCluster: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var keywords: Set<String>
    var files: [ExtractedKeywords]
    var subThemes: [SubTheme]
    var fileTypeGroups: [FileTypeHint: [ExtractedKeywords]]
    
    var totalFileCount: Int {
        files.count
    }
    
    var hasSubThemes: Bool {
        !subThemes.isEmpty
    }
    
    var filenames: [String] {
        files.map { $0.original }
    }
}

// MARK: - Sub Theme

/// A sub-theme within a theme
struct SubTheme: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var keywords: Set<String>
    var files: [ExtractedKeywords]
    var fileTypeGroups: [FileTypeHint: [ExtractedKeywords]]
    
    init(name: String, keywords: Set<String>, files: [ExtractedKeywords], fileTypeGroups: [FileTypeHint: [ExtractedKeywords]] = [:]) {
        self.name = name
        self.keywords = keywords
        self.files = files
        self.fileTypeGroups = fileTypeGroups
    }
    
    var totalFileCount: Int {
        files.count
    }
    
    var filenames: [String] {
        files.map { $0.original }
    }
}

