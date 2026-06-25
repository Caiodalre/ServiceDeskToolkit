@echo off
title ServiceDesk Toolkit Corporate

if exist "C:\Program Files\PowerShell\7\pwsh.exe" (
    start "" "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\ServiceDeskToolkit\ServiceDeskToolkit-Corporate.ps1"
    exit
)

where pwsh.exe >nul 2>&1
if %errorlevel%==0 (
    start "" pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ServiceDeskToolkit\ServiceDeskToolkit-Corporate.ps1"
    exit
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ServiceDeskToolkit\ServiceDeskToolkit-Corporate.ps1"
exit
