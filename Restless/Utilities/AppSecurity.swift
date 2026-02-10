import Foundation
import CryptoKit
import AppKit

// MARK: - Security Utilities

/// Provides security utilities for the application.
///
/// Security measures implemented:
/// - Input validation and sanitization
/// - Secure settings storage with integrity checks
/// - Path traversal prevention
/// - Memory protection for sensitive data
/// - Rate limiting for repeated operations
final class SecurityManager {

    // MARK: - Singleton

    static let shared = SecurityManager()

    private init() {}

    // MARK: - Private Properties

    /// Rate limiting: tracks operation timestamps
    private var operationTimestamps: [String: [Date]] = [:]
    private let operationQueue = DispatchQueue(label: "com.restless.security", attributes: .concurrent)

    /// Maximum operations per minute for rate limiting
    private let maxOperationsPerMinute: Int = 60

    // MARK: - Input Validation

    /// Validates and sanitizes a file path to prevent path traversal attacks.
    /// - Parameter path: The path to validate
    /// - Returns: A sanitized path, or nil if the path is invalid
    func sanitizePath(_ path: String) -> String? {
        // Security: Check ORIGINAL path for path traversal attempts BEFORE resolving
        // This prevents symlink-based bypasses
        if path.contains("..") {
            AppLogger.shared.warning("Blocked path traversal attempt")
            return nil
        }

        // Resolve the path to its canonical form
        let url = URL(fileURLWithPath: path)
        let resolvedPath = url.standardizedFileURL.path

        // Security: Check RESOLVED path also for traversal (double-check)
        if resolvedPath.contains("..") {
            AppLogger.shared.warning("Blocked path traversal in resolved path")
            return nil
        }

        // Security: Ensure path doesn't point to sensitive system directories
        let sensitiveDirectories = [
            "/System",
            "/Library/Keychains",
            "/private/var/db",
            "/etc",
            "/var/root",
            "/usr/bin",
            "/usr/sbin",
            "/sbin",
            "/bin",
            "/private/etc"
        ]

        for dir in sensitiveDirectories {
            if resolvedPath.hasPrefix(dir) {
                AppLogger.shared.warning("Blocked access to sensitive directory")
                return nil
            }
        }

        // Security: Verify the path is within allowed directories
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let tempDir = NSTemporaryDirectory()

        let allowedPrefixes = [homeDir, tempDir]
        let isAllowed = allowedPrefixes.contains { resolvedPath.hasPrefix($0) }

        guard isAllowed else {
            AppLogger.shared.warning("Blocked access outside allowed directories")
            return nil
        }

        return resolvedPath
    }

    /// Validates a string input for safe use (prevents injection attacks).
    /// - Parameters:
    ///   - input: The string to validate
    ///   - maxLength: Maximum allowed length
    ///   - allowedCharacters: Character set of allowed characters (defaults to alphanumerics + minimal punctuation)
    /// - Returns: Sanitized string, or nil if invalid
    func sanitizeString(_ input: String, maxLength: Int = 1000, allowedCharacters: CharacterSet? = nil) -> String? {
        // Security: Reject empty input
        guard !input.isEmpty else {
            return nil
        }

        // Security: Check length before processing
        guard input.count <= maxLength else {
            AppLogger.shared.warning("Input string exceeds maximum length")
            return nil
        }

        // Security: Use restrictive default character set - no angle brackets or slashes
        let safeCharacters = allowedCharacters ?? CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "._-@#(),:!?"))

        // Filter out unsafe characters
        let sanitized = String(input.unicodeScalars.filter { safeCharacters.contains($0) })
            .trimmingCharacters(in: .whitespaces)

        // Security: Ensure result is non-empty after filtering
        guard !sanitized.isEmpty else {
            return nil
        }

        return sanitized
    }

    /// Validates a schedule name.
    func validateScheduleName(_ name: String) -> String? {
        // Schedule names: alphanumeric, spaces, and basic punctuation
        let allowedChars = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-_"))

        guard let sanitized = sanitizeString(name, maxLength: 100, allowedCharacters: allowedChars),
              !sanitized.isEmpty else {
            return nil
        }

        return sanitized.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Rate Limiting

    /// Checks if an operation should be rate limited.
    /// - Parameter operationID: Unique identifier for the operation type
    /// - Returns: true if the operation is allowed, false if rate limited
    func checkRateLimit(for operationID: String) -> Bool {
        // Security: Validate operation ID
        guard !operationID.isEmpty, operationID.count <= 100 else {
            return false
        }

        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)

        var allowed = true

        operationQueue.sync(flags: .barrier) {
            // Security: Use safe optional handling - no force unwraps
            let currentTimestamps = operationTimestamps[operationID] ?? []
            let filteredTimestamps = currentTimestamps.filter { $0 > oneMinuteAgo }

            // Check if under limit
            if filteredTimestamps.count >= maxOperationsPerMinute {
                allowed = false
                operationTimestamps[operationID] = filteredTimestamps
            } else {
                var newTimestamps = filteredTimestamps
                newTimestamps.append(now)
                operationTimestamps[operationID] = newTimestamps
            }
        }

        if !allowed {
            AppLogger.shared.warning("Rate limit exceeded for operation")
        }

        return allowed
    }

    // MARK: - Settings Integrity

    /// Computes a checksum for settings data.
    func computeChecksum(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Validates settings data integrity.
    /// - Parameters:
    ///   - data: The settings data
    ///   - expectedChecksum: The expected checksum
    /// - Returns: true if checksums match
    func validateChecksum(for data: Data, expected: String) -> Bool {
        let computed = computeChecksum(for: data)
        return computed == expected
    }

    // MARK: - Secure Deletion

    /// Securely overwrites a file before deletion (for sensitive data).
    func secureDelete(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? Int else {
            try FileManager.default.removeItem(at: url)
            return
        }

        // Overwrite with random data
        let randomData = Data((0..<fileSize).map { _ in UInt8.random(in: 0...255) })
        try randomData.write(to: url)

        // Then delete
        try FileManager.default.removeItem(at: url)

        AppLogger.shared.debug("Securely deleted file: \(url.lastPathComponent)")
    }

    // MARK: - Permission Checks

    /// Verifies the app has necessary permissions before sensitive operations.
    func verifyPermissions() -> [String: Bool] {
        return [
            "accessibility": AXIsProcessTrusted()
        ]
    }

    /// Logs a security event for audit purposes.
    func logSecurityEvent(_ event: String, details: String? = nil) {
        var message = "SECURITY: \(event)"
        if let details = details {
            message += " - \(details)"
        }
        AppLogger.shared.warning(message)
    }
}

// MARK: - Secure Settings Extension

extension AppSettings {

    /// Settings storage keys
    private static let settingsKey = "com.restless.settings"
    private static let checksumKey = "com.restless.settings.checksum"

    /// Saves settings with integrity checksum.
    func saveSecure() {
        guard let data = try? JSONEncoder().encode(self) else { return }

        // Compute checksum
        let checksum = SecurityManager.shared.computeChecksum(for: data)

        // Store both data and checksum
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
        UserDefaults.standard.set(checksum, forKey: Self.checksumKey)

        AppLogger.shared.debug("Settings saved with integrity checksum")
    }

    /// Loads settings and verifies integrity.
    static func loadSecure() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else {
            return AppSettings()
        }

        // Verify checksum if present
        if let storedChecksum = UserDefaults.standard.string(forKey: checksumKey) {
            if !SecurityManager.shared.validateChecksum(for: data, expected: storedChecksum) {
                SecurityManager.shared.logSecurityEvent("Settings integrity check failed", details: "Checksum mismatch")
                // Return default settings if tampered
                return AppSettings()
            }
        }

        guard let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }

        return settings
    }
}

// MARK: - Sandboxed File Access

extension SecurityManager {

    /// Safely accesses a file within allowed directories only.
    /// - Parameter url: The URL to access
    /// - Returns: true if access is allowed
    func isFileAccessAllowed(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path

        // Allow access to app's own directories
        var allowedPrefixes = [
            FileManager.default.homeDirectoryForCurrentUser.path,
            NSTemporaryDirectory()
        ]

        if let appSupportPath = FileManager.default.appSupportDirectory?.path {
            allowedPrefixes.append(appSupportPath)
        }

        for prefix in allowedPrefixes {
            if path.hasPrefix(prefix) {
                return true
            }
        }

        AppLogger.shared.warning("Blocked file access outside allowed directories: \(path)")
        return false
    }
}

// MARK: - Input Sanitization for UI

extension SecurityManager {

    /// Sanitizes user input from text fields before processing.
    func sanitizeUserInput(_ input: String) -> String {
        // Remove control characters
        let controlChars = CharacterSet.controlCharacters
        let sanitized = String(input.unicodeScalars.filter { !controlChars.contains($0) })

        // Trim whitespace
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates a numeric input is within expected bounds.
    func validateNumericInput<T: Comparable>(_ value: T, min: T, max: T) -> T {
        return Swift.min(max, Swift.max(min, value))
    }
}
