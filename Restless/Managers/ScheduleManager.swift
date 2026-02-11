import Foundation
import Combine
import AppKit

// MARK: - Schedule Manager

/// Manages time-based scheduling for keep-awake and caffeinate activation.
///
/// Features:
/// - Evaluates schedules based on current time and day of week
/// - Handles system clock changes gracefully
/// - Responds to wake/sleep notifications
/// - Automatically activates/deactivates keep-awake and caffeinate
///
/// The manager checks schedules every minute and on significant time changes.
final class ScheduleManager: ObservableObject {

    // MARK: - Published State

    /// Whether the scheduler is currently enabled.
    @Published var isEnabled: Bool = true {
        didSet {
            if isEnabled != oldValue {
                if isEnabled {
                    startScheduler()
                } else {
                    stopScheduler()
                }
            }
        }
    }

    /// Currently active schedules.
    @Published private(set) var activeSchedules: [Schedule] = []

    /// Next upcoming schedule activation.
    @Published private(set) var nextActivation: (schedule: Schedule, date: Date)?

    // MARK: - Private Properties

    /// All configured schedules.
    private var schedules: [Schedule] = []

    /// Timer for periodic schedule evaluation.
    private var evaluationTimer: Timer?

    /// Check interval in seconds.
    private let checkIntervalSeconds: TimeInterval = 60

    /// References to managers.
    private let keepAwakeManager = KeepAwakeManager.shared
    private let caffeinateManager = CaffeinateAppManager.shared

    /// Shared logger.
    private let logger = AppLogger.shared

    /// Workspace notification observers.
    private var workspaceObservers: [NSObjectProtocol] = []

    // MARK: - Singleton

    static let shared = ScheduleManager()

    private init() {
        setupWorkspaceNotifications()
    }

    // MARK: - Public Methods

    /// Sets the schedules to manage.
    func setSchedules(_ schedules: [Schedule]) {
        self.schedules = schedules
        evaluateSchedules()
        updateNextActivation()
    }

    /// Adds a new schedule.
    func addSchedule(_ schedule: Schedule) {
        schedules.append(schedule)
        evaluateSchedules()
        updateNextActivation()
    }

    /// Removes a schedule by ID.
    func removeSchedule(id: UUID) {
        schedules.removeAll { $0.id == id }
        evaluateSchedules()
        updateNextActivation()
    }

    /// Updates an existing schedule.
    func updateSchedule(_ schedule: Schedule) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
            evaluateSchedules()
            updateNextActivation()
        }
    }

    /// Manually triggers schedule evaluation.
    func evaluateNow() {
        evaluateSchedules()
        updateNextActivation()
    }

    /// Starts the scheduler.
    func startScheduler() {
        guard evaluationTimer == nil else { return }

        // Initial evaluation
        evaluateSchedules()
        updateNextActivation()

        // Start periodic timer
        evaluationTimer = Timer.scheduledTimer(
            withTimeInterval: checkIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            self?.evaluateSchedules()
            self?.updateNextActivation()
        }

        logger.info("Scheduler started")
    }

    /// Stops the scheduler.
    func stopScheduler() {
        evaluationTimer?.invalidate()
        evaluationTimer = nil

        // Deactivate any active schedules
        deactivateAllSchedules()

        logger.info("Scheduler stopped")
    }

    // MARK: - Schedule Evaluation

    /// Evaluates all schedules and activates/deactivates as needed.
    private func evaluateSchedules() {
        guard isEnabled else { return }

        let now = Date()
        var newlyActiveSchedules: [Schedule] = []

        for schedule in schedules where schedule.isEnabled {
            if schedule.isActive(at: now) {
                newlyActiveSchedules.append(schedule)
            }
        }

        // Determine what changed
        let previousIDs = Set(activeSchedules.map { $0.id })
        let newIDs = Set(newlyActiveSchedules.map { $0.id })

        let schedulesToActivate = newlyActiveSchedules.filter { !previousIDs.contains($0.id) }
        let schedulesToDeactivate = activeSchedules.filter { !newIDs.contains($0.id) }

        // Deactivate schedules that are no longer active
        for schedule in schedulesToDeactivate {
            deactivateSchedule(schedule)
        }

        // Activate newly active schedules
        for schedule in schedulesToActivate {
            activateSchedule(schedule)
        }

        activeSchedules = newlyActiveSchedules
    }

    /// Activates a schedule's actions.
    private func activateSchedule(_ schedule: Schedule) {
        logger.info("Activating schedule: \(schedule.name)")

        // Start keep-awake if enabled
        if schedule.enableKeepAwake {
            // Calculate end time for the schedule
            let endDate = schedule.nextDeactivation(from: Date())
            if let endTime = endDate {
                keepAwakeManager.startUntilTime(endTime, scope: schedule.keepAwakeScope, scheduleName: schedule.name)
            } else {
                keepAwakeManager.startIndefinite(scope: schedule.keepAwakeScope, scheduleName: schedule.name)
            }
        }

        // Start caffeinate if enabled
        if schedule.enableCaffeinate {
            let settings = AppSettings.load()
            if !settings.caffeinateTargets.isEmpty {
                caffeinateManager.startAll(
                    targets: settings.caffeinateTargets,
                    intervalSeconds: settings.caffeinateAppIntervalSeconds
                )
            }
        }
    }

    /// Deactivates a schedule's actions.
    private func deactivateSchedule(_ schedule: Schedule) {
        logger.info("Deactivating schedule: \(schedule.name)")

        // Check if any other active schedule needs keep-awake
        let otherActiveSchedulesNeedKeepAwake = activeSchedules
            .filter { $0.id != schedule.id }
            .contains { $0.enableKeepAwake }

        if !otherActiveSchedulesNeedKeepAwake && schedule.enableKeepAwake {
            keepAwakeManager.stop()
        }

        // Check if any other active schedule needs caffeinate
        let otherActiveSchedulesNeedCaffeinate = activeSchedules
            .filter { $0.id != schedule.id }
            .contains { $0.enableCaffeinate }

        if !otherActiveSchedulesNeedCaffeinate && schedule.enableCaffeinate {
            caffeinateManager.stop()
        }
    }

    /// Deactivates all schedules.
    private func deactivateAllSchedules() {
        keepAwakeManager.stop()
        caffeinateManager.stop()
        activeSchedules = []
    }

    /// Updates the next activation time.
    private func updateNextActivation() {
        let now = Date()

        var earliestActivation: (schedule: Schedule, date: Date)?

        for schedule in schedules where schedule.isEnabled && !activeSchedules.contains(where: { $0.id == schedule.id }) {
            if let nextDate = schedule.nextActivation(from: now) {
                if earliestActivation == nil || nextDate < earliestActivation!.date {
                    earliestActivation = (schedule, nextDate)
                }
            }
        }

        nextActivation = earliestActivation
    }

    // MARK: - System Notifications

    /// Sets up observers for system wake/sleep notifications.
    private func setupWorkspaceNotifications() {
        let workspace = NSWorkspace.shared
        let notificationCenter = workspace.notificationCenter

        // Wake notification - re-evaluate schedules
        let wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.info("System woke - re-evaluating schedules")
            self?.evaluateSchedules()
            self?.updateNextActivation()
        }
        workspaceObservers.append(wakeObserver)

        // Sleep notification - log for debugging
        let sleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.info("System going to sleep")
        }
        workspaceObservers.append(sleepObserver)

        // Significant time change (user changed clock, DST, etc.)
        let timeChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logger.info("System clock changed - re-evaluating schedules")
            self?.evaluateSchedules()
            self?.updateNextActivation()
        }
        workspaceObservers.append(timeChangeObserver)
    }

    // MARK: - Deinit

    deinit {
        stopScheduler()

        for observer in workspaceObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

// MARK: - Schedule Status

extension ScheduleManager {

    /// Returns a status string for display.
    var statusString: String {
        if !isEnabled {
            return "Scheduling disabled"
        }

        if activeSchedules.isEmpty {
            if let next = nextActivation {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relativeTime = formatter.localizedString(for: next.date, relativeTo: Date())
                return "Next: \(next.schedule.name) \(relativeTime)"
            } else {
                return "No upcoming schedules"
            }
        }

        let names = activeSchedules.map { $0.name }.joined(separator: ", ")
        return "Active: \(names)"
    }

    /// Returns whether any schedule is currently active.
    var hasActiveSchedule: Bool {
        return !activeSchedules.isEmpty
    }
}
