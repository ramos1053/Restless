import Foundation
import AppKit

// MARK: - Running App Info

/// Information about a running application.
struct RunningAppInfo: Identifiable, Equatable {
    /// Application name.
    let name: String

    /// Bundle identifier.
    let bundleID: String

    /// Process ID.
    let processID: Int32

    /// Bundle URL for launching.
    let bundleURL: URL?

    /// Unique identifier.
    var id: String { "app-\(bundleID)" }

    /// Display description.
    var displayDescription: String { name }
}

// MARK: - Targeting Manager

/// Manages enumeration of running applications for the caffeinate feature.
final class TargetingManager: ObservableObject {

    // MARK: - Published State

    /// All running user applications (excludes system apps).
    @Published private(set) var runningUserApps: [RunningAppInfo] = []

    /// Current accessibility permission status (updated periodically).
    @Published private(set) var hasAccessibilityPermission: Bool = false

    // MARK: - Private Properties

    /// Shared logger.
    private let logger = AppLogger.shared

    /// Timer for monitoring permission changes.
    private var permissionMonitorTimer: Timer?

    /// Interval for checking permission status.
    private let permissionCheckInterval: TimeInterval = 2.0

    // MARK: - Singleton

    static let shared = TargetingManager()

    private init() {
        refresh()
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    // MARK: - Public Methods

    /// Refreshes the list of running apps.
    func refresh() {
        runningUserApps = enumerateRunningUserApps()
    }

    /// Enumerates all running user applications (excludes system/background apps).
    private func enumerateRunningUserApps() -> [RunningAppInfo] {
        // Bundle IDs to exclude (system apps, background processes, menu bar apps)
        let excludedBundleIDPrefixes = [
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.dock",
            "com.apple.WindowManager",
            "com.apple.SystemUIServer",
            "com.apple.Spotlight",
            "com.apple.loginwindow",
            "com.apple.coreservices",
            "com.apple.CoreServices",
            "com.apple.AirPlayUIAgent",
            "com.apple.inputmethod",
            "com.apple.TextInputMenuAgent",
            "com.apple.TextInputSwitcher",
            "com.apple.wifi.WiFiAgent",
            "com.apple.universalcontrol",
            "com.apple.UserNotificationCenter",
            "com.apple.ScreenContinuity"
        ]

        var apps: [RunningAppInfo] = []
        for runningApp in NSWorkspace.shared.runningApplications {
            // Only include regular apps (not background/UI element apps)
            guard runningApp.activationPolicy == .regular else {
                continue
            }

            guard let bundleID = runningApp.bundleIdentifier,
                  let name = runningApp.localizedName else {
                continue
            }

            // Skip excluded system apps
            let isExcluded = excludedBundleIDPrefixes.contains { prefix in
                bundleID.hasPrefix(prefix)
            }
            if isExcluded {
                continue
            }

            // Skip the current app (Restless itself)
            if bundleID == Bundle.main.bundleIdentifier {
                continue
            }

            let appInfo = RunningAppInfo(
                name: name,
                bundleID: bundleID,
                processID: runningApp.processIdentifier,
                bundleURL: runningApp.bundleURL
            )
            apps.append(appInfo)
        }

        return apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    // MARK: - Accessibility Permission Monitoring

    /// Checks if the app has accessibility permissions (immediate check).
    var hasAccessibilityPermissions: Bool {
        return AXIsProcessTrusted()
    }

    /// Starts monitoring accessibility permission changes.
    func startPermissionMonitoring() {
        stopPermissionMonitoring()

        // Update immediately
        updatePermissionStatus()

        // Then check periodically
        permissionMonitorTimer = Timer.scheduledTimer(withTimeInterval: permissionCheckInterval, repeats: true) { [weak self] _ in
            self?.updatePermissionStatus()
        }

        // Add to common run loop modes for reliability
        if let timer = permissionMonitorTimer {
            RunLoop.main.add(timer, forMode: .common)
        }

        logger.debug("Started accessibility permission monitoring")
    }

    /// Stops monitoring accessibility permission changes.
    func stopPermissionMonitoring() {
        permissionMonitorTimer?.invalidate()
        permissionMonitorTimer = nil
    }

    /// Updates the permission status and notifies observers on any change.
    private func updatePermissionStatus() {
        let newStatus = AXIsProcessTrusted()
        if newStatus != hasAccessibilityPermission {
            DispatchQueue.main.async {
                self.hasAccessibilityPermission = newStatus
                self.logger.info(newStatus ? "Accessibility permission granted" : "Accessibility permission revoked")
                NotificationCenter.default.post(name: .accessibilityPermissionChanged, object: nil)
            }
        }
    }

    /// Opens System Settings to the Accessibility pane and adds the app to the list.
    /// The app will be added to the list but disabled - user just needs to enable the checkbox.
    func openAccessibilitySettings() {
        // This shows the system prompt AND adds the app to the Accessibility list (disabled)
        // User just needs to click the checkbox to enable it
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        logger.info("Requested accessibility permission - app added to list")
    }

    deinit {
        stopPermissionMonitoring()
    }
}

