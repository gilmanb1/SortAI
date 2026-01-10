// MARK: - GraphRAG Enhancer
// Uses Apple Intelligence to extract entities and relationships
// Enhances the existing KnowledgeGraph with LLM-powered analysis

import Foundation
import GRDB
import NaturalLanguage

// MARK: - GraphRAG Enhancer

/// Enhances KnowledgeGraph with AI-powered entity and relationship extraction
actor GraphRAGEnhancer {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        let minEntityConfidence: Double
        let minRelationshipConfidence: Double
        let maxEntitiesPerDocument: Int
        let maxRelationshipsPerDocument: Int
        let enableRelationshipInference: Bool
        
        static let `default` = Configuration(
            minEntityConfidence: 0.6,
            minRelationshipConfidence: 0.5,
            maxEntitiesPerDocument: 50,
            maxRelationshipsPerDocument: 100,
            enableRelationshipInference: true
        )
    }
    
    // MARK: - Properties
    
    private let graphStore: KnowledgeGraphStore
    private let config: Configuration
    private var categorizationService: UnifiedCategorizationService?
    
    // MARK: - Initialization
    
    init(graphStore: KnowledgeGraphStore, configuration: Configuration = .default) {
        self.graphStore = graphStore
        self.config = configuration
    }
    
    /// Set the categorization service (must be called before extracting with AI)
    func setCategorizationService(_ service: UnifiedCategorizationService) {
        self.categorizationService = service
    }
    
    // MARK: - Entity Extraction
    
    /// Extract entities from text using the best available provider
    func extractEntities(from text: String, fileURL: URL) async throws -> [ExtractedEntity] {
        guard let service = categorizationService else {
            // Fall back to NLTagger-only extraction
            return extractEntitiesWithNLTagger(from: text)
        }
        
        // Try to get entities from the unified service
        var entities = try await service.extractEntities(from: text)
        
        // Filter by confidence
        entities = entities.filter { $0.confidence >= config.minEntityConfidence }
        
        // Limit count
        if entities.count > config.maxEntitiesPerDocument {
            entities = Array(entities.prefix(config.maxEntitiesPerDocument))
        }
        
        NSLog("🔍 [GraphRAGEnhancer] Extracted %d entities from %@", entities.count, fileURL.lastPathComponent)
        
        return entities
    }
    
    /// Extract entities using NLTagger (fallback)
    private func extractEntitiesWithNLTagger(from text: String) -> [ExtractedEntity] {
        var entities: [ExtractedEntity] = []
        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = text
        
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                            unit: .word,
                            scheme: .nameType,
                            options: options) { tag, tokenRange in
            if let tag = tag {
                let entityType: ExtractedEntityType? = switch tag {
                case .personalName: .person
                case .organizationName: .organization
                case .placeName: .location
                default: nil
                }
                
                if let type = entityType {
                    entities.append(ExtractedEntity(
                        text: String(text[tokenRange]),
                        type: type,
                        confidence: 0.7  // NLTagger confidence is estimated
                    ))
                }
            }
            return true
        }
        
        // Also extract nouns as potential keywords
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                            unit: .word,
                            scheme: .lexicalClass,
                            options: options) { tag, tokenRange in
            if tag == .noun {
                let word = String(text[tokenRange])
                // Only add if significant (3+ chars) and not already present
                if word.count >= 3 && !entities.contains(where: { $0.text.lowercased() == word.lowercased() }) {
                    entities.append(ExtractedEntity(
                        text: word,
                        type: .keyword,
                        confidence: 0.6
                    ))
                }
            }
            return true
        }
        
        return entities
    }
    
    // MARK: - Relationship Extraction
    
    /// Extract relationships using Apple Intelligence (if available)
    @available(macOS 26.0, *)
    func extractRelationships(
        from text: String,
        entities: [ExtractedEntity],
        fileURL: URL
    ) async throws -> [InferredRelationship] {
        guard config.enableRelationshipInference else { return [] }
        
        // Get Apple Intelligence provider
        let provider = AppleIntelligenceProvider()
        guard await provider.isAvailable() else {
            NSLog("⚠️ [GraphRAGEnhancer] Apple Intelligence not available for relationship extraction")
            return []
        }
        
        // Extract relationships using Apple Intelligence
        let relationshipItems = try await provider.extractRelationships(from: text, entities: entities)
        
        // Convert to InferredRelationship
        var relationships: [InferredRelationship] = []
        
        for item in relationshipItems {
            guard item.confidence >= config.minRelationshipConfidence else { continue }
            
            let relType: RelationshipType = switch item.relationshipType.lowercased() {
            case "works_for": .mentions
            case "located_in": .relatedTo
            case "related_to": .relatedTo
            case "mentions": .mentions
            case "authored_by": .mentions
            case "part_of": .relatedTo
            default: .relatedTo
            }
            
            relationships.append(InferredRelationship(
                sourceEntityText: item.source,
                targetEntityText: item.target,
                type: relType,
                confidence: item.confidence
            ))
        }
        
        // Limit count
        if relationships.count > config.maxRelationshipsPerDocument {
            relationships = Array(relationships.prefix(config.maxRelationshipsPerDocument))
        }
        
        NSLog("🔗 [GraphRAGEnhancer] Extracted %d relationships from %@", relationships.count, fileURL.lastPathComponent)
        
        return relationships
    }
    
    // MARK: - Graph Population
    
    /// Process a file and populate the knowledge graph
    func processFile(
        url: URL,
        textContent: String,
        categoryPath: CategoryPath,
        keywords: [String]
    ) async throws {
        // 1. Extract entities
        let entities = try await extractEntities(from: textContent, fileURL: url)
        
        // 2. Create file entity
        let fileEntity = try graphStore.findOrCreateEntity(
            type: .file, 
            name: url.lastPathComponent,
            metadata: [
                "path": url.path,
                "processedAt": ISO8601DateFormatter().string(from: Date())
            ]
        )
        guard let fileId = fileEntity.id else { return }
        
        // 3. Create/link category entities
        var parentCategoryId: Int64? = nil
        for component in categoryPath.components {
            let categoryEntity = try graphStore.findOrCreateEntity(type: .category, name: component)
            guard let categoryId = categoryEntity.id else { continue }
            
            // Link file to category
            _ = try graphStore.createRelationship(
                sourceId: fileId,
                targetId: categoryId,
                type: .belongsTo,
                weight: 0.9
            )
            
            // Link category hierarchy
            if let parentId = parentCategoryId {
                _ = try graphStore.createRelationship(
                    sourceId: categoryId,
                    targetId: parentId,
                    type: .isChildOf,
                    weight: 1.0
                )
            }
            parentCategoryId = categoryId
        }
        
        // 4. Add extracted entities
        for extracted in entities {
            let entityType = extracted.type.toEntityType
            let entity = try graphStore.findOrCreateEntity(type: entityType, name: extracted.text)
            guard let entityId = entity.id else { continue }
            
            // Link to file
            let relType: RelationshipType = switch extracted.type {
            case .person: .mentions
            case .keyword: .hasKeyword
            case .topic: .relatedTo
            default: .relatedTo
            }
            
            _ = try graphStore.createRelationship(
                sourceId: fileId,
                targetId: entityId,
                type: relType,
                weight: extracted.confidence
            )
        }
        
        // 5. Add keywords
        for keyword in keywords {
            let keywordEntity = try graphStore.findOrCreateEntity(type: .keyword, name: keyword)
            guard let keywordId = keywordEntity.id else { continue }
            
            _ = try graphStore.createRelationship(
                sourceId: fileId,
                targetId: keywordId,
                type: .hasKeyword,
                weight: 0.8
            )
            
            // Link keyword to category (for future suggestions)
            if let categoryId = parentCategoryId {
                _ = try graphStore.createRelationship(
                    sourceId: keywordId,
                    targetId: categoryId,
                    type: .suggestsCategory,
                    weight: 0.5
                )
            }
        }
        
        // 6. Extract and add relationships (macOS 26+)
        if #available(macOS 26.0, *) {
            let relationships = try await extractRelationships(from: textContent, entities: entities, fileURL: url)
            
            for rel in relationships {
                // Find or create source entity
                let sourceEntity = try graphStore.findOrCreateEntity(type: .keyword, name: rel.sourceEntityText)
                guard let sourceId = sourceEntity.id else { continue }
                
                // Find or create target entity
                let targetEntity = try graphStore.findOrCreateEntity(type: .keyword, name: rel.targetEntityText)
                guard let targetId = targetEntity.id else { continue }
                
                // Create relationship
                _ = try graphStore.createRelationship(
                    sourceId: sourceId,
                    targetId: targetId,
                    type: rel.type,
                    weight: rel.confidence
                )
            }
        }
        
        NSLog("✅ [GraphRAGEnhancer] Processed %@ into knowledge graph", url.lastPathComponent)
    }
    
    // MARK: - Category Suggestions
    
    /// Get category suggestions based on entities and keywords
    /// Uses the knowledge graph's existing getSuggestedCategories method
    func suggestCategories(
        forEntities entities: [ExtractedEntity],
        keywords: [String]
    ) async throws -> [(CategoryPath, Double)] {
        // Combine entity texts with keywords
        var allKeywords = keywords
        allKeywords.append(contentsOf: entities.map { $0.text })
        
        // Use the existing graph method
        let suggestions = try graphStore.getSuggestedCategories(for: allKeywords, limit: 10)
        
        // Convert to CategoryPath tuples
        return suggestions.map { entity, score in
            (CategoryPath(path: entity.name), score)
        }
    }
    
    // MARK: - Learning
    
    /// Record human feedback for learning
    func recordFeedback(
        fileURL: URL,
        acceptedCategory: CategoryPath,
        wasCorrection: Bool
    ) async throws {
        let fileEntity = try graphStore.findOrCreateEntity(type: .file, name: fileURL.lastPathComponent)
        guard let fileId = fileEntity.id else { return }
        
        // Create/get category entity
        var lastCategoryId: Int64? = nil
        for component in acceptedCategory.components {
            let categoryEntity = try graphStore.findOrCreateEntity(type: .category, name: component)
            lastCategoryId = categoryEntity.id
        }
        
        guard let categoryId = lastCategoryId else { return }
        
        // Record the feedback
        let relType: RelationshipType = wasCorrection ? .humanConfirmed : .humanConfirmed
        let weight = wasCorrection ? 1.0 : 0.9  // Corrections carry more weight
        
        _ = try graphStore.createRelationship(
            sourceId: fileId,
            targetId: categoryId,
            type: relType,
            weight: weight,
            metadata: ["feedbackAt": ISO8601DateFormatter().string(from: Date())]
        )
        
        // If correction, also boost keyword-category links
        // Note: This would require additional methods on KnowledgeGraphStore
        // that we'll leave for a future enhancement
        
        NSLog("📝 [GraphRAGEnhancer] Recorded feedback for %@ -> %@", 
              fileURL.lastPathComponent, acceptedCategory.description)
    }
}

// MARK: - Inferred Relationship

/// A relationship inferred by AI analysis
struct InferredRelationship: Sendable {
    let sourceEntityText: String
    let targetEntityText: String
    let type: RelationshipType
    let confidence: Double
}

// MARK: - Future Extensions
// The KnowledgeGraphStore extension methods for advanced GraphRAG queries 
// (findRelatedCategories, findCategoriesSuggestedBy, etc.) should be added 
// directly to KnowledgeGraph.swift in a future enhancement.

