# Changelog

All notable changes to the Claude Usage macOS Menu Bar App will be documented in this file.

---

## [1.1.0] - 2026-05-27

### Added
- **WidgetKit Support:** Created a native 2x2 desktop/notification center widget designed in the Apple Battery Widget style with circular progress rings.
- **App Group Pipeline:** Implemented data sharing via App Group shared containers to synchronise the widget and the menu bar app with zero lag.
- **Launch at Login:** Added a "Launch at Login" toggle in Settings under Preferences utilizing the modern macOS `ServiceManagement` API.

### Fixed
- **Status Bar Centering:** Fixed an AppKit layout bug that caused the menu bar text to align off-center when the "C" icon was disabled.
- **Vertical Alignment & Clipping:** Added baseline offsets and strict line height constraints to prevent vertical text clipping inside the highlighted menu bar squircle.
- **DPI Cutoffs:** Added trailing character padding to prevent text cutoff on external monitors.

---

## [1.0.1] - 2026-05-27

### Added
- **Keyboard Shortcuts:** Configured a standard Edit menu (Cut, Copy, Paste, Select All) to enable keyboard shortcuts like `Cmd+V` in settings text fields.
- **Resizable Sidebar:** Converted the static settings view into a draggable `HSplitView` so users can resize the navigation column.
- **Percentage Summaries:** Added a text summary line inside the dropdown menu showing overall session and weekly usage percentage at a glance.

---

## [1.0.0] - 2026-05-27

### Added
- **Initial Release:** Core application supporting dual usage tracking (Claude Web Session Key and Claude Code CLI credentials).
- **Notifications:** Integrated with macOS User Notification Center for threshold alerts.
- **Lightweight Compilation:** Zero-Xcode build script (`build.sh`) compiling the Swift binaries in under 2 seconds.
