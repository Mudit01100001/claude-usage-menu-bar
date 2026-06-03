# AI Usage Bridge — Browser Extension

A companion Chrome/Edge extension for the **Claude Usage** macOS menu bar app. It reads
AI usage from your **logged-in browser tabs** and forwards it to the app, so platforms
that only expose usage inside their own website can still appear in the menu bar.

It does two things:

1. **Bridge (automatic).** A content script runs on supported provider sites. When you
   have a logged-in tab open, it reads whatever usage that site exposes to your session
   and POSTs it to the menu bar app at `http://127.0.0.1:53076/ingest`.
2. **Badge (manual, Claude only).** The toolbar popup keeps the original Claude-token
   feature: paste a Claude OAuth token and the icon badge shows your 5‑hour usage. This
   token, when present, is also forwarded to the app.

## How it talks to the app

```
provider tab ──(content script: bridge.js)──▶ background.js ──POST──▶ 127.0.0.1:53076/ingest ──▶ menu bar app
```

The content script can't POST to `127.0.0.1` directly (the page's CSP blocks it), so it
relays the data to the background service worker, whose network access is governed by the
extension's `host_permissions` instead. The app accepts the POST (with CORS + an `OPTIONS`
preflight) and shows the provider tagged **EXT** in its dropdown.

## What actually works per platform (be realistic)

| Platform | What the bridge can read |
|----------|--------------------------|
| **Claude** | ✅ Real session + weekly % via `claude.ai`'s own API using your logged-in cookies. No token needed. |
| **ChatGPT** | ❌ Nothing reliable. OpenAI does **not** expose remaining-message counts to the web app — there is no number to read. Placeholder reader returns nothing. |
| **Gemini** | ❌ No usage feed in the page. Placeholder. |
| **Perplexity** | ❌ Usage/credits are dashboard-only and not reliably scriptable. Placeholder. |
| **Antigravity** | n/a — it's a local tool, not a website. The menu bar app tracks it directly from local logs (better than a browser could). |

The placeholders exist so adding a provider later is a small, contained change — they do
**not** invent numbers.

## Install (Developer Mode)

1. Open `chrome://extensions/`
2. Enable **Developer mode** (top right)
3. **Load unpacked** → select this `claude-usage-extension-main` folder
4. Make sure the **Claude Usage** menu bar app is running (it hosts the local endpoint)
5. Open [claude.ai](https://claude.ai) logged in — within a few seconds the app shows a
   Claude entry tagged **EXT** (check Settings → Connection → "Browser Extension Bridge"
   for the last-received timestamp)

## Adding a new provider

In `bridge.js`, add a reader to the `PROVIDERS` map keyed by hostname that returns
`{ provider, buckets: [{ name, utilization, resetsAt }] }`, then add the host to both
`matches` and `host_permissions` in `manifest.json`. No app rebuild required.

## Privacy

- Usage is sent only to your own machine (`127.0.0.1:53076`) and to each provider's own
  site (using your existing session). Nothing goes to any third party.
- The optional Claude token is stored in Chrome's local extension storage.
- Open source — inspect `bridge.js` and `background.js` yourself.

## License

MIT
