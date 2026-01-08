// MARK: - Taxonomy Data Models
// Represents hierarchical category structures for file organization

import Foundation

// MARK: - Taxonomy Node

/// A single node in the taxonomy tree
/// Supports arbitrary depth and can track file assignments
@Observable
final class TaxonomyNode: Identifiable, Hashable, @unchecked Sendable {
    
    // MARK: - Properties
    
    let id: UUID
    var name: String
    var parent: TaxonomyNode?
    var children: [TaxonomyNode]
    
    /// Files assigned to this category
    var assignedFiles: [FileAssignment]
    
    /// Confidence score for auto-generated categories (0-1)
    var confidence: Double
    
    /// Whether this node was created by user vs inferred
    var isUserCreated: Bool
    
    /// Metadata for additional info
    var metadata: [String: String]
    
    /// Suggested name from LLM refinement
    var suggestedName: String?
    
    /// Current refinement state
    var refinementState: NodeRefinementState = .initial
    
    /// Refinement state for this node
    enum NodeRefinementState: String, Sendable {
        case initial
        case refining
        case refined
        case userEdited
    }
    
    /// Whether user has manually edited this category
    var isUserEdited: Bool {
        refinementState == .userEdited
    }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        name: String,
        parent: TaxonomyNode? = nil,
        children: [TaxonomyNode] = [],
        assignedFiles: [FileAssignment] = [],
        confidence: Double = 1.0,
        isUserCreated: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.parent = parent
        self.children = children
        self.assignedFiles = assignedFiles
        self.confidence = confidence
        self.isUserCreated = isUserCreated
        self.metadata = metadata
    }
    
    // MARK: - Computed Properties
    
    /// Full path from root to this node
    var path: [String] {
        var components: [String] = [name]
        var current = parent
        while let p = current {
            components.insert(p.name, at: 0)
            current = p.parent
        }
        return components
    }
    
    /// Path as a display string
    var pathString: String {
        path.joined(separator: " / ")
    }
    
    /// Depth in the tree (root = 0)
    var depth: Int {
        var d = 0
        var current = parent
        while current != nil {
            d += 1
            current = current?.parent
        }
        return d
    }
    
    /// Total number of files in this node and all descendants
    var totalFileCount: Int {
        assignedFiles.count + children.reduce(0) { $0 + $1.totalFileCount }
    }
    
    /// Direct file count (not including children)
    var directFileCount: Int {
        assignedFiles.count
    }
    
    /// Whether this is a leaf node (no children)
    var isLeaf: Bool {
        children.isEmpty
    }
    
    /// Whether this is the root node
    var isRoot: Bool {
        parent == nil
    }
    
    // MARK: - Tree Operations
    
    /// Add a child node
    func addChild(_ node: TaxonomyNode) {
        node.parent = self
        children.append(node)
    }
    
    /// Remove a child node
    func removeChild(_ node: TaxonomyNode) {
        children.removeAll { $0.id == node.id }
        node.parent = nil
    }
    
    /// Find a node by path
    func find(path: [String]) -> TaxonomyNode? {
        guard !path.isEmpty else { return nil }
        
        if path.count == 1 && path[0] == name {
            return self
        }
        
        // Check if first component matches this node
        guard path[0] == name else { return nil }
        
        // Look in children for the rest of the path
        let remainingPath = Array(path.dropFirst())
        if remainingPath.isEmpty { return self }
        
        for child in children {
            if child.name == remainingPath[0] {
                if remainingPath.count == 1 {
                    return child
                }
                return child.find(path: remainingPath)
            }
        }
        
        return nil
    }
    
    /// Find or create a path, creating intermediate nodes as needed
    func findOrCreate(path: [String]) -> TaxonomyNode {
        guard !path.isEmpty else { return self }
        
        let childName = path[0]
        let remainingPath = Array(path.dropFirst())
        
        // Find existing child
        if let existingChild = children.first(where: { $0.name == childName }) {
            if remainingPath.isEmpty {
                return existingChild
            }
            return existingChild.findOrCreate(path: remainingPath)
        }
        
        // Create new child
        let newChild = TaxonomyNode(name: childName, parent: self)
        children.append(newChild)
        
        if remainingPath.isEmpty {
            return newChild
        }
        return newChild.findOrCreate(path: remainingPath)
    }
    
    /// Move this node to a new parent
    func move(to newParent: TaxonomyNode) {
        parent?.removeChild(self)
        newParent.addChild(self)
    }
    
    /// Get all descendants (flattened)
    func allDescendants() -> [TaxonomyNode] {
        var result: [TaxonomyNode] = []
        for child in children {
            result.append(child)
            result.append(contentsOf: child.allDescendants())
        }
        return result
    }
    
    /// Get all leaf nodes
    func allLeaves() -> [TaxonomyNode] {
        if isLeaf {
            return [self]
        }
        return children.flatMap { $0.allLeaves() }
    }
    
    // MARK: - File Operations
    
    /// Assign a file to this category
    func assign(file: FileAssignment) {
        assignedFiles.append(file)
    }
    
    /// Assign a file directly to this node (alias for assign)
    func assignFile(_ file: FileAssignment) {
        assignedFiles.append(file)
    }
    
    /// Remove a file assignment
    func unassign(fileId: UUID) {
        assignedFiles.removeAll { $0.id == fileId }
    }
    
    /// Get all files including those in children
    func allFiles() -> [FileAssignment] {
        assignedFiles + children.flatMap { $0.allFiles() }
    }
    
    /// Get all files recursively (alias for allFiles)
    func allFilesRecursive() -> [FileAssignment] {
        allFiles()
    }
    
    // MARK: - Hashable & Equatable
    
    static func == (lhs: TaxonomyNode, rhs: TaxonomyNode) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - File Assignment

/// Represents a file assigned to a taxonomy node
struct FileAssignment: Identifiable, Hashable, Sendable {
    let id: UUID
    let fileId: UUID  // Original scanned file ID
    let categoryId: UUID  // Category node ID
    let url: URL
    let filename: String
    let confidence: Double
    let needsDeepAnalysis: Bool
    let assignedAt: Date
    
    /// Source of the assignment
    let source: AssignmentSource
    
    enum AssignmentSource: String, Sendable, Codable {
        case filename    // Inferred from filename alone
        case content     // From deep content analysis
        case user        // Manually assigned by user
        case memory      // From learned patterns
        case graphRAG    // From knowledge graph
    }
    
    init(
        id: UUID = UUID(),
        fileId: UUID? = nil,
        categoryId: UUID? = nil,
        url: URL,
        filename: String,
        confidence: Double,
        needsDeepAnalysis: Bool = false,
        source: AssignmentSource = .filename,
        assignedAt: Date = Date()
    ) {
        self.id = id
        self.fileId = fileId ?? id
        self.categoryId = categoryId ?? UUID()
        self.url = url
        self.filename = filename
        self.confidence = confidence
        self.needsDeepAnalysis = needsDeepAnalysis
        self.source = source
        self.assignedAt = assignedAt
    }
}

// MARK: - Taxonomy Tree

/// Complete taxonomy tree with root node and management operations
@Observable
final class TaxonomyTree: @unchecked Sendable {
    
    // MARK: - Properties
    
    let id: UUID
    let root: TaxonomyNode
    var createdAt: Date
    var modifiedAt: Date
    
    /// Source folder this taxonomy was created from
    var sourceFolderName: String?
    
    /// Whether the user has verified this taxonomy
    var isVerified: Bool
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        rootName: String,
        sourceFolderName: String? = nil
    ) {
        self.id = id
        self.root = TaxonomyNode(name: rootName, isUserCreated: false)
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.sourceFolderName = sourceFolderName
        self.isVerified = false
    }
    
    // MARK: - Computed Properties
    
    /// Total number of categories (nodes)
    var categoryCount: Int {
        1 + root.allDescendants().count
    }
    
    /// Total number of files assigned
    var totalFileCount: Int {
        root.totalFileCount
    }
    
    /// Number of files needing deep analysis
    var filesNeedingDeepAnalysis: Int {
        root.allFiles().filter { $0.needsDeepAnalysis }.count
    }
    
    /// Number of uncategorized files (in root with low confidence)
    var uncategorizedFileCount: Int {
        root.assignedFiles.filter { $0.confidence < 0.75 }.count
    }
    
    /// Maximum depth of the tree
    var maxDepth: Int {
        func depth(of node: TaxonomyNode) -> Int {
            if node.isLeaf { return 0 }
            return 1 + (node.children.map { depth(of: $0) }.max() ?? 0)
        }
        return depth(of: root)
    }
    
    // MARK: - Tree Operations
    
    /// Find a node by path
    func find(path: [String]) -> TaxonomyNode? {
        guard let first = path.first, first == root.name else {
            // Try without requiring root name match
            return root.findOrCreate(path: path)
        }
        return root.find(path: path)
    }
    
    /// Find or create a category path
    func findOrCreate(path: [String]) -> TaxonomyNode {
        root.findOrCreate(path: path)
    }
    
    /// Add a category at the specified path
    func addCategory(path: [String], isUserCreated: Bool = false) -> TaxonomyNode {
        let node = root.findOrCreate(path: path)
        node.isUserCreated = isUserCreated
        modifiedAt = Date()
        return node
    }
    
    /// Remove a category (moves files to parent)
    func removeCategory(path: [String]) {
        guard let node = find(path: path), let parent = node.parent else { return }
        
        // Move files to parent
        parent.assignedFiles.append(contentsOf: node.assignedFiles)
        
        // Move children to parent
        for child in node.children {
            child.parent = parent
            parent.children.append(child)
        }
        
        parent.removeChild(node)
        modifiedAt = Date()
    }
    
    /// Rename a category
    func renameCategory(path: [String], newName: String) {
        guard let node = find(path: path) else { return }
        node.name = newName
        modifiedAt = Date()
    }
    
    /// Merge two categories (source into target)
    func mergeCategories(sourcePath: [String], into targetPath: [String]) {
        guard let source = find(path: sourcePath),
              let target = find(path: targetPath),
              source.id != target.id else { return }
        
        // Move files
        target.assignedFiles.append(contentsOf: source.assignedFiles)
        
        // Move children
        for child in source.children {
            child.parent = target
            target.children.append(child)
        }
        
        // Remove source
        source.parent?.removeChild(source)
        modifiedAt = Date()
    }
    
    /// Split a category (create subcategories)
    func splitCategory(path: [String], into subcategories: [String]) {
        guard let node = find(path: path) else { return }
        
        for name in subcategories {
            let child = TaxonomyNode(name: name, parent: node, isUserCreated: true)
            node.children.append(child)
        }
        modifiedAt = Date()
    }
    
    /// Assign a file to a category
    func assignFile(_ assignment: FileAssignment, to path: [String]) {
        let node = findOrCreate(path: path)
        node.assign(file: assignment)
        modifiedAt = Date()
    }
    
    /// Get all categories as flat list
    func allCategories() -> [TaxonomyNode] {
        [root] + root.allDescendants()
    }
    
    /// Get all leaf categories
    func allLeafCategories() -> [TaxonomyNode] {
        root.allLeaves()
    }
    
    /// Get categories sorted by file count (descending)
    func categoriesByFileCount() -> [TaxonomyNode] {
        allCategories().sorted { $0.totalFileCount > $1.totalFileCount }
    }
    
    /// Find a node by its UUID
    func node(byId id: UUID) -> TaxonomyNode? {
        if root.id == id { return root }
        return root.allDescendants().first { $0.id == id }
    }
    
    /// Get the path of node names from root to the given node
    func pathToNode(_ node: TaxonomyNode) -> [TaxonomyNode] {
        var path: [TaxonomyNode] = [node]
        var current = node.parent
        while let p = current {
            path.insert(p, at: 0)
            current = p.parent
        }
        return path
    }
    
    /// Get all file assignments from all nodes
    func allAssignments() -> [FileAssignment] {
        root.allFiles()
    }
    
    /// Get confidence for a specific file ID
    func confidenceForFile(_ fileId: UUID) -> Double {
        for file in root.allFiles() {
            if file.id == fileId {
                return file.confidence
            }
        }
        return 0.0
    }
    
    /// Reassign a file to a new category path with updated confidence
    func reassignFile(fileId: UUID, toCategoryPath: [String], confidence: Double) {
        // Remove from current location
        removeFileFromTree(fileId: fileId, node: root)
        
        // Add to new location
        let targetNode = findOrCreate(path: toCategoryPath)
        
        // Find the original file info (if it was just removed, we lost it - need to track)
        // For now, create a minimal assignment
        // In practice, caller should provide full FileAssignment or this should track originals
        let newAssignment = FileAssignment(
            id: fileId,
            url: URL(fileURLWithPath: "/unknown"),
            filename: "reassigned_file",
            confidence: confidence,
            source: .content
        )
        targetNode.assign(file: newAssignment)
        modifiedAt = Date()
    }
    
    /// Remove a file from all nodes in the tree
    private func removeFileFromTree(fileId: UUID, node: TaxonomyNode) {
        node.unassign(fileId: fileId)
        for child in node.children {
            removeFileFromTree(fileId: fileId, node: child)
        }
    }
    
    // MARK: - Serialization
    
    /// Export tree structure as dictionary (for JSON)
    func toDictionary() -> [String: Any] {
        func nodeToDict(_ node: TaxonomyNode) -> [String: Any] {
            var dict: [String: Any] = [
                "id": node.id.uuidString,
                "name": node.name,
                "confidence": node.confidence,
                "isUserCreated": node.isUserCreated,
                "fileCount": node.directFileCount
            ]
            
            if !node.children.isEmpty {
                dict["children"] = node.children.map { nodeToDict($0) }
            }
            
            return dict
        }
        
        return [
            "id": id.uuidString,
            "root": nodeToDict(root),
            "createdAt": createdAt.timeIntervalSince1970,
            "modifiedAt": modifiedAt.timeIntervalSince1970,
            "sourceFolderName": sourceFolderName ?? "",
            "isVerified": isVerified
        ]
    }
}

// MARK: - Taxonomy Statistics

/// Statistics about a taxonomy tree
struct TaxonomyStatistics: Sendable {
    let categoryCount: Int
    let maxDepth: Int
    let totalFiles: Int
    let filesNeedingDeepAnalysis: Int
    let uncategorizedFiles: Int
    let averageConfidence: Double
    let userCreatedCategories: Int
    let inferredCategories: Int
    
    init(from tree: TaxonomyTree) {
        let allNodes = tree.allCategories()
        let allFiles = tree.root.allFiles()
        
        self.categoryCount = allNodes.count
        self.maxDepth = tree.maxDepth
        self.totalFiles = allFiles.count
        self.filesNeedingDeepAnalysis = allFiles.filter { $0.needsDeepAnalysis }.count
        self.uncategorizedFiles = tree.root.assignedFiles.filter { $0.confidence < 0.75 }.count
        self.averageConfidence = allFiles.isEmpty ? 0 : allFiles.reduce(0.0) { $0 + $1.confidence } / Double(allFiles.count)
        self.userCreatedCategories = allNodes.filter { $0.isUserCreated }.count
        self.inferredCategories = allNodes.filter { !$0.isUserCreated }.count
    }
}

