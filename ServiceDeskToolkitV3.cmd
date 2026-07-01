@echo off
setlocal

title ServiceDesk Toolkit Corporate V3

set "ROOT=%~dp0"
set "APP=%ROOT%ServiceDeskToolkit-CorporateV3.ps1"

if not exist "%APP%" (
    echo.
    echo ServiceDeskToolkit-CorporateV3.ps1 nao encontrado.
    echo Caminho esperado:
    echo %APP%
    echo.
    pause
    exit /b 1
)

powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%APP%"

if errorlevel 1 (
    echo.
    echo Falha ao iniciar o ServiceDesk Toolkit Corporate V3.
    echo.
    pause
    exit /b 1
)

endlocal
exit /b 0
