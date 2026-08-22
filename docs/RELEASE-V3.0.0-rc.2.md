# ServiceDesk Toolkit Corporate V3.0.0-rc.2

Status: Candidata interna substituída antes da publicação da tag  
Base anterior: `v3.0.0-rc.1`  
Branch de desenvolvimento: `v3-corporate-redesign`  
Tag planejada: `v3.0.0-rc.2`

> A candidata foi integrada e validada, mas a tag pública não foi criada. Uma
> revisão transversal do repositório originou a `v3.0.0-rc.3`, que passa a ser
> a candidata oficial para publicação.

## Resumo

A `v3.0.0-rc.2` torna úteis os botões SFC e DISM da interface V3. As duas
ações agora executam as ferramentas nativas do Windows com confirmação,
elevação administrativa, acompanhamento de progresso, log técnico, resumo
final, trilha de auditoria e orientação de próxima ação.

## Alterações funcionais

- SFC executa `sfc.exe /scannow`
- DISM executa `dism.exe /Online /Cleanup-Image /RestoreHealth`
- Confirmação antes de iniciar ações administrativas
- Bloqueio de reparos concorrentes
- Janela separada para a execução elevada
- Progresso e tempo decorrido acompanhados pela tela principal
- Prazo de 30 segundos para detectar falha de inicialização
- Estados explícitos de conclusão, interrupção e falha
- Captura da saída nativa usando a página de código OEM do Windows
- Log completo, resumo final e auditoria em `logs\windows-repair`

## Evidências de homologação

- SFC concluído com código de saída `0`
- SFC informou ausência de violações de integridade
- DISM RestoreHealth concluído com código de saída `0`
- DISM informou que a restauração e a operação foram concluídas com êxito
- A interface exibiu o resultado final e registrou automaticamente os logs
- Testes executados em Windows 11 com privilégios administrativos

Os caminhos locais e dados identificáveis não são publicados nesta nota.

## Qualidade esperada

- Sintaxe compatível com Windows PowerShell 5.1
- Suíte Pester aprovada
- Validador técnico da V3 aprovado
- Integridade do instalador e dos marcadores de reparo verificada
- CI aprovada em Windows PowerShell 5.1 e PowerShell 7

## Instalação após a publicação da tag

```powershell
$Version = "v3.0.0-rc.2"
$Installer = Join-Path $env:TEMP "ServiceDeskToolkitV3-install.ps1"
$Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/install-v3.ps1"

Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Branch $Version
```

Não utilizar este comando antes da publicação da tag fixa.

## Reversão

A V3 permanece instalada em builds isoladas dentro de
`%LOCALAPPDATA%\ServiceDeskToolkitV3`. Em caso de bloqueio, interromper o uso
da candidata e retornar à versão estável `v2.3.0`.

## Critérios para promoção a v3.0.0

- CI verde em Windows PowerShell 5.1 e PowerShell 7
- Artefatos da RC gerados e inspecionados
- Instalação por tag fixa aprovada
- Abertura padrão e administrativa aprovadas
- Reversão e coexistência com V2 confirmadas
- Nenhum bloqueador ou defeito crítico aberto
- Decisão de promoção registrada
