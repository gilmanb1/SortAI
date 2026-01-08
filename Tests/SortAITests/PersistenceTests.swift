// MARK: - Persistence Layer Tests
// Comprehensive tests for SortAIDatabase and all Repository classes

import XCTest
@testable import SortAI

// MARK: - Database Tests

final class SortAIDatabaseTests: XCTestCase {
    
    var database: SortAIDatabase!
    
    override func setUp() async throws {
        database = try SortAIDatabase.inMemory()
    }
    
    override func tearDown() async throws {
        database = nil
        SortAIDatabase.resetShared()
    }
    
    // MARK: - Initialization Tests
    
    func testInMemoryDatabaseCreation() throws {
        XCTAssertNotNil(database)
    }
    
    func testDatabaseStatisticsInitiallyEmpty() throws {
        let stats = try database.statistics()
        XCTAssertEqual(stats.entityCount, 0)
        XCTAssertEqual(stats.relationshipCount, 0)
        XCTAssertEqual(stats.patternCount, 0)
        XCTAssertEqual(stats.recordCount, 0)
        XCTAssertEqual(stats.feedbackCount, 0)
        XCTAssertEqual(stats.totalRecords, 0)
    }
    
    func testRepositoriesAccessible() throws {
        XCTAssertNotNil(database.entities)
        XCTAssertNotNil(database.patterns)
        XCTAssertNotNil(database.feedback)
        XCTAssertNotNil(database.records)
        XCTAssertNotNil(database.movementLog)
    }
    
    func testReadWriteTransactions() throws {
        // Write operation
        try database.write { db in
            var entity = Entity(type: .category, name: "Test")
            try entity.insert(db)
        }
        
        // Read operation
        let count = try database.read { db in
            try Entity.fetchCount(db)
        }
        
        XCTAssertEqual(count, 1)
    }
    
    func testStatisticsAfterInserts() throws {
        // Insert entities
        try database.write { db in
            var entity1 = Entity(type: .category, name: "Category 1")
            var entity2 = Entity(type: .keyword, name: "Keyword 1")
            try entity1.insert(db)
            try entity2.insert(db)
        }
        
        // Insert a pattern
        let pattern = LearnedPattern(
            checksum: "test123",
            embedding: [Float](repeating: 0.5, count: 384),
            label: "test-label"
        )
        try database.patterns.save(pattern)
        
        let stats = try database.statistics()
        XCTAssertEqual(stats.entityCount, 2)
        XCTAssertEqual(stats.patternCount, 1)
    }
}

// MARK: - Entity Repository Tests

final class EntityRepositoryTests: XCTestCase {
    
    var database: SortAIDatabase!
    var repository: EntityRepository!
    
    override func setUp() async throws {
        database = try SortAIDatabase.inMemory()
        repository = database.entities
    }
    
    override func tearDown() async throws {
        database = nil
    }
    
    // MARK: - Create Tests
    
    func testFindOrCreateNewEntity() throws {
        let entity = try repository.findOrCreate(type: .category, name: "Test Category")
        
        XCTAssertNotNil(entity.id)
        XCTAssertEqual(entity.type, .category)
        XCTAssertEqual(entity.name, "Test Category")
        XCTAssertEqual(entity.normalizedName, "test category")
        XCTAssertEqual(entity.usageCount, 1)
    }
    
    func testFindOrCreateExistingEntity() throws {
        let entity1 = try repository.findOrCreate(type: .category, name: "Test Category")
        let entity2 = try repository.findOrCreate(type: .category, name: "TEST CATEGORY")
        
        XCTAssertEqual(entity1.id, entity2.id)
        XCTAssertEqual(entity2.usageCount, 2)  // Usage count incremented
    }
    
    func testCreateWithMetadata() throws {
        let metadata: [String: Any] = ["depth": 1, "isLeaf": true]
        let entity = try repository.findOrCreate(type: .category, name: "With Metadata", metadata: metadata)
        
        XCTAssertNotNil(entity.metadata)
        XCTAssertTrue(entity.metadata!.contains("depth"))
        XCTAssertTrue(entity.metadata!.contains("isLeaf"))
    }
    
    func testCreateDifferentTypes() throws {
        let category = try repository.findOrCreate(type: .category, name: "Test")
        let keyword = try repository.findOrCreate(type: .keyword, name: "Test")
        let file = try repository.findOrCreate(type: .file, name: "Test")
        
        XCTAssertNotEqual(category.id, keyword.id)
        XCTAssertNotEqual(keyword.id, file.id)
    }
    
    // MARK: - Read Tests
    
    func testGetById() throws {
        let created = try repository.findOrCreate(type: .category, name: "Find Me")
        let retrieved = try repository.get(id: created.id!)
        
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "Find Me")
    }
    
    func testGetByIdNotFound() throws {
        let result = try repository.get(id: 99999)
        XCTAssertNil(result)
    }
    
    func testGetByType() throws {
        _ = try repository.findOrCreate(type: .category, name: "Cat 1")
        _ = try repository.findOrCreate(type: .category, name: "Cat 2")
        _ = try repository.findOrCreate(type: .keyword, name: "Key 1")
        
        let categories = try repository.getByType(.category)
        let keywords = try repository.getByType(.keyword)
        
        XCTAssertEqual(categories.count, 2)
        XCTAssertEqual(keywords.count, 1)
    }
    
    func testSearchEntities() throws {
        _ = try repository.findOrCreate(type: .category, name: "Programming Languages")
        _ = try repository.findOrCreate(type: .category, name: "Programming Tutorials")
        _ = try repository.findOrCreate(type: .category, name: "Music Videos")
        
        let results = try repository.search(query: "program")
        XCTAssertEqual(results.count, 2)
        
        let musicResults = try repository.search(query: "music")
        XCTAssertEqual(musicResults.count, 1)
    }
    
    func testSearchWithTypeFilter() throws {
        _ = try repository.findOrCreate(type: .category, name: "Swift")
        _ = try repository.findOrCreate(type: .keyword, name: "Swift")
        
        let categoryResults = try repository.search(query: "swift", type: .category)
        XCTAssertEqual(categoryResults.count, 1)
        XCTAssertEqual(categoryResults.first?.type, .category)
    }
    
    func testCount() throws {
        _ = try repository.findOrCreate(type: .category, name: "Cat 1")
        _ = try repository.findOrCreate(type: .category, name: "Cat 2")
        _ = try repository.findOrCreate(type: .keyword, name: "Key 1")
        
        let totalCount = try repository.count()
        let categoryCount = try repository.count(type: .category)
        let keywordCount = try repository.count(type: .keyword)
        
        XCTAssertEqual(totalCount, 3)
        XCTAssertEqual(categoryCount, 2)
        XCTAssertEqual(keywordCount, 1)
    }
    
    // MARK: - Update Tests
    
    func testUpdateEntity() throws {
        var entity = try repository.findOrCreate(type: .category, name: "Original Name")
        entity.usageCount = 100
        try repository.update(entity)
        
        let retrieved = try repository.get(id: entity.id!)
        XCTAssertEqual(retrieved?.usageCount, 100)
    }
    
    func testIncrementUsage() throws {
        let entity = try repository.findOrCreate(type: .category, name: "Popular")
        XCTAssertEqual(entity.usageCount, 1)
        
        try repository.incrementUsage(id: entity.id!)
        try repository.incrementUsage(id: entity.id!)
        
        let retrieved = try repository.get(id: entity.id!)
        XCTAssertEqual(retrieved?.usageCount, 3)
    }
    
    // MARK: - Delete Tests
    
    func testDeleteById() throws {
        let entity = try repository.findOrCreate(type: .category, name: "Delete Me")
        let deleted = try repository.delete(id: entity.id!)
        
        XCTAssertTrue(deleted)
        XCTAssertNil(try repository.get(id: entity.id!))
    }
    
    func testDeleteAllByType() throws {
        _ = try repository.findOrCreate(type: .category, name: "Cat 1")
        _ = try repository.findOrCreate(type: .category, name: "Cat 2")
        _ = try repository.findOrCreate(type: .keyword, name: "Key 1")
        
        let deletedCount = try repository.deleteAll(type: .category)
        
        XCTAssertEqual(deletedCount, 2)
        XCTAssertEqual(try repository.count(type: .category), 0)
        XCTAssertEqual(try repository.count(type: .keyword), 1)
    }
    
    // MARK: - Category Path Tests
    
    func testGetOrCreateCategoryPath() throws {
        let path = CategoryPath(path: "Tech / Programming / Swift")
        let entity = try repository.getOrCreateCategoryPath(path)
        
        XCTAssertNotNil(entity.id)
        XCTAssertEqual(entity.name, "Tech / Programming / Swift")
        
        // Verify all intermediate categories were created
        let allCategories = try repository.getAllCategories()
        XCTAssertEqual(allCategories.count, 3)
    }
    
    func testGetOrCreateCategoryPathIdempotent() throws {
        let path = CategoryPath(path: "A / B / C")
        
        let entity1 = try repository.getOrCreateCategoryPath(path)
        let entity2 = try repository.getOrCreateCategoryPath(path)
        
        XCTAssertEqual(entity1.id, entity2.id)
        XCTAssertEqual(entity2.usageCount, 2)  // Created once, found once
    }
    
    func testGetRootCategories() throws {
        _ = try repository.getOrCreateCategoryPath(CategoryPath(path: "Root1 / Child"))
        _ = try repository.getOrCreateCategoryPath(CategoryPath(path: "Root2"))
        
        let roots = try repository.getRootCategories()
        
        // Root categories should not have isChildOf relationship
        XCTAssertEqual(roots.count, 2)
    }
    
    func testGetChildCategories() throws {
        _ = try repository.getOrCreateCategoryPath(CategoryPath(path: "Parent / Child1"))
        _ = try repository.getOrCreateCategoryPath(CategoryPath(path: "Parent / Child2"))
        
        let parent = try repository.find(type: .category, normalizedName: "parent")
        XCTAssertNotNil(parent)
        
        let children = try repository.getChildCategories(of: parent!.id!)
        XCTAssertEqual(children.count, 2)
    }
}

// MARK: - Relationship Repository Tests

final class RelationshipRepositoryTests: XCTestCase {
    
    var database: SortAIDatabase!
    var entityRepo: EntityRepository!
    var relationshipRepo: RelationshipRepository!
    
    override func setUp() async throws {
        database = try SortAIDatabase.inMemory()
        entityRepo = database.entities
        relationshipRepo = RelationshipRepository(database: database)
    }
    
    override func tearDown() async throws {
        database = nil
    }
    
    // MARK: - Create Tests
    
    func testCreateRelationship() throws {
        let source = try entityRepo.findOrCreate(type: .file, name: "file.pdf")
        let target = try entityRepo.findOrCreate(type: .category, name: "Documents")
        
        let relationship = try relationshipRepo.create(
            sourceId: source.id!,
            targetId: target.id!,
            type: .belongsTo
        )
        
        XCTAssertNotNil(relationship.id)
        XCTAssertEqual(relationship.type, .belongsTo)
        XCTAssertEqual(relationship.weight, 1.0)
    }
    
    func testCreateOrStrengthen() throws {
        let source = try entityRepo.findOrCreate(type: .keyword, name: "swift")
        let target = try entityRepo.findOrCreate(type: .category, name: "Programming")
        
        let rel1 = try relationshipRepo.createOrStrengthen(
            sourceId: source.id!,
            targetId: target.id!,
            type: .suggestsCategory,
            weight: 0.5
        )
        
        let rel2 = try relationshipRepo.createOrStrengthen(
            sourceId: source.id!,
            targetId: target.id!,
            type: .suggestsCategory
        )
        
        XCTAssertEqual(rel1.id, rel2.id)
        XCTAssertEqual(rel2.weight, 0.6, accuracy: 0.01)  // 0.5 + 0.1
    }
    
    // MARK: - Read Tests
    
    func testGetFrom() throws {
        let source = try entityRepo.findOrCreate(type: .file, name: "file.pdf")
        let target1 = try entityRepo.findOrCreate(type: .category, name: "Cat1")
        let target2 = try entityRepo.findOrCreate(type: .category, name: "Cat2")
        
        _ = try relationshipRepo.create(sourceId: source.id!, targetId: target1.id!, type: .belongsTo)
        _ = try relationshipRepo.create(sourceId: source.id!, targetId: target2.id!, type: .belongsTo)
        
        let relationships = try relationshipRepo.getFrom(sourceId: source.id!)
        XCTAssertEqual(relationships.count, 2)
    }
    
    func testGetTo() throws {
        let source1 = try entityRepo.findOrCreate(type: .keyword, name: "key1")
        let source2 = try entityRepo.findOrCreate(type: .keyword, name: "key2")
        let target = try entityRepo.findOrCreate(type: .category, name: "Category")
        
        _ = try relationshipRepo.create(sourceId: source1.id!, targetId: target.id!, type: .suggestsCategory)
        _ = try relationshipRepo.create(sourceId: source2.id!, targetId: target.id!, type: .suggestsCategory)
        
        let relationships = try relationshipRepo.getTo(targetId: target.id!)
        XCTAssertEqual(relationships.count, 2)
    }
    
    func testFind() throws {
        let source = try entityRepo.findOrCreate(type: .file, name: "file")
        let target = try entityRepo.findOrCreate(type: .category, name: "cat")
        
        _ = try relationshipRepo.create(sourceId: source.id!, targetId: target.id!, type: .belongsTo)
        
        let found = try relationshipRepo.find(sourceId: source.id!, targetId: target.id!, type: .belongsTo)
        XCTAssertNotNil(found)
        
        let notFound = try relationshipRepo.find(sourceId: source.id!, targetId: target.id!, type: .humanConfirmed)
        XCTAssertNil(notFound)
    }
    
    // MARK: - Learning Tests
    
    func testLearnKeywordSuggestion() throws {
        let keyword = try entityRepo.findOrCreate(type: .keyword, name: "python")
        let category = try entityRepo.findOrCreate(type: .category, name: "Programming")
        
        try relationshipRepo.learnKeywordSuggestion(keywordId: keyword.id!, categoryId: category.id!, weight: 0.7)
        
        let relationships = try relationshipRepo.getFrom(sourceId: keyword.id!, type: .suggestsCategory)
        XCTAssertEqual(relationships.count, 1)
        XCTAssertEqual(relationships.first!.weight, 0.7, accuracy: 0.01)
    }
    
    func testRecordHumanConfirmation() throws {
        let file = try entityRepo.findOrCreate(type: .file, name: "doc.pdf")
        let category = try entityRepo.findOrCreate(type: .category, name: "Documents")
        
        try relationshipRepo.recordHumanConfirmation(fileId: file.id!, categoryId: category.id!)
        
        let relationships = try relationshipRepo.getFrom(sourceId: file.id!, type: .humanConfirmed)
        XCTAssertEqual(relationships.count, 1)
    }
    
    func testGetSuggestedCategories() throws {
        let kw1 = try entityRepo.findOrCreate(type: .keyword, name: "swift")
        let kw2 = try entityRepo.findOrCreate(type: .keyword, name: "ios")
        let cat1 = try entityRepo.findOrCreate(type: .category, name: "Programming")
        let cat2 = try entityRepo.findOrCreate(type: .category, name: "Mobile")
        
        try relationshipRepo.learnKeywordSuggestion(keywordId: kw1.id!, categoryId: cat1.id!, weight: 0.8)
        try relationshipRepo.learnKeywordSuggestion(keywordId: kw2.id!, categoryId: cat1.id!, weight: 0.6)
        try relationshipRepo.learnKeywordSuggestion(keywordId: kw2.id!, categoryId: cat2.id!, weight: 0.3)
        
        let suggestions = try relationshipRepo.getSuggestedCategories(for: [kw1.id!, kw2.id!])
        
        XCTAssertEqual(suggestions.count, 2)
        XCTAssertEqual(suggestions.first?.entityId, cat1.id)  // Highest total weight
    }
}

// MARK: - Pattern Repository Tests

final class PatternRepositoryTests: XCTestCase {
    
    var database: SortAIDatabase!
    var repository: PatternRepository!
    
    override func setUp() async throws {
        database = try SortAIDatabase.inMemory()
        repository = PatternRepository(database: database, embeddingDimensions: 128, similarityThreshold: 0.85)
    }
    
    override func tearDown() async throws {
        database = nil
    }
    
    // MARK: - Create Tests
    
    func testSavePattern() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        let pattern = LearnedPattern(
            checksum: "abc123",
            embedding: embedding,
            label: "work-documents"
        )
        
        let saved = try repository.save(pattern)
        
        XCTAssertEqual(saved.id, pattern.id)
        XCTAssertEqual(saved.label, "work-documents")
    }
    
    func testSavePatternDimensionMismatch() throws {
        let wrongDimensions = [Float](repeating: 0.5, count: 64)
        let pattern = LearnedPattern(
            checksum: "abc",
            embedding: wrongDimensions,
            label: "test"
        )
        
        XCTAssertThrowsError(try repository.save(pattern)) { error in
            XCTAssertTrue(error is DatabaseError)
        }
    }
    
    func testSaveOrUpdate() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        var pattern = LearnedPattern(
            id: "update-test",
            checksum: "abc",
            embedding: embedding,
            label: "original"
        )
        
        _ = try repository.saveOrUpdate(pattern)
        
        pattern.label = "updated"
        _ = try repository.saveOrUpdate(pattern)
        
        let retrieved = try repository.get(id: "update-test")
        XCTAssertEqual(retrieved?.label, "updated")
    }
    
    // MARK: - Read Tests
    
    func testGetById() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        let pattern = LearnedPattern(
            id: "find-me",
            checksum: "check123",
            embedding: embedding,
            label: "test"
        )
        _ = try repository.save(pattern)
        
        let retrieved = try repository.get(id: "find-me")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.checksum, "check123")
    }
    
    func testFindByChecksum() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        let pattern = LearnedPattern(
            checksum: "unique-checksum",
            embedding: embedding,
            label: "test"
        )
        _ = try repository.save(pattern)
        
        let found = try repository.findByChecksum("unique-checksum")
        XCTAssertNotNil(found)
        
        let notFound = try repository.findByChecksum("nonexistent")
        XCTAssertNil(notFound)
    }
    
    func testFindByLabel() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        
        _ = try repository.save(LearnedPattern(checksum: "c1", embedding: embedding, label: "work", confidence: 0.9))
        _ = try repository.save(LearnedPattern(checksum: "c2", embedding: embedding, label: "work", confidence: 0.8))
        _ = try repository.save(LearnedPattern(checksum: "c3", embedding: embedding, label: "personal"))
        
        let workPatterns = try repository.findByLabel("work")
        XCTAssertEqual(workPatterns.count, 2)
        XCTAssertEqual(workPatterns.first?.confidence, 0.9)  // Sorted by confidence
    }
    
    func testGetAllLabels() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        
        _ = try repository.save(LearnedPattern(checksum: "c1", embedding: embedding, label: "work"))
        _ = try repository.save(LearnedPattern(checksum: "c2", embedding: embedding, label: "personal"))
        _ = try repository.save(LearnedPattern(checksum: "c3", embedding: embedding, label: "work"))
        
        let labels = try repository.getAllLabels()
        XCTAssertEqual(Set(labels), Set(["work", "personal"]))
    }
    
    // MARK: - Vector Similarity Tests
    
    func testQueryNearest() throws {
        let base = [Float](repeating: 0.5, count: 128)
        var similar = base
        similar[0] = 0.55
        var different = [Float](repeating: 0.1, count: 128)
        different[0] = -0.5
        
        _ = try repository.save(LearnedPattern(checksum: "base", embedding: base, label: "category-a"))
        _ = try repository.save(LearnedPattern(checksum: "diff", embedding: different, label: "category-b"))
        
        let matches = try repository.queryNearest(to: similar, k: 5, minSimilarity: 0.5)
        
        XCTAssertFalse(matches.isEmpty)
        XCTAssertEqual(matches.first?.pattern.label, "category-a")
    }
    
    func testFindBestMatch() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        _ = try repository.save(LearnedPattern(checksum: "match", embedding: embedding, label: "found"))
        
        var query = embedding
        query[0] = 0.52
        
        let match = try repository.findBestMatch(for: query)
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.pattern.label, "found")
    }
    
    func testCosineDistance() {
        let a: [Float] = [1.0, 0.0, 0.0]
        let b: [Float] = [1.0, 0.0, 0.0]
        let c: [Float] = [-1.0, 0.0, 0.0]
        
        XCTAssertEqual(PatternRepository.cosineDistance(a: a, b: b), 0.0, accuracy: 0.001)
        XCTAssertEqual(PatternRepository.cosineDistance(a: a, b: c), 2.0, accuracy: 0.001)
    }
    
    func testEuclideanDistance() {
        let a: [Float] = [0.0, 0.0]
        let b: [Float] = [3.0, 4.0]
        
        XCTAssertEqual(PatternRepository.euclideanDistance(a: a, b: b), 5.0, accuracy: 0.001)
    }
    
    // MARK: - Update Tests
    
    func testRecordHit() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        let pattern = LearnedPattern(
            id: "hit-test",
            checksum: "hit",
            embedding: embedding,
            label: "test",
            hitCount: 0
        )
        _ = try repository.save(pattern)
        
        try repository.recordHit(patternId: "hit-test")
        try repository.recordHit(patternId: "hit-test")
        
        let retrieved = try repository.get(id: "hit-test")
        XCTAssertEqual(retrieved?.hitCount, 2)
    }
    
    func testUpdateConfidence() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        let pattern = LearnedPattern(
            id: "conf-test",
            checksum: "conf",
            embedding: embedding,
            label: "test",
            confidence: 0.5
        )
        _ = try repository.save(pattern)
        
        try repository.updateConfidence(patternId: "conf-test", confidence: 0.95)
        
        let retrieved = try repository.get(id: "conf-test")
        XCTAssertEqual(retrieved!.confidence, 0.95, accuracy: 0.01)
    }
    
    // MARK: - Delete Tests
    
    func testDelete() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        let pattern = LearnedPattern(id: "delete-me", checksum: "del", embedding: embedding, label: "test")
        _ = try repository.save(pattern)
        
        let deleted = try repository.delete(id: "delete-me")
        XCTAssertTrue(deleted)
        
        let retrieved = try repository.get(id: "delete-me")
        XCTAssertNil(retrieved)
    }
    
    func testPruneWeakPatterns() throws {
        let embedding = [Float](repeating: 0.5, count: 128)
        
        _ = try repository.save(LearnedPattern(checksum: "strong", embedding: embedding, label: "test", confidence: 0.9, hitCount: 10))
        _ = try repository.save(LearnedPattern(checksum: "weak1", embedding: embedding, label: "test", confidence: 0.2, hitCount: 0))
        _ = try repository.save(LearnedPattern(checksum: "weak2", embedding: embedding, label: "test", confidence: 0.1, hitCount: 0))
        
        let pruned = try repository.pruneWeakPatterns(minConfidence: 0.3, minHits: 0)
        
        XCTAssertEqual(pruned, 2)
        XCTAssertEqual(try repository.count(), 1)
    }
}

// MARK: - Record Repository Tests

final class RecordRepositoryTests: XCTestCase {
    
    var database: SortAIDatabase!
    var repository: RecordRepository!
    
    override func setUp() async throws {
        database = try SortAIDatabase.inMemory()
        repository = database.records
    }
    
    override func tearDown() async throws {
        database = nil
    }
    
    // MARK: - Create Tests
    
    func testSaveRecord() throws {
        let record = ProcessingRecord(
            fileURL: URL(fileURLWithPath: "/test/file.pdf"),
            checksum: "abc123",
            mediaKind: .document,
            assignedCategory: "work",
            confidence: 0.95
        )
        
        let saved = try repository.save(record)
        XCTAssertEqual(saved.assignedCategory, "work")
    }
    
    func testSaveBatch() throws {
        let records = (1...5).map { i in
            ProcessingRecord(
                fileURL: URL(fileURLWithPath: "/test/file\(i).pdf"),
                checksum: "check\(i)",
                mediaKind: .document,
                assignedCategory: "batch",
                confidence: 0.8
            )
        }
        
        try repository.saveBatch(records)
        XCTAssertEqual(try repository.count(), 5)
    }
    
    // MARK: - Read Tests
    
    func testFindByChecksum() throws {
        let record = ProcessingRecord(
            fileURL: URL(fileURLWithPath: "/test/file.pdf"),
            checksum: "unique-check",
            mediaKind: .document,
            assignedCategory: "work",
            confidence: 0.9
        )
        _ = try repository.save(record)
        
        let found = try repository.findByChecksum("unique-check")
        XCTAssertNotNil(found)
        
        let notFound = try repository.findByChecksum("nonexistent")
        XCTAssertNil(notFound)
    }
    
    func testFindByCategory() throws {
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/work1.pdf"), checksum: "w1", mediaKind: .document, assignedCategory: "work", confidence: 0.9))
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/work2.pdf"), checksum: "w2", mediaKind: .document, assignedCategory: "work", confidence: 0.8))
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/personal.pdf"), checksum: "p1", mediaKind: .document, assignedCategory: "personal", confidence: 0.7))
        
        let workRecords = try repository.findByCategory("work")
        XCTAssertEqual(workRecords.count, 2)
    }
    
    func testFindByMediaKind() throws {
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/doc.pdf"), checksum: "d1", mediaKind: .document, assignedCategory: "test", confidence: 0.9))
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/video.mp4"), checksum: "v1", mediaKind: .video, assignedCategory: "test", confidence: 0.9))
        
        let documents = try repository.findByMediaKind(.document)
        let videos = try repository.findByMediaKind(.video)
        
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(videos.count, 1)
    }
    
    func testGetRecent() throws {
        for i in 1...10 {
            _ = try repository.save(ProcessingRecord(
                fileURL: URL(fileURLWithPath: "/file\(i).pdf"),
                checksum: "c\(i)",
                mediaKind: .document,
                assignedCategory: "test",
                confidence: 0.9
            ))
        }
        
        let recent = try repository.getRecent(limit: 5)
        XCTAssertEqual(recent.count, 5)
    }
    
    // MARK: - Statistics Tests
    
    func testCategoryStatistics() throws {
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/w1.pdf"), checksum: "w1", mediaKind: .document, assignedCategory: "work", confidence: 0.9))
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/w2.pdf"), checksum: "w2", mediaKind: .document, assignedCategory: "work", confidence: 0.8))
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/p1.pdf"), checksum: "p1", mediaKind: .document, assignedCategory: "personal", confidence: 0.7))
        
        let stats = try repository.categoryStatistics()
        
        XCTAssertEqual(stats.count, 2)
        
        let workStats = stats.first { $0.category == "work" }
        XCTAssertEqual(workStats?.totalFiles, 2)
        XCTAssertEqual(workStats?.avgConfidence ?? 0, 0.85, accuracy: 0.01)
    }
    
    func testOverallStatistics() throws {
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/1.pdf"), checksum: "1", mediaKind: .document, assignedCategory: "test", confidence: 0.9, wasFromMemory: true))
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/2.pdf"), checksum: "2", mediaKind: .document, assignedCategory: "test", confidence: 0.8, wasOverridden: true))
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/3.pdf"), checksum: "3", mediaKind: .document, assignedCategory: "test", confidence: 0.7))
        
        let stats = try repository.overallStatistics()
        
        XCTAssertEqual(stats.totalRecords, 3)
        XCTAssertEqual(stats.fromMemory, 1)
        XCTAssertEqual(stats.overridden, 1)
        XCTAssertEqual(stats.memoryHitRate, 1.0/3.0, accuracy: 0.01)
    }
    
    // MARK: - Update Tests
    
    func testMarkOverridden() throws {
        let record = ProcessingRecord(
            id: "override-test",
            fileURL: URL(fileURLWithPath: "/test.pdf"),
            checksum: "ov",
            mediaKind: .document,
            assignedCategory: "original",
            confidence: 0.5
        )
        _ = try repository.save(record)
        
        try repository.markOverridden(id: "override-test", newCategory: "corrected")
        
        let retrieved = try repository.get(id: "override-test")
        XCTAssertTrue(retrieved?.wasOverridden ?? false)
        XCTAssertEqual(retrieved?.assignedCategory, "corrected")
    }
    
    // MARK: - Delete Tests
    
    func testDelete() throws {
        let record = ProcessingRecord(id: "del-test", fileURL: URL(fileURLWithPath: "/del.pdf"), checksum: "del", mediaKind: .document, assignedCategory: "test", confidence: 0.9)
        _ = try repository.save(record)
        
        let deleted = try repository.delete(id: "del-test")
        XCTAssertTrue(deleted)
        XCTAssertNil(try repository.get(id: "del-test"))
    }
    
    func testDeleteByCategory() throws {
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/1.pdf"), checksum: "1", mediaKind: .document, assignedCategory: "delete-me", confidence: 0.9))
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/2.pdf"), checksum: "2", mediaKind: .document, assignedCategory: "delete-me", confidence: 0.8))
        _ = try repository.save(ProcessingRecord(fileURL: URL(fileURLWithPath: "/3.pdf"), checksum: "3", mediaKind: .document, assignedCategory: "keep", confidence: 0.7))
        
        let deleted = try repository.deleteByCategory("delete-me")
        
        XCTAssertEqual(deleted, 2)
        XCTAssertEqual(try repository.count(), 1)
    }
}

// MARK: - Feedback Repository Tests

final class FeedbackRepositoryTests: XCTestCase {
    
    var database: SortAIDatabase!
    var repository: FeedbackRepository!
    
    override func setUp() async throws {
        database = try SortAIDatabase.inMemory()
        repository = database.feedback
    }
    
    override func tearDown() async throws {
        database = nil
    }
    
    // MARK: - Create Tests
    
    func testAddFeedbackItem() throws {
        let item = try repository.add(
            fileURL: URL(fileURLWithPath: "/test/file.pdf"),
            category: "work",
            subcategories: ["documents", "reports"],
            confidence: 0.7,
            rationale: "Contains work-related content",
            keywords: ["quarterly", "report"]
        )
        
        XCTAssertNotNil(item.id)
        XCTAssertEqual(item.suggestedCategory, "work")
        XCTAssertEqual(item.status, .pending)  // Below auto-accept threshold
    }
    
    func testAddHighConfidenceAutoAccepted() throws {
        let item = try repository.add(
            fileURL: URL(fileURLWithPath: "/test/file.pdf"),
            category: "work",
            subcategories: [],
            confidence: 0.95,
            rationale: "High confidence",
            keywords: []
        )
        
        XCTAssertEqual(item.status, .autoAccepted)
    }
    
    // MARK: - Read Tests
    
    func testGetPending() throws {
        _ = try repository.add(fileURL: URL(fileURLWithPath: "/1.pdf"), category: "cat", subcategories: [], confidence: 0.5, rationale: "", keywords: [])
        _ = try repository.add(fileURL: URL(fileURLWithPath: "/2.pdf"), category: "cat", subcategories: [], confidence: 0.4, rationale: "", keywords: [])
        _ = try repository.add(fileURL: URL(fileURLWithPath: "/3.pdf"), category: "cat", subcategories: [], confidence: 0.95, rationale: "", keywords: [])
        
        let pending = try repository.getPending()
        
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(pending.first?.confidence, 0.4)  // Sorted by confidence ascending
    }
    
    func testGetByStatus() throws {
        _ = try repository.add(fileURL: URL(fileURLWithPath: "/1.pdf"), category: "cat", subcategories: [], confidence: 0.5, rationale: "", keywords: [])
        _ = try repository.add(fileURL: URL(fileURLWithPath: "/2.pdf"), category: "cat", subcategories: [], confidence: 0.95, rationale: "", keywords: [])
        
        let pending = try repository.getByStatus(.pending)
        let autoAccepted = try repository.getByStatus(.autoAccepted)
        
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(autoAccepted.count, 1)
    }
    
    // MARK: - Statistics Tests
    
    func testStatistics() throws {
        // Create items with various statuses
        let item1 = try repository.add(fileURL: URL(fileURLWithPath: "/1.pdf"), category: "cat", subcategories: [], confidence: 0.5, rationale: "", keywords: [])
        let item2 = try repository.add(fileURL: URL(fileURLWithPath: "/2.pdf"), category: "cat", subcategories: [], confidence: 0.95, rationale: "", keywords: [])
        
        _ = try repository.acceptSuggestion(itemId: item1.id!)
        
        let stats = try repository.statistics()
        
        XCTAssertEqual(stats.pendingReview, 0)
        XCTAssertEqual(stats.autoAccepted, 1)
        XCTAssertEqual(stats.humanAccepted, 1)
        XCTAssertEqual(stats.total, 2)
    }
    
    // MARK: - Update Tests
    
    func testAcceptSuggestion() throws {
        let item = try repository.add(fileURL: URL(fileURLWithPath: "/test.pdf"), category: "test", subcategories: [], confidence: 0.5, rationale: "", keywords: [])
        
        let accepted = try repository.acceptSuggestion(itemId: item.id!)
        
        XCTAssertEqual(accepted.status, .humanAccepted)
        XCTAssertNotNil(accepted.reviewedAt)
    }
    
    func testCorrectCategory() throws {
        let item = try repository.add(fileURL: URL(fileURLWithPath: "/test.pdf"), category: "wrong", subcategories: [], confidence: 0.5, rationale: "", keywords: [])
        
        let corrected = try repository.correctCategory(
            itemId: item.id!,
            newCategory: "correct",
            newSubcategories: ["sub1", "sub2"],
            notes: "Fixed the category"
        )
        
        XCTAssertEqual(corrected.status, .humanCorrected)
        XCTAssertEqual(corrected.humanCategory, "correct")
        XCTAssertNotNil(corrected.feedbackNotes)
    }
    
    func testSkip() throws {
        let item = try repository.add(fileURL: URL(fileURLWithPath: "/test.pdf"), category: "test", subcategories: [], confidence: 0.5, rationale: "", keywords: [])
        
        let skipped = try repository.skip(itemId: item.id!)
        
        XCTAssertEqual(skipped.status, .skipped)
    }
    
    // MARK: - Batch Tests
    
    func testAcceptBatch() throws {
        let item1 = try repository.add(fileURL: URL(fileURLWithPath: "/1.pdf"), category: "cat", subcategories: [], confidence: 0.5, rationale: "", keywords: [])
        let item2 = try repository.add(fileURL: URL(fileURLWithPath: "/2.pdf"), category: "cat", subcategories: [], confidence: 0.5, rationale: "", keywords: [])
        
        let count = try repository.acceptBatch(itemIds: [item1.id!, item2.id!])
        
        XCTAssertEqual(count, 2)
        
        let accepted = try repository.getByStatus(.humanAccepted)
        XCTAssertEqual(accepted.count, 2)
    }
    
    // MARK: - Delete Tests
    
    func testDelete() throws {
        let item = try repository.add(fileURL: URL(fileURLWithPath: "/del.pdf"), category: "cat", subcategories: [], confidence: 0.5, rationale: "", keywords: [])
        
        let deleted = try repository.delete(id: item.id!)
        XCTAssertTrue(deleted)
        
        XCTAssertNil(try repository.get(id: item.id!))
    }
    
    func testDeleteByStatus() throws {
        _ = try repository.add(fileURL: URL(fileURLWithPath: "/1.pdf"), category: "cat", subcategories: [], confidence: 0.5, rationale: "", keywords: [])
        _ = try repository.add(fileURL: URL(fileURLWithPath: "/2.pdf"), category: "cat", subcategories: [], confidence: 0.95, rationale: "", keywords: [])
        
        let deleted = try repository.deleteByStatus(.pending)
        
        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(try repository.count(), 1)
    }
}

// MARK: - Integration Tests

final class PersistenceIntegrationTests: XCTestCase {
    
    var database: SortAIDatabase!
    
    override func setUp() async throws {
        database = try SortAIDatabase.inMemory()
    }
    
    override func tearDown() async throws {
        database = nil
    }
    
    /// Tests the full workflow: create category -> create file entity -> link them -> add feedback -> learn
    func testFullWorkflow() throws {
        let entityRepo = database.entities
        let relationshipRepo = RelationshipRepository(database: database)
        let feedbackRepo = database.feedback
        let recordRepo = database.records
        
        // 1. Create category hierarchy
        let categoryPath = CategoryPath(path: "Work / Documents / Reports")
        let categoryEntity = try entityRepo.getOrCreateCategoryPath(categoryPath)
        XCTAssertNotNil(categoryEntity.id)
        
        // 2. Create file entity
        let fileEntity = try entityRepo.findOrCreate(type: .file, name: "quarterly-report.pdf", metadata: ["path": "/reports/quarterly-report.pdf"])
        
        // 3. Create relationship between file and category
        let relationship = try relationshipRepo.create(
            sourceId: fileEntity.id!,
            targetId: categoryEntity.id!,
            type: .belongsTo
        )
        XCTAssertNotNil(relationship.id)
        
        // 4. Add feedback item
        let feedbackItem = try feedbackRepo.add(
            fileURL: URL(fileURLWithPath: "/reports/quarterly-report.pdf"),
            category: "Work",
            subcategories: ["Documents", "Reports"],
            confidence: 0.7,
            rationale: "Contains financial data",
            keywords: ["quarterly", "revenue", "expenses"],
            fileEntityId: fileEntity.id
        )
        
        // 5. Human accepts the suggestion
        _ = try feedbackRepo.acceptSuggestion(itemId: feedbackItem.id!)
        
        // 6. Record human confirmation in knowledge graph
        try relationshipRepo.recordHumanConfirmation(fileId: fileEntity.id!, categoryId: categoryEntity.id!)
        
        // 7. Save processing record
        let record = ProcessingRecord(
            fileURL: URL(fileURLWithPath: "/reports/quarterly-report.pdf"),
            checksum: "sha256abc",
            mediaKind: .document,
            assignedCategory: categoryPath.description,
            confidence: 0.7
        )
        _ = try recordRepo.save(record)
        
        // 8. Verify the graph
        let confirmedRelationships = try relationshipRepo.getFrom(sourceId: fileEntity.id!, type: .humanConfirmed)
        XCTAssertEqual(confirmedRelationships.count, 1)
        
        // 9. Verify feedback statistics
        let stats = try feedbackRepo.statistics()
        XCTAssertEqual(stats.humanAccepted, 1)
        
        // 10. Verify database statistics
        let dbStats = try database.statistics()
        XCTAssertGreaterThan(dbStats.entityCount, 0)
        XCTAssertGreaterThan(dbStats.relationshipCount, 0)
    }
    
    /// Tests keyword suggestion learning and retrieval
    func testKeywordSuggestionLearning() throws {
        let entityRepo = database.entities
        let relationshipRepo = RelationshipRepository(database: database)
        
        // Create categories
        let programmingCategory = try entityRepo.getOrCreateCategoryPath(CategoryPath(path: "Tech / Programming"))
        let webDevCategory = try entityRepo.getOrCreateCategoryPath(CategoryPath(path: "Tech / Web Development"))
        
        // Create keywords
        let swiftKeyword = try entityRepo.findOrCreate(type: .keyword, name: "swift")
        let javascriptKeyword = try entityRepo.findOrCreate(type: .keyword, name: "javascript")
        let reactKeyword = try entityRepo.findOrCreate(type: .keyword, name: "react")
        
        // Learn keyword -> category associations
        try relationshipRepo.learnKeywordSuggestion(keywordId: swiftKeyword.id!, categoryId: programmingCategory.id!, weight: 0.9)
        try relationshipRepo.learnKeywordSuggestion(keywordId: javascriptKeyword.id!, categoryId: webDevCategory.id!, weight: 0.8)
        try relationshipRepo.learnKeywordSuggestion(keywordId: reactKeyword.id!, categoryId: webDevCategory.id!, weight: 0.85)
        
        // Query suggestions for keywords
        let suggestions = try relationshipRepo.getSuggestedCategories(for: [javascriptKeyword.id!, reactKeyword.id!])
        
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.entityId, webDevCategory.id)  // Both JS and React suggest webdev
        XCTAssertEqual(suggestions.first?.totalWeight ?? 0, 1.65, accuracy: 0.01)  // 0.8 + 0.85
    }
    
    /// Tests pattern matching with vector similarity
    func testPatternMatchingWorkflow() throws {
        let patternRepo = PatternRepository(database: database, embeddingDimensions: 128, similarityThreshold: 0.8)
        
        // Create patterns for different categories
        var workEmbedding = [Float](repeating: 0.1, count: 128)
        workEmbedding[0...9] = [0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1, 0.0][...]
        
        var personalEmbedding = [Float](repeating: 0.1, count: 128)
        personalEmbedding[0...9] = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9][...]
        
        _ = try patternRepo.save(LearnedPattern(checksum: "work1", embedding: Array(workEmbedding), label: "work"))
        _ = try patternRepo.save(LearnedPattern(checksum: "personal1", embedding: Array(personalEmbedding), label: "personal"))
        
        // Query with similar-to-work embedding
        var queryEmbedding = [Float](repeating: 0.1, count: 128)
        queryEmbedding[0...9] = [0.88, 0.78, 0.68, 0.58, 0.48, 0.38, 0.28, 0.18, 0.08, 0.02][...]
        
        let match = try patternRepo.findBestMatch(for: queryEmbedding)
        
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.pattern.label, "work")
        
        // Record hit and verify
        try patternRepo.recordHit(patternId: match!.pattern.id)
        let updated = try patternRepo.get(id: match!.pattern.id)
        XCTAssertEqual(updated?.hitCount, 1)
    }
    
    /// Tests concurrent access to database
    func testConcurrentAccess() async throws {
        let entityRepo = database.entities
        
        // Spawn multiple concurrent tasks
        await withTaskGroup(of: Entity?.self) { group in
            for i in 0..<50 {
                group.addTask {
                    try? entityRepo.findOrCreate(type: .category, name: "Concurrent Category \(i % 10)")
                }
            }
            
            var results: [Entity?] = []
            for await result in group {
                results.append(result)
            }
            
            // All operations should succeed
            XCTAssertEqual(results.compactMap { $0 }.count, 50)
        }
        
        // Should have exactly 10 unique categories
        let categories = try entityRepo.getAllCategories()
        XCTAssertEqual(categories.count, 10)
    }
    
    /// Tests foreign key cascading delete
    func testCascadingDelete() throws {
        let entityRepo = database.entities
        let relationshipRepo = RelationshipRepository(database: database)
        
        // Create entities
        let file = try entityRepo.findOrCreate(type: .file, name: "test.pdf")
        let category = try entityRepo.findOrCreate(type: .category, name: "Test Category")
        
        // Create relationship
        _ = try relationshipRepo.create(sourceId: file.id!, targetId: category.id!, type: .belongsTo)
        
        // Verify relationship exists
        XCTAssertEqual(try relationshipRepo.count(), 1)
        
        // Delete the file entity
        _ = try entityRepo.delete(id: file.id!)
        
        // Relationship should be cascade deleted
        XCTAssertEqual(try relationshipRepo.count(), 0)
    }
}

