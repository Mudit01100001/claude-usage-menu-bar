// Views
const views = {
  setup: document.getElementById('setup'),
  usage: document.getElementById('usage'),
  settings: document.getElementById('settings-view'),
  loading: document.getElementById('loading'),
  error: document.getElementById('error')
};

// Elements
const elements = {
  tokenInput: document.getElementById('token-input'),
  saveToken: document.getElementById('save-token'),
  fiveHour: document.getElementById('five-hour'),
  weekly: document.getElementById('weekly'),
  sonnet: document.getElementById('sonnet'),
  extra: document.getElementById('extra'),
  updated: document.getElementById('updated'),
  refresh: document.getElementById('refresh'),
  interval: document.getElementById('interval'),
  settingsBtn: document.getElementById('settings'),
  clearToken: document.getElementById('clear-token'),
  back: document.getElementById('back'),
  retry: document.getElementById('retry'),
  reauth: document.getElementById('reauth')
};

// Show a specific view
function showView(name) {
  Object.values(views).forEach(v => v.classList.add('hidden'));
  views[name].classList.remove('hidden');
}

// Format reset time
function formatReset(isoString) {
  if (!isoString) return 'N/A';

  try {
    const date = new Date(isoString);
    if (isNaN(date.getTime())) return 'N/A';

    const now = new Date();
    const diff = date - now;

    if (diff < 0) return 'now';

    const hours = Math.floor(diff / 3600000);
    const mins = Math.floor((diff % 3600000) / 60000);

    if (hours === 0) return `${mins}m`;
    if (hours < 24) return `${hours}h ${mins}m`;

    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  } catch {
    return '?';
  }
}

// Fetch usage from API
async function fetchUsage(token) {
  const response = await fetch('https://api.anthropic.com/api/oauth/usage', {
    headers: {
      'Authorization': `Bearer ${token}`,
      'anthropic-beta': 'oauth-2025-04-20',
      'User-Agent': 'claude-code/2.1.34'
    }
  });

  if (!response.ok) throw new Error('API request failed');
  return response.json();
}

// Update UI with usage data
function updateUI(data) {
  // 5-hour
  if (data.five_hour) {
    const pct = Math.round(data.five_hour.utilization);
    elements.fiveHour.textContent = `${pct}% (resets ${formatReset(data.five_hour.resets_at)})`;
    // Update badge
    chrome.action.setBadgeText({ text: `${pct}%` });
    chrome.action.setBadgeBackgroundColor({ color: pct > 80 ? '#e57373' : pct > 50 ? '#ffb74d' : '#81c784' });
  }

  // Weekly
  if (data.seven_day) {
    const pct = Math.round(data.seven_day.utilization);
    elements.weekly.textContent = `${pct}% (resets ${formatReset(data.seven_day.resets_at)})`;
  }

  // Sonnet
  if (data.seven_day_sonnet) {
    const pct = Math.round(data.seven_day_sonnet.utilization);
    elements.sonnet.textContent = `${pct}% (resets ${formatReset(data.seven_day_sonnet.resets_at)})`;
  } else {
    elements.sonnet.textContent = '--';
  }

  // Extra usage
  if (data.extra_usage && data.extra_usage.is_enabled) {
    const used = (data.extra_usage.used_credits / 100).toFixed(2);
    const limit = Math.round(data.extra_usage.monthly_limit / 100);
    const pct = Math.round(data.extra_usage.utilization);
    elements.extra.textContent = `$${used}/$${limit} (${pct}%)`;
  } else {
    elements.extra.textContent = '--';
  }

  // Updated time
  elements.updated.textContent = new Date().toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });

  showView('usage');
}

// Load and refresh data
async function loadData() {
  const { token } = await chrome.storage.local.get('token');

  if (!token) {
    showView('setup');
    return;
  }

  showView('loading');

  try {
    const data = await fetchUsage(token);
    updateUI(data);
  } catch (err) {
    console.error('Fetch error:', err);
    showView('error');
  }
}

// Save token
elements.saveToken.addEventListener('click', async () => {
  let token = elements.tokenInput.value.trim();

  // Try to parse as JSON (in case they pasted the whole credentials file)
  try {
    const parsed = JSON.parse(token);
    if (parsed.claudeAiOauth?.accessToken) {
      token = parsed.claudeAiOauth.accessToken;
    }
  } catch {
    // Not JSON, use as-is
  }

  if (!token.startsWith('sk-ant-')) {
    alert('Invalid token. Should start with sk-ant-');
    return;
  }

  await chrome.storage.local.set({ token });

  // Trigger background refresh
  chrome.runtime.sendMessage({ action: 'refresh' });

  loadData();
});

// Refresh button
elements.refresh.addEventListener('click', () => {
  chrome.runtime.sendMessage({ action: 'refresh' });
  loadData();
});

// Interval change
elements.interval.addEventListener('change', async () => {
  const interval = parseInt(elements.interval.value);
  await chrome.storage.local.set({ interval });
  chrome.runtime.sendMessage({ action: 'updateInterval', interval });
});

// Settings button
elements.settingsBtn.addEventListener('click', () => showView('settings'));

// Back button
elements.back.addEventListener('click', () => loadData());

// Clear token
elements.clearToken.addEventListener('click', async () => {
  await chrome.storage.local.remove('token');
  chrome.action.setBadgeText({ text: '' });
  showView('setup');
});

// Retry
elements.retry.addEventListener('click', () => loadData());

// Re-auth
elements.reauth.addEventListener('click', async () => {
  await chrome.storage.local.remove('token');
  showView('setup');
});

// Load saved interval
chrome.storage.local.get('interval').then(({ interval }) => {
  if (interval) {
    elements.interval.value = interval.toString();
  }
});

// Initial load
loadData();
