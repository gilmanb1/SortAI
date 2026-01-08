// MARK: - Human Feedback UI Components
// Inline feedback display and batch review interface

import SwiftUI
import AppKit

// MARK: - Focusable TextField (NSViewRepresentable wrapper)

/// A TextField that properly handles first responder for keyboard input
/// This fixes the known SwiftUI issue where TextFields in sheets don't accept keyboard input
struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var onCommit: (() -> Void)? = nil
    
    @Binding var isFirstResponder: Bool
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .exterior
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        
        NSLog("🔲 [FocusableTextField] Created NSTextField")
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Update text if changed externally
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        
        // Handle focus request
        if isFirstResponder && nsView.window?.firstResponder != nsView {
            NSLog("🎯 [FocusableTextField] Requesting focus, window: %@", nsView.window?.title ?? "nil")
            DispatchQueue.main.async {
                if let window = nsView.window {
                    NSLog("🎯 [FocusableTextField] Making key and ordering front")
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    
                    let success = window.makeFirstResponder(nsView)
                    NSLog("🎯 [FocusableTextField] makeFirstResponder result: %@", success ? "SUCCESS" : "FAILED")
                    
                    // Select all text for easy editing
                    if success {
                        nsView.selectText(nil)
                    }
                } else {
                    NSLog("⚠️ [FocusableTextField] No window available!")
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField
        
        init(_ parent: FocusableTextField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
            NSLog("📝 [FocusableTextField] Text changed to: '%@'", textField.stringValue)
        }
        
        func controlTextDidEndEditing(_ notification: Notification) {
            NSLog("📝 [FocusableTextField] Editing ended (focus lost)")
            parent.isFirstResponder = false
            // Don't call onCommit here - only call it on explicit Return press
            // This prevents auto-saving when focus is lost
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                NSLog("📝 [FocusableTextField] Return key pressed - committing")
                parent.onCommit?()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                NSLog("📝 [FocusableTextField] Escape key pressed")
                // Let the parent handle escape via keyboard shortcut
                return false
            }
            return false
        }
    }
}

// MARK: - Inline Feedback View

/// Shows categorization result with inline accept/change options
struct InlineFeedbackView: View {
    let item: FeedbackDisplayItem
    let onAccept: () -> Void
    let onChange: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // File info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    // Category path
                    CategoryPathView(path: item.categoryPath)
                    
                    // Confidence badge
                    ConfidenceBadge(confidence: item.confidence)
                }
            }
            
            Spacer()
            
            // Actions
            if item.needsReview {
                HStack(spacing: 8) {
                    Button("Accept") {
                        onAccept()
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    
                    Button("Change") {
                        onChange()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Category Path View

/// Displays a hierarchical category path with breadcrumb styling
struct CategoryPathView: View {
    let path: CategoryPath
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(path.components.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Text(component)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(colorForLevel(index).opacity(0.2))
                    .foregroundStyle(colorForLevel(index))
                    .cornerRadius(4)
            }
        }
    }
    
    private func colorForLevel(_ level: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink]
        return colors[level % colors.count]
    }
}

// MARK: - Condensed Category Path View

/// Displays a condensed category path that expands on hover
/// Shows first and last components with "..." in between for long paths
struct CondensedCategoryPathView: View {
    let path: CategoryPath
    var maxVisibleComponents: Int = 2
    var compact: Bool = false  // For use in tight spaces like list rows
    
    @State private var isHovering = false
    
    private var needsCondensing: Bool {
        path.components.count > maxVisibleComponents
    }
    
    private var condensedComponents: [String] {
        guard needsCondensing else { return path.components }
        
        if path.components.count <= 1 {
            return path.components
        }
        
        // Show first and last components with ellipsis
        return [path.components.first!, "...", path.components.last!]
    }
    
    var body: some View {
        Group {
            if compact {
                compactView
            } else {
                fullView
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .popover(isPresented: $isHovering, arrowEdge: .bottom) {
            fullPathPopover
        }
    }
    
    // Compact inline view for list rows
    private var compactView: some View {
        HStack(spacing: 3) {
            ForEach(Array(condensedComponents.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    Text("/")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                
                if component == "..." {
                    Text("...")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(component)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            
            // Indicator that there's more to see
            if needsCondensing {
                Image(systemName: "info.circle")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    // Full breadcrumb view with pills
    private var fullView: some View {
        HStack(spacing: 4) {
            ForEach(Array(condensedComponents.enumerated()), id: \.offset) { index, component in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                if component == "..." {
                    Text("...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                } else {
                    let colorIndex = component == path.components.last ? path.components.count - 1 : (component == path.components.first ? 0 : 1)
                    Text(component)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(colorForLevel(colorIndex).opacity(0.2))
                        .foregroundStyle(colorForLevel(colorIndex))
                        .cornerRadius(4)
                }
            }
            
            // Hover hint
            if needsCondensing {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    // Popover showing full path
    private var fullPathPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Full Category Path")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 4) {
                ForEach(Array(path.components.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(component)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(colorForLevel(index).opacity(0.2))
                        .foregroundStyle(colorForLevel(index))
                        .cornerRadius(4)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func colorForLevel(_ level: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink]
        return colors[level % colors.count]
    }
}

// MARK: - Confidence Badge

/// Shows confidence level with color coding
struct ConfidenceBadge: View {
    let confidence: Double
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(confidenceColor)
                .frame(width: 8, height: 8)
            
            Text("\(Int(confidence * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var confidenceColor: Color {
        switch confidence {
        case 0.8...1.0: return .green
        case 0.5..<0.8: return .orange
        default: return .red
        }
    }
}

// MARK: - Batch Review View

/// Main view for reviewing uncertain categorizations
struct BatchReviewView: View {
    @Binding var items: [FeedbackDisplayItem]
    @Binding var isPresented: Bool
    let onComplete: () -> Void
    
    @State private var selectedIndex = 0
    @State private var showCategoryEditor = false
    @State private var newCategoryPath = ""
    
    var pendingItems: [FeedbackDisplayItem] {
        items.filter { $0.needsReview }
    }
    
    /// URLs for QuickLook - all pending items for cycling
    private var quickLookURLs: [URL] {
        pendingItems.map { URL(fileURLWithPath: $0.filePath) }
    }
    
    var body: some View {
        NavigationSplitView {
            // List of items
            List(selection: Binding(
                get: { pendingItems.indices.contains(selectedIndex) ? pendingItems[selectedIndex].id : nil },
                set: { newId in
                    if let newId, let index = pendingItems.firstIndex(where: { $0.id == newId }) {
                        selectedIndex = index
                    }
                }
            )) {
                ForEach(pendingItems) { item in
                    ReviewItemRow(item: item)
                        .tag(item.id)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 300)
            // Enable Space key to toggle QuickLook for the current item, with cycling through all
            .quickLookPreview(urls: quickLookURLs, currentIndex: selectedIndex)
        } detail: {
            if pendingItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                    
                    Text("All Items Reviewed!")
                        .font(.title)
                    
                    Button("Done") {
                        onComplete()
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if selectedIndex < pendingItems.count {
                ReviewDetailView(
                    item: pendingItems[selectedIndex],
                    onAccept: {
                        acceptCurrent()
                    },
                    onCorrect: { newPath in
                        correctCurrent(to: newPath)
                    },
                    onSkip: {
                        skipCurrent()
                    }
                )
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .toolbar {
            ToolbarItemGroup {
                Text("\(pendingItems.count) items need review")
                    .foregroundStyle(.secondary)
                
                Button("Skip All") {
                    skipAll()
                }
                .disabled(pendingItems.isEmpty)
                
                Button("Accept All") {
                    acceptAll()
                }
                .disabled(pendingItems.isEmpty)
            }
        }
    }
    
    private func acceptCurrent() {
        guard selectedIndex < pendingItems.count else { return }
        let itemId = pendingItems[selectedIndex].id
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].status = .humanAccepted
        }
        moveToNext()
    }
    
    private func correctCurrent(to newPath: CategoryPath) {
        guard selectedIndex < pendingItems.count else { return }
        let itemId = pendingItems[selectedIndex].id
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].categoryPath = newPath
            items[index].status = .humanCorrected
        }
        moveToNext()
    }
    
    private func skipCurrent() {
        guard selectedIndex < pendingItems.count else { return }
        let itemId = pendingItems[selectedIndex].id
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].status = .skipped
        }
        moveToNext()
    }
    
    private func moveToNext() {
        if selectedIndex >= pendingItems.count - 1 {
            selectedIndex = 0
        }
    }
    
    private func acceptAll() {
        for item in pendingItems {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].status = .humanAccepted
            }
        }
    }
    
    private func skipAll() {
        for item in pendingItems {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].status = .skipped
            }
        }
    }
}

// MARK: - Review Item Row

struct ReviewItemRow: View {
    let item: FeedbackDisplayItem
    
    var body: some View {
        HStack(spacing: 10) {
            // Clickable file icon for QuickLook preview
            QuickLookIcon(url: URL(fileURLWithPath: item.filePath), size: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.fileName)
                    .font(.headline)
                    .lineLimit(1)
                
                CondensedCategoryPathView(
                    path: item.categoryPath,
                    maxVisibleComponents: 2,
                    compact: true
                )
                
                ConfidenceBadge(confidence: item.confidence)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Review Detail View

struct ReviewDetailView: View {
    let item: FeedbackDisplayItem
    let onAccept: () -> Void
    let onCorrect: (CategoryPath) -> Void
    let onSkip: () -> Void
    
    @State private var isEditing = false
    @State private var editedPath: String = ""
    @State private var showCategoryBrowser = false
    @State private var isTextFieldFocused: Bool = false
    
    private var fileURL: URL {
        URL(fileURLWithPath: item.filePath)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // File info header with QuickLook preview
                VStack(spacing: 8) {
                    // Clickable file icon for QuickLook
                    QuickLookIcon(url: fileURL, size: 64)
                    
                    Text(item.fileName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 8) {
                        Text(item.filePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        // QuickLook button
                        QuickLookButton(url: fileURL)
                    }
                }
                
                Divider()
                
                // Suggested category
                VStack(alignment: .leading, spacing: 12) {
                    Text("Suggested Category")
                        .font(.headline)
                    
                    HStack {
                        CategoryPathView(path: item.categoryPath)
                        Spacer()
                        ConfidenceBadge(confidence: item.confidence)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    
                    Text(item.rationale)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                
                // Keywords
                if !item.keywords.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Extracted Keywords")
                            .font(.headline)
                        
                        FlowLayout(spacing: 6) {
                            ForEach(item.keywords.prefix(15), id: \.self) { keyword in
                                Text(keyword)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.1))
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 16)
                
                // Edit category
                if isEditing {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("New Category Path")
                            .font(.headline)
                        
                        HStack {
                            FocusableTextField(
                                text: $editedPath,
                                placeholder: "e.g., Education / Programming / Python",
                                onCommit: {
                                    if !editedPath.isEmpty {
                                        let newPath = CategoryPath(path: editedPath)
                                        onCorrect(newPath)
                                        isEditing = false
                                        editedPath = ""
                                    }
                                },
                                isFirstResponder: $isTextFieldFocused
                            )
                            .frame(height: 24)
                            
                            Button("Browse") {
                                showCategoryBrowser = true
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Text("Use '/' to separate levels: Main / Sub / Detail")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Actions
                HStack(spacing: 16) {
                    Button("Skip") {
                        onSkip()
                    }
                    .buttonStyle(.bordered)
                    // Only enable keyboard shortcut when not editing (prevents stealing input)
                    .keyboardShortcut(isEditing ? nil : KeyboardShortcut("s", modifiers: []))
                    
                    Spacer()
                    
                    if isEditing {
                        Button("Cancel") {
                            isEditing = false
                            editedPath = ""
                            isTextFieldFocused = false
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.escape, modifiers: [])
                        
                        Button("Save Category") {
                            let newPath = CategoryPath(path: editedPath)
                            onCorrect(newPath)
                            isEditing = false
                            editedPath = ""
                            isTextFieldFocused = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(editedPath.isEmpty)
                        .keyboardShortcut(.return, modifiers: [])
                    } else {
                        Button("Change Category") {
                            NSLog("🔘 [DEBUG] Change Category button clicked - starting edit mode")
                            editedPath = item.categoryPath.description
                            NSLog("🔘 [DEBUG] editedPath set to: '%@'", editedPath)
                            isEditing = true
                            NSLog("🔘 [DEBUG] isEditing set to: true")
                            // Log window state
                            if let window = NSApp.keyWindow {
                                NSLog("🪟 [DEBUG] Key window: %@, isKeyWindow: %@, firstResponder: %@",
                                      window.title,
                                      window.isKeyWindow ? "true" : "false",
                                      String(describing: window.firstResponder))
                            } else {
                                NSLog("🪟 [DEBUG] No key window!")
                            }
                            // Ensure app has focus and then focus the text field
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                NSLog("🎯 [DEBUG] Activating app and setting focus (delayed)...")
                                NSApp.activate(ignoringOtherApps: true)
                                isTextFieldFocused = true
                                NSLog("🎯 [DEBUG] isTextFieldFocused set to: %@", isTextFieldFocused ? "true" : "false")
                            }
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("c", modifiers: [])
                        
                        Button("Accept") {
                            onAccept()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .keyboardShortcut(.return, modifiers: [])
                    }
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .contentShape(Rectangle())
        // Removed onTapGesture - it was interfering with text field focus
        .onChange(of: isTextFieldFocused) { oldValue, newValue in
            NSLog("🎯 [DEBUG] isTextFieldFocused changed: %@ -> %@, isEditing: %@, editedPath: '%@'",
                  oldValue ? "true" : "false",
                  newValue ? "true" : "false",
                  isEditing ? "true" : "false",
                  editedPath)
            // Don't auto-exit editing mode - let user explicitly cancel or save
            // Only exit if the field was never focused (edge case)
        }
        .sheet(isPresented: $showCategoryBrowser) {
            CategoryBrowserView(
                selectedPath: $editedPath,
                isPresented: $showCategoryBrowser
            )
        }
        .onAppear {
            // Ensure the app window gets focus when appearing (fixes terminal launch issue)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

// MARK: - Category Browser View

/// Allows browsing and selecting from existing categories
struct CategoryBrowserView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedPath: String
    @Binding var isPresented: Bool
    var allowNewCategory: Bool = true
    var rootOnly: Bool = false  // Only show root-level categories
    
    @State private var existingCategories: [CategoryPath] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showNewCategoryInput = false
    @State private var newCategoryName = ""
    @State private var isSearchFieldFocused: Bool = false
    @State private var isNewCategoryFocused: Bool = false
    
    var filteredCategories: [CategoryPath] {
        var categories = existingCategories
        
        // Filter to root only if requested
        if rootOnly {
            categories = categories.filter { $0.components.count == 1 }
        }
        
        // Apply search filter
        if !searchText.isEmpty {
            categories = categories.filter {
                $0.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return categories
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(rootOnly ? "Select Root Category" : "Select Category")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding()
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                FocusableTextField(
                    text: $searchText,
                    placeholder: "Search categories...",
                    isFirstResponder: $isSearchFieldFocused
                )
                .frame(height: 20)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding()
            
            // Categories list
            if isLoading {
                Spacer()
                ProgressView("Loading categories...")
                    .frame(maxWidth: .infinity)
                Spacer()
            } else if filteredCategories.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    if searchText.isEmpty {
                        Text("No categories yet")
                            .font(.headline)
                        Text("Categories will appear here as you organize files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No matching categories")
                            .font(.headline)
                        Text("Try a different search or create a new category")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            } else {
                List(filteredCategories, id: \.self) { path in
                    Button {
                        selectedPath = path.description
                        isPresented = false
                    } label: {
                        HStack {
                            CategoryPathView(path: path)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
            
            // Create new section
            if allowNewCategory {
                Divider()
                
                if showNewCategoryInput {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("New Category Path")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            FocusableTextField(
                                text: $newCategoryName,
                                placeholder: "e.g., Work / Projects / Active",
                                onCommit: {
                                    if !newCategoryName.isEmpty {
                                        selectedPath = newCategoryName
                                        isPresented = false
                                    }
                                },
                                isFirstResponder: $isNewCategoryFocused
                            )
                            .frame(height: 24)
                            
                            Button("Add") {
                                if !newCategoryName.isEmpty {
                                    selectedPath = newCategoryName
                                    isPresented = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newCategoryName.isEmpty)
                            
                            Button("Cancel") {
                                showNewCategoryInput = false
                                newCategoryName = ""
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Text("Use '/' to separate levels: Main / Sub / Detail")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                } else {
                    HStack {
                        Text("Don't see what you need?")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showNewCategoryInput = true
                            // Focus after a brief delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isNewCategoryFocused = true
                            }
                        } label: {
                            Label("Create New", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            }
        }
        .frame(width: 500, height: 450)
        .onAppear {
            loadCategories()
            // Focus search field on appear
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isSearchFieldFocused = true
            }
        }
    }
    
    private func loadCategories() {
        isLoading = true
        
        Task {
            let categories = await appState.getExistingCategories()
            
            await MainActor.run {
                existingCategories = categories.sorted { $0.description < $1.description }
                isLoading = false
                NSLog("📋 [CategoryBrowser] Loaded %d categories", existingCategories.count)
            }
        }
    }
}

// MARK: - Display Model

/// UI model for feedback items
struct FeedbackDisplayItem: Identifiable {
    let id: Int64
    let fileName: String
    let filePath: String
    let fileIcon: String
    var categoryPath: CategoryPath
    let confidence: Double
    let rationale: String
    let keywords: [String]
    var status: FeedbackItem.FeedbackStatus
    
    var needsReview: Bool {
        status == .pending
    }
    
    // Memberwise initializer
    init(
        id: Int64,
        fileName: String,
        filePath: String,
        fileIcon: String,
        categoryPath: CategoryPath,
        confidence: Double,
        rationale: String,
        keywords: [String],
        status: FeedbackItem.FeedbackStatus
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.fileIcon = fileIcon
        self.categoryPath = categoryPath
        self.confidence = confidence
        self.rationale = rationale
        self.keywords = keywords
        self.status = status
    }
    
    init(from feedbackItem: FeedbackItem) {
        self.id = feedbackItem.id ?? 0
        self.fileName = feedbackItem.fileName
        self.filePath = feedbackItem.fileURL
        self.fileIcon = Self.iconForFile(feedbackItem.fileName)
        self.categoryPath = feedbackItem.suggestedPath
        self.confidence = feedbackItem.confidence
        self.rationale = feedbackItem.rationale
        self.keywords = feedbackItem.keywords
        self.status = feedbackItem.status
    }
    
    private static func iconForFile(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "mp4", "mov", "avi", "mkv": return "film.fill"
        case "mp3", "m4a", "wav": return "music.note"
        case "jpg", "jpeg", "png", "gif": return "photo.fill"
        case "txt", "md": return "doc.text.fill"
        default: return "doc.fill"
        }
    }
}

// MARK: - Queue Stats View

/// Shows feedback queue statistics
struct QueueStatsView: View {
    let stats: QueueStatistics
    
    var body: some View {
        HStack(spacing: 24) {
            StatItem(title: "Pending", value: stats.pendingReview, color: .orange)
            StatItem(title: "Auto-Accepted", value: stats.autoAccepted, color: .blue)
            StatItem(title: "Confirmed", value: stats.humanAccepted, color: .green)
            StatItem(title: "Corrected", value: stats.humanCorrected, color: .purple)
            
            Divider()
                .frame(height: 30)
            
            VStack(spacing: 2) {
                Text("\(Int(stats.accuracy * 100))%")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(stats.accuracy > 0.8 ? .green : .orange)
                Text("Accuracy")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct StatItem: View {
    let title: String
    let value: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

