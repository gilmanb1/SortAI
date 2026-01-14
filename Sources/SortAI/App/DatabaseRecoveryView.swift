// MARK: - Database Recovery UI
// Modal view displayed during database recovery with progress and status

import SwiftUI

// MARK: - Recovery View

/// Modal view displayed during database recovery
struct DatabaseRecoveryView: View {
    let state: DatabaseState
    let onRetry: () -> Void
    let onContinueReadOnly: () -> Void
    let onReset: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            headerSection
            
            // Content based on state
            switch state {
            case .healthy:
                EmptyView()
                
            case .recovering(let phase):
                recoveryProgress(phase: phase)
                
            case .readOnly(let reason):
                readOnlyWarning(reason: reason)
                
            case .unavailable(let reason):
                unavailableError(reason: reason)
            }
        }
        .padding(32)
        .frame(width: 450)
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 20)
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: headerIcon)
                .font(.system(size: 48))
                .foregroundStyle(headerColor)
                .symbolEffect(.pulse, options: .repeating, isActive: state.isRecovering)
            
            Text(headerTitle)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(headerSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var headerIcon: String {
        switch state {
        case .healthy:
            return "checkmark.circle.fill"
        case .recovering:
            return "arrow.triangle.2.circlepath"
        case .readOnly:
            return "exclamationmark.triangle.fill"
        case .unavailable:
            return "xmark.circle.fill"
        }
    }
    
    private var headerColor: Color {
        switch state {
        case .healthy:
            return .green
        case .recovering:
            return .blue
        case .readOnly:
            return .orange
        case .unavailable:
            return .red
        }
    }
    
    private var headerTitle: String {
        switch state {
        case .healthy:
            return "Database Ready"
        case .recovering:
            return "Recovering Database"
        case .readOnly:
            return "Read-Only Mode"
        case .unavailable:
            return "Database Unavailable"
        }
    }
    
    private var headerSubtitle: String {
        switch state {
        case .healthy:
            return "Your database is healthy and ready to use."
        case .recovering:
            return "Please wait while SortAI recovers your database."
        case .readOnly:
            return "SortAI is running with limited functionality."
        case .unavailable:
            return "SortAI cannot access its database."
        }
    }
    
    // MARK: - Recovery Progress
    
    @ViewBuilder
    private func recoveryProgress(phase: RecoveryPhase) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: phase.progress)
                .progressViewStyle(.linear)
                .tint(.blue)
            
            Text(phase.displayName)
                .font(.callout)
                .foregroundStyle(.secondary)
            
            Text("This may take a moment. Please do not quit the application.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Read-Only Warning
    
    @ViewBuilder
    private func readOnlyWarning(reason: String) -> some View {
        VStack(spacing: 20) {
            // Warning details
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Limited Functionality", systemImage: "info.circle")
                        .font(.headline)
                    
                    Text("""
                    • You can view existing categorizations
                    • File organization is disabled
                    • Learning from corrections is disabled
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            
            // Reason
            Text("Reason: \(reason)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            // Actions
            HStack(spacing: 12) {
                Button("Try Again") {
                    onRetry()
                }
                .buttonStyle(.bordered)
                
                Button("Continue in Read-Only Mode") {
                    onContinueReadOnly()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    // MARK: - Unavailable Error
    
    @ViewBuilder
    private func unavailableError(reason: String) -> some View {
        VStack(spacing: 20) {
            // Error details
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("What happened?", systemImage: "questionmark.circle")
                        .font(.headline)
                    
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            
            // Suggestions
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Try these steps:", systemImage: "lightbulb")
                        .font(.headline)
                    
                    Text("""
                    1. Ensure you have enough disk space
                    2. Check permissions for ~/Library/Application Support/SortAI/
                    3. Restart SortAI
                    4. If the problem persists, reset the database
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            
            // Actions
            HStack(spacing: 12) {
                Button("Reset Database") {
                    onReset()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                
                Button("Try Again") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - State Extension

extension DatabaseState {
    var isRecovering: Bool {
        if case .recovering = self {
            return true
        }
        return false
    }
}

// MARK: - Recovery Banner

/// Persistent banner shown when database is in degraded state
struct DatabaseRecoveryBanner: View {
    let state: DatabaseState
    let onTap: () -> Void
    
    var body: some View {
        if !state.isOperational || state == .readOnly(reason: "") {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: bannerIcon)
                        .foregroundStyle(bannerColor)
                    
                    Text(bannerText)
                        .font(.caption)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bannerColor.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var bannerIcon: String {
        switch state {
        case .healthy:
            return "checkmark.circle"
        case .recovering:
            return "arrow.triangle.2.circlepath"
        case .readOnly:
            return "exclamationmark.triangle"
        case .unavailable:
            return "xmark.circle"
        }
    }
    
    private var bannerColor: Color {
        switch state {
        case .healthy:
            return .green
        case .recovering:
            return .blue
        case .readOnly:
            return .orange
        case .unavailable:
            return .red
        }
    }
    
    private var bannerText: String {
        switch state {
        case .healthy:
            return "Database healthy"
        case .recovering(let phase):
            return "Recovering: \(phase.displayName)"
        case .readOnly:
            return "Running in read-only mode"
        case .unavailable:
            return "Database unavailable - tap for options"
        }
    }
}

// MARK: - Preview

#Preview("Recovery - Recovering") {
    DatabaseRecoveryView(
        state: .recovering(.runningIntegrityCheck),
        onRetry: {},
        onContinueReadOnly: {},
        onReset: {}
    )
    .padding()
    .background(.gray.opacity(0.2))
}

#Preview("Recovery - Read Only") {
    DatabaseRecoveryView(
        state: .readOnly(reason: "Database file was corrupted"),
        onRetry: {},
        onContinueReadOnly: {},
        onReset: {}
    )
    .padding()
    .background(.gray.opacity(0.2))
}

#Preview("Recovery - Unavailable") {
    DatabaseRecoveryView(
        state: .unavailable(reason: "Disk full - 0MB available"),
        onRetry: {},
        onContinueReadOnly: {},
        onReset: {}
    )
    .padding()
    .background(.gray.opacity(0.2))
}

#Preview("Banner") {
    VStack(spacing: 16) {
        DatabaseRecoveryBanner(state: .recovering(.attemptingRepair), onTap: {})
        DatabaseRecoveryBanner(state: .readOnly(reason: "Corrupted"), onTap: {})
        DatabaseRecoveryBanner(state: .unavailable(reason: "Disk full"), onTap: {})
    }
    .padding()
}
