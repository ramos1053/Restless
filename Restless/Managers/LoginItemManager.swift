import Foundation
import ServiceManagement
import AppKit

// MARK: - Login Item Manager

/// Manages the app's launch-at-login behavior.
///
/// Uses SMAppService (macOS 13+) for modern systems, with fallback documentation
/// for LaunchAgent plist installation on older systems.
///
/// Note on sandboxing:
/// - Sandboxed apps should use SMAppService exclusively
/// - Non-sandboxed apps can use either SMAppService or LaunchAgent plists
///
/// Requirements for SMAppService:
/// - macOS 13.0 (Ventura) or later
/// - App must be signed (development or distribution)
/// - No additional entitlements required
final class LoginItemManager: ObservableObject {

    // MARK: - Published State

    /// Whether launch at login is currently enabled.
    @Published private(set) var isEnabled: Bool = false

    /// Last error message, if any.
    @Published private(set) var lastError: String?

    // MARK: - Private Properties

    /// Shared logger.
    private let logger = AppLogger.shared

    // MARK: - Singleton

    static let shared = LoginItemManager()

    private init() {
        refreshStatus()
    }

    // MARK: - Public Methods

    /// Refreshes the current login item status.
    func refreshStatus() {
        if #available(macOS 13.0, *) {
            isEnabled = checkSMAppServiceStatus()
        } else {
            // For older macOS, we can't easily check status
            // User would need to check System Preferences manually
            logger.warning("Login item status check not available on macOS < 13.0")
            isEnabled = false
        }
    }

    /// Enables launch at login.
    func enable() {
        lastError = nil

        if #available(macOS 13.0, *) {
            enableWithSMAppService()
        } else {
            enableLegacy()
        }

        refreshStatus()
    }

    /// Disables launch at login.
    func disable() {
        lastError = nil

        if #available(macOS 13.0, *) {
            disableWithSMAppService()
        } else {
            disableLegacy()
        }

        refreshStatus()
    }

    /// Toggles launch at login.
    func toggle() {
        if isEnabled {
            disable()
        } else {
            enable()
        }
    }

    // MARK: - SMAppService (macOS 13+)

    @available(macOS 13.0, *)
    private func checkSMAppServiceStatus() -> Bool {
        let service = SMAppService.mainApp
        return service.status == .enabled
    }

    @available(macOS 13.0, *)
    private func enableWithSMAppService() {
        let service = SMAppService.mainApp

        do {
            try service.register()
            logger.info("Login item enabled via SMAppService")
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to enable login item: \(error.localizedDescription)")
        }
    }

    @available(macOS 13.0, *)
    private func disableWithSMAppService() {
        let service = SMAppService.mainApp

        do {
            try service.unregister()
            logger.info("Login item disabled via SMAppService")
        } catch {
            lastError = error.localizedDescription
            logger.error("Failed to disable login item: \(error.localizedDescription)")
        }
    }

    // MARK: - Legacy Methods (macOS < 13)

    /// Legacy enable method - provides instructions for manual setup.
    private func enableLegacy() {
        lastError = "Automatic login item setup requires macOS 13.0 or later. " +
                    "Please use the LaunchAgent plist provided with this app."
        logger.warning("Legacy login item enable requested - manual setup required")
    }

    /// Legacy disable method.
    private func disableLegacy() {
        lastError = "Automatic login item setup requires macOS 13.0 or later. " +
                    "Please remove the LaunchAgent plist manually."
        logger.warning("Legacy login item disable requested - manual removal required")
    }

    // MARK: - LaunchAgent Helpers

    /// Returns the path where a LaunchAgent plist should be installed.
    var launchAgentPath: URL {
        let libraryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")

        return libraryURL.appendingPathComponent("com.restless.agent.plist")
    }

    /// Generates a LaunchAgent plist content for manual installation.
    func generateLaunchAgentPlist() -> String {
        let appPath = Bundle.main.bundlePath

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.restless.agent</string>

            <key>ProgramArguments</key>
            <array>
                <string>\(appPath)/Contents/MacOS/Restless</string>
            </array>

            <key>RunAtLoad</key>
            <true/>

            <key>KeepAlive</key>
            <false/>

            <key>StandardOutPath</key>
            <string>/tmp/restless.log</string>

            <key>StandardErrorPath</key>
            <string>/tmp/restless.error.log</string>
        </dict>
        </plist>
        """
    }

    /// Installs the LaunchAgent plist (non-sandboxed apps only).
    func installLaunchAgentPlist() -> Bool {
        let plistContent = generateLaunchAgentPlist()
        let targetPath = launchAgentPath

        // Ensure LaunchAgents directory exists
        let directoryPath = targetPath.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryPath, withIntermediateDirectories: true)
        } catch {
            lastError = "Failed to create LaunchAgents directory: \(error.localizedDescription)"
            logger.error("Failed to create LaunchAgents directory: \(error)")
            return false
        }

        // Write plist file
        do {
            try plistContent.write(to: targetPath, atomically: true, encoding: .utf8)
            logger.info("LaunchAgent plist installed at: \(targetPath.path)")
            return true
        } catch {
            lastError = "Failed to write LaunchAgent plist: \(error.localizedDescription)"
            logger.error("Failed to write LaunchAgent plist: \(error)")
            return false
        }
    }

    /// Removes the LaunchAgent plist.
    func removeLaunchAgentPlist() -> Bool {
        let targetPath = launchAgentPath

        guard FileManager.default.fileExists(atPath: targetPath.path) else {
            return true // Already removed
        }

        do {
            try FileManager.default.removeItem(at: targetPath)
            logger.info("LaunchAgent plist removed")
            return true
        } catch {
            lastError = "Failed to remove LaunchAgent plist: \(error.localizedDescription)"
            logger.error("Failed to remove LaunchAgent plist: \(error)")
            return false
        }
    }
}

