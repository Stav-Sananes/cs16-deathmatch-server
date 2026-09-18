@echo off
REM Standard deathmatch: FFA, all weapons, body damage normal, 10 bots.
REM Run as Administrator the first time (firewall rule).
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0Setup-ReDeathmatch.ps1" ^
    -RconPassword "CHANGE_ME" ^
    -BotQuota 10 ^
    -Map de_dust2
pause
