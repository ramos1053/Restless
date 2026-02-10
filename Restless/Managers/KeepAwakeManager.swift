import Foundation
import AppKit
import IOKit
import IOKit.pwr_mgt

// MARK: - Keep Awake Session

/// Represents an active keep-awake session.
struct KeepAwakeSession {
    let id: UUID
    let startTime: Date
    let mode: KeepAwakeMode
    let scope: KeepAwakeScope
    let endTime: Date?
    let duration: TimeInterval?
    let scheduleName: String?

    /// Returns remaining time if session has a defined end.
    var remainingTime: TimeInterval? {
        guard let endTime = endTime else { return nil }
        let remaining = endTime.timeIntervalSinceNow
        return remaining > 0 ? remaining : 0
    }

    /// Returns whether this session has expired.
    var isExpired: Bool {
        guard let endTime = endTime else { return false }
        return Date() >= endTime
    }

    /// Formatted string for remaining time.
    var remainingTimeString: String? {
        guard let remaining = remainingTime else { return nil }
        if remaining <= 0 { return "Expired" }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}

// MARK: - Keep Awake Manager

/// Manages system power assertions to prevent sleep and screen lock.
///
/// Uses Apple's caffeinate command-line utility for reliable sleep prevention.
/// This is the same approach used by KeepingYouAwake and other proven apps.
///
/// Caffeinate flags:
/// - `-d`: Prevent display from sleeping
/// - `-i`: Prevent system from idle sleeping
/// - `-u`: Declare user is active (prevents screen lock, resets idle timer)
/// - `-s`: Prevent system from sleeping (AC power only)
/// - `-w PID`: Wait for process to exit
/// - `-t N`: Timeout in seconds
final class KeepAwakeManager: ObservableObject {

    // MARK: - Published State

    /// Whether a keep-awake session is currently active.
    @Published private(set) var isActive: Bool = false

    /// Current active session details.
    @Published private(set) var currentSession: KeepAwakeSession?

    /// Which prevention method is currently active.
    @Published private(set) var activeMethod: AwakeMethod = .none

    /// Health status of the current prevention method.
    @Published private(set) var methodStatus: MethodStatus = .inactive

    // MARK: - Private Properties

    /// The caffeinate task that prevents sleep.
    private var caffeinateTask: Process?

    /// Timer for periodic user activity declarations (prevents screen lock).
    private var userActivityTimer: Timer?

    /// User activity assertion ID for IOPMAssertionDeclareUserActivity.
    private var userActivityAssertionID: IOPMAssertionID = IOPMAssertionID(0)

    /// IOKit sleep assertion ID (fallback when caffeinate fails).
    private var sleepAssertionID: IOPMAssertionID = 0

    /// Timer for checking session expiration.
    private var expirationTimer: Timer?

    /// Timer interval for checking expiration.
    private let expirationCheckInterval: TimeInterval = 1.0

    /// Interval for declaring user activity (prevents screen lock).
    private let userActivityInterval: TimeInterval = 25.0

    /// Duration for the user activity caffeinate process (slightly longer than interval for overlap).
    private let userActivityDuration: Int = 30

    /// The caffeinate task that prevents screen lock via user activity.
    private var userActivityCaffeinateTask: Process?

    /// Shared logger.
    private let logger = AppLogger.shared

    /// Computed convenience for health checks.
    var isHealthy: Bool { methodStatus.isHealthy }

    // MARK: - Singleton

    static let shared = KeepAwakeManager()

    private init() {
        // Terminate caffeinate when app quits
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc private func applicationWillTerminate() {
        stop()
    }

    // MARK: - Public Methods

    /// Starts an indefinite keep-awake session.
    func startIndefinite(scope: KeepAwakeScope, scheduleName: String? = nil) {
        let session = KeepAwakeSession(
            id: UUID(),
            startTime: Date(),
            mode: .indefinite,
            scope: scope,
            endTime: nil,
            duration: nil,
            scheduleName: scheduleName
        )
        startSession(session)
    }

    /// Starts a keep-awake session for a specified duration.
    func startForDuration(_ duration: TimeInterval, scope: KeepAwakeScope, scheduleName: String? = nil) {
        let session = KeepAwakeSession(
            id: UUID(),
            startTime: Date(),
            mode: .duration,
            scope: scope,
            endTime: Date().addingTimeInterval(duration),
            duration: duration,
            scheduleName: scheduleName
        )
        startSession(session)
    }

    /// Starts a keep-awake session until a specified time.
    func startUntilTime(_ endTime: Date, scope: KeepAwakeScope, scheduleName: String? = nil) {
        // If end time is in the past, don't start
        guard endTime > Date() else {
            logger.warning("Cannot start keep-awake session: end time is in the past")
            return
        }

        let session = KeepAwakeSession(
            id: UUID(),
            startTime: Date(),
            mode: .untilTime,
            scope: scope,
            endTime: endTime,
            duration: endTime.timeIntervalSinceNow,
            scheduleName: scheduleName
        )
        startSession(session)
    }

    /// Stops the current keep-awake session.
    func stop() {
        guard isActive else { return }

        terminateCaffeinateTask()
        releaseIOKitSleepAssertion()
        stopUserActivityTimer()
        stopExpirationTimer()

        let sessionName = currentSession?.scheduleName ?? "Manual"
        currentSession = nil
        isActive = false
        activeMethod = .none
        methodStatus = .inactive

        logger.info("Keep-awake session stopped: \(sessionName)")

        NotificationCenter.default.post(name: .keepAwakeStateDidChange, object: nil)
        NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
    }

    /// Toggles keep-awake on/off with default settings.
    func toggle(scope: KeepAwakeScope = .systemAndDisplay) {
        if isActive {
            stop()
        } else {
            startIndefinite(scope: scope)
        }
    }

    // MARK: - Private Methods

    private func startSession(_ session: KeepAwakeSession) {
        // Stop any existing session first
        if isActive {
            stop()
        }

        // Try primary method: caffeinate process
        var success = spawnCaffeinateTask(scope: session.scope, timeout: session.duration)

        if success {
            activeMethod = .caffeinate
            methodStatus = .healthy(method: .caffeinate)
            logger.info("Keep-awake using primary method: caffeinate")
        } else {
            // Fallback: IOKit power assertion
            logger.warning("caffeinate failed, falling back to IOKit assertion")
            success = createIOKitSleepAssertion(scope: session.scope)

            if success {
                activeMethod = .iokitAssertion
                methodStatus = .degraded(method: .iokitAssertion, reason: "caffeinate unavailable")
                logger.warning("Keep-awake using fallback: IOKit assertion")

            } else {
                activeMethod = .none
                methodStatus = .failed(reason: "All sleep prevention methods failed")
                logger.error("All keep-awake methods failed")

                NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
                return
            }
        }

        currentSession = session
        isActive = true

        // Start user activity timer to prevent screen lock
        startUserActivityTimer()

        // Start expiration timer if session has an end time
        if session.endTime != nil {
            startExpirationTimer()
        }

        NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)

        let modeDesc: String
        switch session.mode {
        case .indefinite:
            modeDesc = "indefinitely"
        case .duration:
            if let remaining = session.remainingTimeString {
                modeDesc = "for \(remaining)"
            } else {
                modeDesc = "for duration"
            }
        case .untilTime:
            if let endTime = session.endTime {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                modeDesc = "until \(formatter.string(from: endTime))"
            } else {
                modeDesc = "until time"
            }
        }

        let scheduleInfo = session.scheduleName.map { " (Schedule: \($0))" } ?? ""
        logger.info("Keep-awake session started: \(session.scope.displayName) \(modeDesc)\(scheduleInfo)")

        NotificationCenter.default.post(name: .keepAwakeStateDidChange, object: nil)
    }

    // MARK: - Caffeinate Task Management

    // MARK: - Security Constants

    /// Maximum allowed timeout in seconds (24 hours)
    private static let maxTimeoutSeconds: TimeInterval = 86400

    /// Minimum allowed timeout in seconds (1 minute)
    private static let minTimeoutSeconds: TimeInterval = 60

    /// Spawns a caffeinate task with the appropriate flags.
    private func spawnCaffeinateTask(scope: KeepAwakeScope, timeout: TimeInterval?) -> Bool {
        var arguments: [String] = []

        // Build arguments based on scope
        switch scope {
        case .systemOnly:
            // -i: Prevent system from idle sleeping (allows display to sleep)
            arguments.append("-i")
        case .systemAndDisplay:
            // -d: Prevent display from sleeping
            // -i: Prevent system from idle sleeping
            arguments.append("-di")
        }

        // Add timeout if specified with security bounds validation
        if let timeout = timeout, timeout > 0 {
            // Security: Validate timeout is within acceptable bounds
            let sanitizedTimeout = max(Self.minTimeoutSeconds, min(Self.maxTimeoutSeconds, timeout))

            // Security: Ensure we get a valid integer to prevent format string issues
            guard sanitizedTimeout.isFinite, !sanitizedTimeout.isNaN else {
                logger.error("Invalid timeout value rejected")
                return false
            }

            let timeoutInt = Int(sanitizedTimeout)
            arguments.append("-t")
            arguments.append(String(timeoutInt))
        }

        // Tie caffeinate to this process - when our app exits, caffeinate exits too
        arguments.append("-w")
        arguments.append(String(ProcessInfo.processInfo.processIdentifier))

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        task.arguments = arguments

        // Set up termination handler
        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.handleCaffeinateTermination(exitCode: process.terminationStatus)
            }
        }

        do {
            try task.run()
            caffeinateTask = task
            logger.info("Caffeinate started with arguments: \(arguments.joined(separator: " "))")
            return true
        } catch {
            logger.error("Failed to launch caffeinate: \(error.localizedDescription)")
            return false
        }
    }

    /// Terminates the caffeinate task.
    private func terminateCaffeinateTask() {
        guard let task = caffeinateTask else { return }

        // Clear termination handler to avoid callback during manual termination
        task.terminationHandler = nil

        if task.isRunning {
            task.terminate()
            logger.debug("Caffeinate task terminated")
        }

        caffeinateTask = nil
    }

    /// Handles caffeinate task termination.
    private func handleCaffeinateTermination(exitCode: Int32) {
        guard isActive else { return }

        caffeinateTask = nil

        if exitCode == 0 {
            // Normal timeout or natural exit
            logger.info("Caffeinate task completed (timeout or natural exit)")
            stop()
        } else {
            // Unexpected termination - attempt IOKit fallback
            logger.warning("Caffeinate died unexpectedly (exit \(exitCode)), attempting IOKit fallback")

            if createIOKitSleepAssertion(scope: currentSession?.scope ?? .systemAndDisplay) {
                activeMethod = .iokitAssertion
                methodStatus = .degraded(method: .iokitAssertion, reason: "caffeinate process died")
                logger.warning("Keep-awake recovered using IOKit assertion fallback")

                NotificationCenter.default.post(name: .keepAwakeStateDidChange, object: nil)
                NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
            } else {
                logger.error("IOKit fallback also failed after caffeinate death")
                methodStatus = .failed(reason: "caffeinate died and IOKit fallback failed")

                NotificationCenter.default.post(name: .methodStatusDidChange, object: nil)
                stop()
            }
        }
    }

    // MARK: - User Activity (Prevents Screen Lock)

    /// Starts periodic user activity declarations to prevent screen lock.
    private func startUserActivityTimer() {
        stopUserActivityTimer()

        // Declare user activity immediately
        declareUserActivity()

        // Then periodically
        userActivityTimer = Timer.scheduledTimer(withTimeInterval: userActivityInterval, repeats: true) { [weak self] _ in
            self?.declareUserActivity()
        }

        // Add to common run loop modes for reliability
        if let timer = userActivityTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Stops the user activity timer.
    private func stopUserActivityTimer() {
        userActivityTimer?.invalidate()
        userActivityTimer = nil

        // Terminate user activity caffeinate task
        if let task = userActivityCaffeinateTask, task.isRunning {
            task.terminate()
        }
        userActivityCaffeinateTask = nil

        // Release any existing user activity assertion
        if userActivityAssertionID != 0 {
            IOPMAssertionRelease(userActivityAssertionID)
            userActivityAssertionID = 0
        }
    }

    /// Declares that the user is active, which:
    /// - Turns on the display if it's off
    /// - Resets the idle timer
    /// - Prevents screen lock from activating
    ///
    /// Uses caffeinate -u which is the most reliable method for preventing screen lock.
    private func declareUserActivity() {
        // Terminate any existing user activity caffeinate task
        if let existingTask = userActivityCaffeinateTask, existingTask.isRunning {
            existingTask.terminate()
        }

        // Spawn caffeinate -u -t <duration> to continuously declare user activity
        // This is more reliable than IOPMAssertionDeclareUserActivity
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        task.arguments = ["-u", "-t", String(userActivityDuration)]

        do {
            try task.run()
            userActivityCaffeinateTask = task
            logger.debug("User activity caffeinate started for \(userActivityDuration) seconds")
        } catch {
            logger.warning("Failed to spawn user activity caffeinate: \(error.localizedDescription)")

            // Fallback to IOPMAssertionDeclareUserActivity
            declareUserActivityViaAssertion()
        }
    }

    /// Fallback method using IOPMAssertionDeclareUserActivity.
    private func declareUserActivityViaAssertion() {
        // Note: Don't release the old assertion - let the system manage it
        // IOPMAssertionDeclareUserActivity assertions are designed to auto-release

        let assertionName = "Restless User Activity" as CFString

        let result = IOPMAssertionDeclareUserActivity(
            assertionName,
            kIOPMUserActiveLocal,
            &userActivityAssertionID
        )

        if result != kIOReturnSuccess {
            logger.warning("IOPMAssertionDeclareUserActivity failed with error: \(result)")
        } else {
            logger.debug("User activity declared via assertion, ID: \(userActivityAssertionID)")
        }
    }

    // MARK: - Expiration Timer

    /// Starts the timer for checking session expiration.
    private func startExpirationTimer() {
        stopExpirationTimer()

        expirationTimer = Timer.scheduledTimer(withTimeInterval: expirationCheckInterval, repeats: true) { [weak self] _ in
            self?.checkExpiration()
        }
    }

    /// Stops the expiration timer.
    private func stopExpirationTimer() {
        expirationTimer?.invalidate()
        expirationTimer = nil
    }

    /// Checks if the current session has expired.
    private func checkExpiration() {
        guard let session = currentSession, session.isExpired else { return }
        logger.info("Keep-awake session expired")
        stop()
    }

    // MARK: - Status Check

    /// Returns whether caffeinate is actually running.
    var isCaffeinateRunning: Bool {
        return caffeinateTask?.isRunning ?? false
    }

    // MARK: - Deinit

    deinit {
        stop()
    }
}

// MARK: - IOKit Sleep Assertion Fallback

extension KeepAwakeManager {

    /// Creates an IOKit sleep assertion as fallback when caffeinate is unavailable.
    private func createIOKitSleepAssertion(scope: KeepAwakeScope) -> Bool {
        // Release any existing assertion first
        releaseIOKitSleepAssertion()

        let assertionType: String
        switch scope {
        case .systemOnly:
            assertionType = kIOPMAssertionTypePreventSystemSleep as String
        case .systemAndDisplay:
            assertionType = kIOPMAssertionTypePreventUserIdleDisplaySleep as String
        }

        let result = IOPMAssertionCreateWithName(
            assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Restless Keep-Awake" as CFString,
            &sleepAssertionID
        )

        if result == kIOReturnSuccess {
            logger.info("IOKit sleep assertion created (ID: \(sleepAssertionID))")
            return true
        } else {
            logger.error("IOPMAssertionCreateWithName failed: \(result)")
            return false
        }
    }

    /// Releases the IOKit sleep assertion if held.
    private func releaseIOKitSleepAssertion() {
        guard sleepAssertionID != 0 else { return }
        IOPMAssertionRelease(sleepAssertionID)
        logger.debug("IOKit sleep assertion released (ID: \(sleepAssertionID))")
        sleepAssertionID = 0
    }
}
