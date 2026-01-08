// MARK: - Hierarchy Editor View
// Tree view for editing taxonomy structure with drag-and-drop

import SwiftUI
import AppKit

// MARK: - Native macOS Editable Text Field
// Provides Finder-like inline editing behavior

struct InlineEditTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onCancel: () -> Void
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.isBordered = true
        textField.bezelStyle = .squareBezel
        textField.focusRingType = .exterior
        textField.drawsBackground = true
        textField.backgroundColor = .textBackgroundColor
        textField.stringValue = text
        
        // Ensure the field becomes first responder and selects all
        DispatchQueue.main.async {
            textField.window?.makeFirstResponder(textField)
            textField.selectText(nil)
            textField.currentEditor()?.selectedRange = NSRange(location: 0, length: textField.stringValue.count)
        }
        
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineEditTextField
        
        init(_ parent: InlineEditTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            // Commit on blur (clicking away)
            parent.onCommit()
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Return key pressed - commit
                parent.onCommit()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                // Escape key pressed - cancel
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

// MARK: - Hierarchy Editor View

struct HierarchyEditorView: View {
    @Bindable var taxonomy: TaxonomyTree
    
    @State private var selectedNode: TaxonomyNode?
    @State private var expandedNodes: Set<UUID> = []
    @State private var editingNode: TaxonomyNode?
    @State private var editingName: String = ""
    @State private var showingAddCategory: Bool = false
    @State private var newCategoryName: String = ""
    @State private var draggedNode: TaxonomyNode?
    
    var body: some View {
        HStack(spacing: 0) {
            // Tree view (left panel)
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Button {
                        addCategory()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add category")
                    
                    Button {
                        deleteSelected()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedNode == nil || selectedNode?.isRoot == true)
                    .help("Delete category")
                    
                    Button {
                        renameSelected()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .disabled(selectedNode == nil)
                    .help("Rename category (or double-click)")
                    
                    Divider()
                        .frame(height: 16)
                    
                    Button {
                        expandAll()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .help("Expand all")
                    
                    Button {
                        collapseAll()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Collapse all")
                    
                    Spacer()
                    
                    Text("\(taxonomy.categoryCount) categories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                
                Divider()
                
                // Tree - scrollable list
                ScrollView([.vertical, .horizontal], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        TreeNodeView(
                            node: taxonomy.root,
                            depth: 0,
                            selectedNode: $selectedNode,
                            expandedNodes: $expandedNodes,
                            editingNode: $editingNode,
                            editingName: $editingName,
                            draggedNode: $draggedNode,
                            onMove: handleMove
                        )
                    }
                    .padding(8)
                    .frame(minWidth: 280, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(minWidth: 300, idealWidth: 350)
            
            Divider()
            
            // Detail panel (right panel)
            VStack(spacing: 0) {
                if let node = selectedNode {
                    NodeDetailView(
                        node: node,
                        onRename: { newName in
                            node.name = newName
                        },
                        onAddSubcategory: { name in
                            let child = TaxonomyNode(name: name, parent: node, isUserCreated: true)
                            node.addChild(child)
                            expandedNodes.insert(node.id)
                        }
                    )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary.opacity(0.5))
                        
                        Text("Select a category to view details")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 280, idealWidth: 350, maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Expand root by default
            expandedNodes.insert(taxonomy.root.id)
        }
        .onKeyPress(.return) {
            // Enter key to rename selected node
            if editingNode == nil, let node = selectedNode {
                editingNode = node
                editingName = node.name
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.delete) {
            // Delete key to remove selected node
            if let node = selectedNode, !node.isRoot {
                node.parent?.removeChild(node)
                selectedNode = nil
                return .handled
            }
            return .ignored
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategorySheet(
                parentName: selectedNode?.name ?? taxonomy.root.name,
                name: $newCategoryName,
                onAdd: { name in
                    let parent = selectedNode ?? taxonomy.root
                    let child = TaxonomyNode(name: name, parent: parent, isUserCreated: true)
                    parent.addChild(child)
                    expandedNodes.insert(parent.id)
                    newCategoryName = ""
                },
                onCancel: {
                    newCategoryName = ""
                }
            )
        }
    }
    
    // MARK: - Actions
    
    private func addCategory() {
        showingAddCategory = true
    }
    
    private func renameSelected() {
        guard let node = selectedNode else { return }
        editingNode = node
        editingName = node.name
    }
    
    private func deleteSelected() {
        guard let node = selectedNode, !node.isRoot else { return }
        node.parent?.removeChild(node)
        selectedNode = nil
    }
    
    private func expandAll() {
        expandedNodes = Set(taxonomy.allCategories().map { $0.id })
    }
    
    private func collapseAll() {
        expandedNodes = [taxonomy.root.id]
    }
    
    private func handleMove(source: TaxonomyNode, target: TaxonomyNode) {
        guard source.id != target.id,
              !target.path.contains(source.name) else { return }  // Prevent circular moves
        
        source.move(to: target)
        expandedNodes.insert(target.id)
    }
}

// MARK: - Tree Node View

struct TreeNodeView: View {
    let node: TaxonomyNode
    let depth: Int
    
    @Binding var selectedNode: TaxonomyNode?
    @Binding var expandedNodes: Set<UUID>
    @Binding var editingNode: TaxonomyNode?
    @Binding var editingName: String
    @Binding var draggedNode: TaxonomyNode?
    
    let onMove: (TaxonomyNode, TaxonomyNode) -> Void
    
    @State private var isTargeted: Bool = false
    
    private var isExpanded: Bool {
        expandedNodes.contains(node.id)
    }
    
    private var isSelected: Bool {
        selectedNode?.id == node.id
    }
    
    private var isEditing: Bool {
        editingNode?.id == node.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Node row
            HStack(spacing: 4) {
                // Expand/collapse button
                if !node.isLeaf {
                    Button {
                        toggleExpanded()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 16)
                }
                
                // Folder icon
                Image(systemName: node.isLeaf ? "folder" : "folder.fill")
                    .foregroundStyle(node.isUserCreated ? .blue : .orange)
                    .font(.system(size: 14))
                
                // Name (editable or static)
                if isEditing {
                    // Use native NSTextField for proper macOS Finder-like behavior
                    InlineEditTextField(
                        text: $editingName,
                        onCommit: {
                            commitEdit()
                        },
                        onCancel: {
                            cancelEdit()
                        }
                    )
                    .frame(minWidth: 150, maxWidth: 250, minHeight: 22)
                } else {
                    Text(node.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .help("Double-click to rename")
                }
                
                Spacer()
                
                // File count badge
                if node.totalFileCount > 0 {
                    Text("\(node.totalFileCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                }
                
                // Confidence indicator
                if !node.isUserCreated && node.confidence < 1.0 {
                    Circle()
                        .fill(confidenceColor(node.confidence))
                        .frame(width: 8, height: 8)
                        .help("Confidence: \(Int(node.confidence * 100))%")
                }
            }
            .padding(.leading, CGFloat(depth) * 20)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
            )
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture(count: 2)
                    .onEnded {
                        if !isEditing {
                            startEditing()
                        }
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 1)
                    .onEnded {
                        if !isEditing {
                            selectedNode = node
                        }
                    }
            )
            .contextMenu {
                Button {
                    startEditing()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                
                Button {
                    let newNode = TaxonomyNode(name: "New Subcategory", parent: node, isUserCreated: true)
                    node.addChild(newNode)
                    expandedNodes.insert(node.id)
                } label: {
                    Label("Add Subcategory", systemImage: "folder.badge.plus")
                }
                
                Divider()
                
                Button {
                    if !node.isRoot {
                        node.parent?.removeChild(node)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(node.isRoot)
            }
            .draggable(node.id.uuidString) {
                Text(node.name)
                    .padding(8)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let idString = items.first,
                      let draggedId = UUID(uuidString: idString),
                      let sourceNode = findNode(by: draggedId) else {
                    return false
                }
                onMove(sourceNode, node)
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
            
            // Children (if expanded)
            if isExpanded {
                ForEach(node.children) { child in
                    TreeNodeView(
                        node: child,
                        depth: depth + 1,
                        selectedNode: $selectedNode,
                        expandedNodes: $expandedNodes,
                        editingNode: $editingNode,
                        editingName: $editingName,
                        draggedNode: $draggedNode,
                        onMove: onMove
                    )
                }
            }
        }
    }
    
    private var backgroundColor: Color {
        if isTargeted {
            return Color.accentColor.opacity(0.3)
        } else if isSelected {
            return Color.accentColor.opacity(0.2)
        } else {
            return Color.clear
        }
    }
    
    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.6 { return .yellow }
        return .red
    }
    
    private func toggleExpanded() {
        if expandedNodes.contains(node.id) {
            expandedNodes.remove(node.id)
        } else {
            expandedNodes.insert(node.id)
        }
    }
    
    private func startEditing() {
        editingNode = node
        editingName = node.name
    }
    
    private func commitEdit() {
        let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only update if name is not empty (like macOS Finder behavior)
        if !trimmedName.isEmpty {
            node.name = trimmedName
            node.refinementState = .userEdited  // Mark as user-edited to prevent LLM overwriting
        }
        editingNode = nil
        editingName = ""
    }
    
    private func cancelEdit() {
        editingNode = nil
        editingName = ""
    }
    
    private func findNode(by id: UUID) -> TaxonomyNode? {
        // Traverse tree to find node
        func search(_ node: TaxonomyNode) -> TaxonomyNode? {
            if node.id == id { return node }
            for child in node.children {
                if let found = search(child) { return found }
            }
            return nil
        }
        
        // Find root and search from there
        var root = node
        while let parent = root.parent {
            root = parent
        }
        return search(root)
    }
}

// MARK: - Node Detail View

struct NodeDetailView: View {
    @Bindable var node: TaxonomyNode
    let onRename: (String) -> Void
    let onAddSubcategory: (String) -> Void
    
    @State private var newSubcategoryName: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: node.isLeaf ? "folder" : "folder.fill")
                        .font(.title2)
                        .foregroundStyle(node.isUserCreated ? .blue : .orange)
                    
                    VStack(alignment: .leading) {
                        Text(node.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text(node.pathString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                
                Divider()
                
                // Stats
                GroupBox("Statistics") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Direct files:")
                            Spacer()
                            Text("\(node.directFileCount)")
                        }
                        
                        HStack {
                            Text("Total files (including children):")
                            Spacer()
                            Text("\(node.totalFileCount)")
                        }
                        
                        HStack {
                            Text("Subcategories:")
                            Spacer()
                            Text("\(node.children.count)")
                        }
                        
                        HStack {
                            Text("Confidence:")
                            Spacer()
                            Text("\(Int(node.confidence * 100))%")
                        }
                        
                        HStack {
                            Text("Source:")
                            Spacer()
                            Text(node.isUserCreated ? "User created" : "AI inferred")
                        }
                    }
                    .font(.caption)
                    .padding(8)
                }
                
                // Add subcategory
                GroupBox("Add Subcategory") {
                    HStack {
                        TextField("Subcategory name", text: $newSubcategoryName)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Add") {
                            guard !newSubcategoryName.isEmpty else { return }
                            onAddSubcategory(newSubcategoryName)
                            newSubcategoryName = ""
                        }
                        .disabled(newSubcategoryName.isEmpty)
                    }
                    .padding(8)
                }
                
                // Files preview
                if !node.assignedFiles.isEmpty {
                    GroupBox("Assigned Files (\(node.assignedFiles.count))") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(node.assignedFiles.prefix(10)), id: \.id) { file in
                                HStack {
                                    Image(systemName: "doc")
                                        .foregroundStyle(.secondary)
                                    
                                    Text(file.filename)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    if file.needsDeepAnalysis {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundStyle(.orange)
                                            .font(.caption)
                                    }
                                }
                                .font(.caption)
                            }
                            
                            if node.assignedFiles.count > 10 {
                                Text("... and \(node.assignedFiles.count - 10) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - Add Category Sheet

struct AddCategorySheet: View {
    let parentName: String
    @Binding var name: String
    let onAdd: (String) -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Category")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Parent: \(parentName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("Category name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
            }
            
            HStack {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Add") {
                    onAdd(name)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            // Auto-focus the text field when sheet appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let taxonomy = TaxonomyTree(rootName: "Downloads")
    
    // Add some test data
    let _ = taxonomy.addCategory(path: ["Documents", "Work"])
    let _ = taxonomy.addCategory(path: ["Documents", "Personal"])
    let _ = taxonomy.addCategory(path: ["Media", "Photos"])
    let _ = taxonomy.addCategory(path: ["Media", "Videos"])
    
    return HierarchyEditorView(taxonomy: taxonomy)
        .frame(width: 600, height: 400)
}

