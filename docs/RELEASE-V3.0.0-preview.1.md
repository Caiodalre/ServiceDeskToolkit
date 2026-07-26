# ServiceDesk Toolkit Corporate V3.0.0-preview.1

Status: Preview interna validada
Branch de desenvolvimento: v3-corporate-redesign
Tag fixa: v3.0.0-preview.1

## Resumo

Esta preview representa a primeira versão instalável e validável da V3 do ServiceDesk Toolkit Corporate.

A V3 tem foco em interface mais limpa, execução segura, saída técnica organizada e facilidade para copiar evidências para chamados.

## Recursos validados

- Interface V3 redesenhada
- Launcher ServiceDeskToolkitV3.cmd corrigido sem BOM
- Instalador oficial install-v3.ps1
- Instalação em pasta limpa por build dentro de LOCALAPPDATA
- Arquivo latest.txt apontando para a última instalação válida
- Validador Test-ToolkitV3.ps1
- Inventário consolidado
- Diagnóstico de rede consolidado
- Diagnóstico automático de VPN / Appgate
- Limpeza segura de DNS
- Sincronização segura de horário
- Reinício seguro do Spooler
- Botão Copiar resultado

## Comando oficial de instalação

    $Version = "v3.0.0-preview.1"
    $Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/install-v3.ps1"
    $Installer = Join-Path $env:TEMP "install-v3-preview.ps1"
    Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Branch $Version

## Comando para instalar sem criar atalho

    $Version = "v3.0.0-preview.1"
    $Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/install-v3.ps1"
    $Installer = Join-Path $env:TEMP "install-v3-preview.ps1"
    Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Branch $Version -NoShortcut

## Validação pós-instalação

    $Root = Join-Path $env:LOCALAPPDATA "ServiceDeskToolkitV3"
    $Latest = Get-ChildItem $Root -Directory -Filter "build-*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    cd $Latest.FullName
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tools\Test-ToolkitV3.ps1"

## Observações

- A tag v3.0.0-preview.1 não deve ser movida.
- Novas alterações devem continuar na branch v3-corporate-redesign.
- A próxima versão preview deverá ser v3.0.0-preview.2.
- Correções administrativas, como Spooler, devem ser executadas como administrador.

## Próximos itens sugeridos

- Melhorar painel de Impressoras
- Criar exportação TXT/HTML do resultado
- Criar histórico local de atendimentos
- Criar modo coleta rápida para N1
- Criar tela Sobre / Versão
