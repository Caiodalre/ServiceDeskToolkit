# ServiceDesk Toolkit Corporate V3

## Status

A V3 é uma nova experiência visual do ServiceDesk Toolkit Corporate.

A preview `3.0.0-preview.5` foi aprovada na homologação interna obrigatória. A
candidata atual é `3.0.0-rc.1`, preparada para validação final de release.

A V3 ainda não substitui a versão estável `v2.3.0` até a promoção formal para
`v3.0.0`.

## Homologação interna

A execução manual seguiu o [Plano de homologação da V3 preview 5](V3-PREVIEW5-HOMOLOGACAO.md). A rodada obrigatória foi concluída e aprovada em 27/07/2026 nos ambientes ENV-A e ENV-B.

O resultado sanitizado está registrado na [Issue #5](https://github.com/Caiodalre/ServiceDeskToolkit/issues/5).

Resultados públicos não devem conter usuários, domínio, endereços de rede, seriais, nomes de impressoras, credenciais ou pacotes de suporte.

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
- docs\V3-PREVIEW5-HOMOLOGACAO.md

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

- Validar instalação e reversão da `v3.0.0-rc.1`
- Confirmar os artefatos gerados pela CI
- Preservar o congelamento funcional durante a release candidate
- Preparar a promoção controlada para `v3.0.0`

## Observação

A versão estável oficial continua sendo a v2.3.0.

A V3 permanece em branch própria durante a release candidate e só será promovida após os critérios finais de release.
