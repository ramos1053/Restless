import Foundation

// MARK: - Day of Week

/// Represents days of the week for scheduling.
struct DayOfWeek: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let sunday    = DayOfWeek(rawValue: 1 << 0)
    static let monday    = DayOfWeek(rawValue: 1 << 1)
    static let tuesday   = DayOfWeek(rawValue: 1 << 2)
    static let wednesday = DayOfWeek(rawValue: 1 << 3)
    static let thursday  = DayOfWeek(rawValue: 1 << 4)
    static let friday    = DayOfWeek(rawValue: 1 << 5)
    static let saturday  = DayOfWeek(rawValue: 1 << 6)

    static let weekdays: DayOfWeek = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let weekends: DayOfWeek = [.saturday, .sunday]
    static let allDays: DayOfWeek = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]

    /// All individual days in order (Sunday = 1 in Calendar).
    static let orderedDays: [(day: DayOfWeek, name: String, shortName: String)] = [
        (.sunday, "Sunday", "Sun"),
        (.monday, "Monday", "Mon"),
        (.tuesday, "Tuesday", "Tue"),
        (.wednesday, "Wednesday", "Wed"),
        (.thursday, "Thursday", "Thu"),
        (.friday, "Friday", "Fri"),
        (.saturday, "Saturday", "Sat")
    ]

    /// Converts a Calendar weekday (1 = Sunday) to DayOfWeek.
    static func from(calendarWeekday: Int) -> DayOfWeek {
        guard calendarWeekday >= 1 && calendarWeekday <= 7 else { return [] }
        return DayOfWeek(rawValue: 1 << (calendarWeekday - 1))
    }

    /// Returns a human-readable description of the selected days.
    var displayString: String {
        if self == .allDays {
            return "Every day"
        } else if self == .weekdays {
            return "Weekdays"
        } else if self == .weekends {
            return "Weekends"
        }

        let selectedDays = DayOfWeek.orderedDays
            .filter { self.contains($0.day) }
            .map { $0.shortName }

        return selectedDays.joined(separator: ", ")
    }

    /// Checks if the given date falls on a selected day.
    func contains(date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        let dayOfWeek = DayOfWeek.from(calendarWeekday: weekday)
        return self.contains(dayOfWeek)
    }
}

// MARK: - Time of Day

/// Represents a time of day (hour and minute only).
struct TimeOfDay: Codable, Equatable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = max(0, min(23, hour))
        self.minute = max(0, min(59, minute))
    }

    /// Creates a TimeOfDay from the current time.
    static var now: TimeOfDay {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    /// Total minutes from midnight.
    var totalMinutes: Int {
        return hour * 60 + minute
    }

    /// Returns a Date with this time on the given date.
    func date(on referenceDate: Date = Date()) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return Calendar.current.date(from: components) ?? referenceDate
    }

    /// Display string in HH:MM format.
    var displayString: String {
        return String(format: "%02d:%02d", hour, minute)
    }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        return lhs.totalMinutes < rhs.totalMinutes
    }
}

// MARK: - Schedule

/// Represents a scheduled time window for keep-awake and/or caffeinate activation.
struct Schedule: Identifiable, Codable, Equatable {
    /// Unique identifier for this schedule.
    var id: UUID = UUID()

    /// User-provided name for this schedule.
    var name: String

    /// Whether this schedule is currently enabled.
    var isEnabled: Bool = true

    /// Days of the week when this schedule is active.
    var days: DayOfWeek = .weekdays

    /// Start time for the schedule.
    var startTime: TimeOfDay

    /// End time for the schedule.
    var endTime: TimeOfDay

    /// Whether to enable keep-awake during this schedule.
    var enableKeepAwake: Bool = true

    /// Scope for keep-awake (if enabled).
    var keepAwakeScope: KeepAwakeScope = .systemAndDisplay

    /// Whether to enable caffeinate app during this schedule.
    var enableCaffeinate: Bool = false

    // MARK: - Convenience Methods

    /// Checks if the schedule is currently active (right now).
    var isCurrentlyActive: Bool {
        return isActive(at: Date())
    }

    /// Checks if the schedule is active at the given date/time.
    func isActive(at date: Date) -> Bool {
        guard isEnabled else { return false }

        // Check if it's on an enabled day
        guard days.contains(date: date) else { return false }

        // Check if current time is within the time window
        let currentTime = TimeOfDay.now
        return isTimeInWindow(currentTime)
    }

    /// Checks if a given time is within the start/end window.
    /// Handles overnight schedules (e.g., 22:00 - 06:00).
    func isTimeInWindow(_ time: TimeOfDay) -> Bool {
        if startTime <= endTime {
            // Normal schedule (e.g., 09:00 - 17:00)
            return time >= startTime && time < endTime
        } else {
            // Overnight schedule (e.g., 22:00 - 06:00)
            return time >= startTime || time < endTime
        }
    }

    /// Returns the next activation date/time, or nil if schedule is disabled.
    func nextActivation(from date: Date = Date()) -> Date? {
        guard isEnabled else { return nil }

        let calendar = Calendar.current

        // Check today first
        for dayOffset in 0..<7 {
            guard let checkDate = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }

            if days.contains(date: checkDate) {
                let startDate = startTime.date(on: checkDate)

                // If it's today, only return if start time is in the future
                if dayOffset == 0 {
                    if startDate > date {
                        return startDate
                    }
                    // Check if we're currently in the window
                    if isActive(at: date) {
                        return date // Already active
                    }
                } else {
                    return startDate
                }
            }
        }

        return nil
    }

    /// Returns the next deactivation date/time when currently active.
    func nextDeactivation(from date: Date = Date()) -> Date? {
        guard isEnabled && isActive(at: date) else { return nil }

        let endDate = endTime.date(on: date)

        // If end time is "before" start time, it's overnight - add a day
        if endTime < startTime {
            return Calendar.current.date(byAdding: .day, value: 1, to: endDate)
        }

        return endDate
    }

    // MARK: - Factory Methods

    /// Creates a default weekday work hours schedule.
    static func defaultWorkHours() -> Schedule {
        Schedule(
            name: "Work Hours",
            days: .weekdays,
            startTime: TimeOfDay(hour: 9, minute: 0),
            endTime: TimeOfDay(hour: 17, minute: 0),
            enableKeepAwake: true,
            enableCaffeinate: false
        )
    }
}
