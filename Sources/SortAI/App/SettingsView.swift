// MARK: - SortAI Settings
// Configuration for AI providers, Ollama, models, and organization

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    
    // v2.0 AI Provider Settings
    @AppStorage(SortAIDefaultsKey.providerPreference) private var providerPreferenceRaw = ProviderPreference.automatic.rawValue
    @AppStorage(SortAIDefaultsKey.escalationThreshold) private var escalationThreshold = 0.5
    @AppStorage(SortAIDefaultsKey.autoAcceptThreshold) private var autoAcceptThreshold = 0.85
    @AppStorage(SortAIDefaultsKey.autoInstallOllama) private var autoInstallOllama = true
    @AppStorage(SortAIDefaultsKey.enableFAISS) private var enableFAISS = false
    @AppStorage(SortAIDefaultsKey.useAppleEmbeddings) private var useAppleEmbeddings = true
    
    // Use centralized keys - defaults are registered at app startup via SortAIDefaults.registerDefaults()
    @AppStorage(SortAIDefaultsKey.ollamaHost) private var ollamaHost = "http://127.0.0.1:11434"
    @AppStorage(SortAIDefaultsKey.documentModel) private var documentModel = OllamaConfiguration.defaultModel
    @AppStorage(SortAIDefaultsKey.videoModel) private var videoModel = OllamaConfiguration.defaultModel
    @AppStorage(SortAIDefaultsKey.imageModel) private var imageModel = OllamaConfiguration.defaultModel
    @AppStorage(SortAIDefaultsKey.audioModel) private var audioModel = OllamaConfiguration.defaultModel
    @AppStorage(SortAIDefaultsKey.embeddingModel) private var embeddingModel = OllamaConfiguration.defaultModel
    @AppStorage(SortAIDefaultsKey.embeddingDimensions) private var embeddingDimensions = 512
    @AppStorage(SortAIDefaultsKey.defaultOrganizationMode) private var defaultMode = OrganizationMode.copy.rawValue
    
    // v1.1 Settings
    @AppStorage(SortAIDefaultsKey.organizationDestination) private var organizationDestination = "centralized"
    @AppStorage(SortAIDefaultsKey.customDestinationPath) private var customDestinationPath = ""
    @AppStorage(SortAIDefaultsKey.maxTaxonomyDepth) private var maxTaxonomyDepth = 5
    @AppStorage(SortAIDefaultsKey.stabilityVsCorrectness) private var stabilityVsCorrectness = 0.5
    @AppStorage(SortAIDefaultsKey.enableDeepAnalysis) private var enableDeepAnalysis = true
    @AppStorage(SortAIDefaultsKey.deepAnalysisFileTypes) private var deepAnalysisFileTypes = "pdf,docx,mp4,jpg"
    @AppStorage(SortAIDefaultsKey.useSoftMove) private var useSoftMove = false
    @AppStorage(SortAIDefaultsKey.enableNotifications) private var enableNotifications = true
    @AppStorage(SortAIDefaultsKey.respectBatteryStatus) private var respectBatteryStatus = true
    @AppStorage(SortAIDefaultsKey.enableWatchMode) private var enableWatchMode = false
    @AppStorage(SortAIDefaultsKey.watchQuietPeriod) private var watchQuietPeriod = 3.0
    
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var needsReload = false
    @State private var showingCustomPathPicker = false
    @State private var appleIntelligenceAvailable = false
    @State private var ollamaAvailable = false
    
    /// Current provider preference
    private var providerPreference: ProviderPreference {
        get { ProviderPreference(rawValue: providerPreferenceRaw) ?? .automatic }
        set { providerPreferenceRaw = newValue.rawValue }
    }
    
    /// Whether Ollama settings should be enabled
    private var ollamaSettingsEnabled: Bool {
        providerPreference != .appleIntelligenceOnly
    }
    
    var body: some View {
        Form {
            // MARK: - AI Provider Section
            Section {
                // Provider Preference Picker
                HStack {
                    Text("Provider")
                    Spacer()
                    Picker("", selection: $providerPreferenceRaw) {
                        ForEach(ProviderPreference.allCases, id: \.rawValue) { preference in
                            HStack(spacing: 6) {
                                providerIcon(for: preference)
                                Text(preference.displayName)
                            }
                            .tag(preference.rawValue)
                        }
                    }
                    .frame(width: 240)
                    .accessibilityIdentifier("providerPreferencePicker")
                    .onChange(of: providerPreferenceRaw) { needsReload = true }
                }
                
                // Status indicators
                HStack(spacing: 16) {
                    providerStatusBadge(.appleIntelligence, available: appleIntelligenceAvailable)
                    providerStatusBadge(.ollama, available: ollamaAvailable)
                }
                .padding(.vertical, 4)
                
                // Provider description
                Text(providerPreference.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
            } header: {
                Label("AI Provider Settings", systemImage: "brain.head.profile")
            } footer: {
                if !appleIntelligenceAvailable {
                    Text("⚠️ Apple Intelligence requires macOS 26+")
                        .foregroundStyle(.orange)
                }
            }
            
            // MARK: - Escalation Settings (visible in Automatic mode)
            if providerPreference == .automatic {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Low")
                            Spacer()
                            Text("High")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        
                        Slider(value: $escalationThreshold, in: 0.3...0.8, step: 0.05)
                            .accessibilityIdentifier("escalationThresholdSlider")
                            .onChange(of: escalationThreshold) { needsReload = true }
                        
                        Text("Escalation Threshold: \(String(format: "%.0f%%", escalationThreshold * 100))")
                            .font(.caption)
                    }
                    
                    Toggle("Auto-install Ollama if needed", isOn: $autoInstallOllama)
                        .accessibilityIdentifier("autoInstallOllamaToggle")
                        .onChange(of: autoInstallOllama) { needsReload = true }
                    
                } header: {
                    Text("Escalation Behavior")
                } footer: {
                    Text("Below this confidence, files escalate to a more capable provider.")
                }
            }
            
            // MARK: - Ollama Server Section
            Section {
                TextField("Host URL", text: $ollamaHost)
                    .accessibilityIdentifier("ollamaHostField")
                    .disabled(!ollamaSettingsEnabled)
                    .opacity(ollamaSettingsEnabled ? 1.0 : 0.5)
                    .onChange(of: ollamaHost) { needsReload = true }
                
                HStack {
                    if isLoadingModels {
                        ProgressView()
                            .scaleEffect(0.7)
                            .accessibilityIdentifier("modelsLoadingIndicator")
                    }
                    Button("Refresh Models") {
                        loadAvailableModels()
                    }
                    .accessibilityIdentifier("refreshModelsButton")
                    .disabled(isLoadingModels || !ollamaSettingsEnabled)
                }
            } header: {
                HStack {
                    Text("Ollama Server")
                    if !ollamaSettingsEnabled {
                        Text("(Disabled)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section {
                modelPicker("Documents (PDF, Text)", selection: $documentModel)
                    .disabled(!ollamaSettingsEnabled)
                    .opacity(ollamaSettingsEnabled ? 1.0 : 0.5)
                    .onChange(of: documentModel) { needsReload = true }
                modelPicker("Videos (MP4, MOV)", selection: $videoModel)
                    .disabled(!ollamaSettingsEnabled)
                    .opacity(ollamaSettingsEnabled ? 1.0 : 0.5)
                    .onChange(of: videoModel) { needsReload = true }
                modelPicker("Images (JPG, PNG)", selection: $imageModel)
                    .disabled(!ollamaSettingsEnabled)
                    .opacity(ollamaSettingsEnabled ? 1.0 : 0.5)
                    .onChange(of: imageModel) { needsReload = true }
                modelPicker("Audio (MP3, WAV)", selection: $audioModel)
                    .disabled(!ollamaSettingsEnabled)
                    .opacity(ollamaSettingsEnabled ? 1.0 : 0.5)
                    .onChange(of: audioModel) { needsReload = true }
            } header: {
                HStack {
                    Text("Categorization Models")
                    if !ollamaSettingsEnabled {
                        Text("(Using Apple Intelligence)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if ollamaSettingsEnabled {
                    Text("Use different models for different file types. Larger models may give better results but are slower.")
                } else {
                    Text("Apple Intelligence uses its own optimized model.")
                }
            }
            
            Section {
                Toggle("Use Apple Embeddings", isOn: $useAppleEmbeddings)
                    .accessibilityIdentifier("useAppleEmbeddingsToggle")
                    .disabled(!appleIntelligenceAvailable)
                    .onChange(of: useAppleEmbeddings) { needsReload = true }
                
                if !useAppleEmbeddings || providerPreference == .preferOllama {
                    modelPicker("Embedding Model", selection: $embeddingModel)
                        .disabled(!ollamaSettingsEnabled)
                        .opacity(ollamaSettingsEnabled ? 1.0 : 0.5)
                        .onChange(of: embeddingModel) { needsReload = true }
                }
                
                Stepper("Dimensions: \(embeddingDimensions)", value: $embeddingDimensions, in: 128...1024, step: 128)
                    .onChange(of: embeddingDimensions) { needsReload = true }
                
                Toggle("Enable FAISS Vector Search", isOn: $enableFAISS)
                    .accessibilityIdentifier("enableFAISSToggle")
                    .onChange(of: enableFAISS) { needsReload = true }
            } header: {
                Text("Memory & Embeddings")
            } footer: {
                if useAppleEmbeddings {
                    Text("Using Apple NLEmbedding for fast, on-device similarity matching.")
                } else {
                    Text("Using Ollama model for embeddings.")
                }
            }
            
            // MARK: - Re-embedding Section
            if useAppleEmbeddings {
                Section {
                    ReembeddingStatusCard()
                } header: {
                    Text("Upgrade Existing Embeddings")
                } footer: {
                    Text("Migrate existing embeddings to Apple Intelligence for better accuracy.")
                }
            }
            
            Section {
                Picker("Default Mode", selection: $defaultMode) {
                    ForEach(OrganizationMode.allCases, id: \.rawValue) { mode in
                        Text(mode.rawValue).tag(mode.rawValue)
                    }
                }
                .accessibilityIdentifier("defaultModePicker")
                .onChange(of: defaultMode) { needsReload = true }
                
                Picker("Destination", selection: $organizationDestination) {
                    Text("Centralized").tag("centralized")
                    Text("Distributed").tag("distributed")
                    Text("Custom Path").tag("custom")
                }
                .accessibilityIdentifier("destinationPicker")
                .onChange(of: organizationDestination) { needsReload = true }
                
                if organizationDestination == "custom" {
                    HStack {
                        Text(customDestinationPath.isEmpty ? "No path selected" : customDestinationPath)
                            .lineLimit(1)
                            .foregroundStyle(customDestinationPath.isEmpty ? .secondary : .primary)
                            .accessibilityIdentifier("customPathLabel")
                        Spacer()
                        Button("Choose...") {
                            showingCustomPathPicker = true
                        }
                        .accessibilityIdentifier("choosePathButton")
                    }
                }
                
                Toggle("Soft Move (Symlinks)", isOn: $useSoftMove)
                    .accessibilityIdentifier("softMoveToggle")
                    .onChange(of: useSoftMove) { needsReload = true }
            } header: {
                Text("Organization Settings")
            } footer: {
                Text("Centralized: all files in one folder. Distributed: categories spread across source folders. Soft Move: creates symlinks instead of moving files.")
            }
            
            Section {
                Stepper("Max Depth: \(maxTaxonomyDepth)", value: $maxTaxonomyDepth, in: 2...7)
                    .accessibilityIdentifier("maxDepthStepper")
                    .accessibilityValue("\(maxTaxonomyDepth)")
                    .onChange(of: maxTaxonomyDepth) { needsReload = true }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Stability")
                        Spacer()
                        Text("Correctness")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    
                    Slider(value: $stabilityVsCorrectness, in: 0...1, step: 0.1)
                        .accessibilityIdentifier("stabilitySlider")
                        .accessibilityValue(String(format: "%.1f", stabilityVsCorrectness))
                        .onChange(of: stabilityVsCorrectness) { needsReload = true }
                }
            } header: {
                Text("Taxonomy Settings")
            } footer: {
                Text("Max depth controls hierarchy complexity. Stability mode preserves user edits; Correctness mode optimizes categories automatically.")
            }
            
            Section {
                Toggle("Enable Deep Analysis", isOn: $enableDeepAnalysis)
                    .accessibilityIdentifier("enableDeepAnalysisToggle")
                    .onChange(of: enableDeepAnalysis) { needsReload = true }
                
                if enableDeepAnalysis {
                    TextField("File Types (comma-separated)", text: $deepAnalysisFileTypes)
                        .accessibilityIdentifier("fileTypesField")
                        .onChange(of: deepAnalysisFileTypes) { needsReload = true }
                }
            } header: {
                Text("Deep Analysis")
            } footer: {
                Text("Deep analysis uses LLM to read file content for better categorization. Specify file extensions to analyze (e.g., pdf,docx,mp4).")
            }
            
            Section {
                Toggle("Enable Watch Mode", isOn: $enableWatchMode)
                    .accessibilityIdentifier("enableWatchModeToggle")
                    .onChange(of: enableWatchMode) { needsReload = true }
                
                if enableWatchMode {
                    Stepper("Quiet Period: \(String(format: "%.1f", watchQuietPeriod))s", 
                           value: $watchQuietPeriod, in: 1...10, step: 0.5)
                        .accessibilityIdentifier("quietPeriodStepper")
                        .accessibilityValue(String(format: "%.1f", watchQuietPeriod))
                        .onChange(of: watchQuietPeriod) { needsReload = true }
                }
                
                Toggle("Respect Battery Status", isOn: $respectBatteryStatus)
                    .accessibilityIdentifier("batteryStatusToggle")
                    .onChange(of: respectBatteryStatus) { needsReload = true }
                
                Toggle("Show Notifications", isOn: $enableNotifications)
                    .accessibilityIdentifier("notificationsToggle")
                    .onChange(of: enableNotifications) { needsReload = true }
            } header: {
                Text("Watch & System")
            } footer: {
                Text("Watch mode continuously monitors folders. Quiet period waits for file activity to stop before organizing. Battery mode pauses intensive tasks on battery power.")
            }
            
            if needsReload {
                Section {
                    Button("Apply Changes") {
                        Task {
                            // Update AI provider configuration (v2.0)
                            appState.configManager.updateAIProvider { aiProvider in
                                aiProvider.preference = providerPreference
                                aiProvider.escalationThreshold = escalationThreshold
                                aiProvider.autoAcceptThreshold = autoAcceptThreshold
                                aiProvider.autoInstallOllama = autoInstallOllama
                                aiProvider.enableFAISS = enableFAISS
                                aiProvider.useAppleEmbeddings = useAppleEmbeddings
                            }
                            
                            // Update Ollama configuration
                            appState.configManager.updateOllama { ollama in
                                ollama.host = ollamaHost
                                ollama.documentModel = documentModel
                                ollama.videoModel = videoModel
                                ollama.imageModel = imageModel
                                ollama.audioModel = audioModel
                                ollama.embeddingModel = embeddingModel
                            }
                            appState.configManager.updateMemory { memory in
                                memory.embeddingDimensions = embeddingDimensions
                            }
                            if let mode = OrganizationMode(rawValue: defaultMode) {
                                appState.configManager.updateOrganization { org in
                                    org.defaultMode = mode
                                }
                            }
                            
                            // Save configuration to file
                            try? appState.configManager.save()
                            
                            // Reload pipeline with new settings
                            await appState.reloadPipeline()
                            needsReload = false
                        }
                    }
                    .accessibilityIdentifier("applyChangesButton")
                    .buttonStyle(.borderedProminent)
                } footer: {
                    Text("Settings have changed. Click to apply.")
                        .accessibilityIdentifier("changesWarningLabel")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: needsReload ? 820 : 800)
        .onAppear {
            checkProviderAvailability()
            loadAvailableModels()
        }
        .fileImporter(
            isPresented: $showingCustomPathPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    customDestinationPath = url.path
                    needsReload = true
                }
            case .failure:
                break
            }
        }
    }
    
    @ViewBuilder
    private func modelPicker(_ label: String, selection: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            if availableModels.isEmpty {
                TextField("Model", text: selection)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            } else {
                Picker("", selection: selection) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .frame(width: 180)
            }
        }
    }
    
    private func loadAvailableModels() {
        isLoadingModels = true
        
        Task {
            do {
                guard let url = URL(string: "\(ollamaHost)/api/tags") else { return }
                let (data, _) = try await URLSession.shared.data(from: url)
                
                struct TagsResponse: Decodable {
                    struct Model: Decodable {
                        let name: String
                    }
                    let models: [Model]
                }
                
                let response = try JSONDecoder().decode(TagsResponse.self, from: data)
                
                await MainActor.run {
                    availableModels = response.models.map { $0.name }.sorted()
                    ollamaAvailable = true
                    isLoadingModels = false
                }
            } catch {
                await MainActor.run {
                    availableModels = []
                    ollamaAvailable = false
                    isLoadingModels = false
                }
            }
        }
    }
    
    private func checkProviderAvailability() {
        // Check Apple Intelligence availability
        appleIntelligenceAvailable = SortAIDefaults.isAppleIntelligenceAvailable
        
        // Check Ollama availability (done by loadAvailableModels)
    }
    
    // MARK: - Provider Badge Views
    
    @ViewBuilder
    private func providerIcon(for preference: ProviderPreference) -> some View {
        switch preference {
        case .automatic:
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
        case .appleIntelligenceOnly:
            Image(systemName: "apple.logo")
                .foregroundStyle(.primary)
        case .preferOllama:
            Text("🦙")
        case .cloud:
            Image(systemName: "cloud")
                .foregroundStyle(.blue)
        }
    }
    
    @ViewBuilder
    private func providerStatusBadge(_ provider: LLMProviderIdentifier, available: Bool) -> some View {
        HStack(spacing: 4) {
            // Icon
            switch provider {
            case .appleIntelligence:
                Image(systemName: "apple.logo")
                    .font(.system(size: 14))
            case .ollama:
                Text("🦙")
                    .font(.system(size: 12))
            default:
                Image(systemName: "cloud")
                    .font(.system(size: 14))
            }
            
            // Status dot
            Circle()
                .fill(available ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            // Name
            Text(provider.displayName)
                .font(.caption)
                .foregroundStyle(available ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(available ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - Future: LLM Status View
// TODO: Integrate LLMRoutingService into SortAIPipeline and add status view
// to display degraded/full mode status, retry/backoff indicators, and
// "Return to full mode" action.

