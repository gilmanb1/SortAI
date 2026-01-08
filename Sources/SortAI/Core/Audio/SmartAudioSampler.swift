// MARK: - Smart Audio Sampler
// Fast audio extraction with Voice Activity Detection (VAD)
// Extracts only speech segments for efficient LLM categorization

import Foundation
import AVFoundation
import Accelerate
import SoundAnalysis

// MARK: - Configuration

struct AudioSamplerConfig: Sendable {
    /// Target duration of speech to collect (seconds)
    let targetSpeechDuration: TimeInterval
    
    /// Minimum segment duration to consider (seconds)
    let minSegmentDuration: TimeInterval
    
    /// Output sample rate (16kHz is optimal for speech recognition)
    let outputSampleRate: Double
    
    /// Energy threshold for speech detection (0.0-1.0)
    let speechEnergyThreshold: Float
    
    /// Maximum time to scan before giving up (seconds)
    let maxScanDuration: TimeInterval
    
    /// Chunk size for processing (samples)
    let chunkSize: Int
    
    static let `default` = AudioSamplerConfig(
        targetSpeechDuration: 90.0,      // Collect ~90s of speech
        minSegmentDuration: 1.0,          // Ignore segments < 1s
        outputSampleRate: 16000.0,        // 16kHz for speech
        speechEnergyThreshold: 0.02,      // Energy threshold
        maxScanDuration: 600.0,           // Scan up to 10 min of video
        chunkSize: 4096                   // Process in 4k chunks
    )
    
    static let fast = AudioSamplerConfig(
        targetSpeechDuration: 45.0,       // Less speech needed
        minSegmentDuration: 2.0,          // Longer minimum segments
        outputSampleRate: 16000.0,
        speechEnergyThreshold: 0.03,      // Slightly higher threshold
        maxScanDuration: 300.0,           // Scan up to 5 min
        chunkSize: 8192                   // Larger chunks = faster
    )
}

// MARK: - Audio Sample Result

struct AudioSampleResult: Sendable {
    let sourceURL: URL
    let tempAudioURL: URL
    let speechDuration: TimeInterval
    let totalScanned: TimeInterval
    let segmentCount: Int
    let processingTime: TimeInterval
}

// MARK: - Errors

enum AudioSamplerError: LocalizedError {
    case noAudioTrack
    case readerCreationFailed(String)
    case outputCreationFailed(String)
    case processingFailed(String)
    case insufficientSpeech
    
    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found in video"
        case .readerCreationFailed(let reason):
            return "Failed to create audio reader: \(reason)"
        case .outputCreationFailed(let reason):
            return "Failed to create output file: \(reason)"
        case .processingFailed(let reason):
            return "Audio processing failed: \(reason)"
        case .insufficientSpeech:
            return "Not enough speech detected in video"
        }
    }
}

// MARK: - Smart Audio Sampler Actor

actor SmartAudioSampler {
    
    private let config: AudioSamplerConfig
    private let tempDirectory: URL
    
    init(config: AudioSamplerConfig = .default) {
        self.config = config
        self.tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortAI_Audio", isDirectory: true)
        
        // Ensure temp directory exists
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }
    
    // MARK: - Public Interface
    
    /// Extracts speech segments from a video file
    /// Returns path to temporary audio file containing only speech
    func extractSpeech(from videoURL: URL) async throws -> AudioSampleResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let asset = AVURLAsset(url: videoURL)
        
        // Get audio track
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioSamplerError.noAudioTrack
        }
        
        // Get format description
        let formatDescriptions = try await audioTrack.load(.formatDescriptions)
        guard let formatDesc = formatDescriptions.first else {
            throw AudioSamplerError.readerCreationFailed("No format description")
        }
        
        let sourceFormat = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee
        let sourceSampleRate = sourceFormat?.mSampleRate ?? 44100.0
        
        // Create reader
        let reader = try AVAssetReader(asset: asset)
        
        // Configure output settings for raw PCM
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sourceSampleRate,
            AVNumberOfChannelsKey: 1,  // Mono
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        readerOutput.alwaysCopiesSampleData = false
        
        guard reader.canAdd(readerOutput) else {
            throw AudioSamplerError.readerCreationFailed("Cannot add output")
        }
        reader.add(readerOutput)
        
        guard reader.startReading() else {
            throw AudioSamplerError.readerCreationFailed(reader.error?.localizedDescription ?? "Unknown")
        }
        
        // Process audio and detect speech
        let speechSegments = try await detectSpeechSegments(
            reader: reader,
            output: readerOutput,
            sampleRate: sourceSampleRate
        )
        
        // Create output file with speech segments
        let outputURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        
        let speechDuration = try await writeSpeechSegments(
            segments: speechSegments,
            from: videoURL,
            to: outputURL
        )
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        return AudioSampleResult(
            sourceURL: videoURL,
            tempAudioURL: outputURL,
            speechDuration: speechDuration,
            totalScanned: speechSegments.last?.end ?? 0,
            segmentCount: speechSegments.count,
            processingTime: processingTime
        )
    }
    
    /// Batch process multiple video files
    func extractSpeechBatch(
        from videoURLs: [URL],
        maxConcurrent: Int = 4
    ) async throws -> [Result<AudioSampleResult, Error>] {
        
        await withTaskGroup(of: (Int, Result<AudioSampleResult, Error>).self) { group in
            var results = [Result<AudioSampleResult, Error>?](repeating: nil, count: videoURLs.count)
            var activeCount = 0
            var nextIndex = 0
            
            // Start initial batch
            while activeCount < maxConcurrent && nextIndex < videoURLs.count {
                let index = nextIndex
                let url = videoURLs[index]
                group.addTask {
                    do {
                        let result = try await self.extractSpeech(from: url)
                        return (index, .success(result))
                    } catch {
                        return (index, .failure(error))
                    }
                }
                activeCount += 1
                nextIndex += 1
            }
            
            // Process results and add new tasks
            for await (index, result) in group {
                results[index] = result
                activeCount -= 1
                
                if nextIndex < videoURLs.count {
                    let newIndex = nextIndex
                    let url = videoURLs[newIndex]
                    group.addTask {
                        do {
                            let result = try await self.extractSpeech(from: url)
                            return (newIndex, .success(result))
                        } catch {
                            return (newIndex, .failure(error))
                        }
                    }
                    activeCount += 1
                    nextIndex += 1
                }
            }
            
            return results.compactMap { $0 }
        }
    }
    
    /// Cleans up temporary audio files
    func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    // MARK: - Speech Detection
    
    private struct TimeRange: Sendable {
        let start: TimeInterval
        let end: TimeInterval
        var duration: TimeInterval { end - start }
    }
    
    private func detectSpeechSegments(
        reader: AVAssetReader,
        output: AVAssetReaderTrackOutput,
        sampleRate: Double
    ) async throws -> [TimeRange] {
        
        var speechSegments: [TimeRange] = []
        var totalSpeechDuration: TimeInterval = 0
        var currentTime: TimeInterval = 0
        var inSpeechSegment = false
        var segmentStart: TimeInterval = 0
        
        // Energy history for smoothing
        var energyHistory: [Float] = []
        let historySize = 5
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
            // Check if we have enough speech
            if totalSpeechDuration >= config.targetSpeechDuration {
                break
            }
            
            // Check if we've scanned enough
            if currentTime >= config.maxScanDuration {
                break
            }
            
            // Get audio data
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }
            
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            
            guard let data = dataPointer else { continue }
            
            // Convert to float samples
            let sampleCount = length / 2  // 16-bit samples
            let int16Pointer = data.withMemoryRebound(to: Int16.self, capacity: sampleCount) { $0 }
            
            var floatSamples = [Float](repeating: 0, count: sampleCount)
            vDSP_vflt16(int16Pointer, 1, &floatSamples, 1, vDSP_Length(sampleCount))
            
            // Normalize
            var scalar: Float = 1.0 / 32768.0
            vDSP_vsmul(floatSamples, 1, &scalar, &floatSamples, 1, vDSP_Length(sampleCount))
            
            // Calculate RMS energy
            var energy: Float = 0
            vDSP_rmsqv(floatSamples, 1, &energy, vDSP_Length(sampleCount))
            
            // Smooth energy
            energyHistory.append(energy)
            if energyHistory.count > historySize {
                energyHistory.removeFirst()
            }
            let smoothedEnergy = energyHistory.reduce(0, +) / Float(energyHistory.count)
            
            // Update time
            let chunkDuration = Double(sampleCount) / sampleRate
            let chunkEnd = currentTime + chunkDuration
            
            // Speech detection with hysteresis
            let isSpeech = smoothedEnergy > config.speechEnergyThreshold
            
            if isSpeech && !inSpeechSegment {
                // Start of speech segment
                inSpeechSegment = true
                segmentStart = currentTime
            } else if !isSpeech && inSpeechSegment {
                // End of speech segment
                inSpeechSegment = false
                let segmentDuration = currentTime - segmentStart
                
                if segmentDuration >= config.minSegmentDuration {
                    speechSegments.append(TimeRange(start: segmentStart, end: currentTime))
                    totalSpeechDuration += segmentDuration
                }
            }
            
            currentTime = chunkEnd
        }
        
        // Close any open segment
        if inSpeechSegment {
            let segmentDuration = currentTime - segmentStart
            if segmentDuration >= config.minSegmentDuration {
                speechSegments.append(TimeRange(start: segmentStart, end: currentTime))
            }
        }
        
        return speechSegments
    }
    
    // MARK: - Audio Writing
    
    private func writeSpeechSegments(
        segments: [TimeRange],
        from sourceURL: URL,
        to outputURL: URL
    ) async throws -> TimeInterval {
        
        guard !segments.isEmpty else {
            throw AudioSamplerError.insufficientSpeech
        }
        
        let asset = AVURLAsset(url: sourceURL)
        
        // Merge nearby segments and limit total duration
        let mergedSegments = mergeSegments(segments, maxGap: 0.5, maxTotal: config.targetSpeechDuration)
        
        // Create composition with only speech segments
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioSamplerError.outputCreationFailed("Cannot create composition track")
        }
        
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioSamplerError.noAudioTrack
        }
        
        var insertTime = CMTime.zero
        var totalDuration: TimeInterval = 0
        
        for segment in mergedSegments {
            let startTime = CMTime(seconds: segment.start, preferredTimescale: 44100)
            let duration = CMTime(seconds: segment.duration, preferredTimescale: 44100)
            let timeRange = CMTimeRange(start: startTime, duration: duration)
            
            try compositionTrack.insertTimeRange(timeRange, of: sourceTrack, at: insertTime)
            insertTime = CMTimeAdd(insertTime, duration)
            totalDuration += segment.duration
        }
        
        // Export to WAV at 16kHz mono
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioSamplerError.outputCreationFailed("Cannot create export session")
        }
        
        // Use M4A output (faster than WAV, still compatible with Speech framework)
        let m4aURL = outputURL.deletingPathExtension().appendingPathExtension("m4a")
        exportSession.outputURL = m4aURL
        exportSession.outputFileType = .m4a
        
        try await exportSession.export(to: m4aURL, as: .m4a)
        
        return totalDuration
    }
    
    private func mergeSegments(
        _ segments: [TimeRange],
        maxGap: TimeInterval,
        maxTotal: TimeInterval
    ) -> [TimeRange] {
        guard !segments.isEmpty else { return [] }
        
        var merged: [TimeRange] = []
        var current = segments[0]
        var totalDuration: TimeInterval = 0
        
        for segment in segments.dropFirst() {
            if totalDuration >= maxTotal {
                break
            }
            
            if segment.start - current.end <= maxGap {
                // Merge with current
                current = TimeRange(start: current.start, end: segment.end)
            } else {
                // Save current and start new
                if totalDuration + current.duration <= maxTotal {
                    merged.append(current)
                    totalDuration += current.duration
                }
                current = segment
            }
        }
        
        // Add last segment if room
        if totalDuration + current.duration <= maxTotal {
            merged.append(current)
        }
        
        return merged
    }
}

// MARK: - Convenience Extensions

extension SmartAudioSampler {
    
    /// Quick extraction with automatic cleanup callback
    func extractSpeechWithCleanup(
        from videoURL: URL,
        process: @Sendable (URL) async throws -> Void
    ) async throws {
        let result = try await extractSpeech(from: videoURL)
        
        defer {
            try? FileManager.default.removeItem(at: result.tempAudioURL)
        }
        
        try await process(result.tempAudioURL)
    }
}

