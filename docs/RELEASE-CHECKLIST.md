# Release Checklist - ServiceDesk Toolkit Corporate

## Antes da tag

- [ ] Branch correta: v2.1-hardening
- [ ] Git status limpo
- [ ] ServiceDeskToolkit-Corporate.ps1 sem erro de sintaxe
- [ ] install.ps1 sem erro de sintaxe
- [ ] update.ps1 sem erro de sintaxe
- [ ] rollback.ps1 sem erro de sintaxe
- [ ] update.ps1 sem param global
- [ ] rollback.ps1 sem param global
- [ ] update.ps1 sem exit
- [ ] rollback.ps1 sem exit
- [ ] Quality Gate aprovado
- [ ] Toolkit abre com powershell.exe -STA
- [ ] Diagnostico gera TXT e JSON
- [ ] Update conclui com sucesso
- [ ] Rollback dry-run conclui com sucesso
- [ ] Botoes administrativos funcionam

## Comandos principais

Validar branch e status:
git branch --show-current
git status

Rodar Quality Gate:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-ToolkitQuality.ps1

Criar tag RC:
git tag v2.1.0-hardening-rc4
git push origin v2.1.0-hardening-rc4
