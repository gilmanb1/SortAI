// MARK: - Taxonomy Pipeline Enhancements
// Depth enforcement, merge/split gating, and guardrails for user edits

import Foundation

// MARK: - Taxonomy Depth Configuration

/// Configuration for taxonomy depth constraints
struct TaxonomyDepthConfiguration: Sendable {
    /// Minimum allowed depth (inclusive)
    let minDepth: Int
    
    /// Maximum allowed depth (inclusive)
    let maxDepth: Int
    
    /// How to handle depth violations
    let depthEnforcement: DepthEnforcementStrategy
    
    /// Whether to show warnings for approaching limits
    let showDepthWarnings: Bool
    
    enum DepthEnforcementStrategy: String, Sendable {
        case strict      // Prevent creating categories beyond max depth
        case advisory    // Allow but warn
        case flatten     // Automatically flatten to max depth
    }
    
    static let `default` = TaxonomyDepthConfiguration(
        minDepth: 2,
        maxDepth: 5,
        depthEnforcement: .advisory,
        showDepthWarnings: true
    )
    
    static let strict = TaxonomyDepthConfiguration(
        minDepth: 3,
        maxDepth: 7,
        depthEnforcement: .strict,
        showDepthWarnings: true
    )
    
    /// Validate that a depth is within allowed range
    func isValid(depth: Int) -> Bool {
        depth >= minDepth && depth <= maxDepth
    }
    
    /// Get suggested depth adjustment
    func suggestedDepth(for depth: Int) -> Int {
        if depth < minDepth { return minDepth }
        if depth > maxDepth { return maxDepth }
        return depth
    }
}

// MARK: - Depth Enforcer

/// Enforces depth constraints on taxonomy trees
actor TaxonomyDepthEnforcer {
    
    private let config: TaxonomyDepthConfiguration
    
    init(configuration: TaxonomyDepthConfiguration = .default) {
        self.config = configuration
    }
    
    /// Validate a taxonomy tree against depth constraints
    func validate(_ tree: TaxonomyTree) -> DepthValidationResult {
        var violations: [DepthViolation] = []
        var warnings: [DepthWarning] = []
        
        let allNodes = tree.allCategories()
        let currentMaxDepth = tree.maxDepth
        
        // Check overall depth
        if currentMaxDepth > config.maxDepth {
            violations.append(DepthViolation(
                type: .exceedsMaximum,
                currentDepth: currentMaxDepth,
                allowedDepth: config.maxDepth,
                affectedNodes: allNodes.filter { $0.depth > config.maxDepth }
            ))
        }
        
        if currentMaxDepth < config.minDepth {
            warnings.append(DepthWarning(
                type: .belowMinimum,
                currentDepth: currentMaxDepth,
                suggestedDepth: config.minDepth
            ))
        }
        
        // Check individual nodes
        for node in allNodes {
            if node.depth > config.maxDepth {
                violations.append(DepthViolation(
                    type: .nodeExceedsMaximum,
                    currentDepth: node.depth,
                    allowedDepth: config.maxDepth,
                    affectedNodes: [node]
                ))
            }
            
            // Warning if approaching max depth
            if config.showDepthWarnings && node.depth == config.maxDepth - 1 && !node.isLeaf {
                warnings.append(DepthWarning(
                    type: .approachingMaximum,
                    currentDepth: node.depth,
                    suggestedDepth: config.maxDepth
                ))
            }
        }
        
        return DepthValidationResult(
            isValid: violations.isEmpty,
            violations: violations,
            warnings: warnings,
            currentMaxDepth: currentMaxDepth,
            allowedMaxDepth: config.maxDepth
        )
    }
    
    /// Enforce depth constraints by flattening deep hierarchies
    func enforce(_ tree: TaxonomyTree) async throws {
        let validation = validate(tree)
        
        guard !validation.isValid else { return }
        
        switch config.depthEnforcement {
        case .strict:
            throw TaxonomyPipelineError.depthConstraintViolation(validation)
            
        case .advisory:
            // Just log, don't modify
            NSLog("⚠️ [DepthEnforcer] Advisory: Tree exceeds depth limits (\(validation.currentMaxDepth) > \(config.maxDepth))")
            
        case .flatten:
            // Flatten nodes exceeding max depth
            try await flattenExcessiveDepth(tree)
        }
    }
    
    /// Flatten nodes that exceed maximum depth
    private func flattenExcessiveDepth(_ tree: TaxonomyTree) async throws {
        let allNodes = tree.allCategories()
        let violatingNodes = allNodes.filter { $0.depth > config.maxDepth }
        
        for node in violatingNodes {
            // Move children up to allowed depth
            if let parent = node.parent {
                // Move this node's children to parent
                for child in node.children {
                    parent.addChild(child)
                }
                
                // Move files to parent
                parent.assignedFiles.append(contentsOf: node.assignedFiles)
                
                // Remove this node
                parent.removeChild(node)
            }
        }
        
        NSLog("✅ [DepthEnforcer] Flattened \(violatingNodes.count) nodes to enforce max depth \(config.maxDepth)")
    }
}

// MARK: - Depth Validation Results

struct DepthValidationResult: Sendable {
    let isValid: Bool
    let violations: [DepthViolation]
    let warnings: [DepthWarning]
    let currentMaxDepth: Int
    let allowedMaxDepth: Int
}

struct DepthViolation: Sendable, Identifiable {
    let id = UUID()
    let type: ViolationType
    let currentDepth: Int
    let allowedDepth: Int
    let affectedNodes: [TaxonomyNode]
    
    enum ViolationType: String, Sendable {
        case exceedsMaximum = "Exceeds maximum depth"
        case nodeExceedsMaximum = "Node exceeds maximum depth"
    }
}

struct DepthWarning: Sendable, Identifiable {
    let id = UUID()
    let type: WarningType
    let currentDepth: Int
    let suggestedDepth: Int
    
    enum WarningType: String, Sendable {
        case belowMinimum = "Below minimum depth"
        case approachingMaximum = "Approaching maximum depth"
    }
}

// MARK: - Merge/Split Suggestions

/// Represents a suggestion to merge categories
struct MergeSuggestion: Identifiable, Sendable {
    let id: UUID
    let sourceNodes: [TaxonomyNode]
    let targetNode: TaxonomyNode
    let reason: String
    let confidence: Double
    let createdAt: Date
    var status: SuggestionStatus
    
    enum SuggestionStatus: String, Sendable {
        case pending = "Pending Review"
        case approved = "Approved"
        case rejected = "Rejected"
        case applied = "Applied"
    }
    
    init(
        id: UUID = UUID(),
        sourceNodes: [TaxonomyNode],
        targetNode: TaxonomyNode,
        reason: String,
        confidence: Double,
        status: SuggestionStatus = .pending
    ) {
        self.id = id
        self.sourceNodes = sourceNodes
        self.targetNode = targetNode
        self.reason = reason
        self.confidence = confidence
        self.createdAt = Date()
        self.status = status
    }
}

/// Represents a suggestion to split a category
struct SplitSuggestion: Identifiable, Sendable {
    let id: UUID
    let sourceNode: TaxonomyNode
    let proposedSubcategories: [ProposedSubcategory]
    let reason: String
    let confidence: Double
    let createdAt: Date
    var status: SuggestionStatus
    
    struct ProposedSubcategory: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let exemplarFiles: [String]  // Sample filenames
        let confidence: Double
    }
    
    enum SuggestionStatus: String, Sendable {
        case pending = "Pending Review"
        case approved = "Approved"
        case rejected = "Rejected"
        case applied = "Applied"
    }
    
    init(
        id: UUID = UUID(),
        sourceNode: TaxonomyNode,
        proposedSubcategories: [ProposedSubcategory],
        reason: String,
        confidence: Double,
        status: SuggestionStatus = .pending
    ) {
        self.id = id
        self.sourceNode = sourceNode
        self.proposedSubcategories = proposedSubcategories
        self.reason = reason
        self.confidence = confidence
        self.createdAt = Date()
        self.status = status
    }
}

// MARK: - Merge/Split Gatekeeper

/// Manages merge/split suggestions with explicit approval flow
actor MergeSplitGatekeeper {
    
    private var mergeSuggestions: [UUID: MergeSuggestion] = [:]
    private var splitSuggestions: [UUID: SplitSuggestion] = [:]
    
    // MARK: - Suggestion Management
    
    /// Add a merge suggestion for review
    func suggestMerge(_ suggestion: MergeSuggestion) {
        // Check for user-edited nodes
        let hasUserEdited = suggestion.sourceNodes.contains { $0.isUserEdited }
                         || suggestion.targetNode.isUserEdited
        
        if hasUserEdited {
            NSLog("⚠️ [MergeSplitGatekeeper] Merge suggestion involves user-edited nodes - requires explicit approval")
        }
        
        mergeSuggestions[suggestion.id] = suggestion
        NSLog("📋 [MergeSplitGatekeeper] Added merge suggestion: \(suggestion.sourceNodes.map { $0.name }.joined(separator: ", ")) → \(suggestion.targetNode.name)")
    }
    
    /// Add a split suggestion for review
    func suggestSplit(_ suggestion: SplitSuggestion) {
        // Check for user-edited nodes
        if suggestion.sourceNode.isUserEdited {
            NSLog("⚠️ [MergeSplitGatekeeper] Split suggestion involves user-edited node - requires explicit approval")
        }
        
        splitSuggestions[suggestion.id] = suggestion
        NSLog("📋 [MergeSplitGatekeeper] Added split suggestion: \(suggestion.sourceNode.name) → \(suggestion.proposedSubcategories.count) subcategories")
    }
    
    /// Get all pending merge suggestions
    func getPendingMerges() -> [MergeSuggestion] {
        mergeSuggestions.values.filter { $0.status == .pending }
    }
    
    /// Get all pending split suggestions
    func getPendingSplits() -> [SplitSuggestion] {
        splitSuggestions.values.filter { $0.status == .pending }
    }
    
    /// Approve and apply a merge suggestion
    func approveMerge(id: UUID, tree: TaxonomyTree) throws {
        guard var suggestion = mergeSuggestions[id] else {
            throw TaxonomyPipelineError.suggestionNotFound(id)
        }
        
        guard suggestion.status == .pending else {
            throw TaxonomyPipelineError.suggestionAlreadyProcessed(suggestion.status.rawValue)
        }
        
        // Apply the merge
        for sourceNode in suggestion.sourceNodes {
            let sourcePath = sourceNode.path
            let targetPath = suggestion.targetNode.path
            tree.mergeCategories(sourcePath: sourcePath, into: targetPath)
        }
        
        suggestion.status = .applied
        mergeSuggestions[id] = suggestion
        
        NSLog("✅ [MergeSplitGatekeeper] Applied merge: \(suggestion.sourceNodes.map { $0.name }.joined(separator: ", ")) → \(suggestion.targetNode.name)")
    }
    
    /// Approve and apply a split suggestion
    func approveSplit(id: UUID, tree: TaxonomyTree) throws {
        guard var suggestion = splitSuggestions[id] else {
            throw TaxonomyPipelineError.suggestionNotFound(id)
        }
        
        guard suggestion.status == .pending else {
            throw TaxonomyPipelineError.suggestionAlreadyProcessed(suggestion.status.rawValue)
        }
        
        // Apply the split
        let subcategoryNames = suggestion.proposedSubcategories.map { $0.name }
        tree.splitCategory(path: suggestion.sourceNode.path, into: subcategoryNames)
        
        suggestion.status = .applied
        splitSuggestions[id] = suggestion
        
        NSLog("✅ [MergeSplitGatekeeper] Applied split: \(suggestion.sourceNode.name) → \(subcategoryNames.joined(separator: ", "))")
    }
    
    /// Reject a merge suggestion
    func rejectMerge(id: UUID) throws {
        guard var suggestion = mergeSuggestions[id] else {
            throw TaxonomyPipelineError.suggestionNotFound(id)
        }
        
        suggestion.status = .rejected
        mergeSuggestions[id] = suggestion
        
        NSLog("❌ [MergeSplitGatekeeper] Rejected merge: \(suggestion.sourceNodes.map { $0.name }.joined(separator: ", "))")
    }
    
    /// Reject a split suggestion
    func rejectSplit(id: UUID) throws {
        guard var suggestion = splitSuggestions[id] else {
            throw TaxonomyPipelineError.suggestionNotFound(id)
        }
        
        suggestion.status = .rejected
        splitSuggestions[id] = suggestion
        
        NSLog("❌ [MergeSplitGatekeeper] Rejected split: \(suggestion.sourceNode.name)")
    }
    
    /// Clear all processed suggestions (applied or rejected)
    func clearProcessed() {
        let mergeCount = mergeSuggestions.count
        let splitCount = splitSuggestions.count
        
        mergeSuggestions = mergeSuggestions.filter { $0.value.status == .pending }
        splitSuggestions = splitSuggestions.filter { $0.value.status == .pending }
        
        let cleared = (mergeCount - mergeSuggestions.count) + (splitCount - splitSuggestions.count)
        if cleared > 0 {
            NSLog("🧹 [MergeSplitGatekeeper] Cleared \(cleared) processed suggestions")
        }
    }
}

// MARK: - User Edit Guardrails

/// Protects user-edited nodes from automatic modifications
actor UserEditGuardrails {
    
    /// Check if a node can be automatically modified
    func canAutoModify(_ node: TaxonomyNode) -> Bool {
        !node.isUserEdited && !node.isUserCreated
    }
    
    /// Check if a file assignment can be automatically changed
    func canAutoReassign(fileId: UUID, in tree: TaxonomyTree) -> Bool {
        // Find the node containing this file
        for category in tree.allCategories() {
            if category.assignedFiles.contains(where: { $0.fileId == fileId }) {
                // Don't auto-reassign if the category is user-edited
                return !category.isUserEdited
            }
        }
        return true
    }
    
    /// Mark a node as user-edited (prevents automatic modifications)
    func markAsUserEdited(_ node: TaxonomyNode) {
        node.refinementState = .userEdited
        NSLog("🔒 [Guardrails] Marked node '\(node.name)' as user-edited (protected from auto-modifications)")
    }
    
    /// Check if a merge would affect user-edited nodes
    func validateMerge(sourceNodes: [TaxonomyNode], target: TaxonomyNode) -> GuardrailCheckResult {
        let userEditedSources = sourceNodes.filter { $0.isUserEdited }
        let targetUserEdited = target.isUserEdited
        
        if !userEditedSources.isEmpty || targetUserEdited {
            return GuardrailCheckResult(
                allowed: false,
                requiresApproval: true,
                reason: "Merge involves user-edited nodes",
                affectedNodes: userEditedSources + [target]
            )
        }
        
        return GuardrailCheckResult(allowed: true, requiresApproval: false)
    }
    
    /// Check if a split would affect user-edited nodes
    func validateSplit(node: TaxonomyNode) -> GuardrailCheckResult {
        if node.isUserEdited {
            return GuardrailCheckResult(
                allowed: false,
                requiresApproval: true,
                reason: "Split involves user-edited node",
                affectedNodes: [node]
            )
        }
        
        return GuardrailCheckResult(allowed: true, requiresApproval: false)
    }
}

struct GuardrailCheckResult: Sendable {
    let allowed: Bool
    let requiresApproval: Bool
    let reason: String?
    let affectedNodes: [TaxonomyNode]
    
    init(allowed: Bool, requiresApproval: Bool, reason: String? = nil, affectedNodes: [TaxonomyNode] = []) {
        self.allowed = allowed
        self.requiresApproval = requiresApproval
        self.reason = reason
        self.affectedNodes = affectedNodes
    }
}

// MARK: - Pipeline Errors

enum TaxonomyPipelineError: Error, LocalizedError {
    case depthConstraintViolation(DepthValidationResult)
    case suggestionNotFound(UUID)
    case suggestionAlreadyProcessed(String)
    case userEditedNodeProtected(String)
    case guardrailViolation(String)
    
    var errorDescription: String? {
        switch self {
        case .depthConstraintViolation(let result):
            return "Depth constraint violation: \(result.violations.count) violations found"
        case .suggestionNotFound(let id):
            return "Suggestion not found: \(id)"
        case .suggestionAlreadyProcessed(let status):
            return "Suggestion already processed: \(status)"
        case .userEditedNodeProtected(let nodeName):
            return "Cannot modify user-edited node: \(nodeName)"
        case .guardrailViolation(let reason):
            return "Guardrail violation: \(reason)"
        }
    }
}

