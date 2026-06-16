import Foundation
import AppKit
import CoreGraphics
import IOKit
import IOKit.pwr_mgt

// MARK: - Caffeinate App Manager

/// Manages keeping background apps active by sending periodic invisible events to their processes.
/// This allows apps to show the user as "Active" without moving the cursor.
/// Supports up to 10 simultaneous targets.
final class CaffeinateAppManager: ObservableObject {

    // MARK: - Singleton

    static let shared = CaffeinateAppManager()

    // MARK: - Internal Session

    /// Tracks state for a single caffeinated app.
    private struct CaffeinateSession {
        let bundleID: String
        let appName: String
        var pid: Int32
        var eventCount: Int = 0
        var lastEventTime: Date?
    }

    // MARK: - Published State

    /// Whether any caffeinate session is currently running.
    @Published private(set) var isRunning: Bool = false

    /// Names of all apps being caffeinated.
    @Published private(set) var targetAppNames: [String] = []

    /// Total number of activity events sent across all sessions.
    @Published private(set) var totalEventCount: Int = 0

    /// Last time an event was sent (most recent across all sessions).
    @Published private(set) var lastEventTime: Date?

    /// Which prevention method is currently active.
    @Published private(set) var activeMethod: AwakeMethod = .none

    /// Health status of the current prevention method.
    @Published private(set) var methodStatus: MethodStatus = .inactive

    /// Whether mouse events are working (requires accessibility).
    @Published private(set) var mouseEventsWorking: Bool = false

    /// Number of active target sessions.
    var activeTargetCount: Int { sessions.count }

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
    private var sessions: [String: CaffeinateSession] = [:] // keyed by bundleID
    private var intervalSeconds: Int = 30
    private let logger = AppLogger.shared

    /// User activity assertion ID for IOPMAssertionDeclareUserActivity.
    private var userActivityAssertionID: IOPMAssertionID = IOPMAssertionID(0)

    /// The most recent `caffeinate -u` task. Retained so it can be terminated
    /// and reaped, preventing accumulation of orphaned/zombie subprocesses.
    private var userActivityCaffeinateTask: Process?

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

        // Security: Block system processes and critical apps. Covers both the
        // legacy (systempreferences) and modern (systemsettings) Settings bundle
        // IDs plus security-sensitive surfaces.
        let blockedPrefixes = [
            "com.apple.finder",
            "com.apple.loginwindow",
            "com.apple.SecurityAgent",
            "com.apple.securityagent",
            "com.apple.systempreferences",
            "com.apple.systemsettings",
            "com.apple.preferences",
            "com.apple.keychainaccess",
            "com.apple.Terminal",
            "com.apple.dt.Xcode"
        ]

        // Security: Never target ourselves.
        if bundleID == Bundle.main.bundleIdentifier {
            logger.warning("Security: Blocked caffeinate target (self): \(bundleID)")
            return false
        }

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

    /// Verifies a session's target process is still valid and hasn't been replaced.
    /// Security: Prevents PID reuse attacks.
    private func verifySessionProcess(_ session: CaffeinateSession) -> NSRunningApplication? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == session.bundleID }) else {
            return nil
        }

        // Security: Verify PID hasn't changed (process was replaced)
        guard app.processIdentifier == session.pid else {
            logger.warning("Security: Target process PID changed for \(session.appName), removing session")
            return nil
        }

        return app
    }

    // MARK: - Public Methods

    /// Starts caffeinating a single target app. Adds to existing sessions.
    func startTarget(bundleID: String, appName: String, intervalSeconds: Int = 30) {
        // Security: Validate bundle ID
        guard !bundleID.isEmpty else {
            logger.warning("Cannot start caffeinate: no bundle ID specified")
            return
        }

        // Don't add duplicates
        guard sessions[bundleID] == nil else {
            logger.info("Already caffeinating \(appName)")
            return
        }

        // Security: Validate the target app is allowed
        guard isValidTargetApp(bundleID: bundleID) else {
            logger.warning("Cannot start caffeinate: app '\(bundleID)' is not a valid target")
            return
        }

        // Verify the app is running
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            logger.warning("Cannot start caffeinate: app '\(appName)' is not running")
            return
        }

        // Security: Sanitize interval
        let sanitizedInterval = sanitizeInterval(intervalSeconds)
        self.intervalSeconds = sanitizedInterval

        let session = CaffeinateSession(
            bundleID: bundleID,
            appName: app.localizedName ?? appName,
            pid: app.processIdentifier
        )
        sessions[bundleID] = session

        updatePublishedState()

        // Start timer if this is the first session
        if sessions.count == 1 {
            let hasAccessibility = TargetingManager.shared.hasAccessibilityPermissions
            self.mouseEventsWorking = hasAccessibility
            self.activeMethod = .caffeinate

            if hasAccessibility {
                self.methodStatus = .healthy(method: .caffeinate)
            } else {
                self.methodStatus = .degraded(method: .caffeinate, reason: "No accessibility permission")
                logger.warning("Caffeinate started without accessibility - mouse events disabled")
            }

            startTimer()
        }

        // Send an initial event to this target
        sendActivityEventForSession(session, hasAccessibility: TargetingManager.shared.hasAccessibilityPermissions)

        logger.info("Started caffeinating \(session.appName) (total targets: \(sessions.count))")

        NotificationCenter.default.post(name: .caffeinateStateDidChange, object: nil)
        NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
    }

    /// Stops caffeinating a single target app.
    func stopTarget(bundleID: String) {
        guard let session = sessions.removeValue(forKey: bundleID) else { return }

        logger.info("Stopped caffeinating \(session.appName) after \(session.eventCount) events (remaining targets: \(sessions.count))")

        if sessions.isEmpty {
            stopInternal()
        } else {
            updatePublishedState()
        }

        NotificationCenter.default.post(name: .caffeinateStateDidChange, object: nil)
        NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
    }

    /// Starts caffeinating all provided targets.
    func startAll(targets: [CaffeinateTarget], intervalSeconds: Int = 30) {
        for target in targets {
            startTarget(bundleID: target.bundleID, appName: target.appName, intervalSeconds: intervalSeconds)
        }
    }

    /// Stops all caffeinate sessions.
    func stopAll() {
        let totalEvents = sessions.values.reduce(0) { $0 + $1.eventCount }
        sessions.removeAll()
        stopInternal()
        logger.info("Stopped all caffeinate sessions after \(totalEvents) total events")

        NotificationCenter.default.post(name: .caffeinateStateDidChange, object: nil)
        NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
    }

    /// Stops caffeinating (alias for stopAll).
    func stop() {
        stopAll()
    }

    /// Updates the interval while running.
    func updateInterval(_ newInterval: Int) {
        guard isRunning else { return }
        // Security: Sanitize interval
        self.intervalSeconds = sanitizeInterval(newInterval)
        startTimer() // Restart timer with new interval
    }

    // MARK: - Private Methods

    /// Clears timer and resets state when no sessions remain.
    private func stopInternal() {
        timer?.invalidate()
        timer = nil

        // Terminate any outstanding user-activity caffeinate subprocess.
        if let task = userActivityCaffeinateTask, task.isRunning {
            task.terminate()
        }
        userActivityCaffeinateTask = nil

        // Release user activity assertion
        releaseUserActivityAssertion()

        activeMethod = .none
        methodStatus = .inactive
        mouseEventsWorking = false

        updatePublishedState()
    }

    /// Updates published properties from current sessions.
    private func updatePublishedState() {
        isRunning = !sessions.isEmpty
        targetAppNames = sessions.values.map { $0.appName }.sorted()
        totalEventCount = sessions.values.reduce(0) { $0 + $1.eventCount }
        lastEventTime = sessions.values.compactMap { $0.lastEventTime }.max()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(intervalSeconds), repeats: true) { [weak self] _ in
            self?.sendActivityEvents()
        }
    }

    /// Sends invisible activity events to all target processes.
    private func sendActivityEvents() {
        guard !sessions.isEmpty else { return }

        let hasAccessibility = TargetingManager.shared.hasAccessibilityPermissions

        // Update accessibility status
        if hasAccessibility && !mouseEventsWorking {
            mouseEventsWorking = true
            methodStatus = .healthy(method: .caffeinate)
            logger.info("Mouse events restored (accessibility permission granted)")
            NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
        } else if !hasAccessibility && mouseEventsWorking {
            mouseEventsWorking = false
            methodStatus = .degraded(method: .caffeinate, reason: "No accessibility permission")
            logger.warning("Accessibility permission lost - mouse events disabled, using caffeinate -u only")
            NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
        }

        // Send events to each session
        var invalidBundleIDs: [String] = []

        for (bundleID, session) in sessions {
            guard let app = verifySessionProcess(session) else {
                invalidBundleIDs.append(bundleID)
                continue
            }

            sendActivityEventForSession(session, hasAccessibility: hasAccessibility, app: app)

            // Update session state
            sessions[bundleID]?.eventCount += 1
            sessions[bundleID]?.lastEventTime = Date()
        }

        // Remove dead sessions
        for bundleID in invalidBundleIDs {
            if let session = sessions.removeValue(forKey: bundleID) {
                logger.warning("Target app '\(session.appName)' is no longer valid, removed from sessions")
            }
        }

        // If all sessions died, stop entirely
        if sessions.isEmpty {
            stopInternal()
            NotificationCenter.default.post(name: .caffeinateStateDidChange, object: nil)
            NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
            return
        }

        // Declare system-level user activity once for all sessions
        declareUserActivity()

        updatePublishedState()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .caffeinateStateDidChange, object: nil)
        }
    }

    /// Sends activity events to a single session's process.
    private func sendActivityEventForSession(_ session: CaffeinateSession, hasAccessibility: Bool, app: NSRunningApplication? = nil) {
        guard hasAccessibility else { return }

        // Security: Resolve the live running application for this bundle ID and
        // re-verify it matches the session before posting any synthetic event.
        // Never post to the cached session.pid directly: PIDs are reused by the
        // kernel, so a stale PID could target an unrelated (possibly privileged)
        // process.
        let targetApp = app ?? NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == session.bundleID })
        guard let targetApp = targetApp else { return }

        // Security: Confirm the resolved process still matches the session's
        // recorded PID. If it changed, the process was replaced (PID reuse) and
        // we must not target it.
        guard targetApp.processIdentifier == session.pid else {
            logger.warning("Security: Skipping event - PID for \(session.appName) no longer matches session")
            return
        }

        // Security: Re-validate the target is still an allowed user app and not
        // a system/privileged process that may have claimed this bundle ID.
        guard isValidTargetApp(bundleID: session.bundleID) else {
            logger.warning("Security: Skipping event - \(session.bundleID) is no longer a valid target")
            return
        }

        let pid = targetApp.processIdentifier
        let position = getTargetPosition(for: targetApp)
        sendMouseMoveToProcess(pid: pid, position: position)
        let offsetPosition = CGPoint(x: position.x + 1, y: position.y)
        sendMouseMoveToProcess(pid: pid, position: offsetPosition)
        sendMouseMoveToProcess(pid: pid, position: position)

        // Send a shift key press/release to reset idle timers in web apps
        sendKeyEventToProcess(pid: pid)
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

        // Terminate and clear any previous user-activity task so we never leak
        // overlapping subprocesses.
        if let existingTask = userActivityCaffeinateTask, existingTask.isRunning {
            existingTask.terminate()
        }
        userActivityCaffeinateTask = nil

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        task.arguments = ["-u", "-t", String(duration)]
        // Reap the process on exit so it doesn't linger as a zombie.
        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                if self?.userActivityCaffeinateTask === process {
                    self?.userActivityCaffeinateTask = nil
                }
            }
        }

        do {
            try task.run()
            userActivityCaffeinateTask = task
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
