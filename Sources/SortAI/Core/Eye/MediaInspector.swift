// MARK: - Media Inspector (The Eye)
// Polymorphic actor that extracts signals from files based on type
// Uses Apple Vision for scene tags + SFSpeechRecognizer for audio transcripts

import Foundation
import AVFoundation
import Vision
@preconcurrency import Speech
import PDFKit
import NaturalLanguage
import CoreImage

// MARK: - Speech Recognition Actor

/// Actor that handles speech recognition with proper structured concurrency
/// Ensures thread-safe access to recognition state and proper cancellation
private actor SpeechRecognitionWorker {
    private var currentTask: SFSpeechRecognitionTask?
    private var isCompleted = false
    
    enum RecognitionResult {
        case success(String)
        case error(Error)
        case timeout
        case noSpeech
    }
    
    /// Performs speech recognition with proper cancellation handling
    func recognize(url: URL, timeout: TimeInterval = 30.0) async throws -> String {
        // Reset state
        isCompleted = false
        currentTask = nil
        
        guard let recognizer = SFSpeechRecognizer() else {
            throw InspectorError.speechRecognitionUnavailable
        }
        
        guard recognizer.isAvailable else {
            throw InspectorError.speechRecognitionUnavailable
        }
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        
        // Use async stream for structured result handling
        return try await withThrowingTaskGroup(of: RecognitionResult.self) { group in
            // Recognition task
            group.addTask {
                try await self.performRecognition(recognizer: recognizer, request: request, url: url)
            }
            
            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .timeout
            }
            
            // Wait for first result
            guard let result = try await group.next() else {
                throw InspectorError.extractionFailed("Recognition failed to produce result")
            }
            
            // Cancel remaining tasks
            group.cancelAll()
            
            // Also cancel the speech task if still running
            self.cancelCurrentTask()
            
            switch result {
            case .success(let transcript):
                return transcript
            case .error(let error):
                throw error
            case .timeout:
                NSLog("⚠️ [Speech] Recognition timed out after \(timeout)s for \(url.lastPathComponent)")
                throw InspectorError.extractionFailed("Speech recognition timed out")
            case .noSpeech:
                return ""
            }
        }
    }
    
    private func performRecognition(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest,
        url: URL
    ) async throws -> RecognitionResult {
        try await withCheckedThrowingContinuation { [weak self] continuation in
            // Use a class to capture mutable state safely
            let resumed = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
            resumed.initialize(to: false)
            
            let task = recognizer.recognitionTask(with: request) { result, error in
                // Ensure we only resume once
                guard !resumed.pointee else { return }
                
                if let error = error {
                    resumed.pointee = true
                    resumed.deallocate()
                    
                    let nsError = error as NSError
                    // Handle common non-error conditions
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        NSLog("ℹ️ [Speech] No speech detected for \(url.lastPathComponent)")
                        continuation.resume(returning: .noSpeech)
                        return
                    }
                    if nsError.domain == AVFoundationErrorDomain && nsError.code == -11800 {
                        NSLog("ℹ️ [Speech] AVFoundation completion for \(url.lastPathComponent)")
                        continuation.resume(returning: .noSpeech)
                        return
                    }
                    if nsError.domain == "kLSRErrorDomain" && nsError.code == 301 {
                        NSLog("ℹ️ [Speech] Recognition cancelled for \(url.lastPathComponent)")
                        continuation.resume(returning: .noSpeech)
                        return
                    }
                    
                    NSLog("⚠️ [Speech] Recognition error for \(url.lastPathComponent): \(nsError.localizedDescription)")
                    continuation.resume(returning: .error(InspectorError.extractionFailed(error.localizedDescription)))
                    return
                }
                
                guard let result = result, result.isFinal else {
                    return // Wait for final result
                }
                
                resumed.pointee = true
                resumed.deallocate()
                continuation.resume(returning: .success(result.bestTranscription.formattedString))
            }
            
            // Store task for potential cancellation
            Task { [weak self] in
                await self?.setCurrentTask(task)
            }
        }
    }
    
    private func setCurrentTask(_ task: SFSpeechRecognitionTask) {
        currentTask = task
    }
    
    func cancelCurrentTask() {
        if let task = currentTask, task.state == .running {
            task.cancel()
        }
        currentTask = nil
    }
}

/// Global speech recognition worker for thread-safe access
private let speechWorker = SpeechRecognitionWorker()

// MARK: - Inspector Errors
enum InspectorError: LocalizedError {
    case unsupportedFormat(String)
    case extractionFailed(String)
    case speechRecognitionUnavailable
    case visionRequestFailed(String)
    case audioExportFailed(String)
    case fileReadError(URL)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported format: \(format)"
        case .extractionFailed(let reason):
            return "Extraction failed: \(reason)"
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available"
        case .visionRequestFailed(let reason):
            return "Vision request failed: \(reason)"
        case .audioExportFailed(let reason):
            return "Audio export failed: \(reason)"
        case .fileReadError(let url):
            return "Cannot read file: \(url.lastPathComponent)"
        }
    }
}

// MARK: - Media Inspector Actor
/// The "Eye" of SortAI - extracts raw signals from files.
/// Uses Swift actors to prevent UI blocking during heavy compute operations.
actor MediaInspector: MediaInspecting {
    
    // MARK: - Configuration (Optimized for Speed)
    private let router = FileRouter()
    private let maxTextLength = 10_000       // Reduced from 50k for faster LLM processing
    private let maxVideoSamples = 5          // Only 5 key frames for categorization
    private let maxAudioDuration: TimeInterval = 15.0  // OPTIMIZED: Only 15 seconds for categorization
    private let ffmpegTimeout: TimeInterval = 45.0     // Allow a bit more headroom for large files
    private let speechTimeout: TimeInterval = 20.0     // OPTIMIZED: 20-second speech recognition timeout
    private let minVideoDurationForSpeech: TimeInterval = 20.0  // Skip speech for short videos
    private let useQuickHash = true          // Use metadata hash instead of full SHA256
    private let useSmartAudioSampler = true  // Use VAD-based audio extraction
    private let useFFmpegExtractor = true    // Use FFmpeg for audio extraction (preferred)
    private let useParallelAudioStrategies = true  // Try multiple extraction methods simultaneously
    
    // Smart audio sampler for fast speech extraction
    private let audioSampler = SmartAudioSampler(config: .fast)
    
    // FFmpeg-based audio extractor with optimized timeout
    private let ffmpegExtractor: CombinedAudioExtractor
    
    // MARK: - Initialization
    
    init() {
        // Create FFmpeg extractor with optimized configuration
        let ffmpegConfig = FFmpegAudioExtractor.Configuration(
            ffmpegPath: nil,
            sampleRate: 16000,
            channels: 1,
            outputCodec: "pcm_s16le",
            maxDuration: 15,  // Only extract 15 seconds
            timeout: 30.0     // 30-second timeout
        )
        self.ffmpegExtractor = CombinedAudioExtractor(ffmpegConfig: ffmpegConfig)
    }
    
    // MARK: - Public Interface
    
    /// Main entry point - inspects a file and returns a unified FileSignature
    func inspect(url: URL) async throws -> FileSignature {
        let inspectStart = Date()
        let filename = url.lastPathComponent
        NSLog("👁️ [MediaInspector] Starting inspection: \(filename)")
        
        let routeStart = Date()
        let strategy = try await router.route(url: url)
        NSLog("👁️ [MediaInspector] Route determined in \(String(format: "%.3f", Date().timeIntervalSince(routeStart)))s: \(strategy)")
        
        let fileSize = try fileSize(url: url)
        NSLog("👁️ [MediaInspector] File size: \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))")
        
        // Use quick metadata hash for speed (full SHA256 only when needed for deduplication)
        let hashStart = Date()
        let checksum = useQuickHash 
            ? (try FileHasher.quickHash(url: url))
            : (try await FileHasher.sha256(url: url))
        NSLog("👁️ [MediaInspector] Hash computed in \(String(format: "%.3f", Date().timeIntervalSince(hashStart)))s")
        
        let contentStart = Date()
        let result: FileSignature
        switch strategy {
        case .document(let docType):
            NSLog("👁️ [MediaInspector] Inspecting as document (\(docType))...")
            result = try await inspectDocument(url: url, type: docType, fileSize: fileSize, checksum: checksum)
        case .video:
            NSLog("👁️ [MediaInspector] Inspecting as video...")
            result = try await inspectVideo(url: url, fileSize: fileSize, checksum: checksum)
        case .image:
            NSLog("👁️ [MediaInspector] Inspecting as image...")
            result = try await inspectImage(url: url, fileSize: fileSize, checksum: checksum)
        case .audio:
            NSLog("👁️ [MediaInspector] Inspecting as audio...")
            result = try await inspectAudio(url: url, fileSize: fileSize, checksum: checksum)
        }
        
        let contentDuration = Date().timeIntervalSince(contentStart)
        let totalDuration = Date().timeIntervalSince(inspectStart)
        NSLog("👁️ [MediaInspector] Content extraction: \(String(format: "%.2f", contentDuration))s")
        NSLog("👁️ [MediaInspector] ✅ Inspection complete: \(filename) in \(String(format: "%.2f", totalDuration))s - textCue: \(result.textualCue.count) chars, tags: \(result.sceneTags.count)")
        
        return result
    }
    
    // MARK: - Document Inspection (Low Compute)
    
    private func inspectDocument(
        url: URL,
        type: InspectionStrategy.DocumentType,
        fileSize: Int64,
        checksum: String
    ) async throws -> FileSignature {
        let text: String
        var pageCount: Int?
        var slideCount: Int?
        
        switch type {
        case .pdf:
            guard let pdfDoc = PDFDocument(url: url) else {
                throw InspectorError.fileReadError(url)
            }
            pageCount = pdfDoc.pageCount
            text = extractPDFText(from: pdfDoc)
            
        case .plainText, .markdown:
            text = try String(contentsOf: url, encoding: .utf8)
            
        case .richText:
            text = try extractRichText(from: url)
            
        case .word:
            text = try extractWordDocument(from: url)
            
        case .excel:
            text = try extractExcelDocument(from: url)
            
        case .powerpoint:
            let (extractedText, slides) = try extractPowerPointDocument(from: url)
            text = extractedText
            slideCount = slides
            
        case .sourceCode:
            text = try extractSourceCode(from: url)
        }
        
        let truncatedText = String(text.prefix(maxTextLength))
        let wordCount = countWords(in: text)
        let language = detectLanguage(text: truncatedText)
        
        return FileSignature(
            url: url,
            kind: .document,
            title: url.deletingPathExtension().lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            fileSizeBytes: fileSize,
            checksum: checksum,
            textualCue: truncatedText,
            pageCount: pageCount ?? slideCount,
            wordCount: wordCount,
            language: language
        )
    }
    
    // MARK: - Video Inspection (High Compute)
    
    private func inspectVideo(
        url: URL,
        fileSize: Int64,
        checksum: String
    ) async throws -> FileSignature {
        let filename = url.lastPathComponent
        NSLog("🎬 [MediaInspector] Video inspection started: \(filename)")
        
        let asset = AVURLAsset(url: url)
        
        // Get video metadata (fast)
        let metaStart = Date()
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        
        var resolution: CGSize?
        var frameCount: Int?
        
        if let videoTrack = tracks.first {
            let size = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            resolution = size.applying(transform)
            
            let frameRate = try await videoTrack.load(.nominalFrameRate)
            frameCount = Int(durationSeconds * Double(frameRate))
        }
        
        // Check for audio track
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let hasAudio = !audioTracks.isEmpty
        NSLog("🎬 [MediaInspector] Metadata loaded in \(String(format: "%.3f", Date().timeIntervalSince(metaStart)))s - duration: \(String(format: "%.1f", durationSeconds))s, hasAudio: \(hasAudio)")
        
        // OPTIMIZATION: Run frame sampling, audio extraction, and subtitle extraction in PARALLEL
        // Note: extractAudioForTranscription is non-throwing (returns "" on failure)
        NSLog("🎬 [MediaInspector] Starting parallel extraction (frames + audio + subtitles)...")
        let extractStart = Date()
        async let framesTask = sampleKeyFrames(from: asset, duration: durationSeconds)
        async let audioTask = extractAudioForTranscription(url: url, hasAudio: hasAudio, videoDuration: durationSeconds)
        async let subtitlesTask = extractSubtitles(from: url)
        
        let frames = try await framesTask
        NSLog("🎬 [MediaInspector] Frames sampled: \(frames.count) keyframes")
        let audioText = await audioTask  // Non-throwing - empty string on failure
        NSLog("🎬 [MediaInspector] Audio extracted: \(audioText.count) chars")
        let subtitleText = await subtitlesTask  // Non-throwing - nil on failure
        NSLog("🎬 [MediaInspector] Subtitles extracted: \(subtitleText?.count ?? 0) chars")
        NSLog("🎬 [MediaInspector] Parallel extraction complete in \(String(format: "%.2f", Date().timeIntervalSince(extractStart)))s")
        
        // Combine audio transcript and subtitles
        var textComponents: [String] = []
        if !audioText.isEmpty {
            textComponents.append(audioText)
        }
        if let subs = subtitleText, !subs.isEmpty {
            textComponents.append(subs)
        }
        let text = textComponents.joined(separator: "\n\n")
        
        // OPTIMIZATION: Process all frames in parallel using TaskGroup
        let frameProcessStart = Date()
        NSLog("🎬 [MediaInspector] Processing \(frames.count) frames for classification...")
        let (allTags, allObjects, allColors) = await processFramesInParallel(frames)
        NSLog("🎬 [MediaInspector] Frame processing complete in \(String(format: "%.2f", Date().timeIntervalSince(frameProcessStart)))s - tags: \(allTags.count), objects: \(allObjects.count)")
        
        // Aggregate color data
        let colorCounts = Dictionary(grouping: allColors, by: { $0 }).mapValues { $0.count }
        let colorHexes = colorCounts.sorted { $0.value > $1.value }.prefix(5).map { $0.key }
        
        let tags = Array(allTags).sorted()
        let objects = Array(allObjects).sorted()
        
        return FileSignature(
            url: url,
            kind: .video,
            title: url.deletingPathExtension().lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            fileSizeBytes: fileSize,
            checksum: checksum,
            textualCue: text,
            sceneTags: tags,
            detectedObjects: objects,
            dominantColors: colorHexes,
            duration: durationSeconds,
            frameCount: frameCount,
            resolution: resolution,
            hasAudio: hasAudio
        )
    }
    
    // MARK: - Image Inspection
    
    private func inspectImage(
        url: URL,
        fileSize: Int64,
        checksum: String
    ) async throws -> FileSignature {
        guard let image = CIImage(contentsOf: url) else {
            throw InspectorError.fileReadError(url)
        }
        
        let resolution = image.extent.size
        
        async let sceneTags = classifyImage(image)
        async let detectedObjects = detectObjectsInImage(image)
        async let textFromImage = recognizeText(in: image)
        async let colors = extractColorsFromImage(image)
        
        let (tags, objects, text, colorHexes) = try await (sceneTags, detectedObjects, textFromImage, colors)
        
        return FileSignature(
            url: url,
            kind: .image,
            title: url.deletingPathExtension().lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            fileSizeBytes: fileSize,
            checksum: checksum,
            textualCue: text,
            sceneTags: tags,
            detectedObjects: objects,
            dominantColors: colorHexes,
            resolution: resolution
        )
    }
    
    // MARK: - Audio Inspection
    
    private func inspectAudio(
        url: URL,
        fileSize: Int64,
        checksum: String
    ) async throws -> FileSignature {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        let transcript = try await transcribeAudioFile(url: url)
        let language = detectLanguage(text: transcript)
        
        return FileSignature(
            url: url,
            kind: .audio,
            title: url.deletingPathExtension().lastPathComponent,
            fileExtension: url.pathExtension.lowercased(),
            fileSizeBytes: fileSize,
            checksum: checksum,
            textualCue: transcript,
            language: language,
            duration: durationSeconds,
            hasAudio: true
        )
    }
    
    // MARK: - Optimized Video Processing
    
    /// Samples only key frames at strategic positions (0%, 25%, 50%, 75%, near-end)
    /// Much faster than sampling every N seconds
    private func sampleKeyFrames(from asset: AVAsset, duration: TimeInterval) async throws -> [CIImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        
        // Sample at key points: start, 25%, 50%, 75%, near-end
        let positions = [0.0, 0.25, 0.5, 0.75, 0.95]
        let times = positions.map { CMTime(seconds: duration * $0, preferredTimescale: 600) }
        
        var frames: [CIImage] = []
        
        for await result in generator.images(for: times) {
            switch result {
            case .success(_, let cgImage, _):
                frames.append(CIImage(cgImage: cgImage))
            case .failure:
                continue
            }
        }
        
        return frames
    }
    
    /// Processes frames in parallel using TaskGroup for speed
    private func processFramesInParallel(_ frames: [CIImage]) async -> (Set<String>, Set<String>, [String]) {
        var allTags = Set<String>()
        var allObjects = Set<String>()
        var allColors = [String]()
        
        // Process all frames concurrently
        await withTaskGroup(of: (tags: [String], objects: [String], colors: [String]).self) { group in
            for frame in frames {
                group.addTask {
                    let tags = (try? await self.classifyImage(frame)) ?? []
                    let objects = (try? await self.detectObjectsInImage(frame)) ?? []
                    let colors = (try? await self.extractColorsFromImage(frame)) ?? []
                    return (tags, objects, colors)
                }
            }
            
            for await result in group {
                allTags.formUnion(result.tags)
                allObjects.formUnion(result.objects)
                allColors.append(contentsOf: result.colors)
            }
        }
        
        return (allTags, allObjects, allColors)
    }
    
    // MARK: - Subtitle Extraction
    
    /// Extract subtitles from video using FFmpeg
    /// Returns nil on failure (graceful fallback)
    private func extractSubtitles(from url: URL) async -> String? {
        guard useFFmpegExtractor else { return nil }
        
        // Access ffmpegExtractor directly since it's a CombinedAudioExtractor
        // We need to use the underlying FFmpegAudioExtractor for subtitle extraction
        let ffmpeg = FFmpegAudioExtractor(configuration: .default)
        
        do {
            return try await ffmpeg.extractSubtitles(from: url)
        } catch {
            // Subtitles are optional - don't log errors for missing subtitles
            return nil
        }
    }
    
    // MARK: - Smart Audio Extraction (Multi-Clip Strategy)
    
    /// Extracts and transcribes audio using multi-clip sampling strategy
    /// Returns empty string on failure (graceful fallback - video frames + filename will be used)
    /// NEW: Uses multi-clip strategy for long videos to capture representative content
    private func extractAudioForTranscription(url: URL, hasAudio: Bool, videoDuration: TimeInterval? = nil) async -> String {
        guard hasAudio else { return "" }
        
        // Validate duration
        guard let duration = videoDuration, duration > 0, duration.isFinite else {
            NSLog("⚠️ [MediaInspector] Invalid video duration, skipping audio extraction")
            return ""
        }
        
        // Skip speech recognition for very short videos (under 20 seconds)
        if duration < minVideoDurationForSpeech {
            NSLog("⏭️ [MediaInspector] Skipping speech recognition for short video (\(String(format: "%.1f", duration))s < \(minVideoDurationForSpeech)s)")
            return ""
        }
        
        let filename = url.lastPathComponent
        NSLog("🎤 [MediaInspector] Starting multi-clip audio extraction for: \(filename)")
        let startTime = Date()
        
        // Use multi-clip extraction strategy
        let result = await extractAudioMultiClip(url: url, videoDuration: duration)
        let elapsed = Date().timeIntervalSince(startTime)
        
        if !result.isEmpty {
            NSLog("✅ [MediaInspector] Audio extracted in \(String(format: "%.2f", elapsed))s (\(result.count) chars)")
        } else {
            NSLog("⚠️ [MediaInspector] All audio extraction attempts failed after \(String(format: "%.2f", elapsed))s - using visual cues")
        }
        
        return result
    }
    
    /// Multi-clip extraction: samples multiple positions throughout video
    private func extractAudioMultiClip(url: URL, videoDuration: TimeInterval) async -> String {
        // Calculate clip positions
        let clipExtractor = MultiClipExtractor(config: AudioConfiguration.fast)
        let clipPositions = await clipExtractor.calculateClipPositions(videoDuration: videoDuration)
        
        guard !clipPositions.isEmpty else {
            NSLog("⚠️ [MediaInspector] No valid clip positions calculated")
            return ""
        }
        
        var transcripts: [String] = []
        var successfulClips = 0
        var failedClips = 0
        
        // Extract and transcribe each clip
        for position in clipPositions {
            NSLog("🎬 [MediaInspector] Processing clip \(position.index + 1)/\(clipPositions.count) at \(String(format: "%.1f", position.startTime))s")
            
            let result = await extractAndTranscribeClip(
                url: url,
                position: position
            )
            
            if !result.transcript.isEmpty {
                transcripts.append(result.transcript)
                successfulClips += 1
                NSLog("✅ [MediaInspector] Clip \(position.index + 1) succeeded: \(result.transcript.count) chars via \(result.extractionMethod)")
            } else {
                failedClips += 1
                NSLog("⚠️ [MediaInspector] Clip \(position.index + 1) failed: \(result.error ?? "unknown error")")
            }
        }
        
        NSLog("📊 [MediaInspector] Multi-clip summary: \(successfulClips) succeeded, \(failedClips) failed")
        
        // Return aggregated transcripts
        return transcripts.joined(separator: "\n\n")
    }
    
    /// Extract and transcribe a single clip with fallback chain
    private func extractAndTranscribeClip(
        url: URL,
        position: ClipPosition
    ) async -> ClipExtractionResult {
        let clipExtractor = MultiClipExtractor(config: AudioConfiguration.fast)
        let timeout = await clipExtractor.calculateTimeout(for: position.duration)
        let retryCount = 0
        let startTime = Date()
        
        // Strategy 1: FFmpeg contiguous clip (PRIMARY for multi-clip)
        if useFFmpegExtractor {
            if let result = await tryFFmpegClip(url: url, position: position, timeout: timeout) {
                let elapsed = Date().timeIntervalSince(startTime)
                return ClipExtractionResult(
                    position: position,
                    audioURL: nil,
                    transcript: result,
                    extractionMethod: "FFmpeg",
                    extractionTime: elapsed,
                    transcriptionTime: 0,
                    retryCount: retryCount,
                    error: nil
                )
            }
        }
        
        // Strategy 2: AVFoundation clip export
        if let result = await tryAVFoundationClip(url: url, position: position) {
            let elapsed = Date().timeIntervalSince(startTime)
            return ClipExtractionResult(
                position: position,
                audioURL: nil,
                transcript: result,
                extractionMethod: "AVFoundation",
                extractionTime: elapsed,
                transcriptionTime: 0,
                retryCount: retryCount,
                error: nil
            )
        }
        
        // Strategy 3: VAD-based sampling (fallback for clips)
        if useSmartAudioSampler {
            if let result = await trySmartSampling(url: url) {
                let elapsed = Date().timeIntervalSince(startTime)
                return ClipExtractionResult(
                    position: position,
                    audioURL: nil,
                    transcript: result,
                    extractionMethod: "VAD",
                    extractionTime: elapsed,
                    transcriptionTime: 0,
                    retryCount: retryCount,
                    error: nil
                )
            }
        }
        
        // All strategies failed
        let elapsed = Date().timeIntervalSince(startTime)
        return ClipExtractionResult(
            position: position,
            audioURL: nil,
            transcript: "",
            extractionMethod: "None",
            extractionTime: elapsed,
            transcriptionTime: 0,
            retryCount: retryCount,
            error: "All extraction methods failed"
        )
    }
    
    /// Try extracting a clip using FFmpeg with optional audio separation
    private func tryFFmpegClip(url: URL, position: ClipPosition, timeout: TimeInterval) async -> String? {
        let start = Date()
        
        do {
            // Try without audio separation first
            let audioURL = try await ffmpegExtractor.extractAudioClip(
                from: url,
                startTime: position.startTime,
                duration: position.duration,
                timeout: timeout,
                applySeparation: false
            )
            
            defer {
                Task {
                    await TempFileManager.shared.cleanup(audioURL)
                }
            }
            
            let transcript = try await transcribeAudioFileWithTimeout(url: audioURL, timeout: speechTimeout)
            let elapsed = Date().timeIntervalSince(start)
            
            if !transcript.isEmpty {
                NSLog("✅ [MediaInspector] FFmpeg clip succeeded (\(String(format: "%.2f", elapsed))s)")
                return transcript
            }
            
            // Try with audio separation if empty result
            NSLog("🔧 [MediaInspector] Retrying with audio separation")
            let separatedURL = try await ffmpegExtractor.extractAudioClip(
                from: url,
                startTime: position.startTime,
                duration: position.duration,
                timeout: timeout,
                applySeparation: true
            )
            
            defer {
                Task {
                    await TempFileManager.shared.cleanup(separatedURL)
                }
            }
            
            let separatedTranscript = try await transcribeAudioFileWithTimeout(url: separatedURL, timeout: speechTimeout)
            let totalElapsed = Date().timeIntervalSince(start)
            
            if !separatedTranscript.isEmpty {
                NSLog("✅ [MediaInspector] FFmpeg with separation succeeded (\(String(format: "%.2f", totalElapsed))s)")
                return separatedTranscript
            }
            
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            NSLog("⚠️ [MediaInspector] FFmpeg clip failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// Try extracting a clip using AVFoundation
    private func tryAVFoundationClip(url: URL, position: ClipPosition) async -> String? {
        let start = Date()
        var audioURL: URL?
        
        do {
            audioURL = try await ffmpegExtractor.extractAudioClip(
                from: url,
                startTime: position.startTime,
                duration: position.duration,
                timeout: nil,
                applySeparation: false
            )
            
            guard let outputURL = audioURL else {
                return nil
            }
            
            defer {
                Task {
                    await TempFileManager.shared.cleanup(outputURL)
                }
            }
            
            let transcript = try await transcribeAudioFileWithTimeout(url: outputURL, timeout: speechTimeout)
            let elapsed = Date().timeIntervalSince(start)
            
            if !transcript.isEmpty {
                NSLog("✅ [MediaInspector] AVFoundation clip succeeded (\(String(format: "%.2f", elapsed))s)")
                return transcript
            }
            
        } catch {
            if let url = audioURL {
                await TempFileManager.shared.cleanup(url)
            }
            let elapsed = Date().timeIntervalSince(start)
            NSLog("⚠️ [MediaInspector] AVFoundation clip failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    /// PARALLEL audio extraction - tries multiple strategies simultaneously
    /// Returns first successful result or empty string if all fail
    private func extractAudioParallel(url: URL) async -> String {
        // Create a task group with timeout
        return await withTaskGroup(of: String?.self) { group in
            var completedResult: String?
            
            // Strategy 1: FFmpeg (fastest for most formats)
            if useFFmpegExtractor {
                group.addTask {
                    await self.tryFFmpegExtraction(url: url)
                }
            }
            
            // Strategy 2: Smart VAD sampling
            if useSmartAudioSampler {
                group.addTask {
                    await self.trySmartSampling(url: url)
                }
            }
            
            // Strategy 3: Simple time sampling (fallback)
            group.addTask {
                await self.trySampleExtraction(url: url)
            }
            
            // Return first non-empty result
            for await result in group {
                if let transcript = result, !transcript.isEmpty {
                    completedResult = transcript
                    group.cancelAll()  // Cancel remaining tasks
                    break
                }
            }
            
            return completedResult ?? ""
        }
    }
    
    /// Try FFmpeg-based extraction with timeout
    private func tryFFmpegExtraction(url: URL) async -> String? {
        let start = Date()
        do {
            let audioURL = try await ffmpegExtractor.extractAudio(from: url)
            let extractionElapsed = Date().timeIntervalSince(start)
            defer { try? FileManager.default.removeItem(at: audioURL) }
            
            let speechStart = Date()
            let transcript = try await transcribeAudioFileWithTimeout(url: audioURL, timeout: speechTimeout)
            let speechElapsed = Date().timeIntervalSince(speechStart)
            if !transcript.isEmpty {
                NSLog("✅ [MediaInspector] FFmpeg extraction succeeded (audio: \(String(format: "%.2f", extractionElapsed))s, speech: \(String(format: "%.2f", speechElapsed))s)")
                return transcript
            }
            
            NSLog("ℹ️ [MediaInspector] FFmpeg transcript was empty (audio: \(String(format: "%.2f", extractionElapsed))s, speech: \(String(format: "%.2f", speechElapsed))s)")
        } catch {
            if case FFmpegError.extractionFailed(let reason) = error, reason.localizedCaseInsensitiveContains("no speech detected") {
                NSLog("ℹ️ [MediaInspector] FFmpeg extraction produced no speech for \(url.lastPathComponent)")
                return nil
            }
            let elapsed = Date().timeIntervalSince(start)
            NSLog("⚠️ [MediaInspector] FFmpeg extraction failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
        }
        return nil
    }
    
    /// Try smart VAD-based sampling
    private func trySmartSampling(url: URL) async -> String? {
        let start = Date()
        do {
            let result = try await audioSampler.extractSpeech(from: url)
            let extractionElapsed = Date().timeIntervalSince(start)
            defer { try? FileManager.default.removeItem(at: result.tempAudioURL) }
            
            let speechStart = Date()
            let transcript = try await transcribeAudioFileWithTimeout(url: result.tempAudioURL, timeout: speechTimeout)
            let speechElapsed = Date().timeIntervalSince(speechStart)
            if !transcript.isEmpty {
                NSLog("✅ [MediaInspector] Smart sampling succeeded (audio: \(String(format: "%.2f", extractionElapsed))s, speech: \(String(format: "%.2f", speechElapsed))s)")
                return transcript
            }
        } catch {
            if error is CancellationError || error.localizedDescription == "Operation Stopped" || error.localizedDescription.localizedCaseInsensitiveContains("Not enough speech") {
                return nil
            }
            let elapsed = Date().timeIntervalSince(start)
            NSLog("⚠️ [MediaInspector] Smart sampling failed after \(String(format: "%.2f", elapsed))s: \(error.localizedDescription)")
        }
        return nil
    }
    
    /// Try simple time-based sampling at beginning/middle/end
    private func trySampleExtraction(url: URL) async -> String? {
        do {
            let asset = AVURLAsset(url: url)
            let transcript = try await transcribeAudioSample(asset: asset, url: url, maxDuration: maxAudioDuration)
            if !transcript.isEmpty {
                NSLog("✅ [MediaInspector] Simple sampling succeeded")
                return transcript
            }
        } catch {
            if error.localizedDescription.localizedCaseInsensitiveContains("No compatible export preset") {
                return nil
            }
            NSLog("⚠️ [MediaInspector] Simple sampling failed: \(error.localizedDescription)")
        }
        return nil
    }
    
    /// Sequential audio extraction (fallback if parallel disabled)
    private func extractAudioSequential(url: URL) async -> String {
        // Strategy 0: FFmpeg extraction (PRIMARY)
        if useFFmpegExtractor {
            if let transcript = await tryFFmpegExtraction(url: url) {
                return transcript
            }
        }
        
        // Strategy 1: Smart VAD sampling
        if useSmartAudioSampler {
            if let transcript = await trySmartSampling(url: url) {
                return transcript
            }
        }
        
        // Strategy 2: Simple sampling
        if let transcript = await trySampleExtraction(url: url) {
            return transcript
        }
        
        // All strategies failed
        NSLog("ℹ️ [MediaInspector] All audio strategies failed - using visual + filename cues")
        return ""
    }
    
    /// Transcribe audio file with configurable timeout
    private func transcribeAudioFileWithTimeout(url: URL, timeout: TimeInterval) async throws -> String {
        // Delegate directly to speech worker with the specified timeout
        try await speechWorker.recognize(url: url, timeout: timeout)
    }
    
    /// Transcribes only the first N seconds of audio for speed (fallback method)
    private func transcribeAudioSample(asset: AVAsset, url: URL, maxDuration: TimeInterval) async throws -> String {
        // Create a temporary file for the audio sample
        let tempDir = FileManager.default.temporaryDirectory
        let tempAudioURL = tempDir.appendingPathComponent("audio_sample_\(UUID().uuidString).m4a")
        
        defer {
            try? FileManager.default.removeItem(at: tempAudioURL)
        }
        
        // Export only the first N seconds of audio
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let sampleDuration = min(maxDuration, durationSeconds)
        
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: sampleDuration, preferredTimescale: 600)
        )
        
        // Try multiple export presets for compatibility
        let presets = [
            AVAssetExportPresetAppleM4A,
            AVAssetExportPresetPassthrough,
            AVAssetExportPresetLowQuality
        ]
        
        for preset in presets {
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue
            }
            
            // Check if this preset is compatible
            let compatibleTypes = exportSession.supportedFileTypes
            guard !compatibleTypes.isEmpty else { continue }
            
            let outputType: AVFileType = compatibleTypes.contains(.m4a) ? .m4a : (compatibleTypes.first ?? .m4a)
            let outputExtension = outputType == .m4a ? "m4a" : "mov"
            let outputURL = tempDir.appendingPathComponent("audio_sample_\(UUID().uuidString).\(outputExtension)")
            
            exportSession.outputURL = outputURL
            exportSession.outputFileType = outputType
            exportSession.timeRange = timeRange
            
            do {
                try await exportSession.export(to: outputURL, as: outputType)
                let transcript = try await transcribeAudioFile(url: outputURL)
                try? FileManager.default.removeItem(at: outputURL)
                return transcript
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                continue // Try next preset
            }
        }
        
        // All export presets failed
        throw InspectorError.extractionFailed("No compatible export preset found")
    }
    
    /// Classifies a single image using Vision
    private func classifyImage(_ image: CIImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()
            
            func safeResume(_ result: Result<[String], Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }
            
            let request = VNClassifyImageRequest { request, error in
                if let error = error {
                    safeResume(.failure(InspectorError.visionRequestFailed(error.localizedDescription)))
                    return
                }
                
                guard let observations = request.results as? [VNClassificationObservation] else {
                    safeResume(.success([]))
                    return
                }
                
                // Return top classifications with confidence > 0.3
                let tags = observations
                    .filter { $0.confidence > 0.3 }
                    .prefix(10)
                    .map { $0.identifier }
                
                safeResume(.success(Array(tags)))
            }
            
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                safeResume(.failure(InspectorError.visionRequestFailed(error.localizedDescription)))
            }
        }
    }
    
    /// Detects objects (faces, animals, etc.) in image
    private func detectObjectsInImage(_ image: CIImage) async throws -> [String] {
        var objects = [String]()
        
        // Detect faces
        let faceCount = try await detectFaces(in: image)
        if faceCount > 0 {
            objects.append("face (\(faceCount))")
        }
        
        // Detect animals
        let animals = try await detectAnimals(in: image)
        objects.append(contentsOf: animals)
        
        // Detect text regions
        let hasText = try await detectTextRegions(in: image)
        if hasText {
            objects.append("text")
        }
        
        return objects
    }
    
    private func detectFaces(in image: CIImage) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()
            
            func safeResume(_ result: Result<Int, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }
            
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    safeResume(.failure(InspectorError.visionRequestFailed(error.localizedDescription)))
                    return
                }
                
                let count = (request.results as? [VNFaceObservation])?.count ?? 0
                safeResume(.success(count))
            }
            
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                safeResume(.failure(InspectorError.visionRequestFailed(error.localizedDescription)))
            }
        }
    }
    
    private func detectAnimals(in image: CIImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()
            
            func safeResume(_ result: Result<[String], Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }
            
            let request = VNRecognizeAnimalsRequest { request, error in
                if let error = error {
                    safeResume(.failure(InspectorError.visionRequestFailed(error.localizedDescription)))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedObjectObservation] else {
                    safeResume(.success([]))
                    return
                }
                
                let animals = observations.flatMap { observation in
                    observation.labels.filter { $0.confidence > 0.5 }.map { $0.identifier }
                }
                
                safeResume(.success(animals))
            }
            
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                safeResume(.failure(InspectorError.visionRequestFailed(error.localizedDescription)))
            }
        }
    }
    
    private func detectTextRegions(in image: CIImage) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()
            
            func safeResume(_ result: Result<Bool, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }
            
            let request = VNDetectTextRectanglesRequest { request, error in
                if let error = error {
                    safeResume(.failure(InspectorError.visionRequestFailed(error.localizedDescription)))
                    return
                }
                
                let results = request.results as? [VNTextObservation]
                let hasText = results?.isEmpty == false
                safeResume(.success(hasText))
            }
            
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                safeResume(.failure(InspectorError.visionRequestFailed(error.localizedDescription)))
            }
        }
    }
    
    /// OCR text recognition
    private func recognizeText(in image: CIImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            let lock = NSLock()
            
            func safeResume(_ result: Result<String, Error>) {
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }
            
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    safeResume(.failure(InspectorError.visionRequestFailed(error.localizedDescription)))
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    safeResume(.success(""))
                    return
                }
                
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
                safeResume(.success(text))
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(ciImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                safeResume(.failure(InspectorError.visionRequestFailed(error.localizedDescription)))
            }
        }
    }
    
    /// Extracts dominant colors from image
    private func extractColorsFromImage(_ image: CIImage) async throws -> [String] {
        // Use Core Image to sample colors
        let context = CIContext()
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            return []
        }
        
        // Sample center pixel and corner pixels for quick color extraction
        let width = cgImage.width
        let height = cgImage.height
        
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return []
        }
        
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let bytesPerRow = cgImage.bytesPerRow
        
        func colorAt(x: Int, y: Int) -> String? {
            let offset = y * bytesPerRow + x * bytesPerPixel
            let r = bytes[offset]
            let g = bytes[offset + 1]
            let b = bytes[offset + 2]
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        
        var colors = [String]()
        
        // Sample 5 points
        let points = [
            (width / 2, height / 2),  // center
            (width / 4, height / 4),  // top-left
            (3 * width / 4, height / 4),  // top-right
            (width / 4, 3 * height / 4),  // bottom-left
            (3 * width / 4, 3 * height / 4)  // bottom-right
        ]
        
        for (x, y) in points {
            if let color = colorAt(x: x, y: y) {
                colors.append(color)
            }
        }
        
        return Array(Set(colors))  // Deduplicate
    }
    
    // MARK: - Speech Recognition Helpers
    
    /// Transcribes audio from video asset using SFSpeechRecognizer
    private func transcribeAudio(asset: AVAsset, url: URL) async throws -> String {
        // Export audio track to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        try await exportAudio(from: asset, to: tempURL)
        return try await transcribeAudioFile(url: tempURL)
    }
    
    /// Exports audio track from video to separate file
    private func exportAudio(from asset: AVAsset, to outputURL: URL) async throws {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw InspectorError.audioExportFailed("Cannot create export session")
        }
        
        do {
            try await exportSession.export(to: outputURL, as: .m4a)
        } catch {
            throw InspectorError.audioExportFailed(error.localizedDescription)
        }
    }
    
    /// Transcribes audio file using SFSpeechRecognizer with structured concurrency
    private func transcribeAudioFile(url: URL) async throws -> String {
        // Use the actor-based speech worker for proper thread safety
        try await speechWorker.recognize(url: url, timeout: 30.0)
    }
    
    // MARK: - Document Extraction Helpers
    
    private func extractPDFText(from document: PDFDocument) -> String {
        (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")
    }
    
    private func extractRichText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let attributedString = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        return attributedString.string
    }
    
    private func extractWordDocument(from url: URL) throws -> String {
        let filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        var extractedText: String? = nil
        var lastError: String? = nil
        
        NSLog("📄 [MediaInspector] Attempting Word document extraction: \(filename)")
        
        // Strategy 1: For .docx files, extract from ZIP archive (Office Open XML)
        if ext == "docx" {
            if let text = extractDocxFromZip(url: url) {
                NSLog("✅ [MediaInspector] Successfully extracted .docx via ZIP: \(text.count) chars")
                return text
            }
            lastError = "ZIP extraction failed"
        }
        
        // Strategy 2: Try NSAttributedString with Office Open XML type (for .docx)
        if extractedText == nil {
            do {
                let data = try Data(contentsOf: url)
                let attributedString = try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                    documentAttributes: nil
                )
                if !attributedString.string.isEmpty {
                    extractedText = attributedString.string
                    NSLog("✅ [MediaInspector] Successfully extracted via NSAttributedString (OOXML): \(extractedText!.count) chars")
                }
            } catch {
                lastError = "NSAttributedString OOXML: \(error.localizedDescription)"
            }
        }
        
        // Strategy 3: Try NSAttributedString with legacy .doc format
        if extractedText == nil {
            do {
                let data = try Data(contentsOf: url)
                let attributedString = try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.docFormat],
                    documentAttributes: nil
                )
                if !attributedString.string.isEmpty {
                    extractedText = attributedString.string
                    NSLog("✅ [MediaInspector] Successfully extracted via NSAttributedString (DOC): \(extractedText!.count) chars")
                }
            } catch {
                lastError = "NSAttributedString DOC: \(error.localizedDescription)"
            }
        }
        
        // Strategy 4: Try reading as plain text (some .doc files are actually plain text)
        if extractedText == nil {
            if let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty {
                // Check if it looks like actual text content (not binary garbage)
                let printableRatio = Double(text.unicodeScalars.filter { $0.isASCII && $0.value >= 32 }.count) / Double(text.count)
                if printableRatio > 0.8 {
                    extractedText = text
                    NSLog("✅ [MediaInspector] Successfully read as plain text: \(text.count) chars")
                }
            }
        }
        
        // Strategy 5: Try textutil command (macOS built-in converter)
        if extractedText == nil {
            if let text = extractViaTextutil(url: url) {
                extractedText = text
                NSLog("✅ [MediaInspector] Successfully extracted via textutil: \(text.count) chars")
            }
        }
        
        // If we got text, return it
        if let text = extractedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        
        // Graceful degradation: Return filename-based metadata instead of throwing
        // This allows categorization to proceed using filename cues
        NSLog("⚠️ [MediaInspector] All Word extraction methods failed for: \(filename). Using filename fallback. Last error: \(lastError ?? "unknown")")
        
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? Int64) ?? 0
        let modDate = (attributes?[.modificationDate] as? Date)?.ISO8601Format() ?? "unknown"
        
        return """
        [Word Document - Content Extraction Unavailable]
        Filename: \(filename)
        Size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        Modified: \(modDate)
        Note: Document content could not be extracted. Categorization based on filename only.
        """
    }
    
    /// Extract text content from .docx file by unzipping and parsing document.xml
    private func extractDocxFromZip(url: URL) -> String? {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        // Use unzip command to extract
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", url.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                return nil
            }
        } catch {
            return nil
        }
        
        var extractedText: [String] = []
        
        // Read document.xml (main content)
        let documentPath = tempDir.appendingPathComponent("word/document.xml")
        if let documentData = try? Data(contentsOf: documentPath),
           let documentContent = String(data: documentData, encoding: .utf8) {
            // Extract text from <w:t> tags (Word text elements)
            let pattern = "<w:t[^>]*>([^<]*)</w:t>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(documentContent.startIndex..., in: documentContent)
                let matches = regex.matches(in: documentContent, options: [], range: range)
                for match in matches {
                    if let textRange = Range(match.range(at: 1), in: documentContent) {
                        let text = String(documentContent[textRange])
                        if !text.isEmpty {
                            extractedText.append(text)
                        }
                    }
                }
            }
        }
        
        // If we found text, join it with spaces
        let result = extractedText.joined(separator: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return result.isEmpty ? nil : String(result.prefix(maxTextLength))
    }
    
    /// Extract text using macOS textutil command
    private func extractViaTextutil(url: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-stdout", "-convert", "txt", url.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                return nil
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return String(text.prefix(maxTextLength))
            }
        } catch {
            return nil
        }
        
        return nil
    }
    
    /// Extract text from Excel files (.xlsx, .xls, .csv, .numbers)
    private func extractExcelDocument(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        
        // CSV is plain text
        if ext == "csv" {
            let content = try String(contentsOf: url, encoding: .utf8)
            // Parse CSV to extract meaningful content
            let lines = content.components(separatedBy: .newlines)
            let preview = lines.prefix(100).joined(separator: "\n")
            let summary = "CSV file with \(lines.count) rows. Headers: \(lines.first ?? "")"
            return summary + "\n\nContent Preview:\n" + preview
        }
        
        // For .xlsx files (Office Open XML), extract from ZIP archive
        if ext == "xlsx" {
            return try extractXLSXContent(from: url)
        }
        
        // For .xls (binary format) or .numbers, try basic metadata
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? Int64) ?? 0
        return "Excel spreadsheet (\(ext)), \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
    }
    
    /// Extract text from XLSX (Office Open XML) format
    private func extractXLSXContent(from url: URL) throws -> String {
        // XLSX is a ZIP archive containing XML files
        // Extract sharedStrings.xml for text content
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        // Use unzip command to extract
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", url.path, "-d", tempDir.path]
        
        try process.run()
        process.waitUntilExit()
        
        var extractedText: [String] = []
        
        // Try to read sharedStrings.xml (contains cell text values)
        let sharedStringsPath = tempDir.appendingPathComponent("xl/sharedStrings.xml")
        if let sharedData = try? Data(contentsOf: sharedStringsPath),
           let sharedContent = String(data: sharedData, encoding: .utf8) {
            // Extract <t> tags content (text values)
            let pattern = "<t[^>]*>([^<]+)</t>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(sharedContent.startIndex..., in: sharedContent)
                let matches = regex.matches(in: sharedContent, options: [], range: range)
                for match in matches.prefix(500) { // Limit to 500 values
                    if let textRange = Range(match.range(at: 1), in: sharedContent) {
                        extractedText.append(String(sharedContent[textRange]))
                    }
                }
            }
        }
        
        // Also try to get sheet names from workbook.xml
        let workbookPath = tempDir.appendingPathComponent("xl/workbook.xml")
        if let workbookData = try? Data(contentsOf: workbookPath),
           let workbookContent = String(data: workbookData, encoding: .utf8) {
            let namePattern = "name=\"([^\"]+)\""
            if let regex = try? NSRegularExpression(pattern: namePattern, options: []) {
                let range = NSRange(workbookContent.startIndex..., in: workbookContent)
                let matches = regex.matches(in: workbookContent, options: [], range: range)
                let sheetNames = matches.compactMap { match -> String? in
                    if let nameRange = Range(match.range(at: 1), in: workbookContent) {
                        return String(workbookContent[nameRange])
                    }
                    return nil
                }
                if !sheetNames.isEmpty {
                    extractedText.insert("Sheets: \(sheetNames.joined(separator: ", "))", at: 0)
                }
            }
        }
        
        return extractedText.isEmpty ? "Excel spreadsheet (no text content extracted)" : extractedText.joined(separator: "\n")
    }
    
    /// Extract text from PowerPoint files (.pptx, .ppt, .key)
    private func extractPowerPointDocument(from url: URL) throws -> (String, Int) {
        let ext = url.pathExtension.lowercased()
        
        // For .pptx (Office Open XML), extract from ZIP archive
        if ext == "pptx" {
            return try extractPPTXContent(from: url)
        }
        
        // For .ppt (binary) or .key (Keynote), try basic approach
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? Int64) ?? 0
        return ("PowerPoint presentation (\(ext)), \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))", 0)
    }
    
    /// Extract text from PPTX (Office Open XML) format
    private func extractPPTXContent(from url: URL) throws -> (String, Int) {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        // Use unzip command to extract
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", url.path, "-d", tempDir.path]
        
        try process.run()
        process.waitUntilExit()
        
        var extractedText: [String] = []
        var slideCount = 0
        
        // Extract text from each slide (ppt/slides/slideN.xml)
        let slidesDir = tempDir.appendingPathComponent("ppt/slides")
        if let slideFiles = try? fileManager.contentsOfDirectory(atPath: slidesDir.path) {
            let xmlSlides = slideFiles.filter { $0.hasPrefix("slide") && $0.hasSuffix(".xml") }.sorted()
            slideCount = xmlSlides.count
            
            for (index, slideFile) in xmlSlides.prefix(50).enumerated() { // Limit to 50 slides
                let slidePath = slidesDir.appendingPathComponent(slideFile)
                if let slideData = try? Data(contentsOf: slidePath),
                   let slideContent = String(data: slideData, encoding: .utf8) {
                    // Extract <a:t> tags (text content)
                    let pattern = "<a:t>([^<]+)</a:t>"
                    if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                        let range = NSRange(slideContent.startIndex..., in: slideContent)
                        let matches = regex.matches(in: slideContent, options: [], range: range)
                        var slideTexts: [String] = []
                        for match in matches {
                            if let textRange = Range(match.range(at: 1), in: slideContent) {
                                slideTexts.append(String(slideContent[textRange]))
                            }
                        }
                        if !slideTexts.isEmpty {
                            extractedText.append("Slide \(index + 1): \(slideTexts.joined(separator: " | "))")
                        }
                    }
                }
            }
        }
        
        let summary = "PowerPoint presentation with \(slideCount) slides"
        let content = extractedText.isEmpty ? "" : extractedText.joined(separator: "\n")
        return (summary + "\n\n" + content, slideCount)
    }
    
    /// Extract source code content with syntax context
    private func extractSourceCode(from url: URL) throws -> String {
        let content = try String(contentsOf: url, encoding: .utf8)
        let ext = url.pathExtension.lowercased()
        
        // Get language-specific context
        let language = languageFromExtension(ext)
        let lines = content.components(separatedBy: .newlines)
        
        // Extract meaningful portions
        var extractedContent: [String] = []
        extractedContent.append("Source code file: \(language)")
        extractedContent.append("Lines: \(lines.count)")
        
        // Extract imports/includes (usually at top)
        let importLines = lines.prefix(50).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("import ") || 
                   trimmed.hasPrefix("#include") ||
                   trimmed.hasPrefix("from ") ||
                   trimmed.hasPrefix("require") ||
                   trimmed.hasPrefix("using ")
        }
        if !importLines.isEmpty {
            extractedContent.append("Imports: \(importLines.prefix(10).joined(separator: ", "))")
        }
        
        // Extract function/class definitions
        let definitionPatterns = [
            "func ", "function ", "def ", "class ", "struct ", "enum ", 
            "interface ", "public ", "private ", "protected ", "@"
        ]
        let definitions = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return definitionPatterns.contains { trimmed.hasPrefix($0) }
        }
        if !definitions.isEmpty {
            extractedContent.append("Definitions found: \(min(definitions.count, 50))")
            extractedContent.append(contentsOf: definitions.prefix(20).map { "  - \($0.trimmingCharacters(in: .whitespaces).prefix(80))" })
        }
        
        // Extract comments (might contain documentation)
        let commentPatterns = ["//", "/*", "#", "'''", "\"\"\""]
        let comments = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return commentPatterns.contains { trimmed.hasPrefix($0) }
        }
        if comments.count > 3 {
            extractedContent.append("Comments: \(comments.count) lines")
        }
        
        // Include first portion of code for context
        let codePreview = String(content.prefix(2000))
        extractedContent.append("\nCode preview:\n\(codePreview)")
        
        return extractedContent.joined(separator: "\n")
    }
    
    private func languageFromExtension(_ ext: String) -> String {
        switch ext {
        case "swift": return "Swift"
        case "py": return "Python"
        case "js": return "JavaScript"
        case "ts": return "TypeScript"
        case "java": return "Java"
        case "c": return "C"
        case "cpp", "cc", "cxx": return "C++"
        case "h", "hpp": return "C/C++ Header"
        case "cs": return "C#"
        case "go": return "Go"
        case "rs": return "Rust"
        case "rb": return "Ruby"
        case "php": return "PHP"
        case "html", "htm": return "HTML"
        case "css": return "CSS"
        case "json": return "JSON"
        case "xml": return "XML"
        case "yaml", "yml": return "YAML"
        case "sh", "bash": return "Shell Script"
        case "sql": return "SQL"
        default: return "Source Code"
        }
    }
    
    // MARK: - Text Analysis Helpers
    
    private func countWords(in text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }
    
    private func detectLanguage(text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
    
    // MARK: - Utilities
    
    private func fileSize(url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
}
