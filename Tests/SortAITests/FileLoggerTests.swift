// MARK: - FileLogger Tests
// Tests for file logging system

import XCTest
@testable import SortAI

final class FileLoggerTests: XCTestCase {
    
    var testLogDir: URL!
    
    override func setUp() async throws {
        // Create a temporary directory for test logs
        testLogDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortAITests/logs/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testLogDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up test logs
        try? FileManager.default.removeItem(at: testLogDir)
    }
    
    // MARK: - LogLevel Tests
    
    func testLogLevelComparison() {
        XCTAssertTrue(LogLevel.debug < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.notice)
        XCTAssertTrue(LogLevel.notice < LogLevel.warning)
        XCTAssertTrue(LogLevel.warning < LogLevel.error)
        XCTAssertTrue(LogLevel.error < LogLevel.fault)
    }
    
    func testLogLevelIsError() {
        XCTAssertFalse(LogLevel.debug.isError)
        XCTAssertFalse(LogLevel.info.isError)
        XCTAssertFalse(LogLevel.notice.isError)
        XCTAssertFalse(LogLevel.warning.isError)
        XCTAssertTrue(LogLevel.error.isError)
        XCTAssertTrue(LogLevel.fault.isError)
    }
    
    func testLogLevelSymbols() {
        XCTAssertEqual(LogLevel.debug.symbol, "🔍")
        XCTAssertEqual(LogLevel.info.symbol, "ℹ️")
        XCTAssertEqual(LogLevel.notice.symbol, "📝")
        XCTAssertEqual(LogLevel.warning.symbol, "⚠️")
        XCTAssertEqual(LogLevel.error.symbol, "❌")
        XCTAssertEqual(LogLevel.fault.symbol, "💥")
    }
    
    func testLogLevelNames() {
        XCTAssertEqual(LogLevel.debug.name, "DEBUG")
        XCTAssertEqual(LogLevel.info.name, "INFO")
        XCTAssertEqual(LogLevel.notice.name, "NOTICE")
        XCTAssertEqual(LogLevel.warning.name, "WARNING")
        XCTAssertEqual(LogLevel.error.name, "ERROR")
        XCTAssertEqual(LogLevel.fault.name, "FAULT")
    }
    
    // MARK: - LogConfiguration Tests
    
    func testLogConfigurationDefaults() {
        let config = LogConfiguration.default
        
        XCTAssertTrue(config.logDirectory.contains("SortAI/logs"))
        XCTAssertEqual(config.maxAgeDays, 30)
        XCTAssertEqual(config.maxTotalSizeBytes, 1_073_741_824) // 1GB
        XCTAssertTrue(config.enabled)
    }
    
    func testLogConfigurationCustom() {
        let config = LogConfiguration(
            logDirectory: "/tmp/custom",
            maxAgeDays: 7,
            maxTotalSizeBytes: 100_000_000,
            printToConsole: true,
            enabled: false
        )
        
        XCTAssertEqual(config.logDirectory, "/tmp/custom")
        XCTAssertEqual(config.maxAgeDays, 7)
        XCTAssertEqual(config.maxTotalSizeBytes, 100_000_000)
        XCTAssertTrue(config.printToConsole)
        XCTAssertFalse(config.enabled)
    }
    
    // MARK: - FileLogger Tests
    
    func testFileLoggerIsDevMode() {
        // In test builds, DEBUG should be defined
        #if DEBUG
        XCTAssertTrue(FileLogger.isDevMode)
        #else
        // In release without env var, should be false
        XCTAssertFalse(FileLogger.isDevMode)
        #endif
    }
    
    func testFileLoggerInitialization() async throws {
        let config = LogConfiguration(
            logDirectory: testLogDir.path,
            maxAgeDays: 30,
            maxTotalSizeBytes: 1_073_741_824,
            printToConsole: false,
            enabled: true
        )
        
        let logger = FileLogger(configuration: config)
        try await logger.initialize()
        
        let paths = await logger.getLogPaths()
        
        // Check that log files were created
        XCTAssertNotNil(paths.log)
        XCTAssertNotNil(paths.error)
        
        if let logPath = paths.log {
            XCTAssertTrue(FileManager.default.fileExists(atPath: logPath.path))
            XCTAssertTrue(logPath.lastPathComponent.hasPrefix("sortai_"))
            XCTAssertTrue(logPath.lastPathComponent.hasSuffix(".log"))
        }
        
        if let errorPath = paths.error {
            XCTAssertTrue(FileManager.default.fileExists(atPath: errorPath.path))
            XCTAssertTrue(errorPath.lastPathComponent.hasPrefix("sortai_"))
            XCTAssertTrue(errorPath.lastPathComponent.hasSuffix(".error"))
        }
        
        await logger.close()
    }
    
    func testFileLoggerWritesToCorrectFile() async throws {
        let config = LogConfiguration(
            logDirectory: testLogDir.path,
            maxAgeDays: 30,
            maxTotalSizeBytes: 1_073_741_824,
            printToConsole: false,
            enabled: true
        )
        
        let logger = FileLogger(configuration: config)
        try await logger.initialize()
        
        // Write info message (should go to .log)
        await logger.log("Test info message", level: .info)
        
        // Write error message (should go to .error)
        await logger.log("Test error message", level: .error)
        
        // Flush to ensure writes are complete
        await logger.flush()
        
        let paths = await logger.getLogPaths()
        
        // Check .log file contains info message but not error
        if let logPath = paths.log {
            let logContent = try String(contentsOf: logPath, encoding: .utf8)
            XCTAssertTrue(logContent.contains("Test info message"))
            XCTAssertFalse(logContent.contains("Test error message"))
        }
        
        // Check .error file contains error message but not info
        if let errorPath = paths.error {
            let errorContent = try String(contentsOf: errorPath, encoding: .utf8)
            XCTAssertTrue(errorContent.contains("Test error message"))
            XCTAssertFalse(errorContent.contains("Test info message"))
        }
        
        await logger.close()
    }
    
    func testFileLoggerWarningGoesToLogFile() async throws {
        let config = LogConfiguration(
            logDirectory: testLogDir.path,
            maxAgeDays: 30,
            maxTotalSizeBytes: 1_073_741_824,
            printToConsole: false,
            enabled: true
        )
        
        let logger = FileLogger(configuration: config)
        try await logger.initialize()
        
        // Warning should go to .log (not .error)
        await logger.log("Test warning message", level: .warning)
        await logger.flush()
        
        let paths = await logger.getLogPaths()
        
        if let logPath = paths.log {
            let logContent = try String(contentsOf: logPath, encoding: .utf8)
            XCTAssertTrue(logContent.contains("Test warning message"))
        }
        
        if let errorPath = paths.error {
            let errorContent = try String(contentsOf: errorPath, encoding: .utf8)
            XCTAssertFalse(errorContent.contains("Test warning message"))
        }
        
        await logger.close()
    }
    
    func testFileLoggerSessionHeader() async throws {
        let config = LogConfiguration(
            logDirectory: testLogDir.path,
            maxAgeDays: 30,
            maxTotalSizeBytes: 1_073_741_824,
            printToConsole: false,
            enabled: true
        )
        
        let logger = FileLogger(configuration: config)
        try await logger.initialize()
        
        let paths = await logger.getLogPaths()
        
        if let logPath = paths.log {
            let logContent = try String(contentsOf: logPath, encoding: .utf8)
            XCTAssertTrue(logContent.contains("SortAI Log Session Started"))
            XCTAssertTrue(logContent.contains("PID:"))
            XCTAssertTrue(logContent.contains("macOS:"))
        }
        
        await logger.close()
    }
    
    func testFileLoggerSessionFooter() async throws {
        let config = LogConfiguration(
            logDirectory: testLogDir.path,
            maxAgeDays: 30,
            maxTotalSizeBytes: 1_073_741_824,
            printToConsole: false,
            enabled: true
        )
        
        let logger = FileLogger(configuration: config)
        try await logger.initialize()
        
        let paths = await logger.getLogPaths()
        
        // Close to write footer
        await logger.close()
        
        if let logPath = paths.log {
            let logContent = try String(contentsOf: logPath, encoding: .utf8)
            XCTAssertTrue(logContent.contains("SortAI Log Session Ended"))
            XCTAssertTrue(logContent.contains("Duration:"))
        }
    }
    
    // MARK: - LoggingConfiguration Tests
    
    func testLoggingConfigurationConversion() {
        let loggingConfig = LoggingConfiguration(
            logDirectory: "/custom/path",
            maxAgeDays: 14,
            maxTotalSizeBytes: 500_000_000,
            printToConsole: true,
            enabled: true
        )
        
        let logConfig = loggingConfig.asLogConfiguration
        
        XCTAssertEqual(logConfig.logDirectory, "/custom/path")
        XCTAssertEqual(logConfig.maxAgeDays, 14)
        XCTAssertEqual(logConfig.maxTotalSizeBytes, 500_000_000)
        XCTAssertTrue(logConfig.printToConsole)
        XCTAssertTrue(logConfig.enabled)
    }
    
    func testLoggingConfigurationDefaults() {
        let config = LoggingConfiguration.default
        
        XCTAssertTrue(config.logDirectory.contains("SortAI/logs"))
        XCTAssertEqual(config.maxAgeDays, 30)
        XCTAssertEqual(config.maxTotalSizeBytes, 1_073_741_824)
        XCTAssertTrue(config.enabled)
    }
    
    // MARK: - Log Cleanup Tests
    
    func testLogCleanupByAge() async throws {
        // Create old log files
        let oldDate = Calendar.current.date(byAdding: .day, value: -45, to: Date())!
        let oldTimestamp = DateFormatter().then { $0.dateFormat = "yyyy-MM-dd_HH-mm-ss" }.string(from: oldDate)
        
        let oldLogPath = testLogDir.appendingPathComponent("sortai_\(oldTimestamp).log")
        let oldErrorPath = testLogDir.appendingPathComponent("sortai_\(oldTimestamp).error")
        
        try "old log content".write(to: oldLogPath, atomically: true, encoding: .utf8)
        try "old error content".write(to: oldErrorPath, atomically: true, encoding: .utf8)
        
        // Set creation date to old date
        try FileManager.default.setAttributes(
            [.creationDate: oldDate],
            ofItemAtPath: oldLogPath.path
        )
        try FileManager.default.setAttributes(
            [.creationDate: oldDate],
            ofItemAtPath: oldErrorPath.path
        )
        
        // Initialize logger (should clean up old files)
        let config = LogConfiguration(
            logDirectory: testLogDir.path,
            maxAgeDays: 30,
            maxTotalSizeBytes: 1_073_741_824,
            printToConsole: false,
            enabled: true
        )
        
        let logger = FileLogger(configuration: config)
        try await logger.initialize()
        
        // Give cleanup time to run
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        // Old files should be deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldLogPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldErrorPath.path))
        
        await logger.close()
    }
}

// MARK: - Helper Extensions

extension DateFormatter {
    func then(_ configure: (DateFormatter) -> Void) -> DateFormatter {
        configure(self)
        return self
    }
}

