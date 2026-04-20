# Restless

A macOS menu bar app that keeps your Mac awake and prevents screen lock. Built entirely with Apple frameworks — no third-party dependencies.

## Features

### Keep-Awake
- Prevents system sleep using Apple's `caffeinate` command (same approach as KeepingYouAwake)
- Prevents screen lock using overlapping `caffeinate -u` calls for reliable user activity declaration
- Multiple modes: indefinite, duration-based, or until a specific time
- Configurable scope: system-only (display can sleep) or system + display

### Caffeinate App
- Keep any app or web browser active in the background without moving your cursor
- Sends invisible mouse and keyboard activity events directly to the selected app's process
- Declares system-level user activity to prevent screen lock
- Your cursor does not move and your work is not interrupted
- Works with minimized or unfocused windows
- Configurable activity interval (15 seconds to 10 minutes)

### Scheduling
- Create time-based schedules (e.g., 9 AM – 5 PM on weekdays)
- Each schedule can enable keep-awake, caffeinate app, or both
- Overnight schedule support
- Multiple concurrent schedules

### Menu Bar Interface
- Status icons showing current state
- Quick toggles for keep-awake
- Duration presets (30 min, 1 hour, 2 hours)
- Schedule management

## Requirements

- **macOS 13.0 (Ventura)** or later
- **Xcode 15.0** or later (to build from source)
- **Accessibility permissions** (for the Caffeinate App feature)

## Building and Running

### 1. Code Signing (required before first build)

1. Open `Restless.xcodeproj` in Xcode
2. Click the project in the Navigator → select the **Restless** target
3. Go to **Signing & Capabilities**
4. Set **Team** to your own Apple developer account (or "None / Sign to Run Locally" for ad-hoc)
5. Optionally update **Bundle Identifier** (e.g. `com.yourname.Restless`)

> **Note on re-signing:** Each time you build with Xcode using ad-hoc signing, macOS assigns a new code signature. If you previously granted Accessibility permission, you may need to remove and re-add Restless in **System Settings → Privacy & Security → Accessibility** after a rebuild.

### 2. Open in Xcode

```bash
open Restless.xcodeproj
```

### 3. Build and Run

1. Select the **Restless** scheme
2. Select **My Mac** as the run destination
3. Press **⌘R** to build and run

### 3. First Launch

On first launch, the app will:
1. Appear in your menu bar (look for the moon/bolt icon)
2. Be ready to use immediately (no permissions needed for Keep-Awake)

## Permissions

### Accessibility Permission

**Required for:** Caffeinate App feature only (sending activity events to background apps)

**Not required for:** Keep-Awake feature (preventing sleep/screen lock)

**When you enable the Caffeinate App feature:**
1. The app shows the permission status with a colored indicator:
   - Green = Permission granted, ready to use
   - Red = Permission required
2. Click **Grant Permission** — Restless will be automatically added to the Accessibility list
3. Enable the checkbox next to Restless in System Settings
4. Return to Restless — it will automatically detect the permission and start working

**Note:** When rebuilding from Xcode with ad-hoc signing, you may need to remove and re-add the app in Accessibility settings as the code signature changes.

## Launch at Login

Open Restless Preferences > **General** tab > enable **Launch at Login**.

This uses Apple's SMAppService API (macOS 13+).

## Usage

### Menu Bar

Click the menu bar icon to:
- See current status (keep-awake, caffeinate, schedules)
- Toggle keep-awake on/off
- Toggle caffeinate on/off
- Access quick duration presets
- Manage schedules
- Open Preferences

### Menu Bar Icons

| Icon | Meaning |
|------|---------|
| Moon with Zzz | Idle (nothing active) |
| Bolt outline | Keep-awake active |
| Cup and saucer | Caffeinate active |
| Filled bolt | Both active |

### Preferences

Access via menu bar > **Preferences...**

**General Tab:**
- Launch at login
- Show/hide Dock icon
- Keep-awake defaults (mode, scope, duration)

**Caffeinate App Tab:**
- Enable/disable caffeinate
- Select any running app or web browser to keep active
- Activity interval setting
- Status display

**Scheduling Tab:**
- Enable/disable scheduling
- Add/edit/remove schedules
- Configure schedule actions

## How It Works

### Sleep Prevention

Restless uses a two-pronged approach to reliably prevent both sleep and screen lock:

1. **`caffeinate -di -w PID`** — Apple's command-line utility for sleep prevention
   - `-d` flag: Prevents display from sleeping
   - `-i` flag: Prevents system from idle sleeping
   - `-w PID` flag: Ties the assertion to the app's lifetime

2. **`caffeinate -u -t <duration>`** — Declares user is active (periodic)
   - `-u` flag: Resets the idle timer and declares user activity
   - `-t <duration>` flag: Maintains the assertion for the specified seconds
   - Spawned periodically with overlapping durations for continuous coverage

This combination ensures that:
- The display stays on
- The system doesn't sleep
- The screen lock doesn't activate
- Screen saver doesn't start

### App Activity Simulation

When the Caffeinate App feature is enabled, Restless sends invisible events directly to the target process:
- **Mouse move events** — simulated within the app's window bounds
- **Keyboard events** — a Shift key press/release that has no visible effect but resets idle timers

These events are posted via `CGEvent.postToPid()`, which delivers them directly to the process without stealing focus or moving your cursor.

### Verifying It's Working

Check active power assertions in Terminal:
```bash
pmset -g assertions
```

You should see assertions from "caffeinate" when Keep-Awake is enabled.

## Architecture

```
Restless/
├── RestlessApp.swift              # App entry point
├── Models/
│   ├── Settings.swift             # App settings (Codable)
│   └── Schedule.swift             # Schedule model
├── Managers/
│   ├── KeepAwakeManager.swift     # Caffeinate + user activity assertions
│   ├── CaffeinateAppManager.swift # App-specific activity + user activity
│   ├── TargetingManager.swift     # Running app enumeration
│   ├── ScheduleManager.swift      # Time-based scheduling
│   └── LoginItemManager.swift     # SMAppService integration
├── Views/
│   ├── MenuBarView.swift          # Menu bar controller
│   ├── PreferencesView.swift      # Preferences window
│   └── ...                        # Tab-specific views
├── Utilities/
│   ├── Logger.swift               # OSLog wrapper
│   └── Extensions.swift           # Helper extensions
└── Resources/
    └── Assets.xcassets            # App icons and colors
```

## Key Technologies

| Feature | API/Framework |
|---------|---------------|
| Sleep prevention | `/usr/bin/caffeinate` command |
| Screen lock prevention | IOKit (`IOPMAssertionDeclareUserActivity`) |
| Keep-awake assertions | IOKit (`IOPMAssertionCreateWithName`) |
| Mouse & keyboard events | CoreGraphics (`CGEvent`) |
| App enumeration | AppKit (`NSWorkspace.shared.runningApplications`) |
| Menu bar | AppKit (`NSStatusItem`) |
| Preferences UI | SwiftUI |
| Launch at login | ServiceManagement (`SMAppService`) |
| Logging | OSLog |
| Settings storage | UserDefaults |

## Limitations

### Sandboxing
- The app is **not sandboxed** to allow spawning caffeinate processes, IOKit power assertions, and CGEvent posting
- This means it cannot be distributed via the Mac App Store without modifications

### Accessibility
- Accessibility permissions must be granted manually by the user
- The app cannot programmatically enable these permissions
- Permissions may need to be re-granted after Xcode rebuilds (ad-hoc signing)

## Troubleshooting

### Keep-awake not preventing screen lock
1. Verify caffeinate is running: `pgrep caffeinate`
2. Check assertions: `pmset -g assertions`
3. Look for "Restless User Activity" assertion
4. Check Console.app for logs (filter by "com.restless")

### Keep-awake not preventing sleep
1. Verify with `pmset -g assertions` in Terminal
2. Check for conflicting apps
3. Try system-and-display scope

### Caffeinate App not keeping target active
1. Ensure the target app is running
2. Re-select the target in preferences
3. Check Accessibility permissions in System Settings

### App not launching at login
1. Check System Settings > General > Login Items
2. Ensure the app is in /Applications

## Viewing Logs

### Console.app
1. Open Console.app
2. Filter by: `subsystem:com.restless`

### Terminal
```bash
log show --predicate 'subsystem == "com.restless"' --last 1h
```

## Credits

Inspired by:
- [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) — caffeinate-based approach
- [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) — feature inspiration

## License

MIT License — See [LICENSE](LICENSE) for details.

---

Built with SwiftUI, AppKit, CoreGraphics, and IOKit. No external dependencies.
