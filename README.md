# CS 1.6 Deathmatch Server Setup

One PowerShell script that installs and configures a complete **Counter-Strike 1.6 deathmatch server** on Windows: HLDS, Metamod-P, AMX Mod X, CSDM, and working bots.

Built while fighting through every one of the failure modes listed in [Troubleshooting](#troubleshooting) — the script exists so you don't have to.

```powershell
cd C:\hlds
Unblock-File .\Setup-CsDeathmatch.ps1
powershell -ExecutionPolicy Bypass -File .\Setup-CsDeathmatch.ps1 -RconPassword 'yourPassword'
```

Run it from an **Administrator** PowerShell — see [Running the script](#running-the-script) if Windows blocks it.

## What it does

| Step | Component | Notes |
|------|-----------|-------|
| 1 | SteamCMD | Downloaded and unpacked if missing |
| 2 | HLDS + Counter-Strike (app 90) | Retries up to 3× — partial downloads are a known SteamCMD bug |
| 3 | Cleanup | Removes files misplaced by earlier manual attempts |
| 4 | Metamod-P 1.21p37 | Plus a fix for its `plugins.ini` path lookup |
| 5 | AMX Mod X 1.10 | **Both** the base and cstrike packages |
| 6 | CSDM 2.1.3d | From a local zip — see [CSDM](#csdm-is-the-one-manual-step) |
| 7 | YaPB | Bots that actually work on a dedicated server |
| 8 | Configuration | `liblist.gam`, `plugins.ini`, `csdm.cfg`, `server.cfg` |
| 9 | Firewall | Inbound UDP rule for the server port |
| 10 | Launch | Plus a reusable `start-server.bat` |

The script is idempotent — every step checks whether its files are already in place, so re-running it is safe. Pass `-Force` to redo downloads and extractions.

## Requirements

- Windows 10/11 (64-bit is fine — HLDS is a 32-bit app, so all its DLLs are `win32` builds)
- PowerShell 5.1+
- Administrator, for the firewall rule only
- ~1 GB disk, plus a Steam copy of CS 1.6 for anyone connecting from the internet

## Running the script

Windows blocks downloaded scripts by default, so you may hit this:

```
File ...\Setup-CsDeathmatch.ps1 cannot be loaded. The file is not digitally signed.
You cannot run this script on the current system.
```

That's the execution policy, not a problem with the script. Two steps:

```powershell
# 1. Clear the "downloaded from the internet" mark
Unblock-File .\Setup-CsDeathmatch.ps1

# 2. Run it in a process that bypasses the policy
powershell -ExecutionPolicy Bypass -File .\Setup-CsDeathmatch.ps1 -RconPassword 'yourPassword'
```

This affects only that one process, nothing system-wide.

`Set-ExecutionPolicy -Scope Process Bypass` is the more commonly suggested fix, but under an `AllSigned` policy that command can itself be blocked, so the `-File` form above is more reliable. Check what you're on with `Get-ExecutionPolicy -List`.

To change it permanently instead, run this in an Administrator window — local scripts then run freely, while downloaded ones still need `Unblock-File`:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

> **Read any script before you bypass a security control for it.** That policy exists to stop you running something you haven't looked at, and a README telling you to work around it is exactly the pattern a malicious script would use. This one is a single readable file — [open it](Setup-CsDeathmatch.ps1) and check what it does first. Apply the same rule to the next repo that tells you to pipe something into PowerShell.

What this script does that's worth knowing about:

- Downloads and extracts binaries from third parties (Valve, AlliedModders, jeefo, jkivilin) and runs SteamCMD
- Writes to `C:\hlds`, `C:\steamcmd`, and `%TEMP%`, and overwrites `liblist.gam`, `plugins.ini`, `csdm.cfg` and `server.cfg` (`liblist.gam` is backed up to `.bak`)
- Adds an inbound firewall rule for UDP 27015
- Starts `hlds.exe`

It doesn't touch anything outside those paths, and it deletes nothing except stray files under `cstrike\addons\`.

## Security

A game server is a program on your machine listening for traffic from strangers, so:

- **Set a real `-RconPassword`.** RCON is full remote control of the server. The default is a placeholder, and the script will happily run with it.
- **Port forwarding exposes that port to the entire internet**, not just your friends. Close the forward when you're not playing, or use a virtual LAN instead (see [Connecting](#connecting)).
- **HLDS and these plugins are old, unmaintained code** with known vulnerabilities. Fine for a private game with friends; don't run it on a machine holding anything you care about, and don't leave it running unattended.
- `sv_password` in `server.cfg` is worth setting if the server is reachable from the internet — otherwise anyone who finds the IP can join.

## Usage

```powershell
# Standard install
.\Setup-CsDeathmatch.ps1 -RconPassword 'secret'

# If CSDM crashes on team select: reinstall HLDS from the pre-anniversary branch
.\Setup-CsDeathmatch.ps1 -LegacyBuild -Force

# Reconfigure an existing install without touching HLDS
.\Setup-CsDeathmatch.ps1 -SkipHlds -NoStart
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Root` | `C:\hlds` | Server install directory |
| `-SteamCmdDir` | `C:\steamcmd` | SteamCMD directory |
| `-CsdmZip` | `~\Downloads\csdm_2.1.3d_KWo.zip` | Path to the CSDM archive |
| `-AmxxVersion` | `1.10.0-git5483` | AMX Mod X build |
| `-ServerName` | `Stav's Deathmatch` | `hostname` |
| `-RconPassword` | `CHANGE_ME` | **Change this.** Anyone with it controls the server |
| `-Map` | `de_dust2` | Starting map |
| `-Port` | `27015` | UDP port |
| `-MaxPlayers` | `16` | Slot count |
| `-BotQuota` | `6` | YaPB bots (0 to disable) |
| `-LegacyBuild` | off | Install the pre-25th-anniversary HLDS build |
| `-Force` | off | Re-download and re-extract everything |
| `-SkipHlds` | off | Skip SteamCMD and HLDS |
| `-NoStart` | off | Configure only, don't launch |

## CSDM is the one manual step

CSDM is hosted on the AlliedModders forums behind a login, so it can't be fetched automatically. Download **CSDM 2.1.3d (KWo)** from [the forum thread](https://forums.alliedmods.net/showthread.php?p=403419), then either drop it in your Downloads folder or point at it:

```powershell
.\Setup-CsDeathmatch.ps1 -CsdmZip 'D:\stuff\csdm_2.1.3d_KWo.zip'
```

Use 2.1.3d rather than the older 2.1.2. 2.1.3b restored CSDM after the February 2013 Steam update, and 2.1.3d fixed the client-command restrictions Valve added in 2014. Version 2.1.2 predates both and will crash the server.

## Connecting

Run these in the **game** console (`~`):

| Who | Command |
|-----|---------|
| You, same machine | `connect 127.0.0.1:27015` |
| Friend, same LAN | `connect <your-lan-ip>:27015` |
| Friend, internet | `connect <your-public-ip>:27015` |

The script prints your LAN IP when it finishes.

For internet play, forward **UDP 27015** to your machine on the router, and reserve its LAN IP (DHCP reservation) so the forward doesn't break.

**If port forwarding does nothing, check for CGNAT.** Compare the WAN address in your router's UI against [whatismyip.com](https://www.whatismyip.com). If they differ, or the WAN address is in `100.64.0.0/10`, your ISP is sharing a public IP and no forwarding rule will work. Options: use a virtual LAN ([ZeroTier](https://www.zerotier.com), [Tailscale](https://tailscale.com), Radmin VPN) and set `sv_lan 1`; ask your ISP for a public IP; or rent a cheap VPS.

## Verifying it works

In the **server** console window:

```
meta list       # AMX Mod X, CSDM and YaPB should all be RUN
amxx plugins    # the csdm_* plugins should be running
```

In game: die, and you should respawn within a second with a weapon menu.

## Troubleshooting

**`cannot be loaded. The file is not digitally signed`** — the execution policy blocking a downloaded script. See [Running the script](#running-the-script).

**`X is not recognized as a cmdlet`** — PowerShell doesn't run programs from the current directory. Use `.\hlds.exe`, not `hlds.exe`.

**`LoadLibrary failed on <garbage> (126)`** — `liblist.gam` is broken. Usually it was saved as UTF-16 (which is what `Set-Content` does by default in Windows PowerShell 5.1) or contains smart quotes pasted from a chat or Word. Save as ANSI with straight quotes.

**`meta list` shows `0 plugins`** — Metamod isn't reading `plugins.ini`. Either it's missing, named `plugins.ini.txt`, or Metamod is resolving the path relative to the working directory instead of `cstrike\`. The script handles the last case by writing an absolute `plugins_file` into `config.ini` and mirroring the file where Metamod looks.

**Server crashes when a player picks a team** — almost always CSDM. Confirm by commenting out every line in `configs/plugins-csdm.ini` with `;`; if the crash stops, CSDM is the cause. Fix by upgrading to 2.1.3d and AMX Mod X 1.10. If it still crashes, run with `-LegacyBuild`: the 25th-anniversary HLDS build broke most 1.6 plugins, and the `steam_legacy` branch is what they were compiled against.

**No bots, and `bot_add` / `bot_quota` do nothing** — this is expected. Valve's built-in CS bots are disabled on dedicated servers; they only work on a listen server ("New Game"). You need a server-side bot, which is why this script installs YaPB. Control it with `yb_quota`, `yb_difficulty` and the `yb` menu. YaPB fetches its own waypoints, so no manual nav files.

**Files extracted to the wrong place** — a recurring theme. AMX Mod X archives contain an `addons\` folder and extract into `cstrike\`; the CSDM archive contains bare `modules\`, `plugins\` and `configs\` folders and extracts into `cstrike\addons\amxmodx\`. Getting this backwards leaves you with `cstrike\addons\modules\`, which nothing loads. The script detects the layout and copies accordingly.

## Load order

Useful when something silently doesn't load — each layer only gets reached if the one above it worked:

```
hlds.exe
  └─ liblist.gam            gamedll -> metamod.dll
       └─ metamod
            └─ plugins.ini  -> amxmodx_mm.dll, yapb.dll
                 └─ AMX Mod X
                      └─ configs/plugins-csdm.ini -> csdm_*.amxx
                           └─ configs/csdm.cfg
```

## Credits

The script only automates existing work by other people:

- [Metamod-P](https://github.com/jkivilin/metamod-p) — Jussi Kivilinna, after Will Day's Metamod
- [AMX Mod X](https://www.amxmodx.org) — AlliedModders
- [CSDM](https://forums.alliedmods.net/showthread.php?p=403419) — BAILOPAN, with the 2.1.3 fixes by KWo
- [YaPB](https://github.com/yapb/yapb) — jeefo
- [ReDeathmatch](https://github.com/ReDeathmatch/ReDeathmatch_AMXX) — the modern ReHLDS-based alternative, if you outgrow CSDM

## License

MIT, for the script in this repo. The components it downloads carry their own licenses.
