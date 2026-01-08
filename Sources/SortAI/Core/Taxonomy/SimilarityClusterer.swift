// MARK: - Similarity Clusterer
// Clusters filenames by keyword similarity using Jaccard + Levenshtein

import Foundation

// MARK: - Similarity Clusterer

/// Clusters files based on keyword similarity
actor SimilarityClusterer {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// Target number of clusters (5-10 default, adjustable)
        let targetClusterCount: Int
        
        /// Minimum Jaccard similarity to consider files related
        let minJaccardSimilarity: Double
        
        /// Levenshtein threshold for edge case matching (0-1 normalized)
        let levenshteinThreshold: Double
        
        /// Minimum files per cluster
        let minFilesPerCluster: Int
        
        /// Maximum files per cluster before splitting
        let maxFilesPerCluster: Int
        
        static let `default` = Configuration(
            targetClusterCount: 7,
            minJaccardSimilarity: 0.2,
            levenshteinThreshold: 0.7,
            minFilesPerCluster: 2,
            maxFilesPerCluster: 50
        )
        
        static func withTargetCount(_ count: Int) -> Configuration {
            Configuration(
                targetClusterCount: max(3, min(count, 20)),
                minJaccardSimilarity: 0.2,
                levenshteinThreshold: 0.7,
                minFilesPerCluster: 2,
                maxFilesPerCluster: 50
            )
        }
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .default) {
        self.config = configuration
    }
    
    // MARK: - Clustering
    
    /// Cluster extracted keywords into groups
    func cluster(keywords: [ExtractedKeywords]) -> [FileCluster] {
        guard !keywords.isEmpty else { return [] }
        
        // Phase 1: Group by file type first
        let typeGroups = Dictionary(grouping: keywords) { $0.fileType }
        
        // Phase 2: Within each type, cluster by keyword similarity
        var clusters: [FileCluster] = []
        
        for (fileType, files) in typeGroups {
            let typeClusters = clusterByKeywords(files, baseType: fileType)
            clusters.append(contentsOf: typeClusters)
        }
        
        // Phase 3: Merge small clusters
        clusters = mergeSmallClusters(clusters)
        
        // Phase 4: Split large clusters
        clusters = splitLargeClusters(clusters)
        
        // Phase 5: Generate cluster names
        clusters = clusters.map { generateClusterName($0) }
        
        // Sort by file count (largest first)
        clusters.sort { $0.files.count > $1.files.count }
        
        return clusters
    }
    
    // MARK: - Keyword-Based Clustering
    
    /// Cluster files within a type by keyword similarity
    private func clusterByKeywords(_ files: [ExtractedKeywords], baseType: FileTypeHint) -> [FileCluster] {
        guard files.count > 1 else {
            return files.isEmpty ? [] : [FileCluster(
                id: UUID(),
                name: baseType.displayName,
                suggestedName: nil,
                files: files,
                commonKeywords: files.first?.keywords ?? [],
                fileType: baseType,
                state: .initial
            )]
        }
        
        // Build similarity matrix using Jaccard
        var assigned = Set<UUID>()
        var clusters: [FileCluster] = []
        
        // Greedy clustering: start with most keyword-rich files
        let sorted = files.sorted { $0.keywords.count > $1.keywords.count }
        
        for file in sorted {
            guard !assigned.contains(file.id) else { continue }
            
            // Find all similar files
            var clusterFiles = [file]
            var clusterKeywords = file.keywords
            assigned.insert(file.id)
            
            for other in sorted {
                guard !assigned.contains(other.id) else { continue }
                
                // Calculate Jaccard similarity
                let jaccard = jaccardSimilarity(file.keywords, other.keywords)
                
                // If Jaccard is low, try Levenshtein on original filename
                var isSimilar = jaccard >= config.minJaccardSimilarity
                
                if !isSimilar && jaccard > 0.05 {
                    // Check Levenshtein as fallback
                    let levenshtein = normalizedLevenshtein(file.original, other.original)
                    isSimilar = levenshtein >= config.levenshteinThreshold
                }
                
                if isSimilar {
                    clusterFiles.append(other)
                    clusterKeywords = clusterKeywords.union(other.keywords)
                    assigned.insert(other.id)
                }
            }
            
            // Find common keywords (appear in >50% of files)
            let commonKeywords = findCommonKeywords(in: clusterFiles)
            
            let cluster = FileCluster(
                id: UUID(),
                name: baseType.displayName,
                suggestedName: nil,
                files: clusterFiles,
                commonKeywords: commonKeywords,
                fileType: baseType,
                state: .initial
            )
            clusters.append(cluster)
        }
        
        return clusters
    }
    
    // MARK: - Similarity Calculations
    
    /// Jaccard similarity between two keyword sets
    private func jaccardSimilarity(_ set1: Set<String>, _ set2: Set<String>) -> Double {
        guard !set1.isEmpty || !set2.isEmpty else { return 0 }
        
        let intersection = set1.intersection(set2).count
        let union = set1.union(set2).count
        
        return Double(intersection) / Double(union)
    }
    
    /// Normalized Levenshtein distance (0 = different, 1 = identical)
    private func normalizedLevenshtein(_ s1: String, _ s2: String) -> Double {
        let distance = levenshteinDistance(s1.lowercased(), s2.lowercased())
        let maxLen = max(s1.count, s2.count)
        
        guard maxLen > 0 else { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLen))
    }
    
    /// Levenshtein edit distance
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        
        let m = s1Array.count
        let n = s2Array.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
    
    // MARK: - Cluster Refinement
    
    /// Find keywords that appear in >50% of cluster files
    private func findCommonKeywords(in files: [ExtractedKeywords]) -> Set<String> {
        guard files.count > 1 else {
            return files.first?.keywords ?? []
        }
        
        var keywordCounts: [String: Int] = [:]
        for file in files {
            for keyword in file.keywords {
                keywordCounts[keyword, default: 0] += 1
            }
        }
        
        let threshold = files.count / 2
        return Set(keywordCounts.filter { $0.value > threshold }.keys)
    }
    
    /// Merge clusters that are too small
    private func mergeSmallClusters(_ clusters: [FileCluster]) -> [FileCluster] {
        var result: [FileCluster] = []
        var smallClusters: [FileCluster] = []
        
        for cluster in clusters {
            if cluster.files.count < config.minFilesPerCluster {
                smallClusters.append(cluster)
            } else {
                result.append(cluster)
            }
        }
        
        // Try to merge small clusters with similar ones
        for small in smallClusters {
            // Find best matching cluster
            var bestMatch: Int?
            var bestSimilarity: Double = 0
            
            for (index, cluster) in result.enumerated() {
                guard cluster.fileType == small.fileType else { continue }
                
                let similarity = jaccardSimilarity(cluster.commonKeywords, small.commonKeywords)
                if similarity > bestSimilarity && similarity > 0.1 {
                    bestSimilarity = similarity
                    bestMatch = index
                }
            }
            
            if let matchIndex = bestMatch {
                // Merge into best match
                var mergedCluster = result[matchIndex]
                mergedCluster.files.append(contentsOf: small.files)
                mergedCluster.commonKeywords = mergedCluster.commonKeywords.union(small.commonKeywords)
                result[matchIndex] = mergedCluster
            } else {
                // Create "Other" cluster for unmatched
                result.append(small)
            }
        }
        
        return result
    }
    
    /// Split clusters that are too large
    private func splitLargeClusters(_ clusters: [FileCluster]) -> [FileCluster] {
        var result: [FileCluster] = []
        
        for cluster in clusters {
            if cluster.files.count > config.maxFilesPerCluster {
                // Split by secondary keywords
                let subClusters = splitCluster(cluster)
                result.append(contentsOf: subClusters)
            } else {
                result.append(cluster)
            }
        }
        
        return result
    }
    
    /// Split a large cluster into smaller ones
    private func splitCluster(_ cluster: FileCluster) -> [FileCluster] {
        // Re-cluster with stricter similarity threshold
        let subClusters = clusterByKeywords(cluster.files, baseType: cluster.fileType)
        
        // If we couldn't split meaningfully, return original
        if subClusters.count <= 1 {
            return [cluster]
        }
        
        return subClusters
    }
    
    // MARK: - Name Generation
    
    /// Generate a descriptive name for a cluster
    private func generateClusterName(_ cluster: FileCluster) -> FileCluster {
        var updated = cluster
        
        // Use most common keywords to create name
        let topKeywords = cluster.commonKeywords
            .sorted { $0.count > $1.count }
            .prefix(3)
        
        if !topKeywords.isEmpty {
            let keywordName = topKeywords
                .map { $0.capitalized }
                .joined(separator: " ")
            
            // Combine with file type
            updated.name = "\(cluster.fileType.displayName) - \(keywordName)"
            updated.suggestedName = keywordName
        } else {
            updated.name = cluster.fileType.displayName
        }
        
        return updated
    }
}

// MARK: - File Cluster

/// A cluster of related files
struct FileCluster: Identifiable, Sendable {
    let id: UUID
    var name: String
    var suggestedName: String?
    var files: [ExtractedKeywords]
    var commonKeywords: Set<String>
    let fileType: FileTypeHint
    var state: ClusterState
    
    enum ClusterState: String, Sendable {
        case initial       // Just created from rule-based pass
        case refining      // LLM is refining
        case refined       // LLM has refined
        case userEdited    // User has manually edited (locked from LLM)
    }
    
    var fileCount: Int { files.count }
    
    var filenames: [String] {
        files.map { $0.original }
    }
}

