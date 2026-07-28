# ServiceDesk Toolkit Corporate V3.0.0-preview.3

Status: Preview interna validada  
Branch de desenvolvimento: v3-corporate-redesign  
Tag fixa: v3.0.0-preview.3

## Resumo

Esta preview mantém todos os recursos da v3.0.0-preview.2 e adiciona o Atendimento Guiado para o cenário "Impressora não imprime".

O novo fluxo reutiliza o Painel de Impressoras V3 para coletar evidências automáticas, apresentar causas prováveis e orientar as próximas ações do analista.

## Incluído nesta preview

- Atendimento Guiado - Impressora Não Imprime
- Função Invoke-V3WorkflowPrinter
- Integração com o motor New-V3WorkflowResult
- Uso automático do Invoke-V3PrintersPanel como coleta técnica
- Inclusão do fluxo na tela Atendimento Guiado
- Botão Impressoras conectado ao novo fluxo
- Identificação de causas prováveis de falha de impressão
- Orientação para Spooler, filas, impressora padrão, porta, IP e driver
- Aviso para não limpar filas sem validar o impacto
- Validação do novo fluxo no Test-ToolkitV3.ps1
- Exigência do novo fluxo no install-v3.ps1
- Teste local aprovado
- Teste remoto da branch aprovado
- Instalação pela tag v3.0.0-preview.3 aprovada

## Estrutura do fluxo

O Atendimento Guiado de Impressoras apresenta:

- Problema relatado
- Coleta automática
- Painel de Impressoras - Diagnóstico Consolidado
- Causas prováveis
- Próximas ações
- Nível de risco
- Observação operacional

Nenhuma correção destrutiva é executada automaticamente.

## Recursos herdados da preview.2

- Interface V3 redesenhada
- Launcher ServiceDeskToolkitV3.cmd sem BOM
- Instalador oficial install-v3.ps1
- Instalação isolada por build em LOCALAPPDATA
- Validador Test-ToolkitV3.ps1
- Inventário consolidado
- Diagnóstico de rede consolidado
- Diagnóstico automático de VPN / Appgate
- Limpeza segura de DNS
- Sincronização segura de horário
- Reinício seguro do Spooler
- Painel de Impressoras consolidado
- Botões principais alinhados com UniformGrid
- Estilo ActionGridButton
- Botão Copiar resultado

## Comando oficial de instalação

    $Version = "v3.0.0-preview.3"
    $Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/install-v3.ps1"
    $Installer = Join-Path $env:TEMP "install-v3-preview-3.ps1"

    Invoke-WebRequest `
        -Uri $Url `
        -OutFile $Installer `
        -UseBasicParsing

    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File $Installer `
        -Branch $Version

## Validação pós-instalação

    $Root = Join-Path $env:LOCALAPPDATA "ServiceDeskToolkitV3"

    $Latest = Get-ChildItem $Root -Directory -Filter "build-*" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    Set-Location $Latest.FullName

    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File ".\tools\Test-ToolkitV3.ps1"

Resultado esperado:

    APROVADO - V3 validada sem falhas.

## Validação funcional

- Interface abre corretamente
- Botões permanecem alinhados
- Impressoras abre o atendimento guiado
- Painel técnico aparece em Coleta Automática
- Causas prováveis são exibidas
- Próximas ações são exibidas
- Reiniciar Spooler continua funcionando separadamente
- Copiar resultado funciona

## Observações

- A tag v3.0.0-preview.3 não deve ser movida ou recriada.
- Novas alterações devem continuar na branch v3-corporate-redesign.
- O documento desta release permanece na branch de desenvolvimento.
- A próxima versão preview deverá ser v3.0.0-preview.4.

## Próximos itens sugeridos

- Painel de Saúde da Máquina
- Atendimento Guiado para Máquina Lenta
- Atendimento Guiado para Office / Teams
- Ações controladas no Painel de Impressoras
- Histórico local seguro de atendimentos
- Modularização gradual do código
