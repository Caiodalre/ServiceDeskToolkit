# ServiceDesk Toolkit Corporate V3.0.0-preview.4

Status: Preview interna validada  
Branch de desenvolvimento: v3-corporate-redesign  
Tag fixa: v3.0.0-preview.4

## Resumo

Esta preview mantém todos os recursos da v3.0.0-preview.3 e adiciona o Painel de Saúde da Máquina.

O novo painel executa uma análise consolidada dos principais indicadores do computador, atribui uma pontuação geral de 0 a 100 e apresenta uma classificação automática.

A coleta é exclusivamente diagnóstica. Nenhuma correção é executada automaticamente.

## Incluído nesta preview

- Painel de Saúde da Máquina
- Função Invoke-V3MachineHealthPanel
- Botão Saúde da máquina na grade principal
- Substituição do placeholder Área avançada protegida
- Grade principal mantida com duas linhas de cinco botões
- Pontuação geral de 0 a 100
- Classificação automática:
  - Saudável
  - Atenção
  - Crítico
- Conclusão automática
- Lista de próximas ações recomendadas
- Identificação de reinício pendente
- Validação do painel no Test-ToolkitV3.ps1
- Exigência do painel no install-v3.ps1
- Teste local aprovado
- Teste remoto da branch aprovado
- Instalação pela tag v3.0.0-preview.4 aprovada

## Indicadores analisados

O Painel de Saúde da Máquina verifica:

- Sistema operacional
- Memória RAM instalada e utilização atual
- Espaço livre no disco do Windows
- Tempo de atividade da máquina
- Adaptador de rede, endereço IPv4 e gateway
- Resolução DNS
- Serviço e fonte de sincronização de horário
- Serviço Spooler
- Reinício pendente do Windows

## Critérios principais

### Memória RAM

- Uso igual ou superior a 80% gera atenção
- Uso igual ou superior a 90% gera estado crítico
- Quantidade reduzida de memória também influencia a classificação

### Disco do Windows

- Menos de 30 GB ou 20% livres gera atenção
- Menos de 15 GB ou 10% livres gera estado crítico

### Uptime

- Mais de 7 dias gera recomendação de reinício
- Mais de 30 dias gera estado crítico

### Rede

- Ausência de IPv4 válido gera estado crítico
- Endereço APIPA 169.254.x.x gera estado crítico
- Ausência de gateway gera atenção

## Estrutura do resultado

O painel apresenta:

- Data e horário da coleta
- Hostname
- Usuário conectado
- Estado administrativo da sessão
- Pontuação geral
- Classificação
- Indicadores individuais
- Pontos de atenção encontrados
- Conclusão automática
- Próximas ações
- Aviso operacional

## Segurança operacional

O Painel de Saúde:

- Não encerra processos
- Não remove arquivos
- Não limpa temporários
- Não reinicia serviços
- Não altera configurações de rede
- Não reinicia a máquina
- Não executa correções automaticamente

As correções permanecem disponíveis somente por ações específicas e controladas da ferramenta.

## Recursos herdados da preview.3

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
- Atendimento Guiado - Impressora Não Imprime
- Botões principais alinhados com UniformGrid
- Estilo ActionGridButton
- Botão Copiar resultado

## Comando oficial de instalação

    $Version = "v3.0.0-preview.4"
    $Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/install-v3.ps1"
    $Installer = Join-Path $env:TEMP "install-v3-preview-4.ps1"

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
- Grade principal permanece alinhada
- Botão Saúde da máquina está visível
- Painel abre sem erro
- Pontuação permanece entre 0 e 100
- Classificação automática é exibida
- Todos os indicadores são apresentados
- Conclusão automática é exibida
- Próximas ações são apresentadas
- Copiar resultado continua funcionando
- Nenhuma correção é executada automaticamente

## Observações

- A tag v3.0.0-preview.4 não deve ser movida ou recriada.
- Novas alterações devem continuar na branch v3-corporate-redesign.
- O documento desta release permanece na branch de desenvolvimento.
- A próxima versão preview deverá ser v3.0.0-preview.5.

## Próximos itens sugeridos

- Atendimento Guiado para Máquina Lenta
- Atendimento Guiado para Office / Teams
- Ações controladas no Painel de Impressoras
- Histórico local seguro de atendimentos
- Exportação estruturada de resultados
- Modularização gradual do código
