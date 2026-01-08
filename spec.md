# SortAI – Product Requirements Specification (v1.1)

**Document Version:** 1.1  
**Last Updated:** January 2026  

---

## 1. Overview

SortAI is an intelligent macOS file organization application that automatically categorizes and organizes files using modern machine learning and Large Language Models (LLMs). It recursively analyzes files using a multi-evidence pipeline—fast filename-based inference followed by optional deep content inspection—to infer categories and sub-categories, then organizes files into a structured hierarchy.

### 1.1 Core Value Proposition

- **Speed**: Instant filename-based categorization provides immediate results; deep content analysis runs asynchronously
- **Intelligence**: Embedding- and LLM-powered categorization that improves through explicit user corrections
- **Trust**: Full transparency, preview-before-move, and robust undo; files are never deleted
- **Integration**: Deep macOS integration (Finder, Spotlight, system conventions)

### 1.2 Operating Modes

1. **One-Shot Mode**: Organize a folder once with full user verification before execution  
2. **Continuous Watch Mode**: Monitor folders (e.g., Downloads) and organize new files automatically and safely

---

## 2. User Experience

### 2.1 First-Time User Experience (1UX)

SortAI onboarding uses **progressive disclosure**: simple defaults first, advanced controls revealed as needed.

#### 2.1.1 Core Setup Decisions

1. **Destination Mode**
   - `~/Organized/` (default)
   - Distributed macOS folders (`~/Documents`, `~/Pictures`, etc.)
   - Custom per-category destinations

2. **Integration Mode**
   - **Parallel Structure** (default)
   - **Merge Mode** (opt-in)

3. **Hierarchy Depth**
   - Range: 3–7 levels (default: 3)

4. **LLM Provider**
   - Local (Ollama, default)
   - Cloud (opt-in with explicit privacy warnings)

#### 2.1.2 Simulation Mode

Optional preview during onboarding:

- Before/after visual tree
- Persistent until explicit acceptance
- Cherry-pick individual moves
- Incremental category approval

#### 2.1.3 Advanced Options (Progressive)

- Stability ↔ Correctness slider
- Deep analysis file type selection
- Battery behavior
- Notifications
- Hidden file handling

---

## 3. Core Functionality

### UX Considerations (additive; does not change existing requirements)
- First-time “aha”: Show initial hierarchy immediately with exemplar files per top-level category; allow inline accept/edit before deeper steps.
- Status clarity: Persistent, unobtrusive indicators for LLM mode (full/degraded), watch mode, background deep analysis; one-click retry/return to full mode.
- Undo & safety: Visible undo/redo affordances near move/organize actions; easy entry to movement log/activity view.
- Hierarchy editing: Keep inline edit discoverable (button, context menu, Enter to edit); show counts and confidence per node; surface merge/split suggestions as actionable chips; lock badge on user-edited nodes.
- Continuous watch UI: Menubar item showing mode (full/degraded), watch on/off, queue depth, last action, quiet-period indicator; in-app watch status mirrored.
- Collision handling: macOS-style rename prompts with preview of proposed names (“file (1).pdf”); default to copy/alias-first.
- Performance perception: Stream category tree progressively; keep UI interactive while background refinement runs; use skeleton/loading states.
- Review queue: Dedicated “Needs Review” bucket with sortable columns (confidence, size, type, date) and batch approve/reassign.
- Learning visibility: “Why” tooltips on auto-moves (similarity score, prototype source); unobtrusive, dismissible.
- Merge/split proposals: Diff-like preview (before/after counts, exemplars) with explicit approve/decline and undo.
- Deep analysis UX: Per-batch progress, pause/cancel; highlight upgraded/downgraded placements on completion; file-type opt-ins surfaced with battery/latency hints.
- Degraded vs full: On LLM unavailability, prompt once (“Wait/Retry” vs “Use local-only”), remember choice per session; small toggle in status bar to switch back when healthy.
- Accessibility: Keyboard parity for tree ops (rename, delete, move, merge/split approve/decline); VoiceOver labels for hierarchy, status, buttons.
- Exemplars: Show small exemplar list (names, icons, QuickLook where applicable) per category to validate quickly.
- Notifications: Prefer in-app toasts for routine events; use system notifications only for long-running background watch actions.
- Resizing/scroll: Ensure visible scrollbars for tree/detail panes; maintain sensible min sizes.
- Error recovery: Friendly toast on failures (LLM timeout, I/O) with “Retry” and “Details…” linking to logs.

### 3.1 Two-Phase Categorization

#### Overview

SortAI uses a **two-phase, confidence-gated categorization pipeline**. Each file is routed into one of three outcomes:

1. **Auto-place** (high confidence)
2. **Propose for review** (medium confidence)
3. **Stage for deeper analysis or confirmation** (low confidence)

This guarantees predictable behavior and prevents unexpected file moves.

---

#### Phase 1: Instant Semantic Filename Analysis (<1 second)

**Evidence extracted**

- Filename tokenization (delimiters, camelCase, digits)
- Normalization (Unicode, case)
- File extension and coarse type
- Parent folder names
- Size bucket and created/modified year
- Parent-folder context weighted highly for disambiguation

**Processing**

1. Build a normalized textual fingerprint
2. Generate a **name embedding** using a lightweight sentence transformer (tens of MB acceptable) plus character/word n-grams; cache embeddings
3. Compare against existing category prototype vectors (EMA-updated); allow shared prototypes across linked folders
4. If no taxonomy exists: perform bounded recursive clustering (spherical k-means or HDBSCAN) to propose finer themes up front for the 1UX “aha” moment; label clusters with top keywords + parent-folder signals
5. Assign a category path with confidence score; target ≥85% precision for auto-place, otherwise propose for review
6. Enforce runtime: sub-10s for 5k files (filename-only fast path), with depth respecting user preference but not hard-capped (advisory)

**Outputs**

- Draft hierarchy
- Per-file confidence
- Immediate preview structure

---

#### Phase 2: Background Deep Content Analysis

Triggered when:

- Phase 1 confidence < threshold
- User enables full analysis
- Continuous Watch Mode introduces new files

**Content extraction**

- Documents: text extraction, OCR if needed
- Images: OCR, optional object/scene labels
- Audio/Video: speech-to-text + metadata
- App bundles: metadata introspection (atomic handling)

**Processing**

1. Generate content summaries
2. Create **content embeddings**
3. Re-score against category prototypes
4. Upgrade/downgrade confidence or flag for review

**Guarantees**

- No silent overrides of user-approved placements
- All refinements are logged and undoable

---

### 3.2 Continuous Watch Mode

#### 3.2.1 File Detection

- Uses FSEvents to monitor folders
- Detects new files, moves, renames
- Stability checks (no writes for X seconds)
- Ignores partial downloads (`.part`, `.crdownload`)
- Skips locked/open files

#### 3.2.2 Quiet Period Processing

- Batches related downloads
- Waits for inactivity window before organizing
- Stages in-use files for later processing
- Never moves files while user is actively interacting

#### 3.2.3 Large File Handling

- Warns user before deep analysis
- Processes asynchronously
- Never blocks UI

---

### 3.3 Learning & Patterns

#### Learning Model

SortAI learns **only from explicit user actions** using embedding-based prototype vectors.

#### Pattern Scope

- Folder-scoped by default
- Each folder maintains independent prototype vectors
- Users may explicitly link folders to share learning
- Linked folders share prototypes but keep separate undo history

#### What Is Learned

On user confirmation or correction:

- File embedding is incorporated into category prototype (EMA update)
- Records:
  - embedding type (name/content)
  - folder scope
  - timestamp
  - prior confidence

Ignored files never contribute to learning.

#### How Learning Is Applied

- Files are scored against category prototypes using cosine similarity
- Prototype similarity contributes to confidence
- Improves auto-placement and semantic generalization

#### Active Learning (Optional)

- Surfaces high-uncertainty files for one-click confirmation
- Feeds directly into prototype updates
- Fully opt-in

---

### 3.4 Taxonomy Evolution

#### Philosophy

Taxonomy evolution is conservative and signal-driven, prioritizing stability unless the user opts for higher correctness.

#### New Category Emergence

- Created when files are dissimilar to all existing prototypes
- Backed by clustering coherence
- Named and defined via LLM summarization
- Silent by default; notifications optional

#### Category Drift Detection

Monitors:

- Intra-category variance
- Multi-modal clustering
- Rising correction frequency

Weighted by Stability ↔ Correctness preference.

#### Split Suggestions

1. Internal re-clustering
2. Proposed subcategories with exemplars and definitions
3. Explicit user approval required

#### Merge Suggestions

- Triggered by prototype convergence and frequent user moves
- Always explicit and reversible

---

## 4. File Handling

### 4.1 Conflict Resolution

#### Filename Collisions

- macOS-style renaming (`file (1).pdf`)

#### Duplicate Detection

- SHA-256 for exact duplicates
- Perceptual hashing for near-duplicates
- User prompted; no auto-deletion

#### Symlinks & Aliases

- Ignored in V1

#### Package Files

- Treated atomically
- Metadata inspected; contents not reorganized

### 4.2 Hidden & System Files

- Hidden files ignored by default
- System files always ignored
- Quarantined files ignored until cleared

### 4.3 Move Operations

#### Soft Move Option

- Uses symlinks/aliases first
- Confirmation window before hard move
- Fully undoable

#### Activity Logging

- Timestamp, source, destination, reason, confidence
- Default retention: 120 days

#### Absolute Rule

- Files are never deleted

---

## 5. Destination Management

### 5.1 Destination Modes

1. Centralized (`~/Organized/`)
2. Distributed (macOS conventions)
3. Custom per-category

### 5.2 Hierarchy Depth

- 3–7 levels (default: 3)

### 5.3 Existing Folder Integration

- Parallel structure by default
- Merge mode is opt-in and respectful of existing organization

---

## 6. “Where Is My File?” System

### 6.1 Spotlight Integration

- Adds Spotlight metadata/tags
- Custom SortAI attributes

### 6.2 Activity Log

- Searchable movement history
- Shows when, why, and where files moved

### 6.3 Undo System

- File-level or batch-level undo
- Time-based undo (nice-to-have)

---

## 7. LLM Integration

### 7.1 Provider Support

#### Local (Default)

- Ollama-based
- Speed ↔ Accuracy slider
- Automatic context optimization

#### Cloud (Opt-in)

- Explicit privacy warnings
- Filenames shared by default
- Content only with additional opt-in

### 7.2 Offline / Degraded Mode

- User chooses degraded filename-only mode or wait
- Continuous Watch pauses unless degraded mode enabled

---

## 8. Performance & Resource Management

- No hard limits; graceful degradation
- Background processing for heavy workloads
- Battery-aware deep analysis (paused by default on battery)

---

## 9. Security & Privacy

- App Store sandboxed
- Full Disk Access required
- Explicit consent for any cloud processing

---

## 10. Recovery & Resilience

- Progress log for crash recovery
- Resume safely after force-quit
- No partial or lost moves

---

## 11. Preferences Panel

### General

- Launch at login
- Menu bar icon
- Notifications

### Organization

- Destination mode
- Hierarchy depth
- Stability ↔ Correctness
- Soft move toggle

### Analysis

- Deep analysis file types
- Large file threshold
- Battery behavior

### LLM

- Provider and model
- Speed ↔ Accuracy
- Cloud privacy controls

### Privacy

- Hidden file handling
- Log retention

### Advanced

- Database location
- Export/import/reset patterns

---

## 12. Out of Scope (V1)

- Multi-device sync
- Context profiles (work/personal)
- Compliance/audit logging
- File deletion
- Automatic cross-folder learning
- iOS/iPadOS support

---

## 13. Success Metrics

- Initial taxonomy <1s for 5,000 files
- ≥85% correct categorization without correction
- Zero unexpected moves
- High adoption of Continuous Watch Mode

---

## 14. Technical Requirements

- macOS 15.0+ (Tahoe)
- Swift 6
- Ollama (local LLM inference)
- FFmpeg (optional)
- Full Disk Access