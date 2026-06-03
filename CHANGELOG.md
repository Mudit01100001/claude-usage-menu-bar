# Changelog

All notable changes to the Claude Usage macOS Menu Bar App will be documented in this file.

---

## [1.4.0] - 2026-06-03

### Fixed
- **Claude reliability restored:** the multi-provider release had added a hard 5-second timeout to every network request. Claude's web path makes two sequential calls (org lookup → usage), so any slow response silently blanked the menu bar to `--%`. Timeout relaxed to 15s.
- **Thread-safety:** per-provider usage buckets were written on URLSession background threads while being read on the main thread, which could intermittently blank out Claude. All bucket writes now happen on the main thread.
- **Actionable errors:** expired session key / timeout now show a specific message in the dropdown instead of silently showing no data.

### Added
- **Honest data-source tags:** every usage row is tagged by provenance — **LIVE** (Claude subscription), **LOCAL** (Antigravity logs), **API $** (real developer API spend), **MANUAL** (user estimate), **EXT** (browser extension). Shown next to each entry in the dropdown.
- **Browser-extension bridge:** the app's local server now accepts `POST /ingest` (with CORS + preflight) so the companion extension can push real web-session usage. The extension (`claude-usage-extension-main/`) reads logged-in tabs and relays via its background worker. Consolidation prefers real data, falling back to extension data.
- **OpenAI Costs API (opt-in):** ChatGPT "API spend" mode now calls the correct Costs endpoint with an Admin key, clearly labeled as developer API spend — not ChatGPT Plus message limits (which have no API).

### Changed
- **Removed fabricated "simulated" numbers.** ChatGPT/Gemini/Perplexity no longer display invented live data. Gemini and Perplexity are honest manual-estimate tiles (no consumer usage API exists); their dead "API key" modes were removed. Antigravity's limit is reframed as a user-set target (it has no vendor-enforced cap).
- **One-time migration:** on upgrade, ChatGPT/Gemini/Perplexity are switched off once (they had been enabled under the old fake-data behavior). Antigravity is untouched. Re-enable any provider afterward and it persists.

---

## [1.3.0] - 2026-05-30

### Added
- **Interactive Provider Reordering:** Added Up/Down controls to reorder tracking sources (Claude, ChatGPT, Gemini, Perplexity, Antigravity) dynamically across the Dashboard and the Menu Bar dropdown lists.
- **Help Popovers:** Integrated `(?)` buttons next to method selectors to clarify Web Session, OAuth CLI, API Key, Prepaid Balance, and Simulation modes.
- **Separated Connection & Visibility:** Relocated enablement switches from Connection tabs into the Menu Bar display pane, keeping credentials separate from visibility settings.
- **Resizable Window:** Modified the main Settings view and AppKit window style mask to fully support resizing.
- **Apple Design Language Polish:** Revamped sidebar buttons with native hover states, proper system spacing, and modern iconography (`menubar.rectangle`).
- **Build Cleanup:** Integrated automatic `pkill` termination of running app instances within the build pipeline.

---

## [1.2.0] - 2026-05-27

### Fixed
- **Widget Gallery:** Replaced deprecated `.background()` with `.containerBackground(for: .widget)` — the mandatory WidgetKit API for macOS 14 Sonoma that allows widgets to appear in the Widget Gallery.
- **Duplicate App Icons:** Cleaned up stale Launch Services registrations from test build directories causing multiple `ClaudeUsage` icons in Launchpad.
- **Build Target:** Updated compilation target to `arm64-apple-macosx14.0` for both app and widget targets, eliminating deprecation warnings.

### Added
- **Release Automation (`release.py`):** New Python script that auto-generates semantic version tags, categorizes commits by type, updates `CHANGELOG.md`, commits/pushes, and publishes GitHub releases — either via the API (with `GITHUB_TOKEN`) or by opening a pre-filled browser page.
- **Polished README:** Complete documentation overhaul with badges, feature and security tables, widget setup guide, and troubleshooting section.

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
