@echo off
title ServiceDesk Toolkit Corporate
cd /d C:\ServiceDeskToolkit

echo ============================================================
echo  ServiceDesk Toolkit Corporate
echo ============================================================
echo.

if exist "C:\Program Files\PowerShell\7\pwsh.exe" (
    echo Usando PowerShell 7...
    "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\ServiceDeskToolkit\ServiceDeskToolkit-Corporate.ps1"
    goto fim
)

where pwsh.exe >nul 2>&1
if %errorlevel%==0 (
    echo Usando pwsh do PATH...
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ServiceDeskToolkit\ServiceDeskToolkit-Corporate.ps1"
    goto fim
)

echo Usando Windows PowerShell...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ServiceDeskToolkit\ServiceDeskToolkit-Corporate.ps1"

:fim
echo.
echo ============================================================
echo  O Toolkit foi encerrado ou ocorreu erro.
echo ============================================================
echo.
pause
