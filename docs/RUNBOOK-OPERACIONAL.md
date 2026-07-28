# ServiceDesk Toolkit Corporate - Runbook Operacional

## Objetivo

Orientar a instalação e o uso seguro do ServiceDesk Toolkit Corporate V3 em
ambiente de suporte técnico.

## Versões suportadas

| Referência | Situação |
| --- | --- |
| `v3.0.0` | Versão estável atual |
| `v2.3.0` | Fallback legado |
| `v3-corporate-redesign` | Desenvolvimento, não usar em produção |

## Instalação estável

Abra o PowerShell como administrador:

```powershell
$Version = "v3.0.0"
$Installer = Join-Path $env:TEMP "ServiceDeskToolkitV3-stable.ps1"
$Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/install-stable.ps1"

Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer
```

O instalador baixa o script oficial para arquivo, valida sua sintaxe e confirma
os marcadores do produto antes da execução.

## Caminho padrão

```text
%LOCALAPPDATA%\ServiceDeskToolkitV3
```

Cada instalação cria um build isolado. O arquivo `latest.txt` aponta para o
build ativo.

## Abrir o Toolkit

Use o atalho **ServiceDesk Toolkit V3** criado na Área de Trabalho.

Para abrir manualmente:

```powershell
$Root = Join-Path $env:LOCALAPPDATA "ServiceDeskToolkitV3"
$Build = Get-Content (Join-Path $Root "latest.txt") -Raw
& (Join-Path $Build "ServiceDeskToolkitV3.cmd")
```

## Diagnósticos

Os painéis de Saúde, Inventário, Rede e Impressoras são somente leitura. Preserve
o resultado antes de executar qualquer correção.

Os relatórios e logs ficam dentro do build ativo:

```text
reports\
logs\
logs\windows-repair\
```

## SFC e DISM

- **SFC: verificar arquivos** executa `sfc.exe /scannow`.
- **DISM: reparar imagem** executa
  `dism.exe /Online /Cleanup-Image /RestoreHealth`.

Essas ações exigem confirmação e elevação administrativa. Não feche a janela
elevada durante a execução. Ao terminar, guarde o resumo e valide o sintoma
original.

Quando o SFC não conseguir reparar todos os arquivos:

1. Execute o DISM.
2. Reinicie o computador, se solicitado.
3. Execute o SFC novamente.

## Reinstalação e atualização

Execute novamente o instalador estável. Um novo build isolado será criado e o
`latest.txt` será atualizado somente após a validação do pacote.

## Fallback para V2.3.0

Use apenas quando uma regressão da V3 impedir o atendimento:

```powershell
$Version = "v2.3.0"
$Installer = Join-Path $env:TEMP "ServiceDeskToolkit-bootstrap.ps1"
$Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/bootstrap.ps1"

Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer
```

A V2 utiliza `C:\ServiceDeskToolkit` e mantém seu próprio fluxo de atualização
e rollback.

## Regra operacional

- Não execute scripts remotos por pipe.
- Use sempre uma tag fixa.
- Baixe para arquivo e revise a origem antes da execução.
- Não publique logs com dados pessoais, corporativos ou credenciais.
- Registre versão, horário, ação executada e resultado da correção.
