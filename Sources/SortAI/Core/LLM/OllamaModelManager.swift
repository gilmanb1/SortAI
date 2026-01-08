// MARK: - Ollama Model Manager
// Handles model availability checking, downloading, and fallback logic

import Foundation

// MARK: - Model Status

/// Status of a model in Ollama
enum OllamaModelStatus: Equatable, Sendable {
    case available
    case downloading(progress: Double)
    case notFound
    case error(String)
}

// MARK: - Model Download Progress

/// Progress information for model downloads
struct ModelDownloadProgress: Sendable {
    let modelName: String
    let status: String
    let completed: Int64
    let total: Int64
    
    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
    
    var progressPercent: Int {
        Int(progress * 100)
    }
    
    var isComplete: Bool {
        status == "success"
    }
}

// MARK: - Ollama Model Manager

/// Manages Ollama model availability, downloading, and fallback
actor OllamaModelManager {
    
    // MARK: - Singleton
    
    static let shared = OllamaModelManager()
    
    // MARK: - Properties
    
    private var host: String
    private let session: URLSession
    private let decoder = JSONDecoder()
    
    /// Cache of available models (refreshed periodically)
    private var cachedModels: [String] = []
    private var lastCacheRefresh: Date?
    private let cacheExpiration: TimeInterval = 60.0 // 1 minute
    
    /// Active download tasks
    private var activeDownloads: [String: Task<Bool, Error>] = [:]
    
    /// Download progress callbacks
    private var progressCallbacks: [String: [(ModelDownloadProgress) -> Void]] = [:]
    
    // MARK: - Initialization
    
    init(host: String = "http://127.0.0.1:11434") {
        self.host = host
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 3600.0 // 1 hour for large model downloads
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Configuration
    
    /// Update the Ollama host URL
    func setHost(_ newHost: String) {
        self.host = newHost
        // Invalidate cache when host changes
        cachedModels = []
        lastCacheRefresh = nil
    }
    
    // MARK: - Model Availability
    
    /// Check if Ollama server is reachable
    func isOllamaAvailable() async -> Bool {
        guard let url = URL(string: "\(host)/api/tags") else { return false }
        
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            NSLog("❌ [OllamaModelManager] Server not available: %@", error.localizedDescription)
            return false
        }
    }
    
    /// Get list of all available models
    func listAvailableModels(forceRefresh: Bool = false) async throws -> [String] {
        // Return cached if still valid
        if !forceRefresh,
           let lastRefresh = lastCacheRefresh,
           Date().timeIntervalSince(lastRefresh) < cacheExpiration,
           !cachedModels.isEmpty {
            return cachedModels
        }
        
        guard let url = URL(string: "\(host)/api/tags") else {
            throw OllamaModelError.invalidHost(host)
        }
        
        struct TagsResponse: Decodable {
            struct Model: Decodable {
                let name: String
            }
            let models: [Model]
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaModelError.serverUnavailable
        }
        
        let tagsResponse = try decoder.decode(TagsResponse.self, from: data)
        cachedModels = tagsResponse.models.map { $0.name }
        lastCacheRefresh = Date()
        
        NSLog("📋 [OllamaModelManager] Found %d models: %@", cachedModels.count, cachedModels.joined(separator: ", "))
        
        return cachedModels
    }
    
    /// Check if a specific model is available
    func isModelAvailable(_ modelName: String) async -> Bool {
        do {
            let models = try await listAvailableModels()
            return findMatchingModel(modelName, in: models) != nil
        } catch {
            return false
        }
    }
    
    /// Find a model that matches the requested name (handles partial matches like "deepseek-r1" -> "deepseek-r1:8b")
    func findMatchingModel(_ requestedModel: String, in availableModels: [String]) -> String? {
        // Exact match first
        if availableModels.contains(requestedModel) {
            return requestedModel
        }
        
        // Try to find a model that starts with the requested name (e.g., "deepseek-r1" matches "deepseek-r1:8b")
        let normalizedRequest = requestedModel.lowercased()
        
        // First try: exact prefix match with colon (e.g., "deepseek-r1" matches "deepseek-r1:8b")
        if let match = availableModels.first(where: { $0.lowercased().hasPrefix(normalizedRequest + ":") }) {
            NSLog("🔍 [OllamaModelManager] Matched '%@' to '%@' (prefix with tag)", requestedModel, match)
            return match
        }
        
        // Second try: exact match ignoring case
        if let match = availableModels.first(where: { $0.lowercased() == normalizedRequest }) {
            NSLog("🔍 [OllamaModelManager] Matched '%@' to '%@' (case insensitive)", requestedModel, match)
            return match
        }
        
        // Third try: starts with (for things like "llama3.2" matching "llama3.2:latest")
        if let match = availableModels.first(where: { $0.lowercased().hasPrefix(normalizedRequest) }) {
            NSLog("🔍 [OllamaModelManager] Matched '%@' to '%@' (prefix)", requestedModel, match)
            return match
        }
        
        return nil
    }
    
    // MARK: - Model Resolution
    
    /// Resolve the best available model, downloading if necessary
    /// Returns the actual model name to use
    func resolveModel(
        requested: String,
        fallbacks: [String] = [],
        autoDownload: Bool = true,
        progressHandler: (@Sendable (ModelDownloadProgress) -> Void)? = nil
    ) async throws -> String {
        NSLog("🔄 [OllamaModelManager] Resolving model: %@", requested)
        
        // Check server availability first
        guard await isOllamaAvailable() else {
            throw OllamaModelError.serverUnavailable
        }
        
        let availableModels = try await listAvailableModels(forceRefresh: true)
        
        // Try to find the requested model
        if let match = findMatchingModel(requested, in: availableModels) {
            NSLog("✅ [OllamaModelManager] Model '%@' resolved to '%@'", requested, match)
            return match
        }
        
        // Model not found - try to download if enabled
        if autoDownload {
            NSLog("📥 [OllamaModelManager] Model '%@' not found, attempting download...", requested)
            
            let success = try await pullModel(requested, progressHandler: progressHandler)
            if success {
                // Refresh cache and return the model
                let updatedModels = try await listAvailableModels(forceRefresh: true)
                if let match = findMatchingModel(requested, in: updatedModels) {
                    NSLog("✅ [OllamaModelManager] Model '%@' downloaded successfully, resolved to '%@'", requested, match)
                    return match
                }
            }
        }
        
        // Download failed or disabled - try fallbacks
        for fallback in fallbacks {
            if let match = findMatchingModel(fallback, in: availableModels) {
                NSLog("⚠️ [OllamaModelManager] Using fallback model '%@' instead of '%@'", match, requested)
                return match
            }
        }
        
        // No fallbacks available - try any available model
        if let firstAvailable = availableModels.first {
            NSLog("⚠️ [OllamaModelManager] Using first available model '%@' as last resort", firstAvailable)
            return firstAvailable
        }
        
        throw OllamaModelError.noModelsAvailable
    }
    
    // MARK: - Model Downloading
    
    /// Pull/download a model from Ollama library
    func pullModel(
        _ modelName: String,
        progressHandler: (@Sendable (ModelDownloadProgress) -> Void)? = nil
    ) async throws -> Bool {
        // Check if already downloading
        if let existingTask = activeDownloads[modelName] {
            NSLog("⏳ [OllamaModelManager] Model '%@' already downloading, waiting...", modelName)
            return try await existingTask.value
        }
        
        NSLog("📥 [OllamaModelManager] Starting download of model: %@", modelName)
        
        let task = Task<Bool, Error> {
            try await performPull(modelName, progressHandler: progressHandler)
        }
        
        activeDownloads[modelName] = task
        
        defer {
            activeDownloads.removeValue(forKey: modelName)
        }
        
        return try await task.value
    }
    
    private func performPull(
        _ modelName: String,
        progressHandler: (@Sendable (ModelDownloadProgress) -> Void)?
    ) async throws -> Bool {
        guard let url = URL(string: "\(host)/api/pull") else {
            throw OllamaModelError.invalidHost(host)
        }
        
        struct PullRequest: Encodable {
            let name: String
            let stream: Bool
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PullRequest(name: modelName, stream: true))
        
        // Use streaming to get progress updates
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaModelError.downloadFailed("No HTTP response")
        }
        
        if httpResponse.statusCode != 200 {
            throw OllamaModelError.downloadFailed("HTTP \(httpResponse.statusCode)")
        }
        
        struct PullProgress: Decodable {
            let status: String
            let digest: String?
            let total: Int64?
            let completed: Int64?
        }
        
        var lastProgress: ModelDownloadProgress?
        
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8) else { continue }
            
            do {
                let progress = try decoder.decode(PullProgress.self, from: data)
                
                let downloadProgress = ModelDownloadProgress(
                    modelName: modelName,
                    status: progress.status,
                    completed: progress.completed ?? 0,
                    total: progress.total ?? 0
                )
                
                lastProgress = downloadProgress
                
                // Report progress
                if let handler = progressHandler {
                    await MainActor.run {
                        handler(downloadProgress)
                    }
                }
                
                // Log significant progress
                if progress.total ?? 0 > 0 {
                    let percent = Int(Double(progress.completed ?? 0) / Double(progress.total!) * 100)
                    if percent % 10 == 0 {
                        NSLog("📥 [OllamaModelManager] Downloading %@: %d%%", modelName, percent)
                    }
                }
                
                if progress.status == "success" {
                    NSLog("✅ [OllamaModelManager] Model '%@' downloaded successfully!", modelName)
                    return true
                }
            } catch {
                // Skip malformed lines
                continue
            }
        }
        
        // Check if we got a success status
        if lastProgress?.isComplete == true {
            return true
        }
        
        throw OllamaModelError.downloadFailed("Download stream ended without success")
    }
    
    // MARK: - Model Information
    
    /// Get detailed information about a model
    func getModelInfo(_ modelName: String) async throws -> OllamaModelInfo {
        guard let url = URL(string: "\(host)/api/show") else {
            throw OllamaModelError.invalidHost(host)
        }
        
        struct ShowRequest: Encodable {
            let name: String
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ShowRequest(name: modelName))
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaModelError.invalidHost(host)
        }
        
        if httpResponse.statusCode == 404 {
            throw OllamaModelError.modelNotFound(modelName)
        }
        
        if httpResponse.statusCode != 200 {
            throw OllamaModelError.serverError("HTTP \(httpResponse.statusCode)")
        }
        
        return try decoder.decode(OllamaModelInfo.self, from: data)
    }
}

// MARK: - Model Info

/// Detailed information about an Ollama model
struct OllamaModelInfo: Decodable, Sendable {
    let modelfile: String?
    let parameters: String?
    let template: String?
    let details: Details?
    
    struct Details: Decodable, Sendable {
        let parentModel: String?
        let format: String?
        let family: String?
        let families: [String]?
        let parameterSize: String?
        let quantizationLevel: String?
        
        enum CodingKeys: String, CodingKey {
            case parentModel = "parent_model"
            case format, family, families
            case parameterSize = "parameter_size"
            case quantizationLevel = "quantization_level"
        }
    }
}

// MARK: - Errors

/// Errors related to Ollama model management
enum OllamaModelError: LocalizedError, Equatable {
    case invalidHost(String)
    case serverUnavailable
    case modelNotFound(String)
    case downloadFailed(String)
    case noModelsAvailable
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidHost(let host):
            return "Invalid Ollama host URL: \(host)"
        case .serverUnavailable:
            return "Ollama server is not available. Please ensure Ollama is running."
        case .modelNotFound(let model):
            return "Model '\(model)' not found in Ollama library"
        case .downloadFailed(let reason):
            return "Failed to download model: \(reason)"
        case .noModelsAvailable:
            return "No models available in Ollama. Please download at least one model."
        case .serverError(let message):
            return "Ollama server error: \(message)"
        }
    }
}

// MARK: - Convenience Extensions

extension OllamaModelManager {
    /// Ensure the default model from configuration is available
    func ensureDefaultModel() async throws -> String {
        let defaultModel = OllamaConfiguration.defaultModel
        let fallbacks = ["llama3.2", "llama3.1", "mistral", "phi3"]
        
        return try await resolveModel(
            requested: defaultModel,
            fallbacks: fallbacks,
            autoDownload: true
        ) { progress in
            NSLog("📥 [OllamaModelManager] Download progress: %@ - %d%%",
                  progress.status, progress.progressPercent)
        }
    }
    
    /// Quick check and resolution without downloading
    func resolveModelFast(_ requested: String) async -> String? {
        guard let models = try? await listAvailableModels() else { return nil }
        return findMatchingModel(requested, in: models)
    }
}

