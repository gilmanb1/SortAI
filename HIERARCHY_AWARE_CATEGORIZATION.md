# Hierarchy-Aware Categorization Implementation Plan

**Feature**: Folder hierarchy respect with optional re-analysis
**Status**: Planning
**Branch**: `feature/hierarchy-aware-categorization`

---

## Requirements Summary

### Core Behavior
1. **Folders are units**: Sub-folders move as complete units - internal files stay together
2. **Loose files are individuals**: Files not in sub-folders get analyzed and moved individually
3. **Folder categorization**: System analyzes folder contents to determine the *folder's* category
4. **Example**: `/Downloads/Resumes/` → `Work/Job Search/Resumes/` (folder moves, internal structure preserved)

### User Options
- **Default (Conservative)**: Folders move as units, preserve internal structure
- **Option (Aggressive)**: User can opt to re-analyze folder contents and reorganize internally
- **Per-folder control**: User can select specific folders to "flatten" for re-analysis

### Confidence Handling
- Show conflicts only when AI confidence for folder categorization exceeds threshold
- Low confidence folders get queued for user review

---

## Current Architecture Analysis

### Components to Modify

| Component | Current Behavior | Required Changes |
|-----------|------------------|------------------|
| `FilenameScanner` | Scans all files recursively as individuals | Distinguish "folder units" vs "loose files" |
| `TaxonomyScannedFile` | Represents single file | Add `ScannedFolder` type for folder units |
| `TaxonomyInferenceEngine` | Categorizes by individual filenames | Add folder-level categorization |
| `OrganizationEngine` | Plans moves for individual files | Plan moves for folders as units |
| `SafeFileOrganizer` | Moves individual files | Move folders as atomic units |
| `OrganizationConfiguration` | No hierarchy settings | Add `respectHierarchy` toggle |
| `WizardView` | Shows file list | Show folders vs loose files, flatten option |
| `ConflictResolutionView` | File conflicts | Folder-level conflicts |

### New Components Needed

| Component | Purpose |
|-----------|---------|
| `ScannedFolder` | Data model for folder as a unit |
| `FolderCategorizer` | Analyze folder contents to determine category |
| `HierarchyConfiguration` | Settings for hierarchy behavior |
| `OrganizationPreviewView` | New UI showing proposed moves with edit capability |

---

## Data Model Changes

### New: `ScannedFolder`

```swift
struct ScannedFolder: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let folderName: String
    let relativePath: String          // Path relative to scan root
    let depth: Int                     // How deep in folder tree
    let containedFiles: [TaxonomyScannedFile]
    let totalSize: Int64
    let fileCount: Int
    let modifiedAt: Date?
    
    // Computed properties
    var dominantFileTypes: [UTType] { ... }
    var suggestedContext: String { ... }  // "Contains 5 PDF files, 2 DOCX..."
}
```

### New: `ScanUnit` (Unified Type)

```swift
enum ScanUnit: Identifiable, Sendable {
    case folder(ScannedFolder)        // Folder moves as unit
    case file(TaxonomyScannedFile)    // Individual file moves separately
    
    var id: UUID { ... }
    var displayName: String { ... }
    var url: URL { ... }
}
```

### Modified: `FileScanResult`

```swift
struct FileScanResult: Sendable {
    let sourceFolder: URL
    let folders: [ScannedFolder]       // Sub-folders to move as units
    let looseFiles: [TaxonomyScannedFile]  // Files not in sub-folders
    let totalItems: Int
    let totalSize: Int64
}
```

---

## Scanner Changes

### `FilenameScanner` Modifications

```swift
actor FilenameScanner {
    
    struct Configuration: Sendable {
        // Existing...
        
        // NEW: Hierarchy settings
        let respectHierarchy: Bool        // Default: true
        let minDepthForFolder: Int        // Treat as folder unit if depth >= this
        let minFilesForFolder: Int        // Only if folder has >= N files
    }
    
    // NEW: Scan with hierarchy awareness
    func scanWithHierarchy(folder: URL) async throws -> FileScanResult {
        // 1. Get immediate children of folder
        // 2. For each sub-folder: create ScannedFolder with its contents
        // 3. For loose files (not in sub-folders): create TaxonomyScannedFile
        // 4. Return unified result
    }
}
```

### Scanning Algorithm

```
Given: /Downloads/
├── file1.txt           → LOOSE FILE (analyze individually)
├── file2.pdf           → LOOSE FILE (analyze individually)
├── Resumes/            → FOLDER UNIT
│   ├── resume_v1.pdf
│   └── resume_v2.docx
└── Vacation_2024/      → FOLDER UNIT
    ├── photo1.jpg
    └── photo2.jpg

Result:
- looseFiles: [file1.txt, file2.pdf]
- folders: [Resumes/, Vacation_2024/]
```

---

## Taxonomy Changes

### `FolderCategorizer` (New)

```swift
actor FolderCategorizer {
    
    /// Categorize a folder by analyzing its contents
    func categorize(
        folder: ScannedFolder,
        within taxonomy: TaxonomyTree,
        options: LLMOptions
    ) async throws -> FolderCategoryAssignment {
        
        // Build context from folder contents
        let context = buildFolderContext(folder)
        
        // Use LLM to determine folder's category
        let prompt = buildFolderCategorizationPrompt(
            folderName: folder.folderName,
            fileList: folder.containedFiles.map(\.filename),
            context: context
        )
        
        // Get category assignment
        let response = try await provider.completeJSON(prompt: prompt, options: options)
        return parseFolderAssignment(response)
    }
    
    private func buildFolderContext(_ folder: ScannedFolder) -> String {
        // Analyze file types, names, patterns within folder
        // Return context like: "Folder 'Resumes' contains 5 PDF files with names 
        // suggesting job application documents: resume_v1.pdf, cover_letter.docx..."
    }
}
```

### LLM Prompt for Folder Categorization

```
You are a file organization expert. Analyze this FOLDER and determine what category it belongs to.

FOLDER NAME: Resumes
CONTAINED FILES:
1. resume_v1.pdf
2. resume_v2.docx  
3. cover_letter.docx
4. references.txt

Based on the folder name and contents, determine:
1. What category this folder should be organized into
2. Your confidence (0.0-1.0)
3. Brief rationale

The folder will be MOVED AS A UNIT - files inside will stay together.

Return JSON:
{
    "category": "Work / Job Search / Application Materials",
    "confidence": 0.92,
    "rationale": "Folder contains resume and cover letter documents typical of job applications"
}
```

---

## Organization Changes

### `OrganizationEngine` Modifications

```swift
actor OrganizationEngine {
    
    /// Plan organization respecting hierarchy
    func planOrganization(
        scanResult: FileScanResult,
        folderAssignments: [UUID: FolderCategoryAssignment],
        fileAssignments: [UUID: CategoryAssignment],
        tree: TaxonomyTree,
        outputFolder: URL,
        config: OrganizationConfiguration
    ) -> HierarchyAwareOrganizationPlan {
        
        var folderOps: [FolderOrganizationOperation] = []
        var fileOps: [OrganizationOperation] = []
        
        // Plan folder moves
        for folder in scanResult.folders {
            if let assignment = folderAssignments[folder.id] {
                let destPath = resolveFolderDestination(assignment, tree, outputFolder)
                folderOps.append(FolderOrganizationOperation(
                    sourceFolder: folder,
                    destinationFolder: destPath,
                    preserveInternalStructure: true
                ))
            }
        }
        
        // Plan loose file moves
        for file in scanResult.looseFiles {
            if let assignment = fileAssignments[file.id] {
                let destPath = resolveFileDestination(assignment, tree, outputFolder)
                fileOps.append(OrganizationOperation(
                    sourceFile: file,
                    destinationPath: destPath
                ))
            }
        }
        
        return HierarchyAwareOrganizationPlan(
            folderOperations: folderOps,
            fileOperations: fileOps
        )
    }
}
```

### `SafeFileOrganizer` - Folder Move Support

```swift
actor SafeFileOrganizer {
    
    /// Move a folder as a unit
    func moveFolder(
        from source: ScannedFolder,
        to destination: URL,
        mode: OrganizationMode
    ) async throws -> FolderMoveResult {
        
        // Create destination parent
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), 
                                        withIntermediateDirectories: true)
        
        switch mode {
        case .move:
            try fileManager.moveItem(at: source.url, to: destination)
        case .copy:
            try fileManager.copyItem(at: source.url, to: destination)
        case .symlink:
            try fileManager.createSymbolicLink(at: destination, withDestinationURL: source.url)
        }
        
        return FolderMoveResult(
            folder: source,
            destination: destination,
            success: true
        )
    }
}
```

---

## Configuration Changes

### `OrganizationConfiguration` Additions

```swift
struct OrganizationConfiguration: Codable, Sendable, Equatable {
    // Existing...
    
    // NEW: Hierarchy settings
    var respectHierarchy: Bool = true
    var flattenThreshold: Double = 0.5  // Confidence below this suggests flattening
    var allowUserFlatten: Bool = true   // Let user flatten individual folders
}
```

### `SortAIDefaultsKey` Additions

```swift
enum SortAIDefaultsKey {
    // Existing...
    
    // NEW
    static let respectHierarchy = "respectHierarchy"
    static let flattenThreshold = "flattenThreshold"
    static let allowUserFlatten = "allowUserFlatten"
}
```

---

## UI Changes

### New: `OrganizationPreviewView`

Shows proposed moves with edit capability:

```swift
struct OrganizationPreviewView: View {
    @Binding var plan: HierarchyAwareOrganizationPlan
    @State private var selectedItems: Set<UUID> = []
    
    var body: some View {
        VStack {
            // Header with stats
            PreviewHeader(
                folderCount: plan.folderOperations.count,
                fileCount: plan.fileOperations.count
            )
            
            // Folder section
            Section("Folders (Moving as Units)") {
                ForEach(plan.folderOperations) { op in
                    FolderPreviewRow(
                        operation: op,
                        onFlatten: { flattenFolder(op) },
                        onChangeCategory: { showCategoryPicker(for: op) }
                    )
                }
            }
            
            // Loose files section
            Section("Individual Files") {
                ForEach(plan.fileOperations) { op in
                    FilePreviewRow(
                        operation: op,
                        onChangeCategory: { showCategoryPicker(for: op) }
                    )
                }
            }
        }
    }
    
    private func flattenFolder(_ op: FolderOrganizationOperation) {
        // Convert folder to individual file operations
        // Remove from folderOperations
        // Add files to fileOperations
    }
}
```

### `FolderPreviewRow`

```swift
struct FolderPreviewRow: View {
    let operation: FolderOrganizationOperation
    let onFlatten: () -> Void
    let onChangeCategory: () -> Void
    
    var body: some View {
        HStack {
            // Folder icon
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading) {
                Text(operation.sourceFolder.folderName)
                    .font(.headline)
                
                Text("\(operation.sourceFolder.fileCount) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Destination
            VStack(alignment: .trailing) {
                Text(operation.destinationCategory)
                    .font(.subheadline)
                
                Text("Confidence: \(operation.confidence, specifier: "%.0f%%")")
                    .font(.caption)
                    .foregroundStyle(confidenceColor)
            }
            
            // Actions
            Menu {
                Button("Change Category", action: onChangeCategory)
                Button("Flatten (Re-analyze Files)", action: onFlatten)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}
```

---

## Implementation Phases

### Phase 1: Data Models & Scanner (2-3 Ralph iterations)

**Files to modify:**
- `Sources/SortAI/Core/Taxonomy/FilenameScanner.swift`
- `Sources/SortAI/Core/Scanner/FolderScanner.swift`

**Completion criteria:**
- [ ] `ScannedFolder` struct defined
- [ ] `ScanUnit` enum defined
- [ ] `FileScanResult` updated with folders + looseFiles
- [ ] `FilenameScanner.scanWithHierarchy()` implemented
- [ ] Unit tests for hierarchy scanning pass

**Ralph prompt:**
```
Implement hierarchy-aware scanning in FilenameScanner:
1. Add ScannedFolder struct with: id, url, folderName, containedFiles, totalSize
2. Add ScanUnit enum with folder/file cases
3. Add scanWithHierarchy() that separates sub-folders from loose files
4. Update tests in TaxonomyTests.swift

Output <promise>PHASE 1 COMPLETE</promise> when tests pass.
```

### Phase 2: Folder Categorization (2-3 Ralph iterations)

**Files to create/modify:**
- `Sources/SortAI/Core/Taxonomy/FolderCategorizer.swift` (NEW)
- `Sources/SortAI/Core/Taxonomy/TaxonomyInferenceEngine.swift`

**Completion criteria:**
- [ ] `FolderCategorizer` actor created
- [ ] LLM prompt for folder categorization defined
- [ ] `FolderCategoryAssignment` struct defined
- [ ] Integration with existing taxonomy system
- [ ] Tests for folder categorization pass

### Phase 3: Organization Engine Updates (2-3 Ralph iterations)

**Files to modify:**
- `Sources/SortAI/Core/Organizer/OrganizationEngine.swift`
- `Sources/SortAI/Core/Organizer/SafeFileOrganizer.swift`

**Completion criteria:**
- [ ] `HierarchyAwareOrganizationPlan` struct defined
- [ ] `FolderOrganizationOperation` struct defined
- [ ] `OrganizationEngine.planOrganization()` supports folders
- [ ] `SafeFileOrganizer.moveFolder()` implemented
- [ ] Tests for folder moves pass

### Phase 4: Configuration & Settings (1 Ralph iteration)

**Files to modify:**
- `Sources/SortAI/Core/Configuration/AppConfiguration.swift`
- `Sources/SortAI/App/SettingsView.swift`

**Completion criteria:**
- [ ] `respectHierarchy` setting added to OrganizationConfiguration
- [ ] Settings UI for hierarchy options
- [ ] UserDefaults keys registered
- [ ] Configuration tests pass

### Phase 5: UI - Preview & Flatten (3-4 Ralph iterations)

**Files to create/modify:**
- `Sources/SortAI/App/OrganizationPreviewView.swift` (NEW)
- `Sources/SortAI/App/WizardView.swift`

**Completion criteria:**
- [ ] `OrganizationPreviewView` showing folders vs files
- [ ] Flatten button per folder
- [ ] Category change picker
- [ ] Integration with WizardView
- [ ] UI tests pass

### Phase 6: Integration & Testing (2 Ralph iterations)

**Files to modify:**
- `Sources/SortAI/Core/Pipeline/SortAIPipeline.swift`
- `Tests/SortAITests/FunctionalOrganizationTests.swift`

**Completion criteria:**
- [ ] End-to-end workflow works
- [ ] Functional tests with real folder structures
- [ ] Edge cases handled (empty folders, deeply nested, etc.)

---

## Test Plan

### Unit Tests

| Test | Description |
|------|-------------|
| `testScanWithHierarchy_SeparatesFoldersFromFiles` | Verifies scanning correctly identifies folder units vs loose files |
| `testFolderCategorization_UsesContents` | Folder category determined by analyzing contents |
| `testOrganizationPlan_FoldersAsUnits` | Plan correctly groups folder operations |
| `testFolderMove_PreservesStructure` | Moving folder keeps internal files intact |
| `testFlatten_ConvertsToFileOps` | Flatten action converts folder to individual file operations |

### Integration Tests

| Test | Description |
|------|-------------|
| `testEndToEnd_HierarchyRespected` | Complete workflow respects folder hierarchy |
| `testEndToEnd_FlattenOption` | User can flatten and files move individually |
| `testEndToEnd_MixedContent` | Handles mix of folders and loose files |

---

## Rollout Checklist

- [ ] Feature branch created: `feature/hierarchy-aware-categorization`
- [ ] Phase 1-6 completed with tests
- [ ] All existing tests still pass
- [ ] UI tested manually
- [ ] Documentation updated (README, Claude.md)
- [ ] PR created with comprehensive description
- [ ] Claude review approved
- [ ] Merged to main

---

*Created: 2026-01-13*
*Following GitWorkflow.md process*
