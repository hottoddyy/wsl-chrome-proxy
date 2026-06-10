# WSL Chrome Proxy

Routes Chrome traffic through a lightweight HTTP/HTTPS proxy running inside WSL Ubuntu. A Chrome extension toggles the proxy on/off — **installs automatically, no Developer mode or admin rights required**.

## How it works

```
Chrome  →  127.0.0.1:18080  (WSL2 localhost forwarding)
        →  Python proxy inside WSL Ubuntu (0.0.0.0:18080)
        →  Internet
```

WSL2's built-in localhost forwarding exposes any port bound inside WSL at `127.0.0.1` on Windows — no `netsh portproxy` or admin rights needed.

The Chrome extension is delivered via a local CRX update server and a Chrome registry policy written to `HKCU`, so it installs silently into any Chrome profile without enabling Developer mode.

## Requirements

| | |
|---|---|
| Windows 10 (21H2+) or Windows 11 | WSL 2 required |
| WSL Ubuntu distro | Run `wsl --install -d Ubuntu` once if not set up |
| Python 3 inside Ubuntu | Included with Ubuntu 20.04+ — nothing extra to install |
| Google Chrome | Any recent version |

> Setting up WSL for the first time needs admin (once). After that, everything runs as your normal user account.

## Install

1. Download the **[latest release ZIP](../../releases/latest)** and extract it anywhere.
2. Double-click **`Install.cmd`**.
3. When complete, **restart Chrome** — the *WSL Proxy Toggle* extension appears in your toolbar automatically.

The proxy starts on login automatically from that point on.

## What the installer does

- Copies files to `%LOCALAPPDATA%\WslChromeProxy\`
- Starts a local CRX update server (port 18082) that Chrome uses to install the extension
- Writes Chrome extension policy to `HKCU` — no admin needed
- Starts the Python proxy inside WSL Ubuntu on port 18080
- Adds an autostart entry to `HKCU\Run` so the proxy comes back after reboot

No portproxy rules. No firewall changes. No admin.

## Day-to-day control

From the folder where you extracted the files (or from any CMD window if you add it to PATH):

```cmd
Proxy.cmd           start (or restart) the proxy
Proxy.cmd stop      stop everything
Proxy.cmd status    show current state
```

The Chrome extension popup also lets you toggle the proxy on/off without starting/stopping the backend.

## Uninstall

Double-click **`Uninstall.ps1`** (or run it from PowerShell). It removes the install directory, Chrome policy, and autostart entry, then asks you to restart Chrome.

## Re-packing the extension

The `.pem` file is the signing key for the CRX. It is committed to this repo so every install produces the same extension ID — the Chrome policy uses that ID. If you change extension source files, re-pack using Chrome's built-in tool:

1. Go to `chrome://extensions`
2. Enable Developer mode
3. Click *Pack extension*
4. Source folder: `chrome-extension/`
5. Private key file: `chrome-extension.pem`
6. Replace `chrome-extension.crx` in the repo with the new one

If you rotate the key, update `$extensionId` in `Install.ps1` too.
