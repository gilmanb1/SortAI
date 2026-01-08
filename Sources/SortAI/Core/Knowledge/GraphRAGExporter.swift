// MARK: - GraphRAG Exporter
// Export and import learned patterns and knowledge graph data

import Foundation
import GRDB

// MARK: - Export Format

/// Portable format for exporting/importing GraphRAG data
struct GraphRAGExport: Codable, Sendable {
    let version: Int
    let exportedAt: Date
    let appVersion: String
    
    // Knowledge Graph
    let entities: [ExportedEntity]
    let relationships: [ExportedRelationship]
    
    // Learned Patterns
    let patterns: [ExportedPattern]
    
    // Statistics
    let statistics: ExportStatistics
    
    static let currentVersion = 1
}

// MARK: - Exported Models

struct ExportedEntity: Codable, Sendable {
    let id: Int64
    let type: String
    let name: String
    let normalizedName: String
    let metadata: [String: String]?
    let usageCount: Int
    let createdAt: Date
}

struct ExportedRelationship: Codable, Sendable {
    let sourceId: Int64
    let targetId: Int64
    let type: String
    let weight: Double
    let metadata: [String: String]?
    let createdAt: Date
}

struct ExportedPattern: Codable, Sendable {
    let id: String
    let checksum: String
    let label: String
    let originalLabel: String?
    let confidence: Double
    let hitCount: Int
    let embeddingBase64: String  // Base64-encoded embedding
    let createdAt: Date
}

struct ExportStatistics: Codable, Sendable {
    let entityCount: Int
    let relationshipCount: Int
    let patternCount: Int
    let categoryCount: Int
    let keywordCount: Int
    let averageConfidence: Double
}

// MARK: - Export Errors

enum ExportError: LocalizedError {
    case exportFailed(String)
    case importFailed(String)
    case versionMismatch(expected: Int, found: Int)
    case dataCorruption(String)
    case fileWriteError(String)
    case fileReadError(String)
    
    var errorDescription: String? {
        switch self {
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        case .versionMismatch(let expected, let found):
            return "Version mismatch: expected \(expected), found \(found)"
        case .dataCorruption(let reason):
            return "Data corruption: \(reason)"
        case .fileWriteError(let reason):
            return "File write error: \(reason)"
        case .fileReadError(let reason):
            return "File read error: \(reason)"
        }
    }
}

// MARK: - GraphRAG Exporter

/// Exports and imports GraphRAG data for portability and backup
actor GraphRAGExporter {
    
    // MARK: - Properties
    
    private let database: SortAIDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    // MARK: - Initialization
    
    init(database: SortAIDatabase = .shared) {
        self.database = database
        
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Export
    
    /// Export all GraphRAG data to a portable format
    func export() async throws -> GraphRAGExport {
        // Fetch all data
        let entities = try await fetchAllEntities()
        let relationships = try await fetchAllRelationships()
        let patterns = try await fetchAllPatterns()
        
        // Calculate statistics
        let stats = calculateStatistics(
            entities: entities,
            relationships: relationships,
            patterns: patterns
        )
        
        return GraphRAGExport(
            version: GraphRAGExport.currentVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            entities: entities,
            relationships: relationships,
            patterns: patterns,
            statistics: stats
        )
    }
    
    /// Export to a JSON file
    func exportToFile(url: URL) async throws {
        let export = try await export()
        let data = try encoder.encode(export)
        
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.fileWriteError(error.localizedDescription)
        }
    }
    
    /// Export to a compressed archive
    func exportToArchive(url: URL) async throws {
        let export = try await export()
        let data = try encoder.encode(export)
        
        // Compress using gzip
        let compressedData = try (data as NSData).compressed(using: .lzfse) as Data
        
        do {
            try compressedData.write(to: url, options: .atomic)
        } catch {
            throw ExportError.fileWriteError(error.localizedDescription)
        }
    }
    
    // MARK: - Import
    
    /// Import GraphRAG data from portable format
    func `import`(_ export: GraphRAGExport, merge: Bool = true) async throws -> ImportResult {
        // Version check
        guard export.version <= GraphRAGExport.currentVersion else {
            throw ExportError.versionMismatch(
                expected: GraphRAGExport.currentVersion,
                found: export.version
            )
        }
        
        var result = ImportResult()
        
        // Create ID mapping for entities (old ID -> new ID)
        var entityIdMap: [Int64: Int64] = [:]
        
        // Import entities
        for entity in export.entities {
            do {
                let newId = try await importEntity(entity, merge: merge)
                entityIdMap[entity.id] = newId
                result.entitiesImported += 1
            } catch {
                result.entitiesSkipped += 1
            }
        }
        
        // Import relationships (using mapped IDs)
        for relationship in export.relationships {
            guard let newSourceId = entityIdMap[relationship.sourceId],
                  let newTargetId = entityIdMap[relationship.targetId] else {
                result.relationshipsSkipped += 1
                continue
            }
            
            do {
                try await importRelationship(relationship, sourceId: newSourceId, targetId: newTargetId, merge: merge)
                result.relationshipsImported += 1
            } catch {
                result.relationshipsSkipped += 1
            }
        }
        
        // Import patterns
        for pattern in export.patterns {
            do {
                try await importPattern(pattern, merge: merge)
                result.patternsImported += 1
            } catch {
                result.patternsSkipped += 1
            }
        }
        
        return result
    }
    
    /// Import from a JSON file
    func importFromFile(url: URL, merge: Bool = true) async throws -> ImportResult {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ExportError.fileReadError(error.localizedDescription)
        }
        
        let export = try decoder.decode(GraphRAGExport.self, from: data)
        return try await `import`(export, merge: merge)
    }
    
    /// Import from a compressed archive
    func importFromArchive(url: URL, merge: Bool = true) async throws -> ImportResult {
        let compressedData: Data
        do {
            compressedData = try Data(contentsOf: url)
        } catch {
            throw ExportError.fileReadError(error.localizedDescription)
        }
        
        // Decompress
        let data = try (compressedData as NSData).decompressed(using: .lzfse) as Data
        let export = try decoder.decode(GraphRAGExport.self, from: data)
        return try await `import`(export, merge: merge)
    }
    
    // MARK: - Private Methods
    
    private func fetchAllEntities() async throws -> [ExportedEntity] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, type, name, normalizedName, metadata, usageCount, createdAt
                FROM entities
                ORDER BY id
            """)
            
            return rows.map { row in
                let metadataJSON = row["metadata"] as? String
                let metadata: [String: String]? = metadataJSON.flatMap {
                    try? JSONDecoder().decode([String: String].self, from: $0.data(using: .utf8)!)
                }
                
                return ExportedEntity(
                    id: row["id"],
                    type: row["type"],
                    name: row["name"],
                    normalizedName: row["normalizedName"],
                    metadata: metadata,
                    usageCount: row["usageCount"],
                    createdAt: row["createdAt"]
                )
            }
        }
    }
    
    private func fetchAllRelationships() async throws -> [ExportedRelationship] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT sourceId, targetId, type, weight, metadata, createdAt
                FROM relationships
                ORDER BY id
            """)
            
            return rows.map { row in
                let metadataJSON = row["metadata"] as? String
                let metadata: [String: String]? = metadataJSON.flatMap {
                    try? JSONDecoder().decode([String: String].self, from: $0.data(using: .utf8)!)
                }
                
                return ExportedRelationship(
                    sourceId: row["sourceId"],
                    targetId: row["targetId"],
                    type: row["type"],
                    weight: row["weight"],
                    metadata: metadata,
                    createdAt: row["createdAt"]
                )
            }
        }
    }
    
    private func fetchAllPatterns() async throws -> [ExportedPattern] {
        try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, checksum, embeddingData, label, originalLabel, confidence, hitCount, createdAt
                FROM learned_patterns
                ORDER BY createdAt
            """)
            
            return rows.map { row in
                let embeddingData: Data = row["embeddingData"]
                let embeddingBase64 = embeddingData.base64EncodedString()
                
                return ExportedPattern(
                    id: row["id"],
                    checksum: row["checksum"],
                    label: row["label"],
                    originalLabel: row["originalLabel"],
                    confidence: row["confidence"],
                    hitCount: row["hitCount"],
                    embeddingBase64: embeddingBase64,
                    createdAt: row["createdAt"]
                )
            }
        }
    }
    
    private func importEntity(_ entity: ExportedEntity, merge: Bool) async throws -> Int64 {
        try database.write { db in
            // Check if entity exists (by normalized name and type)
            let existing = try Row.fetchOne(db, sql: """
                SELECT id FROM entities 
                WHERE type = ? AND normalizedName = ?
            """, arguments: [entity.type, entity.normalizedName])
            
            if let existingId: Int64 = existing?["id"] {
                if merge {
                    // Update usage count
                    try db.execute(sql: """
                        UPDATE entities 
                        SET usageCount = usageCount + ?, updatedAt = ?
                        WHERE id = ?
                    """, arguments: [entity.usageCount, Date(), existingId])
                }
                return existingId
            } else {
                // Insert new entity
                let metadataJSON = entity.metadata.flatMap {
                    try? JSONEncoder().encode($0)
                }.flatMap { String(data: $0, encoding: .utf8) }
                
                try db.execute(sql: """
                    INSERT INTO entities (type, name, normalizedName, metadata, usageCount, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    entity.type,
                    entity.name,
                    entity.normalizedName,
                    metadataJSON,
                    entity.usageCount,
                    entity.createdAt,
                    Date()
                ])
                
                return db.lastInsertedRowID
            }
        }
    }
    
    private func importRelationship(_ rel: ExportedRelationship, sourceId: Int64, targetId: Int64, merge: Bool) async throws {
        try database.write { db in
            // Check if relationship exists
            let existing = try Row.fetchOne(db, sql: """
                SELECT id, weight FROM relationships 
                WHERE sourceId = ? AND targetId = ? AND type = ?
            """, arguments: [sourceId, targetId, rel.type])
            
            if let existingId: Int64 = existing?["id"] {
                if merge {
                    let existingWeight: Double = existing?["weight"] ?? 0
                    let newWeight = max(existingWeight, rel.weight)
                    
                    try db.execute(sql: """
                        UPDATE relationships 
                        SET weight = ?, updatedAt = ?
                        WHERE id = ?
                    """, arguments: [newWeight, Date(), existingId])
                }
            } else {
                let metadataJSON = rel.metadata.flatMap {
                    try? JSONEncoder().encode($0)
                }.flatMap { String(data: $0, encoding: .utf8) }
                
                try db.execute(sql: """
                    INSERT INTO relationships (sourceId, targetId, type, weight, metadata, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    sourceId,
                    targetId,
                    rel.type,
                    rel.weight,
                    metadataJSON,
                    rel.createdAt,
                    Date()
                ])
            }
        }
    }
    
    private func importPattern(_ pattern: ExportedPattern, merge: Bool) async throws {
        try database.write { db in
            // Check if pattern exists (by checksum)
            let existing = try Row.fetchOne(db, sql: """
                SELECT id, hitCount FROM learned_patterns WHERE checksum = ?
            """, arguments: [pattern.checksum])
            
            if existing != nil {
                if merge {
                    // Hit count merging - existing hitCount is updated via SQL
                    try db.execute(sql: """
                        UPDATE learned_patterns 
                        SET hitCount = hitCount + ?, updatedAt = ?
                        WHERE checksum = ?
                    """, arguments: [pattern.hitCount, Date(), pattern.checksum])
                }
            } else {
                guard let embeddingData = Data(base64Encoded: pattern.embeddingBase64) else {
                    throw ExportError.dataCorruption("Invalid embedding data for pattern \(pattern.id)")
                }
                
                try db.execute(sql: """
                    INSERT INTO learned_patterns (id, checksum, embeddingData, label, originalLabel, confidence, hitCount, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    pattern.id,
                    pattern.checksum,
                    embeddingData,
                    pattern.label,
                    pattern.originalLabel,
                    pattern.confidence,
                    pattern.hitCount,
                    pattern.createdAt,
                    Date()
                ])
            }
        }
    }
    
    private func calculateStatistics(
        entities: [ExportedEntity],
        relationships: [ExportedRelationship],
        patterns: [ExportedPattern]
    ) -> ExportStatistics {
        let categoryCount = entities.filter { $0.type == "category" }.count
        let keywordCount = entities.filter { $0.type == "keyword" }.count
        
        let avgConfidence = patterns.isEmpty ? 0 :
            patterns.reduce(0.0) { $0 + $1.confidence } / Double(patterns.count)
        
        return ExportStatistics(
            entityCount: entities.count,
            relationshipCount: relationships.count,
            patternCount: patterns.count,
            categoryCount: categoryCount,
            keywordCount: keywordCount,
            averageConfidence: avgConfidence
        )
    }
}

// MARK: - Import Result

struct ImportResult: Sendable {
    var entitiesImported: Int = 0
    var entitiesSkipped: Int = 0
    var relationshipsImported: Int = 0
    var relationshipsSkipped: Int = 0
    var patternsImported: Int = 0
    var patternsSkipped: Int = 0
    
    var totalImported: Int {
        entitiesImported + relationshipsImported + patternsImported
    }
    
    var totalSkipped: Int {
        entitiesSkipped + relationshipsSkipped + patternsSkipped
    }
    
    var summary: String {
        """
        Import Complete:
        - Entities: \(entitiesImported) imported, \(entitiesSkipped) skipped
        - Relationships: \(relationshipsImported) imported, \(relationshipsSkipped) skipped
        - Patterns: \(patternsImported) imported, \(patternsSkipped) skipped
        Total: \(totalImported) imported, \(totalSkipped) skipped
        """
    }
}

// MARK: - Convenience Extensions

extension GraphRAGExporter {
    
    /// Quick export to user's Documents folder
    func quickExport() async throws -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let dateString = dateFormatter.string(from: Date())
        
        let exportURL = documentsURL.appendingPathComponent("SortAI_Export_\(dateString).json")
        try await exportToFile(url: exportURL)
        return exportURL
    }
    
    /// Get export preview (statistics only, no data)
    func previewExport() async throws -> ExportStatistics {
        let export = try await export()
        return export.statistics
    }
}

