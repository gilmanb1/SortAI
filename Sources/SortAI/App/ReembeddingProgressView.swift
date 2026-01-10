// MARK: - Re-embedding Progress View
// UI for displaying and controlling the background re-embedding job

import SwiftUI

// MARK: - Re-embedding Card View

/// Compact card showing re-embedding status (for Settings or sidebar)
struct ReembeddingStatusCard: View {
    @StateObject private var job = BackgroundEmbeddingJob.shared
    @State private var needsReembedding = false
    @State private var pendingCount = 0
    @State private var showingDetails = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title3)
                
                Text("Apple Intelligence Embeddings")
                    .font(.headline)
                
                Spacer()
                
                if job.status.isActive {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            // Status content
            statusContent
            
            // Actions
            actionButtons
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await checkReembeddingStatus()
        }
        .sheet(isPresented: $showingDetails) {
            ReembeddingDetailView()
        }
    }
    
    @ViewBuilder
    private var statusContent: some View {
        switch job.status {
        case .idle:
            if needsReembedding {
                Text("\(pendingCount) files can be upgraded to Apple Intelligence embeddings")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label("All embeddings use Apple Intelligence", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
            
        case .preparing:
            Text("Preparing re-embedding job...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
        case .running(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress.percentComplete) {
                    HStack {
                        Text("\(progress.processedFiles) of \(progress.totalFiles)")
                        Spacer()
                        Text("\(Int(progress.percentComplete * 100))%")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                if let currentFile = progress.currentFile {
                    Text("Processing: \(currentFile)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                
                if let eta = progress.estimatedCompletion {
                    Text("ETA: \(eta, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
        case .paused(let progress):
            VStack(alignment: .leading, spacing: 8) {
                Label("Paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
                
                ProgressView(value: progress.percentComplete)
                
                Text("\(progress.processedFiles) of \(progress.totalFiles) completed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
        case .completed(let summary):
            VStack(alignment: .leading, spacing: 4) {
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                
                Text("\(summary.successful) files upgraded in \(formatDuration(summary.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if summary.failed > 0 {
                    Text("\(summary.failed) failed, \(summary.skipped) skipped")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Label("Failed", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
        case .cancelled:
            Label("Cancelled", systemImage: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            switch job.status {
            case .idle:
                if needsReembedding {
                    Button {
                        Task { await job.start() }
                    } label: {
                        Label("Upgrade Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                }
                
            case .running:
                Button {
                    job.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                
                Button(role: .destructive) {
                    job.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                
            case .paused:
                Button {
                    Task { await job.resume() }
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                
                Button(role: .destructive) {
                    job.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                
            case .completed, .failed, .cancelled:
                if needsReembedding {
                    Button {
                        Task { await job.start() }
                    } label: {
                        Label("Run Again", systemImage: "arrow.clockwise")
                    }
                }
                
            case .preparing:
                EmptyView()
            }
            
            Spacer()
            
            Button {
                showingDetails = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
        }
    }
    
    private var statusIcon: String {
        switch job.status {
        case .idle: return needsReembedding ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill"
        case .preparing: return "hourglass"
        case .running: return "arrow.triangle.2.circlepath"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch job.status {
        case .idle: return needsReembedding ? .orange : .green
        case .preparing, .running: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }
    
    private func checkReembeddingStatus() async {
        needsReembedding = await job.needsReembedding()
        if needsReembedding {
            do {
                let cache = EmbeddingCache()
                pendingCount = try await cache.countEmbeddingsNeedingReembedding()
            } catch {
                pendingCount = 0
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "\(Int(duration))s"
    }
}

// MARK: - Detail View

/// Detailed view showing re-embedding statistics and history
struct ReembeddingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var job = BackgroundEmbeddingJob.shared
    @State private var modelStats: [(model: String, count: Int, avgHitCount: Double)] = []
    
    var body: some View {
        NavigationStack {
            List {
                // Current Status
                Section("Current Status") {
                    StatusRow(job: job)
                }
                
                // Model Statistics
                Section("Embedding Models in Use") {
                    if modelStats.isEmpty {
                        Text("Loading...")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(modelStats, id: \.model) { stat in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(stat.model)
                                        .font(.headline)
                                    Text("\(stat.count) embeddings")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                if stat.model == "apple-nl-embedding" {
                                    Image(systemName: "apple.logo")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
                
                // Info
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why Upgrade Embeddings?")
                            .font(.headline)
                        
                        Text("""
                        Apple Intelligence embeddings provide:
                        • Better semantic understanding
                        • Faster similarity search
                        • More accurate file grouping
                        • Privacy-preserving on-device processing
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Re-embedding Status")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .task {
            modelStats = await job.getModelStatistics()
        }
    }
}

// MARK: - Status Row

private struct StatusRow: View {
    @ObservedObject var job: BackgroundEmbeddingJob
    
    var body: some View {
        switch job.status {
        case .idle:
            Label("Ready", systemImage: "circle")
                .foregroundStyle(.secondary)
            
        case .preparing:
            HStack {
                Label("Preparing...", systemImage: "hourglass")
                Spacer()
                ProgressView()
            }
            
        case .running(let progress):
            VStack(alignment: .leading, spacing: 8) {
                Label("Running", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
                
                ProgressView(value: progress.percentComplete)
                
                HStack {
                    Text("\(progress.processedFiles)/\(progress.totalFiles) files")
                    Spacer()
                    if progress.filesPerSecond > 0 {
                        Text(String(format: "%.1f files/sec", progress.filesPerSecond))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
        case .paused(let progress):
            VStack(alignment: .leading, spacing: 8) {
                Label("Paused", systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
                
                ProgressView(value: progress.percentComplete)
                
                Text("\(progress.filesRemaining) files remaining")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
        case .completed(let summary):
            VStack(alignment: .leading, spacing: 4) {
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                
                HStack {
                    Text("✓ \(summary.successful)")
                        .foregroundStyle(.green)
                    if summary.failed > 0 {
                        Text("✗ \(summary.failed)")
                            .foregroundStyle(.red)
                    }
                    if summary.skipped > 0 {
                        Text("○ \(summary.skipped)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            
        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Label("Failed", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
        case .cancelled:
            Label("Cancelled", systemImage: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Status Card - Needs Upgrade") {
    ReembeddingStatusCard()
        .padding()
        .frame(width: 400)
}

#Preview("Detail View") {
    ReembeddingDetailView()
}

