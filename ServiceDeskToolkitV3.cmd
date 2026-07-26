@echo off
title ServiceDesk Toolkit Corporate V3
cd /d "%~dp0"
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0ServiceDeskToolkit-CorporateV3.ps1"
if errorlevel 1 (
    echo.
    echo Falha ao iniciar o ServiceDesk Toolkit Corporate V3.
    echo.
    pause
)
