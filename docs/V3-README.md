# ServiceDesk Toolkit Corporate V3

## Status

A V3 é uma nova experiência visual do ServiceDesk Toolkit Corporate.

Ela está em fase de release candidate e ainda não substitui a versão estável
`v2.3.0`.

Release candidate atual: `3.0.0-rc.3`, preparada a partir da branch
`v3-corporate-redesign`. Esta RC preserva o reparo operacional do Windows com
SFC e DISM e adiciona uma camada transversal de padrões de engenharia.

## Homologação interna

A base `3.0.0-preview.5` foi aprovada em 27/07/2026 nos ambientes ENV-A e
ENV-B, conforme o
[plano de homologação](V3-PREVIEW5-HOMOLOGACAO.md) e a
[Issue #5](https://github.com/Caiodalre/ServiceDeskToolkit/issues/5).

Na rodada complementar da RC2, o SFC concluiu sem violações de integridade e o
DISM RestoreHealth concluiu com êxito. Os dois testes geraram log, resumo e
trilha de auditoria pelo toolkit.

Resultados públicos não devem conter usuários, domínio, endereços de rede,
seriais, nomes de impressoras, credenciais ou pacotes de suporte.

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
- SFC e DISM operacionais, com confirmação, elevação administrativa, progresso,
  log técnico, resumo final e próxima ação recomendada
- Validação transversal de sintaxe, encoding, finais de linha, JSON, verbos
  PowerShell, distribuição segura e consistência de versão

## Reparo do Windows com SFC e DISM

Os botões ficam em **Ações principais da V3**:

- **SFC: verificar arquivos** executa `sfc.exe /scannow`.
- **DISM: reparar imagem** executa
  `dism.exe /Online /Cleanup-Image /RestoreHealth`.

Após a confirmação, o Windows solicita permissão administrativa e abre uma
janela separada com o progresso nativo. A tela principal acompanha o processo,
mostra o tempo decorrido e as últimas mensagens do Windows. Ao terminar, ela
exibe automaticamente a conclusão e a próxima ação recomendada. Se a janela
administrativa for fechada antes do fim, o toolkit informa que o reparo foi
interrompido e não considera o diagnóstico concluído.

Se a rotina elevada não começar em até 30 segundos, a tela informa falha de
inicialização em vez de permanecer indefinidamente em andamento.

O toolkit salva o log completo, um resumo final e uma trilha de auditoria em
`logs\windows-repair`.

Quando o SFC informar que não conseguiu reparar todos os arquivos, a ordem
recomendada é:

1. Executar o DISM.
2. Reiniciar o computador, se solicitado.
3. Executar o SFC novamente.

## Próximas etapas

- Validar a CI da `v3.0.0-rc.3` em Windows PowerShell 5.1 e PowerShell 7
- Confirmar os artefatos gerados pela CI
- Validar instalação e reversão usando a tag fixa
- Preservar o congelamento funcional durante a release candidate
- Preparar a promoção controlada para `v3.0.0`

## Observação

A versão estável oficial continua sendo a v2.3.0.

A V3 permanece em branch própria durante a release candidate e só será
promovida após os critérios finais de release.
