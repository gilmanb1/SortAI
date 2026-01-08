# SortAI - Intelligent File Organization for macOS

![macOS](https://img.shields.io/badge/macOS-15.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Why SortAI?

**The Problem**: We all have folders full of randomly named files—downloads, screenshots, documents, videos—accumulating faster than we can organize them. Manual sorting is tedious, and simple rule-based tools can't understand context.

**The Solution**: SortAI uses Large Language Models to *understand* your files, not just match patterns. It reads filenames, extracts content from documents and media, and learns from your corrections to build a personalized organization system.

### Key Differentiators

| Traditional Tools | SortAI |
|-------------------|--------|
| Match file extensions (`.pdf` → Documents) | Understands content ("invoice.pdf" → Documents/Financial) |
| Static rules | Learns from your corrections |
| Filename-only | Analyzes PDFs, transcribes audio/video, reads images |
| Flat categories | Dynamic hierarchies that emerge from your files |

SortAI is an intelligent macOS application that uses Large Language Models (LLMs) to automatically categorize and organize your files. It combines filename analysis, deep content extraction, and a learning knowledge graph to create a smart, adaptive file organization system.

## Features

### 🧠 Intelligent Categorization
- **Filename-First Analysis**: Uses LLMs to infer categories from filenames without reading content
- **Deep Content Analysis**: Extracts text from PDFs, transcribes audio/video, OCR for images
- **GraphRAG Learning**: Learns from your corrections to improve future categorization
- **Confidence Scoring**: Identifies files needing human review

### 🗂️ Dynamic Taxonomy
- **Emergent Categories**: AI generates category hierarchy based on your files
- **User Verification**: Edit, rename, merge, or split categories before organizing
- **Persistent Learning**: Knowledge graph stores corrections (export/import UI planned)

### 🎨 Modern macOS UI
- **Wizard Flow**: First-time user experience guides setup
- **Tree View Editor**: Visual hierarchy management
- **QuickLook Integration**: Component ready (UI integration planned)
- **Conflict Resolution**: Handle file conflicts elegantly

### 🔧 Robust Media Processing
- **FFmpeg Integration**: Reliable audio extraction from video files
- **Vision Framework**: Image classification and object detection
- **Speech Recognition**: Transcribe audio content

## Requirements

- **macOS 15.0+** (Tahoe)
- **Xcode 17+** 
- **Ollama** (for LLM inference)
- **Swift 6**

## Installation

### Prerequisites

1. **Install Ollama** (https://ollama.ai):
   ```bash
   # Download from https://ollama.ai or:
   brew install ollama
   ```

2. **Pull a model** (SortAI defaults to deepseek-r1:8b):
   ```bash
   ollama pull deepseek-r1:8b
   # Or use any model you prefer - SortAI will auto-download if available
   ```

3. **Start Ollama**:
   ```bash
   ollama serve
   ```

### Build from Source

```bash
# Clone the repository
git clone https://github.com/gilmanb1/SortAI.git
cd SortAI

# First time: Set up custom SQLite (required for GRDB snapshots)
./setup_sqlite.sh

# Build with the custom SQLite
./build.sh

# Run the application
.build/debug/SortAI

# Or create an app bundle
./build.sh --app
open .build/debug/SortAI.app
```

> **Note**: SortAI requires a custom SQLite build with `SQLITE_ENABLE_SNAPSHOT=1`. The standard macOS SQLite doesn't have this feature. See `BUILD_INSTRUCTIONS.md` and `XCODE_BUILD_GUIDE.md` for details.

### Running the App

**Recommended: Use the build script**
```bash
# Build and run
./build.sh && .build/debug/SortAI

# Or run tests
./test.sh
```

**If using Xcode:**
```bash
# First time: Build custom SQLite
./build.sh

# Copy SQLite library for Xcode (after clean builds)
./copy_sqlite_for_xcode.sh

# Then run from Xcode: Cmd+R
```

**Manual run:**
```bash
# Development build
.build/debug/SortAI

# Release build
swift run -c release
```

> **Note**: SortAI requires custom SQLite with snapshot support. If you get "Library not loaded: libsqlite3.dylib", run `./copy_sqlite_for_xcode.sh`. See `XCODE_BUILD_GUIDE.md` for details.

## Architecture

SortAI follows a modular, protocol-based architecture designed for extensibility and testability.

```
┌─────────────────────────────────────────────────────────────────┐
│                        SortAI App                                │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │ ContentView │  │ WizardView   │  │ SettingsView            │ │
│  └─────────────┘  └──────────────┘  └─────────────────────────┘ │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                     SortAIPipeline                               │
│  Orchestrates processing flow through injected components        │
└────────────────────────────┬────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
┌────────────────┐  ┌────────────────┐  ┌────────────────┐
│ MediaInspector │  │ Brain          │  │ MemoryStore    │
│ (Eye)          │  │ (Categorizer)  │  │ (Learning)     │
│ - Vision       │  │ - Ollama LLM   │  │ - Patterns     │
│ - Speech       │  │ - Embeddings   │  │ - Embeddings   │
│ - OCR          │  │ - Categories   │  │ - History      │
└────────────────┘  └────────────────┘  └────────────────┘
         │                   │                   │
         └───────────────────┼───────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Unified Persistence Layer                       │
│  ┌─────────────────┐  ┌────────────────┐  ┌─────────────────┐   │
│  │ SortAIDatabase  │  │ Repositories   │  │ ConfigManager   │   │
│  │ (GRDB)          │  │ - Entity       │  │ (JSON Config)   │   │
│  │                 │  │ - Relationship │  │                 │   │
│  │                 │  │ - Pattern      │  │                 │   │
│  │                 │  │ - Record       │  │                 │   │
│  │                 │  │ - Feedback     │  │                 │   │
│  └─────────────────┘  └────────────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Purpose | Location |
|-----------|---------|----------|
| **SortAIPipeline** | Main processing orchestrator | `Core/Pipeline/` |
| **MediaInspector** | File content extraction (vision, audio, OCR) | `Core/Eye/` |
| **Brain** | LLM-based categorization | `Core/Brain/` |
| **FastTaxonomyBuilder** | Two-phase instant taxonomy creation | `Core/Taxonomy/` |
| **KeywordExtractor** | Filename tokenization and keyword extraction | `Core/Taxonomy/` |
| **SimilarityClusterer** | Jaccard + Levenshtein file clustering | `Core/Taxonomy/` |
| **MemoryStore** | Learned patterns and embeddings | `Core/Memory/` |
| **KnowledgeGraphStore** | GraphRAG entity/relationship storage | `Core/Knowledge/` |
| **FileOrganizer** | File system operations | `Core/Organizer/` |
| **TaxonomyTree** | Hierarchical category model | `Core/Taxonomy/` |
| **OllamaProvider** | Ollama LLM integration | `Core/LLM/` |
| **FFmpegAudioExtractor** | Audio/video extraction via FFmpeg CLI | `Core/Audio/` |
| **ConcurrencyThrottler** | Rate limiting for LLM/IO | `Core/Pipeline/` |

### Design Patterns

- **Actor-based concurrency**: All services are Swift actors for thread safety
- **Protocol-based abstractions**: Core interfaces defined in `SortAIProtocols.swift`
- **Dependency injection**: Components injected into Pipeline for testability
- **Repository pattern**: Database access via dedicated repository classes
- **Singleton pattern**: `SortAIDatabase.shared`, `ConfigurationManager.shared`

### Two-Phase Taxonomy Inference

SortAI uses a **two-phase approach** for ultra-fast initial file categorization:

**Phase 1: Instant Rule-Based (<1 second)**
1. **Keyword Extraction**: Filenames are tokenized, split on delimiters and camelCase
2. **Stopword Filtering**: Common words (the, and, file, download) are removed
3. **File Type Detection**: Extension-based categorization (PDF, MP4, etc.)
4. **Similarity Clustering**: Jaccard similarity + Levenshtein distance groups related files
5. **Cluster Naming**: Auto-generated names from common keywords

**Phase 2: Background LLM Refinement (async)**
- LLM suggests better category names
- Proposes merges for small clusters
- User can proceed immediately while refinement continues
- User-edited categories are locked from LLM changes

**Performance:**
- 500 files: ~40ms
- 1000 files: ~80ms
- 5000 files: <1 second

This ensures users see results instantly while AI refinement improves quality in the background.

## Configuration

Configuration is managed via `AppConfiguration` and persisted as JSON.

### Configuration File

Located at: `~/.sortai/config.json`

```json
{
  "ollama": {
    "host": "http://127.0.0.1:11434",
    "defaultModel": "deepseek-r1:8b",
    "embeddingModel": "nomic-embed-text",
    "timeoutSeconds": 120,
    "retryAttempts": 3
  },
  "memory": {
    "embeddingDimension": 768,
    "maxPatterns": 10000,
    "similarityThreshold": 0.75
  },
  "processing": {
    "maxConcurrentFiles": 5,
    "useParallelProcessing": true,
    "extractAudioFromVideo": true,
    "confidenceThreshold": 0.75
  },
  "organization": {
    "defaultMode": "copy",
    "preserveFolderStructure": false,
    "createBackup": true
  }
}
```

### Environment Overrides

```bash
export SORTAI_OLLAMA_HOST="http://192.168.1.100:11434"
export SORTAI_CONFIG_FILE="~/.config/sortai/config.json"
```

## FFmpeg Integration

SortAI uses the FFmpeg command-line tools for robust audio/video processing. This enables:
- Audio extraction from any video format (MKV, AVI, WMV, FLV, WebM, etc.)
- Subtitle extraction from video files
- Media metadata inspection via ffprobe
- Speech-to-text transcription for video content

### Installation

```bash
# Install via Homebrew (recommended)
brew install ffmpeg

# Verify installation
ffmpeg -version
ffprobe -version
```

### How It Works

SortAI auto-detects FFmpeg in these locations:
1. `/opt/homebrew/bin/ffmpeg` (Homebrew on Apple Silicon)
2. `/usr/local/bin/ffmpeg` (Homebrew on Intel or manual install)
3. `/usr/bin/ffmpeg` (System install)
4. Bundled `Contents/MacOS/ffmpeg` (App bundle)

If FFmpeg is not found, SortAI falls back to AVFoundation (Apple's native framework), which has limited codec support.

### Supported Formats

| With FFmpeg | Without FFmpeg (AVFoundation only) |
|-------------|-----------------------------------|
| MKV, AVI, WMV, FLV, WebM | MP4, MOV, M4V |
| OGG, FLAC, WMA | MP3, M4A, WAV, AAC |
| All subtitle formats | None |

### Check Status

In the app, FFmpeg availability is logged at startup:
```
🎬 [FFmpeg] Found at: /opt/homebrew/bin/ffmpeg
```

Or if not found:
```
⚠️ [FFmpeg] Not found on system
```

## Testing

### Run All Tests (Recommended)

```bash
# Use the test script - handles SQLite library setup automatically
./test.sh

# Or with Swift directly (requires SQLite in build dir)
swift test
```

### Run Specific Test Suite

```bash
# Run specific test class
swift test --filter TaxonomyTests

# Run specific test method
swift test --filter testKeywordExtraction

# Skip tests that require Ollama
swift test --filter '!.*Embedding.*'
```

### Via Xcode

```bash
xcodebuild test -scheme SortAI -destination 'platform=macOS'
```

### Test Structure

```
Tests/SortAITests/
├── TaxonomyTests.swift       # Taxonomy node, tree, assignment tests
├── LLMProviderTests.swift    # LLM abstraction layer tests
├── OrganizationTests.swift   # File organization and throttling tests
├── DeepAnalyzerTests.swift   # Deep content analysis tests
├── PersistenceTests.swift    # Database and repository tests
├── ConfigurationTests.swift  # Configuration system tests
├── ProtocolTests.swift       # Protocol conformance and mock tests
└── SortAITests.swift         # Integration and embedding tests
```

## Usage Guide

### First-Time Setup (Wizard Flow)

1. **Select Source Folder**: Choose the folder containing files to organize
2. **Scanning**: App recursively scans filenames (no content read yet)
3. **AI Inference**: LLM analyzes filenames and suggests category hierarchy
4. **Verify Hierarchy**: Review, edit, merge, split categories as needed
5. **Deep Analysis**: Optionally analyze low-confidence files' content
6. **Resolve Conflicts**: Handle any file naming conflicts
7. **Organize**: Files are moved/copied to the organized structure

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| New Processing | ⌘N |
| Open Settings | ⌘, |
| Start Wizard | ⌘⇧W |
| Review Feedback | ⌘⇧R |

### Learning from Corrections

When you correct a categorization:
1. The correction is stored in the knowledge graph
2. Pattern embeddings are updated
3. Future similar files will use the learned pattern

### Exporting Learned Patterns (API Only)

> **Note**: Export/import is implemented at the API level but not yet exposed in the UI. A future update will add menu options to export and import your learned patterns.

```swift
// Programmatic export (no UI yet)
let exporter = GraphRAGExporter()
try await exporter.export(to: URL(fileURLWithPath: "~/patterns.sortai.json.gz"))
```

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| **GRDB.swift** | 6.29.0+ | SQLite database |

Native Frameworks:
- **SwiftUI** - User interface
- **Vision** - Image analysis
- **Speech** - Audio transcription
- **AVFoundation** - Media handling
- **CoreML** - On-device ML
- **NaturalLanguage** - Text analysis

## Directory Structure

```
osx_cleanup_llm/
├── Package.swift
├── README.md
├── Sources/
│   └── SortAI/
│       ├── App/
│       │   ├── SortAIApp.swift          # Entry point
│       │   ├── AppState.swift           # Global state
│       │   ├── ContentView.swift        # Main UI
│       │   ├── WizardView.swift         # Setup wizard
│       │   ├── HierarchyEditorView.swift
│       │   ├── ConflictResolutionView.swift
│       │   ├── QuickLookPanel.swift
│       │   └── SettingsView.swift
│       └── Core/
│           ├── Brain/                   # LLM categorization
│           ├── Configuration/           # Settings management
│           ├── Eye/                      # Media inspection
│           ├── Knowledge/               # GraphRAG
│           ├── LLM/                      # Provider abstraction
│           ├── Memory/                  # Pattern learning
│           ├── Organizer/               # File operations
│           ├── Persistence/             # Database layer
│           ├── Pipeline/                # Processing flow
│           ├── Protocols/               # Interfaces
│           ├── Taxonomy/                # Category hierarchy
│           └── Audio/                   # FFmpeg integration
└── Tests/
    └── SortAITests/
```

## Troubleshooting

### Ollama Connection Issues

```bash
# Check if Ollama is running
curl http://127.0.0.1:11434/api/tags

# Check available models
ollama list

# Restart Ollama
killall ollama && ollama serve
```

### Audio Extraction Failures

If you see "Smart audio extraction failed":
1. Install FFmpeg: `brew install ffmpeg`
2. Or enable FFmpeg-Kit in Package.swift (commented out by default)

### High Memory Usage

Adjust concurrency settings:
```json
{
  "processing": {
    "maxConcurrentFiles": 2
  }
}
```

### Database Issues

Reset the database:
```bash
rm -rf ~/Library/Application\ Support/SortAI/sortai.db
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Run tests: `xcodebuild test -scheme SortAI -destination 'platform=macOS'`
4. Commit changes: `git commit -m 'Add amazing feature'`
5. Push: `git push origin feature/amazing-feature`
6. Open a Pull Request

## Known Issues & Limitations

### Current Bugs

| Issue | Severity | Status | Workaround |
|-------|----------|--------|------------|
| TextField focus issues in Review modal | Medium | Investigating | Click outside the modal and try again |
| Change Category dialog sometimes auto-closes | Medium | Fixed in latest | Update to latest version |
| Zombie processes when running from terminal | Low | Known | Kill manually with `pkill -9 SortAI` |
| Audio extraction may fail for some MKV files | Low | Known | Install FFmpeg for better codec support |

### Limitations

- **macOS 15+ only**: Uses modern SwiftUI features not available on older versions
- **Apple Silicon recommended**: Some ML features may be slower on Intel Macs
- **Ollama dependency**: Requires local Ollama server for full LLM categorization
- **Large video files**: Processing videos >2GB may take significant time
- **No cloud sync**: Patterns and database are local only

## Future Features & Roadmap

### Short-Term (v1.2)

- [ ] **Wire up Watch Mode**: Connect Settings toggle to `ContinuousWatchManager`
- [ ] **Export/Import UI**: Add File menu options to backup/restore learned patterns
- [ ] **QuickLook integration**: Add preview panel to feedback review workflow
- [ ] **Apple Foundation Models support** (macOS 26+): Zero-dependency LLM option
- [ ] **Progressive degradation cascade**: Apple LLM → Ollama → Local ML → Error
- [ ] **Improved local-only mode**: Better categorization without LLM using combined ML signals
- [ ] **Batch operations**: Select multiple files and apply bulk category changes
- [ ] **Undo support**: Revert file moves and category changes

### Medium-Term (v1.3)

- [ ] **Cloud backup**: Sync learned patterns across devices
- [ ] **Watch folders**: Backend implemented (`ContinuousWatchManager`), needs UI wiring
- [ ] **Custom rules**: User-defined regex → category mappings
- [ ] **Duplicate detection**: Identify and handle duplicate files
- [ ] **Smart suggestions**: Proactively suggest organization improvements

### Long-Term (v2.0)

- [ ] **Plugin system**: Allow third-party categorization providers
- [ ] **iOS companion app**: Browse organized files from iPhone/iPad
- [ ] **Network storage support**: Organize files on NAS devices
- [ ] **AI-powered deduplication**: Semantic duplicate detection (similar content, different files)
- [ ] **Time-based organization**: Auto-archive old files

### Research & Experimental

See [LLM_Research.md](LLM_Research.md) for detailed analysis of:
- Apple Foundation Models integration plan
- Progressive degradation architecture
- Quality comparison between LLM providers

## Project Status

**Version**: 1.1.0  
**Stability**: Beta (functional but actively developed)  
**Last Updated**: January 2026

### What Works Well
- ✅ Filename-based quick categorization
- ✅ Full content analysis with LLM
- ✅ PDF text extraction
- ✅ Image classification (Vision framework)
- ✅ Audio/video transcription
- ✅ Learning from user corrections
- ✅ Hierarchical category management

### What Needs Work
- 🔄 Progressive degradation (partially implemented)
- 🔄 Batch editing UI
- 🔄 Performance with >1000 files
- 🔄 Error recovery and retry logic

### Implemented But Not Wired to UI
- ⚙️ **Watch Mode**: `ContinuousWatchManager` ready, Settings toggle exists but does nothing
- ⚙️ **Export/Import Knowledge**: `GraphRAGExporter` has methods, no menu/UI access
- ⚙️ **QuickLook Panel**: Component built, not integrated into main workflow

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Ollama](https://ollama.ai) - Local LLM inference
- [GRDB.swift](https://github.com/groue/GRDB.swift) - SQLite database
- Apple's Vision, Speech, and NaturalLanguage frameworks

---

**SortAI** - *Bringing intelligence to file organization*
