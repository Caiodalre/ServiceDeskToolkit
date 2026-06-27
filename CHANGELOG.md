# Changelog - ServiceDesk Toolkit Corporate

## v2.1.0-hardening RC5

### Adicionado

- Bootstrap seguro sem BOM para instalacao remota via irm | iex.
- Bootstrap baixa install.ps1 para arquivo temporario e executa com powershell.exe -File.

## v2.1.0-hardening RC3

### Adicionado

- Logs estruturados JSONL: runtime, actions e errors.
- Handlers globais de erro WPF/AppDomain.
- Base de Conhecimento via JSON.
- Diagnostico automatico TXT e JSON.
- Quality Gate automatizado.
- Install.ps1 baixando tools, update.ps1 e rollback.ps1.
- Update seguro com staging, validacao, backup e log.
- Rollback seguro com dry-run padrao.
- Botoes administrativos na interface:
  - ATUALIZAR TOOLKIT
  - TESTAR ROLLBACK DRY-RUN
  - ABRIR LOGS UPDATE/ROLLBACK
  - ABRIR BACKUPS

### Corrigido

- Caminhos entre GITHUB-UPLOAD e C:\ServiceDeskToolkit.
- Encoding UTF-8 BOM para Windows PowerShell 5.1.
- Diagnostico ausente na instalacao final.
- Uso indevido de exit em scripts remotos.
- Validacao incorreta de param dentro de funcoes.

## v2.0.2-compat

Versao estavel anterior preservada para compatibilidade.
