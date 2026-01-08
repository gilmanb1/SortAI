// MARK: - Confidence Service
// Combines prototype similarity, cluster density, and heuristics for categorization confidence
// Spec requirement: "ConfidenceService combining prototype similarity, cluster density, heuristics, tuned to ≥85% auto-place precision"

import Foundation

// MARK: - Confidence Configuration

struct ConfidenceConfiguration: Sendable {
    /// Weight for prototype similarity (0-1)
    let prototypeSimilarityWeight: Double
    
    /// Weight for cluster density (0-1)
    let clusterDensityWeight: Double
    
    /// Weight for extension heuristics (0-1)
    let extensionHeuristicWeight: Double
    
    /// Weight for parent folder heuristics (0-1)
    let parentFolderWeight: Double
    
    /// Threshold for auto-place (high confidence)
    let autoPlaceThreshold: Double
    
    /// Threshold for review (medium confidence)
    let reviewThreshold: Double
    
    /// Minimum confidence for any assignment
    let minimumConfidence: Double
    
    /// Target precision for auto-place decisions
    let targetPrecision: Double
    
    static let `default` = ConfidenceConfiguration(
        prototypeSimilarityWeight: 0.4,
        clusterDensityWeight: 0.25,
        extensionHeuristicWeight: 0.15,
        parentFolderWeight: 0.2,
        autoPlaceThreshold: 0.85,  // Target ≥85% precision
        reviewThreshold: 0.6,
        minimumConfidence: 0.3,
        targetPrecision: 0.85
    )
    
    static let conservative = ConfidenceConfiguration(
        prototypeSimilarityWeight: 0.5,
        clusterDensityWeight: 0.2,
        extensionHeuristicWeight: 0.1,
        parentFolderWeight: 0.2,
        autoPlaceThreshold: 0.9,
        reviewThreshold: 0.7,
        minimumConfidence: 0.4,
        targetPrecision: 0.9
    )
    
    static let aggressive = ConfidenceConfiguration(
        prototypeSimilarityWeight: 0.35,
        clusterDensityWeight: 0.3,
        extensionHeuristicWeight: 0.15,
        parentFolderWeight: 0.2,
        autoPlaceThreshold: 0.75,
        reviewThreshold: 0.5,
        minimumConfidence: 0.25,
        targetPrecision: 0.8
    )
}

// MARK: - Confidence Outcome

enum ConfidenceOutcome: String, Sendable {
    case autoPlace = "auto_place"  // High confidence - place automatically
    case review = "review"  // Medium confidence - propose for review
    case deepAnalysis = "deep_analysis"  // Low confidence - needs deep analysis
    
    var displayName: String {
        switch self {
        case .autoPlace: return "Auto-Place"
        case .review: return "Review"
        case .deepAnalysis: return "Deep Analysis"
        }
    }
}

// MARK: - Confidence Result

struct ConfidenceResult: Sendable {
    /// Overall confidence score (0-1)
    let confidence: Double
    
    /// Categorization outcome based on confidence
    let outcome: ConfidenceOutcome
    
    /// Breakdown of confidence components
    let breakdown: ConfidenceBreakdown
    
    /// Predicted category path
    let categoryPath: String?
    
    /// Human-readable explanation
    let explanation: String
}

struct ConfidenceBreakdown: Sendable {
    let prototypeSimilarity: Double
    let clusterDensity: Double
    let extensionBonus: Double
    let parentFolderBonus: Double
    let adjustedScore: Double
}

// MARK: - Confidence Service

/// Service for calculating calibrated confidence scores
actor ConfidenceService {
    
    private let config: ConfidenceConfiguration
    private let prototypeStore: PrototypeStore
    
    // Calibration statistics
    private var totalPredictions: Int = 0
    private var correctPredictions: Int = 0
    private var autoPlacePredictions: Int = 0
    private var autoPlaceCorrect: Int = 0
    
    // Extension category mappings
    private let extensionCategories: [String: [String]] = [
        "Documents": ["pdf", "doc", "docx", "txt", "rtf", "odt", "pages", "md", "tex"],
        "Spreadsheets": ["xls", "xlsx", "csv", "numbers", "ods"],
        "Presentations": ["ppt", "pptx", "key", "odp"],
        "Images": ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "svg", "raw", "cr2", "nef"],
        "Videos": ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v"],
        "Audio": ["mp3", "wav", "aac", "flac", "m4a", "ogg", "wma", "aiff"],
        "Archives": ["zip", "rar", "7z", "tar", "gz", "bz2", "dmg", "iso"],
        "Code": ["swift", "py", "js", "ts", "java", "c", "cpp", "h", "rb", "go", "rs", "kt"],
        "Data": ["json", "xml", "yaml", "yml", "plist", "sqlite", "db"],
        "Ebooks": ["epub", "mobi", "azw", "azw3", "fb2"]
    ]
    
    // MARK: - Initialization
    
    init(prototypeStore: PrototypeStore, configuration: ConfidenceConfiguration = .default) {
        self.prototypeStore = prototypeStore
        self.config = configuration
    }
    
    // MARK: - Main Confidence Calculation
    
    /// Calculate confidence for categorizing a file
    func calculateConfidence(
        embedding: [Float],
        filename: String,
        parentFolder: String? = nil,
        fileExtension: String? = nil,
        clusterDensity: Double? = nil
    ) async throws -> ConfidenceResult {
        
        // 1. Prototype similarity
        let prototypeResult = try await calculatePrototypeSimilarity(embedding)
        
        // 2. Cluster density (if available)
        let densityScore = clusterDensity ?? 0.5
        
        // 3. Extension heuristics
        let extensionResult = calculateExtensionBonus(
            fileExtension: fileExtension,
            suggestedCategory: prototypeResult.categoryPath
        )
        
        // 4. Parent folder heuristics
        let parentBonus = calculateParentFolderBonus(
            parentFolder: parentFolder,
            suggestedCategory: prototypeResult.categoryPath
        )
        
        // 5. Combine scores with weights
        let weightedScore = (
            prototypeResult.similarity * config.prototypeSimilarityWeight +
            densityScore * config.clusterDensityWeight +
            extensionResult.bonus * config.extensionHeuristicWeight +
            parentBonus * config.parentFolderWeight
        )
        
        // 6. Apply calibration adjustments
        let calibratedScore = calibrateScore(weightedScore)
        
        // 7. Determine outcome
        let outcome = determineOutcome(calibratedScore)
        
        // 8. Generate explanation
        let explanation = generateExplanation(
            prototypeResult: prototypeResult,
            extensionResult: extensionResult,
            parentBonus: parentBonus,
            densityScore: densityScore,
            finalScore: calibratedScore,
            outcome: outcome
        )
        
        let breakdown = ConfidenceBreakdown(
            prototypeSimilarity: prototypeResult.similarity,
            clusterDensity: densityScore,
            extensionBonus: extensionResult.bonus,
            parentFolderBonus: parentBonus,
            adjustedScore: calibratedScore
        )
        
        return ConfidenceResult(
            confidence: calibratedScore,
            outcome: outcome,
            breakdown: breakdown,
            categoryPath: prototypeResult.categoryPath,
            explanation: explanation
        )
    }
    
    // MARK: - Prototype Similarity
    
    private func calculatePrototypeSimilarity(_ embedding: [Float]) async throws -> (categoryPath: String?, similarity: Double) {
        let matches = try await prototypeStore.findSimilar(to: embedding, k: 1, minSimilarity: 0.2)
        
        guard let best = matches.first else {
            return (nil, 0.0)
        }
        
        return (best.prototype.categoryPath, best.similarity)
    }
    
    // MARK: - Extension Heuristics
    
    private func calculateExtensionBonus(fileExtension: String?, suggestedCategory: String?) -> (bonus: Double, matchedCategory: String?) {
        guard let ext = fileExtension?.lowercased() else {
            return (0.0, nil)
        }
        
        // Find which category this extension belongs to
        for (category, extensions) in extensionCategories {
            if extensions.contains(ext) {
                // Check if suggested category matches extension category
                if let suggested = suggestedCategory {
                    let suggestedLower = suggested.lowercased()
                    let categoryLower = category.lowercased()
                    
                    if suggestedLower.contains(categoryLower) || categoryLower.contains(suggestedLower) {
                        return (1.0, category)  // Perfect match
                    }
                }
                return (0.5, category)  // Extension known but category mismatch
            }
        }
        
        return (0.3, nil)  // Unknown extension
    }
    
    // MARK: - Parent Folder Heuristics
    
    private func calculateParentFolderBonus(parentFolder: String?, suggestedCategory: String?) -> Double {
        guard let parent = parentFolder, let suggested = suggestedCategory else {
            return 0.0
        }
        
        let parentLower = parent.lowercased()
        let suggestedComponents = suggested.lowercased().components(separatedBy: "/")
        
        // Check if parent folder name matches any category component
        for component in suggestedComponents {
            if parentLower.contains(component) || component.contains(parentLower) {
                return 0.8  // Parent folder aligns with suggestion
            }
        }
        
        // Check for semantic overlap
        let parentWords = Set(parentLower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        let categoryWords = Set(suggestedComponents.flatMap { $0.components(separatedBy: CharacterSet.alphanumerics.inverted) }.filter { !$0.isEmpty })
        
        let overlap = parentWords.intersection(categoryWords)
        if !overlap.isEmpty {
            return 0.5  // Some semantic overlap
        }
        
        return 0.2  // No match but parent exists
    }
    
    // MARK: - Calibration
    
    private func calibrateScore(_ rawScore: Double) -> Double {
        // Apply sigmoid-like calibration to compress scores toward decision boundaries
        // This helps achieve the target precision
        
        let normalized = max(0, min(1, rawScore))
        
        // Platt scaling approximation
        // Maps raw scores to calibrated probabilities
        let a: Double = 2.5  // Steepness
        let b: Double = 0.5  // Center point
        
        let calibrated = 1.0 / (1.0 + exp(-a * (normalized - b)))
        
        // Scale to [minimumConfidence, 1.0]
        return config.minimumConfidence + calibrated * (1.0 - config.minimumConfidence)
    }
    
    private func determineOutcome(_ confidence: Double) -> ConfidenceOutcome {
        if confidence >= config.autoPlaceThreshold {
            return .autoPlace
        } else if confidence >= config.reviewThreshold {
            return .review
        } else {
            return .deepAnalysis
        }
    }
    
    // MARK: - Explanation Generation
    
    private func generateExplanation(
        prototypeResult: (categoryPath: String?, similarity: Double),
        extensionResult: (bonus: Double, matchedCategory: String?),
        parentBonus: Double,
        densityScore: Double,
        finalScore: Double,
        outcome: ConfidenceOutcome
    ) -> String {
        var parts: [String] = []
        
        // Prototype match
        if let category = prototypeResult.categoryPath {
            let simPercent = Int(prototypeResult.similarity * 100)
            parts.append("Similar to '\(category)' (\(simPercent)% match)")
        } else {
            parts.append("No similar category found")
        }
        
        // Extension info
        if let extCategory = extensionResult.matchedCategory {
            if extensionResult.bonus > 0.7 {
                parts.append("File type confirms '\(extCategory)'")
            } else {
                parts.append("File type suggests '\(extCategory)'")
            }
        }
        
        // Parent folder
        if parentBonus > 0.5 {
            parts.append("Folder context supports suggestion")
        }
        
        // Final decision
        let confidencePercent = Int(finalScore * 100)
        switch outcome {
        case .autoPlace:
            parts.append("Confidence: \(confidencePercent)% - Will place automatically")
        case .review:
            parts.append("Confidence: \(confidencePercent)% - Needs review")
        case .deepAnalysis:
            parts.append("Confidence: \(confidencePercent)% - Requires deeper analysis")
        }
        
        return parts.joined(separator: ". ")
    }
    
    // MARK: - Feedback & Calibration
    
    /// Record prediction outcome for calibration
    func recordOutcome(wasCorrect: Bool, wasAutoPlace: Bool) {
        totalPredictions += 1
        if wasCorrect {
            correctPredictions += 1
        }
        
        if wasAutoPlace {
            autoPlacePredictions += 1
            if wasCorrect {
                autoPlaceCorrect += 1
            }
        }
    }
    
    /// Get current precision statistics
    func getPrecisionStatistics() -> PrecisionStatistics {
        let overallPrecision = totalPredictions > 0 
            ? Double(correctPredictions) / Double(totalPredictions) 
            : 0.0
        
        let autoPlacePrecision = autoPlacePredictions > 0 
            ? Double(autoPlaceCorrect) / Double(autoPlacePredictions) 
            : 0.0
        
        return PrecisionStatistics(
            totalPredictions: totalPredictions,
            correctPredictions: correctPredictions,
            overallPrecision: overallPrecision,
            autoPlacePredictions: autoPlacePredictions,
            autoPlaceCorrect: autoPlaceCorrect,
            autoPlacePrecision: autoPlacePrecision,
            meetsTarget: autoPlacePrecision >= config.targetPrecision
        )
    }
    
    /// Reset calibration statistics
    func resetStatistics() {
        totalPredictions = 0
        correctPredictions = 0
        autoPlacePredictions = 0
        autoPlaceCorrect = 0
    }
}

// MARK: - Precision Statistics

struct PrecisionStatistics: Sendable {
    let totalPredictions: Int
    let correctPredictions: Int
    let overallPrecision: Double
    let autoPlacePredictions: Int
    let autoPlaceCorrect: Int
    let autoPlacePrecision: Double
    let meetsTarget: Bool
}

// MARK: - Batch Processing Extension

extension ConfidenceService {
    
    /// Calculate confidence for multiple files
    func calculateBatch(
        files: [(embedding: [Float], filename: String, parentFolder: String?, extension: String?)],
        clusterDensities: [Double]? = nil
    ) async throws -> [ConfidenceResult] {
        var results: [ConfidenceResult] = []
        
        for (index, file) in files.enumerated() {
            let density = clusterDensities?[safe: index]
            let result = try await calculateConfidence(
                embedding: file.embedding,
                filename: file.filename,
                parentFolder: file.parentFolder,
                fileExtension: file.extension,
                clusterDensity: density
            )
            results.append(result)
        }
        
        return results
    }
    
    /// Group files by outcome
    func groupByOutcome(_ results: [ConfidenceResult]) -> [ConfidenceOutcome: [ConfidenceResult]] {
        Dictionary(grouping: results, by: { $0.outcome })
    }
}

// MARK: - Array Safe Index

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

