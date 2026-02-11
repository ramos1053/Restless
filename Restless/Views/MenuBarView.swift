import SwiftUI
import AppKit

// MARK: - Menu Bar Controller

/// Manages the menu bar status item and its menu.
final class MenuBarController: NSObject, ObservableObject {

    // MARK: - Properties

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?

    private let settings: AppSettings
    private let keepAwakeManager = KeepAwakeManager.shared
    private let caffeinateManager = CaffeinateAppManager.shared
    private let scheduleManager = ScheduleManager.shared

    private var preferencesWindowController: PreferencesWindowController?
    private var refreshTimer: Timer?

    private let logger = AppLogger.shared

    // MARK: - Initialization

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    // MARK: - Setup

    /// Sets up the menu bar status item.
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            updateStatusIcon()

            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        buildMenu()

        // Observe state changes
        setupObservers()

        logger.info("Menu bar controller setup complete")
    }

    /// Removes the status item from the menu bar.
    func teardown() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - Status Icon

    /// Updates the status bar icon based on current state with colored indicators.
    func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        let iconName: String
        let iconColor: NSColor

        if keepAwakeManager.isActive && caffeinateManager.isRunning {
            // Both active - bolt takes priority, yellow
            iconName = "bolt.fill"
            iconColor = .systemYellow
        } else if keepAwakeManager.isActive {
            // Keep-awake only - yellow bolt
            iconName = keepAwakeManager.isHealthy ? "bolt.fill" : "bolt"
            iconColor = .systemYellow
        } else if caffeinateManager.isRunning {
            // Caffeinate only - green if healthy, red if degraded/failed
            iconName = "cup.and.saucer.fill"
            iconColor = caffeinateManager.isHealthy ? .systemGreen : .systemRed
        } else {
            // Idle - orange moon
            iconName = "moon.zzz"
            iconColor = .systemOrange
        }

        let config = NSImage.SymbolConfiguration(paletteColors: [iconColor])
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Restless")?
            .withSymbolConfiguration(config) {
            image.isTemplate = false
            button.image = image
        }

        // Update tooltip with method info
        var tooltip = "Restless"
        if keepAwakeManager.isActive {
            if let remaining = keepAwakeManager.currentSession?.remainingTimeString {
                tooltip += "\nKeep-Awake: \(remaining)"
            } else {
                tooltip += "\nKeep-Awake: Active"
            }
            tooltip += " (\(keepAwakeManager.methodStatus))"
        }
        if caffeinateManager.isRunning {
            let names = caffeinateManager.targetAppNames.joined(separator: ", ")
            tooltip += "\nCaffeinate: \(names.isEmpty ? "Active" : names)"
            tooltip += " (\(caffeinateManager.methodStatus))"
        }
        button.toolTip = tooltip
    }

    // MARK: - Menu

    /// Builds the dropdown menu.
    private func buildMenu() {
        menu = NSMenu()

        // Status section
        addStatusSection()

        menu?.addItem(NSMenuItem.separator())

        // Quick toggles
        addQuickToggleSection()

        menu?.addItem(NSMenuItem.separator())

        // Schedules
        addSchedulesSection()

        menu?.addItem(NSMenuItem.separator())

        // Actions
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu?.addItem(prefsItem)

        menu?.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Restless", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu?.addItem(quitItem)
    }

    private func addStatusSection() {
        // Keep-Awake status
        let awakeStatus: String
        if keepAwakeManager.isActive {
            if let remaining = keepAwakeManager.currentSession?.remainingTimeString {
                awakeStatus = "Keep-Awake: \(remaining) remaining"
            } else {
                awakeStatus = "Keep-Awake: Active (indefinite)"
            }
        } else {
            awakeStatus = "Keep-Awake: Inactive"
        }

        let awakeItem = NSMenuItem(title: awakeStatus, action: nil, keyEquivalent: "")
        awakeItem.isEnabled = false

        if keepAwakeManager.isActive {
            let color: NSColor = keepAwakeManager.isHealthy ? .systemYellow : .systemOrange
            let config = NSImage.SymbolConfiguration(paletteColors: [color])
            let img = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config)
            img?.isTemplate = false
            awakeItem.image = img
        }
        menu?.addItem(awakeItem)

        // Keep-Awake method info (if degraded or failed)
        if keepAwakeManager.isActive && !keepAwakeManager.isHealthy {
            let methodItem = NSMenuItem(title: "  via \(keepAwakeManager.methodStatus)", action: nil, keyEquivalent: "")
            methodItem.isEnabled = false
            menu?.addItem(methodItem)
        }

        // Caffeinate App status
        if caffeinateManager.isRunning {
            let appCountStr = "\(caffeinateManager.activeTargetCount) app\(caffeinateManager.activeTargetCount == 1 ? "" : "s")"
            let caffeinateStatus = "Caffeinate: \(appCountStr) (\(caffeinateManager.totalEventCount) events)"
            let caffeinateItem = NSMenuItem(title: caffeinateStatus, action: nil, keyEquivalent: "")
            caffeinateItem.isEnabled = false

            let caffColor: NSColor = caffeinateManager.isHealthy ? .systemGreen : .systemRed
            let caffConfig = NSImage.SymbolConfiguration(paletteColors: [caffColor])
            let caffImg = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)?.withSymbolConfiguration(caffConfig)
            caffImg?.isTemplate = false
            caffeinateItem.image = caffImg
            menu?.addItem(caffeinateItem)

            // Caffeinate method info (if degraded)
            if !caffeinateManager.isHealthy {
                let methodItem = NSMenuItem(title: "  via \(caffeinateManager.methodStatus)", action: nil, keyEquivalent: "")
                methodItem.isEnabled = false
                menu?.addItem(methodItem)
            }
        }

        // Schedule status
        if scheduleManager.hasActiveSchedule {
            let scheduleNames = scheduleManager.activeSchedules.map { $0.name }.joined(separator: ", ")
            let scheduleItem = NSMenuItem(title: "Schedule: \(scheduleNames)", action: nil, keyEquivalent: "")
            scheduleItem.isEnabled = false
            scheduleItem.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
            menu?.addItem(scheduleItem)
        }
    }

    private func addQuickToggleSection() {
        // Toggle Keep-Awake
        let toggleAwakeTitle = keepAwakeManager.isActive ? "Stop Keep-Awake" : "Start Keep-Awake"
        let toggleAwakeItem = NSMenuItem(title: toggleAwakeTitle, action: #selector(toggleKeepAwake), keyEquivalent: "k")
        toggleAwakeItem.target = self
        menu?.addItem(toggleAwakeItem)

        // Keep-Awake options submenu
        if !keepAwakeManager.isActive {
            let awakeOptionsMenu = NSMenu()

            let indefiniteItem = NSMenuItem(title: "Indefinitely", action: #selector(startKeepAwakeIndefinite), keyEquivalent: "")
            indefiniteItem.target = self
            awakeOptionsMenu.addItem(indefiniteItem)

            let duration30Item = NSMenuItem(title: "For 30 minutes", action: #selector(startKeepAwake30Min), keyEquivalent: "")
            duration30Item.target = self
            awakeOptionsMenu.addItem(duration30Item)

            let duration1HItem = NSMenuItem(title: "For 1 hour", action: #selector(startKeepAwake1Hour), keyEquivalent: "")
            duration1HItem.target = self
            awakeOptionsMenu.addItem(duration1HItem)

            let duration2HItem = NSMenuItem(title: "For 2 hours", action: #selector(startKeepAwake2Hours), keyEquivalent: "")
            duration2HItem.target = self
            awakeOptionsMenu.addItem(duration2HItem)

            let awakeOptionsItem = NSMenuItem(title: "Keep-Awake For...", action: nil, keyEquivalent: "")
            awakeOptionsItem.submenu = awakeOptionsMenu
            menu?.addItem(awakeOptionsItem)
        }

        menu?.addItem(NSMenuItem.separator())

        // Toggle Caffeinate App
        if !settings.caffeinateTargets.isEmpty {
            let targetCount = settings.caffeinateTargets.count
            let caffeinateTitle = caffeinateManager.isRunning
                ? "Stop Caffeinate"
                : "Start Caffeinate (\(targetCount) app\(targetCount == 1 ? "" : "s"))"
            let caffeinateItem = NSMenuItem(title: caffeinateTitle, action: #selector(toggleCaffeinate), keyEquivalent: "c")
            caffeinateItem.target = self
            menu?.addItem(caffeinateItem)
        } else {
            let caffeinateItem = NSMenuItem(title: "Caffeinate App (Not Configured)", action: #selector(openPreferences), keyEquivalent: "")
            caffeinateItem.target = self
            menu?.addItem(caffeinateItem)
        }
    }

    @objc private func toggleCaffeinate() {
        if caffeinateManager.isRunning {
            caffeinateManager.stop()
            settings.caffeinateAppEnabled = false
        } else if !settings.caffeinateTargets.isEmpty {
            caffeinateManager.startAll(
                targets: settings.caffeinateTargets,
                intervalSeconds: settings.caffeinateAppIntervalSeconds
            )
            settings.caffeinateAppEnabled = true
        }
        settings.save()
        buildMenu()
    }

    private func addSchedulesSection() {
        guard !settings.schedules.isEmpty else { return }

        let schedulesMenu = NSMenu()

        // Global toggle
        let globalToggle = NSMenuItem(title: "Enable Scheduling", action: #selector(toggleScheduling), keyEquivalent: "")
        globalToggle.target = self
        globalToggle.state = settings.schedulingEnabled ? .on : .off
        schedulesMenu.addItem(globalToggle)

        schedulesMenu.addItem(NSMenuItem.separator())

        // Individual schedules
        for schedule in settings.schedules {
            let item = NSMenuItem(title: schedule.name, action: #selector(toggleScheduleItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = schedule.id
            item.state = schedule.isEnabled ? .on : .off

            if scheduleManager.activeSchedules.contains(where: { $0.id == schedule.id }) {
                item.image = NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil)
            }

            schedulesMenu.addItem(item)
        }

        let schedulesItem = NSMenuItem(title: "Schedules", action: nil, keyEquivalent: "")
        schedulesItem.submenu = schedulesMenu
        menu?.addItem(schedulesItem)
    }

    // MARK: - Observers

    private func setupObservers() {
        // Observe keep-awake changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateDidChange),
            name: .keepAwakeStateDidChange,
            object: nil
        )

        // Observe caffeinate changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateDidChange),
            name: .caffeinateStateDidChange,
            object: nil
        )

        // Observe method status changes (failover, degradation, recovery)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateDidChange),
            name: .methodStatusDidChange,
            object: nil
        )

        // Periodic refresh for time-based updates
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateStatusIcon()
        }
    }

    @objc private func stateDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusIcon()
            self?.buildMenu()
        }
    }

    // MARK: - Actions

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Show context menu on right-click
            if let menu = menu {
                statusItem?.menu = menu
                statusItem?.button?.performClick(nil)
                statusItem?.menu = nil
            }
        } else {
            // Show menu on left-click
            buildMenu() // Refresh menu
            if let menu = menu {
                statusItem?.menu = menu
                statusItem?.button?.performClick(nil)
                statusItem?.menu = nil
            }
        }
    }

    @objc private func toggleKeepAwake() {
        if keepAwakeManager.isActive {
            keepAwakeManager.stop()
        } else {
            keepAwakeManager.startIndefinite(scope: settings.defaultKeepAwakeScope)
        }
        NotificationCenter.default.post(name: .keepAwakeStateDidChange, object: nil)
    }

    @objc private func startKeepAwakeIndefinite() {
        keepAwakeManager.startIndefinite(scope: settings.defaultKeepAwakeScope)
        NotificationCenter.default.post(name: .keepAwakeStateDidChange, object: nil)
    }

    @objc private func startKeepAwake30Min() {
        keepAwakeManager.startForDuration(.minutes(30), scope: settings.defaultKeepAwakeScope)
        NotificationCenter.default.post(name: .keepAwakeStateDidChange, object: nil)
    }

    @objc private func startKeepAwake1Hour() {
        keepAwakeManager.startForDuration(.hours(1), scope: settings.defaultKeepAwakeScope)
        NotificationCenter.default.post(name: .keepAwakeStateDidChange, object: nil)
    }

    @objc private func startKeepAwake2Hours() {
        keepAwakeManager.startForDuration(.hours(2), scope: settings.defaultKeepAwakeScope)
        NotificationCenter.default.post(name: .keepAwakeStateDidChange, object: nil)
    }

    @objc private func toggleScheduling() {
        settings.schedulingEnabled.toggle()
        scheduleManager.isEnabled = settings.schedulingEnabled
        settings.save()
    }

    @objc private func toggleScheduleItem(_ sender: NSMenuItem) {
        guard let scheduleID = sender.representedObject as? UUID,
              let index = settings.schedules.firstIndex(where: { $0.id == scheduleID }) else { return }

        settings.schedules[index].isEnabled.toggle()
        settings.save()
        scheduleManager.updateSchedule(settings.schedules[index])
    }

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(settings: settings)
        }
        preferencesWindowController?.show()
    }

    @objc private func quitApp() {
        // Cleanup
        keepAwakeManager.stop()
        caffeinateManager.stop()
        scheduleManager.stopScheduler()

        NSApp.terminate(nil)
    }
}
