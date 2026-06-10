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
| Windows 10 (21H2+) or Windows 11 | |
| Google Chrome | Any recent version |

That's it. The installer handles everything else — WSL 2, Ubuntu, and Python 3 are all installed automatically if not already present.

> If WSL needs to be enabled for the first time, Windows will ask for Administrator permission for that one step. Everything else runs without admin.

## Install

1. Download the **[latest release ZIP](../../releases/latest)** and extract it anywhere.
2. Double-click **`Install.cmd`**.
3. If WSL needs to be set up, Windows will show a UAC prompt — accept it. The installer handles the rest.
4. If Windows needs to reboot to finish enabling WSL, it will say so. Reboot, then run `Install.cmd` again.
5. When complete, **restart Chrome** — the *WSL Proxy Toggle* extension appears in your toolbar automatically.

The proxy starts on login automatically from that point on.

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

## Updating

```cmd
Proxy update
```

That's it. The command fetches the latest release ZIP from GitHub, extracts it, and re-runs the installer in-place. No duplicate installs — everything always lives in `%LOCALAPPDATA%\WslChromeProxy\`.

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
