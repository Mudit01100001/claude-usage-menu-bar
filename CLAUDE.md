# Claude Usage — macOS Menu Bar App · CLAUDE.md

_Project memory for Claude Code. Auto-loaded each session. Has no runtime effect on the app._

## What this is

A native **Swift macOS menu-bar app** that tracks AI usage. Originally Claude-only; now a
multi-source tracker. Built with AppKit + SwiftUI + WidgetKit, **no Xcode project** — a
plain `swiftc` build via `build.sh` (~2s). Runs as a menu-bar accessory (`LSUIElement`):
**no Dock icon, no window** — it's the "C" icon in the macOS menu bar. Click it for the
dropdown; **Settings…** opens the only window.

- **GitHub:** https://github.com/Mudit01100001/claude-usage-menu-bar
- **Repo lives at:** `/Users/mudit/Developer/ANTIGRAVITY/01. CLAUDE USAGE MENU BAR MAC APP`
  (the `ANTIGRAVITY` folder is just where it's stored; it is **not** opened "in" the
  Antigravity IDE — it's a standalone compiled app).

## Build & run

```bash
./build.sh                 # compiles ClaudeUsage.app, ad-hoc signs, pkills running instance
open ClaudeUsage.app       # launch — then look at the menu bar (top-right), not the Dock
```

`build.sh` compiles `KeychainHelper.swift AppState.swift SettingsView.swift main.swift`
into one binary, builds the `.app` bundle, compiles the widget, and ad-hoc signs (`-s -`).
`set -e`, so any compile error aborts. `ClaudeUsage` and `ClaudeUsage.app/` are gitignored.

## The one architectural truth (don't re-litigate this)

**Only Anthropic exposes real consumer *subscription* usage** (the 5-hour session % /
7-day % shown in the Claude UI) to a logged-in session. Everyone else does **not**:

| Provider | What's actually available | How this app handles it |
|----------|---------------------------|--------------------------|
| **Claude** | Real session/weekly % via `claude.ai/api/.../usage` (web cookie) or `api.anthropic.com/api/oauth/usage` (Claude Code token) | `live_subscription` — the real, primary feature |
| **ChatGPT** | NO subscription-usage API. Only developer **API $-spend** via the Costs API (needs an Admin key `sk-admin-…`) | `live_api_cost` (opt-in) or `manual` |
| **Gemini** | NO consumer usage API (quota lives in Cloud Console) | `manual` estimate only |
| **Perplexity** | Usage/credits are dashboard-only | `manual` estimate only |
| **Antigravity** | Local logs at `~/.gemini/antigravity/brain/*/.system_generated/logs/transcript.jsonl` (count `USER_INPUT`) | `live_local` — real local activity; the limit is a user **target**, not a cap |

Every `UsageBucket` carries a `source` tag, surfaced in the dropdown as
**LIVE / LOCAL / API $ / MANUAL / EXT**. **Never present a manual/estimated number as if
it were live.** There is no honest way to make ChatGPT/Gemini/Perplexity behave like
Claude — don't add fake "simulated" live data.

## Multi-source design

- `AppState.refreshUsage()` fans out to per-provider `refresh*Usage()` (DispatchGroup),
  each writing its private `*Buckets` **on the main thread**, then `consolidateBuckets()`.
- `resolvedBuckets(direct:provider:)` precedence: real direct data > extension-pushed data
  > manual direct data. So Claude's direct path wins; web-only providers can be fed by the
  extension; manual is the last resort.
- **Browser-extension bridge:** `LocalUsageServer` (in `AppState.swift`) runs an HTTP
  server on `127.0.0.1:53076`. `GET /` returns widget JSON; **`POST /ingest`** accepts
  `{provider, buckets:[{name,utilization,resetsAt}]}` from the extension (with CORS +
  `OPTIONS` preflight) → `ingestExtensionUsage()` → tagged `extension`. The extension
  (`claude-usage-extension-main/`) reads logged-in tabs and relays via its background
  worker (a content script can't reach localhost directly — page CSP blocks it).

## Key files

```
AppState.swift      — model: per-provider fetch, consolidation, LocalUsageServer, migration
main.swift          — AppDelegate, menu-bar rendering, dropdown (ProgressMenuItemView), polling
SettingsView.swift  — SwiftUI settings: Dashboard / Connection / Menu Bar / Settings tabs
KeychainHelper.swift— Keychain + Claude Code credential scan/refresh
ClaudeUsageWidget.swift — 2x2 WidgetKit widget (reads via App Group / local server)
build.sh, release.py
claude-usage-extension-main/ — browser-extension bridge (manifest, bridge.js, background.js)
```

## Gotchas / history

- **The 5s-timeout regression:** the multi-provider commit set `timeoutInterval = 5.0` on
  every request; Claude web makes two sequential calls and silently blanked to `--%`. Now
  `15.0`. Don't tighten it.
- **Off-main bucket writes** caused intermittent blank Claude — keep all `*Buckets` writes
  on `DispatchQueue.main`.
- **UserDefaults migration:** `runHonestyMigrationIfNeeded()` (flag `honestMigrationV1Done`)
  disabled ChatGPT/Gemini/Perplexity once for upgrading users who had enabled them under
  the old fake-data regime. "Default off" only affects fresh installs — saved prefs win.
- **Widget under ad-hoc signing:** `chronod` often won't show ad-hoc-signed widgets in the
  gallery; the local HTTP server exists to bypass App Group Team-ID requirements. Proper
  Developer signing fixes it (see README troubleshooting).
- **Versioning:** git tags are the source of truth (`v1.0.0`…). Keep `Info.plist`
  `CFBundleShortVersionString` in sync when releasing.

## Releasing

Tag + GitHub release. `release.py` automates it, or manually:
`git tag vX.Y.Z && git push origin vX.Y.Z && gh release create vX.Y.Z --notes "…"`.
Update `CHANGELOG.md` and bump `Info.plist` version to match.

## Working agreement

After any change, run `./build.sh` and fix all errors before considering it done. Keep the
honesty model intact (source tags, no fake live data). Commit/push only when asked.
