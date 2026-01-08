// MARK: - Degraded Mode UI Components
// Spec requirement: "On LLM unavailability, prompt once ('Wait/Retry' vs 'Use local-only')"
// Spec requirement: "small toggle in status bar to switch back when healthy"

import SwiftUI

// MARK: - LLM Unavailable Alert

struct LLMUnavailableAlert: View {
    @Binding var isPresented: Bool
    @Binding var selectedAction: LLMUnavailableAction?
    
    let errorMessage: String
    let onRetry: () async -> Void
    let onUseDegraded: () -> Void
    
    enum LLMUnavailableAction {
        case retry
        case useDegraded
        case waitForRecovery
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Icon
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            // Title
            Text("LLM Unavailable")
                .font(.title2)
                .fontWeight(.semibold)
            
            // Message
            Text(errorMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            // Options
            VStack(spacing: 12) {
                Button(action: {
                    selectedAction = .retry
                    Task {
                        await onRetry()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Wait & Retry")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: {
                    selectedAction = .useDegraded
                    onUseDegraded()
                    isPresented = false
                }) {
                    HStack {
                        Image(systemName: "speedometer")
                        Text("Use Local-Only Mode")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .frame(width: 250)
            
            // Info
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Local-only mode uses filename patterns without LLM analysis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 400)
    }
}

// MARK: - Status Banner

struct LLMStatusBanner: View {
    let mode: LLMMode
    let onReturnToFull: () async -> Void
    let onShowDetails: () -> Void
    
    enum LLMMode {
        case full
        case degraded
        case offline
        case recovering
        
        var backgroundColor: Color {
            switch self {
            case .full: return .green.opacity(0.1)
            case .degraded: return .orange.opacity(0.1)
            case .offline: return .red.opacity(0.1)
            case .recovering: return .blue.opacity(0.1)
            }
        }
        
        var borderColor: Color {
            switch self {
            case .full: return .green.opacity(0.3)
            case .degraded: return .orange.opacity(0.3)
            case .offline: return .red.opacity(0.3)
            case .recovering: return .blue.opacity(0.3)
            }
        }
        
        var iconColor: Color {
            switch self {
            case .full: return .green
            case .degraded: return .orange
            case .offline: return .red
            case .recovering: return .blue
            }
        }
        
        var icon: String {
            switch self {
            case .full: return "checkmark.circle.fill"
            case .degraded: return "exclamationmark.triangle.fill"
            case .offline: return "wifi.slash"
            case .recovering: return "arrow.clockwise"
            }
        }
        
        var title: String {
            switch self {
            case .full: return "Full Mode"
            case .degraded: return "Degraded Mode"
            case .offline: return "Offline"
            case .recovering: return "Reconnecting..."
            }
        }
        
        var description: String {
            switch self {
            case .full: return "LLM connected and ready"
            case .degraded: return "Using local patterns only"
            case .offline: return "No LLM connection"
            case .recovering: return "Attempting to reconnect"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            if mode == .recovering {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: mode.icon)
                    .foregroundStyle(mode.iconColor)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(mode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Actions
            if mode == .degraded {
                Button("Return to Full") {
                    Task {
                        await onReturnToFull()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            if mode == .offline {
                Button("Retry") {
                    Task {
                        await onReturnToFull()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            // Details button
            Button(action: onShowDetails) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(mode.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(mode.borderColor, lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

// MARK: - Toast Notification

struct ToastNotification: View {
    let message: String
    let type: ToastType
    @Binding var isShowing: Bool
    
    enum ToastType {
        case success
        case warning
        case error
        case info
        
        var backgroundColor: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            case .info: return .blue
            }
        }
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .foregroundStyle(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
            
            Spacer()
            
            Button(action: { isShowing = false }) {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(type.backgroundColor)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation {
                    isShowing = false
                }
            }
        }
    }
}

// MARK: - Toast Container

struct ToastContainer<Content: View>: View {
    @Binding var toast: ToastState?
    let content: Content
    
    struct ToastState: Identifiable {
        let id = UUID()
        let message: String
        let type: ToastNotification.ToastType
    }
    
    init(toast: Binding<ToastState?>, @ViewBuilder content: () -> Content) {
        self._toast = toast
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            content
            
            if let toastState = toast {
                ToastNotification(
                    message: toastState.message,
                    type: toastState.type,
                    isShowing: Binding(
                        get: { toast != nil },
                        set: { if !$0 { toast = nil } }
                    )
                )
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.3), value: toast?.id)
    }
}

// MARK: - Retry Progress View

struct RetryProgressView: View {
    let attempt: Int
    let maxAttempts: Int
    let nextRetryIn: TimeInterval
    let onCancel: () -> Void
    
    @State private var remainingTime: TimeInterval
    
    init(attempt: Int, maxAttempts: Int, nextRetryIn: TimeInterval, onCancel: @escaping () -> Void) {
        self.attempt = attempt
        self.maxAttempts = maxAttempts
        self.nextRetryIn = nextRetryIn
        self.onCancel = onCancel
        self._remainingTime = State(initialValue: nextRetryIn)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Reconnecting to LLM...")
                .font(.headline)
            
            Text("Attempt \(attempt) of \(maxAttempts)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if remainingTime > 0 {
                Text("Next retry in \(Int(remainingTime))s")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            
            Button("Cancel & Use Degraded Mode") {
                onCancel()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .onAppear {
            startCountdown()
        }
    }
    
    private func startCountdown() {
        // Use a simple timer approach with direct main thread access
        let countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in }
        countdownTimer.invalidate() // Immediately invalidate the placeholder
        
        // Use Task for the countdown instead
        Task {
            while remainingTime > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                await MainActor.run {
                    if remainingTime > 0 {
                        remainingTime -= 1
                    }
                }
            }
        }
    }
}

// MARK: - Connection Details Sheet

struct ConnectionDetailsSheet: View {
    let provider: String
    let host: String
    let lastError: String?
    let retryCount: Int
    let nextRetryAt: Date?
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Connection Details")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            
            Divider()
            
            // Provider Info
            Group {
                detailRow(label: "Provider", value: provider)
                detailRow(label: "Host", value: host)
                detailRow(label: "Retry Count", value: "\(retryCount)")
                
                if let nextRetry = nextRetryAt {
                    detailRow(label: "Next Retry", value: nextRetry.formatted())
                }
            }
            
            // Error
            if let error = lastError {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last Error")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Spacer()
            
            // Actions
            HStack {
                Button("View Logs") {
                    // Open logs
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Test Connection") {
                    // Test connection
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400, height: 400)
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - Preview Helpers

#if DEBUG
struct DegradedModeUI_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            LLMStatusBanner(
                mode: .degraded,
                onReturnToFull: {},
                onShowDetails: {}
            )
            
            LLMStatusBanner(
                mode: .offline,
                onReturnToFull: {},
                onShowDetails: {}
            )
            
            LLMStatusBanner(
                mode: .recovering,
                onReturnToFull: {},
                onShowDetails: {}
            )
            
            LLMStatusBanner(
                mode: .full,
                onReturnToFull: {},
                onShowDetails: {}
            )
        }
        .padding()
        .frame(width: 400)
    }
}
#endif

