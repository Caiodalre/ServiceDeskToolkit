$ErrorActionPreference = "Continue"

$Root = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Root "ServiceDeskToolkit-CorporateV3.ps1"
$Cmd = Join-Path $Root "ServiceDeskToolkitV3.cmd"
$Readme = Join-Path $Root "docs\V3-README.md"
$VersionFile = Join-Path $Root "version-v3.json"
$ChecksumManifest = Join-Path $Root "checksums-v3.json"
$DiagnosticsModule = Join-Path `
    $Root `
    "src\ServiceDeskToolkit.Diagnostics\ServiceDeskToolkit.Diagnostics.psm1"
$HealthModule = Join-Path `
    $Root `
    "src\ServiceDeskToolkit.Health\ServiceDeskToolkit.Health.psm1"
$InventoryModule = Join-Path `
    $Root `
    "src\ServiceDeskToolkit.Inventory\ServiceDeskToolkit.Inventory.psm1"
$NetworkModule = Join-Path `
    $Root `
    "src\ServiceDeskToolkit.Network\ServiceDeskToolkit.Network.psm1"
$PrintersModule = Join-Path `
    $Root `
    "src\ServiceDeskToolkit.Printers\ServiceDeskToolkit.Printers.psm1"
$OfficeModule = Join-Path `
    $Root `
    "src\ServiceDeskToolkit.Office\ServiceDeskToolkit.Office.psm1"
$Reports = Join-Path $Root "reports"

if (-not (Test-Path $Reports)) {
    New-Item -ItemType Directory -Path $Reports -Force | Out-Null
}

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ReportTxt = Join-Path $Reports "v3-validation-$stamp.txt"

$results = New-Object System.Collections.Generic.List[string]
$failures = 0

function Write-V3ValidationLine {
    param(
        [string]$Status,
        [string]$Message
    )

    $line = "[$Status] $Message"

    switch ($Status) {
        "OK" {
            Write-Host $line -ForegroundColor Green
        }
        "FALHA" {
            Write-Host $line -ForegroundColor Red
        }
        "AVISO" {
            Write-Host $line -ForegroundColor Yellow
        }
        default {
            Write-Host $line -ForegroundColor Gray
        }
    }
}

function Add-Result {
    param(
        [string]$Status,
        [string]$Message
    )

    $line = "[$Status] $Message"
    $script:results.Add($line) | Out-Null

    Write-V3ValidationLine -Status $Status -Message $Message

    if ($Status -eq "FALHA") {
        $script:failures++
    }
}
Write-Host ""
Write-Host "ServiceDesk Toolkit Corporate V3 - Validation" -ForegroundColor Cyan
Write-Host "Root: $Root" -ForegroundColor DarkCyan
Write-Host ""

Add-Result "OK" "Validacao iniciada em $stamp"

if (Test-Path $App) {
    Add-Result "OK" "Arquivo existe: ServiceDeskToolkit-CorporateV3.ps1"
}
else {
    Add-Result "FALHA" "Arquivo nao encontrado: ServiceDeskToolkit-CorporateV3.ps1"
}

if (Test-Path $VersionFile) {
    try {
        $versionInfo = Get-Content $VersionFile -Raw | ConvertFrom-Json

        if ([string]::IsNullOrWhiteSpace([string]$versionInfo.version)) {
            Add-Result "FALHA" "version-v3.json nao informa version"
        }
        else {
            Add-Result "OK" "Versao V3 declarada: $($versionInfo.version)"
        }

        if ([string]::IsNullOrWhiteSpace([string]$versionInfo.channel)) {
            Add-Result "FALHA" "version-v3.json nao informa channel"
        }
        else {
            Add-Result "OK" "Canal V3 declarado: $($versionInfo.channel)"
        }
    }
    catch {
        Add-Result "FALHA" "version-v3.json invalido: $($_.Exception.Message)"
    }
}
else {
    Add-Result "FALHA" "Arquivo nao encontrado: version-v3.json"
}

if (Test-Path $ChecksumManifest) {
    try {
        $manifestInfo = Get-Content $ChecksumManifest -Raw | ConvertFrom-Json
        $manifestPaths = @($manifestInfo.files | ForEach-Object {
            [string]$_.path
        })

        if ([string]$manifestInfo.algorithm -eq "SHA256") {
            Add-Result "OK" "Manifesto usa SHA-256"
        }
        else {
            Add-Result "FALHA" "Manifesto nao usa SHA-256"
        }

        if (
            $null -ne $versionInfo -and
            [string]$manifestInfo.sourceRef -eq [string]$versionInfo.sourceRef
        ) {
            Add-Result "OK" "Manifesto corresponde a referencia da versao"
        }
        else {
            Add-Result "FALHA" "Manifesto diverge da referencia da versao"
        }

        foreach ($requiredManifestPath in @(
            "install-v3.ps1",
            "ServiceDeskToolkit-CorporateV3.ps1",
            "tools/Test-ToolkitV3.ps1",
            "version-v3.json",
            "src/ServiceDeskToolkit.Office/ServiceDeskToolkit.Office.psm1"
        )) {
            if ($manifestPaths -contains $requiredManifestPath) {
                Add-Result "OK" "Manifesto inclui: $requiredManifestPath"
            }
            else {
                Add-Result "FALHA" "Manifesto nao inclui: $requiredManifestPath"
            }
        }
    }
    catch {
        Add-Result "FALHA" "Manifesto SHA-256 invalido: $($_.Exception.Message)"
    }
}
else {
    Add-Result "FALHA" "Arquivo nao encontrado: checksums-v3.json"
}

$moduleFiles = @(
    @{
        Name = "Modulo de diagnosticos"
        Path = $DiagnosticsModule
    },
    @{
        Name = "Modulo de avaliacao de saude"
        Path = $HealthModule
    },
    @{
        Name = "Modulo de inventario"
        Path = $InventoryModule
    },
    @{
        Name = "Modulo de diagnostico de rede"
        Path = $NetworkModule
    },
    @{
        Name = "Modulo de diagnostico de impressoras"
        Path = $PrintersModule
    },
    @{
        Name = "Modulo Office, TPM e autenticacao"
        Path = $OfficeModule
    }
)

foreach ($moduleFile in $moduleFiles) {
    if (Test-Path $moduleFile.Path) {
        Add-Result "OK" "Arquivo existe: $($moduleFile.Name)"
    }
    else {
        Add-Result "FALHA" "Arquivo nao encontrado: $($moduleFile.Path)"
    }
}

if (Test-Path $Cmd) {
    Add-Result "OK" "Arquivo existe: ServiceDeskToolkitV3.cmd"


if (Test-Path $Readme) {
    Add-Result "OK" "Arquivo existe: docs\V3-README.md"

    try {
        $readmeContent = Get-Content $Readme -Raw

        $readmeMarkers = @(
            "ServiceDesk Toolkit Corporate V3",
            "Como executar",
            "Como validar",
            "APROVADO - V3 validada sem falhas",
            "v2.3.0"
        )

        foreach ($marker in $readmeMarkers) {
            if ($readmeContent.Contains($marker)) {
                Add-Result "OK" "README contem: $marker"
            }
            else {
                Add-Result "FALHA" "README nao contem: $marker"
            }
        }
    }
    catch {
        Add-Result "FALHA" "Erro ao validar README da V3: $($_.Exception.Message)"
    }
}
else {
    Add-Result "FALHA" "Arquivo nao encontrado: docs\V3-README.md"
}
try {
        $cmdContent = Get-Content $Cmd -Raw

        if ($cmdContent.Contains("ServiceDeskToolkit-CorporateV3.ps1")) {
            Add-Result "OK" "Launcher CMD aponta para a V3"
        }
        else {
            Add-Result "FALHA" "Launcher CMD nao aponta para ServiceDeskToolkit-CorporateV3.ps1"
        }

        if ($cmdContent.Contains("powershell.exe -STA -NoProfile -ExecutionPolicy Bypass")) {
            Add-Result "OK" "Launcher CMD usa PowerShell em STA"
        }
        else {
            Add-Result "FALHA" "Launcher CMD nao usa PowerShell em STA"
        }
    }
    catch {
        Add-Result "FALHA" "Erro ao validar launcher CMD: $($_.Exception.Message)"
    }
}
else {
    Add-Result "FALHA" "Arquivo nao encontrado: ServiceDeskToolkitV3.cmd"
}

if (Test-Path $App) {
    try {
        $content = Get-Content $App -Raw
        $packageContentParts = New-Object 'System.Collections.Generic.List[string]'
        [void]$packageContentParts.Add($content)

        $errors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)

        if ($errors.Count -eq 0) {
            Add-Result "OK" "Sintaxe PowerShell OK"
        }
        else {
            Add-Result "FALHA" "Erros de sintaxe PowerShell encontrados"
            foreach ($err in $errors) {
                Add-Result "FALHA" "Linha $($err.Token.StartLine): $($err.Message)"
            }
        }

        foreach ($moduleFile in $moduleFiles) {
            if (-not (Test-Path $moduleFile.Path)) {
                continue
            }

            $moduleContent = Get-Content $moduleFile.Path -Raw
            $moduleErrors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize(
                $moduleContent,
                [ref]$moduleErrors
            )

            if ($moduleErrors.Count -eq 0) {
                Add-Result "OK" "Sintaxe PowerShell OK: $($moduleFile.Name)"
            }
            else {
                Add-Result "FALHA" "Erro de sintaxe: $($moduleFile.Name)"

                foreach ($moduleError in $moduleErrors) {
                    Add-Result `
                        "FALHA" `
                        "$($moduleFile.Name), linha $($moduleError.Token.StartLine): $($moduleError.Message)"
                }
            }

            [void]$packageContentParts.Add($moduleContent)
        }

        $validationContent = $packageContentParts -join [Environment]::NewLine

        $bytes = [System.IO.File]::ReadAllBytes($App)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF

        if ($hasBom) {
            Add-Result "OK" "Encoding UTF-8 BOM detectado"
        }
        else {
            Add-Result "AVISO" "Encoding UTF-8 BOM nao detectado"
        }

        $badEncodingSequences = @(
            (-join @([char]0x00C3, [char]0x00A1)),
            (-join @([char]0x00C3, [char]0x00A9)),
            (-join @([char]0x00C3, [char]0x00AD)),
            (-join @([char]0x00C3, [char]0x00B3)),
            (-join @([char]0x00C3, [char]0x00BA)),
            (-join @([char]0x00C3, [char]0x00A3)),
            (-join @([char]0x00C3, [char]0x00B5)),
            (-join @([char]0x00C3, [char]0x00A7)),
            (-join @([char]0x00C3, [char]0x00AA)),
            (-join @([char]0x00C3, [char]0x00B4)),
            (-join @([char]0x00C2, [char]0x00A0))
        )

        $hasBadEncoding = $false

        foreach ($sequence in $badEncodingSequences) {
            if ($content.Contains($sequence)) {
                $hasBadEncoding = $true
                break
            }
        }

        if ($content.IndexOf([char]0xFFFD) -ge 0) {
            $hasBadEncoding = $true
        }

        if ($hasBadEncoding) {
            Add-Result "FALHA" "Possivel encoding quebrado encontrado"
        }
        else {
            Add-Result "OK" "Sem sinais comuns de encoding quebrado"
        }

$markers = @(
    "ServiceDesk Toolkit Corporate V3",
    "Central de Atendimento Técnico",
    "function Test-V3Admin",
    "function Get-V3VersionInfo",
    "function Set-V3Output",
    "function Get-V3HomeText",
    "function Invoke-V3QuickInternet",
    "function Invoke-V3QuickVpn",
    "function Open-V3ExternalLink",
    "BtnV3QuickInternet",
    "BtnV3QuickVpn",
    "BtnV3Inventory",
    "BtnV3Network",
    "BtnV3FlushDns",
    "BtnV3TimeSync",
    "BtnV3Spooler",
    "BtnV3CopyOutput",
    "BtnV3LinkedIn",
    "BtnV3GitHub",
    "FooterLinkButton",
    "Made by Caio Dal Re",
    "Set-V3Output (Get-V3HomeText)",
    "function New-V3WorkflowResult",
    "function Get-V3GuidedHomeText",
    "function Invoke-V3WorkflowNoInternet",
    "function Invoke-V3WorkflowVpn",
    "Invoke-V3WorkflowNoInternet",
    "Invoke-V3WorkflowVpn",
    "Get-V3GuidedHomeText",
    "function Invoke-V3InternetDiagnosticSummary",
    "Invoke-V3InternetDiagnosticSummary",
    "DIAGNOSTICO AUTOMATICO DE INTERNET",
    "CONCLUSAO AUTOMATICA",
    "function Invoke-V3VpnDiagnosticSummary",
    "Invoke-V3VpnDiagnosticSummary",
    "DIAGNOSTICO AUTOMATICO DE VPN / APPGATE",
    "CONECTIVIDADE LOCAL",
    "SERVICOS",
    "PROCESSOS",
    "function Invoke-V3SafeFlushDns",
    "Invoke-V3SafeFlushDns",
    "CORRECAO SEGURA - LIMPAR DNS",
    "VALIDACAO ANTES",
    "VALIDACAO DEPOIS",
    "function Invoke-V3SafeTimeSync",
    "Invoke-V3SafeTimeSync",
    "CORRECAO SEGURA - SINCRONIZAR HORARIO",
    "function Invoke-V3SafeSpoolerRestart",
    "Invoke-V3SafeSpoolerRestart",
    "CORRECAO SEGURA - REINICIAR SPOOLER",
    "function New-V3WindowsRepairWorker",
    "function Invoke-V3WindowsRepair",
    "function Start-V3WindowsRepairMonitor",
    "function Get-V3WindowsRepairProgressText",
    "BtnV3Sfc",
    "BtnV3Dism",
    "Invoke-V3WindowsRepair -Tool ""SFC""",
    "Invoke-V3WindowsRepair -Tool ""DISM""",
    "System32\sfc.exe",
    "System32\dism.exe",
    "-Verb RunAs",
    "StandardOutputEncoding",
    "OEMCodePage",
    "ReadToEndAsync",
    "System.Windows.Threading.DispatcherTimer",
    "REPARO DO WINDOWS - CONCLUÍDO",
    "REPARO DO WINDOWS - INTERROMPIDO",
    "REPARO DO WINDOWS - FALHA AO INICIAR",
    "windows-repair-audit.jsonl",
    "RESULTADO DO REPARO",
    "Resumo final:",
    "function Invoke-V3NetworkDiagnostic",
    "DIAGNOSTICO DE REDE - PAINEL CONSOLIDADO",
    "ADAPTADORES ATIVOS",
    "TESTES DE CONECTIVIDADE",
    "ROTAS PRINCIPAIS",
    "Tipo de acao: Diagnostico sem correcao",
    "function Get-ToolkitNetworkSnapshot",
    "function Get-ToolkitNetworkAssessment",
    "function Format-ToolkitNetworkReport",
    "function Get-ToolkitAdvancedNetworkReport",
    "function Get-ToolkitDnsReport",
    "function Get-ToolkitRoutesReport",
    "function Test-ToolkitDefaultGateway",
    "function Invoke-ToolkitRenewIp",
    "function Invoke-ToolkitNetworkStackReset",
    "function Get-V3InventoryLite",
    "INVENTARIO DA MAQUINA - PAINEL CONSOLIDADO",
    "IDENTIFICACAO",
    "SISTEMA OPERACIONAL",
    "HARDWARE PRINCIPAL",
    "MEMORIA RAM",
    "DISCOS",
    "BIOS / SERIAL",
    "REDE RESUMIDA",
    "Tipo de acao: Coleta de inventario sem correcao",
    "function Get-ToolkitInventorySnapshot",
    "function Get-ToolkitInventoryAssessment",
    "function Format-ToolkitInventoryReport",
    "function Invoke-V3PrintersPanel",
    "BtnV3Printers",
    "Invoke-V3PrintersPanel",
    "PAINEL DE IMPRESSORAS - DIAGNOSTICO CONSOLIDADO",
    "Tipo de acao: Diagnostico de impressoras sem correcao",
    "SERVICO SPOOLER",
    "IMPRESSORAS INSTALADAS",
    "FILA DE IMPRESSAO",
    "IMPRESSORAS OFFLINE / COM ALERTA",
    "PORTAS UTILIZADAS",
    "DRIVERS PRINCIPAIS",
    "function Get-ToolkitPrinterSnapshot",
    "function Get-ToolkitPrinterAssessment",
    "function Format-ToolkitPrinterReport",
    "function Get-ToolkitPrinterListReport",
    "function Get-ToolkitPrintJobsReport",
    "function Get-ToolkitDefaultPrinterReport",
    "function Get-ToolkitOfflinePrintersReport",
    "function Clear-ToolkitPrintQueue",
    "function Invoke-V3OfficeTpmPanel",
    "function Invoke-V3OfficeWamRepair",
    "function Get-ToolkitOfficeTpmSnapshot",
    "function Get-ToolkitOfficeTpmAssessment",
    "function Format-ToolkitOfficeTpmReport",
    "function Repair-ToolkitOfficeWam",
    "function Get-ToolkitOfficeEdition",
    "Office 2016",
    "Office 2019",
    "Office 2021",
    "/dstatusall",
    "OSPP_UNLICENSED",
    "BtnV3OfficeTpm",
    "BtnV3OfficeWam",
    "OFFICE / TPM / AUTENTICACAO - DIAGNOSTICO CONSOLIDADO",
    "ACOES CRITICAS NAO AUTOMATIZADAS",
    "Nao limpa TPM",
    "function Get-V3AppgateStatus",
    "function Restart-V3Appgate",
    "function Repair-V3AppgateConfiguration",
    "RunScriptTimeout",
    "BtnV3AppgateStatus",
    "BtnV3AppgateRestart",
    "BtnV3AppgateFix",
    "ActionGridButton",
    "UniformGrid Columns",
    "function Invoke-V3WorkflowPrinter",
    "Atendimento Guiado - Impressora Nao Imprime",
    "Impressora nao imprime",
    "return New-V3WorkflowResult @workflowParameters",
    "Reiniciar o Spooler somente quando houver indicio de falha no servico ou fila",
    "function Invoke-V3MachineHealthPanel",
    "function Get-ToolkitMachineHealthSnapshot",
    "function Get-ToolkitMachineHealthAssessment",
    "function Format-ToolkitMachineHealthReport",
    "PAINEL DE SAUDE DA MAQUINA",
    "PONTUACAO GERAL",
    "Classificacao:",
    "INDICADORES",
    "-Label ""Memoria RAM""",
    "-Label ""Disco do Windows""",
    "-Label ""Reinicio pendente""",
    "Tipo de acao: Diagnostico geral sem correcao",
    "BtnV3Health",
    "Invoke-V3MachineHealthPanel"
)

        foreach ($marker in $markers) {
            if ($validationContent.Contains($marker)) {
                Add-Result "OK" "Marcador encontrado: $marker"
            }
            else {
                Add-Result "FALHA" "Marcador ausente: $marker"
            }
        }

        $linkedinHandlers = (Select-String -Path $App -Pattern 'BtnV3LinkedIn\.Add_Click').Count
        $githubHandlers = (Select-String -Path $App -Pattern 'BtnV3GitHub\.Add_Click').Count

        if ($linkedinHandlers -eq 1) {
            Add-Result "OK" "Handler LinkedIn unico"
        }
        else {
            Add-Result "FALHA" "Handler LinkedIn esperado: 1, encontrado: $linkedinHandlers"
        }

        if ($githubHandlers -eq 1) {
            Add-Result "OK" "Handler GitHub unico"
        }
        else {
            Add-Result "FALHA" "Handler GitHub esperado: 1, encontrado: $githubHandlers"
        }

        if ($content.Contains('$script:V3LastExternalLinkUrl') -and $content.Contains('$script:V3LastExternalLinkAt')) {
            Add-Result "OK" "Protecao contra abertura dupla dos links encontrada"
        }
        else {
            Add-Result "FALHA" "Protecao contra abertura dupla dos links ausente"
        }
    }
    catch {
        Add-Result "FALHA" "Erro durante validacao: $($_.Exception.Message)"
    }
}

$results | Out-File $ReportTxt -Encoding UTF8

Write-Host ""
Write-Host "Resultado da Validacao V3" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan

if ($failures -eq 0) {
    Write-Host "APROVADO - V3 validada sem falhas." -ForegroundColor Green
    $exitCode = 0
}
else {
    Write-Host "REPROVADO - V3 possui $failures falha(s)." -ForegroundColor Red
    $exitCode = 1
}

Write-Host ""
Write-Host "Relatorio:" -ForegroundColor DarkCyan
Write-Host $ReportTxt

exit $exitCode
