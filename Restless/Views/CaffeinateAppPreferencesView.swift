import SwiftUI

// MARK: - Caffeinate App Preferences View

/// Preferences view for the Caffeinate App feature.
/// Supports up to 10 simultaneous target apps.
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
                            showingPermissionAlert = true
                            settings.caffeinateAppEnabled = true
                        } else {
                            settings.caffeinateAppEnabled = newValue
                            if newValue {
                                startAllTargets()
                            } else {
                                caffeinateManager.stop()
                            }
                        }
                        settings.save()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Caffeinate App")
                        Text("Keeps background apps active without moving your cursor")
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

                // MARK: - Apps List
                Section {
                    if settings.caffeinateTargets.isEmpty {
                        Text("No apps selected. Click + to add an app.")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(settings.caffeinateTargets) { target in
                            HStack {
                                Image(systemName: "app.fill")
                                    .frame(width: 20)
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(displayName(for: target))
                                        .fontWeight(.medium)
                                    Text(target.bundleID)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                // Running status indicator
                                if caffeinateManager.isRunning && caffeinateManager.targetAppNames.contains(where: {
                                    $0 == displayName(for: target)
                                }) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                }

                                Button {
                                    removeTarget(target)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    // Add button
                    if settings.caffeinateTargets.count < AppSettings.maxCaffeinateTargets {
                        Button {
                            targetingManager.refresh()
                            showingAppPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.accentColor)
                                Text("Add App")
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Maximum of \(AppSettings.maxCaffeinateTargets) apps reached")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    SectionHeader("Apps", icon: "square.stack")
                }

                // MARK: - Settings
                Section {
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
                        if caffeinateManager.totalEventCount > 0 {
                            Text("Events: \(caffeinateManager.totalEventCount)")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }

                    if caffeinateManager.isRunning {
                        HStack {
                            Text("Active")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(caffeinateManager.activeTargetCount) of \(settings.caffeinateTargets.count) apps")
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

                    if !caffeinateManager.isRunning && !settings.caffeinateTargets.isEmpty && targetingManager.hasAccessibilityPermission {
                        Button("Start All") {
                            startAllTargets()
                        }
                        .buttonStyle(.borderedProminent)
                    } else if caffeinateManager.isRunning {
                        Button("Stop All") {
                            caffeinateManager.stop()
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    SectionHeader("Status", icon: "chart.bar")
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(
                existingBundleIDs: Set(settings.caffeinateTargets.map { $0.bundleID }),
                onSelect: { app in
                    let target = CaffeinateTarget(bundleID: app.bundleID, appName: app.name)
                    settings.caffeinateTargets.append(target)
                    settings.save()
                    if settings.caffeinateAppEnabled && targetingManager.hasAccessibilityPermission {
                        caffeinateManager.startTarget(
                            bundleID: target.bundleID,
                            appName: target.appName,
                            intervalSeconds: settings.caffeinateAppIntervalSeconds
                        )
                    }
                }
            )
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
            if targetingManager.hasAccessibilityPermission && settings.caffeinateAppEnabled {
                startAllTargets()
            }
        }
    }

    // MARK: - Helpers

    private func displayName(for target: CaffeinateTarget) -> String {
        // Try to get the current name from running apps
        if let app = targetingManager.runningUserApps.first(where: { $0.bundleID == target.bundleID }) {
            return app.name
        }
        return target.appName
    }

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
        } else if settings.caffeinateTargets.isEmpty {
            return "No Apps Selected"
        } else {
            return "Not Running"
        }
    }

    private func removeTarget(_ target: CaffeinateTarget) {
        // Stop caffeinating this target if running
        caffeinateManager.stopTarget(bundleID: target.bundleID)
        // Remove from settings
        settings.caffeinateTargets.removeAll { $0.id == target.id }
        settings.save()
    }

    private func startAllTargets() {
        guard !settings.caffeinateTargets.isEmpty else { return }
        guard targetingManager.hasAccessibilityPermission else {
            showingPermissionAlert = true
            return
        }
        caffeinateManager.startAll(
            targets: settings.caffeinateTargets,
            intervalSeconds: settings.caffeinateAppIntervalSeconds
        )
    }
}

// MARK: - App Picker View

struct AppPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let existingBundleIDs: Set<String>
    let onSelect: (RunningAppInfo) -> Void
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
                            onSelect(app)
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
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
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

        // Deduplicate by bundle ID and exclude already-selected apps
        var seenBundleIDs = Set<String>()
        var uniqueApps: [RunningAppInfo] = []

        for app in targetingManager.runningUserApps {
            if !seenBundleIDs.contains(app.bundleID) && !existingBundleIDs.contains(app.bundleID) {
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
