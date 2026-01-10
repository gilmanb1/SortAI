// MARK: - Unified Application Configuration
// Type-safe, hierarchical configuration for all SortAI components
// Supports JSON persistence, environment overrides, and runtime observation

import Foundation

// MARK: - Configuration Domains

/// Ollama LLM server and model configuration
struct OllamaConfiguration: Codable, Sendable, Equatable {
    /// Server host URL (e.g., "http://127.0.0.1:11434")
    var host: String
    
    /// Model used for document categorization (PDF, text, etc.)
    var documentModel: String
    
    /// Model used for video categorization
    var videoModel: String
    
    /// Model used for image categorization
    var imageModel: String
    
    /// Model used for audio categorization
    var audioModel: String
    
    /// Model used for generating embeddings
    var embeddingModel: String
    
    /// LLM temperature (0.0-1.0, lower = more deterministic)
    var temperature: Double
    
    /// Maximum tokens in LLM response
    var maxTokens: Int
    
    /// Request timeout in seconds
    var timeout: TimeInterval
    
    /// Default model for all LLM operations
    static let defaultModel = "deepseek-r1:8b"
    
    static let `default` = OllamaConfiguration(
        host: "http://127.0.0.1:11434",
        documentModel: defaultModel,
        videoModel: defaultModel,
        imageModel: defaultModel,
        audioModel: defaultModel,
        embeddingModel: defaultModel,
        temperature: 0.3,
        maxTokens: 1000,
        timeout: 60.0
    )
    
    /// Returns the appropriate model for a given media kind
    func model(for kind: MediaKind) -> String {
        switch kind {
        case .document: return documentModel
        case .video: return videoModel
        case .image: return imageModel
        case .audio: return audioModel
        case .unknown: return documentModel
        }
    }
    
    /// Creates a uniform configuration with the same model for all types
    static func uniform(host: String = "http://127.0.0.1:11434", model: String = defaultModel) -> OllamaConfiguration {
        OllamaConfiguration(
            host: host,
            documentModel: model,
            videoModel: model,
            imageModel: model,
            audioModel: model,
            embeddingModel: model,
            temperature: 0.3,
            maxTokens: 1000,
            timeout: 60.0
        )
    }
}

// MARK: - UserDefaults Keys and Registration

/// Centralized UserDefaults key constants for consistency
enum SortAIDefaultsKey {
    static let ollamaHost = "ollamaHost"
    static let documentModel = "documentModel"
    static let videoModel = "videoModel"
    static let imageModel = "imageModel"
    static let audioModel = "audioModel"
    static let embeddingModel = "embeddingModel"
    static let embeddingDimensions = "embeddingDimensions"
    static let defaultOrganizationMode = "defaultOrganizationMode"
    static let lastOutputFolder = "lastOutputFolder"
    
    // v1.1 settings
    static let organizationDestination = "organizationDestination"
    static let customDestinationPath = "customDestinationPath"
    static let maxTaxonomyDepth = "maxTaxonomyDepth"
    static let stabilityVsCorrectness = "stabilityVsCorrectness"
    static let enableDeepAnalysis = "enableDeepAnalysis"
    static let deepAnalysisFileTypes = "deepAnalysisFileTypes"
    static let useSoftMove = "useSoftMove"
    static let enableNotifications = "enableNotifications"
    static let respectBatteryStatus = "respectBatteryStatus"
    static let enableWatchMode = "enableWatchMode"
    static let watchQuietPeriod = "watchQuietPeriod"
    
    // v2.0 Apple Intelligence settings
    static let providerPreference = "providerPreference"
    static let escalationThreshold = "escalationThreshold"
    static let autoAcceptThreshold = "autoAcceptThreshold"
    static let autoInstallOllama = "autoInstallOllama"
    static let enableFAISS = "enableFAISS"
    static let useAppleEmbeddings = "useAppleEmbeddings"
}

/// Registers default values in UserDefaults at app startup
/// Call this from the App init() before any @AppStorage properties are accessed
enum SortAIDefaults {
    /// Registers all default values with UserDefaults
    /// This ensures consistent defaults across the app and persistence across sessions
    static func registerDefaults() {
        let defaults: [String: Any] = [
            // AI Provider settings (v2.0) - Apple Intelligence as default
            SortAIDefaultsKey.providerPreference: ProviderPreference.automatic.rawValue,
            SortAIDefaultsKey.escalationThreshold: 0.5,
            SortAIDefaultsKey.autoAcceptThreshold: 0.85,
            SortAIDefaultsKey.autoInstallOllama: true,
            SortAIDefaultsKey.enableFAISS: false,
            SortAIDefaultsKey.useAppleEmbeddings: true,
            
            // Ollama settings - using deepseek-r1 as default model
            SortAIDefaultsKey.ollamaHost: "http://127.0.0.1:11434",
            SortAIDefaultsKey.documentModel: OllamaConfiguration.defaultModel,
            SortAIDefaultsKey.videoModel: OllamaConfiguration.defaultModel,
            SortAIDefaultsKey.imageModel: OllamaConfiguration.defaultModel,
            SortAIDefaultsKey.audioModel: OllamaConfiguration.defaultModel,
            SortAIDefaultsKey.embeddingModel: OllamaConfiguration.defaultModel,
            SortAIDefaultsKey.embeddingDimensions: 512,  // Updated for Apple NLEmbedding compatibility
            
            // Organization settings
            SortAIDefaultsKey.defaultOrganizationMode: OrganizationMode.copy.rawValue,
            SortAIDefaultsKey.organizationDestination: "centralized",
            SortAIDefaultsKey.customDestinationPath: "",
            SortAIDefaultsKey.maxTaxonomyDepth: 5,
            SortAIDefaultsKey.stabilityVsCorrectness: 0.5,
            
            // Deep analysis settings
            SortAIDefaultsKey.enableDeepAnalysis: true,
            SortAIDefaultsKey.deepAnalysisFileTypes: "pdf,docx,mp4,jpg",
            SortAIDefaultsKey.useSoftMove: false,
            
            // System settings
            SortAIDefaultsKey.enableNotifications: true,
            SortAIDefaultsKey.respectBatteryStatus: true,
            SortAIDefaultsKey.enableWatchMode: false,
            SortAIDefaultsKey.watchQuietPeriod: 3.0,
        ]
        
        UserDefaults.standard.register(defaults: defaults)
        NSLog("📋 [CONFIG] Registered defaults with AI Provider: automatic (Apple Intelligence + fallback)")
    }
    
    /// Returns the current default model name
    static var defaultModel: String {
        OllamaConfiguration.defaultModel
    }
    
    /// Check if Apple Intelligence is available on this system
    static var isAppleIntelligenceAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }
}

/// Memory and embedding configuration
struct MemoryConfiguration: Codable, Sendable, Equatable {
    /// Embedding vector dimensions (must match model output)
    var embeddingDimensions: Int
    
    /// Minimum similarity score to consider a memory match (0.0-1.0)
    var similarityThreshold: Double
    
    /// Whether to check memory before invoking LLM
    var useMemoryFirst: Bool
    
    /// Maximum patterns to retain in memory
    var maxPatterns: Int
    
    /// Minimum confidence for pattern retention
    var minPatternConfidence: Double
    
    static let `default` = MemoryConfiguration(
        embeddingDimensions: 384,
        similarityThreshold: 0.85,
        useMemoryFirst: true,
        maxPatterns: 10000,
        minPatternConfidence: 0.5
    )
}

/// Knowledge graph and learning configuration
struct KnowledgeGraphConfiguration: Codable, Sendable, Equatable {
    /// Whether to use knowledge graph for category suggestions
    var enabled: Bool
    
    /// Maximum category suggestions to retrieve
    var maxSuggestions: Int
    
    /// Minimum relationship weight for suggestions
    var minRelationshipWeight: Double
    
    /// Whether to learn from human corrections
    var learnFromFeedback: Bool
    
    static let `default` = KnowledgeGraphConfiguration(
        enabled: true,
        maxSuggestions: 5,
        minRelationshipWeight: 0.1,
        learnFromFeedback: true
    )
}

/// Human feedback and review configuration
struct FeedbackConfiguration: Codable, Sendable, Equatable {
    /// Confidence threshold for auto-accepting categorizations (0.0-1.0)
    var autoAcceptThreshold: Double
    
    /// Confidence threshold below which review is required (0.0-1.0)
    var reviewThreshold: Double
    
    /// Maximum items in pending review queue
    var maxPendingItems: Int
    
    /// Days to retain completed feedback items
    var retentionDays: Int
    
    static let `default` = FeedbackConfiguration(
        autoAcceptThreshold: 0.85,
        reviewThreshold: 0.5,
        maxPendingItems: 1000,
        retentionDays: 90
    )
}

/// Audio processing configuration
struct AudioConfiguration: Codable, Sendable, Equatable {
    /// Target duration of speech to collect (seconds)
    var targetSpeechDuration: TimeInterval
    
    /// Minimum segment duration to consider (seconds)
    var minSegmentDuration: TimeInterval
    
    /// Output sample rate (Hz)
    var outputSampleRate: Double
    
    /// Energy threshold for speech detection (0.0-1.0)
    var speechEnergyThreshold: Float
    
    /// Maximum time to scan before giving up (seconds)
    var maxScanDuration: TimeInterval
    
    /// Chunk size for processing (samples)
    var chunkSize: Int
    
    // MARK: - Multi-clip extraction settings
    
    /// Maximum total audio duration across all clips (seconds)
    var maxTotalAudioDuration: TimeInterval
    
    /// Duration of each clip for long videos (seconds)
    var clipDurationShort: TimeInterval
    
    /// Maximum number of clips to extract per video
    var maxClipsPerVideo: Int
    
    /// Use VAD (Voice Activity Detection) as first extraction method
    var useVADFirst: Bool
    
    /// Enable FFmpeg audio separation on transcription failure
    var enableAudioSeparation: Bool
    
    /// Maximum concurrent extractions (0 = auto-detect)
    var maxConcurrentExtractions: Int
    
    /// Prefer streaming transcription over file-based
    var useStreamingTranscription: Bool
    
    /// Retry transient errors with exponential backoff
    var retryTransientErrors: Bool
    
    /// Maximum retry attempts per clip
    var maxRetriesPerClip: Int
    
    static let `default` = AudioConfiguration(
        targetSpeechDuration: 90.0,
        minSegmentDuration: 1.0,
        outputSampleRate: 16000.0,
        speechEnergyThreshold: 0.02,
        maxScanDuration: 600.0,
        chunkSize: 4096,
        maxTotalAudioDuration: 300.0,
        clipDurationShort: 45.0,
        maxClipsPerVideo: 5,
        useVADFirst: true,
        enableAudioSeparation: true,
        maxConcurrentExtractions: 0,  // Auto-detect
        useStreamingTranscription: true,
        retryTransientErrors: true,
        maxRetriesPerClip: 2
    )
    
    static let fast = AudioConfiguration(
        targetSpeechDuration: 45.0,
        minSegmentDuration: 2.0,
        outputSampleRate: 16000.0,
        speechEnergyThreshold: 0.03,
        maxScanDuration: 300.0,
        chunkSize: 8192,
        maxTotalAudioDuration: 300.0,
        clipDurationShort: 30.0,
        maxClipsPerVideo: 3,
        useVADFirst: true,
        enableAudioSeparation: true,
        maxConcurrentExtractions: 0,  // Auto-detect
        useStreamingTranscription: true,
        retryTransientErrors: true,
        maxRetriesPerClip: 2
    )
}

/// Database and persistence configuration
struct PersistenceConfiguration: Codable, Sendable, Equatable {
    /// Custom database path (nil = default location)
    var databasePath: String?
    
    /// Use in-memory database (for testing)
    var inMemory: Bool
    
    /// Enable WAL (Write-Ahead Logging) mode
    var enableWAL: Bool
    
    /// Enable foreign key constraints
    var enableForeignKeys: Bool
    
    /// Run VACUUM on startup
    var vacuumOnStartup: Bool
    
    static let `default` = PersistenceConfiguration(
        databasePath: nil,
        inMemory: false,
        enableWAL: true,
        enableForeignKeys: true,
        vacuumOnStartup: false
    )
    
    static let testing = PersistenceConfiguration(
        databasePath: ":memory:",
        inMemory: true,
        enableWAL: false,
        enableForeignKeys: true,
        vacuumOnStartup: false
    )
}

/// File organization configuration
struct OrganizationConfiguration: Codable, Sendable, Equatable {
    /// Default organization mode
    var defaultMode: OrganizationMode
    
    /// Create .sortai metadata files
    var createMetadataFiles: Bool
    
    /// Preserve original file timestamps
    var preserveTimestamps: Bool
    
    /// Maximum filename length
    var maxFilenameLength: Int
    
    /// Characters to replace in filenames
    var invalidCharacters: String
    
    static let `default` = OrganizationConfiguration(
        defaultMode: .copy,
        createMetadataFiles: false,
        preserveTimestamps: true,
        maxFilenameLength: 200,
        invalidCharacters: "/\\:*?\"<>|"
    )
}

/// Processing configuration (concurrency, batching, caching)
struct ProcessingConfiguration: Codable, Sendable, Equatable {
    /// Maximum concurrent file processing tasks
    var maxConcurrentTasks: Int
    
    /// Batch size for bulk operations
    var batchSize: Int
    
    /// Enable processing cache
    var enableCache: Bool
    
    /// Cache expiration in hours
    var cacheExpirationHours: Int
    
    static let `default` = ProcessingConfiguration(
        maxConcurrentTasks: 4,
        batchSize: 10,
        enableCache: true,
        cacheExpirationHours: 24
    )
}

/// Logging configuration for dev mode file logging
struct LoggingConfiguration: Codable, Sendable, Equatable {
    /// Directory where log files are stored
    var logDirectory: String
    
    /// Maximum age of log files in days before cleanup
    var maxAgeDays: Int
    
    /// Maximum total size of logs in bytes before cleanup
    var maxTotalSizeBytes: Int64
    
    /// Whether to also print to console (stdout/stderr)
    var printToConsole: Bool
    
    /// Whether file logging is enabled
    var enabled: Bool
    
    private static var defaultLogDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SortAI/logs").path
    }
    
    static let `default` = LoggingConfiguration(
        logDirectory: defaultLogDirectory,
        maxAgeDays: 30,
        maxTotalSizeBytes: 1_073_741_824, // 1GB
        printToConsole: ProcessInfo.processInfo.environment["SORTAI_LOG_CONSOLE"] == "1",
        enabled: true
    )
    
    /// Convert to FileLogger's LogConfiguration
    var asLogConfiguration: LogConfiguration {
        LogConfiguration(
            logDirectory: logDirectory,
            maxAgeDays: maxAgeDays,
            maxTotalSizeBytes: maxTotalSizeBytes,
            printToConsole: printToConsole,
            enabled: enabled
        )
    }
}

/// AI Provider configuration (Apple Intelligence, Ollama, Cloud)
struct AIProviderConfiguration: Codable, Sendable, Equatable {
    /// User preference for LLM provider selection
    var preference: ProviderPreference
    
    /// Confidence threshold for escalating to next provider (0.0-1.0)
    var escalationThreshold: Double
    
    /// Confidence threshold for auto-accepting categorizations (0.0-1.0)
    var autoAcceptThreshold: Double
    
    /// Whether to automatically install Ollama if not found
    var autoInstallOllama: Bool
    
    /// Whether to enable FAISS for vector similarity search
    var enableFAISS: Bool
    
    /// Whether to use Apple NLEmbedding for embeddings (vs NGram)
    var useAppleEmbeddings: Bool
    
    /// Weight for Apple Intelligence embeddings when combining (0.0-1.0)
    var appleEmbeddingWeight: Double
    
    /// Maximum retry attempts per provider
    var maxRetryAttempts: Int
    
    /// Session pool size for Apple Intelligence
    var sessionPoolSize: Int
    
    /// Request timeout in seconds
    var requestTimeout: TimeInterval
    
    static let `default` = AIProviderConfiguration(
        preference: .automatic,
        escalationThreshold: 0.5,
        autoAcceptThreshold: 0.85,
        autoInstallOllama: true,
        enableFAISS: false,
        useAppleEmbeddings: true,
        appleEmbeddingWeight: 0.6,
        maxRetryAttempts: 1,
        sessionPoolSize: 3,
        requestTimeout: 30.0
    )
    
    static let appleOnly = AIProviderConfiguration(
        preference: .appleIntelligenceOnly,
        escalationThreshold: 0.5,
        autoAcceptThreshold: 0.85,
        autoInstallOllama: false,
        enableFAISS: false,
        useAppleEmbeddings: true,
        appleEmbeddingWeight: 1.0,
        maxRetryAttempts: 2,
        sessionPoolSize: 3,
        requestTimeout: 30.0
    )
    
    static let ollamaPreferred = AIProviderConfiguration(
        preference: .preferOllama,
        escalationThreshold: 0.5,
        autoAcceptThreshold: 0.85,
        autoInstallOllama: true,
        enableFAISS: false,
        useAppleEmbeddings: false,
        appleEmbeddingWeight: 0.3,
        maxRetryAttempts: 1,
        sessionPoolSize: 2,
        requestTimeout: 60.0
    )
}

// MARK: - Environment

/// Runtime environment for configuration overrides
enum AppEnvironment: String, Codable, Sendable, CaseIterable {
    case development
    case staging
    case production
    case testing
    
    static var current: AppEnvironment {
        #if DEBUG
        return .development
        #else
        if ProcessInfo.processInfo.environment["SORTAI_ENV"] == "staging" {
            return .staging
        } else if ProcessInfo.processInfo.environment["SORTAI_ENV"] == "testing" {
            return .testing
        }
        return .production
        #endif
    }
}

// MARK: - Unified Configuration

/// Complete application configuration
/// Consolidates all settings into a single, type-safe structure
struct AppConfiguration: Codable, Sendable, Equatable {
    /// Configuration file format version (2 = Apple Intelligence support)
    var version: Int
    
    /// Runtime environment
    var environment: AppEnvironment
    
    /// AI Provider settings (Apple Intelligence, Ollama, Cloud)
    var aiProvider: AIProviderConfiguration
    
    /// Ollama LLM settings
    var ollama: OllamaConfiguration
    
    /// Memory and embedding settings
    var memory: MemoryConfiguration
    
    /// Knowledge graph settings
    var knowledgeGraph: KnowledgeGraphConfiguration
    
    /// Feedback and review settings
    var feedback: FeedbackConfiguration
    
    /// Audio processing settings
    var audio: AudioConfiguration
    
    /// Database settings
    var persistence: PersistenceConfiguration
    
    /// File organization settings
    var organization: OrganizationConfiguration
    
    /// Processing settings
    var processing: ProcessingConfiguration
    
    /// Logging settings (dev mode file logging)
    var logging: LoggingConfiguration
    
    /// Application-level settings
    var lastOutputFolder: String?
    
    /// Current configuration version
    static let currentVersion = 2
    
    // MARK: - Defaults
    
    static let `default` = AppConfiguration(
        version: currentVersion,
        environment: AppEnvironment.current,
        aiProvider: AIProviderConfiguration.default,
        ollama: OllamaConfiguration.default,
        memory: MemoryConfiguration.default,
        knowledgeGraph: KnowledgeGraphConfiguration.default,
        feedback: FeedbackConfiguration.default,
        audio: AudioConfiguration.default,
        persistence: PersistenceConfiguration.default,
        organization: OrganizationConfiguration.default,
        processing: ProcessingConfiguration.default,
        logging: LoggingConfiguration.default,
        lastOutputFolder: nil
    )
    
    static let testing = AppConfiguration(
        version: currentVersion,
        environment: AppEnvironment.testing,
        aiProvider: AIProviderConfiguration.default,
        ollama: OllamaConfiguration.default,
        memory: MemoryConfiguration.default,
        knowledgeGraph: KnowledgeGraphConfiguration.default,
        feedback: FeedbackConfiguration.default,
        audio: AudioConfiguration.fast,
        persistence: PersistenceConfiguration.testing,
        organization: OrganizationConfiguration.default,
        processing: ProcessingConfiguration.default,
        logging: LoggingConfiguration.default,
        lastOutputFolder: nil
    )
    
    // MARK: - Validation
    
    /// Validates configuration values and returns any errors
    func validate() -> [ConfigurationError] {
        var errors: [ConfigurationError] = []
        
        // AI Provider validation
        if aiProvider.escalationThreshold < 0 || aiProvider.escalationThreshold > 1 {
            errors.append(.invalidValue("aiProvider.escalationThreshold", "Must be between 0.0 and 1.0"))
        }
        if aiProvider.autoAcceptThreshold < 0 || aiProvider.autoAcceptThreshold > 1 {
            errors.append(.invalidValue("aiProvider.autoAcceptThreshold", "Must be between 0.0 and 1.0"))
        }
        if aiProvider.appleEmbeddingWeight < 0 || aiProvider.appleEmbeddingWeight > 1 {
            errors.append(.invalidValue("aiProvider.appleEmbeddingWeight", "Must be between 0.0 and 1.0"))
        }
        if aiProvider.sessionPoolSize < 1 || aiProvider.sessionPoolSize > 10 {
            errors.append(.invalidValue("aiProvider.sessionPoolSize", "Must be between 1 and 10"))
        }
        
        // Ollama validation
        if ollama.temperature < 0 || ollama.temperature > 2 {
            errors.append(.invalidValue("ollama.temperature", "Must be between 0.0 and 2.0"))
        }
        if ollama.maxTokens < 1 {
            errors.append(.invalidValue("ollama.maxTokens", "Must be at least 1"))
        }
        if ollama.timeout < 1 {
            errors.append(.invalidValue("ollama.timeout", "Must be at least 1 second"))
        }
        
        // Memory validation
        if memory.embeddingDimensions < 64 || memory.embeddingDimensions > 4096 {
            errors.append(.invalidValue("memory.embeddingDimensions", "Must be between 64 and 4096"))
        }
        if memory.similarityThreshold < 0 || memory.similarityThreshold > 1 {
            errors.append(.invalidValue("memory.similarityThreshold", "Must be between 0.0 and 1.0"))
        }
        
        // Feedback validation
        if feedback.autoAcceptThreshold < feedback.reviewThreshold {
            errors.append(.invalidValue("feedback.autoAcceptThreshold", "Must be >= reviewThreshold"))
        }
        
        // Audio validation
        if audio.speechEnergyThreshold < 0 || audio.speechEnergyThreshold > 1 {
            errors.append(.invalidValue("audio.speechEnergyThreshold", "Must be between 0.0 and 1.0"))
        }
        
        return errors
    }
    
    var isValid: Bool {
        validate().isEmpty
    }
    
    // MARK: - Migration
    
    /// Migrate from older configuration versions
    static func migrate(from oldConfig: AppConfiguration) -> AppConfiguration {
        var newConfig = oldConfig
        
        // Version 1 -> 2: Add AI provider settings
        if oldConfig.version < 2 {
            newConfig.aiProvider = AIProviderConfiguration.default
            newConfig.version = 2
            NSLog("📋 [CONFIG] Migrated from version 1 to 2 (added AI provider settings)")
        }
        
        return newConfig
    }
}

// MARK: - Configuration Errors

enum ConfigurationError: LocalizedError, Equatable {
    case fileNotFound(String)
    case invalidJSON(String)
    case invalidValue(String, String)
    case migrationFailed(String)
    case saveFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Configuration file not found: \(path)"
        case .invalidJSON(let reason):
            return "Invalid configuration JSON: \(reason)"
        case .invalidValue(let key, let reason):
            return "Invalid configuration value '\(key)': \(reason)"
        case .migrationFailed(let reason):
            return "Configuration migration failed: \(reason)"
        case .saveFailed(let reason):
            return "Failed to save configuration: \(reason)"
        }
    }
}

// MARK: - Legacy Conversion

extension AppConfiguration {
    /// Creates configuration from legacy UserDefaults values
    static func fromUserDefaults() -> AppConfiguration {
        let defaults = UserDefaults.standard
        
        var config = AppConfiguration.default
        
        // Migrate Ollama settings
        if let host = defaults.string(forKey: "ollamaHost") {
            config.ollama.host = host
        }
        if let model = defaults.string(forKey: "documentModel") {
            config.ollama.documentModel = model
        }
        if let model = defaults.string(forKey: "videoModel") {
            config.ollama.videoModel = model
        }
        if let model = defaults.string(forKey: "imageModel") {
            config.ollama.imageModel = model
        }
        if let model = defaults.string(forKey: "audioModel") {
            config.ollama.audioModel = model
        }
        if let model = defaults.string(forKey: "embeddingModel") {
            config.ollama.embeddingModel = model
        }
        
        // Migrate memory settings
        let dimensions = defaults.integer(forKey: "embeddingDimensions")
        if dimensions > 0 {
            config.memory.embeddingDimensions = dimensions
        }
        
        // Migrate organization settings
        if let modeRaw = defaults.string(forKey: "defaultOrganizationMode"),
           let mode = OrganizationMode(rawValue: modeRaw) {
            config.organization.defaultMode = mode
        }
        
        // Migrate app settings
        if let path = defaults.string(forKey: "lastOutputFolder") {
            config.lastOutputFolder = path
        }
        
        return config
    }
    
    /// Saves configuration values back to UserDefaults for @AppStorage compatibility
    func syncToUserDefaults() {
        let defaults = UserDefaults.standard
        
        defaults.set(ollama.host, forKey: "ollamaHost")
        defaults.set(ollama.documentModel, forKey: "documentModel")
        defaults.set(ollama.videoModel, forKey: "videoModel")
        defaults.set(ollama.imageModel, forKey: "imageModel")
        defaults.set(ollama.audioModel, forKey: "audioModel")
        defaults.set(ollama.embeddingModel, forKey: "embeddingModel")
        defaults.set(memory.embeddingDimensions, forKey: "embeddingDimensions")
        defaults.set(organization.defaultMode.rawValue, forKey: "defaultOrganizationMode")
        
        if let path = lastOutputFolder {
            defaults.set(path, forKey: "lastOutputFolder")
        }
    }
}

// MARK: - Bridge Types

extension AppConfiguration {
    /// Creates a BrainConfiguration from current settings
    func toBrainConfiguration() -> BrainConfiguration {
        BrainConfiguration(
            host: ollama.host,
            documentModel: ollama.documentModel,
            videoModel: ollama.videoModel,
            imageModel: ollama.imageModel,
            audioModel: ollama.audioModel,
            embeddingModel: ollama.embeddingModel,
            temperature: ollama.temperature,
            maxTokens: ollama.maxTokens,
            timeout: ollama.timeout
        )
    }
    
    /// Creates a DatabaseConfiguration from current settings
    func toDatabaseConfiguration() -> DatabaseConfiguration {
        if persistence.inMemory {
            return .inMemory
        } else if let path = persistence.databasePath {
            return .custom(path: path)
        }
        return .default
    }
    
    /// Creates an AudioSamplerConfig from current settings
    func toAudioSamplerConfig() -> AudioSamplerConfig {
        AudioSamplerConfig(
            targetSpeechDuration: audio.targetSpeechDuration,
            minSegmentDuration: audio.minSegmentDuration,
            outputSampleRate: audio.outputSampleRate,
            speechEnergyThreshold: audio.speechEnergyThreshold,
            maxScanDuration: audio.maxScanDuration,
            chunkSize: audio.chunkSize
        )
    }
}

