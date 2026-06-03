// Background service worker for Claude Usage Tracker

const ALARM_NAME = 'refresh-usage';
const DEFAULT_INTERVAL = 5; // minutes

// Fetch usage from API
async function fetchUsage() {
  const { token } = await chrome.storage.local.get('token');
  if (!token) {
    chrome.action.setBadgeText({ text: '' });
    return null;
  }

  try {
    const response = await fetch('https://api.anthropic.com/api/oauth/usage', {
      headers: {
        'Authorization': `Bearer ${token}`,
        'anthropic-beta': 'oauth-2025-04-20',
        'User-Agent': 'claude-code/2.1.34'
      }
    });

    if (!response.ok) {
      chrome.action.setBadgeText({ text: '!' });
      chrome.action.setBadgeBackgroundColor({ color: '#e57373' });
      return null;
    }

    const data = await response.json();

    // Update badge with 5-hour usage
    if (data.five_hour) {
      const pct = Math.round(data.five_hour.utilization);
      chrome.action.setBadgeText({ text: `${pct}%` });

      // Color based on usage level
      if (pct > 80) {
        chrome.action.setBadgeBackgroundColor({ color: '#e57373' }); // Red
      } else if (pct > 50) {
        chrome.action.setBadgeBackgroundColor({ color: '#ffb74d' }); // Orange
      } else {
        chrome.action.setBadgeBackgroundColor({ color: '#81c784' }); // Green
      }
    }

    // Store last fetch time
    await chrome.storage.local.set({ lastFetch: Date.now() });

    // Forward to the menu bar app (no-op if the app isn't running).
    postToApp('claude', claudeBucketsFromUsage(data));

    return data;
  } catch (err) {
    console.error('Fetch error:', err);
    chrome.action.setBadgeText({ text: '!' });
    chrome.action.setBadgeBackgroundColor({ color: '#e57373' });
    return null;
  }
}

// Set up alarm for periodic refresh
async function setupAlarm() {
  const { interval } = await chrome.storage.local.get('interval');
  const minutes = interval ? interval / 60 : DEFAULT_INTERVAL;

  // Clear existing alarm
  await chrome.alarms.clear(ALARM_NAME);

  // Create new alarm
  chrome.alarms.create(ALARM_NAME, {
    periodInMinutes: minutes
  });

  console.log(`Alarm set for every ${minutes} minutes`);
}

// Handle alarm
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === ALARM_NAME) {
    fetchUsage();
  }
});

// Handle messages from popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === 'refresh') {
    fetchUsage();
  } else if (message.action === 'updateInterval') {
    setupAlarm();
  }
});

// Initialize on install/update
chrome.runtime.onInstalled.addListener(() => {
  setupAlarm();
  fetchUsage();
});

// Initialize on startup
chrome.runtime.onStartup.addListener(() => {
  setupAlarm();
  fetchUsage();
});

// Initial fetch when service worker starts
setupAlarm();
fetchUsage();

// --- AI Usage Bridge: forward usage to the Claude Usage menu bar app ---
const APP_INGEST_URL = 'http://127.0.0.1:53076/ingest';

async function postToApp(provider, buckets) {
  if (!buckets || !buckets.length) return;
  try {
    await fetch(APP_INGEST_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ provider, buckets })
    });
  } catch (err) {
    console.debug('Ingest POST failed (is the menu bar app running?):', err);
  }
}

// Convert the Anthropic usage JSON into the app's bucket shape.
function claudeBucketsFromUsage(data) {
  const out = [];
  for (const [name, val] of Object.entries(data || {})) {
    if (val && typeof val.utilization === 'number' && typeof val.resets_at === 'string') {
      out.push({ name, utilization: val.utilization, resetsAt: val.resets_at });
    }
  }
  return out;
}

// Relay usage that content scripts read from logged-in provider tabs.
chrome.runtime.onMessage.addListener((message) => {
  if (message && message.type === 'ingestUsage' && message.payload) {
    postToApp(message.payload.provider, message.payload.buckets);
  }
});
