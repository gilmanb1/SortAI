# SortAI Bug Analysis Report

**Date**: 2026-01-13
**Branch**: `claude/analyze-codebase-bugs-MHYQp`
**Status**: Analysis Complete - Pending Implementation

---

## Executive Summary

Analysis of the SortAI codebase identified **39+ issues** across multiple categories. This document focuses on the **3 critical bugs** requiring immediate attention, with agreed-upon remediation strategies.

---

## Bug #1: Silent Error Swallowing Throughout Pipeline

### Severity: CRITICAL

### Locations
- `Core/Pipeline/SortAIPipeline.swift:234-327`
- `Core/Brain/Brain.swift:272-279`
- 15+ additional instances across the codebase

### Problem Description

The codebase extensively uses `try?` to silently discard errors, particularly in the learning pipeline:

```swift
// SortAIPipeline.swift:286-293 - Feedback queue failures silently ignored
_ = try? await feedbackManager?.addToQueue(...)

// SortAIPipeline.swift:317-327 - Processing record failures silently ignored
try? concreteMemory.saveRecord(record)

// Brain.swift:272-279 - Graph enhancement failures ignored
Task {
    try? await enhancer.processFile(...)
}
```

### Impact
- User corrections that should improve future categorization are silently lost
- Database corruption or disk-full situations go undetected
- The learning system can degrade without any user notification

### Agreed Remediation

1. **Create `RetryQueue` actor** that:
   - Accepts failed operations with context (operation type, payload, attempt count)
   - Implements exponential backoff (1s, 2s, 4s, 8s)
   - Max retry limit: 3 attempts
   - Persists queue to disk (`~/.sortai/retry_queue.json`) so retries survive app restart

2. **Operations to queue on failure**:
   - `feedbackManager.addToQueue()` - user corrections
   - `memoryStore.saveRecord()` - processing history
   - `memoryStore.recordHit()` - pattern usage tracking
   - `graphEnhancer.processFile()` - knowledge graph updates

3. **After max retries exhausted**:
   - Log to `FileLogger` with full context (file URL, operation type, error details, timestamps)
   - Write to `~/.sortai/logs/sortai.error`

---

## Bug #2: `fatalError` in Database Initialization

### Severity: CRITICAL

### Location
- `Core/Persistence/SortAIDatabase.swift:85`

### Problem Description

```swift
static var shared: SortAIDatabase {
    lock.lock()
    defer { lock.unlock() }

    if _shared == nil {
        do {
            _shared = try SortAIDatabase(configuration: .default)
        } catch {
            fatalError("Failed to initialize SortAI database: \(error)")  // CRASH
        }
    }
    return _shared!
}
```

Using `fatalError` for database initialization failures causes immediate app crash without recovery. This can occur with:
- Disk full conditions
- File permission issues
- Corrupted SQLite database
- Custom SQLite build missing required compile flags

### Impact
- Production crashes with no graceful degradation
- No user feedback or recovery option
- Poor user experience

### Agreed Remediation

1. **Detection Phase**:
   - Replace `fatalError` with throwing initializer
   - Identify error type (corruption, permissions, disk full, missing SQLite flags)

2. **Enter Recovery Mode**:
   - Set app state to `DatabaseRecoveryMode`
   - Disable all user input (file drops, wizard, settings changes)
   - Display modal alert: *"SortAI is recovering your database. Please wait..."*
   - Show progress indicator during recovery

3. **Automatic Recovery Steps** (in order):
   ```
   Step 1: Run SQLite integrity check (PRAGMA integrity_check)
   Step 2: If corrupt → attempt VACUUM or rebuild from WAL
   Step 3: If rebuild fails → restore from automatic backup (~/.sortai/backups/)
   Step 4: If no backup → offer to reset database (lose learning data)
   Step 5: If permissions issue → prompt user to fix permissions
   Step 6: If disk full → alert user to free space
   ```

4. **Recovery UI State Machine**:
   ```
   Normal → DatabaseError → RecoveryInProgress → RecoverySuccess → Normal
                                              → RecoveryFailed → ReadOnlyMode
   ```

5. **Read-Only Fallback** (if recovery fails):
   - Allow viewing existing categorizations
   - Disable: file organization, corrections, learning
   - Persistent banner: *"Database recovery failed. Running in read-only mode."*

6. **Automatic Backups** (prevention):
   - Daily backup of `sortai.db` to `~/.sortai/backups/`
   - Keep last 7 backups, rotate oldest
   - Backup before migrations

---

## Bug #3: Race Condition in Speech Recognition Continuation

### Severity: HIGH

### Location
- `Core/Eye/MediaInspector.swift:1230-1270`

### Problem Description

```swift
let stateBox = SpeechContinuationState()  // Uses NSLock + @unchecked Sendable

return try await withCheckedThrowingContinuation { continuation in
    stateBox.setContinuation(continuation)

    let task = recognizer.recognitionTask(with: request) { result, error in
        // Can resume continuation here
    }

    // RACE: Timeout runs on DispatchQueue.global(), not coordinated with actor
    DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
        if !stateBox.didResume {
            task.cancel()
            stateBox.resumeWithFailure(...)  // Can race with callback above
        }
    }
}
```

The timeout handler runs on `DispatchQueue.global()` while the speech recognizer callback fires on a different thread. This mixes old-style GCD with Swift's structured concurrency, creating:
- Potential for double-resume attempts (checked continuation will trap)
- Actor isolation boundary violations

### Impact
- Potential crashes during audio transcription
- Especially affects files near the 30-second timeout boundary

### Agreed Remediation

1. Replace `DispatchQueue.global().asyncAfter` with `Task.sleep()` + cancellation
2. Use `withTaskCancellationHandler` for clean timeout handling
3. Remove `@unchecked Sendable` / NSLock pattern in favor of actor isolation
4. Leverage native macOS crash reporting (ReportCrash) for any uncaught issues

---

## Additional Issues Identified

| Issue | Location | Severity |
|-------|----------|----------|
| Force unwrap on `FileManager.urls().first!` | `FileLogger.swift:79`, `SortAIDatabase.swift:194`, `GraphRAGExporter.swift:519`, `ConfigurationManager.swift:47` | High |
| Force unwrap on array access | `SphericalKMeans.swift:126`, `SmartAudioSampler.swift:411`, `FileOrganizer.swift:100` | High |
| Temp files leaking on export failure | `MediaInspector.swift:862-917` | Medium |
| Unchecked empty path array in TaxonomyNode | `TaxonomyNode.swift:140-167` | Medium |
| Fire-and-forget tasks without error handling | `Brain.swift:242-244` | Medium |
| Missing bounds check in Levenshtein | `SimilarityClusterer.swift:195-196` | Medium |

---

## Logging Strategy

| Log Type | Destination | Purpose |
|----------|-------------|---------|
| Application logs | `FileLogger` → `~/.sortai/logs/` | Debug, info, warnings |
| Failed operations (post-retry) | `FileLogger` → `sortai.error` | Audit trail for lost data |
| Crashes | macOS native `ReportCrash` | Automatic crash reports |
| Performance metrics | `MetricKit` (optional) | Native macOS analytics |
| System-level diagnostics | `OSLog` / `Logger` | Console.app integration |

**Recommendation**: Add `OSLog` alongside `FileLogger` for better integration with macOS Console.app and unified logging system.

---

## Implementation Priority

| Priority | Bug | Estimated Complexity |
|----------|-----|---------------------|
| 1 | Bug #2 - Database Init | High (new state machine, UI changes) |
| 2 | Bug #1 - Silent Errors | Medium (new RetryQueue actor) |
| 3 | Bug #3 - Race Condition | Low (refactor to structured concurrency) |

---

## Next Steps

1. [ ] Implement `RetryQueue` actor for Bug #1
2. [ ] Refactor `SortAIDatabase` initialization for Bug #2
3. [ ] Create `DatabaseRecoveryMode` UI state
4. [ ] Add automatic backup system
5. [ ] Refactor speech recognition timeout for Bug #3
6. [ ] Address additional force-unwrap issues
7. [ ] Add `OSLog` integration
