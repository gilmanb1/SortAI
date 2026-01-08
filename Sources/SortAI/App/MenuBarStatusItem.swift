// MARK: - Menubar Status Item
// Spec requirement: "Menubar item showing mode (full/degraded), watch on/off, queue depth, last action"

import SwiftUI
import AppKit

// MARK: - Menu Bar Status Manager

@MainActor
final class MenuBarStatusManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published var llmMode: LLMStatusMode = .full
    @Published var watchEnabled: Bool = false
    @Published var queueDepth: Int = 0
    @Published var lastAction: String = "Ready"
    @Published var lastActionTime: Date?
    @Published var isProcessing: Bool = false
    @Published var healthStatus: HealthStatus = .healthy
    
    // MARK: - Types
    
    enum LLMStatusMode: String {
        case full = "Full"
        case degraded = "Degraded"
        case offline = "Offline"
        
        var icon: String {
            switch self {
            case .full: return "brain"
            case .degraded: return "brain.head.profile"
            case .offline: return "wifi.slash"
            }
        }
        
        var color: Color {
            switch self {
            case .full: return .green
            case .degraded: return .orange
            case .offline: return .red
            }
        }
    }
    
    enum HealthStatus {
        case healthy
        case warning
        case error
        
        var color: Color {
            switch self {
            case .healthy: return .green
            case .warning: return .yellow
            case .error: return .red
            }
        }
    }
    
    // MARK: - Status Updates
    
    func updateLLMMode(_ mode: LLMStatusMode) {
        llmMode = mode
        recordAction("LLM mode: \(mode.rawValue)")
    }
    
    func updateWatchStatus(enabled: Bool) {
        watchEnabled = enabled
        recordAction(enabled ? "Watch enabled" : "Watch disabled")
    }
    
    func updateQueueDepth(_ depth: Int) {
        queueDepth = depth
    }
    
    func recordAction(_ action: String) {
        lastAction = action
        lastActionTime = Date()
    }
    
    func setProcessing(_ processing: Bool) {
        isProcessing = processing
    }
    
    func updateHealth(_ status: HealthStatus) {
        healthStatus = status
    }
    
    // MARK: - Computed Properties
    
    var statusText: String {
        var parts: [String] = []
        parts.append(llmMode.rawValue)
        if watchEnabled {
            parts.append("Watch: On")
        }
        if queueDepth > 0 {
            parts.append("Queue: \(queueDepth)")
        }
        return parts.joined(separator: " | ")
    }
    
    var timeSinceLastAction: String? {
        guard let time = lastActionTime else { return nil }
        let interval = Date().timeIntervalSince(time)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m ago"
        } else {
            return "\(Int(interval / 3600))h ago"
        }
    }
}

// MARK: - Menu Bar View

struct MenuBarStatusView: View {
    @ObservedObject var statusManager: MenuBarStatusManager
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            headerSection
            
            Divider()
            
            // LLM Status
            llmStatusSection
            
            Divider()
            
            // Watch Mode
            watchModeSection
            
            if statusManager.queueDepth > 0 {
                Divider()
                queueSection
            }
            
            Divider()
            
            // Quick Actions
            quickActionsSection
            
            Divider()
            
            // Footer
            footerSection
        }
        .padding(12)
        .frame(width: 280)
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        HStack {
            Image(systemName: "folder.badge.gearshape")
                .font(.title2)
                .foregroundStyle(.tint)
            
            VStack(alignment: .leading) {
                Text("SortAI")
                    .font(.headline)
                Text(statusManager.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Health indicator
            Circle()
                .fill(statusManager.healthStatus.color)
                .frame(width: 8, height: 8)
        }
    }
    
    private var llmStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusManager.llmMode.icon)
                    .foregroundStyle(statusManager.llmMode.color)
                
                Text("LLM Mode")
                    .font(.subheadline)
                
                Spacer()
                
                Text(statusManager.llmMode.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(statusManager.llmMode.color)
            }
            
            if statusManager.llmMode == .degraded {
                Button("Return to Full Mode") {
                    statusManager.updateLLMMode(.full)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            if statusManager.llmMode == .offline {
                HStack {
                    Button("Retry Connection") {
                        Task {
                            // Trigger health check
                            statusManager.recordAction("Retrying connection...")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    Button("Use Degraded") {
                        statusManager.updateLLMMode(.degraded)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
    
    private var watchModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: statusManager.watchEnabled ? "eye.fill" : "eye.slash")
                    .foregroundStyle(statusManager.watchEnabled ? .green : .secondary)
                
                Text("Watch Mode")
                    .font(.subheadline)
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { statusManager.watchEnabled },
                    set: { statusManager.updateWatchStatus(enabled: $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            
            if statusManager.watchEnabled {
                Text("Monitoring ~/Downloads")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tray.full")
                    .foregroundStyle(.orange)
                
                Text("Queue")
                    .font(.subheadline)
                
                Spacer()
                
                Text("\(statusManager.queueDepth) items")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if statusManager.isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .padding(.leading, 24)
            }
        }
    }
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                // Open main window
            }) {
                HStack {
                    Image(systemName: "macwindow")
                    Text("Open SortAI")
                }
            }
            .buttonStyle(.plain)
            
            Button(action: {
                // Open settings
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Preferences...")
                }
            }
            .buttonStyle(.plain)
            
            if statusManager.isProcessing {
                Button(action: {
                    statusManager.setProcessing(false)
                    statusManager.recordAction("Processing paused")
                }) {
                    HStack {
                        Image(systemName: "pause.circle")
                        Text("Pause Processing")
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Last: \(statusManager.lastAction)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if let time = statusManager.timeSinceLastAction {
                    Text(time)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            HStack {
                Button("Quit SortAI") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
                
                Spacer()
                
                Text("v1.1")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Status Item Icon

struct MenuBarIcon: View {
    @ObservedObject var statusManager: MenuBarStatusManager
    
    var body: some View {
        ZStack {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 16))
            
            // Activity indicator
            if statusManager.isProcessing {
                Circle()
                    .fill(.blue)
                    .frame(width: 6, height: 6)
                    .offset(x: 6, y: -6)
            }
            
            // Status dot
            Circle()
                .fill(statusManager.llmMode.color)
                .frame(width: 5, height: 5)
                .offset(x: -8, y: 6)
        }
    }
}

// MARK: - App Integration

extension SortAIApp {
    
    /// Creates and configures the menu bar status item
    @MainActor
    static func setupMenuBarItem(statusManager: MenuBarStatusManager, appState: AppState) -> some Scene {
        MenuBarExtra {
            MenuBarStatusView(statusManager: statusManager)
                .environment(appState)
        } label: {
            MenuBarIcon(statusManager: statusManager)
        }
        .menuBarExtraStyle(.window)
    }
}

