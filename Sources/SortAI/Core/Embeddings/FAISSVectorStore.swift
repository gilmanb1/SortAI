// MARK: - FAISS Vector Store
// Optional backend for fast vector similarity search
// Uses FAISS library when available, falls back to brute-force search

import Foundation

// MARK: - Vector Store Protocol

/// Protocol for vector similarity stores
protocol VectorStore: Actor, Sendable {
    /// Add vectors to the store
    func add(id: String, vector: [Float]) async throws
    
    /// Add multiple vectors at once
    func addBatch(vectors: [(id: String, vector: [Float])]) async throws
    
    /// Search for similar vectors
    func search(query: [Float], k: Int) async throws -> [(id: String, distance: Float)]
    
    /// Remove a vector by ID
    func remove(id: String) async throws
    
    /// Get total count of vectors
    func count() async -> Int
    
    /// Clear all vectors
    func clear() async throws
    
    /// Save index to disk
    func save(to path: URL) async throws
    
    /// Load index from disk
    func load(from path: URL) async throws
}

// MARK: - FAISS Store Status

/// Status of the FAISS backend
enum FAISSStatus: Sendable {
    case available
    case notInstalled
    case loadFailed(String)
}

// MARK: - FAISS Vector Store

/// Optional FAISS-backed vector store for high-performance similarity search
/// Falls back to brute-force search if FAISS is not available
actor FAISSVectorStore: VectorStore {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        let dimensions: Int
        let indexType: IndexType
        let nlistClusters: Int  // For IVF indexes
        let m: Int              // For HNSW indexes
        let efConstruction: Int // For HNSW indexes
        
        enum IndexType: String, Sendable {
            case flat = "Flat"              // Exact search (slow but accurate)
            case ivfFlat = "IVF,Flat"      // Inverted file index (faster)
            case hnsw = "HNSW"             // Hierarchical navigable small world (fastest)
        }
        
        static let `default` = Configuration(
            dimensions: 512,
            indexType: .flat,
            nlistClusters: 100,
            m: 32,
            efConstruction: 200
        )
        
        static let highPerformance = Configuration(
            dimensions: 512,
            indexType: .hnsw,
            nlistClusters: 100,
            m: 32,
            efConstruction: 200
        )
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private var vectors: [String: [Float]] = [:]  // Fallback storage
    private var vectorIds: [String] = []           // Ordered list for index mapping
    private(set) var status: FAISSStatus = .notInstalled
    private var faissIndex: Any? = nil             // Actual FAISS index (when available)
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .default) {
        self.config = configuration
        
        // Check if FAISS is available (nonisolated call)
        status = Self.checkFAISSAvailability()
        
        if case .available = status {
            NSLog("✅ [FAISSVectorStore] FAISS available, using optimized index")
        } else {
            NSLog("⚠️ [FAISSVectorStore] FAISS not available, using brute-force fallback")
        }
    }
    
    private nonisolated static func checkFAISSAvailability() -> FAISSStatus {
        // Check if FAISS library is loaded
        // In a real implementation, this would check for the FAISS dylib
        // For now, we'll use the fallback implementation
        return .notInstalled
    }
    
    // MARK: - VectorStore Protocol
    
    func add(id: String, vector: [Float]) async throws {
        guard vector.count == config.dimensions else {
            throw VectorStoreError.dimensionMismatch(expected: config.dimensions, got: vector.count)
        }
        
        // Remove existing if present
        if vectors[id] != nil {
            try await remove(id: id)
        }
        
        vectors[id] = vector
        vectorIds.append(id)
    }
    
    func addBatch(vectors: [(id: String, vector: [Float])]) async throws {
        for (id, vector) in vectors {
            try await add(id: id, vector: vector)
        }
    }
    
    func search(query: [Float], k: Int) async throws -> [(id: String, distance: Float)] {
        guard query.count == config.dimensions else {
            throw VectorStoreError.dimensionMismatch(expected: config.dimensions, got: query.count)
        }
        
        // Brute-force search (fallback)
        return bruteForceSearch(query: query, k: k)
    }
    
    func remove(id: String) async throws {
        vectors.removeValue(forKey: id)
        vectorIds.removeAll { $0 == id }
    }
    
    func count() async -> Int {
        vectors.count
    }
    
    func clear() async throws {
        vectors.removeAll()
        vectorIds.removeAll()
    }
    
    func save(to path: URL) async throws {
        // Save vectors to disk
        let data = VectorStoreData(
            dimensions: config.dimensions,
            vectors: vectors,
            vectorIds: vectorIds
        )
        
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(data)
        try encoded.write(to: path)
        
        NSLog("💾 [FAISSVectorStore] Saved %d vectors to %@", vectors.count, path.lastPathComponent)
    }
    
    func load(from path: URL) async throws {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw VectorStoreError.fileNotFound(path.path)
        }
        
        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        let storeData = try decoder.decode(VectorStoreData.self, from: data)
        
        guard storeData.dimensions == config.dimensions else {
            throw VectorStoreError.dimensionMismatch(expected: config.dimensions, got: storeData.dimensions)
        }
        
        vectors = storeData.vectors
        vectorIds = storeData.vectorIds
        
        NSLog("📂 [FAISSVectorStore] Loaded %d vectors from %@", vectors.count, path.lastPathComponent)
    }
    
    // MARK: - Brute Force Search
    
    private func bruteForceSearch(query: [Float], k: Int) -> [(id: String, distance: Float)] {
        var distances: [(id: String, distance: Float)] = []
        
        for id in vectorIds {
            guard let vector = vectors[id] else { continue }
            let distance = cosineDistance(query, vector)
            distances.append((id, distance))
        }
        
        // Sort by distance (lower is better for cosine distance)
        distances.sort { $0.distance < $1.distance }
        
        return Array(distances.prefix(k))
    }
    
    /// Calculate cosine distance (1 - cosine similarity)
    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return Float.infinity }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        let similarity = denominator > 0 ? dotProduct / denominator : 0
        
        return 1.0 - similarity  // Convert similarity to distance
    }
    
    // MARK: - Statistics
    
    /// Get memory usage estimate
    func memoryUsage() -> Int {
        // Each Float is 4 bytes
        return vectors.count * config.dimensions * 4
    }
    
    /// Check if using FAISS or fallback
    func isUsingFAISS() -> Bool {
        if case .available = status {
            return true
        }
        return false
    }
}

// MARK: - Storage Data

/// Serializable vector store data
private struct VectorStoreData: Codable {
    let dimensions: Int
    let vectors: [String: [Float]]
    let vectorIds: [String]
}

// MARK: - Errors

enum VectorStoreError: LocalizedError {
    case dimensionMismatch(expected: Int, got: Int)
    case fileNotFound(String)
    case indexNotBuilt
    case faissError(String)
    
    var errorDescription: String? {
        switch self {
        case .dimensionMismatch(let expected, let got):
            return "Vector dimension mismatch: expected \(expected), got \(got)"
        case .fileNotFound(let path):
            return "Vector store file not found: \(path)"
        case .indexNotBuilt:
            return "FAISS index not built. Add vectors first."
        case .faissError(let message):
            return "FAISS error: \(message)"
        }
    }
}

// MARK: - In-Memory Vector Store

/// Simple in-memory vector store (always available)
actor InMemoryVectorStore: VectorStore {
    private var vectors: [String: [Float]] = [:]
    private var vectorIds: [String] = []
    private let dimensions: Int
    
    init(dimensions: Int = 512) {
        self.dimensions = dimensions
    }
    
    func add(id: String, vector: [Float]) async throws {
        guard vector.count == dimensions else {
            throw VectorStoreError.dimensionMismatch(expected: dimensions, got: vector.count)
        }
        
        if vectors[id] != nil {
            try await remove(id: id)
        }
        
        vectors[id] = vector
        vectorIds.append(id)
    }
    
    func addBatch(vectors: [(id: String, vector: [Float])]) async throws {
        for (id, vector) in vectors {
            try await add(id: id, vector: vector)
        }
    }
    
    func search(query: [Float], k: Int) async throws -> [(id: String, distance: Float)] {
        var distances: [(id: String, distance: Float)] = []
        
        for id in vectorIds {
            guard let vector = vectors[id] else { continue }
            let distance = cosineDistance(query, vector)
            distances.append((id, distance))
        }
        
        distances.sort { $0.distance < $1.distance }
        return Array(distances.prefix(k))
    }
    
    func remove(id: String) async throws {
        vectors.removeValue(forKey: id)
        vectorIds.removeAll { $0 == id }
    }
    
    func count() async -> Int {
        vectors.count
    }
    
    func clear() async throws {
        vectors.removeAll()
        vectorIds.removeAll()
    }
    
    func save(to path: URL) async throws {
        let data = VectorStoreData(dimensions: dimensions, vectors: vectors, vectorIds: vectorIds)
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: path)
    }
    
    func load(from path: URL) async throws {
        let data = try Data(contentsOf: path)
        let storeData = try JSONDecoder().decode(VectorStoreData.self, from: data)
        
        guard storeData.dimensions == dimensions else {
            throw VectorStoreError.dimensionMismatch(expected: dimensions, got: storeData.dimensions)
        }
        
        vectors = storeData.vectors
        vectorIds = storeData.vectorIds
    }
    
    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<min(a.count, b.count) {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        return 1.0 - (denominator > 0 ? dotProduct / denominator : 0)
    }
}

// MARK: - Vector Store Factory

/// Factory for creating the appropriate vector store
enum VectorStoreFactory {
    /// Create a vector store based on configuration
    static func create(
        dimensions: Int = 512,
        useFAISS: Bool = false
    ) -> any VectorStore {
        if useFAISS {
            return FAISSVectorStore(configuration: .init(
                dimensions: dimensions,
                indexType: .flat,
                nlistClusters: 100,
                m: 32,
                efConstruction: 200
            ))
        }
        
        return InMemoryVectorStore(dimensions: dimensions)
    }
}

