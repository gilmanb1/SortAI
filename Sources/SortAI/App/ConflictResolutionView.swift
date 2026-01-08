// MARK: - Conflict Resolution View
// UI for resolving file organization conflicts

import SwiftUI

// MARK: - Conflict Resolution View

struct ConflictResolutionView: View {
    @Binding var conflicts: [OrganizationConflict]
    @State private var globalResolution: ConflictResolution = .rename
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.title2)
                
                VStack(alignment: .leading) {
                    Text("\(conflicts.count) File Conflicts Found")
                        .font(.headline)
                    Text("These files already exist at the destination")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Apply to all
                Menu {
                    ForEach(ConflictResolution.allCases.filter { $0 != .askUser }, id: \.self) { resolution in
                        Button(resolution.rawValue) {
                            applyToAll(resolution)
                        }
                    }
                } label: {
                    Label("Apply to All", systemImage: "checklist")
                }
            }
            .padding(.bottom, 8)
            
            Divider()
            
            // Conflict list
            if conflicts.isEmpty {
                ContentUnavailableView(
                    "No Conflicts",
                    systemImage: "checkmark.circle.fill",
                    description: Text("All files can be organized without conflicts")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(conflicts) { conflict in
                            ConflictRow(conflict: conflict) { resolution in
                                if let index = conflicts.firstIndex(where: { $0.id == conflict.id }) {
                                    conflicts[index].resolution = resolution
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // Summary
            if !conflicts.isEmpty {
                Divider()
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Resolution Summary")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 16) {
                            SummaryBadge(
                                count: conflicts.filter { $0.resolution == .skip }.count,
                                label: "Skip",
                                color: .gray
                            )
                            SummaryBadge(
                                count: conflicts.filter { $0.resolution == .rename }.count,
                                label: "Rename",
                                color: .blue
                            )
                            SummaryBadge(
                                count: conflicts.filter { $0.resolution == .replace }.count,
                                label: "Replace",
                                color: .orange
                            )
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding()
    }
    
    private func applyToAll(_ resolution: ConflictResolution) {
        for conflict in conflicts {
            conflict.resolution = resolution
        }
        // Force view update
        conflicts = conflicts
    }
}

// MARK: - Conflict Row

struct ConflictRow: View {
    let conflict: OrganizationConflict
    let onResolutionChanged: (ConflictResolution) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // File icon
                Image(systemName: iconForFile(conflict.sourceFile.filename))
                    .foregroundStyle(.blue)
                    .frame(width: 24)
                
                // File info
                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.sourceFile.filename)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    
                    Text(conflict.destinationPath.deletingLastPathComponent().lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Resolution picker
                Picker("Resolution", selection: Binding(
                    get: { conflict.resolution },
                    set: { onResolutionChanged($0) }
                )) {
                    ForEach(ConflictResolution.allCases.filter { $0 != .askUser }, id: \.self) { resolution in
                        Text(resolution.rawValue).tag(resolution)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            
            // Destination path
            HStack {
                Text("→")
                    .foregroundStyle(.secondary)
                Text(conflict.destinationPath.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, 32)
        }
        .padding(12)
        .background(resolutionColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(resolutionColor.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var resolutionColor: Color {
        switch conflict.resolution {
        case .skip: return .gray
        case .rename: return .blue
        case .replace: return .orange
        case .askUser: return .yellow
        }
    }
    
    private func iconForFile(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "m4a", "aac": return "waveform"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo"
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "tablecells"
        case "zip", "tar", "gz": return "archivebox"
        default: return "doc"
        }
    }
}

// MARK: - Summary Badge

struct SummaryBadge: View {
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        if count > 0 {
            HStack(spacing: 4) {
                Text("\(count)")
                    .fontWeight(.semibold)
                Text(label)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Preview

#Preview {
    ConflictResolutionView(conflicts: .constant([]))
        .frame(width: 600, height: 400)
}

