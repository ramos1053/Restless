import Foundation
import AppKit
import CoreGraphics
import IOKit
import IOKit.pwr_mgt

// MARK: - Caffeinate App Manager

/// Manages keeping a background app active by sending periodic invisible events to its process.
/// This allows apps to show the user as "Active" without moving the cursor.
final class CaffeinateAppManager: ObservableObject {

    // MARK: - Singleton

    static let shared = CaffeinateAppManager()

    // MARK: - Published State

    /// Whether caffeinate is currently running.
    @Published private(set) var isRunning: Bool = false

    /// The name of the app being caffeinated.
    @Published private(set) var targetAppName: String?

    /// Number of activity events sent.
    @Published private(set) var eventCount: Int = 0

    /// Last time an event was sent.
    @Published private(set) var lastEventTime: Date?

    /// Which prevention method is currently active.
    @Published private(set) var activeMethod: AwakeMethod = .none

    /// Health status of the current prevention method.
    @Published private(set) var methodStatus: MethodStatus = .inactive

    /// Whether mouse events are working (requires accessibility).
    @Published private(set) var mouseEventsWorking: Bool = false

    /// Computed convenience for health checks.
    var isHealthy: Bool { methodStatus.isHealthy }

    // MARK: - Security Constants

    /// Minimum allowed interval in seconds
    private static let minIntervalSeconds: Int = 15

    /// Maximum allowed interval in seconds (10 minutes)
    private static let maxIntervalSeconds: Int = 600

    /// Maximum allowed caffeinate duration in seconds (15 minutes)
    private static let maxCaffeinateDuration: Int = 900

    // MARK: - Private Properties

    private var timer: Timer?
    private var targetBundleID: String?
    private var targetPID: Int32?  // Security: Track PID for verification
    private var intervalSeconds: Int = 30
    private let logger = AppLogger.shared

    /// User activity assertion ID for IOPMAssertionDeclareUserActivity.
    private var userActivityAssertionID: IOPMAssertionID = IOPMAssertionID(0)

    // MARK: - Initialization

    private init() {}

    // MARK: - Security Validation

    /// Validates and sanitizes the interval value.
    private func sanitizeInterval(_ interval: Int) -> Int {
        return max(Self.minIntervalSeconds, min(Self.maxIntervalSeconds, interval))
    }

    /// Validates that a bundle ID belongs to a legitimate user application.
    /// Security: Prevents targeting system processes or other sensitive apps.
    private func isValidTargetApp(bundleID: String) -> Bool {
        // Reject empty bundle IDs
        guard !bundleID.isEmpty else { return false }

        // Security: Block system processes and critical apps
        let blockedPrefixes = [
            "com.apple.finder",
            "com.apple.loginwindow",
            "com.apple.SecurityAgent",
            "com.apple.systempreferences",
            "com.apple.Terminal",
            "com.apple.dt.Xcode"
        ]

        for prefix in blockedPrefixes {
            if bundleID.hasPrefix(prefix) {
                logger.warning("Security: Blocked caffeinate target: \(bundleID)")
                return false
            }
        }

        // Verify the app is a user application (not a background daemon)
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            return false
        }

        // Security: Only allow regular applications, not background agents
        return app.activationPolicy == .regular || app.activationPolicy == .accessory
    }

    /// Verifies the target process is still valid and hasn't been replaced.
    /// Security: Prevents PID reuse attacks.
    private func verifyTargetProcess() -> NSRunningApplication? {
        guard let bundleID = targetBundleID, let expectedPID = targetPID else {
            return nil
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            return nil
        }

        // Security: Verify PID hasn't changed (process was replaced)
        guard app.processIdentifier == expectedPID else {
            logger.warning("Security: Target process PID changed, stopping caffeinate")
            return nil
        }

        return app
    }

    // MARK: - Public Methods

    /// Starts caffeinating the specified app.
    func start(bundleID: String, intervalSeconds: Int = 30) {
        // Security: Validate bundle ID
        guard !bundleID.isEmpty else {
            logger.warning("Cannot start caffeinate: no bundle ID specified")
            return
        }

        // Security: Validate the target app is allowed
        guard isValidTargetApp(bundleID: bundleID) else {
            logger.warning("Cannot start caffeinate: app '\(bundleID)' is not a valid target")
            return
        }

        // Verify the app is running
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            logger.warning("Cannot start caffeinate: app with bundle ID is not running")
            return
        }

        // Security: Sanitize interval to prevent DoS
        let sanitizedInterval = sanitizeInterval(intervalSeconds)

        self.targetBundleID = bundleID
        self.targetAppName = app.localizedName
        self.targetPID = app.processIdentifier  // Security: Track PID for verification
        self.intervalSeconds = sanitizedInterval
        self.eventCount = 0
        self.isRunning = true

        // Set initial health based on accessibility permission
        let hasAccessibility = TargetingManager.shared.hasAccessibilityPermissions
        self.mouseEventsWorking = hasAccessibility
        self.activeMethod = .caffeinate

        if hasAccessibility {
            self.methodStatus = .healthy(method: .caffeinate)
        } else {
            self.methodStatus = .degraded(method: .caffeinate, reason: "No accessibility permission")
            logger.warning("Caffeinate started without accessibility - mouse events disabled")
        }

        // Start the timer
        startTimer()

        // Send an initial event
        sendActivityEvent()

        logger.info("Started caffeinating app every \(sanitizedInterval) seconds")

        NotificationCenter.default.post(name: .caffeinateStateDidChange, object: nil)
        NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
    }

    /// Stops caffeinating.
    func stop() {
        timer?.invalidate()
        timer = nil

        // Release user activity assertion
        releaseUserActivityAssertion()

        targetBundleID = nil
        targetAppName = nil
        targetPID = nil  // Security: Clear tracked PID
        isRunning = false
        activeMethod = .none
        methodStatus = .inactive
        mouseEventsWorking = false

        logger.info("Stopped caffeinating after \(eventCount) events")

        NotificationCenter.default.post(name: .caffeinateStateDidChange, object: nil)
        NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
    }

    /// Updates the interval while running.
    func updateInterval(_ newInterval: Int) {
        guard isRunning else { return }
        // Security: Sanitize interval
        self.intervalSeconds = sanitizeInterval(newInterval)
        startTimer() // Restart timer with new interval
    }

    // MARK: - Private Methods

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalSeconds), repeats: true) { [weak self] _ in
            self?.sendActivityEvent()
        }
    }

    /// Sends invisible activity events to the target process.
    private func sendActivityEvent() {
        // Security: Verify target process is still valid and PID hasn't been reused
        guard let app = verifyTargetProcess() else {
            logger.warning("Target app is no longer valid")
            stop()
            return
        }

        let pid = app.processIdentifier

        // Check accessibility permission for mouse events
        let hasAccessibility = TargetingManager.shared.hasAccessibilityPermissions

        if hasAccessibility {
            // Send invisible mouse events to keep the app active
            let position = getTargetPosition(for: app)
            sendMouseMoveToProcess(pid: pid, position: position)
            let offsetPosition = CGPoint(x: position.x + 1, y: position.y)
            sendMouseMoveToProcess(pid: pid, position: offsetPosition)
            sendMouseMoveToProcess(pid: pid, position: position)

            // Send a shift key press/release to reset idle timers in web apps
            sendKeyEventToProcess(pid: pid)

            // Track recovery from degraded state
            if !mouseEventsWorking {
                mouseEventsWorking = true
                methodStatus = .healthy(method: .caffeinate)
                logger.info("Mouse events restored (accessibility permission granted)")

                NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
            }
        } else {
            // No accessibility - skip mouse events, rely on caffeinate -u only
            if mouseEventsWorking {
                mouseEventsWorking = false
                methodStatus = .degraded(method: .caffeinate, reason: "No accessibility permission")
                logger.warning("Accessibility permission lost - mouse events disabled, using caffeinate -u only")
                NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
            }
        }

        // Always declare system-level user activity to prevent screen lock
        declareUserActivity()

        eventCount += 1
        lastEventTime = Date()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .caffeinateStateDidChange, object: nil)
        }
    }

    /// Gets a target position within the app's window.
    /// Tries on-screen windows first, then falls back to all windows (includes minimized).
    private func getTargetPosition(for app: NSRunningApplication) -> CGPoint {
        let pid = app.processIdentifier

        // First try on-screen windows
        if let position = findWindowPosition(for: pid, options: [.optionOnScreenOnly, .excludeDesktopElements]) {
            return position
        }

        // Fallback: try ALL windows (includes minimized/hidden)
        if let position = findWindowPosition(for: pid, options: [.excludeDesktopElements]) {
            return position
        }

        // No window found at all, use a default position
        return CGPoint(x: 100, y: 100)
    }

    /// Searches for a window belonging to the given PID and returns its center point.
    private func findWindowPosition(for pid: Int32, options: CGWindowListOption) -> CGPoint? {
        let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
        guard let windows = windowList as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard let windowPID = window[kCGWindowOwnerPID as String] as? Int32,
                  windowPID == pid,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"],
                  let y = bounds["Y"],
                  let width = bounds["Width"],
                  let height = bounds["Height"],
                  width > 50 && height > 50 else {
                continue
            }

            return CGPoint(x: x + width / 2, y: y + height / 2)
        }

        return nil
    }

    /// Sends a shift key press/release to a process to reset idle timers.
    /// Shift alone has no visible effect in most apps but reliably triggers activity detection.
    private func sendKeyEventToProcess(pid: Int32) {
        let shiftKeyCode: UInt16 = 56 // kVK_Shift
        // Key down
        if let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: shiftKeyCode, keyDown: true) {
            keyDown.postToPid(pid)
        }
        // Key up
        if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: shiftKeyCode, keyDown: false) {
            keyUp.postToPid(pid)
        }
        logger.debug("Sent shift key event to PID \(pid)")
    }

    /// Sends a mouse move event directly to a process without moving the actual cursor.
    private func sendMouseMoveToProcess(pid: Int32, position: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: position,
            mouseButton: .left
        ) else {
            return
        }

        // Post directly to the process - this doesn't move the actual cursor
        event.postToPid(pid)
    }

    // MARK: - User Activity (Prevents Screen Lock)

    /// Declares that the user is active, which:
    /// - Turns on the display if it's off
    /// - Resets the idle timer
    /// - Prevents screen lock from activating
    ///
    /// Uses caffeinate -u which is the most reliable method for preventing screen lock.
    private func declareUserActivity() {
        // Spawn caffeinate -u -t <interval+5> to declare user activity
        // Duration slightly longer than interval to ensure overlap
        // Security: Bound the duration to prevent excessive values
        let rawDuration = intervalSeconds + 5
        let duration = min(rawDuration, Self.maxCaffeinateDuration)

        // Security: Validate duration is positive
        guard duration > 0 else {
            logger.warning("Invalid caffeinate duration, skipping")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        task.arguments = ["-u", "-t", String(duration)]

        do {
            try task.run()
            logger.debug("Caffeinate user activity spawned")

            // If we were in userActivityOnly mode, we've recovered to caffeinate
            if activeMethod == .userActivityOnly {
                activeMethod = .caffeinate
                if mouseEventsWorking {
                    methodStatus = .healthy(method: .caffeinate)
                } else {
                    methodStatus = .degraded(method: .caffeinate, reason: "No accessibility permission")
                }
                logger.info("Recovered to caffeinate method")
                NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
            }
        } catch {
            logger.warning("Failed to spawn user activity caffeinate, falling back to IOKit")
            // Fallback to IOPMAssertionDeclareUserActivity
            let iokitSuccess = declareUserActivityViaAssertion()

            if iokitSuccess {
                if activeMethod != .userActivityOnly {
                    activeMethod = .userActivityOnly
                    methodStatus = .degraded(method: .userActivityOnly, reason: "caffeinate -u unavailable")
                    logger.warning("Degraded to IOKit user activity assertion")
                    NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
                }
            } else {
                methodStatus = .failed(reason: "All user activity methods failed")
                logger.error("All user activity methods failed")

                NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
            }
        }
    }

    /// Fallback method using IOPMAssertionDeclareUserActivity.
    @discardableResult
    private func declareUserActivityViaAssertion() -> Bool {
        let assertionName = "Restless Caffeinate User Activity" as CFString

        let result = IOPMAssertionDeclareUserActivity(
            assertionName,
            kIOPMUserActiveLocal,
            &userActivityAssertionID
        )

        if result != kIOReturnSuccess {
            logger.warning("IOPMAssertionDeclareUserActivity failed with error: \(result)")
            return false
        } else {
            logger.debug("Caffeinate user activity declared via assertion, ID: \(userActivityAssertionID)")
            return true
        }
    }

    /// Releases any existing user activity assertion.
    private func releaseUserActivityAssertion() {
        if userActivityAssertionID != 0 {
            IOPMAssertionRelease(userActivityAssertionID)
            userActivityAssertionID = 0
        }
    }
}

