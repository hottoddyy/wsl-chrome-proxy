const DEFAULTS = {
  enabled: true
};

const PROXY = {
  scheme: "http",
  host: "127.0.0.1",
  port: 18080,
  bypassList: ["<local>", "localhost", "127.0.0.1"]
};

async function getSettings() {
  return new Promise((resolve) => {
    chrome.storage.sync.get(DEFAULTS, (items) => resolve(items));
  });
}

async function setBadge(enabled) {
  await chrome.action.setBadgeText({ text: enabled ? "ON" : "" });
  await chrome.action.setBadgeBackgroundColor({ color: enabled ? "#15803d" : "#6b7280" });
}

async function applyProxy() {
  const settings = await getSettings();

  if (!settings.enabled) {
    await chrome.proxy.settings.clear({ scope: "regular" });
    await setBadge(false);
    return;
  }

  const config = {
    mode: "fixed_servers",
    rules: {
      singleProxy: {
        scheme: PROXY.scheme,
        host: PROXY.host,
        port: PROXY.port
      },
      bypassList: PROXY.bypassList
    }
  };

  await chrome.proxy.settings.set({
    value: config,
    scope: "regular"
  });

  await setBadge(true);
}

chrome.runtime.onInstalled.addListener(async () => {
  await chrome.storage.sync.set(DEFAULTS);
  await applyProxy();
});

chrome.runtime.onStartup.addListener(applyProxy);

chrome.storage.onChanged.addListener((changes, area) => {
  if (area === "sync" && "enabled" in changes) {
    applyProxy();
  }
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "applyProxy") {
    applyProxy().then(() => sendResponse({ ok: true }));
    return true;
  }

  return false;
});
