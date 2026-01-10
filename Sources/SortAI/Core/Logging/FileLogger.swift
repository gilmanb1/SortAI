// MARK: - FileLogger
// Timestamped file logging with separate .log and .error streams
// Only active in dev mode (DEBUG build or SORTAI_DEV_LOGGING=1)

import Foundation
import os.log

// MARK: - Log Level

/// Log levels for categorizing messages
public enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case notice = 2
    case warning = 3
    case error = 4
    case fault = 5
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    public var symbol: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .notice: return "📝"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .fault: return "💥"
        }
    }
    
    public var name: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        }
    }
    
    /// Whether this level goes to stderr (and thus .error file)
    public var isError: Bool {
        self >= .error
    }
}

// MARK: - Log Configuration

/// Configuration for the file logger
public struct LogConfiguration: Codable, Sendable {
    /// Directory where log files are stored
    public var logDirectory: String
    
    /// Maximum age of log files in days before cleanup
    public var maxAgeDays: Int
    
    /// Maximum total size of logs in bytes before cleanup
    public var maxTotalSizeBytes: Int64
    
    /// Whether to also print to console (stdout/stderr)
    public var printToConsole: Bool
    
    /// Whether file logging is enabled
    public var enabled: Bool
    
    public static let `default` = LogConfiguration(
        logDirectory: defaultLogDirectory,
        maxAgeDays: 30,
        maxTotalSizeBytes: 1_073_741_824, // 1GB
        printToConsole: ProcessInfo.processInfo.environment["SORTAI_LOG_CONSOLE"] == "1",
        enabled: true
    )
    
    private static var defaultLogDirectory: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SortAI/logs").path
    }
    
    public init(
        logDirectory: String? = nil,
        maxAgeDays: Int = 30,
        maxTotalSizeBytes: Int64 = 1_073_741_824,
        printToConsole: Bool = false,
        enabled: Bool = true
    ) {
        self.logDirectory = logDirectory ?? Self.defaultLogDirectory
        self.maxAgeDays = maxAgeDays
        self.maxTotalSizeBytes = maxTotalSizeBytes
        self.printToConsole = printToConsole
        self.enabled = enabled
    }
}

// MARK: - FileLogger Actor

/// Thread-safe file logger that streams to .log and .error files
public actor FileLogger {
    
    // MARK: - Shared Instance
    
    /// Shared logger instance
    public static let shared = FileLogger()
    
    // MARK: - Properties
    
    private var configuration: LogConfiguration
    private var logFileHandle: FileHandle?
    private var errorFileHandle: FileHandle?
    private var currentLogPath: URL?
    private var currentErrorPath: URL?
    private var sessionStartTime: Date
    private var isInitialized = false
    
    private let fileManager = FileManager.default
    private let osLogger = Logger(subsystem: "com.sortai.app", category: "filelogger")
    
    // Cached formatters for performance
    private let timestampFormatter: DateFormatter
    private let filenameFormatter: DateFormatter
    
    // MARK: - Initialization
    
    public init(configuration: LogConfiguration = .default) {
        self.configuration = configuration
        self.sessionStartTime = Date()
        
        // Initialize formatters
        self.timestampFormatter = DateFormatter()
        self.timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        self.filenameFormatter = DateFormatter()
        self.filenameFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    }
    
    // MARK: - Public API
    
    /// Check if file logging should be active
    public static var isDevMode: Bool {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.environment["SORTAI_DEV_LOGGING"] == "1"
        #endif
    }
    
    /// Initialize the logger and create log files
    public func initialize() async throws {
        guard Self.isDevMode && configuration.enabled else {
            osLogger.debug("FileLogger disabled (not dev mode or disabled in config)")
            return
        }
        
        guard !isInitialized else { return }
        
        // Create log directory
        let logDir = URL(fileURLWithPath: configuration.logDirectory)
        try fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
        
        // Create timestamped log files
        let timestamp = filenameFormatter.string(from: sessionStartTime)
        let logPath = logDir.appendingPathComponent("sortai_\(timestamp).log")
        let errorPath = logDir.appendingPathComponent("sortai_\(timestamp).error")
        
        // Create files
        fileManager.createFile(atPath: logPath.path, contents: nil)
        fileManager.createFile(atPath: errorPath.path, contents: nil)
        
        // Open file handles
        logFileHandle = try FileHandle(forWritingTo: logPath)
        errorFileHandle = try FileHandle(forWritingTo: errorPath)
        
        // Seek to end for appending
        try logFileHandle?.seekToEnd()
        try errorFileHandle?.seekToEnd()
        
        currentLogPath = logPath
        currentErrorPath = errorPath
        isInitialized = true
        
        // Write header
        let header = """
        ================================================================================
        SortAI Log Session Started
        Time: \(timestampFormatter.string(from: sessionStartTime))
        PID: \(ProcessInfo.processInfo.processIdentifier)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        ================================================================================
        
        """
        
        try logFileHandle?.write(contentsOf: Data(header.utf8))
        try errorFileHandle?.write(contentsOf: Data(header.utf8))
        
        osLogger.info("FileLogger initialized: \(logPath.path)")
        
        // Perform log cleanup
        await cleanupOldLogs()
    }
    
    /// Log a message at the specified level
    public func log(
        _ message: String,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        guard isInitialized else { return }
        
        let formattedMessage = formatMessage(
            message,
            level: level,
            file: file,
            function: function,
            line: line
        )
        
        // Write to appropriate file (mutually exclusive)
        do {
            if level.isError {
                // Error and above go to .error file only
                try errorFileHandle?.write(contentsOf: Data(formattedMessage.utf8))
            } else {
                // Non-error messages go to .log file only
                try logFileHandle?.write(contentsOf: Data(formattedMessage.utf8))
            }
        } catch {
            osLogger.error("Failed to write to log file: \(error.localizedDescription)")
        }
        
        // Optionally print to console
        if configuration.printToConsole {
            if level.isError {
                fputs(formattedMessage, stderr)
            } else {
                print(formattedMessage, terminator: "")
            }
        }
    }
    
    /// Log multiple lines (for large outputs like LLM responses)
    public func logBlock(
        _ message: String,
        header: String? = nil,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) async {
        if let header = header {
            await log(header, level: level, file: file, function: function, line: line)
        }
        
        // Log each line separately for readability
        for logLine in message.components(separatedBy: .newlines) {
            await log(logLine, level: level, file: file, function: function, line: line)
        }
    }
    
    /// Flush pending writes to disk
    public func flush() async {
        try? logFileHandle?.synchronize()
        try? errorFileHandle?.synchronize()
    }
    
    /// Close the logger
    public func close() async {
        await flush()
        
        let footer = """
        
        ================================================================================
        SortAI Log Session Ended
        Time: \(timestampFormatter.string(from: Date()))
        Duration: \(formatDuration(Date().timeIntervalSince(sessionStartTime)))
        ================================================================================
        """
        
        try? logFileHandle?.write(contentsOf: Data(footer.utf8))
        try? errorFileHandle?.write(contentsOf: Data(footer.utf8))
        
        try? logFileHandle?.close()
        try? errorFileHandle?.close()
        
        logFileHandle = nil
        errorFileHandle = nil
        isInitialized = false
    }
    
    /// Update configuration at runtime
    public func updateConfiguration(_ config: LogConfiguration) {
        self.configuration = config
    }
    
    /// Get current log file paths
    public func getLogPaths() -> (log: URL?, error: URL?) {
        (currentLogPath, currentErrorPath)
    }
    
    // MARK: - Private Helpers
    
    private func formatMessage(
        _ message: String,
        level: LogLevel,
        file: String,
        function: String,
        line: Int
    ) -> String {
        let timestamp = timestampFormatter.string(from: Date())
        let filename = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        
        #if DEBUG
        // Detailed format for debug builds
        return "[\(timestamp)] [\(level.name)] [\(filename):\(line)] [\(function)] \(message)\n"
        #else
        // Simple format for production builds
        return "[\(timestamp)] [\(level.name)] \(message)\n"
        #endif
    }
    
    private func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    // MARK: - Log Cleanup
    
    private func cleanupOldLogs() async {
        let logDir = URL(fileURLWithPath: configuration.logDirectory)
        
        guard let files = try? fileManager.contentsOfDirectory(
            at: logDir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        let logFiles = files.filter { $0.pathExtension == "log" || $0.pathExtension == "error" }
        let now = Date()
        let maxAge = TimeInterval(configuration.maxAgeDays * 24 * 60 * 60)
        
        var totalSize: Int64 = 0
        var filesToDelete: [URL] = []
        
        // Sort by creation date (oldest first)
        let sortedFiles = logFiles.sorted { file1, file2 in
            let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now
            let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? now
            return date1 < date2
        }
        
        for file in sortedFiles {
            guard let attributes = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]) else {
                continue
            }
            
            let creationDate = attributes.creationDate ?? now
            let fileSize = Int64(attributes.fileSize ?? 0)
            
            // Skip current session's files
            if file == currentLogPath || file == currentErrorPath {
                totalSize += fileSize
                continue
            }
            
            // Check age
            if now.timeIntervalSince(creationDate) > maxAge {
                filesToDelete.append(file)
                continue
            }
            
            totalSize += fileSize
        }
        
        // Check total size and delete oldest until under limit
        for file in sortedFiles where !filesToDelete.contains(file) {
            if totalSize > configuration.maxTotalSizeBytes {
                if file != currentLogPath && file != currentErrorPath {
                    filesToDelete.append(file)
                    let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    totalSize -= size
                }
            }
        }
        
        // Delete files
        for file in filesToDelete {
            do {
                try fileManager.removeItem(at: file)
                osLogger.debug("Cleaned up old log: \(file.lastPathComponent)")
            } catch {
                osLogger.error("Failed to delete old log \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        if !filesToDelete.isEmpty {
            osLogger.info("Cleaned up \(filesToDelete.count) old log files")
        }
    }
}

// MARK: - Convenience Logging Functions

/// Log a message to the file logger (dev mode only)
/// This is designed to be a drop-in replacement for NSLog in many cases
@inlinable
public func SortAILog(
    _ message: String,
    level: LogLevel = .info,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    guard FileLogger.isDevMode else { return }
    
    Task {
        await FileLogger.shared.log(message, level: level, file: file, function: function, line: line)
    }
    
    // Also send to NSLog for Console.app visibility
    NSLog("%@ [%@] %@", level.symbol, level.name, message)
}

/// Log an error message
@inlinable
public func SortAILogError(
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    SortAILog(message, level: .error, file: file, function: function, line: line)
}

/// Log a warning message
@inlinable
public func SortAILogWarning(
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    SortAILog(message, level: .warning, file: file, function: function, line: line)
}

/// Log a debug message
@inlinable
public func SortAILogDebug(
    _ message: String,
    file: String = #file,
    function: String = #function,
    line: Int = #line
) {
    SortAILog(message, level: .debug, file: file, function: function, line: line)
}

// MARK: - Stderr Capture

/// Captures stderr output and redirects to error log file
public actor StderrCapture {
    public static let shared = StderrCapture()
    
    private var originalStderr: Int32 = -1
    private var pipeReadFD: Int32 = -1
    private var pipeWriteFD: Int32 = -1
    private var captureTask: Task<Void, Never>?
    private var isCapturing = false
    
    /// Start capturing stderr
    public func startCapture() async {
        guard FileLogger.isDevMode else { return }
        guard !isCapturing else { return }
        
        // Create a pipe
        var pipeFDs: [Int32] = [0, 0]
        guard pipe(&pipeFDs) == 0 else {
            NSLog("❌ Failed to create stderr capture pipe")
            return
        }
        
        pipeReadFD = pipeFDs[0]
        pipeWriteFD = pipeFDs[1]
        
        // Save original stderr
        originalStderr = dup(STDERR_FILENO)
        
        // Redirect stderr to our pipe
        dup2(pipeWriteFD, STDERR_FILENO)
        
        isCapturing = true
        
        // Start reading from the pipe
        captureTask = Task {
            await readCapturedOutput()
        }
        
        NSLog("📝 Stderr capture started")
    }
    
    /// Stop capturing stderr
    public func stopCapture() async {
        guard isCapturing else { return }
        
        // Restore original stderr
        if originalStderr >= 0 {
            dup2(originalStderr, STDERR_FILENO)
            close(originalStderr)
            originalStderr = -1
        }
        
        // Close pipe write end to signal EOF to reader
        if pipeWriteFD >= 0 {
            close(pipeWriteFD)
            pipeWriteFD = -1
        }
        
        // Wait for capture task to finish
        captureTask?.cancel()
        captureTask = nil
        
        // Close pipe read end
        if pipeReadFD >= 0 {
            close(pipeReadFD)
            pipeReadFD = -1
        }
        
        isCapturing = false
    }
    
    private func readCapturedOutput() async {
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        
        while !Task.isCancelled && pipeReadFD >= 0 {
            let bytesRead = read(pipeReadFD, &buffer, bufferSize)
            
            if bytesRead <= 0 {
                break
            }
            
            if let message = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
                // Log to error file (stderr content is treated as error level)
                await FileLogger.shared.log(
                    message.trimmingCharacters(in: .newlines),
                    level: .error,
                    file: "stderr",
                    function: "captured",
                    line: 0
                )
            }
        }
    }
}

