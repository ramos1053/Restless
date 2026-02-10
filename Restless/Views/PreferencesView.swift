import SwiftUI
import AppKit

// MARK: - Preferences Tab

/// Available tabs in the preferences window.
enum PreferencesTab: String, CaseIterable {
    case general = "General"
    case caffeinateApp = "Caffeinate App"
    case scheduling = "Scheduling"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .caffeinateApp: return "cup.and.saucer.fill"
        case .scheduling: return "calendar.badge.clock"
        }
    }
}

// MARK: - Preferences View

/// Main preferences window view.
struct PreferencesView: View {
    @ObservedObject var settings: AppSettings
    @State private var selectedTab: PreferencesTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView(settings: settings)
                .tabItem {
                    Label(PreferencesTab.general.rawValue, systemImage: PreferencesTab.general.icon)
                }
                .tag(PreferencesTab.general)

            CaffeinateAppPreferencesView(settings: settings)
                .tabItem {
                    Label(PreferencesTab.caffeinateApp.rawValue, systemImage: PreferencesTab.caffeinateApp.icon)
                }
                .tag(PreferencesTab.caffeinateApp)

            SchedulePreferencesView(settings: settings)
                .tabItem {
                    Label(PreferencesTab.scheduling.rawValue, systemImage: PreferencesTab.scheduling.icon)
                }
                .tag(PreferencesTab.scheduling)
        }
        .frame(minWidth: 550, minHeight: 400)
        .padding()
    }
}

// MARK: - Preferences Window Controller

/// Controller for managing the preferences window.
final class PreferencesWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    /// Shows the preferences window.
    func show() {
        if let existingWindow = window {
            // Bring existing window to front
            existingWindow.level = .floating
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Reset to normal level after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                existingWindow.level = .normal
            }
            return
        }

        let preferencesView = PreferencesView(settings: settings)
        let hostingController = NSHostingController(rootView: preferencesView)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Restless Preferences"
        newWindow.styleMask = [.titled, .closable, .miniaturizable]
        newWindow.center()
        newWindow.setFrameAutosaveName("PreferencesWindow")
        newWindow.delegate = self

        // Ensure window comes to front
        newWindow.level = .floating
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Reset to normal level after a brief delay so it behaves normally
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            newWindow.level = .normal
        }

        window = newWindow
    }

    /// Closes the preferences window.
    func close() {
        window?.close()
        window = nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

// MARK: - Section Header

/// Reusable section header component.
struct SectionHeader: View {
    let title: String
    let icon: String?

    init(_ title: String, icon: String? = nil) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
            }
            Text(title)
                .font(.headline)
        }
    }
}

// MARK: - Preference Row

/// Reusable row component for preferences.
struct PreferenceRow<Content: View>: View {
    let label: String
    let description: String?
    let content: Content

    init(_ label: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.description = description
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 150, alignment: .leading)

            Spacer()

            content
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        PreferencesView(settings: AppSettings())
    }
}
#endif
