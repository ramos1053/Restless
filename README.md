# Restless

macOS menu bar app that keeps your Mac awake. No third-party dependencies.

**Requires:** macOS 13.0 (Ventura) or later

---

## What it does

**Keep-Awake** — prevents system sleep and screen lock using Apple's `caffeinate` utility and IOKit power assertions. Runs indefinitely, for a set duration, or until a specific time. You can target the system only or include the display.

**Caffeinate App** — keeps a specific app active in the background without touching your cursor. Sends invisible mouse and keyboard events directly to the target process via `CGEvent.postToPid()`. Useful for keeping a remote session or long-running job from going idle while you work in another window.

**Scheduling** — set time-based schedules (e.g. 9 AM – 5 PM weekdays) that automatically enable keep-awake, caffeinate, or both. Overnight schedules work. Multiple concurrent schedules work.

---

## Build

1. Open `Restless.xcodeproj` in Xcode
2. Set your signing team under Signing & Capabilities
3. Press `⌘R`

The Caffeinate App feature needs Accessibility permission. Keep-Awake doesn't. After a Xcode rebuild with ad-hoc signing the code signature changes — you'll need to remove and re-add Restless in System Settings → Privacy & Security → Accessibility.

---

## Verify it's working

```sh
pmset -g assertions
```

You should see assertions from `caffeinate` and "Restless User Activity" when keep-awake is active.

---

## Launch at login

Preferences → General → Launch at Login. Uses `SMAppService` (macOS 13+).

---

MIT License — [LICENSE](../LICENSE)
