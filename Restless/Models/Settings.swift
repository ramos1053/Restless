import Foundation

// MARK: - Keep Awake Mode

/// Defines how long a keep-awake session should last.
enum KeepAwakeMode: String, Codable, CaseIterable {
    case indefinite = "indefinite"
    case duration = "duration"
    case untilTime = "untilTime"

    var displayName: String {
        switch self {
        case .indefinite: return "Indefinitely"
        case .duration: return "For Duration"
        case .untilTime: return "Until Time"
        }
    }
}

// MARK: - Keep Awake Scope

/// Defines what should be kept awake.
enum KeepAwakeScope: String, Codable, CaseIterable {
    case systemOnly = "systemOnly"         // Prevent system sleep, allow display sleep
    case systemAndDisplay = "systemAndDisplay"  // Prevent both system and display sleep

    var displayName: String {
        switch self {
        case .systemOnly: return "System Only (Display May Sleep)"
        case .systemAndDisplay: return "System & Display"
        }
    }
}

// MARK: - Logging Level

/// Verbosity level for logging.
enum LoggingLevel: String, Codable, CaseIterable {
    case minimal = "minimal"
    case basic = "basic"
    case verbose = "verbose"

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .basic: return "Basic"
        case .verbose: return "Verbose"
        }
    }
}

// MARK: - App Settings

/// Main settings model for the application.
/// All settings are persisted to UserDefaults.
/// Named AppSettings to avoid conflict with SwiftUI.Settings scene.
final class AppSettings: ObservableObject, Codable {

    // MARK: - General Settings

    /// Whether to launch the app at login.
    @Published var launchAtLogin: Bool = false

    /// Default keep-awake mode when starting a session.
    @Published var defaultKeepAwakeMode: KeepAwakeMode = .indefinite

    /// Default duration in minutes for duration-based sessions.
    /// Security: Bounded to prevent excessive values (1-1440 minutes = 1 min to 24 hours)
    @Published var defaultDurationMinutes: Int = 60 {
        didSet {
            let clamped = max(1, min(1440, defaultDurationMinutes))
            if clamped != defaultDurationMinutes {
                defaultDurationMinutes = clamped
            }
        }
    }

    /// Default scope for keep-awake sessions.
    @Published var defaultKeepAwakeScope: KeepAwakeScope = .systemAndDisplay

    // MARK: - Caffeinate App Settings

    /// Whether caffeinate app feature is enabled.
    @Published var caffeinateAppEnabled: Bool = false

    /// Bundle ID of the app to keep active in background.
    @Published var caffeinateAppBundleID: String? {
        didSet {
            // Security: Validate bundle ID format
            if let bundleID = caffeinateAppBundleID {
                if bundleID.isEmpty || bundleID.count > 256 {
                    caffeinateAppBundleID = nil
                }
            }
        }
    }

    /// Interval in seconds between activity events sent to the app.
    /// Security: Bounded to prevent DoS (15-600 seconds)
    @Published var caffeinateAppIntervalSeconds: Int = 30 {
        didSet {
            // Security: Enforce bounds to prevent DoS
            let clamped = max(15, min(600, caffeinateAppIntervalSeconds))
            if clamped != caffeinateAppIntervalSeconds {
                caffeinateAppIntervalSeconds = clamped
            }
        }
    }

    // MARK: - Scheduling Settings

    /// All configured schedules.
    @Published var schedules: [Schedule] = []

    /// Whether scheduling is globally enabled.
    @Published var schedulingEnabled: Bool = true

    // MARK: - Advanced Settings

    /// Logging verbosity level.
    @Published var loggingLevel: LoggingLevel = .basic

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case defaultKeepAwakeMode
        case defaultDurationMinutes
        case defaultKeepAwakeScope
        case caffeinateAppEnabled
        case caffeinateAppBundleID
        case caffeinateAppIntervalSeconds
        case schedules
        case schedulingEnabled
        case loggingLevel
    }

    init() {}

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        defaultKeepAwakeMode = try container.decodeIfPresent(KeepAwakeMode.self, forKey: .defaultKeepAwakeMode) ?? .indefinite
        defaultDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultDurationMinutes) ?? 60
        defaultKeepAwakeScope = try container.decodeIfPresent(KeepAwakeScope.self, forKey: .defaultKeepAwakeScope) ?? .systemAndDisplay
        caffeinateAppEnabled = try container.decodeIfPresent(Bool.self, forKey: .caffeinateAppEnabled) ?? false
        caffeinateAppBundleID = try container.decodeIfPresent(String.self, forKey: .caffeinateAppBundleID)
        caffeinateAppIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .caffeinateAppIntervalSeconds) ?? 30
        schedules = try container.decodeIfPresent([Schedule].self, forKey: .schedules) ?? []
        schedulingEnabled = try container.decodeIfPresent(Bool.self, forKey: .schedulingEnabled) ?? true
        loggingLevel = try container.decodeIfPresent(LoggingLevel.self, forKey: .loggingLevel) ?? .basic
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(defaultKeepAwakeMode, forKey: .defaultKeepAwakeMode)
        try container.encode(defaultDurationMinutes, forKey: .defaultDurationMinutes)
        try container.encode(defaultKeepAwakeScope, forKey: .defaultKeepAwakeScope)
        try container.encode(caffeinateAppEnabled, forKey: .caffeinateAppEnabled)
        try container.encodeIfPresent(caffeinateAppBundleID, forKey: .caffeinateAppBundleID)
        try container.encode(caffeinateAppIntervalSeconds, forKey: .caffeinateAppIntervalSeconds)
        try container.encode(schedules, forKey: .schedules)
        try container.encode(schedulingEnabled, forKey: .schedulingEnabled)
        try container.encode(loggingLevel, forKey: .loggingLevel)
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "com.restless.settings"

    /// Loads settings from UserDefaults.
    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    /// Saves settings to UserDefaults.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
    }

    /// Exports settings to a JSON file at the specified URL.
    func exportSettings(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }

    /// Imports settings from a JSON file at the specified URL.
    static func importSettings(from url: URL) throws -> AppSettings {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }
}
