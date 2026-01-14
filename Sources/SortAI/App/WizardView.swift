// MARK: - Sort Wizard View
// First-time experience and guided file organization workflow

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Wizard Step

enum WizardStep: Int, CaseIterable {
    case selectFolder
    case scanning
    case inferring
    case verifyHierarchy
    case resolveConflicts
    case organizing
    case complete
    
    var title: String {
        switch self {
        case .selectFolder: return "Select Folder"
        case .scanning: return "Scanning Files"
        case .inferring: return "Analyzing Names"
        case .verifyHierarchy: return "Verify Hierarchy"
        case .resolveConflicts: return "Resolve Conflicts"
        case .organizing: return "Organizing"
        case .complete: return "Complete"
        }
    }
    
    var description: String {
        switch self {
        case .selectFolder: return "Choose a folder to organize"
        case .scanning: return "Finding all files..."
        case .inferring: return "AI is inferring categories from filenames..."
        case .verifyHierarchy: return "Review and adjust the suggested organization"
        case .resolveConflicts: return "Resolve file conflicts before organizing"
        case .organizing: return "Moving files into folders..."
        case .complete: return "Your files have been organized!"
        }
    }
    
    var icon: String {
        switch self {
        case .selectFolder: return "folder.badge.plus"
        case .scanning: return "magnifyingglass"
        case .inferring: return "brain"
        case .verifyHierarchy: return "checkmark.circle"
        case .resolveConflicts: return "exclamationmark.triangle"
        case .organizing: return "arrow.right.arrow.left"
        case .complete: return "checkmark.seal.fill"
        }
    }
}

// MARK: - Wizard State

@Observable
@MainActor
final class WizardState {
    
    // MARK: - Properties
    
    var currentStep: WizardStep = .selectFolder
    var selectedFolder: URL?
    var useRootAsCategory: Bool = true
    var outputFolder: URL?
    
    // Scanning
    var scanResult: TaxonomyScanResult?
    var scanProgress: Double = 0
    
    // Taxonomy
    var taxonomy: TaxonomyTree?
    var inferenceProgress: Double = 0
    
    // Organization
    var organizationPlan: OrganizationPlan?
    var organizationConflicts: [OrganizationConflict] = []
    var organizationResult: WizardOrganizationResult?
    var organizationProgress: Double = 0
    var organizedCount: Int = 0
    var totalToOrganize: Int = 0
    var conflicts: [FileConflict] = []
    var currentOrgFile: String = ""
    
    // Status
    var isProcessing: Bool = false
    var errorMessage: String?
    var statusMessage: String = ""
    
    // Deep analysis
    var enableDeepAnalysis: Bool = false
    var confidenceThreshold: Double = 0.75
    var deepAnalysisResults: [DeepAnalysisResult] = []
    var isPerformingDeepAnalysis: Bool = false
    
    // Background analysis (continuous third pass)
    var isBackgroundAnalysisRunning: Bool = false
    var backgroundAnalysisPhase: String = "Idle"
    var backgroundAnalysisProgress: Double = 0
    var backgroundAnalyzedCount: Int = 0
    var backgroundRecategorizedCount: Int = 0
    var backgroundCurrentFile: String = ""
    
    // Taxonomy refinement (Phase 2)
    var isRefining: Bool = false
    var refinementProgress: RefinementProgress?
    var targetCategoryCount: Int = 7  // User preference slider
    var separateFileTypes: Bool = true  // Separate Videos, PDFs, etc. within themes
    
    // MARK: - Computed
    
    var canProceed: Bool {
        switch currentStep {
        case .selectFolder:
            return selectedFolder != nil && outputFolder != nil
        case .scanning:
            return scanResult != nil
        case .inferring:
            return taxonomy != nil
        case .verifyHierarchy:
            // User can proceed once taxonomy exists (they can edit while refinement continues)
            return taxonomy != nil && !isProcessing
        case .resolveConflicts:
            // Can proceed when all conflicts have non-askUser resolutions
            return organizationConflicts.allSatisfy { $0.resolution != .askUser }
        case .organizing:
            return !isProcessing
        case .complete:
            return true
        }
    }
    
    var hasConflicts: Bool {
        organizationPlan?.hasConflicts == true
    }
    
    var progressPercentage: Double {
        switch currentStep {
        case .selectFolder: return 0
        case .scanning: return scanProgress
        case .inferring: return inferenceProgress
        case .verifyHierarchy: return 0.6
        case .resolveConflicts: return 0.7
        case .organizing: return organizationProgress
        case .complete: return 1.0
        }
    }
    
    // MARK: - Actions
    
    func reset() {
        currentStep = .selectFolder
        selectedFolder = nil
        outputFolder = nil
        scanResult = nil
        taxonomy = nil
        organizationPlan = nil
        organizationConflicts = []
        organizationResult = nil
        scanProgress = 0
        inferenceProgress = 0
        organizationProgress = 0
        organizedCount = 0
        totalToOrganize = 0
        conflicts = []
        currentOrgFile = ""
        isProcessing = false
        errorMessage = nil
        statusMessage = ""
        deepAnalysisResults = []
        isPerformingDeepAnalysis = false
    }
    
    func goBack() {
        guard let prevStep = WizardStep(rawValue: currentStep.rawValue - 1) else { return }
        
        // Handle specific step transitions that need state clearing
        switch currentStep {
        case .verifyHierarchy:
            // Going back from verify should let user change options and re-infer
            // Clear taxonomy so inference runs again
            taxonomy = nil
            inferenceProgress = 0
            deepAnalysisResults = []
            isRefining = false
            refinementProgress = nil
            // Go back to selectFolder so they can change options
            currentStep = .selectFolder
            return
            
        case .inferring:
            // Going back from inferring clears scan to rescan
            taxonomy = nil
            scanResult = nil
            scanProgress = 0
            currentStep = .selectFolder
            return
            
        case .organizing:
            // Can't go back during organization
            return
            
        default:
            break
        }
        
        currentStep = prevStep
    }
    
    /// Reset taxonomy to re-infer with new options (called from verify step)
    func reInferTaxonomy() {
        taxonomy = nil
        inferenceProgress = 0
        deepAnalysisResults = []
        isRefining = false
        refinementProgress = nil
        currentStep = .inferring
    }
    
    func goNext() {
        guard let nextStep = WizardStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = nextStep
    }
    
    func skipToOrganizing() {
        currentStep = .organizing
    }
}

// MARK: - File Conflict

struct FileConflict: Identifiable, Sendable {
    let id: UUID
    let sourceURL: URL
    let destinationURL: URL
    var resolution: Resolution
    
    enum Resolution: String, Sendable, CaseIterable {
        case rename
        case skip
        case overwrite
        
        var displayName: String {
            switch self {
            case .rename: return "Rename"
            case .skip: return "Skip"
            case .overwrite: return "Overwrite"
            }
        }
    }
    
    init(sourceURL: URL, destinationURL: URL) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.resolution = .rename
    }
}

// MARK: - Wizard View

struct WizardView: View {
    @Bindable var state: WizardState
    @Environment(\.dismiss) private var dismiss
    
    // Services (injected or created)
    let scanner: FilenameScanner
    let fastTaxonomyBuilder: FastTaxonomyBuilder
    let inferenceEngine: TaxonomyInferenceEngine?
    let organizationEngine: OrganizationEngine
    let deepAnalyzer: DeepAnalyzer?
    let backgroundAnalysisManager: BackgroundAnalysisManager?
    let onComplete: (TaxonomyTree?) -> Void
    
    init(
        state: WizardState,
        scanner: FilenameScanner = FilenameScanner(),
        fastTaxonomyBuilder: FastTaxonomyBuilder = FastTaxonomyBuilder(),
        inferenceEngine: TaxonomyInferenceEngine? = nil,
        organizationEngine: OrganizationEngine = OrganizationEngine(),
        deepAnalyzer: DeepAnalyzer? = nil,
        backgroundAnalysisManager: BackgroundAnalysisManager? = nil,
        onComplete: @escaping (TaxonomyTree?) -> Void
    ) {
        self.state = state
        self.scanner = scanner
        self.fastTaxonomyBuilder = fastTaxonomyBuilder
        self.inferenceEngine = inferenceEngine
        self.organizationEngine = organizationEngine
        self.deepAnalyzer = deepAnalyzer
        self.backgroundAnalysisManager = backgroundAnalysisManager
        self.onComplete = onComplete
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with progress
            wizardHeader
            
            Divider()
            
            // Step content (expands to fill available space)
            ScrollView {
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Footer with navigation
            wizardFooter
        }
        // Allow resizing within bounds set by ContentView sheet
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var wizardHeader: some View {
        VStack(spacing: 16) {
            // Step indicators
            HStack(spacing: 0) {
                ForEach(Array(WizardStep.allCases.enumerated()), id: \.element.rawValue) { index, step in
                    stepIndicator(step: step, index: index)
                    
                    if index < WizardStep.allCases.count - 1 {
                        stepConnector(isActive: step.rawValue < state.currentStep.rawValue)
                    }
                }
            }
            .padding(.horizontal)
            
            // Current step info
            VStack(spacing: 4) {
                Text(state.currentStep.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(state.currentStep.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 20)
    }
    
    private func stepIndicator(step: WizardStep, index: Int) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(stepColor(for: step))
                    .frame(width: 36, height: 36)
                
                if step.rawValue < state.currentStep.rawValue {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(step == state.currentStep ? .white : .secondary)
                }
            }
            
            Text(step.title)
                .font(.caption2)
                .foregroundStyle(step == state.currentStep ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(width: 80)
    }
    
    private func stepConnector(isActive: Bool) -> some View {
        Rectangle()
            .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }
    
    private func stepColor(for step: WizardStep) -> Color {
        if step.rawValue < state.currentStep.rawValue {
            return .green
        } else if step == state.currentStep {
            return .accentColor
        } else {
            return .secondary.opacity(0.3)
        }
    }
    
    // MARK: - Step Content
    
    @ViewBuilder
    private var stepContent: some View {
        switch state.currentStep {
        case .selectFolder:
            SelectFolderStep(state: state)
        case .scanning:
            ScanningStep(state: state, scanner: scanner)
        case .inferring:
            InferringStep(state: state, fastBuilder: fastTaxonomyBuilder, legacyEngine: inferenceEngine)
        case .verifyHierarchy:
            VerifyHierarchyStep(state: state, deepAnalyzer: deepAnalyzer)
        case .resolveConflicts:
            ConflictResolutionStep(state: state)
        case .organizing:
            OrganizingStep(state: state, engine: organizationEngine)
        case .complete:
            CompleteStep(state: state)
        }
    }
    
    // MARK: - Footer
    
    private var wizardFooter: some View {
        HStack {
            // Cancel/Back
            if state.currentStep == .selectFolder {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            } else if state.currentStep != .complete && !state.isProcessing {
                Button("Back") {
                    state.goBack()
                }
            }
            
            Spacer()
            
            // Error message
            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            
            Spacer()
            
            // Next/Finish
            if state.currentStep == .complete {
                Button("Done") {
                    onComplete(state.taxonomy)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            } else if !state.isProcessing {
                Button(nextButtonTitle) {
                    handleNextAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!state.canProceed)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding()
    }
    
    private var nextButtonTitle: String {
        switch state.currentStep {
        case .selectFolder: return "Start Scanning"
        case .verifyHierarchy: return state.hasConflicts ? "Review Conflicts" : "Organize Files"
        case .resolveConflicts: return "Start Organizing"
        default: return "Continue"
        }
    }
    
    private func handleNextAction() {
        switch state.currentStep {
        case .selectFolder:
            state.goNext()
            // Scanning will start automatically in ScanningStep
        case .verifyHierarchy:
            state.taxonomy?.isVerified = true
            
            // Plan organization and check for conflicts
            Task {
                await planOrganization()
                
                await MainActor.run {
                    if state.hasConflicts {
                        state.goNext() // Go to conflict resolution
                    } else {
                        state.skipToOrganizing() // Skip to organizing
                    }
                }
            }
        case .resolveConflicts:
            state.goNext()
            // Organization will start automatically
        default:
            state.goNext()
        }
    }
    
    private func planOrganization() async {
        guard let taxonomy = state.taxonomy,
              let scanResult = state.scanResult,
              let outputFolder = state.outputFolder else { 
            NSLog("❌ [WizardPlan] Missing required data for organization planning")
            return 
        }
        
        // Get file assignments from taxonomy
        let assignments = taxonomy.allAssignments()
        
        NSLog("📋 [WizardPlan] Planning organization...")
        NSLog("📋 [WizardPlan] Files from scan: \(scanResult.files.count)")
        NSLog("📋 [WizardPlan] Assignments from taxonomy: \(assignments.count)")
        NSLog("📋 [WizardPlan] Output folder: \(outputFolder.path)")
        
        // Debug: Log first few file IDs to verify matching
        if scanResult.files.count > 0 && assignments.count > 0 {
            let firstScanId = scanResult.files.first!.id
            let firstAssignId = assignments.first!.fileId
            NSLog("📋 [WizardPlan] Sample scan file ID: \(firstScanId)")
            NSLog("📋 [WizardPlan] Sample assignment fileId: \(firstAssignId)")
        }
        
        // Plan the organization
        let plan = await organizationEngine.planOrganization(
            files: scanResult.files,
            assignments: assignments,
            tree: taxonomy,
            outputFolder: outputFolder
        )
        
        NSLog("📋 [WizardPlan] Plan created: \(plan.operations.count) operations, \(plan.conflicts.count) conflicts")
        
        // Debug: Log how many ended up as planned vs unassigned
        let plannedDests = Set(plan.operations.map { $0.destinationFolder.lastPathComponent })
        NSLog("📋 [WizardPlan] Destination folders: \(plannedDests.joined(separator: ", "))")
        
        await MainActor.run {
            state.organizationPlan = plan
            state.organizationConflicts = plan.conflicts
            state.totalToOrganize = plan.totalFiles
        }
    }
    
    // MARK: - Deep Analysis Methods
    
    private func performDeepAnalysis() async {
        guard let taxonomy = state.taxonomy,
              let scanResult = state.scanResult else { return }
        
        // Use BackgroundAnalysisManager for continuous analysis
        if let manager = backgroundAnalysisManager {
            NSLog("🔄 [WizardDeepAnalysis] Starting continuous background analysis...")
            
            await MainActor.run {
                state.isPerformingDeepAnalysis = true
                state.isBackgroundAnalysisRunning = true
            }
            
            manager.start(
                files: scanResult.files,
                taxonomy: taxonomy
            ) { [state] event in
                Task { @MainActor in
                    Self.handleAnalysisEvent(event, state: state, taxonomy: taxonomy)
                }
            }
        } else if let deepAnalyzer = deepAnalyzer {
            // Fallback to old batch analysis
            NSLog("🔄 [WizardDeepAnalysis] Falling back to batch analysis...")
            await performBatchDeepAnalysis(taxonomy: taxonomy, files: scanResult.files, analyzer: deepAnalyzer)
        }
    }
    
    @MainActor
    private static func handleAnalysisEvent(_ event: AnalysisEvent, state: WizardState, taxonomy: TaxonomyTree) {
        switch event {
        case .started:
            state.backgroundAnalysisPhase = "Starting analysis..."
            
        case .fileAnalyzed(let filename, let newCategory, let confidence):
            state.backgroundCurrentFile = filename
            state.backgroundAnalyzedCount += 1
            NSLog("📊 [BGAnalysis] Analyzed: \(filename) → \(newCategory.joined(separator: "/")) (\(Int(confidence * 100))%)")
            
        case .fileRecategorized(let filename, let fromCategory, let toCategory):
            state.backgroundRecategorizedCount += 1
            state.statusMessage = "Recategorized: \(filename)"
            NSLog("📁 [BGAnalysis] Recategorized: \(filename): \(fromCategory.joined(separator: "/")) → \(toCategory.joined(separator: "/"))")
            
            // Create a result for the UI
            let result = DeepAnalysisResult(
                filename: filename,
                categoryPath: toCategory,
                confidence: 0.9,
                rationale: "Recategorized based on content analysis",
                contentSummary: "Moved from \(fromCategory.joined(separator: "/"))",
                suggestedTags: []
            )
            state.deepAnalysisResults.append(result)
            
        case .progressUpdated(let analyzed, let total, let phase):
            state.backgroundAnalysisProgress = total > 0 ? Double(analyzed) / Double(total) : 0
            state.backgroundAnalysisPhase = phase.rawValue
            state.backgroundAnalyzedCount = analyzed
            
        case .completed(let summary):
            state.isPerformingDeepAnalysis = false
            state.isBackgroundAnalysisRunning = false
            state.backgroundAnalysisPhase = "Complete"
            state.statusMessage = "Analysis complete: \(summary.totalAnalyzed) analyzed, \(summary.recategorized) recategorized"
            NSLog("✅ [BGAnalysis] Complete - Analyzed: \(summary.totalAnalyzed), Recategorized: \(summary.recategorized)")
            
        case .error(let filename, let error):
            NSLog("❌ [BGAnalysis] Error analyzing \(filename): \(error)")
        }
    }
    
    private func performBatchDeepAnalysis(taxonomy: TaxonomyTree, files: [TaxonomyScannedFile], analyzer: DeepAnalyzer) async {
        await MainActor.run {
            state.isPerformingDeepAnalysis = true
        }
        
        // Get files needing deep analysis (low confidence)
        let lowConfFiles = files.filter { file in
            taxonomy.confidenceForFile(file.id) < state.confidenceThreshold
        }
        
        let existingCategories = taxonomy.allCategories().map { $0.name }
        
        do {
            let results = try await analyzer.analyzeFiles(
                Array(lowConfFiles.prefix(10)), // Limit batch size
                existingCategories: existingCategories
            ) { completed, total in
                Task { @MainActor in
                    state.statusMessage = "Analyzing \(completed)/\(total)..."
                }
            }
            
            await MainActor.run {
                state.deepAnalysisResults = results
                state.isPerformingDeepAnalysis = false
                
                // Apply results to taxonomy
                for result in results {
                    if let file = lowConfFiles.first(where: { $0.filename == result.filename }) {
                        taxonomy.reassignFile(
                            fileId: file.id,
                            toCategoryPath: result.categoryPath,
                            confidence: result.confidence
                        )
                    }
                }
            }
        } catch {
            await MainActor.run {
                state.errorMessage = error.localizedDescription
                state.isPerformingDeepAnalysis = false
            }
        }
    }
    
    /// Stop background analysis when leaving the wizard
    private func stopBackgroundAnalysis() {
        backgroundAnalysisManager?.stop()
        state.isBackgroundAnalysisRunning = false
    }
}

// MARK: - Step Views

struct SelectFolderStep: View {
    @Bindable var state: WizardState
    
    var body: some View {
        VStack(spacing: 24) {
            // Source folder
            GroupBox("Source Folder") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        
                        if let folder = state.selectedFolder {
                            VStack(alignment: .leading) {
                                Text(folder.lastPathComponent)
                                    .font(.headline)
                                Text(folder.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("No folder selected")
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Choose...") {
                            chooseSourceFolder()
                        }
                    }
                    
                    if state.selectedFolder != nil {
                        Toggle("Use folder name as root category", isOn: $state.useRootAsCategory)
                            .font(.caption)
                    }
                }
                .padding(8)
            }
            
            // Output folder
            GroupBox("Output Folder") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.green)
                        
                        if let folder = state.outputFolder {
                            VStack(alignment: .leading) {
                                Text(folder.lastPathComponent)
                                    .font(.headline)
                                Text(folder.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("No folder selected")
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Choose...") {
                            chooseOutputFolder()
                        }
                    }
                    
                    Text("Files will be organized into this folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            
            // Options
            GroupBox("Options") {
                VStack(alignment: .leading, spacing: 12) {
                    // Category count preference
                    HStack {
                        Text("Target categories:")
                        Slider(value: Binding(
                            get: { Double(state.targetCategoryCount) },
                            set: { state.targetCategoryCount = Int($0) }
                        ), in: 3...15, step: 1)
                        Text("\(state.targetCategoryCount)")
                            .monospacedDigit()
                            .frame(width: 30)
                    }
                    .font(.caption)
                    
                    Text("Fewer = broader categories, More = finer organization")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Divider()
                    
                    Toggle("Separate file types within themes", isOn: $state.separateFileTypes)
                    
                    Text("When enabled: Magic → Card Magic → Videos, PDFs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("When disabled: Magic → Card Magic → (all files mixed)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    Divider()
                    
                    Toggle("Enable deep analysis for low-confidence files", isOn: $state.enableDeepAnalysis)
                    
                    if state.enableDeepAnalysis {
                        HStack {
                            Text("Confidence threshold:")
                            Slider(value: $state.confidenceThreshold, in: 0.5...0.95, step: 0.05)
                            Text("\(Int(state.confidenceThreshold * 100))%")
                                .monospacedDigit()
                                .frame(width: 40)
                        }
                        .font(.caption)
                    }
                }
                .padding(8)
            }
            
            Spacer()
        }
    }
    
    private func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to organize"
        
        if panel.runModal() == .OK, let url = panel.url {
            state.selectedFolder = url
            
            // Auto-set output folder if not set
            if state.outputFolder == nil {
                state.outputFolder = url.deletingLastPathComponent()
                    .appendingPathComponent("\(url.lastPathComponent)_Organized")
            }
        }
    }
    
    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Select or create output folder"
        
        if panel.runModal() == .OK, let url = panel.url {
            state.outputFolder = url
        }
    }
}

struct ScanningStep: View {
    @Bindable var state: WizardState
    let scanner: FilenameScanner
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            ProgressView(value: state.scanProgress) {
                Text("Scanning files...")
            }
            .progressViewStyle(.linear)
            
            Text(state.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let result = state.scanResult {
                // Scan results
                GroupBox("Scan Results") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("\(result.fileCount) files found", systemImage: "doc")
                            Spacer()
                            Label("\(result.directoryCount) folders", systemImage: "folder")
                        }
                        
                        HStack {
                            Label(result.formattedTotalSize, systemImage: "externaldrive")
                            Spacer()
                            Label(String(format: "%.1fs", result.scanDuration), systemImage: "clock")
                        }
                        
                        if result.reachedLimit {
                            Label("File limit reached", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .padding(8)
                }
            }
            
            Spacer()
        }
        .task {
            await performScan()
        }
    }
    
    private func performScan() async {
        guard let folder = state.selectedFolder else {
            NSLog("❌ [WizardScan] No folder selected!")
            return
        }
        
        NSLog("📂 [WizardScan] Starting scan of: \(folder.path)")
        let scanStartTime = Date()
        
        state.isProcessing = true
        state.statusMessage = "Starting scan..."
        
        do {
            state.scanProgress = 0.1
            NSLog("📂 [WizardScan] Calling scanner.scan()...")
            let result = try await scanner.scan(folder: folder)
            
            let scanDuration = Date().timeIntervalSince(scanStartTime)
            NSLog("✅ [WizardScan] Scan completed in %.2fs", scanDuration)
            NSLog("✅ [WizardScan] Found \(result.fileCount) files, \(result.directoryCount) directories")
            
            state.scanResult = result
            state.scanProgress = 1.0
            state.statusMessage = "Found \(result.fileCount) files"
            
            // Auto-advance to next step
            try? await Task.sleep(for: .milliseconds(500))
            state.isProcessing = false
            NSLog("➡️ [WizardScan] Advancing to next step (inference)")
            state.goNext()
        } catch {
            let scanDuration = Date().timeIntervalSince(scanStartTime)
            NSLog("❌ [WizardScan] Scan FAILED after %.2fs: \(error.localizedDescription)", scanDuration)
            state.errorMessage = error.localizedDescription
            state.isProcessing = false
        }
    }
}

struct InferringStep: View {
    @Bindable var state: WizardState
    let fastBuilder: FastTaxonomyBuilder
    let legacyEngine: TaxonomyInferenceEngine?
    
    var body: some View {
        VStack(spacing: 24) {
            // Phase indicator
            HStack(spacing: 20) {
                PhaseIndicator(
                    phase: 1,
                    title: "Quick Analysis",
                    isActive: state.inferenceProgress < 0.5,
                    isComplete: state.inferenceProgress >= 0.5
                )
                
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                
                PhaseIndicator(
                    phase: 2,
                    title: "AI Refinement",
                    isActive: state.isRefining,
                    isComplete: state.refinementProgress?.isComplete == true
                )
            }
            .padding(.bottom, 8)
            
            // Progress
            ProgressView(value: state.inferenceProgress) {
                Text(state.statusMessage)
            }
            .progressViewStyle(.linear)
            
            // Refinement progress (if active)
            if state.isRefining, let progress = state.refinementProgress {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refining: \(progress.currentCategory ?? "...")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress.percentage * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                }
                .padding(.horizontal)
            }
            
            if let taxonomy = state.taxonomy {
                // Preview of inferred categories
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Categories")
                                .font(.headline)
                            Spacer()
                            Text("\(taxonomy.categoryCount) categories • \(taxonomy.totalFileCount) files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.bottom, 4)
                        
                        Divider()
                        
                        ForEach(Array(taxonomy.allCategories().prefix(10)), id: \.id) { node in
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                
                                Text(node.name)
                                    .lineLimit(1)
                                
                                // Show refinement indicator
                                if node.refinementState == .refining {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else if node.refinementState == .refined {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.blue)
                                        .font(.caption2)
                                }
                                
                                Spacer()
                                
                                Text("\(node.totalFileCount)")
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.2)))
                            }
                            .font(.caption)
                        }
                        
                        if taxonomy.categoryCount > 10 {
                            Text("... and \(taxonomy.categoryCount - 10) more categories")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(12)
                }
            }
            
            Spacer()
        }
        .task {
            await performTwoPhaseInference()
        }
    }
    
    private func performTwoPhaseInference() async {
        NSLog("⚡️ [WizardInfer] Starting TWO-PHASE inference...")
        
        guard let scanResult = state.scanResult else {
            NSLog("❌ [WizardInfer] No scan result available!")
            state.errorMessage = "No scan result available"
            return
        }
        
        let files = scanResult.files  // Pass full file objects to preserve URLs and IDs
        let rootName = state.useRootAsCategory ? state.selectedFolder?.lastPathComponent : nil
        
        NSLog("⚡️ [WizardInfer] Have \(files.count) files to process")
        
        // ========== PHASE 1: Instant Rule-Based ==========
        state.isProcessing = true
        state.statusMessage = "Quick analysis..."
        state.inferenceProgress = 0.1
        
        let phase1Start = Date()
        
        // Create builder with user's preferences
        let config = FastTaxonomyBuilder.Configuration(
            targetCategoryCount: state.targetCategoryCount,
            separateFileTypes: state.separateFileTypes,
            autoRefine: true,
            refinementModel: "llama3.2",
            refinementBatchSize: 50
        )
        let builder = FastTaxonomyBuilder(configuration: config)
        
        // This should complete in <1 second (now preserves file URLs and IDs for organization)
        let taxonomy = await builder.buildInstant(from: files, rootName: rootName)
        
        let phase1Duration = Date().timeIntervalSince(phase1Start)
        NSLog("✅ [WizardInfer] Phase 1 complete in %.3fs!", phase1Duration)
        
        await MainActor.run {
            state.taxonomy = taxonomy
            state.inferenceProgress = 0.5
            state.statusMessage = "Quick analysis complete! \(taxonomy.categoryCount) categories found."
        }
        
        // Short pause to show results
        try? await Task.sleep(for: .milliseconds(300))
        
        // ========== PHASE 2: LLM Full Hierarchy Inference ==========
        await MainActor.run {
            state.isRefining = true
            state.statusMessage = "Getting full hierarchy from AI..."
        }
        
        NSLog("🧠 [WizardInfer] ========== PHASE 2: LLM HIERARCHY INFERENCE ==========")
        let phase2Start = Date()
        
        // Get LLM provider for TaxonomyInferenceEngine
        let ollamaProvider = await LLMProviderRegistry.shared.provider(id: "ollama")
        let defaultProv = await LLMProviderRegistry.shared.defaultProvider()
        
        if let llmProvider = ollamaProvider ?? defaultProv {
            NSLog("🧠 [WizardInfer] Using LLM provider: \(llmProvider.identifier)")
            
            // Create inference engine to get full hierarchies from LLM
            let inferenceEngine = TaxonomyInferenceEngine(provider: llmProvider)
            let filenames = files.map { $0.filename }
            let options = LLMOptions.default(model: "llama3.2")
            
            do {
                // Get LLM's suggested full hierarchy structure
                let llmTaxonomy = try await inferenceEngine.inferTaxonomy(
                    from: filenames,
                    rootName: rootName,
                    options: options
                )
                
                // Build a filename -> category path lookup from LLM results
                var llmFileToPaths: [String: [String]] = [:]
                for node in llmTaxonomy.allCategories() {
                    let nodePath = node.path  // Full path like ["Work", "Job Search", "Resumes"]
                    for file in node.assignedFiles {
                        llmFileToPaths[file.filename] = nodePath
                    }
                }
                
                NSLog("🧠 [WizardInfer] LLM suggested paths for \(llmFileToPaths.count) files")
                
                // Reassign files in Phase 1 taxonomy to LLM's suggested hierarchy paths
                var reassignedCount = 0
                for assignment in taxonomy.allAssignments() {
                    if let newPath = llmFileToPaths[assignment.filename] {
                        // Get the confidence from the LLM taxonomy for this path
                        let llmConfidence = llmTaxonomy.find(path: newPath)?.confidence ?? 0.8
                        
                        taxonomy.reassignFile(
                            fileId: assignment.fileId,
                            toCategoryPath: newPath,
                            confidence: max(assignment.confidence, llmConfidence)
                        )
                        reassignedCount += 1
                    }
                }
                
                let phase2Duration = Date().timeIntervalSince(phase2Start)
                NSLog("✅ [WizardInfer] Phase 2 complete in %.2fs - reassigned \(reassignedCount) files to full hierarchies", phase2Duration)
                
                await MainActor.run {
                    state.inferenceProgress = 0.7
                    state.statusMessage = "Hierarchy inference complete! \(taxonomy.categoryCount) categories."
                }
                
            } catch {
                NSLog("⚠️ [WizardInfer] Phase 2 failed: \(error.localizedDescription) - continuing with Phase 1 results")
                await MainActor.run {
                    state.statusMessage = "AI hierarchy inference failed, using quick analysis results..."
                }
            }
        } else {
            NSLog("⚠️ [WizardInfer] No LLM provider available for Phase 2 - skipping hierarchy inference")
        }
        
        await MainActor.run {
            state.isRefining = false
            state.inferenceProgress = 0.7
        }
        
        // ========== PHASE 3: Deep Content Analysis (on ALL files) ==========
        NSLog("🔬 [WizardInfer] ========== PHASE 3: DEEP CONTENT ANALYSIS ==========")
        NSLog("🔬 [WizardInfer] Running deep analysis on ALL files for content-based categorization")
        await startFullDeepAnalysis()
        
        // Allow user to proceed after all phases complete
        await MainActor.run {
            state.isProcessing = false
            state.inferenceProgress = 1.0
            state.statusMessage = "All analysis complete!"
            NSLog("➡️ [WizardInfer] All phases complete - advancing to next step")
            state.goNext()
        }
    }
    
    /// Deep analyze ALL files using content extraction and LLM
    private func startFullDeepAnalysis() async {
        let startTime = Date()
        NSLog("🔬 [DeepAnalysis] Starting FULL deep analysis on all files...")
        
        guard let taxonomy = state.taxonomy,
              let scanResult = state.scanResult else {
            NSLog("❌ [DeepAnalysis] Cannot start - missing taxonomy or scan result")
            return
        }
        
        let allFiles = scanResult.files
        NSLog("🔬 [DeepAnalysis] Will analyze ALL \(allFiles.count) files")
        
        if allFiles.isEmpty {
            NSLog("✅ [DeepAnalysis] No files to analyze")
            return
        }
        
        await MainActor.run {
            state.isPerformingDeepAnalysis = true
            state.statusMessage = "Deep analyzing all \(allFiles.count) files..."
        }
        
        // Create deep analyzer with LLM provider
        NSLog("🔬 [DeepAnalysis] Creating DeepAnalyzer...")
        let analyzerConfig = DeepAnalyzer.Configuration(
            confidenceThreshold: 0.0,  // Analyze ALL files regardless of confidence
            maxConcurrent: 2,
            timeoutPerFile: 120.0,
            extractAudio: true,
            performOCR: true,
            useHybridExtraction: true,
            fullExtractionThreshold: 0.0  // Full extraction for all
        )
        
        // Get LLM provider from registry
        let ollamaProvider = await LLMProviderRegistry.shared.provider(id: "ollama")
        let defaultProv = await LLMProviderRegistry.shared.defaultProvider()
        guard let llmProvider = ollamaProvider ?? defaultProv else {
            NSLog("❌ [DeepAnalysis] No LLM provider available!")
            await MainActor.run {
                state.isPerformingDeepAnalysis = false
                state.statusMessage = "Deep analysis unavailable - no LLM provider"
            }
            return
        }
        NSLog("🔬 [DeepAnalysis] Using LLM provider: \(llmProvider.identifier)")
        
        let deepAnalyzer = DeepAnalyzer(configuration: analyzerConfig, llmProvider: llmProvider)
        let existingCategories = taxonomy.allCategories().map { $0.pathString }
        NSLog("🔬 [DeepAnalysis] Existing categories: \(existingCategories.count)")
        
        do {
            NSLog("🔬 [DeepAnalysis] ========== STARTING FULL BATCH ANALYSIS ==========")
            let results = try await deepAnalyzer.analyzeFiles(
                allFiles,
                existingCategories: existingCategories
            ) { completed, total in
                Task { @MainActor in
                    state.statusMessage = "Deep analyzing \(completed)/\(total)..."
                    state.inferenceProgress = 0.7 + (Double(completed) / Double(total) * 0.3)
                }
            }
            
            let duration = Date().timeIntervalSince(startTime)
            
            await MainActor.run {
                state.deepAnalysisResults = results
                state.isPerformingDeepAnalysis = false
                state.statusMessage = "Deep analysis complete: \(results.count) files in \(String(format: "%.1f", duration))s"
                
                NSLog("🔬 [DeepAnalysis] ========== ANALYSIS COMPLETE ==========")
                NSLog("🔬 [DeepAnalysis] Total time: \(String(format: "%.2f", duration))s")
                NSLog("🔬 [DeepAnalysis] Results: \(results.count)")
                
                // Apply results to taxonomy - reassign files to content-based categories
                for result in results {
                    if let file = scanResult.files.first(where: { $0.filename == result.filename }) {
                        taxonomy.reassignFile(
                            fileId: file.id,
                            toCategoryPath: result.categoryPath,
                            confidence: result.confidence
                        )
                    }
                }
                
                NSLog("🔬 [DeepAnalysis] Applied \(results.count) deep analysis results to taxonomy")
            }
            
        } catch {
            NSLog("❌ [DeepAnalysis] Batch analysis failed: \(error.localizedDescription)")
            await MainActor.run {
                state.isPerformingDeepAnalysis = false
                state.statusMessage = "Deep analysis failed: \(error.localizedDescription)"
            }
        }
    }
    
}

// MARK: - Phase Indicator

struct PhaseIndicator: View {
    let phase: Int
    let title: String
    let isActive: Bool
    let isComplete: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 28, height: 28)
                
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else if isActive {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Text("\(phase)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? .white : .secondary)
                }
            }
            
            Text(title)
                .font(.caption)
                .foregroundStyle(isActive || isComplete ? .primary : .secondary)
        }
    }
    
    private var backgroundColor: Color {
        if isComplete {
            return .green
        } else if isActive {
            return .accentColor
        } else {
            return .secondary.opacity(0.3)
        }
    }
}

struct VerifyHierarchyStep: View {
    @Bindable var state: WizardState
    let deepAnalyzer: DeepAnalyzer?
    @State private var showingOptionsPopover = false
    
    var body: some View {
        VStack(spacing: 12) {
            if let taxonomy = state.taxonomy {
                // Refinement status banner (if active)
                if state.isRefining {
                    refinementStatusBanner
                }
                
                // Header row with stats and re-infer option
                HStack {
                    if state.isRefining {
                        Text("AI is refining categories - you can start editing now")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    } else {
                        Text("Review and edit the category structure")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Re-infer button with options (disabled during refinement)
                    Button {
                        showingOptionsPopover = true
                    } label: {
                        Label("Re-categorize", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(state.isRefining)
                    .popover(isPresented: $showingOptionsPopover) {
                        reInferOptionsView
                    }
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Stats
                    HStack(spacing: 16) {
                        Label("\(taxonomy.categoryCount) categories", systemImage: "folder")
                        Label("\(taxonomy.totalFileCount) files", systemImage: "doc")
                    }
                    .font(.caption)
                }
                
                // Hierarchy editor - takes all available space
                HierarchyEditorView(taxonomy: taxonomy)
                    .frame(minHeight: 300, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Deep analysis option (fixed height)
                if taxonomy.filesNeedingDeepAnalysis > 0 {
                    deepAnalysisPrompt(for: taxonomy)
                }
                
                // Show deep analysis results if any (fixed height)
                if !state.deepAnalysisResults.isEmpty {
                    deepAnalysisResultsView
                }
            } else {
                Spacer()
                Text("No taxonomy available")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private func deepAnalysisPrompt(for taxonomy: TaxonomyTree) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            
            Text("\(taxonomy.filesNeedingDeepAnalysis) files have low confidence and may benefit from deep analysis")
                .font(.caption)
            
            Spacer()
            
            if state.isPerformingDeepAnalysis {
                ProgressView()
                    .controlSize(.small)
                Text("Analyzing...")
                    .font(.caption)
            } else if deepAnalyzer != nil {
                Button("Analyze Now") {
                    Task {
                        await performDeepAnalysis()
                    }
                }
                .controlSize(.small)
            } else {
                Text("Deep analyzer not available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private var deepAnalysisResultsView: some View {
        GroupBox("Deep Analysis Results") {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.deepAnalysisResults) { result in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(result.filename)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(result.pathString)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("\(Int(result.confidence * 100))%")
                                .font(.caption)
                                .foregroundStyle(result.confidence > 0.75 ? .green : .orange)
                        }
                    }
                }
                .padding(4)
            }
            .frame(maxHeight: 150)
        }
    }
    
    // MARK: - Re-infer Options Popover
    
    @ViewBuilder
    private var reInferOptionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Re-categorize Options")
                .font(.headline)
            
            Divider()
            
            // Category count slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Target categories:")
                    Spacer()
                    Text("\(state.targetCategoryCount)")
                        .monospacedDigit()
                        .fontWeight(.medium)
                }
                
                Slider(value: Binding(
                    get: { Double(state.targetCategoryCount) },
                    set: { state.targetCategoryCount = Int($0) }
                ), in: 3...15, step: 1)
                
                Text("Fewer = broader themes, More = specific categories")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // File type separation toggle
            Toggle("Separate file types within themes", isOn: $state.separateFileTypes)
            
            Text("Videos, PDFs, etc. in separate sub-folders")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Divider()
            
            // Deep analysis toggle
            Toggle("Auto-analyze low-confidence files", isOn: $state.enableDeepAnalysis)
            
            if state.enableDeepAnalysis {
                HStack {
                    Text("Threshold:")
                    Slider(value: $state.confidenceThreshold, in: 0.5...0.95, step: 0.05)
                    Text("\(Int(state.confidenceThreshold * 100))%")
                        .monospacedDigit()
                }
                .padding(.leading)
            }
            
            Divider()
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    showingOptionsPopover = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Re-categorize") {
                    showingOptionsPopover = false
                    state.reInferTaxonomy()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320)
    }
    
    /// Refinement status banner showing current AI activity
    @ViewBuilder
    private var refinementStatusBanner: some View {
        HStack(spacing: 12) {
            // Animated spinner
            ProgressView()
                .controlSize(.small)
            
            VStack(alignment: .leading, spacing: 2) {
                // Phase description
                Text(state.refinementProgress?.phase.rawValue ?? "Refining...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                // Category being processed
                if let currentCategory = state.refinementProgress?.currentCategory {
                    Text("Processing: \(currentCategory)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Progress indicator
            if let progress = state.refinementProgress {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(progress.refinedCategories)/\(progress.totalCategories)")
                        .font(.caption)
                        .monospacedDigit()
                    
                    ProgressView(value: progress.percentage)
                        .frame(width: 80)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.3), value: state.refinementProgress?.currentCategory)
    }
    
    // MARK: - Deep Analysis
    
    private func performDeepAnalysis() async {
        guard let taxonomy = state.taxonomy,
              let deepAnalyzer = deepAnalyzer,
              let scanResult = state.scanResult else {
            NSLog("❌ [VerifyStep] Cannot perform deep analysis - missing taxonomy, analyzer, or scan result")
            return
        }
        
        NSLog("🔬 [VerifyStep] Starting deep analysis...")
        
        await MainActor.run {
            state.isPerformingDeepAnalysis = true
        }
        
        // Get files below confidence threshold
        let lowConfFiles = scanResult.files.filter { file in
            taxonomy.confidenceForFile(file.id) < state.confidenceThreshold
        }
        
        if lowConfFiles.isEmpty {
            NSLog("✅ [VerifyStep] No low-confidence files found")
            await MainActor.run {
                state.isPerformingDeepAnalysis = false
            }
            return
        }
        
        NSLog("🔬 [VerifyStep] Analyzing \(lowConfFiles.count) low-confidence files...")
        
        let existingCategories = taxonomy.allCategories().map { $0.name }
        
        do {
            let results = try await deepAnalyzer.analyzeFiles(
                lowConfFiles,
                existingCategories: existingCategories
            ) { analyzed, total in
                Task { @MainActor in
                    self.state.statusMessage = "Analyzed \(analyzed)/\(total) files..."
                }
            }
            
            await MainActor.run {
                state.deepAnalysisResults = results
                state.isPerformingDeepAnalysis = false
                
                // Apply results to taxonomy
                for result in results {
                    if let file = lowConfFiles.first(where: { $0.filename == result.filename }) {
                        taxonomy.reassignFile(
                            fileId: file.id,
                            toCategoryPath: result.categoryPath,
                            confidence: result.confidence
                        )
                    }
                }
                state.statusMessage = "Deep analysis complete: \(results.count) files analyzed"
            }
        } catch {
            await MainActor.run {
                state.errorMessage = error.localizedDescription
                state.isPerformingDeepAnalysis = false
            }
        }
    }
}

struct ConflictResolutionStep: View {
    @Bindable var state: WizardState
    
    var body: some View {
        ConflictResolutionView(conflicts: $state.organizationConflicts)
    }
}

struct OrganizingStep: View {
    @Bindable var state: WizardState
    let engine: OrganizationEngine
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            ProgressView(value: state.organizationProgress) {
                Text("Organizing files...")
            }
            .progressViewStyle(.linear)
            
            // Current file
            if !state.currentOrgFile.isEmpty {
                HStack {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.blue)
                    Text(state.currentOrgFile)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            // Stats
            Text("\(state.organizedCount) of \(state.totalToOrganize) files organized")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Live log of operations
            if state.organizedCount > 0 {
                GroupBox("Progress") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("Processed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Text("\(state.organizedCount)")
                                .fontWeight(.medium)
                        }
                        
                        if let result = state.organizationResult {
                            HStack {
                                Label("Skipped", systemImage: "minus.circle.fill")
                                    .foregroundStyle(.yellow)
                                Spacer()
                                Text("\(result.skippedCount)")
                                    .fontWeight(.medium)
                            }
                            
                            HStack {
                                Label("Failed", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Spacer()
                                Text("\(result.failedOperations.count)")
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .font(.caption)
                    .padding(8)
                }
            }
            
            Spacer()
        }
        .task {
            await performOrganization()
        }
    }
    
    private func performOrganization() async {
        NSLog("📁 [WizardOrg] Starting organization step...")
        
        guard let plan = state.organizationPlan else {
            NSLog("❌ [WizardOrg] No organization plan available!")
            state.errorMessage = "No organization plan available"
            return
        }
        
        NSLog("📁 [WizardOrg] Plan has \(plan.totalFiles) files to organize")
        NSLog("📁 [WizardOrg] Conflicts: \(plan.conflicts.count)")
        
        let orgStartTime = Date()
        
        await MainActor.run {
            state.isProcessing = true
        }
        
        do {
            NSLog("📁 [WizardOrg] Executing organization plan...")
            let result = try await engine.execute(plan: plan) { progress in
                Task { @MainActor in
                    state.organizationProgress = progress.percentage / 100.0
                    state.organizedCount = progress.completed
                    state.currentOrgFile = progress.currentFile
                    state.statusMessage = progress.phase.rawValue
                    
                    // Log progress every 10 files
                    if progress.completed % 10 == 0 || progress.completed == progress.total {
                        NSLog("📁 [WizardOrg] Progress: \(progress.completed)/\(progress.total) (\(Int(progress.percentage))%)")
                    }
                }
            }
            
            let orgDuration = Date().timeIntervalSince(orgStartTime)
            NSLog("✅ [WizardOrg] Organization completed in %.2fs", orgDuration)
            NSLog("✅ [WizardOrg] Success: \(result.successCount), Skipped: \(result.skippedCount), Failed: \(result.failedOperations.count)")
            
            await MainActor.run {
                state.organizationResult = result
                state.isProcessing = false
                NSLog("➡️ [WizardOrg] Advancing to complete step")
                state.goNext()
            }
        } catch {
            let orgDuration = Date().timeIntervalSince(orgStartTime)
            NSLog("❌ [WizardOrg] Organization FAILED after %.2fs: \(error.localizedDescription)", orgDuration)
            await MainActor.run {
                state.errorMessage = error.localizedDescription
                state.isProcessing = false
            }
        }
    }
}

struct CompleteStep: View {
    @Bindable var state: WizardState
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            
            Text("Organization Complete!")
                .font(.title)
                .fontWeight(.semibold)
            
            // Summary stats
            if let result = state.organizationResult {
                VStack(spacing: 16) {
                    // Success stats
                    HStack(spacing: 32) {
                        StatBadge(
                            value: result.successCount,
                            label: "Organized",
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                        
                        if result.skippedCount > 0 {
                            StatBadge(
                                value: result.skippedCount,
                                label: "Skipped",
                                icon: "minus.circle.fill",
                                color: .yellow
                            )
                        }
                        
                        if !result.failedOperations.isEmpty {
                            StatBadge(
                                value: result.failedOperations.count,
                                label: "Failed",
                                icon: "xmark.circle.fill",
                                color: .red
                            )
                        }
                    }
                    
                    // Categories created
                    if let taxonomy = state.taxonomy {
                        Label("\(taxonomy.categoryCount) categories created", systemImage: "folder.fill")
                            .foregroundStyle(.secondary)
                    }
                    
                    // Failed files detail
                    if !result.failedOperations.isEmpty {
                        GroupBox("Failed Operations") {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(result.failedOperations, id: \.file.id) { failure in
                                        HStack {
                                            Text(failure.file.filename)
                                                .font(.caption)
                                            Spacer()
                                            Text(failure.error)
                                                .font(.caption2)
                                                .foregroundStyle(.red)
                                        }
                                    }
                                }
                                .padding(4)
                            }
                            .frame(maxHeight: 100)
                        }
                    }
                    
                    // Open in Finder button
                    if let outputFolder = state.outputFolder {
                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputFolder.path)
                        } label: {
                            Label("Open in Finder", systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else if let taxonomy = state.taxonomy {
                // Fallback if no result (shouldn't happen)
                VStack(spacing: 8) {
                    Label("\(taxonomy.categoryCount) categories created", systemImage: "folder.fill")
                    Label("\(state.organizedCount) files organized", systemImage: "doc.fill")
                }
                .font(.headline)
            }
            
            Spacer()
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let value: Int
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text("\(value)")
                .font(.title)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    let state = WizardState()
    
    return WizardView(
        state: state,
        onComplete: { _ in }
    )
}

