import SwiftUI

// MARK: - General Preferences View

/// General settings tab in preferences.
struct GeneralPreferencesView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var loginItemManager = LoginItemManager.shared

    var body: some View {
        Form {
            // MARK: - Startup Section
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { newValue in
                        if newValue {
                            loginItemManager.enable()
                        } else {
                            loginItemManager.disable()
                            settings.startKeepAwakeOnLogin = false
                        }
                        settings.launchAtLogin = newValue
                        settings.save()
                    }
                ))
                .help("Start Restless automatically when you log in")

                Toggle("Start Keep-Awake on Login", isOn: Binding(
                    get: { settings.startKeepAwakeOnLogin },
                    set: { newValue in
                        settings.startKeepAwakeOnLogin = newValue
                        settings.save()
                    }
                ))
                .disabled(!loginItemManager.isEnabled)
                .help("Automatically start a Keep-Awake session when Restless launches at login")

                if !loginItemManager.isEnabled && settings.startKeepAwakeOnLogin {
                    // Safety: clear the setting if launch at login is off
                    Color.clear.frame(height: 0).onAppear {
                        settings.startKeepAwakeOnLogin = false
                        settings.save()
                    }
                }

                if let error = loginItemManager.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            } header: {
                SectionHeader("Startup", icon: "power")
            }

            // MARK: - Keep-Awake Defaults
            Section {
                HStack {
                    Text("Default Mode")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.defaultKeepAwakeMode },
                        set: { newValue in
                            settings.defaultKeepAwakeMode = newValue
                            settings.save()
                        }
                    )) {
                        ForEach(KeepAwakeMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                HStack {
                    Text("Default Scope")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.defaultKeepAwakeScope },
                        set: { newValue in
                            settings.defaultKeepAwakeScope = newValue
                            settings.save()
                        }
                    )) {
                        ForEach(KeepAwakeScope.allCases, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }

                if settings.defaultKeepAwakeMode == .duration {
                    HStack {
                        Text("Default Duration")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.defaultDurationMinutes },
                            set: { newValue in
                                settings.defaultDurationMinutes = newValue
                                settings.save()
                            }
                        )) {
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                            Text("2 hours").tag(120)
                            Text("4 hours").tag(240)
                            Text("8 hours").tag(480)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
            } header: {
                SectionHeader("Keep-Awake Defaults", icon: "bolt")
            }

            // MARK: - Quick Info
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    InfoRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }
            } header: {
                SectionHeader("About", icon: "info.circle")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loginItemManager.refreshStatus()
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .textSelection(.enabled)
        }
        .font(.caption)
    }
}

// MARK: - Preview

#if DEBUG
struct GeneralPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralPreferencesView(settings: AppSettings())
            .frame(width: 500, height: 400)
    }
}
#endif
