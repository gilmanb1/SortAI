// MARK: - Background Analysis Manager
// Manages continuous background deep analysis with auto-recategorization

import Foundation

// MARK: - Analysis Event

/// Events emitted during background analysis
enum AnalysisEvent: Sendable {
    case started
    case fileAnalyzed(filename: String, newCategory: [String], confidence: Double)
    case fileRecategorized(filename: String, fromCategory: [String], toCategory: [String])
    case progressUpdated(analyzed: Int, total: Int, phase: AnalysisPhase)
    case completed(summary: AnalysisSummary)
    case error(filename: String, error: String)
    
    enum AnalysisPhase: String, Sendable {
        case scanning = "Scanning files..."
        case quickAnalysis = "Quick analysis..."
        case deepAnalysis = "Deep content analysis..."
        case recategorizing = "Updating categories..."
        case idle = "Idle"
    }
}

/// Summary of a completed analysis session
struct AnalysisSummary: Sendable {
    let totalAnalyzed: Int
    let recategorized: Int
    let improved: Int
    let failed: Int
    let duration: TimeInterval
}

// MARK: - Background Analysis Manager

/// Manages continuous background analysis of files
/// Runs as a third pass, analyzing files based on content and automatically updating taxonomy
@MainActor
@Observable
final class BackgroundAnalysisManager {
    
    // MARK: - State
    
    var isRunning: Bool = false
    var currentPhase: AnalysisEvent.AnalysisPhase = .idle
    var progress: Double = 0
    var currentFile: String = ""
    var analyzedCount: Int = 0
    var totalCount: Int = 0
    var recategorizedCount: Int = 0
    
    // Queue of files to analyze (prioritized by confidence)
    private var analysisQueue: [QueuedFile] = []
    
    // MARK: - Dependencies
    
    private let deepAnalyzer: DeepAnalyzer
    private var taxonomy: TaxonomyTree?
    private var eventCallback: ((AnalysisEvent) -> Void)?
    private var analysisTask: Task<Void, Never>?
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// Delay between file analyses (to not overload system)
        let delayBetweenFiles: TimeInterval
        
        /// Maximum files to analyze per session
        let maxFilesPerSession: Int
        
        /// Whether to auto-recategorize files
        let autoRecategorize: Bool
        
        /// Minimum confidence improvement to trigger recategorization
        let minConfidenceImprovement: Double
        
        static let `default` = Configuration(
            delayBetweenFiles: 0.5,
            maxFilesPerSession: 100,
            autoRecategorize: true,
            minConfidenceImprovement: 0.15
        )
    }
    
    private let config: Configuration
    
    // MARK: - Types
    
    private struct QueuedFile: Sendable {
        let file: TaxonomyScannedFile
        let currentConfidence: Double
        let currentCategory: [String]
        let priority: Int  // Lower = higher priority
    }
    
    // MARK: - Initialization
    
    init(
        deepAnalyzer: DeepAnalyzer,
        configuration: Configuration = .default
    ) {
        self.deepAnalyzer = deepAnalyzer
        self.config = configuration
    }
    
    // MARK: - Public Methods
    
    /// Start background analysis for files in the taxonomy
    func start(
        files: [TaxonomyScannedFile],
        taxonomy: TaxonomyTree,
        onEvent: @escaping (AnalysisEvent) -> Void
    ) {
        guard !isRunning else { 
            NSLog("⚠️ [BGAnalysis] Already running, ignoring start request")
            return 
        }
        
        NSLog("🔄 [BGAnalysis] Starting background analysis...")
        NSLog("🔄 [BGAnalysis] Files to analyze: \(files.count)")
        
        self.taxonomy = taxonomy
        self.eventCallback = onEvent
        self.isRunning = true
        self.currentPhase = .scanning
        
        // Build prioritized queue
        buildAnalysisQueue(files: files, taxonomy: taxonomy)
        
        NSLog("🔄 [BGAnalysis] Queue built: \(analysisQueue.count) files need analysis")
        
        totalCount = min(analysisQueue.count, config.maxFilesPerSession)
        analyzedCount = 0
        recategorizedCount = 0
        
        eventCallback?(.started)
        
        // Start async analysis
        analysisTask = Task {
            await runAnalysis()
        }
    }
    
    /// Stop the background analysis
    func stop() {
        NSLog("🛑 [BGAnalysis] Stopping...")
        analysisTask?.cancel()
        analysisTask = nil
        isRunning = false
        currentPhase = .idle
    }
    
    /// Pause analysis (can be resumed)
    func pause() {
        NSLog("⏸️ [BGAnalysis] Pausing...")
        analysisTask?.cancel()
        analysisTask = nil
        // Keep isRunning true so it can be resumed
    }
    
    /// Resume paused analysis
    func resume() {
        guard isRunning && analysisTask == nil else { return }
        NSLog("▶️ [BGAnalysis] Resuming...")
        analysisTask = Task {
            await runAnalysis()
        }
    }
    
    // MARK: - Private Methods
    
    /// Build the analysis queue, prioritizing low-confidence files
    private func buildAnalysisQueue(files: [TaxonomyScannedFile], taxonomy: TaxonomyTree) {
        analysisQueue = []
        
        // Get all file assignments from taxonomy
        let allAssignments = taxonomy.allAssignments()
        let assignmentMap = Dictionary(
            allAssignments.map { ($0.fileId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        
        for file in files {
            let assignment = assignmentMap[file.id]
            let confidence = assignment?.confidence ?? 0.5
            let needsAnalysis = assignment?.needsDeepAnalysis ?? (confidence < 0.75)
            
            if needsAnalysis || confidence < 0.75 {
                // Find the category path
                var categoryPath: [String] = []
                if let catId = assignment?.categoryId,
                   let node = taxonomy.node(byId: catId) {
                    categoryPath = taxonomy.pathToNode(node).map { $0.name }
                }
                
                // Priority: lower confidence = higher priority
                let priority = Int((1.0 - confidence) * 100)
                
                analysisQueue.append(QueuedFile(
                    file: file,
                    currentConfidence: confidence,
                    currentCategory: categoryPath,
                    priority: priority
                ))
            }
        }
        
        // Sort by priority (highest first)
        analysisQueue.sort { $0.priority > $1.priority }
    }
    
    /// Main analysis loop
    private func runAnalysis() async {
        NSLog("🔄 [BGAnalysis] Analysis loop starting...")
        
        currentPhase = .quickAnalysis
        eventCallback?(.progressUpdated(analyzed: 0, total: totalCount, phase: currentPhase))
        
        // Get existing categories for LLM prompt
        let existingCategories = taxonomy?.allCategories().map { $0.name } ?? []
        
        for (index, queuedFile) in analysisQueue.prefix(config.maxFilesPerSession).enumerated() {
            guard !Task.isCancelled else { 
                NSLog("🛑 [BGAnalysis] Cancelled at file \(index)")
                break 
            }
            
            currentFile = queuedFile.file.filename
            progress = Double(index) / Double(totalCount)
            
            NSLog("🔍 [BGAnalysis] [\(index + 1)/\(totalCount)] Analyzing: \(queuedFile.file.filename) (current confidence: \(String(format: "%.0f", queuedFile.currentConfidence * 100))%)")
            
            do {
                // Perform deep analysis
                currentPhase = .deepAnalysis
                let result = try await deepAnalyzer.analyze(
                    file: queuedFile.file,
                    existingCategories: existingCategories
                )
                
                analyzedCount += 1
                
                eventCallback?(.fileAnalyzed(
                    filename: queuedFile.file.filename,
                    newCategory: result.categoryPath,
                    confidence: result.confidence
                ))
                
                // Check if recategorization is warranted
                let confidenceImproved = result.confidence > queuedFile.currentConfidence + config.minConfidenceImprovement
                let categoryChanged = result.categoryPath != queuedFile.currentCategory
                
                if config.autoRecategorize && (confidenceImproved || categoryChanged) && result.confidence > queuedFile.currentConfidence {
                    NSLog("📁 [BGAnalysis] Recategorizing: \(queuedFile.file.filename)")
                    NSLog("📁 [BGAnalysis]   From: \(queuedFile.currentCategory.joined(separator: "/"))")
                    NSLog("📁 [BGAnalysis]   To: \(result.categoryPath.joined(separator: "/"))")
                    NSLog("📁 [BGAnalysis]   Confidence: \(String(format: "%.0f", queuedFile.currentConfidence * 100))% → \(String(format: "%.0f", result.confidence * 100))%")
                    
                    currentPhase = .recategorizing
                    
                    // Update taxonomy
                    await recategorizeFile(
                        fileId: queuedFile.file.id,
                        url: queuedFile.file.url,
                        filename: queuedFile.file.filename,
                        toCategoryPath: result.categoryPath,
                        confidence: result.confidence
                    )
                    
                    recategorizedCount += 1
                    
                    eventCallback?(.fileRecategorized(
                        filename: queuedFile.file.filename,
                        fromCategory: queuedFile.currentCategory,
                        toCategory: result.categoryPath
                    ))
                }
                
                eventCallback?(.progressUpdated(
                    analyzed: analyzedCount,
                    total: totalCount,
                    phase: currentPhase
                ))
                
            } catch {
                NSLog("❌ [BGAnalysis] Failed: \(queuedFile.file.filename) - \(error.localizedDescription)")
                eventCallback?(.error(filename: queuedFile.file.filename, error: error.localizedDescription))
            }
            
            // Delay between files to not overload system
            if !Task.isCancelled {
                try? await Task.sleep(for: .seconds(config.delayBetweenFiles))
            }
        }
        
        // Complete
        let summary = AnalysisSummary(
            totalAnalyzed: analyzedCount,
            recategorized: recategorizedCount,
            improved: recategorizedCount,
            failed: totalCount - analyzedCount,
            duration: 0 // Could track actual duration
        )
        
        NSLog("✅ [BGAnalysis] Complete!")
        NSLog("✅ [BGAnalysis] Analyzed: \(analyzedCount), Recategorized: \(recategorizedCount)")
        
        currentPhase = .idle
        isRunning = false
        eventCallback?(.completed(summary: summary))
    }
    
    /// Update taxonomy with new categorization
    private func recategorizeFile(
        fileId: UUID,
        url: URL,
        filename: String,
        toCategoryPath: [String],
        confidence: Double
    ) async {
        guard let taxonomy = taxonomy else { return }
        
        // Remove from current location
        removeFileFromTree(fileId: fileId, node: taxonomy.root)
        
        // Add to new location
        let targetNode = taxonomy.findOrCreate(path: toCategoryPath)
        
        let newAssignment = FileAssignment(
            id: UUID(),
            fileId: fileId,
            categoryId: targetNode.id,
            url: url,
            filename: filename,
            confidence: confidence,
            needsDeepAnalysis: false,  // Already analyzed
            source: .content  // From deep content analysis
        )
        
        targetNode.assign(file: newAssignment)
        targetNode.refinementState = .refined  // Mark as refined
    }
    
    /// Remove a file from the taxonomy tree
    private func removeFileFromTree(fileId: UUID, node: TaxonomyNode) {
        node.unassign(fileId: fileId)
        for child in node.children {
            removeFileFromTree(fileId: fileId, node: child)
        }
    }
}

