# MP4 Audio → Text Extraction Plan (Verbose Spec)

## Goals

- Extract sufficient speech from `.mp4` files to enable accurate categorization and sub-categorization.
- Use multi-clip sampling strategy to capture representative content throughout the video.
- Produce reliable transcripts; avoid silent failures and minimize timeouts.
- Support memory-aware concurrent processing with adaptive resource management.

## Extraction Strategy (Step-by-Step)

- **Multi-clip sampling strategy**
  - Extract multiple clips distributed throughout video duration to capture representative content.
  - For videos ≤5 min: single 300s clip from start.
  - For videos >5 min: extract 3-5 clips of 30-60s each, evenly distributed (beginning, middle(s), end).
  - Total extracted audio capped at 300s across all clips.
  - Clip positions: `[0s, duration/4, duration/2, 3*duration/4, duration-60s]` (skip if overlap).

- **Primary: VAD-based extraction**
  - Use VAD (Voice Activity Detection) via `SmartAudioSampler` as first approach.
  - Benefits: efficient, focuses on speech-dense segments.
  
- **Fallback chain (in order)**
  1. **FFmpeg contiguous clip export** - if VAD fails or insufficient speech detected
     - Output: 16 kHz mono PCM WAV (`-vn -ac 1 -ar 16000`).
     - Timeout per clip: `min(60s, max(30s, clipDuration * 0.2))`.
     - Audio separation: use FFmpeg's `afftdn` (noise reduction) and `highpass/lowpass` filters to isolate speech frequencies if initial transcription fails.
  2. **AVFoundation clip export** - if FFmpeg missing or timeout
     - Export same clip window to `.m4a` via `AVAssetExportSession`.
     - Apply same time ranges as FFmpeg would use.
  3. **SmartAudioSampler (frame-based)** - last resort before hard failure
     - Attempt original smart sampling approach.
  4. **Hard failure** - surface error via existing error/notification infrastructure.

- **Streaming transcription (preferred)**
  - Stream audio data directly to `SFSpeechRecognizer` without intermediate files where possible.
  - Falls back to file-based transcription if streaming unavailable.
  
- **Temporary file management**
  - Store temp files in system tmp directory with unique identifiers.
  - Clean up immediately after transcription completes (success or failure).
  - Implement cleanup on app termination for orphaned files.
  
- **Parallelism & resource management**
  - Audio and visual pipelines are independent and run in parallel.
  - No shared state between pipelines; separate configurations.
  - Memory-aware concurrency: sample system memory pressure and adjust concurrent extraction count.
  - Default concurrency: start with 2-4 concurrent extractions, scale based on available memory.

## Transcription Strategy

- **Primary**: `SFSpeechRecognizer` on extracted clips (streaming preferred, file-based fallback).

- **Language handling**
  - Auto-detect language using `SFSpeechRecognizer`'s language detection (already implemented).
  - Transcribe all detected languages to English.
  - Support code-switching (multiple languages in same video).

- **General retry mechanism**
  - **Transient errors** (network, memory pressure, timeout): retry up to 2 times with exponential backoff (1s, 3s).
  - **No speech errors** (kAFAssistantErrorDomain 1110, AVFoundation -11800): 
    - First: retry once on same clip.
    - Second: fall back to next extraction method in fallback chain.
    - Third: if all clips fail, try FFmpeg audio separation preprocessing, then retry.
  - **Codec/format errors**: immediately fall back to next extraction method.
  - **Hard failures** after all retries: surface via existing error/notification infrastructure.
  
- **Audio separation preprocessing** (only on repeated failures)
  - Apply FFmpeg filters to separate speech from background music:
    - `afftdn` - adaptive FFT denoiser for background noise.
    - `highpass=f=80, lowpass=f=3000` - isolate speech frequency range.
    - `dialoguenhance` - enhance dialogue over music (if available in FFmpeg build).
  - Triggered only after initial transcription attempts fail on clip.
  - Re-attempt transcription on processed audio.

- **Return conditions**
  - Empty transcript only after confirmed no-speech across all clips and all retries.
  - Partial success: return transcripts from successful clips even if some clips fail.

## Logging & Observability

- Per file: clip length, timeout, extractor used, extraction duration, transcription duration, retry outcomes, backend used, final transcript length.
- “No subtitles found” → info level.
- Hard failures (missing FFmpeg, repeated transcription failure) stay warnings.

## Configurables

- `maxTotalAudioDuration` (default 300s) - total audio extracted across all clips.
- `clipDurationShort` (default 30-60s) - duration of each clip for long videos.
- `maxClipsPerVideo` (default 5) - maximum number of clips to extract.
- `ffmpegTimeoutPerClip` - calculated as `min(60s, max(30s, clipDuration * 0.2))`.
- `useVADFirst` (default true) - attempt VAD-based extraction before contiguous clips.
- `enableAudioSeparation` (default true) - enable FFmpeg audio separation on failure.
- `maxConcurrentExtractions` (default auto) - auto-detect based on system memory, or manual override.
- `useStreamingTranscription` (default true) - prefer streaming over file-based transcription.
- `retryTransientErrors` (default true) - retry transient errors with exponential backoff.
- `maxRetriesPerClip` (default 2) - maximum retry attempts per clip.

## Implementation Steps

1) **Multi-clip position calculation**
   - In `MediaInspector`, determine clip positions based on video duration:
     - ≤5 min: single clip at 0s
     - \>5 min: distribute 3-5 clips evenly throughout duration
   - Calculate: `[0s, duration/4, duration/2, 3*duration/4, max(0, duration-60s)]`
   - Skip overlapping clips; ensure total doesn't exceed `maxTotalAudioDuration`.

2) **Dynamic timeout per clip**
   - Compute timeout per clip: `min(60s, max(30s, clipDuration * 0.2))`.
   - Pass timeout to `FFmpegAudioExtractor` per clip extraction.

3) **Extraction fallback chain**
   - **Primary**: Try `SmartAudioSampler` with VAD (if `useVADFirst` enabled).
   - **Fallback 1**: FFmpeg contiguous clip export with `-t <clipDuration>` and `-ss <startTime>`.
   - **Fallback 2**: AVFoundation with same `timeRange`.
   - **Fallback 3**: Original `SmartAudioSampler` frame-based approach.
   - **Fail**: Surface error through existing notification infrastructure.

4) **Streaming transcription**
   - Implement streaming path to `SFSpeechRecognizer` using audio buffers.
   - Fall back to file-based transcription if streaming fails or unavailable.
   - Clean up temp files immediately after transcription.

5) **General retry mechanism**
   - Wrap transcription in retry logic with error classification:
     - Transient (network, memory): exponential backoff, max 2 retries.
     - No-speech: retry same clip once, then try next extraction method.
     - Codec/format: immediately try next extraction method.
   - Track retry count per clip and per video.

6) **Audio separation preprocessing**
   - Add FFmpeg filter chain for speech isolation:
     ```
     -af "afftdn=nf=-25,highpass=f=80,lowpass=f=3000"
     ```
   - Apply only after initial transcription attempts fail.
   - Add `dialoguenhance` if available in FFmpeg build.

7) **Memory-aware concurrency**
   - Implement memory pressure sampling using `ProcessInfo.processInfo.thermalState`.
   - Adjust `maxConcurrentExtractions` dynamically:
     - Low pressure: 4 concurrent
     - Nominal: 2 concurrent  
     - Fair/Serious/Critical: 1 concurrent
   - Queue remaining extractions until resources available.

8) **Input validation**
   - Check video duration before processing:
     - If duration == 0, NaN, or invalid: skip file, log warning.
     - Prevents timeout calculation errors on corrupted files.

9) **Temp file management**
   - Create temp files in `FileManager.default.temporaryDirectory`.
   - Use UUID-based naming: `sortai_audio_<UUID>.wav`.
   - Implement cleanup:
     - Immediate: after successful transcription.
     - Deferred: on error, mark for cleanup.
     - Startup: purge orphaned temp files from previous runs.

10) **Logging enhancements**
    - Per clip: position, duration, timeout, extractor used, extraction time, transcription time.
    - Per video: total clips, successful clips, total transcript length, retries, fallback usage.
    - Aggregate: success rate, average time per clip, most common failure modes.

11) **Configurability**
    - Expose all configurables through `AppConfiguration`.
    - Add auto-detection for `maxConcurrentExtractions` based on system specs.
    - Allow per-run override of defaults.

## Coding Strategy / Architecture (fit to current code)

- **`MediaInspector.extractAudioForTranscription` changes**:
  - Calculate multi-clip positions based on video duration.
  - Loop through each clip position and extract/transcribe.
  - Maintain fallback chain: VAD → FFmpeg → AVFoundation → SmartAudioSampler.
  - Aggregate transcripts from all successful clips.
  - Validate input: skip if duration ≤ 0 or NaN.

- **`FFmpegAudioExtractor` enhancements**:
  - Accept dynamic timeout per clip (not per video).
  - Add `-ss <startTime>` and `-t <duration>` for clip extraction.
  - Support audio separation filter chain: `afftdn`, `highpass`, `lowpass`, optional `dialoguenhance`.
  - Method signature: `extract(from url: URL, startTime: TimeInterval, duration: TimeInterval, timeout: TimeInterval, applySeparation: Bool)`.

- **`AVFoundationAudioExtractor` updates**:
  - Accept `timeRange` parameter for clip extraction.
  - Match FFmpeg's clip window exactly.
  - Return error details for proper retry classification.

- **`SmartAudioSampler` integration**:
  - Keep as primary method (VAD-first approach).
  - If insufficient speech detected, return signal to try contiguous clip fallback.
  - No changes to frame sampling for visual analysis (separate pipeline).

- **New `StreamingTranscriber` class** (optional):
  - Wraps `SFSpeechRecognizer` with streaming audio buffer support.
  - Falls back to file-based transcription if streaming unavailable.
  - Handles cleanup of resources.

- **`transcribeAudioFile` retry wrapper**:
  - Classify errors: transient, no-speech, codec, hard failure.
  - Implement exponential backoff for transient errors.
  - For no-speech: retry same clip once, then signal to try next extraction method.
  - Track retry count and reason per clip.
  - Return result with metadata: success, retries, method used, duration.

- **New `ConcurrencyManager` class**:
  - Monitor system memory pressure via `ProcessInfo`.
  - Maintain queue of pending extractions.
  - Dynamically adjust concurrent limit based on pressure.
  - Expose metrics: queue depth, active extractions, pressure level.

- **New `TempFileManager` utility**:
  - Centralized temp file creation with UUID naming.
  - Track all temp files in memory (weak references).
  - Cleanup methods: immediate (after use), deferred (on error), startup (orphans).
  - Implement using `FileManager` with proper error handling.

- **Data flow per video**:
  1. Validate duration → calculate clip positions
  2. For each clip position:
     a. Try VAD extraction → transcribe
     b. On failure: FFmpeg contiguous → transcribe  
     c. On failure: AVFoundation → transcribe
     d. On failure: SmartAudioSampler → transcribe
     e. On repeated transcription failure: apply audio separation → retry
  3. Aggregate successful transcripts
  4. Clean up all temp files
  5. Return combined transcript with metadata

- **Configuration flags** (all in `AppConfiguration`):
  - `maxTotalAudioDuration`, `clipDurationShort`, `maxClipsPerVideo`
  - `useVADFirst`, `enableAudioSeparation`, `useStreamingTranscription`
  - `maxConcurrentExtractions`, `retryTransientErrors`, `maxRetriesPerClip`

- **Error handling**:
  - Transient errors: retry with backoff, eventually fallback.
  - No-speech errors: retry once, then try audio separation.
  - Missing FFmpeg: skip to AVFoundation immediately.
  - Corrupted input: skip file entirely, log warning.
  - Use existing error/notification infrastructure for surfacing to UI.

- **Parallel pipelines**:
  - Audio extraction/transcription: separate actor or async context.
  - Visual frame sampling: independent, no shared state.
  - Can run simultaneously with separate resource pools.
  - Coordinated only at final metadata aggregation step.

## Testing Plan

### Unit Tests
- **Clip position calculation**:
  - Videos ≤5 min → single clip at 0s.
  - Videos >5 min → 3-5 clips distributed evenly.
  - Verify no overlapping clips.
  - Total duration ≤ `maxTotalAudioDuration`.
- **Timeout calculation**: per-clip timeout scales correctly with clip duration.
- **Error classification**: transient vs. no-speech vs. codec vs. hard failure.
- **Retry logic**: exponential backoff timing, max retries enforced.
- **Memory pressure detection**: concurrency adjusts based on thermal state.
- **Temp file naming**: UUID-based, unique per extraction.

### Integration Tests
- **Short video with clear speech** (<5 min):
  - VAD succeeds, single clip, transcript returned, no retries.
- **Long video with speech** (60-120 min):
  - Multiple clips extracted at correct positions.
  - All clips transcribed successfully within timeout.
  - Transcripts aggregated correctly.
- **Music-only video**:
  - VAD fails → FFmpeg contiguous → no speech detected.
  - Retry with audio separation preprocessing.
  - Eventually return empty or minimal transcript after all attempts.
- **Video with background music and speech**:
  - Initial extraction includes music.
  - If transcription poor, apply audio separation.
  - Improved transcript after separation.
- **Corrupted/invalid video**:
  - Duration returns 0 or NaN → skip file immediately.
  - Log warning, no extraction attempted.
- **Odd codec video**:
  - FFmpeg fails → AVFoundation fallback succeeds.
  - Transcript returned from fallback method.
- **Missing FFmpeg**:
  - Skip FFmpeg step, use AVFoundation directly.
  - Transcript successful via AVFoundation.
- **Multiple audio tracks**:
  - Verify default track selection (usually track 0).
  - Or extract primary language track if detectable.
- **Variable bitrate audio**:
  - Extraction handles VBR without corruption.
  - Transcript successful.
- **Sparse speech video** (20s speech in 10 min):
  - Multi-clip strategy captures some speech segments.
  - VAD might help identify speech-heavy clips.
  - Partial transcript returned from speech segments.
- **Multi-language video**:
  - Auto-detect languages per clip.
  - All languages transcribed to English.
  - Transcripts aggregated.
- **Code-switching video** (multiple languages in same clip):
  - SFSpeechRecognizer handles language switching.
  - Transcript includes all detected speech.

### Concurrency & Resource Tests
- **Concurrent processing of many files**:
  - Queue 20+ videos for processing.
  - Verify concurrency limit enforced.
  - Memory pressure adjusts concurrency dynamically.
  - No crashes or memory exhaustion.
- **Temp file cleanup verification**:
  - All temp files cleaned after successful transcription.
  - Error case: temp files cleaned on failure.
  - Startup: orphaned temp files from previous runs purged.
- **Memory pressure simulation**:
  - Simulate high memory usage.
  - Verify concurrency drops to 1.
  - Processing continues without crash.
- **Streaming vs. file-based transcription**:
  - Compare performance and accuracy.
  - Verify fallback works when streaming unavailable.

### Performance Tests
- **Batch sample set** (50+ diverse videos):
  - Ensure no systemic timeouts.
  - Success rate >90% for speech-containing videos.
  - Average extraction time per clip <30s.
  - Audio separation used <10% of time.
- **Subtitle absence handling**:
  - Videos without embedded subtitles → info level log, no warning.
  - Does not affect transcription success.

### Regression Tests
- **Non-MP4 files unaffected**:
  - PDFs: text extraction unchanged.
  - Images: visual analysis unchanged.
  - Audio files: existing audio flow unchanged.
- **Frame sampling for MP4s**:
  - Visual keyframe extraction still works.
  - Parallel to audio extraction.
  - No interference or shared state issues.
- **Existing error/notification UI**:
  - Failures surface correctly through existing infrastructure.
  - No UI regressions.

## Notes for Implementers

- **Async/await throughout**: avoid blocking actors, use structured concurrency.
- **Logging style**: reuse existing `NSLog` patterns for consistency.
- **Defaults**: 300s total audio, multi-clip for long videos, VAD-first, audio separation enabled.
- **Progressive enhancement**: implement core multi-clip + retry first, then add streaming and memory-aware concurrency.
- **Backward compatibility**: ensure existing non-MP4 flows unaffected.
- **Error messages**: user-friendly, actionable, routed through existing UI notification system.
- **Performance monitoring**: instrument with timing and success metrics for future optimization.
- **Configuration**: all new settings should have sensible defaults that work for 90% of use cases.
- **Testing order**: unit tests → integration (happy path) → edge cases → concurrency → performance.
- **Code reuse**: leverage existing `MediaInspector`, `FFmpegAudioExtractor`, `SmartAudioSampler` where possible; extend, don't replace.

---

## Key Improvements Summary

### Problem Solved
Extract sufficient speech from MP4 videos to enable accurate categorization without transcribing entire files, while handling edge cases (music, corrupted files, long videos) robustly.

### Solution Architecture
1. **Multi-clip sampling**: Distribute 3-5 clips throughout long videos to capture representative content.
2. **Intelligent fallback chain**: VAD → FFmpeg → AVFoundation → SmartAudioSampler → hard fail.
3. **Adaptive retry**: Classify errors and apply appropriate retry strategies with backoff.
4. **Audio separation**: Isolate speech from background music using FFmpeg filters when needed.
5. **Resource-aware**: Adjust concurrency based on system memory pressure.
6. **Streaming-first**: Minimize disk I/O by streaming to transcription when possible.

### Trade-offs & Decisions
- **Sampling vs. Complete**: Accept missing some content in favor of faster processing and categorization focus.
- **VAD-first**: Leverage existing efficient VAD when possible, fall back to brute-force only on failure.
- **No new dependencies**: Use FFmpeg + SFSpeechRecognizer; avoid Whisper to prevent new hard dependencies.
- **Parallel pipelines**: Audio and visual remain independent for maximum parallelism.
- **Fail gracefully**: Empty transcript only after exhausting all attempts; surface errors clearly.

### Expected Outcomes
- **Higher success rate**: Multi-pronged approach catches more edge cases.
- **Better categorization**: Representative samples from throughout video.
- **Manageable resource usage**: Memory-aware concurrency prevents system overload.
- **Clearer diagnostics**: Enhanced logging reveals bottlenecks and failure patterns.

