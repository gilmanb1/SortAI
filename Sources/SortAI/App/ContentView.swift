// MARK: - SortAI Compact Workspace
// Reactive utility interface for file organization

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var isDragOver = false
    @State private var showingReviewForItem: ProcessingItem?
    @State private var showingWizard = false
    @State private var showingBatchReview = false
    @State private var isFirstLaunch: Bool = !UserDefaults.standard.bool(forKey: "hasCompletedFirstLaunch")
    
    var body: some View {
        VStack(spacing: 0) {
            // Header: Drop Zone & Configuration
            headerView
            
            Divider()
            
            // Main Content: Reactive Stream
            ZStack {
                if appState.items.isEmpty {
                    emptyStateView
                } else {
                    activityStreamView
                }
            }
            
            Divider()
            
            // Footer: Stats & Health
            footerView
        }
        .frame(minWidth: 400, maxWidth: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Error", isPresented: Binding(
            get: { appState.lastError != nil },
            set: { if !$0 { appState.lastError = nil } }
        )) {
            Button("OK") { appState.lastError = nil }
        } message: {
            Text(appState.lastError ?? "An unknown error occurred")
        }
        .sheet(item: $showingReviewForItem) { item in
            reviewSheet(item: item)
        }
        .sheet(isPresented: $showingBatchReview) {
            batchReviewSheet
        }
        .sheet(isPresented: $showingWizard) {
            wizardSheet
        }
        .onAppear {
            // Show wizard on first launch
            if isFirstLaunch {
                showingWizard = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingWizard = true
                } label: {
                    Label("Organization Wizard", systemImage: "wand.and.stars")
                }
                .help("Open the Organization Wizard")
            }
        }
    }
    
    // MARK: - Wizard Sheet
    
    @MainActor
    private var wizardSheet: some View {
        let state = WizardState()
        let scanner = FilenameScanner()
        
        return WizardView(
            state: state,
            scanner: scanner
        ) { taxonomy in
            // Mark first launch complete
            if isFirstLaunch {
                UserDefaults.standard.set(true, forKey: "hasCompletedFirstLaunch")
                isFirstLaunch = false
            }
            
            // Handle completed taxonomy
            if let taxonomy = taxonomy {
                handleWizardCompletion(taxonomy: taxonomy)
            }
        }
        // Make the wizard sheet resizable with sensible bounds
        .frame(
            minWidth: 700,
            idealWidth: 900,
            maxWidth: 1400,
            minHeight: 500,
            idealHeight: 700,
            maxHeight: 1000
        )
        .presentationSizing(.fitted)
    }
    
    private func handleWizardCompletion(taxonomy: TaxonomyTree) {
        // Store taxonomy for future use
        // The wizard handles file organization internally
        // We could update appState here with results
        NSLog("📊 [DEBUG] Wizard completed with \(taxonomy.categoryCount) categories")
    }
    
    /// Create the appropriate LLM provider based on user preference
    @MainActor
    private func createLLMProviderFromPreference() -> any LLMProvider {
        let preferenceRaw = UserDefaults.standard.string(forKey: SortAIDefaultsKey.providerPreference)
            ?? ProviderPreference.automatic.rawValue
        let preference = ProviderPreference(rawValue: preferenceRaw) ?? .automatic
        
        switch preference {
        case .automatic, .appleIntelligenceOnly:
            // Try Apple Intelligence first
            let appleProvider = AppleIntelligenceLLMFactory.create()
            NSLog("🤖 [ContentView] Using Apple Intelligence provider (preference: \(preference.rawValue))")
            return appleProvider
            
        case .preferOllama:
            // Use Ollama
            NSLog("🤖 [ContentView] Using Ollama provider (preference: \(preference.rawValue))")
            return OllamaProvider()
            
        case .cloud:
            // Use OpenAI provider (fallback to Ollama if not configured)
            NSLog("🤖 [ContentView] Using Cloud provider (preference: \(preference.rawValue))")
            // For now, fall back to Ollama since cloud isn't fully configured
            return OllamaProvider()
        }
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 12) {
            // Drop Zone Area
            VStack(spacing: 8) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 24))
                    .foregroundStyle(isDragOver ? Color.accentColor : Color.secondary)
                
                Text(isDragOver ? "Drop to Process" : "Drop Folders to Sort")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isDragOver ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(isDragOver ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .padding([.horizontal, .top])
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                handleDrop(providers: providers)
            }
            
            // Output Location & Settings
            HStack {
                Button {
                    chooseOutputFolder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text(appState.outputFolder?.lastPathComponent ?? "Select Output...")
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                
                Spacer()
                
                Picker("", selection: Bindable(appState).organizationMode) {
                    Text("Copy").tag(OrganizationMode.copy)
                    Text("Move").tag(OrganizationMode.move)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No files processed yet")
                .foregroundStyle(.secondary)
        }
    }
    
    private var activityStreamView: some View {
        VStack(spacing: 0) {
            // Bulk edit controls (shown when items selected or bulk mode active)
            if appState.isBulkEditMode || appState.hasSelection {
                bulkEditToolbar
            }
            
            List {
                ForEach(appState.items) { item in
                    ItemRowView(
                        item: item,
                        isSelected: appState.isSelected(item),
                        isBulkEditMode: appState.isBulkEditMode,
                        onReview: {
                            showingReviewForItem = item
                        },
                        onSelectionClick: { shiftHeld, cmdHeld in
                            appState.handleSelectionClick(item, shiftHeld: shiftHeld, cmdHeld: cmdHeld)
                        }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.visible, edges: .bottom)
                }
            }
            .listStyle(.plain)
            // Enable Space key to toggle QuickLook for selected items (or all if none selected)
            .quickLookPreview(urls: quickLookURLs, currentIndex: 0)
            
            // Bulk edit panel (shown when items are selected)
            if appState.hasSelection {
                BulkEditPanel()
            }
        }
    }
    
    /// URLs for QuickLook preview - selected items if any, otherwise all items
    private var quickLookURLs: [URL] {
        if appState.hasSelection {
            return appState.selectedItems.map(\.url)
        } else {
            return appState.items.map(\.url)
        }
    }
    
    private var bulkEditToolbar: some View {
        HStack(spacing: 12) {
            // Toggle bulk edit mode
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    appState.isBulkEditMode.toggle()
                    if !appState.isBulkEditMode {
                        appState.clearSelection()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appState.isBulkEditMode ? "checkmark.square.fill" : "square.stack")
                    Text(appState.isBulkEditMode ? "Done" : "Select")
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            if appState.isBulkEditMode {
                Divider()
                    .frame(height: 16)
                
                // Select all / deselect
                Button("Select All") {
                    appState.selectAll()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                
                if appState.hasSelection {
                    Button("Deselect") {
                        appState.clearSelection()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    Text("\(appState.selectionCount) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
    }
    
    private var footerView: some View {
        HStack(spacing: 16) {
            // Model & Pipeline Status
            modelStatusIndicator
            
            // Undo/Redo buttons (when operations available)
            if appState.canUndoLastMove || appState.canRedoLastMove {
                HStack(spacing: 4) {
                    Button {
                        Task { await appState.undoLastMove() }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appState.canUndoLastMove ? .primary : .tertiary)
                    .disabled(!appState.canUndoLastMove)
                    .help("Undo last file move (⌘Z)")
                    .keyboardShortcut("z", modifiers: .command)
                    
                    Button {
                        Task { await appState.redoLastMove() }
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(appState.canRedoLastMove ? .primary : .tertiary)
                    .disabled(!appState.canRedoLastMove)
                    .help("Redo last undone move (⇧⌘Z)")
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    
                    if appState.undoableOperationsCount > 0 {
                        Text("\(appState.undoableOperationsCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
            }
            
            // Stats
            if appState.totalProcessed > 0 {
                HStack(spacing: 12) {
                    statLabel(value: appState.successCount, icon: "checkmark.circle", color: .green)
                    statLabel(value: appState.failureCount, icon: "exclamationmark.triangle", color: .red)
                    if appState.pendingReviewCount > 0 {
                        // Clickable pending review count - opens batch review
                        Button {
                            showingBatchReview = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person.badge.key")
                                Text("\(appState.pendingReviewCount)")
                            }
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .help("Click to review \(appState.pendingReviewCount) pending items")
                    }
                    // Show accepted-but-not-organized count
                    if appState.acceptedUnorganizedCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "tray.full")
                            Text("\(appState.acceptedUnorganizedCount)")
                        }
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                        .help("\(appState.acceptedUnorganizedCount) files ready to organize")
                    }
                }
            } else if appState.modelStatus.isReady {
                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Action buttons
            if appState.isProcessing {
                ProgressView()
                    .controlSize(.small)
            } else {
                HStack(spacing: 12) {
                    // Review All button (when there are pending items)
                    if appState.pendingReviewCount > 0 {
                        Button {
                            showingBatchReview = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "list.bullet.clipboard")
                                Text("Review All")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        // Accept All button
                        Button {
                            appState.acceptAllPendingItems()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Accept All")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.green)
                        .help("Accept all pending items and organize them")
                    }
                    
                    // Organize Files button (when there are accepted but unorganized items)
                    // This handles the case where files hit cache and are auto-accepted
                    if appState.acceptedUnorganizedCount > 0 && appState.pendingReviewCount == 0 {
                        Button {
                            appState.organizeAllAcceptedItems()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.plus")
                                Text("Organize Files (\(appState.acceptedUnorganizedCount))")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .help("Organize all accepted files to the output folder")
                        .disabled(appState.outputFolder == nil)
                    }
                    
                    // Clear All button
                    if !appState.items.isEmpty {
                        Button("Clear All") {
                            appState.reset()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
        .padding(.horizontal)
        .frame(height: 36)
        .background(Color.secondary.opacity(0.05))
    }
    
    @ViewBuilder
    private var modelStatusIndicator: some View {
        switch appState.modelStatus {
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Checking model...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
        case .downloading(let progress):
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Color.white, lineWidth: 2)
                            .rotationEffect(.degrees(-90))
                    }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Downloading model...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(width: 80)
                }
            }
            .help("Downloading \(appState.modelDownloadStatus)")
            
        case .ready:
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isInitialized ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                if let model = appState.activeModel {
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .help(appState.isInitialized ? "AI Pipeline Ready - \(appState.activeModel ?? "unknown")" : "AI Pipeline Initializing...")
            
        case .error(let message):
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Model Error")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .help(message)
        }
    }
    
    private func statLabel(value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(value)")
        }
        .font(.caption2)
        .fontWeight(.bold)
        .foregroundStyle(color)
    }
    
    // MARK: - Sheets
    
    // MARK: - Batch Review Sheet
    
    @MainActor
    private var batchReviewSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Review Pending Items")
                    .font(.headline)
                
                Spacer()
                
                Text("\(appState.pendingReviewCount) items")
                    .foregroundStyle(.secondary)
                
                Button {
                    showingBatchReview = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            
            Divider()
            
            // List of pending items
            if appState.pendingReviewItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                    
                    Text("All Items Reviewed!")
                        .font(.title2)
                    
                    Button("Done") {
                        showingBatchReview = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(appState.pendingReviewItems) { item in
                        BatchReviewItemRow(
                            item: item,
                            onReview: {
                                showingBatchReview = false
                                showingReviewForItem = item
                            },
                            onAccept: {
                                appState.confirmItem(item)
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
            
            Divider()
            
            // Footer actions
            HStack {
                Button("Skip All") {
                    for item in appState.pendingReviewItems {
                        item.feedbackItem?.status = .skipped
                        item.status = .completed
                    }
                    showingBatchReview = false
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button {
                    appState.acceptAllPendingItems()
                    showingBatchReview = false
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Accept All (\(appState.pendingReviewCount))")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(appState.pendingReviewItems.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    private func reviewSheet(item: ProcessingItem) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review Categorization")
                    .font(.headline)
                Spacer()
                Button {
                    showingReviewForItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .help("Close (Esc)")
            }
            .padding()
            
            Divider()
            
            if let feedback = item.feedbackItem {
                ReviewDetailView(
                    item: feedback,
                    onAccept: {
                        appState.confirmItem(item)
                        showingReviewForItem = nil
                    },
                    onCorrect: { newPath in
                        appState.confirmItem(item, correctedPath: newPath)
                        showingReviewForItem = nil
                    },
                    onSkip: {
                        showingReviewForItem = nil
                    }
                )
            } else {
                Text("Result loading...")
                    .padding()
            }
        }
        .frame(minWidth: 520, maxWidth: 520, minHeight: 480, maxHeight: 650)
    }
    
    // MARK: - Actions
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var folders: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    DispatchQueue.main.async {
                        folders.append(url)
                    }
                }
            }
        }
        
        group.notify(queue: .main) {
            if !folders.isEmpty {
                appState.addFolders(folders)
            }
        }
        return true
    }
    
    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose target folder for organized files"
        
        if panel.runModal() == .OK, let url = panel.url {
            appState.setOutputFolder(url)
        }
    }
}

// MARK: - Item Row View

struct ItemRowView: View {
    let item: ProcessingItem
    let isSelected: Bool
    let isBulkEditMode: Bool
    let onReview: () -> Void
    let onSelectionClick: (Bool, Bool) -> Void  // (shiftHeld, cmdHeld)
    
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox (visible in bulk edit mode)
            if isBulkEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .onTapGesture {
                        onSelectionClick(false, true)  // Toggle like cmd-click
                    }
            }
            
            // File icon with QuickLook on click (when not processing)
            if item.status.isActive {
                // Status Icon with Activity Indicator for active states
                ZStack {
                    Circle()
                        .fill(item.status.color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: item.status.icon)
                        .foregroundStyle(item.status.color)
                        .font(.system(size: 16, weight: .bold))
                    
                    // Spinning indicator for active states
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(item.status.color, lineWidth: 2)
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(rotationAngle))
                        .onAppear {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                rotationAngle = 360
                            }
                        }
                }
            } else {
                // Clickable file icon for QuickLook preview
                QuickLookIcon(url: item.url, size: 36)
                    .overlay {
                        // Small status badge in corner
                        Circle()
                            .fill(item.status.color)
                            .frame(width: 12, height: 12)
                            .overlay {
                                Image(systemName: item.status == .completed ? "checkmark" : 
                                                  item.status == .reviewing ? "person.fill" : "")
                                    .font(.system(size: 6, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .offset(x: 12, y: 12)
                    }
            }
            
            // File Details
            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    // Status label
                    Text(item.status.label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(item.status.color)
                    
                    // Full category path (condensed with hover expansion)
                    if !item.fullCategoryPath.components.isEmpty {
                        HStack(spacing: 2) {
                            CondensedCategoryPathView(
                                path: item.fullCategoryPath,
                                maxVisibleComponents: 2,
                                compact: true
                            )
                            
                            // Refining indicator
                            if item.isRefining {
                                Text("→")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    
                    // Confidence badge for completed items
                    if item.result != nil {
                        let confidence = item.displayConfidence
                        Text("\(Int(confidence * 100))%")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(confidenceColor(confidence).opacity(0.2))
                            .foregroundStyle(confidenceColor(confidence))
                            .clipShape(Capsule())
                    }
                }
                
                // Progress bar for active items
                if item.status.isActive {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 3)
                                .clipShape(Capsule())
                            
                            Rectangle()
                                .fill(item.status.color)
                                .frame(width: geometry.size.width * item.estimatedProgress, height: 3)
                                .clipShape(Capsule())
                                .animation(.easeInOut(duration: 0.3), value: item.progress)
                        }
                    }
                    .frame(height: 3)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                // QuickLook button (always available when not actively processing)
                if !item.status.isActive {
                    QuickLookButton(url: item.url)
                }
                
                if item.status == .reviewing {
                    Button("Review") {
                        onReview()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
                } else if case .failed(let reason) = item.status {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.red)
                        .help(reason)
                } else if item.status == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Handle row tap for selection when in bulk edit mode
            if isBulkEditMode {
                onSelectionClick(NSEvent.modifierFlags.contains(.shift),
                               NSEvent.modifierFlags.contains(.command))
            }
        }
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.85 { return .green }
        if confidence >= 0.6 { return .yellow }
        return .orange
    }
}

// MARK: - Batch Review Item Row

struct BatchReviewItemRow: View {
    let item: ProcessingItem
    let onReview: () -> Void
    let onAccept: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Clickable file icon for QuickLook
            QuickLookIcon(url: item.url, size: 36)
            
            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.headline)
                    .lineLimit(1)
                
                if !item.fullCategoryPath.components.isEmpty {
                    CondensedCategoryPathView(
                        path: item.fullCategoryPath,
                        maxVisibleComponents: 2,
                        compact: true
                    )
                }
                
                // Confidence and rationale
                HStack(spacing: 8) {
                    let confidence = item.displayConfidence
                    Text("\(Int(confidence * 100))%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(confidenceColor(confidence))
                    
                    if let rationale = item.feedbackItem?.rationale, !rationale.isEmpty {
                        Text(rationale)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 8) {
                // QuickLook button
                QuickLookButton(url: item.url)
                
                Button("Review") {
                    onReview()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button {
                    onAccept()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
                .help("Accept this categorization")
            }
        }
        .padding(.vertical, 6)
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.85 { return .green }
        if confidence >= 0.6 { return .yellow }
        return .orange
    }
}

// MARK: - Bulk Edit Panel

struct BulkEditPanel: View {
    @Environment(AppState.self) private var appState
    
    @State private var newRootCategory: String = ""
    @State private var selectedExistingRoot: String?
    @State private var isCustomInput: Bool = false
    @State private var showPreview: Bool = true
    
    // Collect unique existing root categories from all items
    private var existingRootCategories: [String] {
        var roots = Set<String>()
        for item in appState.items {
            let root = item.fullCategoryPath.root
            if !root.isEmpty {
                roots.insert(root)
            }
        }
        return roots.sorted()
    }
    
    // Preview of what will change
    private var rerootPreview: [(from: String, to: String, count: Int)] {
        guard !effectiveNewRoot.isEmpty else { return [] }
        
        var previews: [String: Int] = [:]
        for item in appState.selectedItems {
            let currentPath = item.fullCategoryPath
            let currentRoot = currentPath.root
            
            if currentRoot != effectiveNewRoot {
                // Build preview string
                var newComponents = [effectiveNewRoot]
                if currentPath.components.count > 1 {
                    newComponents.append(contentsOf: currentPath.components.dropFirst())
                }
                let preview = "\(currentPath.description) → \(newComponents.joined(separator: " / "))"
                previews[preview, default: 0] += 1
            }
        }
        
        return previews.map { (from: $0.key, to: "", count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    private var effectiveNewRoot: String {
        isCustomInput ? newRootCategory : (selectedExistingRoot ?? "")
    }
    
    private var canApply: Bool {
        !effectiveNewRoot.isEmpty && appState.hasSelection
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundStyle(.orange)
                
                Text("Re-root \(appState.selectionCount) Files")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    appState.clearSelection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Current categories summary
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Root Categories")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        FlowLayout(spacing: 6) {
                            ForEach(Array(appState.selectedRootCategories.keys.sorted()), id: \.self) { root in
                                HStack(spacing: 4) {
                                    Text(root)
                                    Text("(\(appState.selectedRootCategories[root] ?? 0))")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .cornerRadius(12)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // New root selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Move to New Root Category")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        // Mode toggle
                        Picker("Source", selection: $isCustomInput) {
                            Text("Pick Existing").tag(false)
                            Text("Type Custom").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        
                        if isCustomInput {
                            // Custom text input
                            HStack {
                                TextField("Enter new root category...", text: $newRootCategory)
                                    .textFieldStyle(.roundedBorder)
                                
                                if !newRootCategory.isEmpty {
                                    Button {
                                        newRootCategory = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            // Dropdown for existing categories
                            if existingRootCategories.isEmpty {
                                Text("No existing categories found")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Picker("Select category", selection: $selectedExistingRoot) {
                                    Text("Choose...").tag(nil as String?)
                                    ForEach(existingRootCategories, id: \.self) { root in
                                        Text(root).tag(root as String?)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                    
                    // Preview
                    if showPreview && !rerootPreview.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Preview Changes")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                                
                                Button {
                                    showPreview.toggle()
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(rerootPreview.prefix(5), id: \.from) { preview in
                                    Text(preview.from)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                if rerootPreview.count > 5 {
                                    Text("... and \(rerootPreview.count - 5) more")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding()
            }
            .frame(maxHeight: 250)
            
            Divider()
            
            // Actions
            HStack {
                Button("Cancel") {
                    appState.clearSelection()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Apply to \(appState.selectionCount) Files") {
                    appState.rerootSelectedItems(to: effectiveNewRoot)
                    appState.clearSelection()
                    appState.isBulkEditMode = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canApply)
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, y: -2)
    }
}

