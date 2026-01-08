// MARK: - Configuration Manager
// Handles loading, saving, observing, and managing application configuration
// Supports JSON file persistence, environment overrides, and runtime changes

import Foundation
import Observation

// MARK: - Configuration Manager

/// Manages application configuration lifecycle
/// Observable for SwiftUI integration
@Observable
@MainActor
final class ConfigurationManager {
    
    // MARK: - Singleton
    
    static let shared = ConfigurationManager()
    
    // MARK: - Properties
    
    /// Current active configuration
    private(set) var config: AppConfiguration
    
    /// Configuration file path
    let configFilePath: URL
    
    /// Whether configuration has unsaved changes
    var hasUnsavedChanges: Bool = false
    
    /// Last error encountered
    var lastError: ConfigurationError?
    
    /// Configuration change callbacks
    private var changeHandlers: [(AppConfiguration) -> Void] = []
    
    // MARK: - Initialization
    
    init(configPath: URL? = nil) {
        // Determine config file path
        if let path = configPath {
            self.configFilePath = path
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            let sortAIDir = appSupport.appendingPathComponent("SortAI", isDirectory: true)
            self.configFilePath = sortAIDir.appendingPathComponent("config.json")
        }
        
        // Load configuration
        self.config = Self.loadConfiguration(from: configFilePath)
    }
    
    // MARK: - Loading
    
    /// Loads configuration from file, falling back to defaults
    private static func loadConfiguration(from path: URL) -> AppConfiguration {
        // Try to load from file
        if FileManager.default.fileExists(atPath: path.path) {
            do {
                let data = try Data(contentsOf: path)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                var config = try decoder.decode(AppConfiguration.self, from: data)
                
                // Apply environment overrides
                config = applyEnvironmentOverrides(to: config)
                
                return config
            } catch {
                print("⚠️ Failed to load config file: \(error). Using defaults.")
            }
        }
        
        // Try to migrate from UserDefaults
        let legacyConfig = AppConfiguration.fromUserDefaults()
        if legacyConfig != AppConfiguration.default {
            print("📦 Migrated configuration from UserDefaults")
            return legacyConfig
        }
        
        // Return defaults
        return AppConfiguration.default
    }
    
    /// Applies environment variable overrides to configuration
    private static func applyEnvironmentOverrides(to config: AppConfiguration) -> AppConfiguration {
        var config = config
        let env = ProcessInfo.processInfo.environment
        
        // Ollama overrides
        if let host = env["SORTAI_OLLAMA_HOST"] {
            config.ollama.host = host
        }
        if let model = env["SORTAI_OLLAMA_MODEL"] {
            config.ollama = .uniform(host: config.ollama.host, model: model)
        }
        
        // Memory overrides
        if let dims = env["SORTAI_EMBEDDING_DIMENSIONS"], let value = Int(dims) {
            config.memory.embeddingDimensions = value
        }
        if let threshold = env["SORTAI_SIMILARITY_THRESHOLD"], let value = Double(threshold) {
            config.memory.similarityThreshold = value
        }
        
        // Database overrides
        if let dbPath = env["SORTAI_DATABASE_PATH"] {
            config.persistence.databasePath = dbPath
        }
        if env["SORTAI_IN_MEMORY_DB"] == "true" {
            config.persistence.inMemory = true
        }
        
        // Environment override
        if let envStr = env["SORTAI_ENV"], let environment = AppEnvironment(rawValue: envStr) {
            config.environment = environment
        }
        
        return config
    }
    
    /// Reloads configuration from file
    func reload() {
        config = Self.loadConfiguration(from: configFilePath)
        hasUnsavedChanges = false
        notifyChangeHandlers()
    }
    
    // MARK: - Saving
    
    /// Saves current configuration to file
    func save() throws {
        // Ensure directory exists
        let directory = configFilePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        // Encode and save
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(config)
        try data.write(to: configFilePath, options: .atomic)
        
        // Sync to UserDefaults for @AppStorage compatibility
        config.syncToUserDefaults()
        
        hasUnsavedChanges = false
        lastError = nil
    }
    
    /// Saves configuration asynchronously
    func saveAsync() async throws {
        try save()
    }
    
    // MARK: - Updates
    
    /// Updates configuration with a closure
    func update(_ block: (inout AppConfiguration) -> Void) {
        var newConfig = config
        block(&newConfig)
        
        // Validate before applying
        let errors = newConfig.validate()
        if let error = errors.first {
            lastError = error
            return
        }
        
        config = newConfig
        hasUnsavedChanges = true
        lastError = nil
        notifyChangeHandlers()
    }
    
    /// Updates a specific configuration domain
    func updateOllama(_ block: (inout OllamaConfiguration) -> Void) {
        update { config in
            block(&config.ollama)
        }
    }
    
    func updateMemory(_ block: (inout MemoryConfiguration) -> Void) {
        update { config in
            block(&config.memory)
        }
    }
    
    func updateFeedback(_ block: (inout FeedbackConfiguration) -> Void) {
        update { config in
            block(&config.feedback)
        }
    }
    
    func updateAudio(_ block: (inout AudioConfiguration) -> Void) {
        update { config in
            block(&config.audio)
        }
    }
    
    func updateOrganization(_ block: (inout OrganizationConfiguration) -> Void) {
        update { config in
            block(&config.organization)
        }
    }
    
    // MARK: - Change Observation
    
    /// Registers a handler to be called when configuration changes
    func onConfigurationChange(_ handler: @escaping (AppConfiguration) -> Void) {
        changeHandlers.append(handler)
    }
    
    private func notifyChangeHandlers() {
        for handler in changeHandlers {
            handler(config)
        }
    }
    
    // MARK: - Convenience Accessors
    
    /// Current Ollama configuration
    var ollama: OllamaConfiguration { config.ollama }
    
    /// Current memory configuration
    var memory: MemoryConfiguration { config.memory }
    
    /// Current knowledge graph configuration
    var knowledgeGraph: KnowledgeGraphConfiguration { config.knowledgeGraph }
    
    /// Current feedback configuration
    var feedback: FeedbackConfiguration { config.feedback }
    
    /// Current audio configuration
    var audio: AudioConfiguration { config.audio }
    
    /// Current persistence configuration
    var persistence: PersistenceConfiguration { config.persistence }
    
    /// Current organization configuration
    var organization: OrganizationConfiguration { config.organization }
    
    /// Current processing configuration
    var processing: ProcessingConfiguration { config.processing }
    
    // MARK: - Reset
    
    /// Resets configuration to defaults
    func reset() {
        config = AppConfiguration.default
        hasUnsavedChanges = true
        notifyChangeHandlers()
    }
    
    /// Resets a specific configuration domain to defaults
    func resetOllama() {
        update { config in
            config.ollama = .default
        }
    }
    
    func resetMemory() {
        update { config in
            config.memory = .default
        }
    }
    
    func resetAll() throws {
        reset()
        try save()
    }
    
    // MARK: - Export/Import
    
    /// Exports configuration to a URL
    func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
    
    /// Imports configuration from a URL
    func `import`(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var newConfig = try decoder.decode(AppConfiguration.self, from: data)
        
        // Validate
        let errors = newConfig.validate()
        if let error = errors.first {
            throw error
        }
        
        // Apply environment overrides
        newConfig = Self.applyEnvironmentOverrides(to: newConfig)
        
        config = newConfig
        hasUnsavedChanges = true
        notifyChangeHandlers()
    }
}

// MARK: - Non-Isolated Access

extension ConfigurationManager {
    /// Thread-safe read-only access to current configuration
    nonisolated var currentConfig: AppConfiguration {
        // Note: In production, this would need proper synchronization
        // For now, we rely on the fact that AppConfiguration is Sendable
        MainActor.assumeIsolated {
            return ConfigurationManager.shared.config
        }
    }
}

// MARK: - Testing Support

extension ConfigurationManager {
    /// Creates a test configuration manager with in-memory settings
    static func forTesting() -> ConfigurationManager {
        let tempDir = FileManager.default.temporaryDirectory
        let configPath = tempDir.appendingPathComponent("test-config-\(UUID().uuidString).json")
        let manager = ConfigurationManager(configPath: configPath)
        manager.config = .testing
        return manager
    }
}

