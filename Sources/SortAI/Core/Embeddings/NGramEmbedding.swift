// MARK: - N-Gram Embedding Generator
// Implements character and word n-grams for lightweight embeddings
// Spec requirement: "lightweight sentence transformer plus character/word n-grams"

import Foundation

// MARK: - N-Gram Configuration

struct NGramConfiguration: Sendable {
    /// Character n-gram sizes (e.g., 2, 3, 4)
    let charNGramSizes: [Int]
    
    /// Word n-gram sizes (e.g., 1, 2, 3)
    let wordNGramSizes: [Int]
    
    /// Output embedding dimensions
    let dimensions: Int
    
    /// Weight for character n-grams (vs word n-grams)
    let charWeight: Float
    
    /// Whether to use hash-based dimensionality reduction
    let useHashing: Bool
    
    /// Minimum character n-gram frequency to include
    let minCharNGramFreq: Int
    
    static let `default` = NGramConfiguration(
        charNGramSizes: [2, 3, 4],
        wordNGramSizes: [1, 2],
        dimensions: 384,
        charWeight: 0.3,
        useHashing: true,
        minCharNGramFreq: 1
    )
    
    static let lightweight = NGramConfiguration(
        charNGramSizes: [3],
        wordNGramSizes: [1, 2],
        dimensions: 256,
        charWeight: 0.25,
        useHashing: true,
        minCharNGramFreq: 1
    )
}

// MARK: - N-Gram Embedding Generator

/// Generates embeddings using character and word n-grams
/// This provides a lightweight, offline-capable embedding method
struct NGramEmbeddingGenerator: Sendable {
    
    private let config: NGramConfiguration
    
    init(configuration: NGramConfiguration = .default) {
        self.config = configuration
    }
    
    // MARK: - Main Embedding Generation
    
    /// Generate embedding for a filename
    func embed(filename: String) -> [Float] {
        // Preprocess filename
        let normalized = normalizeFilename(filename)
        
        // Generate character n-grams
        let charEmbedding = generateCharNGramEmbedding(normalized)
        
        // Generate word n-grams
        let wordEmbedding = generateWordNGramEmbedding(normalized)
        
        // Combine with weights
        return combineEmbeddings(
            char: charEmbedding,
            word: wordEmbedding,
            charWeight: config.charWeight
        )
    }
    
    /// Generate embedding for text (filename + context)
    func embed(filename: String, parentFolder: String? = nil, extension ext: String? = nil) -> [Float] {
        var components: [String] = []
        
        // Add parent folder context
        if let parent = parentFolder, !parent.isEmpty {
            components.append(parent)
        }
        
        // Add filename
        components.append(filename)
        
        // Add extension emphasis
        if let ext = ext, !ext.isEmpty {
            components.append(ext)
            components.append(ext)  // Double weight for extension
        }
        
        let combined = components.joined(separator: " ")
        let normalized = normalizeFilename(combined)
        
        let charEmbedding = generateCharNGramEmbedding(normalized)
        let wordEmbedding = generateWordNGramEmbedding(normalized)
        
        return combineEmbeddings(
            char: charEmbedding,
            word: wordEmbedding,
            charWeight: config.charWeight
        )
    }
    
    // MARK: - Filename Preprocessing
    
    private func normalizeFilename(_ filename: String) -> String {
        var result = filename.lowercased()
        
        // Remove extension
        if let dotIndex = result.lastIndex(of: ".") {
            let ext = String(result[dotIndex...])
            if ext.count <= 5 {  // Likely a file extension
                result = String(result[..<dotIndex])
            }
        }
        
        // Split camelCase and PascalCase
        result = splitCamelCase(result)
        
        // Replace common separators with spaces
        result = result.replacingOccurrences(of: "_", with: " ")
        result = result.replacingOccurrences(of: "-", with: " ")
        result = result.replacingOccurrences(of: ".", with: " ")
        
        // Remove special characters but keep alphanumerics and spaces
        result = result.filter { $0.isLetter || $0.isNumber || $0 == " " }
        
        // Normalize whitespace
        result = result.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return result
    }
    
    private func splitCamelCase(_ text: String) -> String {
        var result = ""
        var previousWasLower = false
        
        for char in text {
            if char.isUppercase && previousWasLower {
                result += " "
            }
            result += String(char)
            previousWasLower = char.isLowercase
        }
        
        return result
    }
    
    // MARK: - Character N-Gram Embedding
    
    private func generateCharNGramEmbedding(_ text: String) -> [Float] {
        var embedding = [Float](repeating: 0, count: config.dimensions)
        var totalNGrams = 0
        
        let paddedText = "^^" + text + "$$"  // Add boundary markers
        let chars = Array(paddedText)
        
        for n in config.charNGramSizes {
            guard chars.count >= n else { continue }
            
            for i in 0...(chars.count - n) {
                let ngram = String(chars[i..<(i + n)])
                let (index, value) = hashNGram(ngram, dimensions: config.dimensions)
                embedding[index] += value
                totalNGrams += 1
            }
        }
        
        // Normalize
        if totalNGrams > 0 {
            let scale = 1.0 / Float(totalNGrams)
            embedding = embedding.map { $0 * scale }
        }
        
        return l2Normalize(embedding)
    }
    
    // MARK: - Word N-Gram Embedding
    
    private func generateWordNGramEmbedding(_ text: String) -> [Float] {
        var embedding = [Float](repeating: 0, count: config.dimensions)
        var totalNGrams = 0
        
        let words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        
        for n in config.wordNGramSizes {
            guard words.count >= n else { continue }
            
            for i in 0...(words.count - n) {
                let ngram = words[i..<(i + n)].joined(separator: "_")
                let (index, value) = hashNGram(ngram, dimensions: config.dimensions)
                embedding[index] += value
                totalNGrams += 1
            }
        }
        
        // Normalize
        if totalNGrams > 0 {
            let scale = 1.0 / Float(totalNGrams)
            embedding = embedding.map { $0 * scale }
        }
        
        return l2Normalize(embedding)
    }
    
    // MARK: - Hashing
    
    /// Hash n-gram to embedding index and value using feature hashing
    private func hashNGram(_ ngram: String, dimensions: Int) -> (index: Int, value: Float) {
        // Use two hashes for index and sign (feature hashing trick)
        var hasher1 = Hasher()
        hasher1.combine(ngram)
        let hash1 = abs(hasher1.finalize())
        
        var hasher2 = Hasher()
        hasher2.combine(ngram)
        hasher2.combine("sign_salt")
        let hash2 = hasher2.finalize()
        
        let index = hash1 % dimensions
        let sign: Float = (hash2 % 2 == 0) ? 1.0 : -1.0
        
        // TF-IDF-like weighting based on n-gram length
        let weight = 1.0 / Float(ngram.count).squareRoot()
        
        return (index, sign * weight)
    }
    
    // MARK: - Combination
    
    private func combineEmbeddings(char: [Float], word: [Float], charWeight: Float) -> [Float] {
        let wordWeight = 1.0 - charWeight
        
        var combined = [Float](repeating: 0, count: config.dimensions)
        for i in 0..<config.dimensions {
            combined[i] = char[i] * charWeight + word[i] * wordWeight
        }
        
        return l2Normalize(combined)
    }
    
    // MARK: - Normalization
    
    private func l2Normalize(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }
}

// MARK: - Batch Processing

extension NGramEmbeddingGenerator {
    
    /// Generate embeddings for multiple filenames
    func embedBatch(_ filenames: [String]) -> [[Float]] {
        filenames.map { embed(filename: $0) }
    }
    
    /// Generate embeddings with file context
    func embedBatch(_ files: [(filename: String, parentFolder: String?, extension: String?)]) -> [[Float]] {
        files.map { embed(filename: $0.filename, parentFolder: $0.parentFolder, extension: $0.extension) }
    }
}

// MARK: - Similarity

extension NGramEmbeddingGenerator {
    
    /// Calculate cosine similarity between two embeddings
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
    
    /// Find k-nearest neighbors
    static func findNearest(
        query: [Float],
        candidates: [[Float]],
        k: Int = 5
    ) -> [(index: Int, similarity: Float)] {
        var results: [(index: Int, similarity: Float)] = []
        
        for (i, candidate) in candidates.enumerated() {
            let sim = cosineSimilarity(query, candidate)
            results.append((i, sim))
        }
        
        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(k)
            .map { $0 }
    }
}

