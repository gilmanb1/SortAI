// MARK: - Multi-Clip Audio Extractor
// Implements multi-clip sampling strategy for long videos
// Extracts distributed clips throughout video duration for representative content

import Foundation
import AVFoundation

// MARK: - Clip Position

struct ClipPosition: Sendable {
    let startTime: TimeInterval
    let duration: TimeInterval
    let index: Int
    
    var endTime: TimeInterval {
        startTime + duration
    }
}

// MARK: - Extraction Result

struct ClipExtractionResult: Sendable {
    let position: ClipPosition
    let audioURL: URL?
    let transcript: String
    let extractionMethod: String
    let extractionTime: TimeInterval
    let transcriptionTime: TimeInterval
    let retryCount: Int
    let error: String?
}

// MARK: - Extraction Strategy

enum ExtractionStrategy: String, Sendable {
    case vad = "VAD"
    case ffmpeg = "FFmpeg"
    case avfoundation = "AVFoundation"
    case smartSampler = "SmartSampler"
}

// MARK: - Multi-Clip Extractor

/// Calculates clip positions and coordinates multi-clip extraction
actor MultiClipExtractor {
    
    // MARK: - Configuration
    
    private let config: AudioConfiguration
    
    init(config: AudioConfiguration) {
        self.config = config
    }
    
    // MARK: - Clip Position Calculation
    
    /// Calculate clip positions based on video duration
    /// - Parameter videoDuration: Total video duration in seconds
    /// - Returns: Array of clip positions to extract
    func calculateClipPositions(videoDuration: TimeInterval) -> [ClipPosition] {
        // Validate input
        guard videoDuration > 0, videoDuration.isFinite else {
            NSLog("⚠️ [MultiClipExtractor] Invalid duration: \(videoDuration)")
            return []
        }
        
        // Short videos: single clip from start
        if videoDuration <= 300 {  // 5 minutes
            let duration = min(videoDuration, config.maxTotalAudioDuration)
            NSLog("📏 [MultiClipExtractor] Short video (\(String(format: "%.1f", videoDuration))s): single clip of \(String(format: "%.1f", duration))s")
            return [ClipPosition(startTime: 0, duration: duration, index: 0)]
        }
        
        // Long videos: distribute clips throughout duration
        let clipDuration = config.clipDurationShort
        let maxClips = config.maxClipsPerVideo
        
        // Calculate positions: [0s, 25%, 50%, 75%, end-60s]
        let positions: [TimeInterval] = [
            0,  // Start
            videoDuration * 0.25,  // First quarter
            videoDuration * 0.5,   // Middle
            videoDuration * 0.75,  // Third quarter
            max(0, videoDuration - 60)  // Near end
        ]
        
        var clips: [ClipPosition] = []
        var totalDuration: TimeInterval = 0
        
        for (index, startTime) in positions.prefix(maxClips).enumerated() {
            // Stop if we've reached the total duration limit
            if totalDuration >= config.maxTotalAudioDuration {
                break
            }
            
            // Skip if this would overlap with previous clip
            if let lastClip = clips.last, startTime < lastClip.endTime {
                continue
            }
            
            // Calculate clip duration (don't exceed video end or total limit)
            let remainingVideo = videoDuration - startTime
            let remainingBudget = config.maxTotalAudioDuration - totalDuration
            let effectiveDuration = min(clipDuration, remainingVideo, remainingBudget)
            
            if effectiveDuration > 5 {  // Minimum 5 seconds
                clips.append(ClipPosition(
                    startTime: startTime,
                    duration: effectiveDuration,
                    index: index
                ))
                totalDuration += effectiveDuration
            }
        }
        
        NSLog("📏 [MultiClipExtractor] Long video (\(String(format: "%.1f", videoDuration))s): \(clips.count) clips, total \(String(format: "%.1f", totalDuration))s")
        for clip in clips {
            NSLog("   Clip \(clip.index): \(String(format: "%.1f", clip.startTime))s - \(String(format: "%.1f", clip.endTime))s (\(String(format: "%.1f", clip.duration))s)")
        }
        
        return clips
    }
    
    /// Calculate dynamic timeout for a clip
    /// - Parameter clipDuration: Duration of the clip in seconds
    /// - Returns: Timeout in seconds
    func calculateTimeout(for clipDuration: TimeInterval) -> TimeInterval {
        // timeout = min(60s, max(30s, clipDuration * 0.2))
        let scaledTimeout = clipDuration * 0.2
        let timeout = min(60.0, max(30.0, scaledTimeout))
        return timeout
    }
}

// MARK: - Retry Logic

/// Error classification for retry decisions
enum ErrorClassification: Sendable {
    case transient       // Network, memory pressure - retry with backoff
    case noSpeech        // No speech detected - try next method
    case codec           // Codec/format error - try next method
    case hardFailure     // Unrecoverable - surface to user
}

extension Error {
    /// Classify error for retry logic
    var classification: ErrorClassification {
        let description = localizedDescription.lowercased()
        
        // No-speech errors
        if description.contains("no speech") ||
           description.contains("1110") ||
           description.contains("-11800") {
            return .noSpeech
        }
        
        // Codec/format errors
        if description.contains("codec") ||
           description.contains("format") ||
           description.contains("compatible") {
            return .codec
        }
        
        // Transient errors
        if description.contains("timeout") ||
           description.contains("network") ||
           description.contains("memory") ||
           description.contains("pressure") {
            return .transient
        }
        
        // Default to hard failure
        return .hardFailure
    }
}

/// Retry helper with exponential backoff
actor RetryHelper {
    
    /// Execute operation with retry logic
    /// - Parameters:
    ///   - maxRetries: Maximum retry attempts
    ///   - operation: Operation to execute
    /// - Returns: Result and retry count
    func executeWithRetry<T>(
        maxRetries: Int,
        operation: @Sendable () async throws -> T
    ) async throws -> (result: T, retryCount: Int) {
        var retryCount = 0
        var lastError: Error?
        
        while retryCount <= maxRetries {
            do {
                let result = try await operation()
                return (result, retryCount)
            } catch {
                lastError = error
                let classification = error.classification
                
                switch classification {
                case .transient:
                    // Retry with exponential backoff
                    let backoff = pow(2.0, Double(retryCount))  // 1s, 2s, 4s...
                    retryCount += 1
                    
                    if retryCount <= maxRetries {
                        NSLog("🔄 [Retry] Transient error, retry \(retryCount)/\(maxRetries) after \(String(format: "%.1f", backoff))s")
                        try? await Task.sleep(for: .seconds(backoff))
                        continue
                    }
                    
                case .noSpeech, .codec:
                    // Don't retry these - signal to try next method
                    throw error
                    
                case .hardFailure:
                    // Don't retry hard failures
                    throw error
                }
            }
        }
        
        throw lastError ?? NSError(domain: "RetryHelper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Max retries exceeded"])
    }
}

