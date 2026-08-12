# ServiceDesk Toolkit Corporate

[![CI](https://github.com/Caiodalre/ServiceDeskToolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/Caiodalre/ServiceDeskToolkit/actions/workflows/ci.yml)
![Windows](https://img.shields.io/badge/platform-Windows-0078D4)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-5391FE)
![V3](https://img.shields.io/badge/V3-3.0.1%20stable-2ea44f)

Central de atendimento técnico em PowerShell para diagnóstico, evidências e
correções controladas em estações Windows.

O projeto foi criado para reduzir o tempo de triagem do Service Desk, padronizar
procedimentos e tornar explícita a diferença entre diagnóstico, correção segura
e ação administrativa avançada.

## Canais do projeto

| Canal | Referência | Uso recomendado |
| --- | --- | --- |
| V3 estável | `v3.0.1` | SHA-256 homologado em Windows 10 e 11 |
| Preview Office/TPM | `v3.1.0-preview.1` | Homologação interna; não usar em produção |
| V3 anterior | `v3.0.0` | Fallback temporário da linha V3 |
| V2 legado | `v2.3.0` | Fallback para instalações anteriores |
| Desenvolvimento | `v3-corporate-redesign` | Evolução controlada da V3 |

A `v3.0.1` é o canal estável após homologação funcional em mais de 10
máquinas e validação da distribuição SHA-256 em Windows 10 e 11. A tag
`v2.3.0` permanece imutável como fallback legado.

## Capacidades

- Inventário e painel de saúde da máquina
- Diagnóstico de rede, DNS, VPN e Appgate
- Atendimento guiado para falhas comuns
- Diagnóstico de impressoras e fila de impressão
- Suporte a Teams, Office, OneDrive e Microsoft Store
- Diagnóstico Office/TPM, WAM e licenciamento do Microsoft 365 e Office 2016/2019/2021
- Reparo confirmado dos componentes WAM no perfil afetado
- Relatórios, logs estruturados e pacote de suporte
- Base de conhecimento local pesquisável
- Atualização com staging, backup e rollback
- Confirmação para ações administrativas críticas

## Requisitos

- Windows 10 ou 11
- Windows PowerShell 5.1 ou PowerShell 7+
- PowerShell em modo STA para a interface WPF
- Privilégios administrativos apenas para as ações que os exigem

## Instalação

### V3 estável

Abra o PowerShell como administrador. O instalador e o manifesto são baixados
para arquivos temporários. O instalador só é executado após a conferência do
seu SHA-256:

```powershell
$Version = "v3.0.1"
$BaseUrl = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version"
$Installer = Join-Path $env:TEMP "ServiceDeskToolkitV3-$Version.ps1"
$ManifestFile = Join-Path $env:TEMP "ServiceDeskToolkitV3-$Version-checksums.json"

Invoke-WebRequest -Uri "$BaseUrl/install-v3.ps1" -OutFile $Installer -UseBasicParsing
Invoke-WebRequest -Uri "$BaseUrl/checksums-v3.json" -OutFile $ManifestFile -UseBasicParsing

$Manifest = Get-Content $ManifestFile -Raw | ConvertFrom-Json
$Expected = @($Manifest.files | Where-Object { $_.path -eq "install-v3.ps1" })

if ($Expected.Count -ne 1) {
    throw "Manifesto inválido para install-v3.ps1."
}

$ActualHash = (Get-FileHash $Installer -Algorithm SHA256).Hash
if ($ActualHash -ne $Expected[0].sha256) {
    throw "Falha de integridade no instalador V3."
}

powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer
```

A instalação padrão utiliza builds isoladas dentro de
`%LOCALAPPDATA%\ServiceDeskToolkitV3`. O instalador valida novamente todos
os componentes antes de gravá-los.

### Histórico da candidata

A `v3.0.1-rc.1` foi aprovada em Windows 10 e Windows 11 e promovida sem
alterações funcionais para `v3.0.1`.

### V2.3.0 — fallback legado

```powershell
$Version = "v2.3.0"
$Installer = Join-Path $env:TEMP "ServiceDeskToolkit-bootstrap.ps1"
$Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/bootstrap.ps1"

Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer
```

> Revise o script baixado antes da execução e prefira sempre referências
> versionadas. Branches de desenvolvimento são mutáveis e não devem ser usadas
> em produção.

## Validação local

```powershell
# Quality Gate da V2
powershell.exe -NoProfile -File .\tools\Test-ToolkitQuality.ps1

# Validação de release
powershell.exe -NoProfile -File .\tools\Test-ToolkitRelease.ps1

# Validação da V3
powershell.exe -NoProfile -File .\tools\Test-ToolkitV3.ps1

# Integridade do manifesto de distribuição
powershell.exe -NoProfile -File .\tools\New-ToolkitChecksumManifest.ps1 -Check

# Testes de repositório com Pester 5.7.1
Invoke-Pester -Path .\tests -Output Detailed
```

Os validadores retornam código `0` quando aprovados e código diferente de zero
quando encontram falhas, permitindo integração confiável com CI.

Os painéis de Saúde, Inventário, Rede, Impressoras e Office/TPM da V3 já
utilizam módulos separados para coleta, avaliação das regras e formatação dos
relatórios. O diagnóstico Office/TPM é somente leitura; o reparo WAM exige
confirmação e não limpa TPM, credenciais ou vínculo Entra.

## Estrutura

```text
ServiceDeskToolkit-Corporate.ps1    Aplicação operacional V2
ServiceDeskToolkit-CorporateV3.ps1  Aplicação estável V3
data/knowledge-base.json            Base de conhecimento local
src/                                Módulos de diagnóstico e regras de domínio
tools/                              Diagnóstico e validadores
tests/                              Contratos automatizados do repositório
docs/                               Runbooks, arquitetura e releases
.github/workflows/ci.yml            Validação contínua
```

Consulte [Arquitetura](docs/ARCHITECTURE.md),
[Roadmap](docs/ROADMAP-PROFISSIONALIZACAO.md) e
[Como contribuir](CONTRIBUTING.md). O contrato técnico está em
[Padrões de engenharia](docs/REPOSITORY-STANDARDS.md).

## Segurança

Este toolkit consulta informações do sistema e também oferece ações que podem
alterar serviços, rede, cache, impressão e componentes do Windows. Use primeiro
os diagnósticos, preserve evidências e execute correções somente com autorização.

Vulnerabilidades devem seguir o processo descrito em [SECURITY.md](SECURITY.md).
Não publique dados corporativos, credenciais ou pacotes de suporte em issues.

## Licença

O repositório ainda não possui uma licença pública definida. Uso, cópia e
redistribuição dependem da autorização do proprietário até que uma licença seja
formalmente escolhida.
