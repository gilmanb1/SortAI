// MARK: - Ollama Installer
// Helper for detecting, installing, and launching Ollama
// Shows non-blocking notifications when Ollama is needed

import Foundation
import AppKit
import UserNotifications

// MARK: - Installation Status

/// Status of Ollama installation
enum OllamaInstallationStatus: Sendable, Equatable {
    case notInstalled
    case installed
    case installing(progress: Double)
    case failed(String)
    case serverRunning
    case serverStopped
}

// MARK: - Ollama Installer

/// Handles Ollama installation, detection, and server management
actor OllamaInstaller {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        let serverCheckInterval: TimeInterval
        let serverStartTimeout: TimeInterval
        let defaultModel: String
        
        static let `default` = Configuration(
            serverCheckInterval: 1.0,
            serverStartTimeout: 30.0,
            defaultModel: "deepseek-r1:8b"
        )
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private let session: URLSession
    private(set) var status: OllamaInstallationStatus = .notInstalled
    
    /// Known installation paths for Ollama
    private let installPaths = [
        "/usr/local/bin/ollama",
        "/opt/homebrew/bin/ollama",
        NSHomeDirectory() + "/.ollama/ollama",
        "/Applications/Ollama.app"
    ]
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .default) {
        self.config = configuration
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 10.0
        self.session = URLSession(configuration: sessionConfig)
    }
    
    // MARK: - Installation Detection
    
    /// Check if Ollama is installed
    nonisolated func isInstalled() -> Bool {
        // Check for Ollama.app
        if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") {
            return true
        }
        
        // Check for command-line binary
        for path in ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama"] {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        // Check with `which` command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ollama"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    /// Check if Ollama server is running
    func isServerRunning() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { return false }
        
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    /// Get comprehensive status
    func getStatus() async -> OllamaInstallationStatus {
        if !isInstalled() {
            status = .notInstalled
            return .notInstalled
        }
        
        if await isServerRunning() {
            status = .serverRunning
            return .serverRunning
        }
        
        status = .serverStopped
        return .serverStopped
    }
    
    // MARK: - Installation
    
    /// Download and install Ollama
    func install() async throws {
        NSLog("📥 [OllamaInstaller] Starting installation...")
        status = .installing(progress: 0)
        
        // Download the official macOS app
        guard let installerURL = URL(string: "https://ollama.ai/download/Ollama-darwin.zip") else {
            throw OllamaInstallerError.invalidURL
        }
        
        let downloadDelegate = DownloadProgressDelegate { [weak self] progress in
            Task { await self?.updateProgress(progress * 0.8) }  // Download is 80% of progress
        }
        
        let downloadSession = URLSession(configuration: .default, delegate: downloadDelegate, delegateQueue: nil)
        
        do {
            let (downloadURL, _) = try await downloadSession.download(from: installerURL)
            status = .installing(progress: 0.8)
            
            NSLog("📥 [OllamaInstaller] Downloaded to: %@", downloadURL.path)
            
            // Unzip to Applications
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", downloadURL.path, "-d", "/Applications"]
            
            let pipe = Pipe()
            unzipProcess.standardOutput = pipe
            unzipProcess.standardError = pipe
            
            try unzipProcess.run()
            unzipProcess.waitUntilExit()
            
            status = .installing(progress: 0.9)
            
            if unzipProcess.terminationStatus != 0 {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                throw OllamaInstallerError.installationFailed(output)
            }
            
            NSLog("✅ [OllamaInstaller] Unzipped to /Applications")
            
            // Clean up download
            try? FileManager.default.removeItem(at: downloadURL)
            
            // Launch Ollama
            try await launchOllama()
            
            status = .installing(progress: 0.95)
            
            // Pull default model
            try await pullDefaultModel()
            
            status = .serverRunning
            NSLog("✅ [OllamaInstaller] Installation complete!")
            
        } catch {
            status = .failed(error.localizedDescription)
            NSLog("❌ [OllamaInstaller] Installation failed: %@", error.localizedDescription)
            throw error
        }
    }
    
    private func updateProgress(_ progress: Double) {
        status = .installing(progress: progress)
    }
    
    // MARK: - Server Management
    
    /// Launch Ollama application
    func launchOllama() async throws {
        let ollamaAppPath = "/Applications/Ollama.app"
        
        // Check if app exists
        guard FileManager.default.fileExists(atPath: ollamaAppPath) else {
            // Try launching CLI version
            if await launchOllamaCLI() {
                return
            }
            throw OllamaInstallerError.notInstalled
        }
        
        NSLog("🚀 [OllamaInstaller] Launching Ollama.app...")
        
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false  // Don't bring to foreground
        config.hides = true       // Start hidden
        
        do {
            try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: ollamaAppPath),
                configuration: config
            )
        } catch {
            NSLog("⚠️ [OllamaInstaller] Failed to launch app: %@", error.localizedDescription)
            // Fall back to CLI
            if !(await launchOllamaCLI()) {
                throw OllamaInstallerError.launchFailed(error.localizedDescription)
            }
        }
        
        // Wait for server to start
        try await waitForServer()
    }
    
    /// Launch Ollama CLI server
    private func launchOllamaCLI() async -> Bool {
        let paths = ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama"]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                NSLog("🚀 [OllamaInstaller] Launching Ollama CLI from: %@", path)
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["serve"]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                
                do {
                    try process.run()
                    
                    // Wait a moment for server to start
                    try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
                    
                    if await isServerRunning() {
                        return true
                    }
                } catch {
                    NSLog("⚠️ [OllamaInstaller] Failed to launch CLI: %@", error.localizedDescription)
                }
            }
        }
        
        return false
    }
    
    /// Wait for server to become available
    private func waitForServer() async throws {
        NSLog("⏳ [OllamaInstaller] Waiting for server to start...")
        
        let maxAttempts = Int(config.serverStartTimeout / config.serverCheckInterval)
        
        for attempt in 0..<maxAttempts {
            if await isServerRunning() {
                NSLog("✅ [OllamaInstaller] Server is running!")
                status = .serverRunning
                return
            }
            
            try await Task.sleep(nanoseconds: UInt64(config.serverCheckInterval * 1_000_000_000))
            
            if attempt % 10 == 0 {
                NSLog("⏳ [OllamaInstaller] Still waiting... (attempt %d/%d)", attempt + 1, maxAttempts)
            }
        }
        
        throw OllamaInstallerError.serverStartTimeout
    }
    
    // MARK: - Model Management
    
    /// Pull the default model
    func pullDefaultModel() async throws {
        NSLog("📥 [OllamaInstaller] Pulling default model: %@", config.defaultModel)
        
        guard let url = URL(string: "http://127.0.0.1:11434/api/pull") else {
            throw OllamaInstallerError.invalidURL
        }
        
        struct PullRequest: Encodable {
            let name: String
            let stream: Bool
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PullRequest(name: config.defaultModel, stream: false))
        
        // This can take a while for large models
        let longTimeoutSession = URLSession(configuration: {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 3600  // 1 hour
            config.timeoutIntervalForResource = 3600
            return config
        }())
        
        let (_, response) = try await longTimeoutSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaInstallerError.modelPullFailed("No response")
        }
        
        if httpResponse.statusCode != 200 {
            throw OllamaInstallerError.modelPullFailed("HTTP \(httpResponse.statusCode)")
        }
        
        NSLog("✅ [OllamaInstaller] Model pulled successfully!")
    }
    
    // MARK: - User Prompts
    
    /// Show non-blocking notification for installation using UserNotifications framework
    @MainActor
    func showInstallationNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Ollama Not Found"
        content.body = "Ollama provides more powerful AI models. Tap to install."
        content.sound = .default
        content.categoryIdentifier = "OLLAMA_INSTALL"
        
        let request = UNNotificationRequest(
            identifier: "ollama_install_prompt",
            content: content,
            trigger: nil  // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("⚠️ [OllamaInstaller] Failed to show notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Show installation prompt (non-blocking)
    @MainActor
    func showInstallationPrompt() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Ollama Not Found"
        alert.informativeText = """
        Ollama provides more powerful AI models for complex file analysis.
        
        Would you like to install Ollama now? This will:
        1. Download Ollama (~500 MB)
        2. Install it to Applications
        3. Download the deepseek-r1:8b model (~5 GB)
        
        You can continue using Apple Intelligence in the meantime.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Ollama")
        alert.addButton(withTitle: "Use Apple Intelligence Only")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        
        return response == .alertFirstButtonReturn
    }
}

// MARK: - Download Progress Delegate

private class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (Double) -> Void
    
    init(progressHandler: @escaping @Sendable (Double) -> Void) {
        self.progressHandler = progressHandler
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by async/await
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }
}

// MARK: - Errors

/// Errors related to Ollama installation
enum OllamaInstallerError: LocalizedError {
    case notInstalled
    case invalidURL
    case installationFailed(String)
    case launchFailed(String)
    case serverStartTimeout
    case modelPullFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Ollama is not installed"
        case .invalidURL:
            return "Invalid URL for Ollama download"
        case .installationFailed(let reason):
            return "Installation failed: \(reason)"
        case .launchFailed(let reason):
            return "Failed to launch Ollama: \(reason)"
        case .serverStartTimeout:
            return "Ollama server failed to start within timeout"
        case .modelPullFailed(let reason):
            return "Failed to pull model: \(reason)"
        }
    }
}

// MARK: - OllamaModelManager Extension

extension OllamaModelManager {
    /// Get the best available model for categorization
    func getBestAvailableModel() async -> String? {
        guard await isOllamaAvailable() else { return nil }
        
        do {
            let models = try await listAvailableModels()
            
            // Priority order for categorization
            let preferredModels = [
                "deepseek-r1:8b",
                "deepseek-r1",
                "llama3.2",
                "llama3.1",
                "mistral",
                "phi3"
            ]
            
            for preferred in preferredModels {
                if let match = findMatchingModel(preferred, in: models) {
                    return match
                }
            }
            
            // Return first available
            return models.first
        } catch {
            return nil
        }
    }
}

