import Foundation
import os.log
import AppKit

// MARK: - App Logger

/// Centralized logging for the application using OSLog.
///
/// Provides structured logging with different verbosity levels
/// and the ability to export logs for debugging.
///
/// Uses the unified logging system (os.log) which integrates with
/// Console.app and can be filtered by subsystem and category.
final class AppLogger {

    // MARK: - Singleton

    static let shared = AppLogger()

    // MARK: - Properties

    /// The logging subsystem identifier.
    private let subsystem = "com.restless"

    /// OSLog instances for different categories.
    private let generalLog: OSLog
    private let keepAwakeLog: OSLog
    private let caffeinateLog: OSLog
    private let scheduleLog: OSLog
    private let targetingLog: OSLog

    /// Current logging level (configurable via settings).
    var level: LoggingLevel = .basic

    /// In-memory log buffer for export (limited size).
    private var logBuffer: [LogEntry] = []
    private let maxBufferSize = 1000
    private let bufferQueue = DispatchQueue(label: "com.restless.logger.buffer")

    // MARK: - Log Entry

    struct LogEntry {
        let timestamp: Date
        let level: String
        let category: String
        let message: String

        var formattedString: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            return "[\(formatter.string(from: timestamp))] [\(level.uppercased())] [\(category)] \(message)"
        }
    }

    // MARK: - Initialization

    private init() {
        generalLog = OSLog(subsystem: subsystem, category: "general")
        keepAwakeLog = OSLog(subsystem: subsystem, category: "keepAwake")
        caffeinateLog = OSLog(subsystem: subsystem, category: "caffeinate")
        scheduleLog = OSLog(subsystem: subsystem, category: "schedule")
        targetingLog = OSLog(subsystem: subsystem, category: "targeting")
    }

    // MARK: - Logging Methods

    /// Logs a debug message (only shown in verbose mode).
    func debug(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        guard level == .verbose else { return }
        log(message, type: .debug, category: category, file: file, function: function, line: line)
    }

    /// Logs an info message (shown in basic and verbose modes).
    func info(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        guard level != .minimal else { return }
        log(message, type: .info, category: category, file: file, function: function, line: line)
    }

    /// Logs a warning message (always shown).
    func warning(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .default, category: category, file: file, function: function, line: line)
    }

    /// Logs an error message (always shown).
    func error(_ message: String, category: LogCategory = .general, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .error, category: category, file: file, function: function, line: line)
    }

    // MARK: - Private Methods

    private func log(_ message: String, type: OSLogType, category: LogCategory, file: String, function: String, line: Int) {
        let osLog = osLog(for: category)
        let fileName = (file as NSString).lastPathComponent

        // Log to OSLog
        os_log("%{public}@", log: osLog, type: type, message)

        // Add to buffer
        let entry = LogEntry(
            timestamp: Date(),
            level: levelString(for: type),
            category: category.rawValue,
            message: message
        )
        addToBuffer(entry)

        // Also print to console in debug builds
        #if DEBUG
        print("[\(entry.level)] [\(category.rawValue)] \(message) (\(fileName):\(line))")
        #endif
    }

    private func osLog(for category: LogCategory) -> OSLog {
        switch category {
        case .general: return generalLog
        case .keepAwake: return keepAwakeLog
        case .caffeinate: return caffeinateLog
        case .schedule: return scheduleLog
        case .targeting: return targetingLog
        }
    }

    private func levelString(for type: OSLogType) -> String {
        switch type {
        case .debug: return "debug"
        case .info: return "info"
        case .default: return "warning"
        case .error: return "error"
        case .fault: return "fault"
        default: return "unknown"
        }
    }

    private func addToBuffer(_ entry: LogEntry) {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            self.logBuffer.append(entry)
            if self.logBuffer.count > self.maxBufferSize {
                self.logBuffer.removeFirst(self.logBuffer.count - self.maxBufferSize)
            }
        }
    }

    // MARK: - Export Methods

    /// Returns all buffered log entries as a formatted string.
    func exportLogs() -> String {
        var result = ""
        bufferQueue.sync {
            result = logBuffer.map { $0.formattedString }.joined(separator: "\n")
        }
        return result
    }

    /// Saves logs to a file at the specified URL.
    func saveLogs(to url: URL) throws {
        let logContent = exportLogs()
        try logContent.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Clears the log buffer.
    func clearBuffer() {
        bufferQueue.async { [weak self] in
            self?.logBuffer.removeAll()
        }
    }

    /// Returns recent log entries (last N).
    func recentLogs(count: Int = 100) -> [LogEntry] {
        var result: [LogEntry] = []
        bufferQueue.sync {
            let startIndex = max(0, logBuffer.count - count)
            result = Array(logBuffer[startIndex...])
        }
        return result
    }
}

// MARK: - Log Category

/// Categories for log messages.
enum LogCategory: String {
    case general = "general"
    case keepAwake = "keepAwake"
    case caffeinate = "caffeinate"
    case schedule = "schedule"
    case targeting = "targeting"
}

// MARK: - Console Integration

extension AppLogger {

    /// Opens Console.app filtered to this app's logs.
    func openConsoleApp() {
        // Construct a predicate for Console.app
        // Note: This opens Console but user needs to add filter manually
        let consoleURL = URL(fileURLWithPath: "/System/Applications/Utilities/Console.app")
        NSWorkspace.shared.open(consoleURL)

        info("Opened Console.app - filter by subsystem '\(subsystem)' to see Restless logs")
    }

    /// Returns instructions for viewing logs in Console.app.
    var consoleInstructions: String {
        return """
        To view logs in Console.app:
        1. Open Console.app (Utilities folder)
        2. Select your Mac in the sidebar
        3. Click the Search field
        4. Type: subsystem:com.restless
        5. Press Enter to filter

        Or use Terminal:
        log show --predicate 'subsystem == "com.restless"' --last 1h
        """
    }
}
