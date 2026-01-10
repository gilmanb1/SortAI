// MARK: - Apple NL Embedding Service
// Uses NaturalLanguage framework for fast, on-device embeddings
// Standardizes to 512 dimensions with optional weighted combination

import Foundation
import NaturalLanguage

// MARK: - Embedding Service

/// Service for generating embeddings using Apple's NaturalLanguage framework
actor AppleNLEmbeddingService {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        let targetDimensions: Int
        let combineWithNGram: Bool
        let ngramWeight: Double  // Weight for NGram (1 - this = Apple weight)
        let language: NLLanguage
        
        static let `default` = Configuration(
            targetDimensions: 512,
            combineWithNGram: true,
            ngramWeight: 0.4,  // 40% NGram, 60% Apple
            language: .english
        )
        
        static let appleOnly = Configuration(
            targetDimensions: 512,
            combineWithNGram: false,
            ngramWeight: 0.0,
            language: .english
        )
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private var embedding: NLEmbedding?
    private let ngramGenerator: NGramEmbeddingGenerator
    
    /// Native dimension of Apple's word embeddings
    private let appleDimension = 300  // NLEmbedding uses 300-dim vectors
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .default) {
        self.config = configuration
        self.ngramGenerator = NGramEmbeddingGenerator()
        
        // Pre-load embedding
        Task {
            await loadEmbedding()
        }
    }
    
    private func loadEmbedding() {
        if embedding == nil {
            embedding = NLEmbedding.wordEmbedding(for: config.language)
            
            if embedding != nil {
                NSLog("✅ [NLEmbedding] Loaded word embedding for %@", config.language.rawValue)
            } else {
                NSLog("⚠️ [NLEmbedding] Word embedding not available for %@", config.language.rawValue)
            }
        }
    }
    
    // MARK: - Public API
    
    /// Generate embedding for text
    /// - Parameter text: Text to embed
    /// - Returns: 512-dimensional embedding vector
    func embed(text: String) async -> [Float] {
        loadEmbedding()
        
        // Get Apple embedding
        let appleEmbedding = generateAppleEmbedding(for: text)
        
        // If not combining, just normalize and return
        guard config.combineWithNGram else {
            return normalizeToTargetDimensions(appleEmbedding)
        }
        
        // Get NGram embedding
        let ngramEmbedding = ngramGenerator.embed(filename: text)
        
        // Combine embeddings
        return combineEmbeddings(apple: appleEmbedding, ngram: ngramEmbedding)
    }
    
    /// Generate embedding for a file (uses filename + content preview)
    func embedFile(filename: String, contentPreview: String?) async -> [Float] {
        var text = filename
        
        if let preview = contentPreview, !preview.isEmpty {
            text += " " + preview.prefix(500)
        }
        
        return await embed(text: text)
    }
    
    /// Calculate cosine similarity between two embeddings
    func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }
    
    /// Find most similar embeddings from a list
    func findSimilar(
        to query: [Float],
        candidates: [(id: String, embedding: [Float])],
        topK: Int = 5
    ) -> [(id: String, similarity: Float)] {
        var results: [(id: String, similarity: Float)] = []
        
        for candidate in candidates {
            let sim = similarity(query, candidate.embedding)
            results.append((candidate.id, sim))
        }
        
        return results.sorted { $0.similarity > $1.similarity }.prefix(topK).map { $0 }
    }
    
    /// Check if NLEmbedding is available
    func isAvailable() -> Bool {
        loadEmbedding()
        return embedding != nil
    }
    
    // MARK: - Private Implementation
    
    /// Generate Apple NLEmbedding vector
    private func generateAppleEmbedding(for text: String) -> [Double] {
        guard let embedding = embedding else {
            // Return zero vector if embedding not available
            return [Double](repeating: 0, count: appleDimension)
        }
        
        // Tokenize text
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = text
        
        var wordVectors: [[Double]] = []
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                            unit: .word,
                            scheme: .tokenType,
                            options: [.omitWhitespace, .omitPunctuation]) { _, tokenRange in
            let word = String(text[tokenRange]).lowercased()
            if let vector = embedding.vector(for: word) {
                wordVectors.append(vector)
            }
            return true
        }
        
        // If no words found, return zero vector
        guard !wordVectors.isEmpty else {
            return [Double](repeating: 0, count: appleDimension)
        }
        
        // Average all word vectors
        var averaged = [Double](repeating: 0, count: appleDimension)
        
        for vector in wordVectors {
            for i in 0..<min(appleDimension, vector.count) {
                averaged[i] += vector[i]
            }
        }
        
        let count = Double(wordVectors.count)
        for i in 0..<averaged.count {
            averaged[i] /= count
        }
        
        return averaged
    }
    
    /// Normalize embedding to target dimensions
    private func normalizeToTargetDimensions(_ embedding: [Double]) -> [Float] {
        var result = embedding.map { Float($0) }
        
        // Pad with zeros if needed
        if result.count < config.targetDimensions {
            result.append(contentsOf: [Float](repeating: 0, count: config.targetDimensions - result.count))
        }
        
        // Truncate if needed
        if result.count > config.targetDimensions {
            result = Array(result.prefix(config.targetDimensions))
        }
        
        // L2 normalize
        let norm = sqrt(result.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            result = result.map { $0 / norm }
        }
        
        return result
    }
    
    /// Combine Apple and NGram embeddings
    private func combineEmbeddings(apple: [Double], ngram: [Float]) -> [Float] {
        // Normalize both to target dimensions
        let appleNormalized = normalizeToTargetDimensions(apple)
        
        var ngramPadded = ngram
        if ngramPadded.count < config.targetDimensions {
            ngramPadded.append(contentsOf: [Float](repeating: 0, count: config.targetDimensions - ngramPadded.count))
        } else if ngramPadded.count > config.targetDimensions {
            ngramPadded = Array(ngramPadded.prefix(config.targetDimensions))
        }
        
        // Weighted combination
        let appleWeight = Float(1.0 - config.ngramWeight)
        let ngramWeight = Float(config.ngramWeight)
        
        var combined = [Float](repeating: 0, count: config.targetDimensions)
        for i in 0..<config.targetDimensions {
            combined[i] = appleNormalized[i] * appleWeight + ngramPadded[i] * ngramWeight
        }
        
        // L2 normalize the result
        let norm = sqrt(combined.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            combined = combined.map { $0 / norm }
        }
        
        return combined
    }
}

// MARK: - Sentence Embedding

extension AppleNLEmbeddingService {
    /// Generate sentence embedding using NLEmbedding.sentenceEmbedding (if available)
    @available(macOS 11.0, *)
    func embedSentence(text: String) async -> [Float]? {
        // Try to get sentence embedding
        guard let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: config.language) else {
            return nil
        }
        
        guard let vector = sentenceEmbedding.vector(for: text) else {
            return nil
        }
        
        return normalizeToTargetDimensions(vector)
    }
}

// MARK: - Batch Processing

extension AppleNLEmbeddingService {
    /// Embed multiple texts in batch
    func embedBatch(texts: [String]) async -> [[Float]] {
        var results: [[Float]] = []
        
        for text in texts {
            let embedding = await embed(text: text)
            results.append(embedding)
        }
        
        return results
    }
    
    /// Background job to re-embed existing files with Apple embeddings
    func reembedFiles(
        fileStore: EmbeddingCacheStore,
        batchSize: Int = 50,
        progressHandler: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws {
        // Get files that need re-embedding
        let files = try await fileStore.getFilesNeedingReembedding(limit: batchSize)
        let total = files.count
        
        for (index, file) in files.enumerated() {
            let embedding = await embed(text: file.text)
            try await fileStore.updateEmbedding(fileId: file.id, embedding: embedding)
            
            progressHandler?(index + 1, total)
        }
        
        NSLog("✅ [NLEmbedding] Re-embedded %d files", total)
    }
}

// MARK: - Embedding Cache Store Protocol

/// Protocol for stores that can hold file embeddings
protocol EmbeddingCacheStore: Sendable {
    func getFilesNeedingReembedding(limit: Int) async throws -> [(id: Int64, text: String)]
    func updateEmbedding(fileId: Int64, embedding: [Float]) async throws
}

