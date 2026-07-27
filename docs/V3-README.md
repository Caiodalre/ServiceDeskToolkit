# ServiceDesk Toolkit Corporate V3

## Status

A V3 é uma nova experiência visual do ServiceDesk Toolkit Corporate.

Ela ainda está em fase de preview técnico e não substitui a versão estável v2.3.0.

Desenvolvimento atual: `3.0.0-preview.5-dev`, na branch
`v3-corporate-redesign`. A última preview publicada é `v3.0.0-preview.4`.

## Objetivo da V3

Criar uma interface mais limpa, organizada e corporativa para uso em Service Desk, mantendo a base técnica do toolkit atual como motor.

## Como executar

Pelo CMD:

    ServiceDeskToolkitV3.cmd

Ou pelo PowerShell:

    powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File ".\ServiceDeskToolkit-CorporateV3.ps1"

## Como validar

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\Test-ToolkitV3.ps1"

Resultado esperado:

    APROVADO - V3 validada sem falhas.

## Arquivos principais

- ServiceDeskToolkit-CorporateV3.ps1
- ServiceDeskToolkitV3.cmd
- version-v3.json
- src\ServiceDeskToolkit.Diagnostics\ServiceDeskToolkit.Diagnostics.psm1
- src\ServiceDeskToolkit.Health\ServiceDeskToolkit.Health.psm1
- src\ServiceDeskToolkit.Inventory\ServiceDeskToolkit.Inventory.psm1
- src\ServiceDeskToolkit.Network\ServiceDeskToolkit.Network.psm1
- src\ServiceDeskToolkit.Printers\ServiceDeskToolkit.Printers.psm1
- tools\Test-ToolkitV3.ps1
- docs\V3-CORPORATE-REDESIGN-ESCOPO.md

## O que já funciona

- Shell visual inicial da V3
- Sidebar corporativa
- Cards de status da máquina
- Área de resultado central
- Botões de atendimento rápido
- Links LinkedIn e GitHub com proteção contra abertura dupla
- Launcher CMD
- Validador técnico da V3
- Metadados de versão exclusivos da V3
- Pipeline de CI para Windows PowerShell 5.1 e PowerShell 7
- Painel de Saúde com coleta e avaliação modularizadas
- Inventário, Rede e Impressoras com coleta, avaliação e relatório modularizados

## Próximas etapas

- Conectar funções reais da V2.4 no fluxo visual da V3
- Melhorar atendimento guiado por problema
- Criar tela de evidências
- Criar confirmações para ações avançadas
- Integrar a V3 no fluxo de validação e release

## Observação

A versão estável oficial continua sendo a v2.3.0.

A V3 deve evoluir em branch própria até estar madura para uma release futura.
