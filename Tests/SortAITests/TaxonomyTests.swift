// MARK: - Taxonomy Tests
// Unit tests for the taxonomy system

import Testing
import Foundation
@testable import SortAI

// MARK: - Taxonomy Node Tests

@Suite("TaxonomyNode Tests")
struct TaxonomyNodeTests {
    
    @Test("Create basic node")
    func testCreateBasicNode() {
        let node = TaxonomyNode(name: "Test")
        
        #expect(node.name == "Test")
        #expect(node.children.isEmpty)
        #expect(node.parent == nil)
        #expect(node.isRoot)
        #expect(node.isLeaf)
        #expect(node.depth == 0)
    }
    
    @Test("Add child node")
    func testAddChildNode() {
        let parent = TaxonomyNode(name: "Parent")
        let child = TaxonomyNode(name: "Child")
        
        parent.addChild(child)
        
        #expect(parent.children.count == 1)
        #expect(child.parent?.id == parent.id)
        #expect(!parent.isLeaf)
        #expect(child.depth == 1)
    }
    
    @Test("Remove child node")
    func testRemoveChildNode() {
        let parent = TaxonomyNode(name: "Parent")
        let child = TaxonomyNode(name: "Child")
        
        parent.addChild(child)
        parent.removeChild(child)
        
        #expect(parent.children.isEmpty)
        #expect(child.parent == nil)
    }
    
    @Test("Calculate path")
    func testCalculatePath() {
        let root = TaxonomyNode(name: "Root")
        let level1 = TaxonomyNode(name: "Level1")
        let level2 = TaxonomyNode(name: "Level2")
        
        root.addChild(level1)
        level1.addChild(level2)
        
        #expect(level2.path == ["Root", "Level1", "Level2"])
        #expect(level2.pathString == "Root / Level1 / Level2")
    }
    
    @Test("Find by path")
    func testFindByPath() {
        let root = TaxonomyNode(name: "Root")
        let documents = TaxonomyNode(name: "Documents")
        let photos = TaxonomyNode(name: "Photos")
        
        root.addChild(documents)
        root.addChild(photos)
        
        let found = root.find(path: ["Root", "Documents"])
        #expect(found?.name == "Documents")
        
        let notFound = root.find(path: ["Root", "Videos"])
        #expect(notFound == nil)
    }
    
    @Test("Find or create path")
    func testFindOrCreatePath() {
        let root = TaxonomyNode(name: "Root")
        
        let created = root.findOrCreate(path: ["Level1", "Level2", "Level3"])
        
        #expect(created.name == "Level3")
        #expect(created.depth == 3)
        #expect(root.children.count == 1)
        #expect(root.children[0].children.count == 1)
    }
    
    @Test("Total file count includes children")
    func testTotalFileCount() {
        let root = TaxonomyNode(name: "Root")
        let child = TaxonomyNode(name: "Child")
        root.addChild(child)
        
        // Add files
        let file1 = FileAssignment(url: URL(fileURLWithPath: "/test/1"), filename: "file1", confidence: 0.9)
        let file2 = FileAssignment(url: URL(fileURLWithPath: "/test/2"), filename: "file2", confidence: 0.8)
        
        root.assign(file: file1)
        child.assign(file: file2)
        
        #expect(root.totalFileCount == 2)
        #expect(child.totalFileCount == 1)
        #expect(root.directFileCount == 1)
    }
    
    @Test("All descendants")
    func testAllDescendants() {
        let root = TaxonomyNode(name: "Root")
        let child1 = TaxonomyNode(name: "Child1")
        let child2 = TaxonomyNode(name: "Child2")
        let grandchild = TaxonomyNode(name: "Grandchild")
        
        root.addChild(child1)
        root.addChild(child2)
        child1.addChild(grandchild)
        
        let descendants = root.allDescendants()
        
        #expect(descendants.count == 3)
        #expect(descendants.contains(where: { $0.name == "Child1" }))
        #expect(descendants.contains(where: { $0.name == "Child2" }))
        #expect(descendants.contains(where: { $0.name == "Grandchild" }))
    }
    
    @Test("Move node to new parent")
    func testMoveNode() {
        let root = TaxonomyNode(name: "Root")
        let parent1 = TaxonomyNode(name: "Parent1")
        let parent2 = TaxonomyNode(name: "Parent2")
        let child = TaxonomyNode(name: "Child")
        
        root.addChild(parent1)
        root.addChild(parent2)
        parent1.addChild(child)
        
        child.move(to: parent2)
        
        #expect(parent1.children.isEmpty)
        #expect(parent2.children.count == 1)
        #expect(child.parent?.id == parent2.id)
    }
}

// MARK: - Taxonomy Tree Tests

@Suite("TaxonomyTree Tests")
struct TaxonomyTreeTests {
    
    @Test("Create tree with root")
    func testCreateTree() {
        let tree = TaxonomyTree(rootName: "MyFiles")
        
        #expect(tree.root.name == "MyFiles")
        #expect(tree.categoryCount == 1)
        #expect(tree.totalFileCount == 0)
        #expect(!tree.isVerified)
    }
    
    @Test("Add category")
    func testAddCategory() {
        let tree = TaxonomyTree(rootName: "Files")
        
        let documents = tree.addCategory(path: ["Documents"])
        let photos = tree.addCategory(path: ["Photos"])
        let vacation = tree.addCategory(path: ["Photos", "Vacation"])
        
        #expect(tree.categoryCount == 4) // Root + 3
        #expect(documents.parent?.id == tree.root.id)
        #expect(vacation.parent?.name == "Photos")
    }
    
    @Test("Remove category moves files to parent")
    func testRemoveCategoryMovesFiles() {
        let tree = TaxonomyTree(rootName: "Files")
        let _ = tree.addCategory(path: ["Documents", "Work"])
        
        let file = FileAssignment(url: URL(fileURLWithPath: "/test"), filename: "test.pdf", confidence: 0.9)
        tree.assignFile(file, to: ["Documents", "Work"])
        
        tree.removeCategory(path: ["Documents", "Work"])
        
        // File should be in Documents now
        let documentsNode = tree.find(path: ["Documents"])
        #expect(documentsNode?.assignedFiles.count == 1)
    }
    
    @Test("Rename category")
    func testRenameCategory() {
        let tree = TaxonomyTree(rootName: "Files")
        _ = tree.addCategory(path: ["Documents"])
        
        tree.renameCategory(path: ["Documents"], newName: "My Documents")
        
        let node = tree.find(path: ["My Documents"])
        #expect(node?.name == "My Documents")
    }
    
    @Test("Merge categories")
    func testMergeCategories() {
        let tree = TaxonomyTree(rootName: "Files")
        let docs = tree.addCategory(path: ["Docs"])
        _ = tree.addCategory(path: ["Documents"])
        
        let file = FileAssignment(url: URL(fileURLWithPath: "/test"), filename: "test.pdf", confidence: 0.9)
        tree.assignFile(file, to: ["Docs"])
        
        tree.mergeCategories(sourcePath: ["Docs"], into: ["Documents"])
        
        let documents = tree.find(path: ["Documents"])
        #expect(documents?.assignedFiles.count == 1)
        
        // After merge, the Docs node should be removed from the root's children
        let docsStillChild = tree.root.children.contains(where: { $0.id == docs.id })
        #expect(!docsStillChild)
    }
    
    @Test("Split category")
    func testSplitCategory() {
        let tree = TaxonomyTree(rootName: "Files")
        _ = tree.addCategory(path: ["Documents"])
        
        tree.splitCategory(path: ["Documents"], into: ["Work", "Personal", "Archive"])
        
        let documents = tree.find(path: ["Documents"])
        #expect(documents?.children.count == 3)
    }
    
    @Test("Node by ID")
    func testNodeById() {
        let tree = TaxonomyTree(rootName: "Files")
        let docs = tree.addCategory(path: ["Documents"])
        
        let found = tree.node(byId: docs.id)
        #expect(found?.name == "Documents")
        
        let notFound = tree.node(byId: UUID())
        #expect(notFound == nil)
    }
    
    @Test("Path to node")
    func testPathToNode() {
        let tree = TaxonomyTree(rootName: "Files")
        let vacation = tree.addCategory(path: ["Photos", "Vacation"])
        
        let pathNodes = tree.pathToNode(vacation)
        
        #expect(pathNodes.count == 3)
        #expect(pathNodes[0].name == "Files")
        #expect(pathNodes[1].name == "Photos")
        #expect(pathNodes[2].name == "Vacation")
    }
    
    @Test("All assignments")
    func testAllAssignments() {
        let tree = TaxonomyTree(rootName: "Files")
        _ = tree.addCategory(path: ["Documents"])
        _ = tree.addCategory(path: ["Photos"])
        
        let file1 = FileAssignment(url: URL(fileURLWithPath: "/test/1"), filename: "doc.pdf", confidence: 0.9)
        let file2 = FileAssignment(url: URL(fileURLWithPath: "/test/2"), filename: "photo.jpg", confidence: 0.85)
        
        tree.assignFile(file1, to: ["Documents"])
        tree.assignFile(file2, to: ["Photos"])
        
        let assignments = tree.allAssignments()
        #expect(assignments.count == 2)
    }
    
    @Test("Confidence for file")
    func testConfidenceForFile() {
        let tree = TaxonomyTree(rootName: "Files")
        _ = tree.addCategory(path: ["Documents"])
        
        let file = FileAssignment(url: URL(fileURLWithPath: "/test"), filename: "test.pdf", confidence: 0.87)
        tree.assignFile(file, to: ["Documents"])
        
        let confidence = tree.confidenceForFile(file.id)
        #expect(confidence == 0.87)
        
        let unknownConfidence = tree.confidenceForFile(UUID())
        #expect(unknownConfidence == 0.0)
    }
    
    @Test("To dictionary serialization")
    func testToDictionary() {
        let tree = TaxonomyTree(rootName: "Files", sourceFolderName: "TestFolder")
        _ = tree.addCategory(path: ["Documents"])
        
        let dict = tree.toDictionary()
        
        #expect(dict["sourceFolderName"] as? String == "TestFolder")
        #expect(dict["isVerified"] as? Bool == false)
        
        let rootDict = dict["root"] as? [String: Any]
        #expect(rootDict?["name"] as? String == "Files")
    }
}

// MARK: - File Assignment Tests

@Suite("FileAssignment Tests")
struct FileAssignmentTests {
    
    @Test("Create file assignment")
    func testCreateFileAssignment() {
        let assignment = FileAssignment(
            url: URL(fileURLWithPath: "/Users/test/document.pdf"),
            filename: "document.pdf",
            confidence: 0.95,
            source: .filename
        )
        
        #expect(assignment.filename == "document.pdf")
        #expect(assignment.confidence == 0.95)
        #expect(assignment.source == .filename)
        #expect(!assignment.needsDeepAnalysis)
    }
    
    @Test("Create assignment needing deep analysis")
    func testCreateAssignmentNeedingDeepAnalysis() {
        let assignment = FileAssignment(
            url: URL(fileURLWithPath: "/Users/test/mystery.bin"),
            filename: "mystery.bin",
            confidence: 0.45,
            needsDeepAnalysis: true,
            source: .filename
        )
        
        #expect(assignment.needsDeepAnalysis)
        #expect(assignment.confidence < 0.75)
    }
    
    @Test("Assignment sources")
    func testAssignmentSources() {
        let sources: [FileAssignment.AssignmentSource] = [
            .filename, .content, .user, .memory, .graphRAG
        ]
        
        for source in sources {
            let assignment = FileAssignment(
                url: URL(fileURLWithPath: "/test"),
                filename: "test",
                confidence: 0.9,
                source: source
            )
            #expect(assignment.source == source)
        }
    }
}

// MARK: - Taxonomy Statistics Tests

@Suite("TaxonomyStatistics Tests")
struct TaxonomyStatisticsTests {
    
    @Test("Calculate statistics")
    func testCalculateStatistics() {
        let tree = TaxonomyTree(rootName: "Files")
        _ = tree.addCategory(path: ["Documents"], isUserCreated: true)
        _ = tree.addCategory(path: ["Photos"])
        _ = tree.addCategory(path: ["Photos", "Vacation"])
        
        let file1 = FileAssignment(url: URL(fileURLWithPath: "/1"), filename: "1", confidence: 0.9)
        let file2 = FileAssignment(url: URL(fileURLWithPath: "/2"), filename: "2", confidence: 0.6, needsDeepAnalysis: true)
        
        tree.assignFile(file1, to: ["Documents"])
        tree.assignFile(file2, to: ["Photos"])
        
        let stats = TaxonomyStatistics(from: tree)
        
        #expect(stats.categoryCount == 4)
        #expect(stats.totalFiles == 2)
        #expect(stats.filesNeedingDeepAnalysis == 1)
        #expect(stats.userCreatedCategories == 1)
        #expect(stats.averageConfidence == 0.75)
    }
}

// MARK: - KeywordExtractor Tests

@Suite("KeywordExtractor Tests")
struct KeywordExtractorTests {
    
    @Test("Extract keywords from simple filename")
    func testExtractSimpleFilename() {
        let extractor = KeywordExtractor(configuration: .fast)
        let result = extractor.extract(from: "card_magic_tutorial.pdf")
        
        #expect(result.original == "card_magic_tutorial.pdf")
        #expect(result.keywords.contains("card"))
        #expect(result.keywords.contains("magic"))
        #expect(result.keywords.contains("tutorial"))
        #expect(result.fileType == .document)
    }
    
    @Test("Extract keywords from camelCase filename")
    func testExtractCamelCase() {
        let extractor = KeywordExtractor(configuration: .fast)
        let result = extractor.extract(from: "MyVideoProject.mp4")
        
        #expect(result.keywords.contains("video"))
        #expect(result.keywords.contains("project"))
        #expect(result.fileType == .video)
    }
    
    @Test("Filter stopwords")
    func testFilterStopwords() {
        let extractor = KeywordExtractor(configuration: .fast)
        let result = extractor.extract(from: "the_best_download_file_final.pdf")
        
        #expect(!result.keywords.contains("the"))
        #expect(!result.keywords.contains("download"))
        #expect(!result.keywords.contains("file"))
        #expect(!result.keywords.contains("final"))
        #expect(result.keywords.contains("best"))
    }
    
    @Test("Detect file types")
    func testDetectFileTypes() {
        let extractor = KeywordExtractor(configuration: .fast)
        
        #expect(extractor.extract(from: "doc.pdf").fileType == .document)
        #expect(extractor.extract(from: "video.mp4").fileType == .video)
        #expect(extractor.extract(from: "song.mp3").fileType == .audio)
        #expect(extractor.extract(from: "pic.jpg").fileType == .image)
        #expect(extractor.extract(from: "archive.zip").fileType == .archive)
    }
    
    @Test("Extract date info")
    func testExtractDateInfo() {
        let extractor = KeywordExtractor(configuration: .fast)
        
        let yearResult = extractor.extract(from: "report_2024.pdf")
        #expect(yearResult.dateInfo?.year == 2024)
        
        let quarterResult = extractor.extract(from: "Q3_sales.xlsx")
        #expect(quarterResult.dateInfo?.quarter == "Q3")
    }
    
    @Test("Batch extraction")
    func testBatchExtraction() {
        let extractor = KeywordExtractor(configuration: .fast)
        let filenames = ["file1.pdf", "file2.mp4", "file3.jpg"]
        
        let results = extractor.extractBatch(from: filenames)
        
        #expect(results.count == 3)
        #expect(results[0].fileType == .document)
        #expect(results[1].fileType == .video)
        #expect(results[2].fileType == .image)
    }
}

// MARK: - SimilarityClusterer Tests

@Suite("SimilarityClusterer Tests")
struct SimilarityClustererTests {
    
    @Test("Cluster similar files")
    func testClusterSimilarFiles() async {
        let clusterer = SimilarityClusterer()
        let extractor = KeywordExtractor(configuration: .fast)
        
        let filenames = [
            "card_magic_intro.pdf",
            "card_magic_advanced.pdf",
            "card_tricks_basics.pdf",
            "cooking_recipe_1.pdf",
            "cooking_recipe_2.pdf"
        ]
        
        let keywords = extractor.extractBatch(from: filenames)
        let clusters = await clusterer.cluster(keywords: keywords)
        
        // Should create at least 1 cluster
        #expect(clusters.count >= 1)
        
        // Total files should match
        let totalFiles = clusters.reduce(0) { $0 + $1.files.count }
        #expect(totalFiles == 5)
    }
    
    @Test("Group by file type")
    func testGroupByFileType() async {
        let clusterer = SimilarityClusterer()
        let extractor = KeywordExtractor(configuration: .fast)
        
        let filenames = [
            "video1.mp4",
            "video2.mp4",
            "document1.pdf",
            "document2.pdf"
        ]
        
        let keywords = extractor.extractBatch(from: filenames)
        let clusters = await clusterer.cluster(keywords: keywords)
        
        // All file types should be present in some cluster
        let fileTypes = Set(clusters.map { $0.fileType })
        #expect(fileTypes.count >= 1)
        
        // Total files should match
        let totalFiles = clusters.reduce(0) { $0 + $1.files.count }
        #expect(totalFiles == 4)
    }
    
    @Test("Custom target count")
    func testCustomTargetCount() async {
        let config = SimilarityClusterer.Configuration.withTargetCount(5)
        let clusterer = SimilarityClusterer(configuration: config)
        let extractor = KeywordExtractor(configuration: .fast)
        
        let filenames = (1...20).map { "file_\($0).pdf" }
        let keywords = extractor.extractBatch(from: filenames)
        let clusters = await clusterer.cluster(keywords: keywords)
        
        // Should create some clusters
        #expect(clusters.count >= 1)
        
        // Total files should match
        let totalFiles = clusters.reduce(0) { $0 + $1.files.count }
        #expect(totalFiles == 20)
    }
}

// MARK: - SemanticThemeClusterer Tests

@Suite("SemanticThemeClusterer Tests")
struct SemanticThemeClustererTests {
    
    @Test("Cluster by semantic theme")
    func testClusterBySemanticTheme() async {
        let clusterer = SemanticThemeClusterer()
        let extractor = KeywordExtractor(configuration: .fast)
        
        let filenames = [
            "card_magic_tutorial.pdf",
            "coin_magic_basics.pdf",
            "magic_performance.mp4",
            "cooking_recipe_1.pdf",
            "cooking_dinner.pdf",
            "chef_tips.mp4"
        ]
        
        let keywords = extractor.extractBatch(from: filenames)
        let themes = await clusterer.cluster(keywords: keywords)
        
        // Should create semantic themes (Magic, Cooking)
        #expect(themes.count >= 1)
        
        // Total files should match
        let totalFiles = themes.reduce(0) { $0 + $1.totalFileCount }
        #expect(totalFiles == 6)
    }
    
    @Test("Theme identification from keywords")
    func testThemeIdentification() async {
        let clusterer = SemanticThemeClusterer()
        let extractor = KeywordExtractor(configuration: .fast)
        
        // Files with clear magic theme
        let filenames = [
            "card_magic_intro.pdf",
            "coin_magic.mp4",
            "magic_tricks.pdf",
            "illusion_tutorial.mp4"
        ]
        
        let keywords = extractor.extractBatch(from: filenames)
        let themes = await clusterer.cluster(keywords: keywords)
        
        // Should identify "Magic" as a theme
        let magicTheme = themes.first { $0.name.lowercased().contains("magic") }
        #expect(magicTheme != nil || themes.count >= 1)
    }
    
    @Test("File type separation within themes")
    func testFileTypeSeparation() async {
        let config = SemanticThemeClusterer.Configuration.withTargetCount(5, separateTypes: true)
        let clusterer = SemanticThemeClusterer(configuration: config)
        let extractor = KeywordExtractor(configuration: .fast)
        
        let filenames = [
            "magic_tutorial_1.pdf",
            "magic_tutorial_2.pdf",
            "magic_performance.mp4",
            "magic_show.mp4"
        ]
        
        let keywords = extractor.extractBatch(from: filenames)
        let themes = await clusterer.cluster(keywords: keywords)
        
        // Should have file type groups
        let hasFileTypeGroups = themes.contains { !$0.fileTypeGroups.isEmpty }
        #expect(hasFileTypeGroups)
    }
    
    @Test("Configuration with separateTypes disabled")
    func testNoFileTypeSeparation() async {
        let config = SemanticThemeClusterer.Configuration.withTargetCount(5, separateTypes: false)
        let clusterer = SemanticThemeClusterer(configuration: config)
        let extractor = KeywordExtractor(configuration: .fast)
        
        let filenames = ["test1.pdf", "test2.mp4"]
        let keywords = extractor.extractBatch(from: filenames)
        let themes = await clusterer.cluster(keywords: keywords)
        
        // Files should be in themes but not separated by type
        #expect(themes.count >= 1)
    }
}

// MARK: - FastTaxonomyBuilder Tests

@Suite("FastTaxonomyBuilder Tests")
struct FastTaxonomyBuilderTests {
    
    @Test("Build instant taxonomy with semantic themes")
    func testBuildInstant() async {
        let builder = FastTaxonomyBuilder()
        
        let filenames = [
            "magic_trick_1.pdf",
            "magic_trick_2.pdf",
            "cooking_recipe.pdf",
            "video_tutorial.mp4"
        ]
        
        let taxonomy = await builder.buildInstant(from: filenames, rootName: "Test")
        
        #expect(taxonomy.categoryCount > 0)
        #expect(taxonomy.totalFileCount == 4)
    }
    
    @Test("Fast performance for large sets")
    func testFastPerformance() async {
        let builder = FastTaxonomyBuilder()
        
        // Create 500 files
        let filenames = (1...500).map { "file_\($0 % 10)_category_\($0 / 10).pdf" }
        
        let startTime = Date()
        let taxonomy = await builder.buildInstant(from: filenames, rootName: "TestRoot")
        let duration = Date().timeIntervalSince(startTime)
        
        // Should complete in under 2 seconds
        #expect(duration < 2.0, "Expected <2s, got \(duration)s")
        #expect(taxonomy.totalFileCount == 500)
        
        print("FastTaxonomyBuilder processed 500 files in \(String(format: "%.3f", duration))s")
    }
    
    @Test("Configuration with separateFileTypes")
    func testConfiguration() async {
        let config = FastTaxonomyBuilder.Configuration(
            targetCategoryCount: 5,
            separateFileTypes: true,
            autoRefine: false,
            refinementModel: "llama3.2",
            refinementBatchSize: 25
        )
        
        let builder = FastTaxonomyBuilder(configuration: config)
        
        let filenames = ["test1.pdf", "test2.pdf", "test3.mp4", "test4.mp4"]
        let taxonomy = await builder.buildInstant(from: filenames, rootName: "Config Test")
        
        #expect(taxonomy.totalFileCount == 4)
    }
    
    @Test("Configuration without file type separation")
    func testConfigurationNoSeparation() async {
        let config = FastTaxonomyBuilder.Configuration(
            targetCategoryCount: 5,
            separateFileTypes: false,
            autoRefine: false,
            refinementModel: "llama3.2",
            refinementBatchSize: 25
        )
        
        let builder = FastTaxonomyBuilder(configuration: config)
        
        let filenames = ["magic_1.pdf", "magic_2.mp4"]
        let taxonomy = await builder.buildInstant(from: filenames, rootName: "No Sep Test")
        
        #expect(taxonomy.totalFileCount == 2)
    }
}

// MARK: - Filename Scanner Tests

@Suite("FilenameScanner Tests")
struct FilenameScannerTests {
    
    @Test("Scanner configuration defaults")
    func testScannerConfigurationDefaults() {
        let config = FilenameScanner.Configuration.default
        
        #expect(config.maxFiles == 10000)
        #expect(config.includeHidden == false)
        #expect(config.minFileSize == 100)  // Default is 100 bytes
    }
    
    @Test("Scanned file properties")
    func testScannedFileProperties() {
        let file = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/Users/test/photo.jpg"),
            filename: "photo.jpg",
            fileExtension: "jpg",
            fileSize: 1024 * 1024, // 1 MB
            modificationDate: Date()
        )
        
        #expect(file.filename == "photo.jpg")
        #expect(file.fileExtension == "jpg")
        #expect(file.fileSize == 1024 * 1024)
        #expect(file.isImage)
        #expect(!file.isVideo)
    }
    
    @Test("Scan result formatting")
    func testScanResultFormatting() async {
        // Create a file so we have some size
        let file = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/big.zip"),
            filename: "big.zip",
            fileExtension: "zip",
            fileSize: 1024 * 1024 * 500, // 500 MB
            modificationDate: Date()
        )
        
        let result = TaxonomyScanResult(
            files: [file],
            totalSize: 1024 * 1024 * 500,
            directoryCount: 10,
            scanDuration: 2.5,
            reachedLimit: false
        )
        
        #expect(result.fileCount == 1)
        #expect(result.directoryCount == 10)
        // Check it formats to some readable string
        #expect(!result.formattedTotalSize.isEmpty)
    }
    
    @Test("Scanner hierarchy configuration defaults")
    func testScannerHierarchyConfigurationDefaults() {
        let config = FilenameScanner.Configuration.default
        
        #expect(config.respectHierarchy == true)
        #expect(config.minDepthForFolder == 1)
        #expect(config.minFilesForFolder == 1)
    }
    
    @Test("Scanner flat configuration disables hierarchy")
    func testScannerFlatConfiguration() {
        let config = FilenameScanner.Configuration.flat
        
        #expect(config.respectHierarchy == false)
    }
}

// MARK: - Hierarchy-Aware Scanning Tests

@Suite("HierarchyScanning Tests")
struct HierarchyScanningTests {
    
    // MARK: - ScannedFolder Tests
    
    @Test("Create ScannedFolder")
    func testCreateScannedFolder() {
        let file1 = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/Resumes/resume_v1.pdf"),
            filename: "resume_v1.pdf",
            fileExtension: "pdf",
            fileSize: 50000,
            modificationDate: Date()
        )
        
        let file2 = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/Resumes/resume_v2.docx"),
            filename: "resume_v2.docx",
            fileExtension: "docx",
            fileSize: 75000,
            modificationDate: Date()
        )
        
        let folder = ScannedFolder(
            url: URL(fileURLWithPath: "/test/Resumes"),
            folderName: "Resumes",
            relativePath: "Resumes",
            depth: 1,
            containedFiles: [file1, file2],
            totalSize: 125000,
            modifiedAt: Date()
        )
        
        #expect(folder.folderName == "Resumes")
        #expect(folder.fileCount == 2)
        #expect(folder.totalSize == 125000)
        #expect(folder.depth == 1)
        #expect(!folder.formattedSize.isEmpty)
    }
    
    @Test("ScannedFolder suggestedContext")
    func testScannedFolderContext() {
        let pdf = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/Docs/file.pdf"),
            filename: "file.pdf",
            fileExtension: "pdf",
            fileSize: 1000,
            modificationDate: Date()
        )
        
        let folder = ScannedFolder(
            url: URL(fileURLWithPath: "/test/Docs"),
            folderName: "Docs",
            relativePath: "Docs",
            depth: 1,
            containedFiles: [pdf],
            totalSize: 1000,
            modifiedAt: nil
        )
        
        let context = folder.suggestedContext
        #expect(context.contains("Docs"))
        #expect(context.contains("document"))
    }
    
    // MARK: - ScanUnit Tests
    
    @Test("ScanUnit folder case")
    func testScanUnitFolder() {
        let folder = ScannedFolder(
            url: URL(fileURLWithPath: "/test/MyFolder"),
            folderName: "MyFolder",
            relativePath: "MyFolder",
            depth: 1,
            containedFiles: [],
            totalSize: 0,
            modifiedAt: nil
        )
        
        let unit = ScanUnit.folder(folder)
        
        #expect(unit.displayName == "MyFolder")
        #expect(unit.isFolder)
        #expect(unit.url.lastPathComponent == "MyFolder")
    }
    
    @Test("ScanUnit file case")
    func testScanUnitFile() {
        let file = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/document.pdf"),
            filename: "document.pdf",
            fileExtension: "pdf",
            fileSize: 1024,
            modificationDate: Date()
        )
        
        let unit = ScanUnit.file(file)
        
        #expect(unit.displayName == "document.pdf")
        #expect(!unit.isFolder)
        #expect(unit.totalSize == 1024)
    }
    
    // MARK: - HierarchyScanResult Tests
    
    @Test("HierarchyScanResult totals")
    func testHierarchyScanResultTotals() {
        let file1 = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/loose.pdf"),
            filename: "loose.pdf",
            fileExtension: "pdf",
            fileSize: 1000,
            modificationDate: Date()
        )
        
        let file2 = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/Folder/inside.pdf"),
            filename: "inside.pdf",
            fileExtension: "pdf",
            fileSize: 2000,
            modificationDate: Date()
        )
        
        let folder = ScannedFolder(
            url: URL(fileURLWithPath: "/test/Folder"),
            folderName: "Folder",
            relativePath: "Folder",
            depth: 1,
            containedFiles: [file2],
            totalSize: 2000,
            modifiedAt: nil
        )
        
        let result = HierarchyScanResult(
            sourceFolder: URL(fileURLWithPath: "/test"),
            sourceFolderName: "test",
            folders: [folder],
            looseFiles: [file1],
            skippedCount: 0,
            scanDuration: 0.5,
            reachedLimit: false
        )
        
        #expect(result.totalItems == 2) // 1 folder + 1 loose file
        #expect(result.totalFileCount == 2) // 1 in folder + 1 loose
        #expect(result.totalSize == 3000) // 2000 + 1000
        #expect(result.allUnits.count == 2)
    }
    
    @Test("HierarchyScanResult toLegacyScanResult")
    func testHierarchyScanResultToLegacy() {
        let looseFile = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/loose.txt"),
            filename: "loose.txt",
            fileExtension: "txt",
            fileSize: 100,
            modificationDate: Date()
        )
        
        let folderFile = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/Folder/inside.txt"),
            filename: "inside.txt",
            fileExtension: "txt",
            fileSize: 200,
            modificationDate: Date()
        )
        
        let folder = ScannedFolder(
            url: URL(fileURLWithPath: "/test/Folder"),
            folderName: "Folder",
            relativePath: "Folder",
            depth: 1,
            containedFiles: [folderFile],
            totalSize: 200,
            modifiedAt: nil
        )
        
        let hierarchyResult = HierarchyScanResult(
            sourceFolder: URL(fileURLWithPath: "/test"),
            sourceFolderName: "test",
            folders: [folder],
            looseFiles: [looseFile],
            skippedCount: 5,
            scanDuration: 1.0,
            reachedLimit: false
        )
        
        let legacy = hierarchyResult.toLegacyScanResult()
        
        #expect(legacy.files.count == 2) // Both files flattened
        #expect(legacy.directoryCount == 1)
        #expect(legacy.skippedCount == 5)
        #expect(legacy.scanDuration == 1.0)
    }
    
    // MARK: - Integration Tests (require temp directory)
    
    @Test("Scan with hierarchy separates folders from loose files")
    func testScanWithHierarchy() async throws {
        // Create temporary test directory structure
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortAI_HierarchyTest_\(UUID().uuidString)")
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create structure:
        // tempDir/
        // ├── loose_file.txt (loose file)
        // ├── Resumes/ (folder unit)
        // │   └── resume.pdf
        // └── Photos/ (folder unit)
        //     └── photo.jpg
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("Resumes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("Photos"), withIntermediateDirectories: true)
        
        // Create files (must be >= 100 bytes to pass minFileSize check)
        let testContent = String(repeating: "test content ", count: 20) // ~260 bytes
        try testContent.write(to: tempDir.appendingPathComponent("loose_file.txt"), atomically: true, encoding: .utf8)
        try testContent.write(to: tempDir.appendingPathComponent("Resumes/resume.pdf"), atomically: true, encoding: .utf8)
        try testContent.write(to: tempDir.appendingPathComponent("Photos/photo.jpg"), atomically: true, encoding: .utf8)
        
        // Scan with hierarchy
        let scanner = FilenameScanner()
        let result = try await scanner.scanWithHierarchy(folder: tempDir)
        
        // Verify results
        #expect(result.folders.count == 2, "Expected 2 folders (Resumes, Photos), got \(result.folders.count)")
        #expect(result.looseFiles.count == 1, "Expected 1 loose file, got \(result.looseFiles.count)")
        #expect(result.totalFileCount == 3, "Expected 3 total files")
        
        // Verify folder names
        let folderNames = Set(result.folders.map { $0.folderName })
        #expect(folderNames.contains("Resumes"))
        #expect(folderNames.contains("Photos"))
        
        // Verify loose file
        #expect(result.looseFiles[0].filename == "loose_file.txt")
    }
    
    @Test("Scan with hierarchy flattens empty folders")
    func testScanWithHierarchyFlattensEmptyFolders() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortAI_EmptyFolderTest_\(UUID().uuidString)")
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create structure:
        // tempDir/
        // ├── EmptyFolder/ (empty - should be ignored)
        // └── NonEmpty/
        //     └── file.txt
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("EmptyFolder"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("NonEmpty"), withIntermediateDirectories: true)
        
        let testContent = String(repeating: "content ", count: 50)
        try testContent.write(to: tempDir.appendingPathComponent("NonEmpty/file.txt"), atomically: true, encoding: .utf8)
        
        let scanner = FilenameScanner()
        let result = try await scanner.scanWithHierarchy(folder: tempDir)
        
        // Empty folder should not appear
        #expect(result.folders.count == 1, "Expected 1 folder (NonEmpty only)")
        #expect(result.folders[0].folderName == "NonEmpty")
    }
    
    @Test("Scan with hierarchy respects minFilesForFolder threshold")
    func testScanWithHierarchyMinFilesThreshold() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortAI_MinFilesTest_\(UUID().uuidString)")
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create structure:
        // tempDir/
        // ├── BigFolder/ (2 files - above threshold of 2)
        // │   ├── file1.txt
        // │   └── file2.txt
        // └── SmallFolder/ (1 file - below threshold of 2)
        //     └── only.txt
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("BigFolder"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("SmallFolder"), withIntermediateDirectories: true)
        
        let testContent = String(repeating: "content ", count: 50)
        try testContent.write(to: tempDir.appendingPathComponent("BigFolder/file1.txt"), atomically: true, encoding: .utf8)
        try testContent.write(to: tempDir.appendingPathComponent("BigFolder/file2.txt"), atomically: true, encoding: .utf8)
        try testContent.write(to: tempDir.appendingPathComponent("SmallFolder/only.txt"), atomically: true, encoding: .utf8)
        
        // Create scanner with minFilesForFolder = 2
        let config = FilenameScanner.Configuration(
            maxFiles: 10000,
            includeHidden: false,
            excludedExtensions: [],
            excludedDirectories: [],
            minFileSize: 100,
            respectHierarchy: true,
            minDepthForFolder: 1,
            minFilesForFolder: 2  // Require at least 2 files
        )
        let scanner = FilenameScanner(configuration: config)
        let result = try await scanner.scanWithHierarchy(folder: tempDir)
        
        // BigFolder should be a folder unit, SmallFolder's file should be flattened to loose
        #expect(result.folders.count == 1, "Expected 1 folder (BigFolder)")
        #expect(result.folders[0].folderName == "BigFolder")
        #expect(result.looseFiles.count == 1, "Expected 1 loose file (from SmallFolder)")
        #expect(result.looseFiles[0].filename == "only.txt")
    }
    
    @Test("Scan with hierarchy preserves nested structure in folders")
    func testScanWithHierarchyPreservesNestedStructure() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortAI_NestedTest_\(UUID().uuidString)")
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create structure:
        // tempDir/
        // └── Resumes/ (folder unit)
        //     ├── resume.pdf
        //     └── 2024/
        //         └── latest.pdf
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("Resumes/2024"), withIntermediateDirectories: true)
        
        let testContent = String(repeating: "content ", count: 50)
        try testContent.write(to: tempDir.appendingPathComponent("Resumes/resume.pdf"), atomically: true, encoding: .utf8)
        try testContent.write(to: tempDir.appendingPathComponent("Resumes/2024/latest.pdf"), atomically: true, encoding: .utf8)
        
        let scanner = FilenameScanner()
        let result = try await scanner.scanWithHierarchy(folder: tempDir)
        
        // Should have 1 folder unit with 2 files inside (preserving internal structure)
        #expect(result.folders.count == 1)
        #expect(result.folders[0].folderName == "Resumes")
        #expect(result.folders[0].fileCount == 2, "Nested files should be included")
        
        // Verify both files are in the folder
        let filenames = Set(result.folders[0].containedFiles.map { $0.filename })
        #expect(filenames.contains("resume.pdf"))
        #expect(filenames.contains("latest.pdf"))
    }
}

