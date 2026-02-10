import SwiftUI
import AppKit

// MARK: - Main App

/// Main entry point for Restless.
///
/// This app runs as a menu bar-only application with no Dock icon.
@main
struct RestlessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Use SwiftUI.Settings scene (renamed to avoid conflict with our AppSettings class)
        // This provides an empty settings scene for menu bar apps
        SwiftUI.Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate

/// Application delegate handling app lifecycle and setup.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    /// Application settings.
    private var settings: AppSettings!

    /// Menu bar controller.
    private var menuBarController: MenuBarController!

    /// Logger instance.
    private let logger = AppLogger.shared

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — this is a menu bar-only app
        NSApp.setActivationPolicy(.accessory)

        logger.info("Restless starting up...")

        // Load settings
        settings = AppSettings.load()

        // Configure logging level
        logger.level = settings.loggingLevel

        // Setup menu bar
        menuBarController = MenuBarController(settings: settings)
        menuBarController.setup()

        // Setup scheduling if enabled
        if settings.schedulingEnabled {
            ScheduleManager.shared.setSchedules(settings.schedules)
            ScheduleManager.shared.startScheduler()
        }

        // Start caffeinate app if enabled and has permissions
        if settings.caffeinateAppEnabled, let bundleID = settings.caffeinateAppBundleID {
            if TargetingManager.shared.hasAccessibilityPermissions {
                CaffeinateAppManager.shared.start(bundleID: bundleID, intervalSeconds: settings.caffeinateAppIntervalSeconds)
            } else {
                logger.warning("Caffeinate App enabled but missing Accessibility permissions")
            }
        }

        // Start permission monitoring
        TargetingManager.shared.startPermissionMonitoring()

        logger.info("Restless startup complete")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Restless shutting down...")

        // Stop all active sessions
        KeepAwakeManager.shared.stop()
        CaffeinateAppManager.shared.stop()
        ScheduleManager.shared.stopScheduler()

        // Save settings
        settings.save()

        // Cleanup menu bar
        menuBarController.teardown()

        logger.info("Restless shutdown complete")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when windows are closed - we're a menu bar app
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

}

// MARK: - App Activation

extension AppDelegate {

    /// Activates the app and brings it to the foreground.
    func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the preferences window.
    func openPreferences() {
        let preferencesController = PreferencesWindowController(settings: settings)
        preferencesController.show()
    }
}
