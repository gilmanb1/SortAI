// MARK: - Deep Analyzer Tests
// Unit tests for deep content analysis

import Testing
import Foundation
@testable import SortAI

// MARK: - Deep Analyzer Configuration Tests

@Suite("DeepAnalyzer Configuration Tests")
struct DeepAnalyzerConfigurationTests {
    
    @Test("Default configuration")
    func testDefaultConfiguration() {
        let config = DeepAnalyzer.Configuration.default
        
        #expect(config.confidenceThreshold == 0.75)
        #expect(config.maxConcurrent == 2)
        #expect(config.timeoutPerFile == 120.0)
        #expect(config.extractAudio == true)
        #expect(config.performOCR == true)
    }
    
    @Test("Fast configuration")
    func testFastConfiguration() {
        let config = DeepAnalyzer.Configuration.fast
        
        #expect(config.maxConcurrent == 3)
        #expect(config.timeoutPerFile == 60.0)
        #expect(config.extractAudio == false) // Disabled for speed
        #expect(config.performOCR == true)
    }
    
    @Test("Custom configuration")
    func testCustomConfiguration() {
        let config = DeepAnalyzer.Configuration(
            confidenceThreshold: 0.5,
            maxConcurrent: 1,
            timeoutPerFile: 30.0,
            extractAudio: false,
            performOCR: false,
            useHybridExtraction: false,
            fullExtractionThreshold: 0.7
        )
        
        #expect(config.confidenceThreshold == 0.5)
        #expect(config.maxConcurrent == 1)
        #expect(config.timeoutPerFile == 30.0)
    }
}

// MARK: - Deep Analysis Result Tests

@Suite("DeepAnalysisResult Tests")
struct DeepAnalysisResultTests {
    
    @Test("Create result")
    func testCreateResult() {
        let result = DeepAnalysisResult(
            filename: "test_video.mp4",
            categoryPath: ["Media", "Videos", "Tutorials"],
            confidence: 0.92,
            rationale: "Contains tutorial content about coding",
            contentSummary: "A 10-minute tutorial about Swift programming",
            suggestedTags: ["swift", "tutorial", "programming"]
        )
        
        #expect(result.filename == "test_video.mp4")
        #expect(result.categoryPath.count == 3)
        #expect(result.confidence == 0.92)
        #expect(result.pathString == "Media / Videos / Tutorials")
        #expect(result.suggestedTags.contains("swift"))
    }
    
    @Test("Result identifiable")
    func testResultIdentifiable() {
        let result1 = DeepAnalysisResult(
            filename: "file1.pdf",
            categoryPath: ["Documents"],
            confidence: 0.9,
            rationale: "",
            contentSummary: "",
            suggestedTags: []
        )
        
        let result2 = DeepAnalysisResult(
            filename: "file2.pdf",
            categoryPath: ["Documents"],
            confidence: 0.9,
            rationale: "",
            contentSummary: "",
            suggestedTags: []
        )
        
        #expect(result1.id != result2.id)
    }
    
    @Test("Path string formatting")
    func testPathStringFormatting() {
        let singleLevel = DeepAnalysisResult(
            filename: "test",
            categoryPath: ["Root"],
            confidence: 0.9,
            rationale: "",
            contentSummary: "",
            suggestedTags: []
        )
        
        let multiLevel = DeepAnalysisResult(
            filename: "test",
            categoryPath: ["A", "B", "C", "D"],
            confidence: 0.9,
            rationale: "",
            contentSummary: "",
            suggestedTags: []
        )
        
        #expect(singleLevel.pathString == "Root")
        #expect(multiLevel.pathString == "A / B / C / D")
    }
}

// MARK: - Deep Analysis Error Tests

@Suite("DeepAnalysisError Tests")
struct DeepAnalysisErrorTests {
    
    @Test("Error descriptions")
    func testErrorDescriptions() {
        let errors: [(DeepAnalysisError, String)] = [
            (.invalidResponse("bad json"), "Invalid response"),
            (.timeout, "timed out"),
            (.extractionFailed("no audio"), "extraction failed"),
            (.llmUnavailable, "unavailable")
        ]
        
        for (error, expectedSubstring) in errors {
            let description = error.errorDescription ?? ""
            #expect(description.lowercased().contains(expectedSubstring.lowercased()))
        }
    }
    
    @Test("Invalid response error")
    func testInvalidResponseError() {
        let error = DeepAnalysisError.invalidResponse("Invalid JSON structure")
        
        #expect(error.errorDescription?.contains("Invalid JSON structure") == true)
    }
    
    @Test("Extraction failed error")
    func testExtractionFailedError() {
        let error = DeepAnalysisError.extractionFailed("No audio track found")
        
        #expect(error.errorDescription?.contains("No audio track found") == true)
    }
}

// MARK: - Mock LLM Provider for Tests

actor TestMockLLMProvider: LLMProvider {
    nonisolated let identifier = "test-mock"
    
    func isAvailable() async -> Bool { true }
    
    func complete(prompt: String, options: LLMOptions) async throws -> String {
        return "Test completion"
    }
    
    func completeJSON(prompt: String, options: LLMOptions) async throws -> String {
        return """
        {"categoryPath": ["Test"], "confidence": 0.95, "rationale": "Test", "contentSummary": "Test", "suggestedTags": []}
        """
    }
    
    func embed(text: String) async throws -> [Float] {
        return Array(repeating: 0.1, count: 128)
    }
    
    func availableModels() async throws -> [LLMModel] {
        return [LLMModel(id: "test", name: "Test", size: nil, contextLength: 4096, capabilities: [.chat])]
    }
    
    func warmup(model: String) async {}
}

// MARK: - Deep Analyzer Tests (Mock-based)

@Suite("DeepAnalyzer Tests")
struct DeepAnalyzerTests {
    
    @Test("Analyzer initialization")
    func testAnalyzerInitialization() async {
        let mockProvider = TestMockLLMProvider()
        let analyzer = DeepAnalyzer(
            configuration: .default,
            llmProvider: mockProvider
        )
        
        // Just verify it can be created
        _ = analyzer
    }
    
    @Test("Analyzer with custom configuration")
    func testAnalyzerWithCustomConfiguration() async {
        let mockProvider = TestMockLLMProvider()
        let customConfig = DeepAnalyzer.Configuration(
            confidenceThreshold: 0.6,
            maxConcurrent: 1,
            timeoutPerFile: 60.0,
            extractAudio: false,
            performOCR: true,
            useHybridExtraction: false,
            fullExtractionThreshold: 0.7
        )
        
        let analyzer = DeepAnalyzer(
            configuration: customConfig,
            llmProvider: mockProvider
        )
        
        // Just verify it can be created with custom config
        _ = analyzer
    }
}

// MARK: - FFmpeg Integration Tests

@Suite("FFmpeg Integration Tests")
struct FFmpegIntegrationTests {
    
    @Test("FFmpeg availability check")
    func testFFmpegAvailability() async {
        let extractor = FFmpegAudioExtractor()
        let availability = await extractor.checkAvailability()
        
        // Just verify the check runs without error
        // FFmpeg may or may not be installed
        #expect(availability.statusDescription.count > 0)
        
        if availability.isFullyAvailable {
            #expect(availability.ffmpegPath != nil)
            #expect(availability.ffprobePath != nil)
        }
    }
    
    @Test("FFmpeg configuration defaults")
    func testFFmpegConfigurationDefaults() {
        let config = FFmpegAudioExtractor.Configuration.default
        
        #expect(config.sampleRate == 16000)
        #expect(config.channels == 1)
        #expect(config.outputCodec == "pcm_s16le")
        #expect(config.timeout == 120.0)
    }
    
    @Test("FFmpeg speech recognition configuration")
    func testFFmpegSpeechRecognitionConfiguration() {
        let config = FFmpegAudioExtractor.Configuration.speechRecognition
        
        #expect(config.sampleRate == 16000)
        #expect(config.channels == 1)
        #expect(config.maxDuration == 300) // 5 minutes
        #expect(config.timeout == 60.0)
    }
    
    @Test("FFmpeg supported formats")
    func testFFmpegSupportedFormats() async {
        let extractor = FFmpegAudioExtractor()
        let formats = await extractor.supportedFormats
        
        // Video formats
        #expect(formats.contains("mp4"))
        #expect(formats.contains("mov"))
        #expect(formats.contains("mkv"))
        #expect(formats.contains("avi"))
        #expect(formats.contains("wmv"))
        #expect(formats.contains("webm"))
        
        // Audio formats
        #expect(formats.contains("mp3"))
        #expect(formats.contains("wav"))
        #expect(formats.contains("flac"))
        #expect(formats.contains("ogg"))
    }
    
    @Test("Combined audio extractor fallback")
    func testCombinedExtractorAvailability() async {
        let extractor = CombinedAudioExtractor()
        
        // Combined extractor is always available (AVFoundation fallback)
        let available = await extractor.isAvailable()
        #expect(available == true)
    }
    
    @Test("FFmpeg availability struct")
    func testFFmpegAvailabilityStruct() {
        let fullyAvailable = FFmpegAvailability(
            ffmpegAvailable: true,
            ffprobeAvailable: true,
            ffmpegPath: "/usr/local/bin/ffmpeg",
            ffprobePath: "/usr/local/bin/ffprobe"
        )
        
        #expect(fullyAvailable.isFullyAvailable == true)
        #expect(fullyAvailable.statusDescription.contains("✅"))
        
        let partialAvailable = FFmpegAvailability(
            ffmpegAvailable: true,
            ffprobeAvailable: false,
            ffmpegPath: "/usr/local/bin/ffmpeg",
            ffprobePath: nil
        )
        
        #expect(partialAvailable.isFullyAvailable == false)
        #expect(partialAvailable.statusDescription.contains("⚠️"))
        
        let notAvailable = FFmpegAvailability(
            ffmpegAvailable: false,
            ffprobeAvailable: false,
            ffmpegPath: nil,
            ffprobePath: nil
        )
        
        #expect(notAvailable.isFullyAvailable == false)
        #expect(notAvailable.statusDescription.contains("❌"))
        #expect(notAvailable.statusDescription.contains("brew install"))
    }
    
    @Test("FFmpeg error descriptions")
    func testFFmpegErrorDescriptions() {
        let errors: [(FFmpegError, String)] = [
            (.ffmpegNotFound, "not found"),
            (.ffprobeNotFound, "Ffprobe"),
            (.extractionFailed("test"), "extraction failed"),
            (.timeout, "timed out"),
            (.outputNotCreated, "not created"),
            (.processError("test"), "Process error"),
            (.probeError("test"), "Probe error"),
            (.noAudioTrack, "audio track"),
            (.noCompatiblePreset, "compatible"),
            (.exportSessionCreationFailed, "export session"),
            (.exportFailed("test"), "Export failed"),
            (.exportCancelled, "cancelled")
        ]
        
        for (error, expectedSubstring) in errors {
            let description = error.errorDescription ?? ""
            #expect(description.lowercased().contains(expectedSubstring.lowercased()),
                    "Expected '\(expectedSubstring)' in '\(description)'")
        }
    }
    
    @Test("Media info decoding")
    func testMediaInfoDecoding() throws {
        let json = """
        {
            "format": {
                "filename": "test.mp4",
                "duration": "60.5",
                "bit_rate": "1500000",
                "format_name": "mp4"
            },
            "streams": [
                {
                    "codec_type": "video",
                    "codec_name": "h264",
                    "duration": "60.5"
                },
                {
                    "codec_type": "audio",
                    "codec_name": "aac",
                    "sample_rate": "44100",
                    "channels": 2,
                    "duration": "60.5"
                }
            ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let mediaInfo = try JSONDecoder().decode(MediaInfo.self, from: data)
        
        #expect(mediaInfo.format?.filename == "test.mp4")
        #expect(mediaInfo.format?.durationSeconds == 60.5)
        #expect(mediaInfo.format?.formatName == "mp4")
        
        #expect(mediaInfo.videoStream?.isVideo == true)
        #expect(mediaInfo.videoStream?.codecName == "h264")
        
        #expect(mediaInfo.audioStream?.isAudio == true)
        #expect(mediaInfo.audioStream?.codecName == "aac")
        #expect(mediaInfo.audioStream?.channels == 2)
    }
}

// MARK: - Integration Test Helpers

@Suite("Deep Analysis Integration Helpers")
struct DeepAnalysisIntegrationHelpers {
    
    @Test("Scanned file for analysis")
    func testScannedFileForAnalysis() {
        let file = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/Users/test/mystery_document.pdf"),
            filename: "mystery_document.pdf",
            fileExtension: "pdf",
            fileSize: 1024 * 500, // 500 KB
            modificationDate: Date()
        )
        
        #expect(file.filename == "mystery_document.pdf")
        #expect(file.fileExtension == "pdf")
        #expect(file.isDocument)
        #expect(!file.isImage)
        #expect(!file.isVideo)
    }
    
    @Test("Video file detection")
    func testVideoFileDetection() {
        let videoFile = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/video.mp4"),
            filename: "video.mp4",
            fileExtension: "mp4",
            fileSize: 1024 * 1024 * 100, // 100 MB
            modificationDate: Date()
        )
        
        #expect(videoFile.isVideo)
        #expect(!videoFile.isAudio)
        #expect(!videoFile.isImage)
    }
    
    @Test("Audio file detection")
    func testAudioFileDetection() {
        let audioFile = TaxonomyScannedFile(
            url: URL(fileURLWithPath: "/test/song.mp3"),
            filename: "song.mp3",
            fileExtension: "mp3",
            fileSize: 1024 * 1024 * 5, // 5 MB
            modificationDate: Date()
        )
        
        #expect(audioFile.isAudio)
        #expect(!audioFile.isVideo)
        #expect(!audioFile.isDocument)
    }
}

