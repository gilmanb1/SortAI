// MARK: - SortAI Settings
// Configuration for Ollama, models, and organization

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    
    // Use centralized keys - defaults are registered at app startup via SortAIDefaults.registerDefaults()
    @AppStorage(SortAIDefaultsKey.ollamaHost) private var ollamaHost = "http://127.0.0.1:11434"
    @AppStorage(SortAIDefaultsKey.documentModel) private var documentModel = OllamaConfiguration.defaultModel
    @AppStorage(SortAIDefaultsKey.videoModel) private var videoModel = OllamaConfiguration.defaultModel
    @AppStorage(SortAIDefaultsKey.imageModel) private var imageModel = OllamaConfiguration.defaultModel
    @AppStorage(SortAIDefaultsKey.audioModel) private var audioModel = OllamaConfiguration.defaultModel
    @AppStorage(SortAIDefaultsKey.embeddingModel) private var embeddingModel = OllamaConfiguration.defaultModel
    @AppStorage(SortAIDefaultsKey.embeddingDimensions) private var embeddingDimensions = 384
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
    
    var body: some View {
        Form {
            Section("Ollama Server") {
                TextField("Host URL", text: $ollamaHost)
                    .accessibilityIdentifier("ollamaHostField")
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
                    .disabled(isLoadingModels)
                }
            }
            
            Section {
                modelPicker("Documents (PDF, Text)", selection: $documentModel)
                    .onChange(of: documentModel) { needsReload = true }
                modelPicker("Videos (MP4, MOV)", selection: $videoModel)
                    .onChange(of: videoModel) { needsReload = true }
                modelPicker("Images (JPG, PNG)", selection: $imageModel)
                    .onChange(of: imageModel) { needsReload = true }
                modelPicker("Audio (MP3, WAV)", selection: $audioModel)
                    .onChange(of: audioModel) { needsReload = true }
            } header: {
                Text("Categorization Models")
            } footer: {
                Text("Use different models for different file types. Larger models may give better results but are slower.")
            }
            
            Section {
                modelPicker("Embedding Model", selection: $embeddingModel)
                    .onChange(of: embeddingModel) { needsReload = true }
                Stepper("Dimensions: \(embeddingDimensions)", value: $embeddingDimensions, in: 128...1536, step: 128)
                    .onChange(of: embeddingDimensions) { needsReload = true }
            } header: {
                Text("Memory & Embeddings")
            } footer: {
                Text("Model used for generating embeddings to match similar files from memory.")
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
                            // Update configuration manager with current values
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
        .frame(width: 600, height: needsReload ? 740 : 720)
        .onAppear {
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
                    isLoadingModels = false
                }
            } catch {
                await MainActor.run {
                    availableModels = []
                    isLoadingModels = false
                }
            }
        }
    }
}

// MARK: - Future: LLM Status View
// TODO: Integrate LLMRoutingService into SortAIPipeline and add status view
// to display degraded/full mode status, retry/backoff indicators, and
// "Return to full mode" action.

