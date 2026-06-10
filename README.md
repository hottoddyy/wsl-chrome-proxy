# WSL Chrome Proxy

Routes Chrome traffic through a lightweight HTTP/HTTPS proxy running inside WSL Ubuntu. A Chrome extension toggles the proxy on/off and installs automatically — **no Chrome Developer mode required**.

## How it works

```
Chrome → 127.0.0.1:18080 (Windows portproxy)
       → WSL Ubuntu IP:18081 (Python HTTP/HTTPS proxy)
       → Internet
```

- **Chrome extension** — sets Chrome's proxy to `127.0.0.1:18080` and lets you toggle it from the toolbar.
- **Windows connector** — `netsh portproxy` forwards `127.0.0.1:18080` to the WSL Ubuntu IP.
- **WSL proxy** — a small Python script (`wsl/local-http-proxy.py`) handles HTTP and HTTPS CONNECT inside Ubuntu.
- **Force-install** — the extension is delivered via a local Chrome update server and a registry policy so it installs on any Chrome profile without Developer mode.

## Prerequisites

| Requirement | Notes |
|---|---|
| Windows 10 (21H2+) or Windows 11 | WSL 2 required |
| WSL 2 with Ubuntu | Run `wsl --install -d Ubuntu` if not set up yet |
| Python 3 in Ubuntu | Ships with Ubuntu 20.04+ — no extra install needed |
| Google Chrome | Any recent version |

> If WSL features are not yet enabled, `install-all.ps1` will enable them and tell you to reboot, then run it again.

## Quick install

1. **Download** the [latest release ZIP](../../releases/latest) and extract it.
2. Open **PowerShell as Administrator**.
3. Navigate to the extracted folder and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-all.ps1
```

4. If Windows asks for a reboot (first-time WSL setup), reboot then run the same command again.
5. **Restart Chrome** — the *WSL Proxy Toggle* extension will appear in your toolbar automatically.

That's it. Open a new CMD window and type `WSL` to start the proxy, or use:

```cmd
WSL status
WSL stop
```

## What the installer does

| Step | Script | What it does |
|---|---|---|
| 1 | `install-wsl-windows-features.ps1` | Enables WSL + Virtual Machine Platform (skipped if already enabled) |
| 2 | `install.ps1` | Copies `WSL.cmd` to `%USERPROFILE%\bin` and adds it to your PATH |
| 3 | `install-cmd-alias.ps1` | Adds a `doskey` alias so CMD finds `WSL` immediately in new windows |
| 4 | `force-install-chrome-extension.ps1` | Starts the local CRX update server, writes Chrome registry policy |
| 5 | `scripts\wsl-proxy.ps1 -Start` | Starts the Ubuntu proxy and sets up the Windows portproxy |

## WSL command

```cmd
WSL                          start (or restart) the proxy
WSL status                   show connector state
WSL stop                     stop the proxy and remove the portproxy rule
WSL -ProxyPort 18081         override the WSL-side port
WSL -ListenPort 18080        override the Windows listen port
WSL -Distro Ubuntu           choose a different WSL distro
```

## Extension without the installer

If you only want the Chrome extension (and will set up the proxy yourself):

**No Developer mode needed** — run `force-install-chrome-extension.ps1` from an elevated PowerShell, then restart Chrome.

**With Developer mode** — go to `chrome://extensions`, enable Developer mode, click *Load unpacked*, and select the `chrome-extension` folder from this repo.

## Logs and state

All connector state, PID files, and logs are written to:

```
%LOCALAPPDATA%\WslChromeProxy\
```

## Build the distributable ZIP

```powershell
.\make-zip.ps1
```

Produces `wsl-chrome-proxy-installer.zip` in the parent folder, ready to hand to someone else.

## Re-packing the extension

The `.pem` file is the signing key for the CRX. It is committed to this repo so the extension ID stays consistent across installs — the Chrome policy uses the ID derived from that key. If you rotate the key, update the extension ID in `force-install-chrome-extension.ps1` too.

To re-pack after changing extension source files, use Chrome's *Pack extension* tool (`chrome://extensions` → *Pack extension* → point at the `chrome-extension` folder and the `chrome-extension.pem` key file).
