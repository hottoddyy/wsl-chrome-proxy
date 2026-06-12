# WSL Chrome Proxy

Routes Chrome traffic through a lightweight HTTP/HTTPS proxy running inside WSL Ubuntu. A Chrome extension toggles the proxy on/off — **installs automatically, no Developer mode required, admin rights are unfortunately**.

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
| Windows 10 (21H2+) or Windows 11 | |
| Google Chrome | Any recent version |

Installer handles everything else — WSL 2, Ubuntu, and Python 3 are all installed automatically if not already present.

> If WSL needs to be enabled for the first time, Windows will ask for Administrator permission for that one step. Everything else runs without admin.

## Install

1. Download **`WSLChromeProxy-Setup.exe`** from the **[latest release](../../releases/latest)**.
2. Run it. The setup wizard installs per-user with no UAC reqs.
3. If WSL needs to be set up, Windows will show a UAC prompt — accept it. The installer handles the rest.
4. **First-time WSL install only:** after Ubuntu downloads, a blue Ubuntu window opens and asks you to create a Unix username and password (pick anything — it's only used inside Ubuntu). Once you see the green `$` prompt, **type `exit` and press Enter** to close it. The installer then carries on automatically.
5. When complete, **restart Chrome** — the *WSL Proxy Toggle* extension appears in your toolbar automatically.

Release also include a script install if preferred.

The proxy starts on login automatically from that point on. If it fails to start/internet is not working, open CMD and type **proxy**. To turn off the proxy, type  **stop proxy**.

## What the installer does

| Step | Needs admin? | What happens |
|---|---|---|
| WSL + Ubuntu | Once only, if not installed | Installs WSL 2 and Ubuntu via `wsl --install` |
| Python 3 | No | Verified inside Ubuntu; installed via `apt` if missing |
| Proxy files | No | Copied to `%LOCALAPPDATA%\WslChromeProxy\` |
| Chrome extension | No | Local CRX server + `HKCU` policy — no Developer mode needed |
| WSL proxy | No | Python process started inside Ubuntu on port 18080 |
| Autostart | No | `HKCU\Run` entry restarts proxy after login |

## Day-to-day control

After install, `Proxy` is available from **any CMD window**:

```cmd
Proxy           start (or restart) the proxy
Proxy stop      stop everything
Proxy status    show current state and installed version
Proxy update    download and install the latest release from GitHub
```

The Chrome extension popup also lets you toggle the proxy on/off without touching the backend.

> The proxy runs **permanently**: it starts automatically every time you log in to Windows, so you never need to run anything by hand. `Proxy stop` only stops it until your next login — to switch it off for a single site or session, use the extension's toggle instead.

## Updating

```cmd
Proxy update
```

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
