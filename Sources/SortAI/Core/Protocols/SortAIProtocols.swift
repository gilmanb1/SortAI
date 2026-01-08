// MARK: - SortAI Core Protocols
// Protocol-based abstractions enabling dependency injection, testing, and extensibility
// These protocols define the contract for each major component in the pipeline

import Foundation

// MARK: - File Routing Protocol

/// Protocol for routing files to appropriate inspection strategies
/// Implementations determine how files are classified and processed
protocol FileRouting: Sendable {
    /// Determines the inspection strategy for a given file URL
    /// - Parameter url: The file URL to analyze
    /// - Returns: The appropriate inspection strategy
    /// - Throws: RouterError if the file type is unsupported
    func route(url: URL) async throws -> InspectionStrategy
    
    /// Returns the media kind for a given file URL
    /// - Parameter url: The file URL to analyze
    /// - Returns: The media kind (document, video, image, audio, unknown)
    func mediaKind(for url: URL) async -> MediaKind
}

// MARK: - Media Inspection Protocol

/// Protocol for inspecting and extracting signals from media files
/// Implementations extract metadata, content, and features from various file types
protocol MediaInspecting: Sendable {
    /// Inspects a file and returns a unified signature containing extracted signals
    /// - Parameter url: The file URL to inspect
    /// - Returns: A FileSignature containing all extracted information
    /// - Throws: InspectorError if inspection fails
    func inspect(url: URL) async throws -> FileSignature
}

// MARK: - Categorization Protocol

/// Protocol for AI-based file categorization
/// Implementations use LLMs or other AI systems to determine file categories
protocol FileCategorizing: Sendable {
    /// Categorizes a file based on its extracted signature
    /// - Parameter signature: The file's extracted features and content
    /// - Returns: Categorization result with category, confidence, and rationale
    /// - Throws: BrainError if categorization fails
    func categorize(signature: FileSignature) async throws -> EnhancedBrainResult
    
    /// Performs a health check to verify the categorization service is available
    /// - Returns: true if the service is healthy and ready
    func healthCheck() async -> Bool
    
    /// Gets existing categories for context and suggestions
    /// - Parameter limit: Maximum number of categories to return
    /// - Returns: Array of category paths
    func getExistingCategories(limit: Int) async -> [CategoryPath]
}

// MARK: - Embedding Generation Protocol

/// Protocol for generating vector embeddings from text
/// Implementations convert text into numerical vectors for similarity search
protocol EmbeddingGenerating: Sendable {
    /// The dimensionality of generated embeddings
    var dimensions: Int { get }
    
    /// Generates an embedding vector for the given text
    /// - Parameter text: The text to embed
    /// - Returns: Array of floating point values representing the embedding
    /// - Throws: Error if embedding generation fails
    func generateEmbedding(for text: String) async throws -> [Float]
    
    /// Generates an embedding for a file signature by combining its features
    /// - Parameter signature: The file signature to embed
    /// - Returns: Array of floating point values representing the embedding
    /// - Throws: Error if embedding generation fails
    func generateEmbedding(for signature: FileSignature) async throws -> [Float]
}

// MARK: - Pattern Matching Protocol

/// Protocol for pattern-based file matching using learned patterns
/// Implementations store and retrieve patterns for similarity-based matching
protocol PatternMatching: Sendable {
    /// Queries for the nearest matching pattern to the given embedding
    /// - Parameters:
    ///   - embedding: The embedding vector to match against
    ///   - threshold: Minimum similarity score (0.0-1.0)
    /// - Returns: Optional tuple of (pattern, similarity) if a match is found
    /// - Throws: Error if query fails
    func queryNearest(embedding: [Float], threshold: Double) throws -> (LearnedPattern, Double)?
    
    /// Finds a pattern by exact file checksum
    /// - Parameter checksum: The file's checksum to look up
    /// - Returns: The matching pattern if found
    /// - Throws: Error if lookup fails
    func findByChecksum(_ checksum: String) throws -> LearnedPattern?
    
    /// Records a hit on a pattern (for tracking usage)
    /// - Parameter patternId: The pattern's identifier
    /// - Throws: Error if recording fails
    func recordHit(patternId: String) throws
    
    /// Saves a new pattern learned from a categorization result
    /// - Parameters:
    ///   - signature: The file signature that was categorized
    ///   - embedding: The embedding vector for the file
    ///   - label: The assigned category label
    ///   - originalLabel: The original label if corrected
    ///   - confidence: The confidence score
    /// - Throws: Error if saving fails
    func savePattern(
        signature: FileSignature,
        embedding: [Float],
        label: String,
        originalLabel: String?,
        confidence: Double
    ) throws
}

// MARK: - Knowledge Graph Protocol

/// Protocol for knowledge graph operations
/// Implementations manage entity relationships and category suggestions
protocol KnowledgeGraphing: Sendable {
    /// Gets suggested categories based on keywords
    /// - Parameters:
    ///   - keywords: Keywords extracted from file content
    ///   - limit: Maximum suggestions to return
    /// - Returns: Array of (entity, weight) tuples sorted by relevance
    /// - Throws: Error if query fails
    func getSuggestedCategories(for keywords: [String], limit: Int) throws -> [(Entity, Double)]
    
    /// Gets or creates a category path in the graph
    /// - Parameter path: The category path (e.g., "Work/Projects/2024")
    /// - Returns: The leaf entity of the path
    /// - Throws: Error if operation fails
    func getOrCreateCategoryPath(_ path: CategoryPath) throws -> Entity
    
    /// Records a human confirmation of a categorization
    /// - Parameters:
    ///   - fileId: The file entity ID
    ///   - categoryId: The confirmed category entity ID
    /// - Throws: Error if operation fails
    func recordHumanConfirmation(fileId: Int64, categoryId: Int64) throws
}

// MARK: - Feedback Management Protocol

/// Protocol for human-in-the-loop feedback management
/// Implementations manage the review queue and learning from corrections
protocol FeedbackManaging: Sendable {
    /// Adds a file to the feedback queue
    /// - Parameters:
    ///   - fileURL: The file URL
    ///   - category: Suggested category
    ///   - subcategories: Suggested subcategories
    ///   - confidence: Confidence score
    ///   - rationale: Explanation for the suggestion
    ///   - keywords: Extracted keywords
    /// - Returns: The created feedback item
    /// - Throws: Error if operation fails
    func addToQueue(
        fileURL: URL,
        category: String,
        subcategories: [String],
        confidence: Double,
        rationale: String,
        keywords: [String]
    ) async throws -> FeedbackItem
    
    /// Gets pending items for review
    /// - Parameter limit: Maximum items to return
    /// - Returns: Array of pending feedback items
    /// - Throws: Error if query fails
    func getPendingItems(limit: Int) throws -> [FeedbackItem]
    
    /// Accepts a suggested categorization
    /// - Parameter itemId: The feedback item ID
    /// - Throws: Error if operation fails
    func acceptSuggestion(itemId: Int64) async throws
    
    /// Records human correction with a different category
    /// - Parameters:
    ///   - itemId: The feedback item ID
    ///   - newCategory: The corrected category
    ///   - newSubcategories: The corrected subcategories
    ///   - notes: Optional feedback notes
    /// - Throws: Error if operation fails
    func correctCategory(
        itemId: Int64,
        newCategory: String,
        newSubcategories: [String],
        notes: String?
    ) async throws
    
    /// Gets queue statistics
    /// - Returns: Statistics about the feedback queue
    /// - Throws: Error if query fails
    func getQueueStats() throws -> QueueStatistics
}

// MARK: - File Organization Protocol

/// Protocol for organizing files into directory structures
/// Implementations handle copying, moving, or linking files
protocol FileOrganizing: Sendable {
    /// Organizes processed files to a destination
    /// - Parameters:
    ///   - results: Array of processing results to organize
    ///   - destination: The root destination directory
    ///   - mode: Organization mode (copy, move, symlink)
    /// - Returns: Summary of the organization operation
    /// - Throws: Error if organization fails
    func organize(
        results: [ProcessingResult],
        to destination: URL,
        mode: OrganizationMode
    ) async throws -> OrganizationSummary
}

// MARK: - Pipeline Protocol

/// Protocol for the main processing pipeline
/// Implementations orchestrate the complete file processing flow
protocol FileProcessing: Sendable {
    /// Processes a single file through the complete pipeline
    /// - Parameter url: The file URL to process
    /// - Returns: The processing result
    /// - Throws: PipelineError if processing fails
    func process(url: URL) async throws -> ProcessingResult
    
    /// Learns from a processing result and optional correction
    /// - Parameters:
    ///   - result: The original processing result
    ///   - correctedPath: Optional corrected category path
    /// - Throws: Error if learning fails
    func learnFromResult(_ result: ProcessingResult, correctedPath: CategoryPath?) async throws
    
    /// Gets processing statistics
    /// - Returns: Tuple of (totalProcessed, memoryHits, graphHits)
    func getStatistics() async -> (Int, Int, Int)
}

// MARK: - Component Factory Protocol

/// Protocol for creating pipeline components
/// Implementations provide dependency injection for testing and customization
protocol ComponentFactory: Sendable {
    /// Creates a file router instance
    func createRouter() -> any FileRouting
    
    /// Creates a media inspector instance
    func createInspector() -> any MediaInspecting
    
    /// Creates a categorizer instance with the given configuration
    func createCategorizer(configuration: BrainConfiguration) -> any FileCategorizing
    
    /// Creates an embedding generator with the given configuration
    func createEmbeddingGenerator(configuration: BrainConfiguration, dimensions: Int) -> any EmbeddingGenerating
    
    /// Creates a pattern matcher with the given configuration
    func createPatternMatcher(embeddingDimensions: Int, similarityThreshold: Double) throws -> any PatternMatching
}

// MARK: - Default Factory

/// Default factory implementation using production components
final class DefaultComponentFactory: ComponentFactory, Sendable {
    static let shared = DefaultComponentFactory()
    
    func createRouter() -> any FileRouting {
        FileRouter()
    }
    
    func createInspector() -> any MediaInspecting {
        MediaInspector()
    }
    
    func createCategorizer(configuration: BrainConfiguration) -> any FileCategorizing {
        Brain(configuration: configuration)
    }
    
    func createEmbeddingGenerator(configuration: BrainConfiguration, dimensions: Int) -> any EmbeddingGenerating {
        EmbeddingGenerator(configuration: configuration, dimensions: dimensions)
    }
    
    func createPatternMatcher(embeddingDimensions: Int, similarityThreshold: Double) throws -> any PatternMatching {
        try MemoryStore(embeddingDimensions: embeddingDimensions, similarityThreshold: similarityThreshold)
    }
}

