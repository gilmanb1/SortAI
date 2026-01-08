# LLM Provider Research & Progressive Degradation Plan

## Current Architecture Analysis

### How SortAI Currently Handles Progressive Degradation

The application has a **partially implemented** progressive degradation system with the following components:

#### 1. LLM Routing Service (`LLMRoutingService.swift`)
- **Three modes**: `full`, `degraded`, `offline`
- Routes requests to available providers with exponential backoff
- Periodic health checks (every 30 seconds)
- Provider priority: prefers local over cloud when configured
- **Current limitation**: Only Ollama is registered as a provider

#### 2. Ollama Model Manager (`OllamaModelManager.swift`)
- Checks Ollama server availability at `http://127.0.0.1:11434`
- Model resolution with fallback chain: `deepseek-r1:8b` → `llama3.2` → `llama3.1` → `mistral` → `phi3`
- Auto-download capability for missing models
- **Current limitation**: If Ollama server is unavailable, the entire LLM stack fails

#### 3. Quick Categorizer (`QuickCategorizer.swift`)
- Filename pattern matching (regex-based)
- File extension categorization
- Returns immediate results with low confidence (0.1-0.65)
- **Used for**: Initial UI feedback before full analysis
- **Not used for**: Final categorization when LLM unavailable

#### 4. Degraded Mode UI (`DegradedModeUI.swift`)
- Alert dialog: "Wait & Retry" vs "Use Local-Only Mode"
- Status banner showing current mode (Full/Degraded/Offline/Recovering)
- Connection details sheet
- **Current limitation**: UI exists but isn't fully wired to the actual degradation logic

#### 5. Built-in ML Tools Already in Use
- **Vision Framework** (`VNClassifyImageRequest`): Image classification, object detection
- **NaturalLanguage Framework** (`NLTagger`): Lemmatization, keyword extraction
- **Speech Framework** (`SFSpeechRecognizer`): Audio transcription
- **AVFoundation**: Video/audio metadata extraction
- **PDFKit**: Document text extraction

### Current Degradation Flow (Actual)
```
Ollama Available?
    ├─ Yes → Full LLM categorization
    └─ No  → Error thrown, no fallback
```

### Current Degradation Flow (Intended but not fully implemented)
```
Ollama Available?
    ├─ Yes → Full LLM categorization
    └─ No  → Show "Use Local-Only Mode" dialog
                └─ Uses QuickCategorizer (filename-only)
```

---

## Apple Foundation Models Framework Research

### Overview

Apple introduced the **Foundation Models framework** at WWDC 2025 with iOS 26, iPadOS 26, and macOS 26 (Tahoe). This provides on-device access to a **3-billion parameter LLM** that powers Apple Intelligence.

**Source**: [Apple Developer Documentation - Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)

### Key Features

| Feature | Description |
|---------|-------------|
| **On-Device Processing** | All inference runs locally, ensuring privacy |
| **Guided Generation** | Ensures consistent response formats (JSON, enums) |
| **Tool Calling** | Model can request additional info from your app |
| **Streaming Output** | Real-time text generation |
| **Session Management** | Maintains conversation context |
| **Structured Output** | `@Generable` protocol for type-safe responses |

### Basic Usage Pattern

```swift
import FoundationModels

// Create a session
let session = LanguageModelSession()

// Simple text generation
let response = try await session.respond(to: "Categorize this file: quarterly_report.pdf")

// Streaming response
for try await chunk in session.streamRespond(to: prompt) {
    print(chunk)
}
```

### Structured Output with `@Generable`

```swift
@Generable
struct FileCategory {
    @Guide(description: "The category path like 'Documents / Financial / Reports'")
    var categoryPath: String
    
    @Guide(description: "Confidence from 0.0 to 1.0")
    var confidence: Double
    
    @Guide(description: "Explanation for the categorization")
    var rationale: String
    
    @Guide(description: "Relevant keywords extracted from the file")
    var keywords: [String]
}

// Usage
let category: FileCategory = try await session.respond(
    to: "Categorize: quarterly_report.pdf, contains 'Q4 2025 Revenue Summary'",
    generating: FileCategory.self
)
```

### System Requirements

| Platform | Minimum Version | Hardware Requirement |
|----------|-----------------|---------------------|
| macOS | 26.0 (Tahoe) | Apple Silicon (M1+) or Apple Intelligence-capable Intel |
| iOS | 26.0 | A17 Pro or newer |
| iPadOS | 26.0 | M1 chip or newer |

### Advantages Over Ollama

| Aspect | Apple Foundation Models | Ollama |
|--------|------------------------|--------|
| **Installation** | Built into OS | Requires separate install |
| **Dependencies** | Zero | Ollama server must be running |
| **Privacy** | Guaranteed on-device | On-device (but user manages) |
| **Type Safety** | Native Swift with `@Generable` | JSON parsing required |
| **Integration** | System-level | Network API |
| **Model Size** | ~3B parameters, optimized | User chooses (2B-70B+) |
| **Speed** | Hardware-accelerated Neural Engine | GPU/CPU |
| **Availability** | Always available on supported hardware | May fail to start |

### Limitations

1. **OS Version Requirement**: macOS 26+ only (not available on current macOS 15)
2. **Hardware Requirement**: Apple Silicon or Apple Intelligence-capable device
3. **Model Selection**: Cannot choose specific models (only Apple's built-in)
4. **Customization**: Less control over temperature, top-p, etc.
5. **Model Quality**: 3B parameters may be less capable than larger Ollama models

### Quality Assessment for File Categorization

Based on the documentation and model capabilities:

| Task | Apple Foundation Models (3B) | Ollama deepseek-r1:8b | Assessment |
|------|------------------------------|----------------------|------------|
| Filename parsing | ✅ Excellent | ✅ Excellent | Both suitable |
| Content summarization | ✅ Good | ✅ Excellent | Ollama slightly better |
| Category suggestion | ✅ Good | ✅ Excellent | Both suitable |
| JSON output reliability | ✅ Excellent (native) | ⚠️ Good (needs parsing) | Apple better |
| Long-form transcription analysis | ⚠️ Limited context | ✅ Good | Ollama better |
| Batch processing speed | ✅ Fast (Neural Engine) | ⚠️ Moderate | Apple faster |

**Conclusion**: Apple Foundation Models would provide **comparable results** for typical file categorization tasks, with **better reliability** (always available, type-safe) but potentially **less nuanced** categorization for complex content.

---

## Implementation Plan: Progressive Degradation Cascade

### Proposed Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    LLM Provider Cascade                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Level 1: Apple Foundation Models (macOS 26+)                   │
│    • Best: Zero dependencies, always available on new hardware  │
│    • Fallback if: OS version < 26 or unsupported hardware       │
│                           ↓                                     │
│  Level 2: Ollama (Local LLM Server)                             │
│    • Good: More powerful models, user-configurable              │
│    • Fallback if: Server not running or no models available     │
│                           ↓                                     │
│  Level 3: Local ML + Heuristics                                 │
│    • Acceptable: Vision, NaturalLanguage, filename patterns     │
│    • Fallback if: (this is the final local fallback)            │
│                           ↓                                     │
│  Level 4: Error State                                           │
│    • Show user actionable error with recovery options           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Detailed Implementation Plan

#### Phase 1: Abstract LLM Provider Interface

**Files to create/modify:**
- `Sources/SortAI/Core/LLM/LLMProviderProtocol.swift` (update existing)

```swift
protocol LLMCategorizationProvider: Sendable {
    var identifier: String { get }
    var priority: Int { get }  // Lower = higher priority
    
    func isAvailable() async -> Bool
    func categorize(signature: FileSignature) async throws -> EnhancedBrainResult
}
```

#### Phase 2: Apple Foundation Models Provider

**Files to create:**
- `Sources/SortAI/Core/LLM/AppleFoundationModelsProvider.swift`

**Implementation outline:**
```swift
@available(macOS 26.0, *)
actor AppleFoundationModelsProvider: LLMCategorizationProvider {
    let identifier = "apple-foundation"
    let priority = 1  // Highest priority
    
    private var session: LanguageModelSession?
    
    func isAvailable() async -> Bool {
        // Check if device supports Apple Intelligence
        return LanguageModelSession.isSupported
    }
    
    func categorize(signature: FileSignature) async throws -> EnhancedBrainResult {
        let session = try await getOrCreateSession()
        
        // Build prompt similar to current Brain implementation
        let prompt = buildCategorizationPrompt(signature: signature)
        
        // Use structured output for reliable JSON
        let result: FileCategoryResponse = try await session.respond(
            to: prompt,
            generating: FileCategoryResponse.self
        )
        
        return EnhancedBrainResult(
            categoryPath: CategoryPath(path: result.categoryPath),
            confidence: result.confidence,
            rationale: result.rationale,
            extractedKeywords: result.keywords,
            suggestedFromGraph: false
        )
    }
}
```

#### Phase 3: Enhanced Local ML Provider

**Files to create:**
- `Sources/SortAI/Core/LLM/LocalMLProvider.swift`

**Components to combine:**
1. `QuickCategorizer` - filename patterns
2. `Vision` framework - image classification
3. `NaturalLanguage` - keyword/entity extraction
4. `ConfidenceService` - prototype matching
5. `KnowledgeGraph` - learned patterns

**Implementation outline:**
```swift
actor LocalMLProvider: LLMCategorizationProvider {
    let identifier = "local-ml"
    let priority = 3  // Fallback priority
    
    private let quickCategorizer: QuickCategorizer
    private let confidenceService: ConfidenceService
    private let knowledgeGraph: KnowledgeGraphStore?
    
    func isAvailable() async -> Bool {
        return true  // Always available
    }
    
    func categorize(signature: FileSignature) async throws -> EnhancedBrainResult {
        var confidence: Double = 0.0
        var category = "Uncategorized"
        var subcategories: [String] = []
        var rationale = "Local ML analysis"
        var keywords: [String] = []
        
        // 1. Check knowledge graph for learned patterns
        if let graphMatch = await knowledgeGraph?.findSimilarPatterns(signature) {
            if graphMatch.confidence > 0.7 {
                return graphMatch.result
            }
            confidence = max(confidence, graphMatch.confidence * 0.8)
        }
        
        // 2. Filename pattern matching
        let quickResult = await quickCategorizer.categorize(url: signature.url)
        if quickResult.confidence > confidence {
            category = quickResult.category
            subcategories = quickResult.subcategory.map { [$0] } ?? []
            confidence = quickResult.confidence
            rationale = quickResult.source.rawValue
        }
        
        // 3. For images, use Vision classification
        if signature.kind == .image, let visionResult = try? await classifyImage(signature) {
            keywords += visionResult.labels
            if visionResult.confidence > confidence {
                // Map Vision labels to categories
                (category, subcategories) = mapVisionLabelsToCategory(visionResult.labels)
                confidence = visionResult.confidence
                rationale = "Vision framework classification"
            }
        }
        
        // 4. Extract keywords from text content
        if let textContent = signature.textContent {
            let extractedKeywords = extractKeywords(from: textContent)
            keywords += extractedKeywords
            
            // Use NL framework entity recognition
            let entities = extractEntities(from: textContent)
            if let entityCategory = inferCategoryFromEntities(entities) {
                if entityCategory.confidence > confidence {
                    category = entityCategory.category
                    subcategories = entityCategory.subcategories
                    confidence = entityCategory.confidence
                    rationale = "Entity recognition"
                }
            }
        }
        
        // 5. Boost confidence if multiple signals agree
        confidence = min(confidence * 1.2, 0.85)  // Cap at 0.85 for local-only
        
        return EnhancedBrainResult(
            categoryPath: CategoryPath(components: [category] + subcategories),
            confidence: confidence,
            rationale: rationale + " (Local ML - no LLM)",
            extractedKeywords: Array(Set(keywords)).prefix(10).map { $0 },
            suggestedFromGraph: false
        )
    }
}
```

#### Phase 4: Unified Provider Manager

**Files to modify:**
- `Sources/SortAI/Core/Brain/Brain.swift`
- `Sources/SortAI/App/AppState.swift`

**Implementation outline:**
```swift
actor UnifiedCategorizationService {
    private var providers: [any LLMCategorizationProvider] = []
    private var currentProvider: (any LLMCategorizationProvider)?
    
    func initialize() async {
        // Register providers in priority order
        if #available(macOS 26.0, *) {
            let appleProvider = AppleFoundationModelsProvider()
            if await appleProvider.isAvailable() {
                providers.append(appleProvider)
            }
        }
        
        let ollamaProvider = OllamaCategorizationProvider(/* config */)
        providers.append(ollamaProvider)
        
        let localMLProvider = LocalMLProvider(/* dependencies */)
        providers.append(localMLProvider)
        
        // Sort by priority
        providers.sort { $0.priority < $1.priority }
    }
    
    func categorize(signature: FileSignature) async throws -> EnhancedBrainResult {
        var lastError: Error?
        
        for provider in providers {
            if await provider.isAvailable() {
                do {
                    NSLog("🧠 [UnifiedService] Trying provider: %@", provider.identifier)
                    let result = try await provider.categorize(signature: signature)
                    currentProvider = provider
                    return result
                } catch {
                    NSLog("⚠️ [UnifiedService] Provider %@ failed: %@", 
                          provider.identifier, error.localizedDescription)
                    lastError = error
                    continue
                }
            }
        }
        
        // All providers failed
        throw CategorizationError.allProvidersFailed(lastError)
    }
}
```

#### Phase 5: UI Integration

**Files to modify:**
- `Sources/SortAI/App/ContentView.swift`
- `Sources/SortAI/App/DegradedModeUI.swift`

**Status indicator showing current provider level:**
```swift
struct ProviderStatusBadge: View {
    let provider: String
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(colorForProvider(provider))
                .frame(width: 8, height: 8)
            Text(labelForProvider(provider))
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func colorForProvider(_ id: String) -> Color {
        switch id {
        case "apple-foundation": return .green   // Best
        case "ollama": return .blue              // Good
        case "local-ml": return .orange          // Acceptable
        default: return .red                      // Error
        }
    }
    
    private func labelForProvider(_ id: String) -> String {
        switch id {
        case "apple-foundation": return "Apple Intelligence"
        case "ollama": return "Ollama LLM"
        case "local-ml": return "Local ML Only"
        default: return "Error"
        }
    }
}
```

### Migration Strategy

1. **Phase 1** (Immediate): Enhance `LocalMLProvider` to use existing ML tools
2. **Phase 2** (Short-term): Refactor `Brain` to use provider abstraction
3. **Phase 3** (macOS 26 release): Add `AppleFoundationModelsProvider` 
4. **Phase 4** (Testing): Validate quality parity between providers

### Testing Plan

```swift
// Test cascade behavior
func testProviderCascade() async {
    // 1. With all providers available
    let result1 = await service.categorize(testSignature)
    XCTAssertEqual(service.currentProvider?.identifier, "apple-foundation")
    
    // 2. Disable Apple Foundation, should fall back to Ollama
    await service.disableProvider("apple-foundation")
    let result2 = await service.categorize(testSignature)
    XCTAssertEqual(service.currentProvider?.identifier, "ollama")
    
    // 3. Disable Ollama, should fall back to Local ML
    await service.disableProvider("ollama")
    let result3 = await service.categorize(testSignature)
    XCTAssertEqual(service.currentProvider?.identifier, "local-ml")
    
    // 4. Verify quality degradation is acceptable
    XCTAssertGreaterThan(result3.confidence, 0.3)  // Should still categorize
}
```

---

## Recommendations

### Short-Term (Now)
1. **Fix current degradation**: Wire `DegradedModeUI` to actually use `QuickCategorizer` when Ollama unavailable
2. **Enhance Local ML**: Combine all existing ML tools into a unified local provider
3. **Test extensively**: Measure accuracy difference between LLM and local-only modes

### Medium-Term (Before macOS 26)
1. **Abstract the provider interface**: Prepare for Apple Foundation Models
2. **Add OpenAI as cloud fallback**: For users who want cloud backup
3. **Improve knowledge graph**: Better pattern learning from human feedback

### Long-Term (macOS 26+)
1. **Add Apple Foundation Models provider**: Zero-dependency primary option
2. **A/B test quality**: Compare Apple vs Ollama vs Local ML
3. **Dynamic selection**: Choose provider based on file complexity

---

## References

- [Apple Foundation Models Documentation](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
- [WWDC 2025 - Introducing Foundation Models](https://developer.apple.com/videos/play/wwdc2025/10154/)
- [Ollama Documentation](https://ollama.ai/docs)
- [Apple Vision Framework](https://developer.apple.com/documentation/vision)
- [Apple NaturalLanguage Framework](https://developer.apple.com/documentation/naturallanguage)

