<#
.SYNOPSIS
    Converts an HLDS install to the modern ReHLDS deathmatch stack:
    ReHLDS + ReGameDLL_CS + Metamod-r + AMX Mod X + ReAPI + ReDeathmatch + YaPB.

.DESCRIPTION
    Replaces CSDM, which has been unmaintained since ~2014 and no longer matches
    either current HLDS builds or the AMX Mod X module interface.

    Every component is resolved from its latest GitHub release, so this does not
    rot the way pinned 2013 downloads do. Each step verifies its own result and
    says plainly what failed.

    Run Setup-CsDeathmatch.ps1 FIRST to get HLDS + AMX Mod X in place, then this.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Setup-ReDeathmatch.ps1 -RconPassword 'secret'
#>

[CmdletBinding()]
param(
    [string] $Root         = 'C:\hlds',
    [string] $ServerName   = "Stav's Deathmatch",
    [string] $RconPassword = 'CHANGE_ME',
    [string] $Map          = 'de_dust2',
    [int]    $Port         = 27015,
    [int]    $MaxPlayers   = 20,
    [int]    $BotQuota     = 15,
    [switch] $TeamDeathmatch,   # default is FFA (free-for-all); this switches to TDM
    [switch] $HeadshotOnly,     # only headshots deal damage
    [switch] $FakeBotPing,      # show invented pings for bots (known to skew real players' pings)
    [switch] $Rotate,
    [switch] $NoStart
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$Cstrike = Join-Path $Root 'cstrike'
$Addons  = Join-Path $Cstrike 'addons'
$Amxx    = Join-Path $Addons 'amxmodx'
$Work    = Join-Path $env:TEMP 'redm-setup'

function Step ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "    [ok]   $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "    [warn] $m" -ForegroundColor Yellow }
function Fail ($m) { Write-Host "    [FAIL] $m" -ForegroundColor Red }

$script:Problems = @()
function Problem ($m) { Fail $m; $script:Problems += $m }

New-Item -ItemType Directory -Force -Path $Work | Out-Null

# ---------------------------------------------------------------------------
function Get-Release {
    <# Downloads and extracts the newest release asset matching $Pattern. #>
    param([string]$Repo, [string]$Pattern, [string]$Label)

    $dest = Join-Path $Work ($Repo -replace '/', '_')
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }

    try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" `
                   -Headers @{ 'User-Agent' = 'redm-setup' } -TimeoutSec 30
    } catch {
        Problem "$Label - could not reach the GitHub API: $($_.Exception.Message)"
        return $null
    }

    $asset = $rel.assets | Where-Object { $_.name -like $Pattern } | Select-Object -First 1
    if (-not $asset) {
        Problem "$Label - no asset matching '$Pattern' in release $($rel.tag_name). Check github.com/$Repo/releases"
        return $null
    }

    $zip = Join-Path $Work $asset.name
    try {
        if (-not (Test-Path $zip)) {
            Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing -TimeoutSec 180
        }
        Expand-Archive $zip -DestinationPath $dest -Force
        Ok "$Label $($rel.tag_name)"
        return $dest
    } catch {
        Problem "$Label - download or extract failed: $($_.Exception.Message)"
        return $null
    }
}

function Place-File {
    <# Finds $Name anywhere under $From and copies it to $To. #>
    param([string]$From, [string]$Name, [string]$To, [string]$Label)
    if (-not $From) { return $false }

    $f = Get-ChildItem $From -Recurse -Filter $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $f) { Problem "$Label - $Name not found in the archive"; return $false }

    New-Item -ItemType Directory -Force -Path (Split-Path $To) | Out-Null
    if (Test-Path $To) { Copy-Item $To "$To.bak" -Force }
    Copy-Item $f.FullName $To -Force
    Ok "$Label -> $To"
    return $true
}

function Add-Line {
    param([string]$Path, [string]$Line)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
    $existing = if (Test-Path $Path) { Get-Content $Path } else { @() }
    if ($existing -notcontains $Line) {
        Set-Content $Path -Value (@($existing | Where-Object { $_ -ne '' }) + $Line) -Encoding Ascii
    }
}

# ---------------------------------------------------------------------------
Step 'Prerequisites'
if (-not (Test-Path (Join-Path $Root 'hlds.exe'))) {
    Fail "No hlds.exe in $Root. Run Setup-CsDeathmatch.ps1 first."
    exit 1
}
if (-not (Test-Path (Join-Path $Amxx 'dlls\amxmodx_mm.dll'))) {
    Fail 'AMX Mod X is not installed. Run Setup-CsDeathmatch.ps1 first.'
    exit 1
}
Ok 'HLDS and AMX Mod X present'

# ---------------------------------------------------------------------------
Step 'Removing CSDM'
# CSDM and ReDeathmatch cannot coexist - both hook spawning.
Get-ChildItem (Join-Path $Amxx 'plugins') -Filter 'csdm*.amxx' -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Amxx 'modules\csdm_amxx.dll') -Force -ErrorAction SilentlyContinue
$modulesIni = Join-Path $Amxx 'configs\modules.ini'
if (Test-Path $modulesIni) {
    Set-Content $modulesIni -Value (Get-Content $modulesIni | Where-Object { $_ -notmatch '^\s*csdm\s*$' }) -Encoding Ascii
}
$csdmPluginsIni = Join-Path $Amxx 'configs\plugins-csdm.ini'
if (Test-Path $csdmPluginsIni) { Rename-Item $csdmPluginsIni "$csdmPluginsIni.disabled" -Force -ErrorAction SilentlyContinue }
Ok 'CSDM removed'

# ---------------------------------------------------------------------------
Step 'ReHLDS (engine)'
$src = Get-Release 'dreamstalker/rehlds' '*rehlds-bin*.zip' 'ReHLDS'
Place-File $src 'swds.dll' (Join-Path $Root 'swds.dll') 'ReHLDS engine' | Out-Null

# ---------------------------------------------------------------------------
Step 'ReGameDLL_CS (game logic)'
$src = Get-Release 'rehlds/ReGameDLL_CS' '*regamedll-bin*.zip' 'ReGameDLL'
Place-File $src 'mp.dll' (Join-Path $Cstrike 'dlls\mp.dll') 'ReGameDLL' | Out-Null

# ---------------------------------------------------------------------------
Step 'Metamod-r'
$src = Get-Release 'theAsmodai/metamod-r' '*metamod-bin*.zip' 'Metamod-r'
Place-File $src 'metamod.dll' (Join-Path $Addons 'metamod\dlls\metamod.dll') 'Metamod-r' | Out-Null

# ---------------------------------------------------------------------------
Step 'ReAPI (AMXX module)'
$src = Get-Release 'rehlds/reapi' '*reapi-bin*.zip' 'ReAPI'
if (Place-File $src 'reapi_amxx.dll' (Join-Path $Amxx 'modules\reapi_amxx.dll') 'ReAPI') {
    Add-Line $modulesIni 'reapi'
    Ok 'registered reapi in modules.ini'
}

# ---------------------------------------------------------------------------
Step 'ReDeathmatch'
$src = Get-Release 'ReDeathmatch/ReDeathmatch_AMXX' '*.zip' 'ReDeathmatch'
if ($src) {
    # The archive mirrors cstrike\addons\amxmodx\{plugins,configs,data}
    $payload = Get-ChildItem $src -Recurse -Directory |
               Where-Object { $_.Name -eq 'amxmodx' } | Select-Object -First 1
    if ($payload) {
        Copy-Item (Join-Path $payload.FullName '*') $Amxx -Recurse -Force
        Ok "ReDeathmatch -> $Amxx"
    } else {
        Problem 'ReDeathmatch - could not find an amxmodx folder in the archive; extract it by hand'
    }

    # Plugins are ReDeathmatch.amxx and redm_spawns.amxx, activated through
    # their own configs\plugins-redm.ini (which AMX Mod X reads automatically).
    $main   = Test-Path (Join-Path $Amxx 'plugins\ReDeathmatch.amxx')
    $spawns = Test-Path (Join-Path $Amxx 'plugins\redm_spawns.amxx')
    if ($main -and $spawns) { Ok 'ReDeathmatch.amxx + redm_spawns.amxx present' }
    else { Problem 'ReDeathmatch - expected plugins are missing from addons\amxmodx\plugins' }

    $redmIni = Join-Path $Amxx 'configs\plugins-redm.ini'
    if (Test-Path $redmIni) {
        # Uncomment any disabled plugin lines
        Set-Content $redmIni -Value (Get-Content $redmIni | ForEach-Object { $_ -replace '^\s*;\s*(\S+\.amxx)', '$1' }) -Encoding Ascii
        Ok 'plugins-redm.ini enabled'
    } else {
        Set-Content $redmIni -Value @('ReDeathmatch.amxx', 'redm_spawns.amxx') -Encoding Ascii
        Ok 'created plugins-redm.ini'
    }

    # ---- Gameplay settings --------------------------------------------------
    # The shipped config is JSONC - it contains // and /* */ comments, which
    # ConvertFrom-Json rejects. Edit the values in place instead, so the
    # comments (and the plugin's expected schema) survive.
    $gmPath = Join-Path $Amxx 'configs\redm\gamemode_deathmatch.json'
    if (Test-Path $gmPath) {
        $text = Get-Content $gmPath -Raw
        Copy-Item $gmPath "$gmPath.bak" -Force

        $wanted = [ordered]@{
            # --- what you asked for ---
            'mp_freeforall'              = if ($TeamDeathmatch) { '0' } else { '1' }  # FFA
            'redm_open_equip_menu'       = '1'    # gun menu appears on spawn
            'redm_equip_menu_open_by_g'  = '1'    # and on G, to switch later
            'redm_equip_manager'         = '1'
            'redm_block_drop_weapon'     = '1'    # can't drop -> nothing on the ground
            'mp_item_staytime'           = '0'    # any dropped item vanishes at once
            'mp_weapons_allow_map_placed'= '0'    # no map-placed guns
            'mp_give_player_c4'          = '0'    # no bomb
            'mp_damage_headshot_only'    = if ($HeadshotOnly) { '1' } else { '0' }
            # --- deathmatch hygiene ---
            'mp_freezetime'              = '0'
            'mp_buytime'                 = '0'
            'mp_autoteambalance'         = '0'
            'mp_limitteams'              = '0'
            'mp_startmoney'              = '0'
            'redm_randomspawn'           = '1'
        }

        $changed = @()
        foreach ($k in $wanted.Keys) {
            $val = $wanted[$k]
            $rx  = "(`"$([regex]::Escape($k))`"\s*:\s*)`"[^`"]*`""
            if ($text -match $rx) {
                $current = ([regex]::Match($text, $rx + '')).Value
                if ($current -notmatch "`"$val`"\s*$") { $changed += "$k -> $val" }
                $text = [regex]::Replace($text, $rx, "`${1}`"$val`"")
            } else {
                # Key absent: insert it as the first entry of the cvars object.
                $text = [regex]::Replace($text, '("cvars"\s*:\s*\{)', "`${1}`r`n        `"$k`": `"$val`",", 1)
                $changed += "$k -> $val (added)"
            }
        }

        # UTF8 without BOM - a BOM breaks some JSON readers.
        [IO.File]::WriteAllText($gmPath, $text, (New-Object Text.UTF8Encoding $false))
        Ok "gamemode_deathmatch.json patched ($(if ($TeamDeathmatch) {'TDM'} else {'FFA'}), equip menu on, no bomb, no dropped guns)"
        if ($changed) { $changed | ForEach-Object { Write-Host "           $_" -ForegroundColor DarkGray } }
        else { Ok 'defaults already matched - nothing to change' }
    } else {
        Problem "gamemode_deathmatch.json not found at $gmPath - ReDeathmatch will not start without it"
    }
}

# ---------------------------------------------------------------------------
Step 'YaPB bots'
$yapbDll = Join-Path $Addons 'yapb\bin\yapb.dll'
if (Test-Path $yapbDll) {
    Ok 'already installed'
} else {
    $src = Get-Release 'yapb/yapb' '*windows*.zip' 'YaPB'
    if ($src) {
        $payload = Get-ChildItem $src -Recurse -Directory |
                   Where-Object { $_.Name -eq 'addons' } | Select-Object -First 1
        if ($payload) { Copy-Item $payload.FullName $Cstrike -Recurse -Force }
        else { Copy-Item (Join-Path $src '*') $Cstrike -Recurse -Force }
    }
}
$yapbOk = Test-Path $yapbDll
if (-not $yapbOk) { Problem "YaPB - $yapbDll missing; download the Windows zip from https://yapb.jeefo.net/latest" }

# ---------------------------------------------------------------------------
Step 'Wiring'

$liblist = Join-Path $Cstrike 'liblist.gam'
if (Test-Path $liblist) {
    Copy-Item $liblist "$liblist.bak" -Force
    $c = (Get-Content $liblist) -replace '^\s*gamedll\s+".*"', 'gamedll "addons\metamod\dlls\metamod.dll"'
    Set-Content $liblist -Value $c -Encoding Ascii
    Ok 'liblist.gam -> metamod'
}

$mmDir = Join-Path $Addons 'metamod'
$pluginsIni = Join-Path $mmDir 'plugins.ini'
$lines = @('win32 addons\amxmodx\dlls\amxmodx_mm.dll')
if ($yapbOk) { $lines += 'win32 addons\yapb\bin\yapb.dll' }
Remove-Item "$pluginsIni*" -Force -ErrorAction SilentlyContinue
Set-Content $pluginsIni -Value $lines -Encoding Ascii
Set-Content (Join-Path $mmDir 'config.ini') -Value "plugins_file $pluginsIni" -Encoding Ascii
Ok 'metamod plugins.ini'

if ($yapbOk) {
    $yapbCfg = Join-Path $Addons 'yapb\conf\yapb.cfg'
    New-Item -ItemType Directory -Force -Path (Split-Path $yapbCfg) | Out-Null
    $body = if (Test-Path $yapbCfg) { Get-Content $yapbCfg } else { @() }
    $body = $body | Where-Object { $_ -notmatch '^\s*yb_(quota|quota_mode|difficulty|autovacate|csdm_mode|latency_display|ping_base_min|ping_base_max)\b' }
    $body += @('', '// added by Setup-ReDeathmatch.ps1',
               "yb_quota `"$BotQuota`"", 'yb_quota_mode "fill"',
               'yb_difficulty "3"', 'yb_autovacate "1"',
               "yb_csdm_mode `"$(if ($TeamDeathmatch) {'1'} else {'2'})`"")

    if ($FakeBotPing) {
        $body += @('yb_latency_display "2"', 'yb_ping_base_min "10"', 'yb_ping_base_max "40"')
    } else {
        # 2 invents bot pings but also skews REAL players' displayed pings
        # (yapb issues #227, #572). 0 leaves everyone's ping accurate.
        $body += 'yb_latency_display "0"'
    }
    Set-Content $yapbCfg -Value $body -Encoding Ascii
    Ok "yapb.cfg (quota $BotQuota)"
}

if ($Rotate) { $timeLimit = 20 } else {
    Set-Content (Join-Path $Cstrike 'mapcycle.txt') -Value $Map -Encoding Ascii
    $timeLimit = 0
    Ok "locked to $Map"
}

$serverCfg = @"
hostname "$ServerName"
rcon_password "$RconPassword"
sv_region 6
sv_lan 0

mp_timelimit $timeLimit
mapcyclefile "mapcycle.txt"
mp_freezetime 0
mp_roundtime 9
mp_buytime 0.25
mp_friendlyfire 0
mp_autoteambalance 1
mp_limitteams 2
mp_forcecamera 0
mp_fadetoblack 0

sv_voiceenable 1
sv_alltalk 1

sys_ticrate 1000
sv_maxrate 100000
sv_minrate 20000
sv_maxupdaterate 101
sv_minupdaterate 30

// Deathmatch settings live in addons\amxmodx\configs\redm\
// Bot settings live in addons\yapb\conf\yapb.cfg

log on
exec banned.cfg
exec listip.cfg
"@
Set-Content (Join-Path $Cstrike 'server.cfg') -Value $serverCfg -Encoding Ascii
foreach ($f in 'banned.cfg','listip.cfg') {
    $p = Join-Path $Cstrike $f
    if (-not (Test-Path $p)) { New-Item -ItemType File -Path $p | Out-Null }
}
Ok 'server.cfg'

# ---------------------------------------------------------------------------
Step 'Result'
if ($script:Problems.Count) {
    Fail "$($script:Problems.Count) problem(s):"
    $script:Problems | ForEach-Object { Write-Host "      - $_" -ForegroundColor Red }
    Write-Host "`n    Fix these before starting, or the server will run without deathmatch." -ForegroundColor Yellow
} else {
    Ok 'All components installed'
}

Write-Host "`n    Mode           : $(if ($TeamDeathmatch) {'Team Deathmatch'} else {'FFA (free-for-all)'})"
Write-Host "    Bots           : $BotQuota (yb_quota, fill mode)"
Write-Host "    Headshot only  : $(if ($HeadshotOnly) {'yes'} else {'no'})"
Write-Host "    Bot fake ping  : $(if ($FakeBotPing) {'on'} else {'off (real pings stay accurate)'})"
Write-Host "    Bomb / dropped guns: disabled"
if ($BotQuota -ge $MaxPlayers) {
    Warn "maxplayers ($MaxPlayers) is not above the bot quota ($BotQuota) - there will be no room for humans."
    Warn "Re-run with -MaxPlayers $($BotQuota + 4)."
}

Write-Host "`n    Verify in the SERVER console:"
Write-Host "      meta list      -> AMX Mod X and YaPB, both RUN"
Write-Host "      amx_modules    -> reapi, running"
Write-Host "      amxx plugins   -> ReDeathmatch.amxx and redm_spawns.amxx, running"
Write-Host "    Look for: FindConfigFile: Config ``gamemode_deathmatch.json`` loaded"
Write-Host "    Then check: addons\amxmodx\logs\error_*.log"

if (-not $script:Problems.Count) {
    $ip = (Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
           Select-Object -First 1 -ExpandProperty IPv4Address | Select-Object -First 1).IPAddress

    # Day-to-day launcher. The settings this script wrote live in the config
    # files on disk, so starting hlds.exe is all that's needed from here on.
    Set-Content (Join-Path $Root 'start-server.bat') -Encoding Ascii -Value @"
@echo off
cd /d "$Root"
hlds.exe -console -game cstrike +ip $ip +map $Map +maxplayers $MaxPlayers -port $Port
"@
    Ok "wrote $Root\start-server.bat - use this to start the server from now on"

    if (-not $NoStart) {
        Start-Process -FilePath (Join-Path $Root 'hlds.exe') -WorkingDirectory $Root `
            -ArgumentList @('-console','-game','cstrike','+ip',$ip,'+map',$Map,'+maxplayers',$MaxPlayers,'-port',$Port)
        Ok 'server started'
    }
}
