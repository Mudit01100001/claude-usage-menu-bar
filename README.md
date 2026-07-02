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
  A lightweight, native macOS status bar app that tracks your rolling <strong>Claude.ai session limits</strong> and <strong>weekly usage</strong> in real-time.<br>
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

### 🧩 Native Desktop Widget (Coming Soon)
A polished 2×2 WidgetKit widget designed in the Apple battery widget style — **Session Limit** ring + time remaining on the left, **Weekly Limit** ring + time remaining on the right. The code is built and ready ([ClaudeUsageWidget.swift](ClaudeUsageWidget.swift)), but macOS won't register a WidgetKit extension in the Widget Gallery unless it's signed with a paid Apple Developer ID and notarized — see [Desktop Widget](#desktop-widget) below.

### 🔔 System Notifications
- Threshold alerts when any limit exceeds a configurable percentage (default: 80%)
- Reset alerts when your 5-hour session or 7-day weekly window actually rolls over, based on the server-reported reset time — not just a menu bar color change

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

**Status: Coming Soon — not available in the default build.**

The widget's code is fully implemented ([ClaudeUsageWidget.swift](ClaudeUsageWidget.swift)) and compiles as part of `build.sh`, but macOS will not list it in the Widget Gallery under the ad-hoc code signing this repo ships with. This isn't a bug to work around — it's an intentional macOS security policy: `chronod` (the system service that manages the Widget Gallery) only registers a WidgetKit extension if the containing app is either running under Xcode's debugger, or signed with a paid **Apple Developer ID** certificate and **notarized** by Apple. A free personal-team certificate isn't enough, and macOS 15+ removed the CLI workarounds that used to paper over this. See [Troubleshooting](#troubleshooting) for the full diagnosis if you're curious.

This will be revisited once the project can justify the $99/year Apple Developer Program membership required for a Developer ID certificate + notarization — at that point it's purely a signing/distribution change, no code changes needed.

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

This is expected under the default ad-hoc code signing (`codesign -s -`) — see [Desktop Widget](#desktop-widget) above. In short: `chronod` (the system service behind the Widget Gallery) refuses to register a WidgetKit extension unless the containing app is signed with a paid Apple Developer ID and notarized, or is actively running under Xcode's debugger. Two things were tried and ruled out, in case you're investigating this yourself:
1. **App Groups & Sandboxing**: Without a valid Apple Developer Account Team ID, macOS rejects App Group containers (`com.apple.security.application-groups`), so the app bypasses this with a lightweight local HTTP server (`127.0.0.1:53076`) in the menu bar app, which the widget queries directly. This part works fine on its own.
2. **Signing with a free "Apple Development" personal-team certificate instead of ad-hoc** was tested directly and still failed — `chronod` logs `LS doesn't have a containing bundle` and `spctl -a` reports the app as Gatekeeper-`rejected`. On macOS 15+, the old `spctl --add` CLI workaround to manually whitelist it was also removed by Apple. There is no remaining free/local fix; it requires a paid Developer ID certificate + notarization.

If you want to poke at the diagnostics yourself:
```bash
# Check system logs for registration errors
log show --predicate 'sender == "chronod" || process == "chronod"' --last 10m

# Force re-register the extension
pluginkit -r /Applications/ClaudeUsage.app/Contents/PlugIns/ClaudeUsageWidget.appex
pluginkit -a /Applications/ClaudeUsage.app/Contents/PlugIns/ClaudeUsageWidget.appex
```

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
