// MARK: - Deep Analyzer
// Performs deep content analysis on files with low categorization confidence

import Foundation

// MARK: - Deep Analyzer

/// Performs deep content analysis using MediaInspector and LLM
/// for files that couldn't be confidently categorized by filename alone
actor DeepAnalyzer {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// Confidence threshold below which deep analysis is triggered
        let confidenceThreshold: Double
        
        /// Maximum concurrent deep analysis tasks
        let maxConcurrent: Int
        
        /// Timeout per file (seconds)
        let timeoutPerFile: TimeInterval
        
        /// Whether to extract audio from video files
        let extractAudio: Bool
        
        /// Whether to perform OCR on images/PDFs
        let performOCR: Bool
        
        /// Use hybrid extraction (quick first, full if still low confidence)
        let useHybridExtraction: Bool
        
        /// Confidence threshold to trigger full extraction after quick pass
        let fullExtractionThreshold: Double
        
        static let `default` = Configuration(
            confidenceThreshold: 0.75,
            maxConcurrent: 2,
            timeoutPerFile: 120.0,
            extractAudio: true,
            performOCR: true,
            useHybridExtraction: true,
            fullExtractionThreshold: 0.6
        )
        
        static let fast = Configuration(
            confidenceThreshold: 0.75,
            maxConcurrent: 3,
            timeoutPerFile: 60.0,
            extractAudio: false,
            performOCR: true,
            useHybridExtraction: false,
            fullExtractionThreshold: 0.6
        )
        
        static let thorough = Configuration(
            confidenceThreshold: 0.75,
            maxConcurrent: 1,
            timeoutPerFile: 300.0,
            extractAudio: true,
            performOCR: true,
            useHybridExtraction: true,
            fullExtractionThreshold: 0.5
        )
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private let inspector: MediaInspector
    private let llmProvider: any LLMProvider
    private var activeTaskCount = 0
    
    // MARK: - Initialization
    
    init(
        configuration: Configuration = .default,
        inspector: MediaInspector = MediaInspector(),
        llmProvider: any LLMProvider
    ) {
        self.config = configuration
        self.inspector = inspector
        self.llmProvider = llmProvider
    }
    
    // MARK: - Analysis
    
    /// Analyze a file deeply and return enhanced categorization
    func analyze(file: TaxonomyScannedFile, existingCategories: [String]) async throws -> DeepAnalysisResult {
        let overallStart = Date()
        NSLog("🔬 [DeepAnalyzer] Starting analysis of: \(file.filename)")
        
        // Wait if too many concurrent tasks
        var waitTime: TimeInterval = 0
        while activeTaskCount >= config.maxConcurrent {
            try await Task.sleep(for: .milliseconds(100))
            waitTime += 0.1
            if waitTime > 1.0 && Int(waitTime * 10) % 50 == 0 {
                NSLog("⏳ [DeepAnalyzer] Waiting for slot... (\(String(format: "%.1f", waitTime))s, active: \(activeTaskCount)/\(config.maxConcurrent))")
            }
        }
        
        if waitTime > 0.5 {
            NSLog("⏳ [DeepAnalyzer] Wait complete after \(String(format: "%.1f", waitTime))s")
        }
        
        activeTaskCount += 1
        defer { 
            activeTaskCount -= 1
            let totalDuration = Date().timeIntervalSince(overallStart)
            NSLog("✅ [DeepAnalyzer] Completed \(file.filename) in \(String(format: "%.2f", totalDuration))s")
        }
        
        // Extract content using MediaInspector
        let inspectStart = Date()
        NSLog("🔍 [DeepAnalyzer] Inspecting file content...")
        let signature = try await inspector.insp/sldnfafnect(url: file.url)
        let inspectDuration = Date().timeIntervalSince(inspectStart)
        NSLog("🔍 [DeepAnalyzer] Inspection complete in \(String(format: "%.2f", inspectDuration))s - kind: \(signature.kind.rawValue), textCue: \(signature.textualCue.count) chars, tags: \(signature.sceneTags.count)")
        
        // Build enhanced prompt with content
        let prompt = buildAnalysisPrompt(
            filename: file.filename,
            signature: signature,
            existingCategories: existingCategories
        )
        NSLog("📝 [DeepAnalyzer] Prompt built: \(prompt.count) chars")
        
        // Get LLM categorization
        let llmStart = Date()
        NSLog("🤖 [DeepAnalyzer] Sending to LLM...")
        let options = LLMOptions.default(model: "llama3.2")
        let response = try await llmProvider.completeJSON(prompt: prompt, options: options)
        let llmDuration = Date().timeIntervalSince(llmStart)
        NSLog("🤖 [DeepAnalyzer] LLM response in \(String(format: "%.2f", llmDuration))s - \(response.count) chars")
        
        let result = try parseAnalysisResponse(response, filename: file.filename)
        NSLog("📊 [DeepAnalyzer] Result: \(result.pathString) (confidence: \(String(format: "%.0f", result.confidence * 100))%%)")
        
        return result
    }
    
    /// Analyze multiple files, returning only those that need recategorization
    func analyzeFiles(
        _ files: [TaxonomyScannedFile],
        existingCategories: [String],
        progressCallback: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> [DeepAnalysisResult] {
        let batchStart = Date()
        NSLog("🔬 [DeepAnalyzer] ========== BATCH ANALYSIS START ==========")
        NSLog("🔬 [DeepAnalyzer] Files to analyze: \(files.count)")
        NSLog("🔬 [DeepAnalyzer] Existing categories: \(existingCategories.count)")
        NSLog("🔬 [DeepAnalyzer] Config: maxConcurrent=\(config.maxConcurrent), timeout=\(config.timeoutPerFile)s, audio=\(config.extractAudio), ocr=\(config.performOCR)")
        
        var results: [DeepAnalysisResult] = []
        var successCount = 0
        var failureCount = 0
        
        for (index, file) in files.enumerated() {
            progressCallback(index, files.count)
            NSLog("🔬 [DeepAnalyzer] Processing [\(index + 1)/\(files.count)]: \(file.filename)")
            
            do {
                let result = try await analyze(file: file, existingCategories: existingCategories)
                results.append(result)
                successCount += 1
            } catch {
                failureCount += 1
                NSLog("❌ [DeepAnalyzer] FAILED \(file.filename): \(error.localizedDescription)")
            }
        }
        
        progressCallback(files.count, files.count)
        
        let batchDuration = Date().timeIntervalSince(batchStart)
        NSLog("🔬 [DeepAnalyzer] ========== BATCH ANALYSIS COMPLETE ==========")
        NSLog("🔬 [DeepAnalyzer] Total time: \(String(format: "%.2f", batchDuration))s")
        NSLog("🔬 [DeepAnalyzer] Success: \(successCount), Failed: \(failureCount)")
        if !results.isEmpty {
            let avgTime = batchDuration / Double(results.count)
            NSLog("🔬 [DeepAnalyzer] Avg per file: \(String(format: "%.2f", avgTime))s")
        }
        
        return results
    }
    
    // MARK: - Prompt Building
    
    private func buildAnalysisPrompt(
        filename: String,
        signature: FileSignature,
        existingCategories: [String]
    ) -> String {
        var prompt = """
        You are a file categorization expert. Analyze this file's CONTENT to determine its category.
        
        FILE: \(filename)
        TYPE: \(signature.kind.rawValue)
        
        """
        
        // Add content-specific information
        if !signature.textualCue.isEmpty {
            let preview = String(signature.textualCue.prefix(2000))
            prompt += """
            
            EXTRACTED TEXT CONTENT:
            \(preview)
            
            """
        }
        
        if !signature.sceneTags.isEmpty {
            prompt += """
            
            VISUAL CONTENT TAGS: \(signature.sceneTags.prefix(10).joined(separator: ", "))
            
            """
        }
        
        if !signature.detectedObjects.isEmpty {
            prompt += """
            
            DETECTED OBJECTS: \(signature.detectedObjects.prefix(10).joined(separator: ", "))
            
            """
        }
        
        if let duration = signature.duration {
            prompt += """
            
            DURATION: \(Int(duration / 60)) minutes \(Int(duration.truncatingRemainder(dividingBy: 60))) seconds
            
            """
        }
        
        // Add existing categories
        if !existingCategories.isEmpty {
            prompt += """
            
            EXISTING CATEGORIES (prefer these if content matches):
            \(existingCategories.prefix(20).joined(separator: "\n"))
            
            """
        }
        
        prompt += """
        
        Based on the actual CONTENT (not just filename), categorize this file.
        
        Return JSON:
        {
            "categoryPath": ["Main", "Sub1", "Sub2"],
            "confidence": 0.95,
            "rationale": "Why this category based on content",
            "contentSummary": "Brief summary of what the file contains",
            "suggestedTags": ["tag1", "tag2"]
        }
        """
        
        return prompt
    }
    
    // MARK: - Response Parsing
    
    private func parseAnalysisResponse(_ response: String, filename: String) throws -> DeepAnalysisResult {
        let cleaned = cleanJSON(response)
        
        guard let data = cleaned.data(using: .utf8) else {
            throw DeepAnalysisError.invalidResponse("Invalid UTF-8")
        }
        
        struct Response: Decodable {
            let categoryPath: [String]
            let confidence: Double
            let rationale: String?
            let contentSummary: String?
            let suggestedTags: [String]?
        }
        
        let parsed = try JSONDecoder().decode(Response.self, from: data)
        
        return DeepAnalysisResult(
            filename: filename,
            categoryPath: parsed.categoryPath,
            confidence: parsed.confidence,
            rationale: parsed.rationale ?? "",
            contentSummary: parsed.contentSummary ?? "",
            suggestedTags: parsed.suggestedTags ?? []
        )
    }
    
    private func cleanJSON(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleaned.hasPrefix("```") {
            if let start = cleaned.range(of: "\n"),
               let end = cleaned.range(of: "```", options: .backwards) {
                cleaned = String(cleaned[start.upperBound..<end.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return cleaned
    }
}

// MARK: - Deep Analysis Result

struct DeepAnalysisResult: Sendable, Identifiable {
    let id: UUID
    let filename: String
    let categoryPath: [String]
    let confidence: Double
    let rationale: String
    let contentSummary: String
    let suggestedTags: [String]
    
    init(
        filename: String,
        categoryPath: [String],
        confidence: Double,
        rationale: String,
        contentSummary: String,
        suggestedTags: [String]
    ) {
        self.id = UUID()
        self.filename = filename
        self.categoryPath = categoryPath
        self.confidence = confidence
        self.rationale = rationale
        self.contentSummary = contentSummary
        self.suggestedTags = suggestedTags
    }
    
    var pathString: String {
        categoryPath.joined(separator: " / ")
    }
}

// MARK: - Deep Analysis Errors

enum DeepAnalysisError: LocalizedError {
    case invalidResponse(String)
    case timeout
    case extractionFailed(String)
    case llmUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let reason):
            return "Invalid response: \(reason)"
        case .timeout:
            return "Analysis timed out"
        case .extractionFailed(let reason):
            return "Content extraction failed: \(reason)"
        case .llmUnavailable:
            return "LLM provider unavailable"
        }
    }
}

