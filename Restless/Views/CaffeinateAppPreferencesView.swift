import SwiftUI

// MARK: - Caffeinate App Preferences View

/// Preferences view for the Caffeinate App feature.
struct CaffeinateAppPreferencesView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var caffeinateManager = CaffeinateAppManager.shared
    @ObservedObject private var targetingManager = TargetingManager.shared

    @State private var showingAppPicker = false
    @State private var showingPermissionAlert = false

    var body: some View {
        Form {
            // MARK: - Enable Section
            Section {
                Toggle(isOn: Binding(
                    get: { settings.caffeinateAppEnabled },
                    set: { newValue in
                        if newValue && !targetingManager.hasAccessibilityPermission {
                            // Show permission alert when trying to enable without permission
                            showingPermissionAlert = true
                            // Still enable the setting so user can see the permissions section
                            settings.caffeinateAppEnabled = true
                        } else {
                            settings.caffeinateAppEnabled = newValue
                            if newValue {
                                startCaffeinate()
                            } else {
                                caffeinateManager.stop()
                            }
                        }
                        settings.save()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Caffeinate App")
                        Text("Keeps a background app active without moving your cursor")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                SectionHeader("Caffeinate App", icon: "cup.and.saucer.fill")
            }

            if settings.caffeinateAppEnabled {
                // MARK: - Permissions
                Section {
                    HStack {
                        Circle()
                            .fill(targetingManager.hasAccessibilityPermission ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text("Accessibility Permission")
                        Spacer()
                        if targetingManager.hasAccessibilityPermission {
                            Text("Granted")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Button("Grant Permission") {
                                targetingManager.openAccessibilitySettings()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }

                    if !targetingManager.hasAccessibilityPermission {
                        Text("Click \"Grant Permission\" to add Restless to the Accessibility list, then enable the checkbox to grant permission.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    SectionHeader("Permissions", icon: "lock.shield")
                }

                // MARK: - App Selection
                Section {
                    HStack {
                        Text("Target App")
                        Spacer()
                        Button(targetAppDisplayName) {
                            targetingManager.refresh()
                            showingAppPicker = true
                        }
                        .buttonStyle(.bordered)
                    }

                    // Interval
                    HStack {
                        Text("Activity Interval")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.caffeinateAppIntervalSeconds },
                            set: { newValue in
                                settings.caffeinateAppIntervalSeconds = newValue
                                settings.save()
                                if caffeinateManager.isRunning {
                                    caffeinateManager.updateInterval(newValue)
                                }
                            }
                        )) {
                            Text("15 seconds").tag(15)
                            Text("30 seconds").tag(30)
                            Text("45 seconds").tag(45)
                            Text("60 seconds").tag(60)
                            Text("90 seconds").tag(90)
                            Text("2 minutes").tag(120)
                        }
                        .frame(width: 130)
                    }
                } header: {
                    SectionHeader("Settings", icon: "gearshape")
                }

                // MARK: - Status
                Section {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .foregroundColor(.secondary)
                        Spacer()
                        if caffeinateManager.eventCount > 0 {
                            Text("Events: \(caffeinateManager.eventCount)")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }

                    if let appName = caffeinateManager.targetAppName, caffeinateManager.isRunning {
                        HStack {
                            Text("Caffeinating")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(appName)
                                .font(.caption)
                        }
                    }

                    if let lastEvent = caffeinateManager.lastEventTime {
                        HStack {
                            Text("Last event")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(lastEvent.relativeString)
                                .font(.caption)
                        }
                    }

                    if !caffeinateManager.isRunning && settings.caffeinateAppBundleID != nil && targetingManager.hasAccessibilityPermission {
                        Button("Start Now") {
                            startCaffeinate()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } header: {
                    SectionHeader("Status", icon: "chart.bar")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(selectedBundleID: Binding(
                get: { settings.caffeinateAppBundleID },
                set: { newValue in
                    settings.caffeinateAppBundleID = newValue
                    settings.save()
                    if settings.caffeinateAppEnabled && targetingManager.hasAccessibilityPermission {
                        startCaffeinate()
                    }
                }
            ))
        }
        .alert("Accessibility Permission Required", isPresented: $showingPermissionAlert) {
            Button("Grant Permission") {
                targetingManager.openAccessibilitySettings()
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("Caffeinate App needs Accessibility permission to send activity events to background apps.\n\nRestless will be added to the Accessibility list. Just enable the checkbox to grant permission.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityPermissionChanged)) { _ in
            // When permission is granted, try to start caffeinate if enabled
            if targetingManager.hasAccessibilityPermission && settings.caffeinateAppEnabled {
                startCaffeinate()
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        if caffeinateManager.isRunning {
            return .green
        } else if !targetingManager.hasAccessibilityPermission {
            return .red
        } else {
            return .orange
        }
    }

    private var statusText: String {
        if caffeinateManager.isRunning {
            return "Running"
        } else if !targetingManager.hasAccessibilityPermission {
            return "Waiting for Permission"
        } else {
            return "Not Running"
        }
    }

    private var targetAppDisplayName: String {
        guard let bundleID = settings.caffeinateAppBundleID else {
            return "Select App..."
        }

        // Find the app name from running apps
        if let app = targetingManager.runningUserApps.first(where: { $0.bundleID == bundleID }) {
            return app.name
        }

        // App not running - show bundle ID
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }

    private func startCaffeinate() {
        guard let bundleID = settings.caffeinateAppBundleID else { return }
        guard targetingManager.hasAccessibilityPermission else {
            showingPermissionAlert = true
            return
        }
        caffeinateManager.start(bundleID: bundleID, intervalSeconds: settings.caffeinateAppIntervalSeconds)
    }
}

// MARK: - App Picker View

struct AppPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedBundleID: String?
    @ObservedObject private var targetingManager = TargetingManager.shared

    @State private var searchText = ""
    @State private var apps: [RunningAppInfo] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select App to Caffeinate")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Search
            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding()

            // App List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filteredApps) { app in
                        Button {
                            selectedBundleID = app.bundleID
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "app.fill")
                                    .frame(width: 24)
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .fontWeight(.medium)
                                    Text(app.bundleID)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if selectedBundleID == app.bundleID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(selectedBundleID == app.bundleID ? Color.accentColor.opacity(0.1) : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 450)
        .onAppear {
            refreshApps()
        }
    }

    private func refreshApps() {
        targetingManager.refresh()

        // Deduplicate by bundle ID
        var seenBundleIDs = Set<String>()
        var uniqueApps: [RunningAppInfo] = []

        for app in targetingManager.runningUserApps {
            if !seenBundleIDs.contains(app.bundleID) {
                seenBundleIDs.insert(app.bundleID)
                uniqueApps.append(app)
            }
        }

        apps = uniqueApps.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private var filteredApps: [RunningAppInfo] {
        if searchText.isEmpty {
            return apps
        }
        let lowercasedSearch = searchText.lowercased()
        return apps.filter {
            $0.name.lowercased().contains(lowercasedSearch) ||
            $0.bundleID.lowercased().contains(lowercasedSearch)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CaffeinateAppPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        CaffeinateAppPreferencesView(settings: AppSettings())
    }
}
#endif
