// MARK: - LLM Routing Service
// Routes LLM requests to appropriate providers with health detection, backoff, and degraded mode

import Foundation

// MARK: - LLM Routing Mode

/// Current LLM routing mode
enum LLMRoutingMode: String, Sendable, Codable {
    case full      // Full mode: cloud or local LLM available
    case degraded  // Degraded mode: local-only heuristics, no cloud calls
    case offline   // Offline mode: no LLM available, queueing retries
}

// MARK: - LLM Routing State

/// Current state of LLM routing service
struct LLMRoutingState: Sendable {
    let mode: LLMRoutingMode
    let availableProviders: [String]
    let lastError: String?
    let backoffUntil: Date?
    let retryCount: Int
    
    init(
        mode: LLMRoutingMode = .full,
        availableProviders: [String] = [],
        lastError: String? = nil,
        backoffUntil: Date? = nil,
        retryCount: Int = 0
    ) {
        self.mode = mode
        self.availableProviders = availableProviders
        self.lastError = lastError
        self.backoffUntil = backoffUntil
        self.retryCount = retryCount
    }
}

// MARK: - LLM Routing Service

/// Routes LLM requests with health detection, exponential backoff, and degraded mode support
actor LLMRoutingService {
    
    // MARK: - Properties
    
    private var providers: [String: any LLMProvider] = [:]
    private var providerConfigs: [String: ProviderConfig] = [:]
    private var state: LLMRoutingState
    private var healthCheckTasks: [String: Task<Void, Never>] = [:]
    
    // Backoff state
    private var backoffState: [String: BackoffState] = [:]
    
    // Routing policy
    private var preferLocal: Bool
    private var allowCloud: Bool
    private var degradedModeEnabled: Bool
    
    // MARK: - Provider Configuration
    
    struct ProviderConfig: Sendable {
        let identifier: String
        let timeout: TimeInterval
        let maxRetries: Int
        let initialBackoff: TimeInterval
        let maxBackoff: TimeInterval
        let backoffMultiplier: Double
        let isCloud: Bool
        
        static let defaultLocal = ProviderConfig(
            identifier: "ollama",
            timeout: 300.0,
            maxRetries: 3,
            initialBackoff: 1.0,
            maxBackoff: 60.0,
            backoffMultiplier: 2.0,
            isCloud: false
        )
        
        static let defaultCloud = ProviderConfig(
            identifier: "openai",
            timeout: 30.0,
            maxRetries: 3,
            initialBackoff: 2.0,
            maxBackoff: 120.0,
            backoffMultiplier: 2.0,
            isCloud: true
        )
    }
    
    // MARK: - Backoff State
    
    private struct BackoffState: Sendable {
        var retryCount: Int
        var nextRetryAt: Date
        var backoffDuration: TimeInterval
        
        init(initialBackoff: TimeInterval) {
            self.retryCount = 0
            self.backoffDuration = initialBackoff
            self.nextRetryAt = Date().addingTimeInterval(initialBackoff)
        }
        
        mutating func increment(maxBackoff: TimeInterval, multiplier: Double) {
            retryCount += 1
            backoffDuration = min(backoffDuration * multiplier, maxBackoff)
            nextRetryAt = Date().addingTimeInterval(backoffDuration)
        }
    }
    
    // MARK: - Initialization
    
    init(
        preferLocal: Bool = true,
        allowCloud: Bool = false,
        degradedModeEnabled: Bool = true
    ) {
        self.preferLocal = preferLocal
        self.allowCloud = allowCloud
        self.degradedModeEnabled = degradedModeEnabled
        self.state = LLMRoutingState()
    }
    
    // MARK: - Provider Registration
    
    /// Registers an LLM provider
    func register(provider: any LLMProvider, config: ProviderConfig) {
        let id = provider.identifier
        providers[id] = provider
        providerConfigs[id] = config
        
        // Start health check for this provider
        startHealthCheck(for: id)
    }
    
    /// Unregisters a provider
    func unregister(identifier: String) {
        providers.removeValue(forKey: identifier)
        providerConfigs.removeValue(forKey: identifier)
        healthCheckTasks[identifier]?.cancel()
        healthCheckTasks.removeValue(forKey: identifier)
        backoffState.removeValue(forKey: identifier)
    }
    
    // MARK: - Health Checks
    
    /// Starts periodic health checks for a provider
    private func startHealthCheck(for identifier: String) {
        // Cancel existing task if any
        healthCheckTasks[identifier]?.cancel()
        
        let task = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                    await checkProviderHealth(identifier: identifier)
                } catch {
                    // Task cancelled or sleep interrupted
                    break
                }
            }
        }
        
        healthCheckTasks[identifier] = task
    }
    
    /// Checks health of a specific provider
    private func checkProviderHealth(identifier: String) async {
        guard let provider = providers[identifier] else { return }
        
        let isAvailable = await provider.isAvailable()
        let config = providerConfigs[identifier] ?? ProviderConfig.defaultLocal
        
        if isAvailable {
            // Provider is healthy - clear backoff
            backoffState.removeValue(forKey: identifier)
            await updateState()
        } else {
            // Provider is unhealthy - set backoff
            if backoffState[identifier] == nil {
                backoffState[identifier] = BackoffState(initialBackoff: config.initialBackoff)
            } else {
                var state = backoffState[identifier]!
                state.increment(maxBackoff: config.maxBackoff, multiplier: config.backoffMultiplier)
                backoffState[identifier] = state
            }
            await updateState()
        }
    }
    
    /// Manually triggers health check for all providers
    func checkHealth() async {
        for identifier in providers.keys {
            await checkProviderHealth(identifier: identifier)
        }
    }
    
    // MARK: - State Management
    
    /// Updates routing state based on provider availability
    private func updateState() async {
        var availableProviders: [String] = []
        
        for (id, provider) in providers {
            // Check if provider is in backoff
            if let backoff = backoffState[id] {
                if Date() < backoff.nextRetryAt {
                    // Still in backoff
                    continue
                }
            }
            
            // Check if provider is available
            let isAvailable = await provider.isAvailable()
            if isAvailable {
                availableProviders.append(id)
            }
        }
        
        // Determine mode
        let newMode: LLMRoutingMode
        if availableProviders.isEmpty {
            if degradedModeEnabled {
                newMode = .degraded
            } else {
                newMode = .offline
            }
        } else {
            newMode = .full
        }
        
        // Update state
        let lastError = state.lastError
        let backoffUntil = backoffState.values.map { $0.nextRetryAt }.max()
        
        state = LLMRoutingState(
            mode: newMode,
            availableProviders: availableProviders,
            lastError: lastError,
            backoffUntil: backoffUntil,
            retryCount: backoffState.values.map { $0.retryCount }.max() ?? 0
        )
    }
    
    /// Gets current routing state
    func getState() -> LLMRoutingState {
        state
    }
    
    // MARK: - Routing
    
    /// Selects the best provider for a request
    private func selectProvider() async -> (any LLMProvider)? {
        // Update state first
        await updateState()
        
        // If in degraded mode, only return local providers
        if state.mode == .degraded {
            for id in state.availableProviders {
                let config = providerConfigs[id] ?? ProviderConfig.defaultLocal
                if !config.isCloud, let provider = providers[id] {
                    return provider
                }
            }
            return nil
        }
        
        // If in offline mode, return nil
        if state.mode == .offline {
            return nil
        }
        
        // Prefer local if configured
        if preferLocal {
            for id in state.availableProviders {
                let config = providerConfigs[id] ?? ProviderConfig.defaultLocal
                if !config.isCloud, let provider = providers[id] {
                    return provider
                }
            }
        }
        
        // Fall back to any available provider
        for id in state.availableProviders {
            if let provider = providers[id] {
                return provider
            }
        }
        
        return nil
    }
    
    // MARK: - LLM Operations with Routing
    
    /// Completes a prompt using the best available provider
    func complete(prompt: String, options: LLMOptions) async throws -> String {
        guard let provider = await selectProvider() else {
            let error = "No LLM provider available (mode: \(state.mode.rawValue))"
            state = LLMRoutingState(
                mode: state.mode,
                availableProviders: state.availableProviders,
                lastError: error,
                backoffUntil: state.backoffUntil,
                retryCount: state.retryCount
            )
            throw LLMError.providerUnavailable(error)
        }
        
        let config = providerConfigs[provider.identifier] ?? ProviderConfig.defaultLocal
        
        do {
            let result = try await withTimeout(seconds: config.timeout) {
                try await provider.complete(prompt: prompt, options: options)
            }
            
            // Success - clear any backoff for this provider
            backoffState.removeValue(forKey: provider.identifier)
            await updateState()
            
            return result
        } catch {
            // Failure - set backoff
            if backoffState[provider.identifier] == nil {
                backoffState[provider.identifier] = BackoffState(initialBackoff: config.initialBackoff)
            } else {
                var backoff = backoffState[provider.identifier]!
                backoff.increment(maxBackoff: config.maxBackoff, multiplier: config.backoffMultiplier)
                backoffState[provider.identifier] = backoff
            }
            
            state = LLMRoutingState(
                mode: state.mode,
                availableProviders: state.availableProviders,
                lastError: error.localizedDescription,
                backoffUntil: backoffState[provider.identifier]?.nextRetryAt,
                retryCount: backoffState[provider.identifier]?.retryCount ?? 0
            )
            
            await updateState()
            throw error
        }
    }
    
    /// Completes a JSON prompt using the best available provider
    func completeJSON(prompt: String, options: LLMOptions) async throws -> String {
        guard let provider = await selectProvider() else {
            let error = "No LLM provider available (mode: \(state.mode.rawValue))"
            state = LLMRoutingState(
                mode: state.mode,
                availableProviders: state.availableProviders,
                lastError: error,
                backoffUntil: state.backoffUntil,
                retryCount: state.retryCount
            )
            throw LLMError.providerUnavailable(error)
        }
        
        let config = providerConfigs[provider.identifier] ?? ProviderConfig.defaultLocal
        
        do {
            let result = try await withTimeout(seconds: config.timeout) {
                try await provider.completeJSON(prompt: prompt, options: options)
            }
            
            // Success - clear backoff
            backoffState.removeValue(forKey: provider.identifier)
            await updateState()
            
            return result
        } catch {
            // Failure - set backoff
            if backoffState[provider.identifier] == nil {
                backoffState[provider.identifier] = BackoffState(initialBackoff: config.initialBackoff)
            } else {
                var backoff = backoffState[provider.identifier]!
                backoff.increment(maxBackoff: config.maxBackoff, multiplier: config.backoffMultiplier)
                backoffState[provider.identifier] = backoff
            }
            
            state = LLMRoutingState(
                mode: state.mode,
                availableProviders: state.availableProviders,
                lastError: error.localizedDescription,
                backoffUntil: backoffState[provider.identifier]?.nextRetryAt,
                retryCount: backoffState[provider.identifier]?.retryCount ?? 0
            )
            
            await updateState()
            throw error
        }
    }
    
    /// Generates embeddings using the best available provider
    func embed(text: String) async throws -> [Float] {
        guard let provider = await selectProvider() else {
            let error = "No LLM provider available (mode: \(state.mode.rawValue))"
            state = LLMRoutingState(
                mode: state.mode,
                availableProviders: state.availableProviders,
                lastError: error,
                backoffUntil: state.backoffUntil,
                retryCount: state.retryCount
            )
            throw LLMError.providerUnavailable(error)
        }
        
        let config = providerConfigs[provider.identifier] ?? ProviderConfig.defaultLocal
        
        do {
            let result = try await withTimeout(seconds: config.timeout) {
                try await provider.embed(text: text)
            }
            
            // Success - clear backoff
            backoffState.removeValue(forKey: provider.identifier)
            await updateState()
            
            return result
        } catch {
            // Failure - set backoff
            if backoffState[provider.identifier] == nil {
                backoffState[provider.identifier] = BackoffState(initialBackoff: config.initialBackoff)
            } else {
                var backoff = backoffState[provider.identifier]!
                backoff.increment(maxBackoff: config.maxBackoff, multiplier: config.backoffMultiplier)
                backoffState[provider.identifier] = backoff
            }
            
            state = LLMRoutingState(
                mode: state.mode,
                availableProviders: state.availableProviders,
                lastError: error.localizedDescription,
                backoffUntil: backoffState[provider.identifier]?.nextRetryAt,
                retryCount: backoffState[provider.identifier]?.retryCount ?? 0
            )
            
            await updateState()
            throw error
        }
    }
    
    // MARK: - Mode Control
    
    /// Sets degraded mode explicitly
    func setDegradedMode(_ enabled: Bool) {
        degradedModeEnabled = enabled
        Task {
            await updateState()
        }
    }
    
    /// Forces a mode (for testing or manual override)
    func forceMode(_ mode: LLMRoutingMode) {
        state = LLMRoutingState(
            mode: mode,
            availableProviders: state.availableProviders,
            lastError: state.lastError,
            backoffUntil: state.backoffUntil,
            retryCount: state.retryCount
        )
    }
    
    // MARK: - Helper Functions
    
    /// Executes a task with timeout
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw LLMError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

