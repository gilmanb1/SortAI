// MARK: - FFmpeg Audio Extractor
// Robust audio extraction using FFmpeg with AVFoundation fallback

import Foundation
import AVFoundation

// MARK: - FFmpeg Extractor Protocol

/// Protocol for audio extraction implementations
protocol AudioExtractor: Actor {
    /// Extract audio from a video/audio file to a temporary WAV file
    func extractAudio(from url: URL) async throws -> URL
    
    /// Check if the extractor is available
    func isAvailable() async -> Bool
    
    /// Get supported formats
    var supportedFormats: Set<String> { get }
}

// MARK: - FFmpeg Audio Extractor

/// Audio extractor using FFmpeg CLI (installed via Homebrew or bundled)
actor FFmpegAudioExtractor: AudioExtractor {
    
    // MARK: - Configuration
    
    struct Configuration: Sendable {
        /// Path to FFmpeg binary (auto-detected if nil)
        let ffmpegPath: String?
        
        /// Audio sample rate for output
        let sampleRate: Int
        
        /// Number of audio channels
        let channels: Int
        
        /// Audio codec for output
        let outputCodec: String
        
        /// Maximum duration to extract (seconds, nil for full)
        let maxDuration: TimeInterval?
        
        /// Timeout for extraction (seconds)
        let timeout: TimeInterval
        
        static let `default` = Configuration(
            ffmpegPath: nil,
            sampleRate: 16000,  // 16kHz for speech recognition
            channels: 1,        // Mono
            outputCodec: "pcm_s16le",  // 16-bit PCM
            maxDuration: nil,
            timeout: 120.0
        )
        
        /// Configuration optimized for speech recognition
        static let speechRecognition = Configuration(
            ffmpegPath: nil,
            sampleRate: 16000,
            channels: 1,
            outputCodec: "pcm_s16le",
            maxDuration: 300,  // First 5 minutes
            timeout: 60.0
        )
    }
    
    // MARK: - Properties
    
    private let config: Configuration
    private var detectedFFmpegPath: String?
    private var hasCheckedFFmpeg = false
    
    let supportedFormats: Set<String> = [
        "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v",  // Video
        "mp3", "m4a", "wav", "aac", "flac", "ogg", "wma", "aiff"  // Audio
    ]
    
    // MARK: - Initialization
    
    init(configuration: Configuration = .default) {
        self.config = configuration
    }
    
    // MARK: - AudioExtractor Protocol
    
    func isAvailable() async -> Bool {
        return await findFFmpeg() != nil
    }
    
    func extractAudio(from url: URL) async throws -> URL {
        guard let ffmpegPath = await findFFmpeg() else {
            throw FFmpegError.ffmpegNotFound
        }
        
        let startTime = Date()
        let maxDurationDesc = config.maxDuration.map { "\(Int($0))s" } ?? "full"
        NSLog("🎬 [FFmpeg] Extracting audio from \(url.lastPathComponent) (limit: \(maxDurationDesc), timeout: \(Int(config.timeout))s)")
        
        // Create temporary output file
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        
        // Build FFmpeg command
        var arguments = [
            "-i", url.path,           // Input file
            "-vn",                     // No video
            "-acodec", config.outputCodec,
            "-ar", String(config.sampleRate),
            "-ac", String(config.channels),
            "-y"                       // Overwrite output
        ]
        
        // Add duration limit if specified
        if let maxDuration = config.maxDuration {
            arguments.insert(contentsOf: ["-t", String(maxDuration)], at: 2)
        }
        
        arguments.append(outputURL.path)
        
        // Run FFmpeg
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = arguments
        
        // Capture stderr for error messages
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        
        // Run with timeout
        do {
            try process.run()
            
            // Wait with timeout
            let deadline = Date().addingTimeInterval(config.timeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            
            if process.isRunning {
                process.terminate()
                let elapsed = Date().timeIntervalSince(startTime)
                NSLog("⚠️ [FFmpeg] Extraction timed out after \(String(format: "%.2f", elapsed))s (limit: \(Int(config.timeout))s) for \(url.lastPathComponent)")
                throw FFmpegError.timeout
            }
            
            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                NSLog("⚠️ [FFmpeg] Extraction failed (code: \(process.terminationStatus)) for \(url.lastPathComponent): \(errorMessage)")
                throw FFmpegError.extractionFailed(errorMessage)
            }
            
            // Verify output exists
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                throw FFmpegError.outputNotCreated
            }
            
            let elapsed = Date().timeIntervalSince(startTime)
            NSLog("✅ [FFmpeg] Audio extracted in \(String(format: "%.2f", elapsed))s -> \(outputURL.lastPathComponent)")
            return outputURL
            
        } catch let error as FFmpegError {
            throw error
        } catch {
            throw FFmpegError.processError(error.localizedDescription)
        }
    }
    
    // MARK: - FFmpeg Detection
    
    /// Find FFmpeg binary on the system
    private func findFFmpeg() async -> String? {
        if hasCheckedFFmpeg {
            return detectedFFmpegPath
        }
        
        hasCheckedFFmpeg = true
        
        // Check configured path first
        if let path = config.ffmpegPath, FileManager.default.fileExists(atPath: path) {
            detectedFFmpegPath = path
            return path
        }
        
        // Common FFmpeg locations
        let searchPaths = [
            "/opt/homebrew/bin/ffmpeg",      // Homebrew (Apple Silicon)
            "/usr/local/bin/ffmpeg",          // Homebrew (Intel) or manual install
            "/usr/bin/ffmpeg",                // System install
            Bundle.main.bundlePath + "/Contents/MacOS/ffmpeg"  // Bundled
        ]
        
        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                detectedFFmpegPath = path
                NSLog("🎬 [FFmpeg] Found at: \(path)")
                return path
            }
        }
        
        // Try `which ffmpeg`
        if let path = await runWhich("ffmpeg") {
            detectedFFmpegPath = path
            NSLog("🎬 [FFmpeg] Found via which: \(path)")
            return path
        }
        
        NSLog("⚠️ [FFmpeg] Not found on system")
        return nil
    }
    
    /// Run `which` to find a binary
    private func runWhich(_ binary: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binary]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return output?.isEmpty == false ? output : nil
            }
        } catch {
            // Ignore errors
        }
        
        return nil
    }
    
    // MARK: - Advanced Operations
    
    /// Extract audio with specific time range and optional audio separation
    func extractAudio(
        from url: URL,
        startTime: TimeInterval,
        duration: TimeInterval,
        timeout: TimeInterval? = nil,
        applySeparation: Bool = false
    ) async throws -> URL {
        guard let ffmpegPath = await findFFmpeg() else {
            throw FFmpegError.ffmpegNotFound
        }
        
        let startExtractionTime = Date()
        let effectiveTimeout = timeout ?? config.timeout
        
        NSLog("🎬 [FFmpeg] Extracting clip at \(String(format: "%.1f", startTime))s for \(String(format: "%.1f", duration))s (timeout: \(Int(effectiveTimeout))s, separation: \(applySeparation))")
        
        let outputURL = await TempFileManager.shared.createTempFile(
            extension: "wav",
            purpose: "ffmpeg_clip"
        )
        
        var arguments = [
            "-ss", String(startTime),      // Start time
            "-i", url.path,
            "-t", String(duration),        // Duration
            "-vn"                          // No video
        ]
        
        // Add audio separation filters if requested
        if applySeparation {
            // Apply noise reduction + bandpass filter to isolate speech frequencies
            let audioFilter = "afftdn=nf=-25,highpass=f=80,lowpass=f=3000"
            arguments.append(contentsOf: ["-af", audioFilter])
            NSLog("🔧 [FFmpeg] Applying audio separation filters")
        }
        
        arguments.append(contentsOf: [
            "-acodec", config.outputCodec,
            "-ar", String(config.sampleRate),
            "-ac", String(config.channels),
            "-y",
            outputURL.path
        ])
        
        // Run with custom timeout
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = arguments
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        
        do {
            try process.run()
            
            let deadline = Date().addingTimeInterval(effectiveTimeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            
            if process.isRunning {
                process.terminate()
                let elapsed = Date().timeIntervalSince(startExtractionTime)
                NSLog("⚠️ [FFmpeg] Clip extraction timed out after \(String(format: "%.2f", elapsed))s")
                await TempFileManager.shared.cleanup(outputURL)
                throw FFmpegError.timeout
            }
            
            guard process.terminationStatus == 0 else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                NSLog("⚠️ [FFmpeg] Clip extraction failed: \(errorMessage)")
                await TempFileManager.shared.cleanup(outputURL)
                throw FFmpegError.extractionFailed(errorMessage)
            }
            
            guard FileManager.default.fileExists(atPath: outputURL.path) else {
                await TempFileManager.shared.cleanup(outputURL)
                throw FFmpegError.outputNotCreated
            }
            
            let elapsed = Date().timeIntervalSince(startExtractionTime)
            NSLog("✅ [FFmpeg] Clip extracted in \(String(format: "%.2f", elapsed))s")
            return outputURL
            
        } catch let error as FFmpegError {
            throw error
        } catch {
            await TempFileManager.shared.cleanup(outputURL)
            throw FFmpegError.processError(error.localizedDescription)
        }
    }
    
    /// Extract subtitles from video file (if present)
    func extractSubtitles(from url: URL) async throws -> String? {
        guard let ffmpegPath = await findFFmpeg() else {
            throw FFmpegError.ffmpegNotFound
        }
        
        // First check if subtitles exist
        let mediaInfo = try await getMediaInfo(for: url)
        let hasSubtitles = mediaInfo.streams?.contains { $0.codecType == "subtitle" } ?? false
        
        guard hasSubtitles else {
            NSLog("📝 [FFmpeg] No subtitle track found in \(url.lastPathComponent)")
            return nil
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("srt")
        
        // Extract first subtitle track to SRT format
        let arguments = [
            "-i", url.path,
            "-map", "0:s:0",  // First subtitle stream
            "-c:s", "srt",
            "-y",
            outputURL.path
        ]
        
        do {
            try await runFFmpeg(path: ffmpegPath, arguments: arguments)
            
            // Read the subtitle content
            let subtitleContent = try String(contentsOf: outputURL, encoding: .utf8)
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: outputURL)
            
            // Strip SRT timing info, keep just the text
            let cleanedText = cleanSubtitleText(subtitleContent)
            NSLog("📝 [FFmpeg] Extracted \(cleanedText.count) chars of subtitles from \(url.lastPathComponent)")
            
            return cleanedText.isEmpty ? nil : cleanedText
        } catch {
            NSLog("⚠️ [FFmpeg] Subtitle extraction failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Extract keyframes from video for visual analysis
    func extractKeyframes(from url: URL, count: Int = 5) async throws -> [URL] {
        guard let ffmpegPath = await findFFmpeg() else {
            throw FFmpegError.ffmpegNotFound
        }
        
        // Get video duration
        let mediaInfo = try await getMediaInfo(for: url)
        let duration = mediaInfo.durationSeconds ?? 60.0
        
        var frameURLs: [URL] = []
        let interval = duration / Double(count + 1)
        
        for i in 1...count {
            let timestamp = interval * Double(i)
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)_frame\(i)")
                .appendingPathExtension("jpg")
            
            let arguments = [
                "-ss", String(timestamp),
                "-i", url.path,
                "-vframes", "1",
                "-q:v", "2",  // High quality
                "-y",
                outputURL.path
            ]
            
            do {
                try await runFFmpeg(path: ffmpegPath, arguments: arguments)
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    frameURLs.append(outputURL)
                }
            } catch {
                NSLog("⚠️ [FFmpeg] Failed to extract frame at \(timestamp)s: \(error.localizedDescription)")
            }
        }
        
        NSLog("🎬 [FFmpeg] Extracted \(frameURLs.count) keyframes from \(url.lastPathComponent)")
        return frameURLs
    }
    
    /// Get media info (duration, codec, etc.)
    func getMediaInfo(for url: URL) async throws -> MediaInfo {
        guard let ffprobePath = await findFFprobe() else {
            throw FFmpegError.ffprobeNotFound
        }
        
        let arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            url.path
        ]
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobePath)
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw FFmpegError.probeError("ffprobe failed")
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return try JSONDecoder().decode(MediaInfo.self, from: data)
    }
    
    /// Check if FFmpeg is available on the system
    func checkAvailability() async -> FFmpegAvailability {
        let ffmpegPath = await findFFmpeg()
        let ffprobePath = await findFFprobe()
        
        return FFmpegAvailability(
            ffmpegAvailable: ffmpegPath != nil,
            ffprobeAvailable: ffprobePath != nil,
            ffmpegPath: ffmpegPath,
            ffprobePath: ffprobePath
        )
    }
    
    private func findFFprobe() async -> String? {
        if let ffmpegPath = await findFFmpeg() {
            let ffprobePath = ffmpegPath.replacingOccurrences(of: "ffmpeg", with: "ffprobe")
            if FileManager.default.isExecutableFile(atPath: ffprobePath) {
                return ffprobePath
            }
        }
        return nil
    }
    
    private func runFFmpeg(path: String, arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice
        
        try process.run()
        
        let deadline = Date().addingTimeInterval(config.timeout)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        
        if process.isRunning {
            process.terminate()
            throw FFmpegError.timeout
        }
        
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw FFmpegError.extractionFailed(errorMessage)
        }
    }
    
    /// Clean subtitle text by removing timing info and tags
    private func cleanSubtitleText(_ srtContent: String) -> String {
        var lines: [String] = []
        var isTimingLine = false
        
        for line in srtContent.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip sequence numbers (just digits)
            if trimmed.allSatisfy({ $0.isNumber }) {
                continue
            }
            
            // Skip timing lines (contain "-->")
            if trimmed.contains("-->") {
                isTimingLine = true
                continue
            }
            
            // Skip empty lines after timing
            if isTimingLine && trimmed.isEmpty {
                isTimingLine = false
                continue
            }
            
            // Keep non-empty text lines
            if !trimmed.isEmpty {
                // Remove HTML-like tags
                let cleaned = trimmed
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "\\{[^}]+\\}", with: "", options: .regularExpression)
                
                if !cleaned.isEmpty {
                    lines.append(cleaned)
                }
            }
        }
        
        return lines.joined(separator: " ")
    }
}

// MARK: - FFmpeg Availability

struct FFmpegAvailability: Sendable {
    let ffmpegAvailable: Bool
    let ffprobeAvailable: Bool
    let ffmpegPath: String?
    let ffprobePath: String?
    
    var isFullyAvailable: Bool {
        ffmpegAvailable && ffprobeAvailable
    }
    
    var statusDescription: String {
        if isFullyAvailable {
            return "✅ FFmpeg available at \(ffmpegPath ?? "unknown")"
        } else if ffmpegAvailable {
            return "⚠️ FFmpeg available, ffprobe missing"
        } else {
            return "❌ FFmpeg not installed. Run: brew install ffmpeg"
        }
    }
}

// MARK: - AVFoundation Fallback Extractor

/// Fallback audio extractor using AVFoundation
actor AVFoundationAudioExtractor: AudioExtractor {
    
    let supportedFormats: Set<String> = [
        "mp4", "mov", "m4v",  // Video
        "mp3", "m4a", "wav", "aac", "aiff"  // Audio
    ]
    
    private let exportPreset: String
    private let maxDuration: TimeInterval
    
    init(exportPreset: String = AVAssetExportPresetAppleM4A, maxDuration: TimeInterval? = nil) {
        self.exportPreset = exportPreset
        self.maxDuration = maxDuration ?? .infinity
    }
    
    func isAvailable() async -> Bool {
        return true  // AVFoundation is always available
    }
    
    func extractAudio(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        
        // Check for audio tracks
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw FFmpegError.noAudioTrack
        }
        
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let clampDuration = min(maxDuration, durationSeconds)
        
        // Output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        
        // Check preset compatibility using modern API
        let isCompatible = await AVAssetExportSession.compatibility(
            ofExportPreset: exportPreset,
            with: asset,
            outputFileType: .m4a
        )
        
        let presetToUse = isCompatible ? exportPreset : AVAssetExportPresetAppleM4A
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetToUse) else {
            throw FFmpegError.exportSessionCreationFailed
        }
        
        if clampDuration.isFinite {
            exportSession.timeRange = CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: clampDuration, preferredTimescale: 600)
            )
        }
        
        // Export using modern async throws API (no status/error checking needed)
        do {
            try await exportSession.export(to: outputURL, as: .m4a)
            return outputURL
        } catch {
            throw FFmpegError.exportFailed(error.localizedDescription)
        }
    }
}

// MARK: - Combined Audio Extractor

/// Smart audio extractor that tries FFmpeg first, then falls back to AVFoundation
actor CombinedAudioExtractor: AudioExtractor {
    
    private let ffmpegExtractor: FFmpegAudioExtractor
    private let avExtractor: AVFoundationAudioExtractor
    private var preferFFmpeg: Bool = true
    
    var supportedFormats: Set<String> {
        ffmpegExtractor.supportedFormats.union(avExtractor.supportedFormats)
    }
    
    init(ffmpegConfig: FFmpegAudioExtractor.Configuration = .default) {
        self.ffmpegExtractor = FFmpegAudioExtractor(configuration: ffmpegConfig)
        self.avExtractor = AVFoundationAudioExtractor(maxDuration: ffmpegConfig.maxDuration)
    }
    
    func isAvailable() async -> Bool {
        return true  // Always available with AVFoundation fallback
    }
    
    func extractAudio(from url: URL) async throws -> URL {
        let ext = url.pathExtension.lowercased()
        
        // Try FFmpeg first for formats AVFoundation struggles with
        let ffmpegPreferredFormats = ["mkv", "avi", "wmv", "flv", "webm"]
        
        if ffmpegPreferredFormats.contains(ext) || preferFFmpeg {
            if await ffmpegExtractor.isAvailable() {
                do {
                    return try await ffmpegExtractor.extractAudio(from: url)
                } catch {
                    NSLog("⚠️ [Audio] FFmpeg failed, falling back to AVFoundation: \(error)")
                }
            }
        }
        
        // Fallback to AVFoundation
        return try await avExtractor.extractAudio(from: url)
    }
    
    /// Set preference for FFmpeg vs AVFoundation
    func setPreferFFmpeg(_ prefer: Bool) {
        preferFFmpeg = prefer
    }
    
    /// Extract audio clip with specific time range and optional audio separation
    func extractAudioClip(
        from url: URL,
        startTime: TimeInterval,
        duration: TimeInterval,
        timeout: TimeInterval? = nil,
        applySeparation: Bool = false
    ) async throws -> URL {
        // Try FFmpeg first for clip extraction (more reliable for time-based extraction)
        if await ffmpegExtractor.isAvailable() {
            do {
                return try await ffmpegExtractor.extractAudio(
                    from: url,
                    startTime: startTime,
                    duration: duration,
                    timeout: timeout,
                    applySeparation: applySeparation
                )
            } catch {
                NSLog("⚠️ [CombinedExtractor] FFmpeg clip extraction failed, falling back to AVFoundation: \(error)")
            }
        }
        
        // Fallback to AVFoundation (doesn't support audio separation)
        let asset = AVURLAsset(url: url)
        let outputURL = await TempFileManager.shared.createTempFile(extension: "m4a", purpose: "avfoundation_clip")
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw FFmpegError.exportSessionCreationFailed
        }
        
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        try await exportSession.export(to: outputURL, as: .m4a)
        return outputURL
    }
}

// MARK: - Supporting Types

/// FFmpeg/Audio extraction errors
enum FFmpegError: LocalizedError {
    case ffmpegNotFound
    case ffprobeNotFound
    case extractionFailed(String)
    case timeout
    case outputNotCreated
    case processError(String)
    case probeError(String)
    case noAudioTrack
    case noCompatiblePreset
    case exportSessionCreationFailed
    case exportFailed(String)
    case exportCancelled
    
    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg not found. Install via: brew install ffmpeg"
        case .ffprobeNotFound:
            return "FFprobe not found"
        case .extractionFailed(let reason):
            return "Audio extraction failed: \(reason)"
        case .timeout:
            return "Audio extraction timed out"
        case .outputNotCreated:
            return "Output file was not created"
        case .processError(let reason):
            return "Process error: \(reason)"
        case .probeError(let reason):
            return "Probe error: \(reason)"
        case .noAudioTrack:
            return "No audio track found in file"
        case .noCompatiblePreset:
            return "No compatible export preset found"
        case .exportSessionCreationFailed:
            return "Failed to create export session"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        case .exportCancelled:
            return "Export was cancelled"
        }
    }
}

/// Media information from ffprobe
struct MediaInfo: Codable, Sendable {
    let format: FormatInfo?
    let streams: [StreamInfo]?
    
    struct FormatInfo: Codable, Sendable {
        let filename: String?
        let duration: String?
        let bitRate: String?
        let formatName: String?
        
        enum CodingKeys: String, CodingKey {
            case filename
            case duration
            case bitRate = "bit_rate"
            case formatName = "format_name"
        }
        
        var durationSeconds: TimeInterval? {
            guard let d = duration else { return nil }
            return TimeInterval(d)
        }
    }
    
    struct StreamInfo: Codable, Sendable {
        let codecType: String?
        let codecName: String?
        let sampleRate: String?
        let channels: Int?
        let duration: String?
        
        enum CodingKeys: String, CodingKey {
            case codecType = "codec_type"
            case codecName = "codec_name"
            case sampleRate = "sample_rate"
            case channels
            case duration
        }
        
        var isAudio: Bool {
            codecType == "audio"
        }
        
        var isVideo: Bool {
            codecType == "video"
        }
    }
    
    var audioStream: StreamInfo? {
        streams?.first { $0.isAudio }
    }
    
    var videoStream: StreamInfo? {
        streams?.first { $0.isVideo }
    }
    
    var durationSeconds: TimeInterval? {
        format?.durationSeconds
    }
}

