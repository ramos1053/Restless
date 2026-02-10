# Changelog

## [1.0.0] - 2026-02-06

### Added
- **Keep-Awake functionality**
  - Prevents system sleep using Apple's `caffeinate` command
  - Prevents screen lock using `caffeinate -u` for reliable user activity declaration
  - Multiple modes: indefinite, duration-based, or until a specific time
  - Configurable scope: system-only (display can sleep) or system + display

- **Caffeinate App**
  - Keep background apps active without moving cursor
  - Sends invisible activity events directly to the selected app's process
  - Declares system-level user activity to prevent screen lock
  - Keeps selected apps showing you as "Active"
  - Configurable activity interval (15 seconds to 10 minutes)
  - Permission status indicator with easy grant button

- **Scheduling**
  - Time-based schedules with day-of-week selection
  - Overnight schedule support
  - Multiple concurrent schedules
  - Per-schedule action configuration

- **Menu Bar Interface**
  - Status icons for different states
  - Quick toggles and duration presets
  - Schedule management

- **Preferences**
  - General settings (launch at login, dock icon)
  - Caffeinate app settings with permission management
  - Schedule management

- **System Integration**
  - Launch at login via SMAppService
  - Accessibility permission handling with auto-add to list

- **Security Hardening**
  - Timeout bounds validation (1 minute to 24 hours)
  - Target app validation with blocklist for system processes
  - PID tracking to prevent PID reuse attacks
  - Interval bounds validation
  - Path traversal prevention
  - Input sanitization

### Technical
- Built with SwiftUI, AppKit, CoreGraphics, and IOKit
- No third-party dependencies
- macOS 13.0+ required
- Non-sandboxed for full system access

## [Unreleased]

### Planned
- Notarization for distribution outside Mac App Store
- Menu bar icon customization
- Keyboard shortcuts for quick toggles
- Battery level threshold to auto-disable
- Integration with external displays (auto-enable when connected)
