## v2.2.0 - Release Final

### Status
- Release final aprovada.
- Instalação validada pela tag `v2.2.0`.
- Update validado pela tag `v2.2.0`.
- Quality Gate aprovado.
- Pacote de suporte gerado com sucesso.
- Resumo final do update gerado com `FAIL: 0`.

### Principais entregas
- Instalação e update agora respeitam `source-ref.json`.
- `source-ref.json` registra a origem instalada.
- Novo validador de integridade instalada:
  - `tools\Test-ToolkitInstalled.ps1`
- Novo exportador de pacote de suporte:
  - `tools\Export-ToolkitSupportPackage.ps1`
- Update com resumo final em TXT e JSON:
  - `reports\update-summary-*.txt`
  - `reports\update-summary-*.json`
- Interface com ações administrativas ampliadas:
  - Validar instalação do Toolkit
  - Gerar pacote de suporte
  - Abrir último resumo do update
  - Resumo dos logs do Toolkit

### Evidências finais
- Instalação: APROVADO
- Quality Gate: APROVADO
- Pacote de suporte: APROVADO
- Update final: APROVADO
- WARN: 0
- FAIL: 0

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
