// MARK: - Organization Preview View
// Shows proposed organization with folders and files, allows user adjustments

import SwiftUI

// MARK: - Organization Preview View

/// Displays a preview of proposed organization operations
/// Separates folder units from loose files for clarity
struct OrganizationPreviewView: View {
    let plan: HierarchyAwareOrganizationPlan
    let taxonomy: TaxonomyTree
    
    /// Callback when user wants to flatten a folder
    let onFlattenFolder: (ScannedFolder) -> Void
    
    /// Callback when user changes category for a folder
    let onChangeFolderCategory: (ScannedFolder, [String]) -> Void
    
    /// Callback when user confirms the plan
    let onConfirm: () -> Void
    
    /// Callback when user cancels
    let onCancel: () -> Void
    
    @State private var selectedFolders: Set<UUID> = []
    @State private var showingCategoryPicker: Bool = false
    @State private var folderToReassign: ScannedFolder?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            Divider()
            
            // Main content in scroll view
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Folder operations section
                    if !plan.folderOperations.isEmpty {
                        folderSection
                    }
                    
                    // File operations section
                    if !plan.fileOperations.isEmpty {
                        fileSection
                    }
                    
                    // Conflicts section
                    if plan.hasConflicts {
                        conflictSection
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer with actions
            footerSection
        }
        .frame(minWidth: 600, minHeight: 400)
        .sheet(item: $folderToReassign) { folder in
            CategoryPickerSheet(
                folder: folder,
                taxonomy: taxonomy,
                onSelect: { path in
                    onChangeFolderCategory(folder, path)
                    folderToReassign = nil
                },
                onCancel: {
                    folderToReassign = nil
                }
            )
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Organization Preview")
                    .font(.headline)
                
                Text("\(plan.totalItems) items (\(plan.folderOperations.count) folders, \(plan.fileOperations.count) files)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Size estimate
            VStack(alignment: .trailing, spacing: 4) {
                Text("Total Size")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(formatSize(plan.estimatedSize))
                    .font(.headline.monospacedDigit())
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Folder Section
    
    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text("Folder Units")
                    .font(.headline)
                
                Spacer()
                
                Text("These folders move as complete units")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(plan.folderOperations) { op in
                FolderPreviewRow(
                    operation: op,
                    isSelected: selectedFolders.contains(op.sourceFolder.id),
                    onToggleSelection: {
                        if selectedFolders.contains(op.sourceFolder.id) {
                            selectedFolders.remove(op.sourceFolder.id)
                        } else {
                            selectedFolders.insert(op.sourceFolder.id)
                        }
                    },
                    onFlatten: {
                        onFlattenFolder(op.sourceFolder)
                    },
                    onChangeCategory: {
                        folderToReassign = op.sourceFolder
                    }
                )
            }
        }
    }
    
    // MARK: - File Section
    
    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.fill")
                    .foregroundStyle(.green)
                Text("Individual Files")
                    .font(.headline)
                
                Spacer()
                
                Text("These files move separately")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Group files by destination category
            let grouped = Dictionary(grouping: plan.fileOperations) { 
                $0.destinationFolder.lastPathComponent 
            }
            
            ForEach(grouped.keys.sorted(), id: \.self) { category in
                DisclosureGroup {
                    ForEach(grouped[category] ?? [], id: \.sourceFile.id) { op in
                        FilePreviewRow(operation: op)
                    }
                } label: {
                    HStack {
                        Text(category)
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(grouped[category]?.count ?? 0) files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Conflict Section
    
    private var conflictSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Conflicts")
                    .font(.headline)
                
                Spacer()
                
                Text("\(plan.folderConflicts.count + plan.fileConflicts.count) items need attention")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if !plan.folderConflicts.isEmpty {
                ForEach(plan.folderConflicts) { conflict in
                    OrganizationConflictRow(
                        name: conflict.sourceFolder.folderName,
                        destinationPath: conflict.destinationPath.path,
                        isFolder: true
                    )
                }
            }
            
            if !plan.fileConflicts.isEmpty {
                ForEach(plan.fileConflicts) { conflict in
                    OrganizationConflictRow(
                        name: conflict.sourceFile.filename,
                        destinationPath: conflict.destinationPath.path,
                        isFolder: false
                    )
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Footer
    
    private var footerSection: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            if plan.hasConflicts {
                Text("⚠️ \(plan.folderConflicts.count + plan.fileConflicts.count) conflicts")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            
            Button("Organize Files") {
                onConfirm()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Helpers
    
    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Folder Preview Row

struct FolderPreviewRow: View {
    let operation: FolderOrganizationOperation
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onFlatten: () -> Void
    let onChangeCategory: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            Toggle("", isOn: .init(
                get: { isSelected },
                set: { _ in onToggleSelection() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            
            // Folder icon
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(.blue)
            
            // Folder info
            VStack(alignment: .leading, spacing: 2) {
                Text(operation.sourceFolder.folderName)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text("\(operation.sourceFolder.fileCount) files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(operation.sourceFolder.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Destination category
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(operation.destinationCategory)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
                
                // Confidence indicator
                HStack(spacing: 4) {
                    confidenceIndicator(operation.confidence)
                    Text("\(Int(operation.confidence * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Action buttons (visible on hover)
            if isHovering {
                HStack(spacing: 8) {
                    Button {
                        onChangeCategory()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Change category")
                    
                    Button {
                        onFlatten()
                    } label: {
                        Image(systemName: "rectangle.expand.vertical")
                    }
                    .buttonStyle(.borderless)
                    .help("Flatten folder (analyze files individually)")
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    @ViewBuilder
    private func confidenceIndicator(_ confidence: Double) -> some View {
        Circle()
            .fill(confidenceColor(confidence))
            .frame(width: 8, height: 8)
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.85 { return .green }
        if confidence >= 0.7 { return .yellow }
        if confidence >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - File Preview Row

struct FilePreviewRow: View {
    let operation: OrganizationOperation
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForFile(operation.sourceFile))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(operation.sourceFile.filename)
                    .font(.callout)
                
                Text(operation.sourceFile.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.leading, 24)
    }
    
    private func iconForFile(_ file: TaxonomyScannedFile) -> String {
        if file.isImage { return "photo" }
        if file.isVideo { return "video" }
        if file.isAudio { return "waveform" }
        if file.isDocument { return "doc.text" }
        return "doc"
    }
}

// MARK: - Organization Conflict Row

struct OrganizationConflictRow: View {
    let name: String
    let destinationPath: String
    let isFolder: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isFolder ? "folder.fill" : "doc.fill")
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .fontWeight(.medium)
                
                Text("Destination exists: \(destinationPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Text("Will be renamed")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.2))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Category Picker Sheet

struct CategoryPickerSheet: View {
    let folder: ScannedFolder
    let taxonomy: TaxonomyTree
    let onSelect: ([String]) -> Void
    let onCancel: () -> Void
    
    @State private var selectedPath: [String] = []
    @State private var customCategory: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Change Category")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.borderless)
            }
            
            Text("Select a category for '\(folder.folderName)'")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Divider()
            
            // Category list
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(taxonomy.allCategories(), id: \.id) { node in
                        Button {
                            selectedPath = node.path
                        } label: {
                            HStack {
                                let indent = CGFloat(node.depth) * 16
                                Text(node.name)
                                    .padding(.leading, indent)
                                Spacer()
                                if selectedPath == node.path {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 300)
            
            Divider()
            
            // Custom category input
            HStack {
                TextField("Or enter custom path...", text: $customCategory)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Actions
            HStack {
                Spacer()
                
                Button("Apply") {
                    if !customCategory.isEmpty {
                        let path = customCategory.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
                        onSelect(path)
                    } else if !selectedPath.isEmpty {
                        onSelect(selectedPath)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPath.isEmpty && customCategory.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 500)
    }
}

