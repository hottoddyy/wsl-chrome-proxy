const DEFAULTS = {
  enabled: true
};

const fields = {
  enabled: document.querySelector("#enabled"),
  status: document.querySelector("#status")
};

function getSettings() {
  return new Promise((resolve) => {
    chrome.storage.sync.get(DEFAULTS, (items) => resolve(items));
  });
}

async function load() {
  const settings = await getSettings();
  fields.enabled.checked = Boolean(settings.enabled);
  fields.status.textContent = settings.enabled ? "Proxy enabled." : "Proxy disabled.";
}

async function save() {
  const settings = {
    enabled: fields.enabled.checked
  };

  await chrome.storage.sync.set(settings);
  chrome.runtime.sendMessage({ type: "applyProxy" }, () => {
    fields.status.textContent = settings.enabled ? "Proxy enabled." : "Proxy disabled.";
  });
}

fields.enabled.addEventListener("change", save);
load();
