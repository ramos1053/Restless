# Restless

A macOS menu bar app that keeps your Mac awake and stops the screen from locking. Built entirely on Apple's own frameworks — no third-party dependencies anywhere.

## What it does

**Keep-Awake** stops the system from sleeping using the same `caffeinate`-based approach as KeepingYouAwake, and separately prevents screen lock by overlapping `caffeinate -u` calls to keep declaring user activity. You can run it indefinitely, for a set duration, or until a specific time, and choose whether it covers just the system or the system and display both.

**Caffeinate App** keeps a specific app or browser active in the background — sending invisible mouse and keyboard events straight to that process — without moving your actual cursor or interrupting whatever you're doing. It works even if the target app is minimized, and the activity interval is adjustable from 15 seconds up to 10 minutes.

**Scheduling** lets you set up time-based rules (9 AM–5 PM on weekdays, say), each of which can trigger keep-awake, the caffeinate app feature, or both, including overnight schedules and multiple schedules running at once.

The menu bar itself shows status icons for whatever's currently active, quick toggles, duration presets (30 min / 1 hr / 2 hr), and schedule management.

## Requirements

- macOS 14.0 (Sonoma) or later for a Release build (the Debug config still targets 13.0, but Release is what actually ships)
- Xcode 15.0+ to build from source
- Accessibility permission, but only if you use the Caffeinate App feature

## Building and running

Before the first build, open `Restless.xcodeproj`, select the Restless target's **Signing & Capabilities**, and set **Team** to your own Apple developer account (or "Sign to Run Locally" for an ad-hoc build). Note that each ad-hoc rebuild gets a new code signature, so if you'd previously granted Accessibility permission, you may need to remove and re-add Restless in System Settings → Privacy & Security → Accessibility afterward.

```bash
open Restless.xcodeproj
```

Select the Restless scheme, choose "My Mac" as the run destination, and press ⌘R. On first launch it appears in the menu bar (look for the moon/bolt icon) and Keep-Awake works immediately — no permissions needed for that part.

## Permissions

Accessibility permission is only required for Caffeinate App — sending activity events to other processes needs it, but plain Keep-Awake doesn't. When you turn on Caffeinate App, Restless shows a colored indicator (green for granted, red for required); clicking Grant Permission adds it to the Accessibility list automatically, and you just need to check the box next to Restless in System Settings. Once granted, Restless picks it up automatically.

One quirk worth knowing: rebuilding from Xcode with ad-hoc signing changes the code signature each time, which can mean removing and re-adding Restless in Accessibility settings after a rebuild.

## Launch at login

Preferences → General → Launch at Login, which uses Apple's SMAppService API (macOS 13+).

## Using it

Click the menu bar icon to see current status, toggle keep-awake or caffeinate, jump to a duration preset, manage schedules, or open Preferences. The icon itself tells you what's active: a moon with Zzz means idle, a bolt outline means keep-awake is on, a cup and saucer means caffeinate is running, and a filled bolt means both.

Preferences has three tabs — General (login item, dock icon, keep-awake defaults), Caffeinate App (target selection, activity interval, status), and Scheduling (add/edit/remove time-based rules).

## How it actually prevents sleep

Two mechanisms working together. `caffeinate -di -w PID` is Apple's own sleep-prevention utility — `-d` stops the display from sleeping, `-i` stops idle sleep, and `-w PID` ties the whole thing to Restless's lifetime. Alongside that, `caffeinate -u -t <duration>` periodically declares user activity, resetting the idle timer; these are spawned with overlapping durations so there's no gap in coverage. Together they keep the display on, stop the system from sleeping, and prevent both screen lock and the screensaver from kicking in.

For the Caffeinate App feature specifically, Restless posts simulated mouse-move and keyboard events (a harmless Shift press/release) directly to the target process via `CGEvent.postToPid()` — which delivers them without stealing focus or moving your actual cursor. It supports up to 10 simultaneous targets, refuses to target a short list of sensitive system processes (Finder, the login window, SecurityAgent, System Settings, Keychain Access, Terminal, Xcode), and guards against PID reuse so it doesn't end up posting events to a different app that happened to inherit a tracked process ID.

You can confirm it's working by running `pmset -g assertions` in Terminal and looking for a "caffeinate" assertion.

If `caffeinate` itself fails to launch or dies unexpectedly, both Keep-Awake and Caffeinate App fall back to raw IOKit power assertions (`IOPMAssertionCreateWithName` / `IOPMAssertionDeclareUserActivity`) and report a "degraded" health state in the menu bar rather than silently doing nothing.

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
├── Models/
│   └── MethodHealth.swift         # Health/fallback state for the sleep-prevention methods
├── Views/
│   ├── MenuBarView.swift          # Menu bar controller
│   ├── PreferencesView.swift      # Preferences window
│   └── ...                        # Tab-specific views
├── Utilities/
│   ├── Logger.swift               # OSLog wrapper
│   ├── AppSecurity.swift          # Path/input sanitization, rate limiting, settings-integrity checks
│   └── Extensions.swift           # Helper extensions
└── Resources/
    └── Assets.xcassets            # App icons and colors
```

Key frameworks: `/usr/bin/caffeinate` for sleep prevention, IOKit for screen-lock prevention and keep-awake assertions, CoreGraphics for the simulated mouse/keyboard events, AppKit for app enumeration and the menu bar itself, SwiftUI for preferences, ServiceManagement for launch-at-login, and OSLog/UserDefaults for logging and settings.

## Known limitations

Restless isn't sandboxed — it needs to spawn caffeinate processes, create IOKit power assertions, and post CGEvents, none of which are sandbox-friendly — so Mac App Store distribution isn't in the cards without real changes. Accessibility permission also has to be granted manually every time (no way around that), and ad-hoc rebuilds may require re-granting it since the signature changes.

## Troubleshooting

If keep-awake isn't preventing screen lock, check that caffeinate is actually running (`pgrep caffeinate`), look for a "Restless User Activity" assertion in `pmset -g assertions`, and check Console.app filtered to `com.restless`. If it's not preventing sleep, same `pmset` check, and look for conflicting apps or try the system-and-display scope instead of system-only. If Caffeinate App isn't keeping its target active, confirm the target app is actually running, re-select it in preferences, and double check Accessibility permissions. If Restless isn't launching at login, check System Settings → General → Login Items and confirm it's actually in /Applications.

Logs are visible in Console.app (filter by `subsystem:com.restless`) or via `log show --predicate 'subsystem == "com.restless"' --last 1h` in Terminal.

## Credits

Inspired by [KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) for the caffeinate-based approach, and [Amphetamine](https://apps.apple.com/app/amphetamine/id937984704) for some of the feature ideas.

## License

MIT — see [LICENSE](LICENSE).
