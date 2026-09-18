<#
.SYNOPSIS
    Installs and configures a Counter-Strike 1.6 Deathmatch server (HLDS + Metamod + AMX Mod X + CSDM + YaPB bots).

.DESCRIPTION
    Idempotent: safe to re-run. Each step checks whether its files are already in place.

.EXAMPLE
    .\Setup-CsDeathmatch.ps1 -RconPassword 'mySecret123'

.EXAMPLE
    # If the 25th-anniversary build keeps crashing, use the old, mod-friendly build:
    .\Setup-CsDeathmatch.ps1 -LegacyBuild -Force

.NOTES
    Run in PowerShell as Administrator (needed only for the firewall rule).
#>

[CmdletBinding()]
param(
    [string] $Root         = 'C:\hlds',
    [string] $SteamCmdDir  = 'C:\steamcmd',
    [string] $CsdmZip      = "$env:USERPROFILE\Downloads\csdm_2.1.3d_KWo.zip",
    [string] $AmxxVersion  = '1.10.0-git5483',
    [string] $ServerName   = "Stav's Deathmatch",
    [string] $RconPassword = 'CHANGE_ME',
    [string] $Map          = 'de_dust2',
    [int]    $Port         = 27015,
    [int]    $MaxPlayers   = 16,
    [int]    $BotQuota     = 6,
    [switch] $LegacyBuild,   # install the pre-anniversary HLDS build (best mod compatibility)
    [switch] $Force,         # re-download / re-extract even if files exist
    [switch] $SkipHlds,      # skip the SteamCMD + HLDS step
    [switch] $NoStart        # configure only, don't launch the server
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # much faster Invoke-WebRequest

$Cstrike = Join-Path $Root 'cstrike'
$Addons  = Join-Path $Cstrike 'addons'
$Amxx    = Join-Path $Addons 'amxmodx'
$Work    = Join-Path $env:TEMP 'csdm-setup'

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

function Step   ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok     ($m) { Write-Host "    [ok]   $m" -ForegroundColor Green }
function Warn   ($m) { Write-Host "    [warn] $m" -ForegroundColor Yellow }
function Fail   ($m) { Write-Host "    [FAIL] $m" -ForegroundColor Red }

function Get-LanIPv4 {
    # The adapter that actually routes to the internet - skips Hyper-V / WSL / VMware.
    $ip = Get-NetIPConfiguration |
          Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } |
          Select-Object -First 1 -ExpandProperty IPv4Address |
          Select-Object -First 1 -ExpandProperty IPAddress
    if (-not $ip) { throw 'Could not detect a LAN IPv4 address. Pass it manually in the launch command.' }
    return $ip
}

function Get-File {
    param([string]$Url, [string]$OutFile)
    if ((Test-Path $OutFile) -and -not $Force) { Ok "cached: $(Split-Path $OutFile -Leaf)"; return $true }
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 120
        Ok "downloaded: $(Split-Path $OutFile -Leaf)"
        return $true
    } catch {
        Warn "download failed: $Url"
        Warn $_.Exception.Message
        return $false
    }
}

function Expand-Smart {
    <#
        Extracts a zip and figures out where its payload belongs.
        Handles the three shapes these archives come in:
          - <zip>/addons/...                  -> copy into cstrike\
          - <zip>/<wrapper>/addons/...        -> copy wrapper contents into cstrike\
          - <zip>/{modules,plugins,configs}/  -> copy into cstrike\addons\amxmodx\  (CSDM by KWo)
    #>
    param([string]$Zip, [string]$Label)

    if (-not (Test-Path $Zip)) { Fail "$Label - archive not found: $Zip"; return $false }

    $tmp = Join-Path $Work ([IO.Path]::GetFileNameWithoutExtension($Zip))
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -Path $Zip -DestinationPath $tmp -Force

    $src = $tmp
    if (-not (Test-Path (Join-Path $src 'addons'))) {
        $nested = Get-ChildItem $src -Directory |
                  Where-Object { Test-Path (Join-Path $_.FullName 'addons') } |
                  Select-Object -First 1
        if ($nested) { $src = $nested.FullName }
    }

    if (Test-Path (Join-Path $src 'addons')) {
        $dest = $Cstrike
    } elseif ((Test-Path (Join-Path $src 'modules')) -or (Test-Path (Join-Path $src 'plugins'))) {
        $dest = $Amxx        # CSDM packages ship their folders un-prefixed
    } else {
        Fail "$Label - unexpected archive layout, nothing copied. Look inside: $src"
        return $false
    }

    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item (Join-Path $src '*') $dest -Recurse -Force
    Ok "$Label -> $dest"
    return $true
}

function Set-CfgValue {
    # Replaces "key = value" in a CSDM-style cfg, or appends it if missing.
    param([string]$Path, [string]$Key, [string]$Value)
    if (-not (Test-Path $Path)) { return }
    $lines = Get-Content $Path
    $hit = $false
    $out = foreach ($l in $lines) {
        if ($l -match "^\s*;?\s*$([regex]::Escape($Key))\s*=") { $hit = $true; "$Key = $Value" }
        else { $l }
    }
    if (-not $hit) { $out += "$Key = $Value" }
    Set-Content -Path $Path -Value $out -Encoding Ascii
}

New-Item -ItemType Directory -Force -Path $Work | Out-Null

# ----------------------------------------------------------------------------
# 1. SteamCMD
# ----------------------------------------------------------------------------
if (-not $SkipHlds) {
    Step 'SteamCMD'
    $steamExe = Join-Path $SteamCmdDir 'steamcmd.exe'
    if (-not (Test-Path $steamExe)) {
        New-Item -ItemType Directory -Force -Path $SteamCmdDir | Out-Null
        $zip = Join-Path $Work 'steamcmd.zip'
        if (Get-File 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip' $zip) {
            Expand-Archive $zip -DestinationPath $SteamCmdDir -Force
        }
    }
    if (Test-Path $steamExe) { Ok $steamExe } else { Fail 'SteamCMD missing'; exit 1 }

    # ------------------------------------------------------------------------
    # 2. HLDS (app 90). Runs up to 3 times - partial downloads are a known bug.
    # ------------------------------------------------------------------------
    Step 'HLDS + Counter-Strike'
    $args = @('+force_install_dir', $Root, '+login', 'anonymous',
              '+app_set_config', '90', 'mod', 'cstrike')
    if ($LegacyBuild) {
        $args += @('+app_update', '90', '-beta', 'steam_legacy', 'validate')
        Warn 'Installing the legacy (pre-25th-anniversary) build.'
    } else {
        $args += @('+app_update', '90', 'validate')
    }
    $args += '+quit'

    for ($i = 1; $i -le 3; $i++) {
        if ((Test-Path (Join-Path $Root 'hlds.exe')) -and (Test-Path $Cstrike) -and -not $Force) { break }
        Write-Host "    attempt $i/3 ..."
        & $steamExe @args | Out-Null
    }
    if (Test-Path (Join-Path $Root 'hlds.exe')) { Ok 'hlds.exe present' }
    else { Fail 'HLDS did not install - run the SteamCMD command manually and watch its output'; exit 1 }
}

# ----------------------------------------------------------------------------
# 3. Clean up misplaced files from earlier manual attempts
# ----------------------------------------------------------------------------
Step 'Cleaning misplaced files'
foreach ($stray in 'configs','modules','plugins','data','scripting') {
    $p = Join-Path $Addons $stray
    if (Test-Path $p) { Remove-Item $p -Recurse -Force; Ok "removed stray $p" }
}
$oldCsdmModule = Join-Path $Amxx 'modules\csdm_amxx.dll'
if ((Test-Path $oldCsdmModule) -and $Force) { Remove-Item $oldCsdmModule -Force }

# ----------------------------------------------------------------------------
# 4. Metamod-P
# ----------------------------------------------------------------------------
Step 'Metamod-P'
$mmDll = Join-Path $Addons 'metamod\dlls\metamod.dll'
if ((Test-Path $mmDll) -and -not $Force) {
    Ok 'already installed'
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $mmDll) | Out-Null
    $zip = Join-Path $Work 'metamod-p.zip'
    $url = 'https://github.com/jkivilin/metamod-p/releases/download/v1.21p37/metamod-1.21p37-windows.zip'
    if (Get-File $url $zip) {
        $tmp = Join-Path $Work 'mm'
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive $zip -DestinationPath $tmp -Force
        $dll = Get-ChildItem $tmp -Recurse -Filter 'metamod.dll' | Select-Object -First 1
        if ($dll) { Copy-Item $dll.FullName $mmDll -Force; Ok 'installed' }
    }
    if (-not (Test-Path $mmDll)) {
        Warn 'Auto-install failed. Download Metamod-P (win32) manually and place metamod.dll at:'
        Warn "  $mmDll"
    }
}

# ----------------------------------------------------------------------------
# 5. AMX Mod X - BOTH packages. base = amxmodx_mm.dll, cstrike = CS modules.
# ----------------------------------------------------------------------------
Step "AMX Mod X $AmxxVersion"
$amxxDll = Join-Path $Amxx 'dlls\amxmodx_mm.dll'
if ((Test-Path $amxxDll) -and -not $Force) {
    Ok 'already installed'
} else {
    $branch = ($AmxxVersion -split '-')[0] -replace '\.\d+$',''   # 1.10.0-git5483 -> 1.10
    foreach ($pkg in 'base','cstrike') {
        $name = "amxmodx-$AmxxVersion-$pkg-windows.zip"
        $zip  = Join-Path "$env:USERPROFILE\Downloads" $name      # reuse an already-downloaded copy
        if (-not (Test-Path $zip)) {
            $zip = Join-Path $Work $name
            Get-File "https://www.amxmodx.org/amxxdrop/$branch/$name" $zip | Out-Null
        } else { Ok "using existing $name" }
        Expand-Smart $zip "AMXX $pkg" | Out-Null
    }
}
if (Test-Path $amxxDll) { Ok $amxxDll }
else {
    Fail 'amxmodx_mm.dll missing. Grab BOTH "Base Package" and "Counter-Strike" (Windows) from amxmodx.org'
    Fail "and extract them into $Cstrike, then re-run."
    exit 1
}

# ----------------------------------------------------------------------------
# 6. CSDM (from the local zip - the forum requires a login, so no auto-download)
# ----------------------------------------------------------------------------
Step 'CSDM'
if (-not (Test-Path $CsdmZip)) {
    Warn "CSDM zip not found at: $CsdmZip"
    Warn 'Download CSDM 2.1.3d (KWo) from forums.alliedmods.net and pass -CsdmZip <path>.'
} else {
    Expand-Smart $CsdmZip 'CSDM' | Out-Null
}
$csdmOk = Test-Path (Join-Path $Amxx 'modules\csdm_amxx.dll')
if ($csdmOk) { Ok 'csdm_amxx.dll present' } else { Warn 'CSDM module missing - deathmatch will not run' }

# ----------------------------------------------------------------------------
# 7. YaPB bots (Valve's built-in bots do NOT work on a dedicated server)
# ----------------------------------------------------------------------------
Step 'YaPB bots'
$yapbDll = Join-Path $Addons 'yapb\bin\yapb.dll'
if ((Test-Path $yapbDll) -and -not $Force) {
    Ok 'already installed'
} else {
    $zip = Join-Path $Work 'yapb.zip'
    if (Get-File 'https://yapb.jeefo.net/latest/windows' $zip) { Expand-Smart $zip 'YaPB' | Out-Null }
}
$yapbOk = Test-Path $yapbDll
if ($yapbOk) { Ok $yapbDll }
else {
    Warn 'YaPB not installed. Download the Windows zip from https://yapb.jeefo.net/latest'
    Warn "and extract it into $Cstrike (you should end up with addons\yapb\bin\yapb.dll)."
}

# ----------------------------------------------------------------------------
# 8. Wiring: liblist.gam -> metamod -> plugins.ini -> amxx + yapb
# ----------------------------------------------------------------------------
Step 'Configuration'

$liblist = Join-Path $Cstrike 'liblist.gam'
if (Test-Path $liblist) {
    Copy-Item $liblist "$liblist.bak" -Force
    $content = (Get-Content $liblist) -replace '^\s*gamedll\s+".*"', 'gamedll "addons\metamod\dlls\metamod.dll"'
    if (-not ($content -match 'metamod\.dll')) { $content += 'gamedll "addons\metamod\dlls\metamod.dll"' }
    Set-Content $liblist -Value $content -Encoding Ascii
    Ok 'liblist.gam -> metamod.dll'
}

# Metamod looks for plugins.ini relative to the working dir, so pin an absolute
# path in config.ini and also drop a copy where it looks by default.
$mmDir = Join-Path $Addons 'metamod'
$pluginsIni = Join-Path $mmDir 'plugins.ini'
$lines = @('win32 addons\amxmodx\dlls\amxmodx_mm.dll')
if ($yapbOk) { $lines += 'win32 addons\yapb\bin\yapb.dll' }
Remove-Item "$pluginsIni*" -Force -ErrorAction SilentlyContinue
Set-Content $pluginsIni -Value $lines -Encoding Ascii
Set-Content (Join-Path $mmDir 'config.ini') -Value "plugins_file $pluginsIni" -Encoding Ascii
$mirror = Join-Path $Root 'addons\metamod'
New-Item -ItemType Directory -Force -Path $mirror | Out-Null
Copy-Item $pluginsIni (Join-Path $mirror 'plugins.ini') -Force
Ok "plugins.ini ($($lines.Count) plugin(s))"

# CSDM settings
$csdmCfg = Join-Path $Amxx 'configs\csdm.cfg'
if (Test-Path $csdmCfg) {
    Set-CfgValue $csdmCfg 'enabled'         '1'
    Set-CfgValue $csdmCfg 'spawnmode'       'preset'
    Set-CfgValue $csdmCfg 'spawn_wait_time' '0.75'
    Set-CfgValue $csdmCfg 'protection'      '2'
    Ok 'csdm.cfg'
}

# Make sure CSDM's plugin list isn't commented out
$csdmPlugins = Join-Path $Amxx 'configs\plugins-csdm.ini'
if (Test-Path $csdmPlugins) {
    $p = Get-Content $csdmPlugins | ForEach-Object { $_ -replace '^\s*;\s*(csdm_)', '$1' }
    Set-Content $csdmPlugins -Value $p -Encoding Ascii
    Ok 'plugins-csdm.ini enabled'
}

# server.cfg
$serverCfg = @"
hostname "$ServerName"
rcon_password "$RconPassword"
sv_password ""
sv_region 6
sv_lan 0

mp_timelimit 20
mp_freezetime 0
mp_roundtime 9
mp_buytime 0.25
mp_startmoney 16000
mp_friendlyfire 0
mp_tkpunish 0
mp_autokick 0
mp_autoteambalance 1
mp_limitteams 2
mp_flashlight 1
mp_footsteps 1
mp_forcecamera 0
mp_fadetoblack 0
mp_chattime 5

sv_voiceenable 1
sv_alltalk 1

sys_ticrate 1000
sv_maxrate 100000
sv_minrate 20000
sv_maxupdaterate 101
sv_minupdaterate 30

sv_allowdownload 1
sv_allowupload 0

// YaPB bots - Valve's built-in bots don't work on HLDS
yb_quota $BotQuota
yb_quota_mode "fill"
yb_difficulty 3
yb_autovacate 1

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

# ----------------------------------------------------------------------------
# 9. Firewall (needs Administrator)
# ----------------------------------------------------------------------------
Step 'Firewall'
try {
    if (-not (Get-NetFirewallRule -DisplayName 'HLDS CS 1.6' -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName 'HLDS CS 1.6' -Direction Inbound -Protocol UDP `
            -LocalPort $Port -Action Allow -Profile Any | Out-Null
    }
    Ok "UDP $Port allowed inbound"
} catch {
    Warn 'Could not add the firewall rule - re-run this script as Administrator, or add it by hand.'
}

# ----------------------------------------------------------------------------
# 10. Summary + launch
# ----------------------------------------------------------------------------
$ip = Get-LanIPv4
Step 'Summary'
Write-Host "    LAN IP        : $ip"
Write-Host "    Metamod       : $(if (Test-Path $mmDll)   {'ok'} else {'MISSING'})"
Write-Host "    AMX Mod X     : $(if (Test-Path $amxxDll) {'ok'} else {'MISSING'})"
Write-Host "    CSDM          : $(if ($csdmOk)            {'ok'} else {'MISSING'})"
Write-Host "    YaPB bots     : $(if ($yapbOk)            {'ok'} else {'MISSING'})"
Write-Host ""
Write-Host "    You      : connect 127.0.0.1:$Port"
Write-Host "    Same LAN : connect ${ip}:$Port"
Write-Host "    Internet : forward UDP $Port to $ip on your router (Deco app: More > Advanced > NAT Forwarding)"
Write-Host ""
Write-Host "    In the SERVER window, verify with:  meta list   /   amxx plugins"

$launch = @("-console","-game","cstrike","+ip",$ip,"+map",$Map,"+maxplayers",$MaxPlayers,"-port",$Port)
Set-Content (Join-Path $Root 'start-server.bat') `
    -Value "@echo off`r`ncd /d `"$Root`"`r`nhlds.exe $($launch -join ' ')" -Encoding Ascii
Ok "created $Root\start-server.bat"

if (-not $NoStart) {
    Step 'Starting server'
    Start-Process -FilePath (Join-Path $Root 'hlds.exe') -ArgumentList $launch -WorkingDirectory $Root
    Ok 'launched - check the server console window'
}
