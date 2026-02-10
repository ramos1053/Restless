import SwiftUI

// MARK: - Schedule Preferences View

/// Scheduling settings tab in preferences.
struct SchedulePreferencesView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var scheduleManager = ScheduleManager.shared

    @State private var selectedScheduleID: UUID?
    @State private var showScheduleEditor = false
    @State private var editingSchedule: Schedule?

    var body: some View {
        Form {
            // MARK: - Enable Section
            Section {
                Toggle("Enable Scheduling", isOn: Binding(
                    get: { settings.schedulingEnabled },
                    set: { newValue in
                        settings.schedulingEnabled = newValue
                        scheduleManager.isEnabled = newValue
                        settings.save()
                    }
                ))
                .help("Automatically enable keep-awake and caffeinate based on schedules")

                HStack {
                    Image(systemName: scheduleManager.hasActiveSchedule ? "clock.fill" : "clock")
                        .foregroundColor(scheduleManager.hasActiveSchedule ? .green : .secondary)
                    Text(scheduleManager.statusString)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            } header: {
                SectionHeader("Scheduling", icon: "calendar.badge.clock")
            }

            // MARK: - Schedules List
            Section {
                if settings.schedules.isEmpty {
                    Text("No schedules configured")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(settings.schedules) { schedule in
                        ScheduleRowView(
                            schedule: schedule,
                            isActive: scheduleManager.activeSchedules.contains { $0.id == schedule.id },
                            onToggle: { enabled in
                                toggleSchedule(schedule, enabled: enabled)
                            },
                            onEdit: {
                                editingSchedule = schedule
                                showScheduleEditor = true
                            },
                            onDelete: {
                                deleteSchedule(schedule)
                            }
                        )
                    }
                }

                Button(action: {
                    editingSchedule = nil
                    showScheduleEditor = true
                }) {
                    Label("Add Schedule", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            } header: {
                SectionHeader("Schedules", icon: "list.bullet")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showScheduleEditor) {
            ScheduleEditorView(
                schedule: editingSchedule,
                onSave: { schedule in
                    saveSchedule(schedule)
                    showScheduleEditor = false
                },
                onCancel: {
                    showScheduleEditor = false
                }
            )
        }
        .onAppear {
            scheduleManager.setSchedules(settings.schedules)
        }
    }

    // MARK: - Actions

    private func toggleSchedule(_ schedule: Schedule, enabled: Bool) {
        if let index = settings.schedules.firstIndex(where: { $0.id == schedule.id }) {
            settings.schedules[index].isEnabled = enabled
            settings.save()
            scheduleManager.updateSchedule(settings.schedules[index])
        }
    }

    private func saveSchedule(_ schedule: Schedule) {
        if let index = settings.schedules.firstIndex(where: { $0.id == schedule.id }) {
            settings.schedules[index] = schedule
        } else {
            settings.schedules.append(schedule)
        }
        settings.save()
        scheduleManager.setSchedules(settings.schedules)
    }

    private func deleteSchedule(_ schedule: Schedule) {
        settings.schedules.removeAll { $0.id == schedule.id }
        settings.save()
        scheduleManager.removeSchedule(id: schedule.id)
    }
}

// MARK: - Schedule Row View

struct ScheduleRowView: View {
    let schedule: Schedule
    let isActive: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(isActive ? Color.green : (schedule.isEnabled ? Color.orange : Color.gray))
                .frame(width: 8, height: 8)

            // Schedule info
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.name)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text(schedule.days.displayString)
                    Text("\(schedule.startTime.displayString) - \(schedule.endTime.displayString)")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    if schedule.enableKeepAwake {
                        Label("Awake", systemImage: "bolt.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    if schedule.enableCaffeinate {
                        Label("Caffeinate", systemImage: "cup.and.saucer.fill")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                }
            }

            Spacer()

            // Actions
            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Schedule Editor View

struct ScheduleEditorView: View {
    let schedule: Schedule?
    let onSave: (Schedule) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var days: DayOfWeek = .weekdays
    @State private var startTime: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var endTime: Date = Calendar.current.date(from: DateComponents(hour: 17, minute: 0)) ?? Date()
    @State private var enableKeepAwake: Bool = true
    @State private var keepAwakeScope: KeepAwakeScope = .systemAndDisplay
    @State private var enableCaffeinate: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(schedule == nil ? "New Schedule" : "Edit Schedule")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Days") {
                    DayPicker(selection: $days)
                }

                Section("Time") {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                Section("Actions") {
                    Toggle("Enable Keep-Awake", isOn: $enableKeepAwake)

                    if enableKeepAwake {
                        Picker("Scope", selection: $keepAwakeScope) {
                            ForEach(KeepAwakeScope.allCases, id: \.self) { scope in
                                Text(scope.displayName).tag(scope)
                            }
                        }
                    }

                    Toggle("Enable Caffeinate App", isOn: $enableCaffeinate)
                        .help("Start the Caffeinate App feature during this schedule")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 500)
        .onAppear {
            loadSchedule()
        }
    }

    private func loadSchedule() {
        guard let schedule = schedule else { return }

        name = schedule.name
        days = schedule.days
        startTime = schedule.startTime.date()
        endTime = schedule.endTime.date()
        enableKeepAwake = schedule.enableKeepAwake
        keepAwakeScope = schedule.keepAwakeScope
        enableCaffeinate = schedule.enableCaffeinate
    }

    private func save() {
        let startComponents = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        let endComponents = Calendar.current.dateComponents([.hour, .minute], from: endTime)

        var newSchedule = schedule ?? Schedule(
            name: name,
            days: days,
            startTime: TimeOfDay(hour: startComponents.hour ?? 9, minute: startComponents.minute ?? 0),
            endTime: TimeOfDay(hour: endComponents.hour ?? 17, minute: endComponents.minute ?? 0)
        )

        newSchedule.name = name
        newSchedule.days = days
        newSchedule.startTime = TimeOfDay(hour: startComponents.hour ?? 9, minute: startComponents.minute ?? 0)
        newSchedule.endTime = TimeOfDay(hour: endComponents.hour ?? 17, minute: endComponents.minute ?? 0)
        newSchedule.enableKeepAwake = enableKeepAwake
        newSchedule.keepAwakeScope = keepAwakeScope
        newSchedule.enableCaffeinate = enableCaffeinate

        onSave(newSchedule)
    }
}

// MARK: - Day Picker

struct DayPicker: View {
    @Binding var selection: DayOfWeek

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DayOfWeek.orderedDays, id: \.day.rawValue) { day in
                DayButton(
                    shortName: day.shortName,
                    isSelected: selection.contains(day.day),
                    action: {
                        if selection.contains(day.day) {
                            selection.remove(day.day)
                        } else {
                            selection.insert(day.day)
                        }
                    }
                )
            }
        }

        HStack {
            Button("Weekdays") { selection = .weekdays }
                .buttonStyle(.bordered)
            Button("Weekends") { selection = .weekends }
                .buttonStyle(.bordered)
            Button("All") { selection = .allDays }
                .buttonStyle(.bordered)
        }
    }
}

struct DayButton: View {
    let shortName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(String(shortName.prefix(1)))
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct SchedulePreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        SchedulePreferencesView(settings: AppSettings())
            .frame(width: 500, height: 600)
    }
}
#endif
