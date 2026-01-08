// MARK: - Taxonomy Pipeline Enhancements Tests
// Tests for depth enforcement, merge/split gating, and guardrails

import Testing
import Foundation
@testable import SortAI

@Suite("Taxonomy Depth Configuration Tests")
struct TaxonomyDepthConfigurationTests {
    
    @Test("Default configuration")
    func testDefaultConfiguration() {
        let config = TaxonomyDepthConfiguration.default
        
        #expect(config.minDepth == 2)
        #expect(config.maxDepth == 5)
        #expect(config.depthEnforcement == .advisory)
        #expect(config.showDepthWarnings == true)
    }
    
    @Test("Strict configuration")
    func testStrictConfiguration() {
        let config = TaxonomyDepthConfiguration.strict
        
        #expect(config.minDepth == 3)
        #expect(config.maxDepth == 7)
        #expect(config.depthEnforcement == .strict)
    }
    
    @Test("Depth validation")
    func testDepthValidation() {
        let config = TaxonomyDepthConfiguration(
            minDepth: 3,
            maxDepth: 7,
            depthEnforcement: .advisory,
            showDepthWarnings: true
        )
        
        #expect(config.isValid(depth: 2) == false)
        #expect(config.isValid(depth: 3) == true)
        #expect(config.isValid(depth: 5) == true)
        #expect(config.isValid(depth: 7) == true)
        #expect(config.isValid(depth: 8) == false)
    }
    
    @Test("Suggested depth adjustment")
    func testSuggestedDepthAdjustment() {
        let config = TaxonomyDepthConfiguration.strict
        
        #expect(config.suggestedDepth(for: 1) == 3)
        #expect(config.suggestedDepth(for: 5) == 5)
        #expect(config.suggestedDepth(for: 10) == 7)
    }
}

@Suite("Depth Enforcer Tests")
struct DepthEnforcerTests {
    
    @Test("Validate tree within limits")
    func testValidateTreeWithinLimits() async {
        let tree = TaxonomyTree(rootName: "Root")
        let child1 = TaxonomyNode(name: "Level1")
        let child2 = TaxonomyNode(name: "Level2")
        tree.root.addChild(child1)
        child1.addChild(child2)
        
        let config = TaxonomyDepthConfiguration(
            minDepth: 2,
            maxDepth: 5,
            depthEnforcement: .advisory,
            showDepthWarnings: true
        )
        let enforcer = TaxonomyDepthEnforcer(configuration: config)
        
        let result = await enforcer.validate(tree)
        #expect(result.isValid == true)
        #expect(result.violations.isEmpty)
    }
    
    @Test("Detect depth violations")
    func testDetectDepthViolations() async {
        let tree = TaxonomyTree(rootName: "Root")
        var current = tree.root
        
        // Create deep hierarchy: Root -> L1 -> L2 -> L3 -> L4 -> L5 -> L6 (depth 6)
        for i in 1...6 {
            let child = TaxonomyNode(name: "Level\(i)")
            current.addChild(child)
            current = child
        }
        
        let config = TaxonomyDepthConfiguration(
            minDepth: 2,
            maxDepth: 4,
            depthEnforcement: .advisory,
            showDepthWarnings: true
        )
        let enforcer = TaxonomyDepthEnforcer(configuration: config)
        
        let result = await enforcer.validate(tree)
        #expect(result.isValid == false)
        #expect(!result.violations.isEmpty)
        #expect(result.currentMaxDepth == 6)
    }
    
    @Test("Advisory enforcement allows violations")
    func testAdvisoryEnforcementAllowsViolations() async throws {
        let tree = TaxonomyTree(rootName: "Root")
        var current = tree.root
        
        // Create deep hierarchy
        for i in 1...6 {
            let child = TaxonomyNode(name: "Level\(i)")
            current.addChild(child)
            current = child
        }
        
        let config = TaxonomyDepthConfiguration(
            minDepth: 2,
            maxDepth: 4,
            depthEnforcement: .advisory,
            showDepthWarnings: true
        )
        let enforcer = TaxonomyDepthEnforcer(configuration: config)
        
        // Should not throw with advisory mode
        try await enforcer.enforce(tree)
        
        // Tree should be unchanged
        #expect(tree.maxDepth == 6)
    }
}

@Suite("Merge Suggestion Tests")
struct MergeSuggestionTests {
    
    @Test("Create merge suggestion")
    func testCreateMergeSuggestion() {
        let source1 = TaxonomyNode(name: "Photos1")
        let source2 = TaxonomyNode(name: "Photos2")
        let target = TaxonomyNode(name: "Photos")
        
        let suggestion = MergeSuggestion(
            sourceNodes: [source1, source2],
            targetNode: target,
            reason: "Similar categories detected",
            confidence: 0.85
        )
        
        #expect(suggestion.sourceNodes.count == 2)
        #expect(suggestion.targetNode.name == "Photos")
        #expect(suggestion.status == .pending)
        #expect(suggestion.confidence == 0.85)
    }
    
    @Test("Merge suggestion status transitions")
    func testMergeSuggestionStatusTransitions() {
        let source = TaxonomyNode(name: "Docs1")
        let target = TaxonomyNode(name: "Documents")
        
        var suggestion = MergeSuggestion(
            sourceNodes: [source],
            targetNode: target,
            reason: "Test",
            confidence: 0.9
        )
        
        #expect(suggestion.status == .pending)
        
        suggestion.status = .approved
        #expect(suggestion.status == .approved)
        
        suggestion.status = .applied
        #expect(suggestion.status == .applied)
    }
}

@Suite("Split Suggestion Tests")
struct SplitSuggestionTests {
    
    @Test("Create split suggestion")
    func testCreateSplitSuggestion() {
        let source = TaxonomyNode(name: "Media")
        let subcats = [
            SplitSuggestion.ProposedSubcategory(
                name: "Photos",
                exemplarFiles: ["IMG_001.jpg", "vacation.png"],
                confidence: 0.9
            ),
            SplitSuggestion.ProposedSubcategory(
                name: "Videos",
                exemplarFiles: ["movie.mp4", "recording.mov"],
                confidence: 0.85
            )
        ]
        
        let suggestion = SplitSuggestion(
            sourceNode: source,
            proposedSubcategories: subcats,
            reason: "Detected multiple media types",
            confidence: 0.88
        )
        
        #expect(suggestion.sourceNode.name == "Media")
        #expect(suggestion.proposedSubcategories.count == 2)
        #expect(suggestion.status == .pending)
    }
    
    @Test("Split suggestion with exemplars")
    func testSplitSuggestionWithExemplars() {
        let source = TaxonomyNode(name: "Documents")
        let subcats = [
            SplitSuggestion.ProposedSubcategory(
                name: "PDFs",
                exemplarFiles: ["report.pdf", "invoice.pdf"],
                confidence: 0.95
            )
        ]
        
        let suggestion = SplitSuggestion(
            sourceNode: source,
            proposedSubcategories: subcats,
            reason: "Single type detected",
            confidence: 0.85
        )
        
        let firstSubcat = suggestion.proposedSubcategories[0]
        #expect(firstSubcat.name == "PDFs")
        #expect(firstSubcat.exemplarFiles.count == 2)
        #expect(firstSubcat.exemplarFiles.contains("report.pdf"))
    }
}

@Suite("Merge Split Gatekeeper Tests")
struct MergeSplitGatekeeperTests {
    
    @Test("Add and retrieve merge suggestions")
    func testAddAndRetrieveMergeSuggestions() async {
        let gatekeeper = MergeSplitGatekeeper()
        
        let source = TaxonomyNode(name: "Photos1")
        let target = TaxonomyNode(name: "Photos")
        let suggestion = MergeSuggestion(
            sourceNodes: [source],
            targetNode: target,
            reason: "Test",
            confidence: 0.9
        )
        
        await gatekeeper.suggestMerge(suggestion)
        
        let pending = await gatekeeper.getPendingMerges()
        #expect(pending.count == 1)
        #expect(pending[0].id == suggestion.id)
    }
    
    @Test("Add and retrieve split suggestions")
    func testAddAndRetrieveSplitSuggestions() async {
        let gatekeeper = MergeSplitGatekeeper()
        
        let source = TaxonomyNode(name: "Media")
        let subcats = [
            SplitSuggestion.ProposedSubcategory(
                name: "Photos",
                exemplarFiles: ["img.jpg"],
                confidence: 0.9
            )
        ]
        let suggestion = SplitSuggestion(
            sourceNode: source,
            proposedSubcategories: subcats,
            reason: "Test",
            confidence: 0.85
        )
        
        await gatekeeper.suggestSplit(suggestion)
        
        let pending = await gatekeeper.getPendingSplits()
        #expect(pending.count == 1)
        #expect(pending[0].id == suggestion.id)
    }
    
    @Test("Approve merge")
    func testApproveMerge() async throws {
        let gatekeeper = MergeSplitGatekeeper()
        let tree = TaxonomyTree(rootName: "Root")
        
        let source = TaxonomyNode(name: "Photos1")
        let target = TaxonomyNode(name: "Photos")
        tree.root.addChild(source)
        tree.root.addChild(target)
        
        // Add files to source
        let assignment = FileAssignment(
            url: URL(fileURLWithPath: "/test/file.jpg"),
            filename: "file.jpg",
            confidence: 0.9
        )
        source.assign(file: assignment)
        
        let suggestion = MergeSuggestion(
            sourceNodes: [source],
            targetNode: target,
            reason: "Test merge",
            confidence: 0.9
        )
        
        await gatekeeper.suggestMerge(suggestion)
        try await gatekeeper.approveMerge(id: suggestion.id, tree: tree)
        
        // Verify files were moved
        #expect(target.assignedFiles.count == 1)
    }
    
    @Test("Reject merge")
    func testRejectMerge() async throws {
        let gatekeeper = MergeSplitGatekeeper()
        
        let source = TaxonomyNode(name: "Photos1")
        let target = TaxonomyNode(name: "Photos")
        let suggestion = MergeSuggestion(
            sourceNodes: [source],
            targetNode: target,
            reason: "Test",
            confidence: 0.9
        )
        
        await gatekeeper.suggestMerge(suggestion)
        try await gatekeeper.rejectMerge(id: suggestion.id)
        
        let pending = await gatekeeper.getPendingMerges()
        #expect(pending.isEmpty)
    }
    
    @Test("Clear processed suggestions")
    func testClearProcessedSuggestions() async throws {
        let gatekeeper = MergeSplitGatekeeper()
        
        let source1 = TaxonomyNode(name: "Photos1")
        let source2 = TaxonomyNode(name: "Photos2")
        let target = TaxonomyNode(name: "Photos")
        
        let suggestion1 = MergeSuggestion(
            sourceNodes: [source1],
            targetNode: target,
            reason: "Test1",
            confidence: 0.9
        )
        let suggestion2 = MergeSuggestion(
            sourceNodes: [source2],
            targetNode: target,
            reason: "Test2",
            confidence: 0.8
        )
        
        await gatekeeper.suggestMerge(suggestion1)
        await gatekeeper.suggestMerge(suggestion2)
        
        try await gatekeeper.rejectMerge(id: suggestion1.id)
        
        await gatekeeper.clearProcessed()
        
        let pending = await gatekeeper.getPendingMerges()
        #expect(pending.count == 1)
        #expect(pending[0].id == suggestion2.id)
    }
}

@Suite("User Edit Guardrails Tests")
struct UserEditGuardrailsTests {
    
    @Test("Can auto-modify non-user-edited node")
    func testCanAutoModifyNonUserEditedNode() async {
        let guardrails = UserEditGuardrails()
        let node = TaxonomyNode(name: "Auto-generated", isUserCreated: false)
        
        let canModify = await guardrails.canAutoModify(node)
        #expect(canModify == true)
    }
    
    @Test("Cannot auto-modify user-edited node")
    func testCannotAutoModifyUserEditedNode() async {
        let guardrails = UserEditGuardrails()
        let node = TaxonomyNode(name: "User-edited", isUserCreated: false)
        node.refinementState = .userEdited
        
        let canModify = await guardrails.canAutoModify(node)
        #expect(canModify == false)
    }
    
    @Test("Cannot auto-modify user-created node")
    func testCannotAutoModifyUserCreatedNode() async {
        let guardrails = UserEditGuardrails()
        let node = TaxonomyNode(name: "User-created", isUserCreated: true)
        
        let canModify = await guardrails.canAutoModify(node)
        #expect(canModify == false)
    }
    
    @Test("Mark node as user-edited")
    func testMarkNodeAsUserEdited() async {
        let guardrails = UserEditGuardrails()
        let node = TaxonomyNode(name: "Test")
        
        #expect(node.refinementState != .userEdited)
        
        await guardrails.markAsUserEdited(node)
        
        #expect(node.refinementState == .userEdited)
        #expect(node.isUserEdited == true)
    }
    
    @Test("Validate merge with user-edited nodes")
    func testValidateMergeWithUserEditedNodes() async {
        let guardrails = UserEditGuardrails()
        
        let source = TaxonomyNode(name: "Source")
        source.refinementState = .userEdited
        
        let target = TaxonomyNode(name: "Target")
        
        let result = await guardrails.validateMerge(sourceNodes: [source], target: target)
        
        #expect(result.allowed == false)
        #expect(result.requiresApproval == true)
        #expect(result.reason == "Merge involves user-edited nodes")
    }
    
    @Test("Validate merge without user-edited nodes")
    func testValidateMergeWithoutUserEditedNodes() async {
        let guardrails = UserEditGuardrails()
        
        let source = TaxonomyNode(name: "Source")
        let target = TaxonomyNode(name: "Target")
        
        let result = await guardrails.validateMerge(sourceNodes: [source], target: target)
        
        #expect(result.allowed == true)
        #expect(result.requiresApproval == false)
    }
    
    @Test("Validate split with user-edited node")
    func testValidateSplitWithUserEditedNode() async {
        let guardrails = UserEditGuardrails()
        
        let node = TaxonomyNode(name: "UserNode")
        node.refinementState = .userEdited
        
        let result = await guardrails.validateSplit(node: node)
        
        #expect(result.allowed == false)
        #expect(result.requiresApproval == true)
    }
    
    @Test("Validate split without user-edited node")
    func testValidateSplitWithoutUserEditedNode() async {
        let guardrails = UserEditGuardrails()
        
        let node = TaxonomyNode(name: "AutoNode")
        
        let result = await guardrails.validateSplit(node: node)
        
        #expect(result.allowed == true)
        #expect(result.requiresApproval == false)
    }
}

@Suite("Pipeline Error Tests")
struct PipelineErrorTests {
    
    @Test("Depth constraint violation error")
    func testDepthConstraintViolationError() {
        let validationResult = DepthValidationResult(
            isValid: false,
            violations: [
                DepthViolation(
                    type: .exceedsMaximum,
                    currentDepth: 8,
                    allowedDepth: 5,
                    affectedNodes: []
                )
            ],
            warnings: [],
            currentMaxDepth: 8,
            allowedMaxDepth: 5
        )
        
        let error = TaxonomyPipelineError.depthConstraintViolation(validationResult)
        let description = error.errorDescription
        
        #expect(description?.contains("Depth constraint violation") == true)
        #expect(description?.contains("1 violations") == true)
    }
    
    @Test("Suggestion not found error")
    func testSuggestionNotFoundError() {
        let id = UUID()
        let error = TaxonomyPipelineError.suggestionNotFound(id)
        let description = error.errorDescription
        
        #expect(description?.contains("Suggestion not found") == true)
    }
    
    @Test("User edited node protected error")
    func testUserEditedNodeProtectedError() {
        let error = TaxonomyPipelineError.userEditedNodeProtected("MyCategory")
        let description = error.errorDescription
        
        #expect(description?.contains("Cannot modify user-edited node") == true)
        #expect(description?.contains("MyCategory") == true)
    }
}

