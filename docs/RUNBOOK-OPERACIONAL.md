# ServiceDesk Toolkit Corporate - Runbook Operacional

## Objetivo

Orientar o uso operacional do ServiceDesk Toolkit Corporate em ambiente de suporte técnico.

## Caminho padrao

C:\ServiceDeskToolkit

## Arquivos principais

- ServiceDeskToolkit-Corporate.ps1
- ServiceDeskToolkit.cmd
- install.ps1
- update.ps1
- rollback.ps1
- version.json
- data\knowledge-base.json
- tools\Get-ToolkitDiagnostic.ps1
- tools\Test-ToolkitQuality.ps1

## Instalacao development

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm 'https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/v2.1-hardening/install.ps1' | iex"

## Abrir Toolkit

cd C:\ServiceDeskToolkit
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\ServiceDeskToolkit-Corporate.ps1

## Diagnostico

Pela interface: GERAR DIAGNOSTICO DO TOOLKIT

Pelo PowerShell:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ServiceDeskToolkit\tools\Get-ToolkitDiagnostic.ps1 -ToolkitRoot C:\ServiceDeskToolkit -OpenReport

Saida:
- C:\ServiceDeskToolkit\reports\diagnostic-*.txt
- C:\ServiceDeskToolkit\reports\diagnostic-*.json

## Quality Gate

cd C:\ServiceDeskToolkit
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ToolkitQuality.ps1

## Update seguro

Pela interface: ATUALIZAR TOOLKIT

Pelo PowerShell:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ServiceDeskToolkit\update.ps1

O update executa staging, validacao, backup e aplicacao controlada.

## Rollback dry-run

Pela interface: TESTAR ROLLBACK DRY-RUN

Pelo PowerShell:
Remove-Item Env:\SDTK_ROLLBACK_CONFIRM -ErrorAction SilentlyContinue
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ServiceDeskToolkit\rollback.ps1

## Rollback real

Executar apenas em falha real:
$env:SDTK_ROLLBACK_CONFIRM = "YES"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\ServiceDeskToolkit\rollback.ps1
Remove-Item Env:\SDTK_ROLLBACK_CONFIRM

## Logs

- C:\ServiceDeskToolkit\logs\runtime-YYYY-MM.jsonl
- C:\ServiceDeskToolkit\logs\actions-YYYY-MM.jsonl
- C:\ServiceDeskToolkit\logs\errors-YYYY-MM.jsonl
- C:\ServiceDeskToolkit\logs\update-*.log
- C:\ServiceDeskToolkit\logs\rollback-*.log

## Regra operacional

Nao executar update ou rollback via Invoke-Expression.
Usar sempre powershell.exe -File.
