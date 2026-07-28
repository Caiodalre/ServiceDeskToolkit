# ServiceDesk Toolkit Corporate V3.0.0-rc.3

Status: Release candidate em validação final  
Base funcional: `v3.0.0-rc.2`  
Branch de desenvolvimento: `v3-corporate-redesign`  
Tag planejada: `v3.0.0-rc.3`

## Resumo

A `v3.0.0-rc.3` preserva o fluxo homologado de SFC e DISM e profissionaliza o
repositório de forma transversal. A candidata alinha código, distribuição,
metadados, documentação e CI a um contrato único de engenharia.

## Padronização aplicada

- Validador transversal de padrões do repositório
- Sintaxe PowerShell verificada em todos os scripts e módulos
- Nomes de funções alinhados aos verbos aprovados pelo PowerShell
- UTF-8, BOM e finais de linha normalizados por tipo de arquivo
- JSON validado automaticamente
- Metadados, instaladores, README e changelog sincronizados
- Comandos de instalação remota alterados para download em arquivo
- Instalador estável corrigido para a tag `v2.3.0`
- Inicialização duplicada removida da proteção de links externos da V3

## Controles de segurança

- Proibição automatizada de `Invoke-Expression` e `iex` em código executável
- Detecção de pipe inseguro nos metadados e no runbook
- Preservação da confirmação e elevação nas ações administrativas
- Manutenção da V2.3.0 como fallback operacional
- Documentação pública sem dados locais ou corporativos

## Qualidade esperada

- `Test-RepositoryStandards.ps1` aprovado
- Pester aprovado
- Quality Gate da V2 aprovado
- Validador de release aprovado
- Validador da V3 aprovado
- CI verde em Windows PowerShell 5.1 e PowerShell 7

## Instalação após a publicação da tag

```powershell
$Version = "v3.0.0-rc.3"
$Installer = Join-Path $env:TEMP "ServiceDeskToolkitV3-install.ps1"
$Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/install-v3.ps1"

Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Branch $Version
```

Não utilizar este comando antes da publicação da tag fixa.

## Reversão

A V3 permanece isolada em `%LOCALAPPDATA%\ServiceDeskToolkitV3`. Em caso de
bloqueio, interromper o uso da candidata e retornar à versão estável `v2.3.0`.

## Critérios para promoção

- CI aprovada nos dois motores PowerShell
- Artefatos de validação gerados e inspecionados
- Instalação pela tag fixa aprovada
- Abertura padrão e administrativa aprovadas
- Reversão e coexistência com a V2 confirmadas
- Nenhum bloqueador ou defeito crítico aberto
