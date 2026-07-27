# ServiceDesk Toolkit Corporate V3.0.0-preview.2

Status: Preview interna validada
Branch de desenvolvimento: v3-corporate-redesign
Tag fixa: v3.0.0-preview.2

## Resumo

Esta preview mantém todos os recursos da v3.0.0-preview.1 e adiciona o Painel de Impressoras V3 com layout dos botões principais corrigido.

## Incluído nesta preview

- Painel de Impressoras - Diagnóstico Consolidado
- Botão Impressoras na área principal
- Layout dos botões principais padronizado
- Estilo ActionGridButton sem dependência problemática de StaticResource
- Grade uniforme com UniformGrid
- Validação do Painel de Impressoras no Test-ToolkitV3.ps1
- Exigência do Painel de Impressoras no install-v3.ps1
- Teste remoto da branch aprovado
- Instalação pela tag v3.0.0-preview.2 aprovada

## Recursos herdados da preview.1

- Interface V3 redesenhada
- Launcher ServiceDeskToolkitV3.cmd corrigido sem BOM
- Instalador oficial install-v3.ps1
- Instalação em pasta limpa por build dentro de LOCALAPPDATA
- Validador Test-ToolkitV3.ps1
- Inventário consolidado
- Diagnóstico de rede consolidado
- Diagnóstico automático de VPN / Appgate
- Limpeza segura de DNS
- Sincronização segura de horário
- Reinício seguro do Spooler
- Botão Copiar resultado

## Comando oficial de instalação

    $Version = "v3.0.0-preview.2"
    $Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/install-v3.ps1"
    $Installer = Join-Path $env:TEMP "install-v3-preview-2.ps1"
    Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Branch $Version

## Validação pós-instalação

    $Root = Join-Path $env:LOCALAPPDATA "ServiceDeskToolkitV3"
    $Latest = Get-ChildItem $Root -Directory -Filter "build-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    cd $Latest.FullName
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\Test-ToolkitV3.ps1"

## Observações

- A tag v3.0.0-preview.2 não deve ser movida.
- Novas alterações devem continuar na branch v3-corporate-redesign.
- A próxima versão preview deverá ser v3.0.0-preview.3.

## Próximos itens sugeridos

- Criar exportação TXT/HTML do resultado
- Criar histórico local de atendimentos
- Criar modo coleta rápida para N1
- Criar tela Sobre / Versão
