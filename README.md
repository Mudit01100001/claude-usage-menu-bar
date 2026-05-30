<h1 align="center">
  <br>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?style=flat-square&logo=apple&logoColor=white" alt="macOS">
  <img src="https://img.shields.io/badge/Swift-5.9-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/github/v/release/Mudit01100001/claude-usage-menu-bar?style=flat-square&color=blue" alt="Latest Release">
  <br><br>
  Claude Usage · macOS Menu Bar App
</h1>

<p align="center">
  A lightweight, native macOS status bar app that tracks your rolling <strong>Claude.ai session limits</strong> and <strong>weekly usage</strong> in real-time — with an optional desktop widget.<br>
  Built entirely in Swift (AppKit + SwiftUI + WidgetKit). Zero Xcode project files. Compiles in seconds.
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#getting-started">Getting Started</a> •
  <a href="#desktop-widget">Desktop Widget</a> •
  <a href="#security">Security</a> •
  <a href="#troubleshooting">Troubleshooting</a> •
  <a href="#changelog">Changelog</a>
</p>

---

## Features

### 🖥️ Menu Bar Status Display (4 Modes)
| Mode | Description |
|------|-------------|
| **Stacked** | Two-line display: session % on top, weekly % on bottom (like Macs Fan Control) |
| **Compact** | Single line: `S:22% W:15%` |
| **Session Only** | Minimal: just `22%` |
| **Icon Only** | A `C` icon that turns 🟢 Green → 🟠 Orange → 🔴 Red based on utilization |

### 📊 Live Progress Dropdown
Click the menu bar icon to see:
- An instant summary line: `Usage: Session 22% • Weekly 15%`
- Visual progress bars with countdown timers for each rolling window (5-Hour / 7-Day)
- **Refresh Now**, **Settings**, and **Quit** actions

### 🔐 Dual Authentication Methods
- **Claude Web Session** — Connect using your browser `sessionKey` cookie
- **Claude Code CLI** — Automatically scans your system Keychain for OAuth credentials from `claude login`

### 🧩 Native Desktop Widget (v1.1.0+)
A polished 2×2 WidgetKit widget designed in the Apple battery widget style:
- **Session Limit** ring + time remaining (left)
- **Weekly Limit** ring + time remaining (right)
- Zero-latency sync with the menu bar app via App Group shared containers

### 🔔 System Notifications
Native macOS alerts when any limit exceeds a configurable threshold (default: 80%).

### ⚙️ Smart Preferences
- Configurable refresh interval (default: 5 min)
- "Launch at Login" toggle via `ServiceManagement`
- Resizable sidebar settings panel with keyboard shortcut support (`Cmd+V`, `Cmd+C`, etc.)

---

## Getting Started

### 1. Build & Run

```bash
# Clone the repository
git clone https://github.com/Mudit01100001/claude-usage-menu-bar.git
cd "claude-usage-menu-bar"

# Build (compiles in ~2 seconds, no Xcode required)
chmod +x build.sh
./build.sh

# Launch
open ClaudeUsage.app
```

The app runs as a status-item accessory (`LSUIElement = true`) — it lives in the menu bar only, with no Dock icon.

### 2. Authentication Setup

#### Method A — Claude Web Session *(Recommended)*
1. Log in to [claude.ai](https://claude.ai) in your browser
2. Open DevTools (`F12` or `Cmd+Option+I`) → **Application** tab → **Cookies**
3. Copy the value of the `sessionKey` cookie (starts with `sk-ant-sid01-`)
4. In Settings → **Connection** → **Web Session**, paste it and click **Verify & Save**

#### Method B — Claude Code CLI
1. Run `claude login` in your terminal once
2. In Settings → **Connection** → **Claude Code CLI**, click **Scan Keychain for Claude Code**
3. When macOS prompts for your login password, click **Always Allow** (you won't be asked again)

---

## Desktop Widget

The 2×2 WidgetKit widget requires:
- macOS 14 (Sonoma) or later
- The main app to be launched at least once (registers the plugin with macOS)

**Adding the widget:**
1. Right-click your macOS desktop and choose **Edit Widgets…**
2. Search for **"Claude Usage"** in the gallery
3. Drag the **2×2 progress ring** widget to your desktop or Notification Center

Data syncs automatically whenever the menu bar app refreshes.

---

## Security Architecture

| Layer | Detail |
|-------|--------|
| **At Rest** | Credentials encrypted in macOS Keychain with `kSecAttrAccessibleAfterFirstUnlock` |
| **In Transit** | Strict HTTPS/TLS to official Anthropic endpoints only |
| **Subprocess** | `/usr/bin/security` called directly with isolated args — no shell injection risk |
| **Telemetry** | Zero. No third-party servers, analytics, or external logging. Everything stays local. |

---

## Troubleshooting

**Will it ask for my Keychain password every time?**  
No — click **"Always Allow"** on the first macOS prompt to permanently whitelist the app binary.

**Does Claude Code CLI need to be running?**  
No — the app reads the stored OAuth token. Your terminal can be fully closed.

**The widget doesn't appear in the Widget Gallery.**  

Under ad-hoc code signing (default in `build.sh` via `codesign -s -`), macOS enforces strict security restrictions on WidgetKit extensions:
1. **App Groups & Sandboxing**: Without a valid Apple Developer Account Team ID, macOS rejects App Group containers (`com.apple.security.application-groups`). The app has been updated to bypass this by running a lightweight local HTTP server (`127.0.0.1:53076`) in the menu bar app, which the widget queries directly.
2. **Widget Gallery Visibility**: Even with the App Group bypass, macOS system daemon `chronod` frequently ignores or fails to load ad-hoc signed app extensions in the Widget Gallery.

**Known Workarounds / Diagnostics:**
- Check system logs for registration errors:
  ```bash
  log show --predicate 'sender == "chronod" || process == "chronod"' --last 10m
  ```
- Force re-register and restart `chronod`:
  ```bash
  # Unregister and re-register
  pluginkit -r /Applications/ClaudeUsage.app/Contents/PlugIns/ClaudeUsageWidget.appex
  pluginkit -a /Applications/ClaudeUsage.app/Contents/PlugIns/ClaudeUsageWidget.appex
  pluginkit -e use -i com.mudit.ClaudeUsage.Widget
  
  # Restart widget daemon
  pkill -f chronod
  ```
- **Recommended Solution**: Open `build.sh`, change `-s -` to your own Apple Developer Certificate Name (e.g., `"Apple Development: your@email.com"`), restore App Group entitlements with your Team ID in the entitlements files, and rebuild. Proper developer signatures solve all Widget Gallery registration issues.

**Refresh fails / data not updating.**  
Open Settings → Connection. For web sessions, the `sessionKey` cookie expires after a few weeks — grab a fresh one from your browser. For CLI, run `claude logout && claude login`.

**Duplicate app icons in Launchpad.**  
If you've built the app from multiple directories, run:
```bash
defaults write com.apple.dock ResetLaunchPad -bool true; killall Dock
```

---

## Releasing a New Version

This repo ships with a Python release automation script:

```bash
python3 release.py
```

The script will:
1. Detect your latest git tag and suggest the next semantic version
2. Categorize commits since last release into features / fixes / polish
3. Generate a professional release notes body
4. Update `CHANGELOG.md` automatically
5. Commit, tag, push to GitHub, and open the release page (or publish via API if `GITHUB_TOKEN` is set)

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full version history. Latest releases are documented on the [Releases page](https://github.com/Mudit01100001/claude-usage-menu-bar/releases).

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with ❤️ and Claude · <a href="https://github.com/Mudit01100001/claude-usage-menu-bar/releases">View Releases</a> · <a href="https://github.com/Mudit01100001/claude-usage-menu-bar/issues">Report Issue</a>
</p>
