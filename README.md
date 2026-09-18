# CS 1.6 Deathmatch Server Setup

One PowerShell script that installs and configures a complete **Counter-Strike 1.6 deathmatch server** on Windows: HLDS, Metamod, AMX Mod X, a deathmatch mod, and working bots. A second script upgrades it to the modern ReHLDS stack when the classic one won't load on current builds.

**Easiest way in: double-click `Start-Here.cmd`.** It asks for administrator rights, unblocks the scripts, bypasses the execution policy, and gives you a menu — full install, mode selection, start server, diagnose. No commands to type.

| Script | Purpose |
|---|---|
| `Start-Here.cmd` | Menu launcher — handles admin rights, unblocking and execution policy |
| `Setup-CsDeathmatch.ps1` | Full install: HLDS, Metamod-P, AMX Mod X, CSDM, YaPB |
| `Setup-ReDeathmatch.ps1` | Swap CSDM for the maintained ReHLDS + ReDeathmatch stack |
| `Setup-Normal.cmd` / `Setup-Headshot.cmd` | One-click mode presets |
| `Diagnose-CsServer.ps1` | Read-only report of what's installed, wired and logged |

Everything below is the manual equivalent, for when you want control over the parameters.

Built while fighting through every one of the failure modes listed in [Troubleshooting](#troubleshooting) — the scripts exist so you don't have to.

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

## Two stacks

This repo has scripts for both, and which you need depends on your HLDS build.

| | `Setup-CsDeathmatch.ps1` | `Setup-ReDeathmatch.ps1` |
|---|---|---|
| Deathmatch | CSDM 2.1.3d (2013) | ReDeathmatch (maintained) |
| Engine | stock HLDS | ReHLDS |
| Game logic | stock `mp.dll` | ReGameDLL_CS |
| Metamod | Metamod-P | Metamod-r |
| AMX Mod X | 1.10 | 1.10 + ReAPI |
| Works on the 25th-anniversary build | often not | yes |

**Start with `Setup-CsDeathmatch.ps1`** — it installs HLDS, AMX Mod X and YaPB, which both stacks need. If CSDM then refuses to load (see [Troubleshooting](#troubleshooting)), run `Setup-ReDeathmatch.ps1` on top; it removes CSDM and swaps in the modern components.

On a current HLDS build you will probably end up on the second one. CSDM has been unmaintained since around 2014 and no longer matches either current HLDS builds or the AMX Mod X module interface.

```powershell
powershell -ExecutionPolicy Bypass -File .\Setup-ReDeathmatch.ps1 -RconPassword 'secret'
```

Defaults: free-for-all, 15 bots, weapon menu on spawn, no bomb, nothing left on the ground, locked to one map. Use `-TeamDeathmatch` for TDM, `-BotQuota N` for a different bot count.

Its settings live in `addons\amxmodx\configs\redm\gamemode_deathmatch.json` — `equip.primary` and `equip.secondary` control the weapon menu, `botEquip` controls what bots get (only famas and galil by default), and the `cvars` block holds the gameplay rules.

## Performance

Bots have no network connection, so their scoreboard ping is a number YaPB makes up (`yb_ping_base_min` / `yb_ping_base_max`). More bots cost **CPU**, not bandwidth. The Half-Life engine is single-threaded, so when it can't keep up, real players feel it as lag.

Diagnose before changing anything:

- **Server console, top-left FPS counter.** 500–1000 is healthy with `sys_ticrate 1000`; drifting toward 100 means CPU-bound. `stats` shows per-frame CPU.
- **`net_graph 3` on a client.** *Choke* means rate settings; *loss* means the network; neither, but jerky, means server frame time.

| Symptom | Fix |
|---|---|
| Low server FPS | Lower `yb_quota`; High performance power plan; raise `hlds.exe` priority; close heavy apps |
| Choke | Server: `sv_maxrate 100000`, `sv_maxupdaterate 101`. Client: `rate 100000`, `cl_updaterate 101`, `cl_cmdrate 101`, `ex_interp 0` |
| Loss | Wired Ethernet, host especially. Distance between players can't be fixed locally |

If only one player feels it and everyone else is fine, it's their connection or settings, not the server.

## Running it day to day

Once set up, **use `C:\hlds\start-server.bat`** — double-click it, or make a desktop shortcut. Closing the console window stops the server.

The setup scripts are not launchers. They write settings into config files on disk (`gamemode_deathmatch.json`, `yapb.cfg`, `plugins.ini`, `server.cfg`), and `hlds.exe` reads those on every start. Running a setup script to start the server would re-download every component and reset your tweaks.

| You want to... | Run |
|---|---|
| Play | `start-server.bat` |
| Change how the server is built or configured | the relevant setup script |
| Change one setting temporarily | type the cvar in the server console |
| Change one setting permanently | edit the config file, then restart |

Both setup scripts write `start-server.bat` with the IP, map, port and slot count they configured, so re-run one after changing any of those.

Common live tweaks, typed into the server console:

```
yb_quota 10          # bot count (fill mode: total players, not bots + humans)
yb_difficulty 2      # 0-4
changelevel de_nuke  # switch map
status               # who's connected
```

To make a live change permanent, put it in the file that owns it: bot settings in `addons\yapb\conf\yapb.cfg`, deathmatch rules in `addons\amxmodx\configs\redm\gamemode_deathmatch.json`, and server basics in `cstrike\server.cfg`.

## Game modes

Two ready-made presets — double-click either, no switches to remember:

| File | Mode |
|---|---|
| `Setup-Normal.cmd` | FFA, all weapons, normal damage, 10 bots |
| `Setup-Headshot.cmd` | FFA, all weapons, **headshots only**, 10 bots |

Edit `CHANGE_ME` in both to your RCON password before first use. They call `Setup-ReDeathmatch.ps1` with the right switches, so the whole stack is reconfigured and the server restarts in that mode.

Or call the script directly:

```powershell
# Headshot-only FFA, 10 bots
powershell -ExecutionPolicy Bypass -File .\Setup-ReDeathmatch.ps1 -HeadshotOnly -BotQuota 10
```

| Switch | Effect |
|---|---|
| *(default)* | FFA, all weapons, body damage normal |
| `-HeadshotOnly` | `mp_damage_headshot_only 1` — only headshots deal damage |
| `-TeamDeathmatch` | TDM instead of free-for-all |
| `-FakeBotPing` | Give bots invented pings (see below) |

**To switch modes mid-session**, don't re-run anything — type it in the server console:

```
mp_damage_headshot_only 1     # headshot only
mp_damage_headshot_only 0     # back to normal
```

The presets are for making a mode the persistent default; the cvar is for flipping between them while people are playing. ReDeathmatch also ships round modes (`PISTOLS_ONLY_HS`, `ALL_WEAPONS_HS_ONLY`) in the `modes` array of `gamemode_deathmatch.json`; set `redm_modes_switch` to `sequentially` or `random` to rotate through them automatically.

## Bot ping

Bots have no network connection, so any ping shown next to them is invented by YaPB. **It's off by default here**, because `yb_latency_display 2` is known to skew *real* players' displayed pings too — a wired player can show a ping that doesn't match the `ping` command ([yapb#227](https://github.com/yapb/yapb/issues/227), [yapb#572](https://github.com/yapb/yapb/issues/572)). With `yb_latency_display 0`, everyone's ping reads correctly and bots simply show as bots.

Pass `-FakeBotPing` if you'd rather have the scoreboard look populated, accepting the display quirk. Tune it with `yb_ping_base_min` and `yb_ping_base_max`.

If the *game itself* feels laggy rather than the number looking wrong, that's a different problem — see [Performance](#performance).

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
| `-Map` | `de_dust2` | The map. The server stays on it unless you pass `-Rotate` |
| `-Rotate` | off | Enable normal map rotation instead of locking to `-Map` |
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

## Bots

Valve's built-in CS bots are disabled on dedicated servers — `bot_add` and `bot_quota` do nothing on HLDS no matter how you configure them. They only work on a listen server ("New Game" from the menu). This script installs [YaPB](https://github.com/yapb/yapb) instead, which runs as a Metamod plugin and downloads its own navigation graphs, so there are no waypoint files to manage.

**Bot settings live in `cstrike\addons\yapb\conf\yapb.cfg`, not `server.cfg`.** YaPB executes its own config on every map load and overwrites anything `server.cfg` set, which is a common reason bot counts appear to be ignored. The script writes these:

| Cvar | Value | Meaning |
|------|-------|---------|
| `yb_quota` | `-BotQuota` (6) | How many bots |
| `yb_quota_mode` | `fill` | Keep N players total, bots making up the difference |
| `yb_difficulty` | `3` | 0–4 |
| `yb_autovacate` | `1` | Kick a bot to make room for a joining human |
| `yb_csdm_mode` | `1` | Tell the bots they're in a deathmatch game |

To change the count live, in the server console: `yb_quota 10`. The `yb` command opens YaPB's own menu.

## Maps

By default the server is locked to a single map (`-Map`, default `de_dust2`). This is done with a one-line `mapcycle.txt` plus `mp_timelimit 0`, so a round ending never triggers a rotation. Pass `-Rotate` if you'd rather cycle maps; edit `cstrike\mapcycle.txt` to choose which.

Note that CSDM needs spawn points for whatever map you run. It ships presets for the standard maps, so obscure maps may spawn players at the normal round-start positions.

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

## Diagnostics

When something doesn't load, `Diagnose-CsServer.ps1` dumps the whole picture — which files exist, how the configs are wired, and the tail of both log files. It's read-only.

```powershell
powershell -ExecutionPolicy Bypass -File .\Diagnose-CsServer.ps1 > report.txt
```

The most useful part is `cstrike\addons\amxmodx\logs\error_*.log`. AMX Mod X records exactly which module or plugin failed and why, which beats guessing from what's missing. If that log doesn't exist at all, AMXX itself never loaded — start there instead.

In the server console, `meta list` (Metamod's view), `amx_modules` (modules, including CSDM) and `amxx plugins` (plugins) answer the same question at three levels.

## Troubleshooting

**`cannot be loaded. The file is not digitally signed`** — the execution policy blocking a downloaded script. See [Running the script](#running-the-script).

**`X is not recognized as a cmdlet`** — PowerShell doesn't run programs from the current directory. Use `.\hlds.exe`, not `hlds.exe`.

**`LoadLibrary failed on <garbage> (126)`** — `liblist.gam` is broken. Usually it was saved as UTF-16 (which is what `Set-Content` does by default in Windows PowerShell 5.1) or contains smart quotes pasted from a chat or Word. Save as ANSI with straight quotes.

**`meta list` shows `0 plugins`** — Metamod isn't reading `plugins.ini`. Either it's missing, named `plugins.ini.txt`, or Metamod is resolving the path relative to the working directory instead of `cstrike\`. The script handles the last case by writing an absolute `plugins_file` into `config.ini` and mirroring the file where Metamod looks.

**`Plugin uses an unknown function (name "csdm_respawn") - check your modules.ini`** — every `csdm_*.amxx` plugin fails with a variant of this when `csdm_amxx.dll` isn't loaded. AMX Mod X only loads non-standard modules listed in `addons\amxmodx\configs\modules.ini`, and the CSDM archive doesn't add itself. Append a line containing just `csdm`, restart, and confirm with `amx_modules` in the server console. Related symptom: `Run time error 10 ... native "csdm_settings_menu"` and `Called dynanative into a paused plugin`, both of which are downstream of the same cause.

**`FindConfigFile: Can't find any config file!`** — ReDeathmatch can't read `configs\redm\gamemode_deathmatch.json`. Either it's missing, or an edit broke its JSON. Note that the shipped file is JSONC: it contains `//` and `/* */` comments, so `ConvertFrom-Json` in PowerShell 5.1 chokes on it, and a script that rewrites it through JSON parsing will fail. Edit values in place instead, and write UTF-8 **without** a BOM.

**`GameConfig CRC mismatch for game "*" section "*" library "server"`** — AMX Mod X's gamedata doesn't match your HLDS build, i.e. the 25th-anniversary build again. Anything depending on memory offsets may misbehave even if it loads. Use `-LegacyBuild`, or move to the ReDeathmatch stack.

**Server crashes when a player picks a team** — almost always CSDM. Confirm by commenting out every line in `configs/plugins-csdm.ini` with `;`; if the crash stops, CSDM is the cause. Fix by upgrading to 2.1.3d and AMX Mod X 1.10. If it still crashes, run with `-LegacyBuild`: the 25th-anniversary HLDS build broke most 1.6 plugins, and the `steam_legacy` branch is what they were compiled against.

**No bots, and `bot_add` / `bot_quota` do nothing** — expected; see [Bots](#bots). Those are Valve's cvars and they're dead on a dedicated server.

**No bots even with YaPB installed** — two usual causes. Either the install failed quietly (check for `cstrike\addons\yapb\bin\yapb.dll` and for a `yapb.dll` line in `addons\metamod\plugins.ini`, and confirm YaPB shows as `RUN` in `meta list`), or `yb_quota` is being set in `server.cfg`, where YaPB's own `yapb.cfg` overwrites it on every map load. Put bot settings in `addons\yapb\conf\yapb.cfg`.

**Files extracted to the wrong place** — a recurring theme. AMX Mod X archives contain an `addons\` folder and extract into `cstrike\`; the CSDM archive contains bare `modules\`, `plugins\` and `configs\` folders and extracts into `cstrike\addons\amxmodx\`. Getting this backwards leaves you with `cstrike\addons\modules\`, which nothing loads. The script detects the layout and copies accordingly.

## Load order

Useful when something silently doesn't load — each layer only gets reached if the one above it worked:

```
hlds.exe
  └─ liblist.gam            gamedll -> metamod.dll
       └─ metamod
            └─ plugins.ini  -> amxmodx_mm.dll, yapb.dll
                 └─ AMX Mod X
                      ├─ configs/modules.ini      -> csdm  (module - easy to miss)
                      └─ configs/plugins-csdm.ini -> csdm_*.amxx
                           └─ configs/csdm.cfg
```

Both AMXX lines are required. The plugins load without the module and then fail one by one, which looks like a plugin problem but isn't.

## Credits

The script only automates existing work by other people:

- [Metamod-P](https://github.com/jkivilin/metamod-p) — Jussi Kivilinna, after Will Day's Metamod
- [AMX Mod X](https://www.amxmodx.org) — AlliedModders
- [CSDM](https://forums.alliedmods.net/showthread.php?p=403419) — BAILOPAN, with the 2.1.3 fixes by KWo
- [YaPB](https://github.com/yapb/yapb) — jeefo
- [ReDeathmatch](https://github.com/ReDeathmatch/ReDeathmatch_AMXX) — the modern ReHLDS-based alternative, if you outgrow CSDM

## License

MIT, for the script in this repo. The components it downloads carry their own licenses.
