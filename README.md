# Claude Usage macOS Menu Bar App

A lightweight, native macOS status bar utility that tracks your rolling Claude.ai session limits and weekly usage in real-time. Built entirely with Swift using AppKit and SwiftUI, this app requires zero Xcode project bloat and compiles in seconds.

---

## Features

* **Modular Menu Bar Displays:**
  * **Stacked:** Displays both session usage (S) and weekly usage (W) vertically on two lines (similar to Macs Fan Control).
  * **Compact:** A single-line summary displaying both limits (`S:22% W:15%`).
  * **Session Only:** Displays only the session percentage (`22%`).
  * **Icon Only:** A minimal "C" icon that changes color based on utilization.
* **Dynamic Progress Dropdown:** Click the menu bar icon to see:
  * An instant summary text line.
  * Individual visual progress bars and reset countdowns for each rolling limit (5-Hour Window, 7-Day Window, etc.).
  * Direct action buttons to refresh, access Settings, or Quit.
* **Dual Authentication Methods:**
  * **Claude Web Session:** Connects using your web browser `sessionKey` cookie.
  * **Claude Code CLI:** Automatically scans the system keychain/credentials to track OAuth CLI sessions established by `claude login`.
* **Keychain Secure Storage:** Stores your keys securely in the macOS Keychain using generic password encryption. No keys are ever stored in plaintext or logged.
* **Native System Notifications:** Sends native macOS notifications when your usage exceeds a configurable alert threshold (e.g., warning at 80% limit capacity).
* **Super Lightweight:** No Xcode setup required. It uses standard Swift compilation and compiles in under 2 seconds.

---

## Getting Started

### 1. Build and Run

To compile and package the app bundle, simply run the build script in your terminal:

```bash
# Clone the repository
git clone https://github.com/your-username/claude-usage-macos.git
cd "claude-usage-macos"

# Make the build script executable and compile
chmod +x build.sh
./build.sh

# Launch the application
open ClaudeUsage.app
```

The app runs as a status-item accessory (`LSUIElement`), meaning it resides exclusively in the menu bar and does not clutter your Dock.

### 2. Configuration & Authentication

1. Click the status bar icon and choose **Settings...**.
2. Resize the sidebar as desired to navigate the panels.
3. Configure your connection method:

#### Method A: Claude Web Session (Recommended)
1. Log in to [claude.ai](https://claude.ai) in your browser.
2. Open Developer Tools (`F12` or `Cmd` + `Option` + `I`).
3. Navigate to the **Application** tab (Chrome/Brave/Arc) or **Storage** tab (Safari/Firefox) and select **Cookies**.
4. Copy the value of the `sessionKey` cookie (starts with `sk-ant-sid01-`).
5. Paste it in the Connection panel under the Web tab and click **Verify & Save**.

#### Method B: Claude Code CLI
1. Ensure you have run `claude login` in your terminal.
2. Under the Connection panel, switch to **Claude Code CLI** and click **Scan Keychain for Claude Code**.
3. macOS will prompt you with a system dialog asking for your computer login password to authorize this app to access the keychain entry. Click **Always Allow**.

---

## Security Architecture

* **At-Rest Security:** Credentials are encrypted in the macOS Keychain using hardware-backed AES keys (Secure Enclave on Apple Silicon). They are set with `kSecAttrAccessibleAfterFirstUnlock` for protection.
* **In-Transit Security:** Enforces strict HTTPS/TLS connections directly to official Anthropic endpoints (`https://claude.ai` and `https://api.anthropic.com`).
* **Subprocess Security:** Keychain querying executes `/usr/bin/security` directly as an executable with isolated argument vectors, eliminating shell command injection risks.
* **Telemetry & Privacy:** Zero third-party servers, analytics, tracking code, or external logs. Your credentials and usage statistics remain entirely local to your device.

---

## Important Notes & Troubleshooting

* **Will the app ask for my Keychain password every time?**
  * **No.** When macOS prompts you to authorize keychain access for the Claude Code credentials scan, make sure to click **"Always Allow"** (not just "Allow"). This adds the compiled app binary to the keychain item's Access Control list, so macOS will never prompt you again.
* **Does the Claude Code CLI need to be running?**
  * **No.** The app only reads the OAuth token generated when you ran `claude login` in the terminal. The CLI does not need to be active, and your terminal can be completely closed.
* **Why did the refresh fail or not update?**
  * If the app fails to retrieve data, check the Connections tab in Settings. Ensure the session is verified and not expired. For the Web Session Key, cookies typically expire after several weeks, requiring a fresh key from the browser. For the CLI, if the token is revoked, running `claude logout` followed by `claude login` in the terminal will refresh the system Keychain credentials.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
