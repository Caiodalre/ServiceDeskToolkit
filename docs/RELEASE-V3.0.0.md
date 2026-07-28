# ServiceDesk Toolkit Corporate V3.0.0

Status: versão estável

Base homologada: `v3.0.0-rc.3`

Tag: `v3.0.0`

Data: 28/07/2026

## Resumo

A V3.0.0 é a primeira versão estável da nova experiência corporativa do
ServiceDesk Toolkit. A promoção preserva exatamente a base funcional homologada
na RC3 e altera somente o canal de distribuição, os metadados e a documentação
da versão.

## Homologação

- Instalação aprovada em máquinas diferentes
- Abertura normal e administrativa aprovada
- Diagnósticos de Saúde, Inventário, Rede e Impressoras aprovados
- Logs e relatórios gerados corretamente
- SFC e DISM executados com confirmação, elevação, progresso e resumo
- CI aprovada em Windows PowerShell 5.1 e PowerShell 7
- 45 testes Pester aprovados
- Validadores de padrões, V2, release e V3 aprovados

## Instalação

Abra o PowerShell como administrador:

```powershell
$Version = "v3.0.0"
$Installer = Join-Path $env:TEMP "ServiceDeskToolkitV3-stable.ps1"
$Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/install-stable.ps1"

Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer
```

O conteúdo remoto é baixado para arquivo antes da execução. Não use pipe para
`Invoke-Expression`.

## Operação

A instalação padrão utiliza builds isolados em
`%LOCALAPPDATA%\ServiceDeskToolkitV3`. O arquivo `latest.txt` aponta para o
build ativo, e o instalador cria o atalho **ServiceDesk Toolkit V3**.

## Segurança

- Diagnósticos permanecem somente leitura
- Correções administrativas exigem confirmação
- SFC e DISM solicitam elevação pelo Windows
- Logs e pacotes de suporte devem ser sanitizados antes do compartilhamento
- A tag `v3.0.0` é imutável

## Fallback

A tag `v2.3.0` permanece disponível como fallback legado. Use-a somente quando
uma regressão da V3 impedir o atendimento e registre o motivo da reversão.

## Dívida técnica controlada

- Checksums de release ainda serão implementados
- Assinatura Authenticode permanece em avaliação
- Partes da aplicação V2 continuam monolíticas, mas não são o entrypoint estável
- A modularização de Office/Teams, VPN, logging e correções seguras continuará
  em versões futuras
