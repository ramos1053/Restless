import Foundation
import SwiftUI
import AppKit

// MARK: - Color Extensions

extension Color {
    /// App accent color.
    static let appAccent = Color.blue

    /// Status colors.
    static let statusActive = Color.green
    static let statusInactive = Color.gray
    static let statusWarning = Color.orange
    static let statusError = Color.red
}

// MARK: - Date Extensions

extension Date {
    /// Returns a string representation for display.
    var displayString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    /// Returns a relative time string (e.g., "in 5 minutes").
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Returns time-only string.
    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    /// Formats the interval as a human-readable duration.
    var durationString: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    /// Creates a TimeInterval from minutes.
    static func minutes(_ count: Int) -> TimeInterval {
        return TimeInterval(count * 60)
    }

    /// Creates a TimeInterval from hours.
    static func hours(_ count: Int) -> TimeInterval {
        return TimeInterval(count * 3600)
    }
}

// MARK: - String Extensions

extension String {
    /// Truncates the string to the specified length with an ellipsis.
    func truncated(to length: Int, trailing: String = "...") -> String {
        if self.count <= length {
            return self
        }
        return String(self.prefix(length - trailing.count)) + trailing
    }
}

// MARK: - CGRect Extensions

extension CGRect {
    /// Returns the center point of the rectangle.
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }

    /// Returns a point at the specified relative position (0-1 for each axis).
    func point(atRelativeX rx: CGFloat, relativeY ry: CGFloat) -> CGPoint {
        return CGPoint(
            x: origin.x + width * rx,
            y: origin.y + height * ry
        )
    }
}

// MARK: - View Extensions

extension View {
    /// Applies a card-like background style.
    func cardStyle() -> some View {
        self
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
    }

    /// Applies a section header style.
    func sectionHeader() -> some View {
        self
            .font(.headline)
            .foregroundColor(.secondary)
    }
}

// MARK: - Binding Extensions

extension Binding where Value == Int {
    /// Creates a Binding<Double> from a Binding<Int> for use with Slider.
    var doubleBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(self.wrappedValue) },
            set: { self.wrappedValue = Int($0) }
        )
    }
}

// MARK: - UserDefaults Extensions

extension UserDefaults {
    /// Keys used by the app.
    enum Keys {
        static let settings = "com.restless.settings"
        static let lastSelectedTargetID = "com.restless.lastSelectedTargetID"
    }

    /// Last selected target ID.
    var lastSelectedTargetID: String? {
        get { string(forKey: Keys.lastSelectedTargetID) }
        set { set(newValue, forKey: Keys.lastSelectedTargetID) }
    }
}

// MARK: - NSApplication Extensions

extension NSApplication {
    /// Restarts the application.
    func restart() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        self.terminate(nil)
    }
}

// MARK: - FileManager Extensions

extension FileManager {
    /// Returns the app's support directory, creating it if needed.
    var appSupportDirectory: URL? {
        guard let appSupport = urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let appDirectory = appSupport.appendingPathComponent("Restless")

        if !fileExists(atPath: appDirectory.path) {
            try? createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        return appDirectory
    }

    /// Returns the logs directory.
    var logsDirectory: URL? {
        guard let appSupport = appSupportDirectory else { return nil }
        let logsDir = appSupport.appendingPathComponent("Logs")

        if !fileExists(atPath: logsDir.path) {
            try? createDirectory(at: logsDir, withIntermediateDirectories: true)
        }

        return logsDir
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when settings have been updated.
    static let settingsDidChange = Notification.Name("com.restless.settingsDidChange")

    /// Posted when keep-awake state changes.
    static let keepAwakeStateDidChange = Notification.Name("com.restless.keepAwakeStateDidChange")

    /// Posted when a schedule activates or deactivates.
    static let scheduleStateDidChange = Notification.Name("com.restless.scheduleStateDidChange")

    /// Posted when a manager's method status changes (failover, degradation, recovery).
    static let methodStatusDidChange = Notification.Name("com.restless.methodStatusDidChange")

    /// Posted when the caffeinate app state changes (started, stopped, event sent).
    static let caffeinateStateDidChange = Notification.Name("caffeinateStateDidChange")

    /// Posted when accessibility permission status changes (granted or revoked).
    static let accessibilityPermissionChanged = Notification.Name("accessibilityPermissionChanged")
}

