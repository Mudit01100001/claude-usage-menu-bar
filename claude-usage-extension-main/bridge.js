// AI Usage Bridge — content script.
//
// Runs on logged-in provider tabs, reads whatever usage the site exposes to the
// current session, and relays it to the background service worker, which forwards
// it to the Claude Usage menu bar app at http://127.0.0.1:53076/ingest.
//
// Why route through the background worker? A content script's fetch is governed
// by the *page's* Content-Security-Policy, which would block a direct call to
// 127.0.0.1. The background worker's fetch is governed by the extension's
// host_permissions instead, so it can reach the local app.
//
// To add a provider: add a reader keyed by hostname below, and add the host to
// both "matches" and "host_permissions" in manifest.json. A reader returns
// { provider, buckets: [{ name, utilization, resetsAt }] } or null.

const PROVIDERS = {
  // Claude — REAL session/weekly usage via claude.ai's own API, using the page's
  // logged-in cookies. No token needed; mirrors what the Claude UI itself shows.
  "claude.ai": async () => {
    const orgs = await fetch("/api/organizations", { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null);
    const orgId = Array.isArray(orgs) && orgs[0] ? orgs[0].uuid : null;
    if (!orgId) return null;

    const usage = await fetch(`/api/organizations/${orgId}/usage`, { credentials: "include" })
      .then((r) => (r.ok ? r.json() : null))
      .catch(() => null);
    if (!usage) return null;

    const buckets = [];
    for (const [name, val] of Object.entries(usage)) {
      if (val && typeof val.utilization === "number" && typeof val.resets_at === "string") {
        buckets.push({ name, utilization: val.utilization, resetsAt: val.resets_at });
      }
    }
    return buckets.length ? { provider: "claude", buckets } : null;
  },

  // ChatGPT — OpenAI does not surface remaining-message counts to the web app,
  // so there is nothing reliable to read. Placeholder kept for structure.
  "chatgpt.com": async () => null,
  "chat.openai.com": async () => null,

  // Gemini — Google exposes no consumer usage feed in the page. Placeholder.
  "gemini.google.com": async () => null,

  // Perplexity — usage/credits are dashboard-only and not reliably scriptable.
  // Placeholder; a best-effort DOM reader could be added here later.
  "www.perplexity.ai": async () => null,
  "perplexity.ai": async () => null,
};

async function runBridge() {
  const reader = PROVIDERS[location.host];
  if (!reader) return;
  try {
    const payload = await reader();
    if (payload && Array.isArray(payload.buckets) && payload.buckets.length) {
      chrome.runtime.sendMessage({ type: "ingestUsage", payload });
    }
  } catch (e) {
    console.debug("AI Usage Bridge reader error:", e);
  }
}

// Read on load, then refresh every 5 minutes while the tab stays open.
runBridge();
setInterval(runBridge, 5 * 60 * 1000);
