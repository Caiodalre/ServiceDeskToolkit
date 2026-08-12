# ServiceDesk Toolkit Corporate V3

## Status

A V3 é a experiência estável atual do ServiceDesk Toolkit Corporate.

Versão estável atual: `3.0.1`, promovida a partir da candidata de segurança
`3.0.1-rc.1`.

A `3.1.0-preview.1` inicia a homologação interna do novo painel Office/TPM e
do reparo controlado de autenticação WAM. Ela não substitui a versão estável.

A versão preserva o reparo operacional do Windows com SFC e DISM, os painéis
modulares e a camada transversal de padrões de engenharia. A tag `v2.3.0`
permanece disponível como fallback legado.

## Homologação interna

A base `3.0.0-preview.5` foi aprovada em 27/07/2026 nos ambientes ENV-A e
ENV-B, conforme o
[plano de homologação](V3-PREVIEW5-HOMOLOGACAO.md) e a
[Issue #5](https://github.com/Caiodalre/ServiceDeskToolkit/issues/5).

Na rodada complementar da RC2, o SFC concluiu sem violações de integridade e o
DISM RestoreHealth concluiu com êxito. Os dois testes geraram log, resumo e
trilha de auditoria pelo toolkit.

A RC3 foi instalada e validada em mais de 10 máquinas, sem erros relatados.
A instalação remota, a interface, os diagnósticos, as ações administrativas e
a geração de logs foram aprovados antes e depois da promoção para `3.0.0`.

A `3.0.1-rc.1` acrescentou integridade SHA-256 sem alterar as funções do
toolkit. A instalação e a regressão básica foram aprovadas em Windows 10 e
Windows 11 antes da promoção para `3.0.1`.

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
- checksums-v3.json
- src\ServiceDeskToolkit.Diagnostics\ServiceDeskToolkit.Diagnostics.psm1
- src\ServiceDeskToolkit.Health\ServiceDeskToolkit.Health.psm1
- src\ServiceDeskToolkit.Inventory\ServiceDeskToolkit.Inventory.psm1
- src\ServiceDeskToolkit.Network\ServiceDeskToolkit.Network.psm1
- src\ServiceDeskToolkit.Printers\ServiceDeskToolkit.Printers.psm1
- src\ServiceDeskToolkit.Office\ServiceDeskToolkit.Office.psm1
- tools\Test-ToolkitV3.ps1
- docs\OFFICE-TPM-RUNBOOK.md
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
- Office/TPM para Microsoft 365 e Office 2016/2019/2021, com WAM, vnextdiag, OSPP e Entra
- Reparo WAM confirmado, restrito ao perfil atual e com trilha de auditoria
- SFC e DISM operacionais, com confirmação, elevação administrativa, progresso,
  log técnico, resumo final e próxima ação recomendada
- Validação transversal de sintaxe, encoding, finais de linha, JSON, verbos
  PowerShell, distribuição segura e consistência de versão

## Office, TPM e autenticação

O botão **Office / TPM** coleta evidências sem alterar o computador. O resultado
correlaciona estado do TPM, proteção BitLocker, reinicialização pendente,
registro dos componentes WAM, licenciamento moderno do Office e os campos
seguros do `dsregcmd /status`.

O botão **Reparar login Office** registra novamente AAD BrokerPlugin e
CloudExperienceHost no perfil afetado. Ele exige confirmação e recusa a
execução enquanto aplicativos Office ou Teams estiverem abertos.

Limpeza do TPM, exclusão de caches e credenciais, remoção de vínculo Entra e
reset indiscriminado de licenças são ações críticas orientadas pelo
[runbook Office/TPM](OFFICE-TPM-RUNBOOK.md), não automatizadas.

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

- Monitorar a adoção interna da `v3.0.1`
- Registrar incidentes e regressões com evidências sanitizadas
- Manter Authenticode fora do escopo conforme a decisão operacional
- Atualizar as actions do CI para versões nativas de Node.js 24
- Evoluir módulos e testes somente em nova versão controlada

## Observação

A versão estável oficial é a `v3.0.1`. A `v3.0.0` permanece como
fallback temporário da linha V3 e a V2.3.0 como fallback legado.
