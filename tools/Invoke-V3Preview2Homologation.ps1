[CmdletBinding()]
param(
    [ValidateSet("All", "Network", "Printer", "Time", "Appgate")]
    [string]$Scenario = "All",

    [ValidateSet("Baseline", "AfterAction")]
    [string]$Phase = "Baseline",

    [string]$EvidenceDirectory
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path $repositoryRoot "reports\homologation"
}

New-Item -Path $EvidenceDirectory -ItemType Directory -Force | Out-Null
$results = New-Object System.Collections.Generic.List[object]
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Add-HomologationResult {
    param(
        [string]$Id,
        [string]$Area,
        [ValidateSet("PASS", "WARN", "FAIL")]
        [string]$Status,
        [string]$Summary,
        [object]$Evidence
    )

    [void]$results.Add([pscustomobject]@{
        Id = $Id
        Area = $Area
        Status = $Status
        Summary = $Summary
        Evidence = $Evidence
    })
}

function Test-HomologationArea {
    param([string]$Area)
    return $Scenario -eq "All" -or $Scenario -eq $Area
}

function Get-ComputerHash {
    $bytes = [Text.Encoding]::UTF8.GetBytes([string]$env:COMPUTERNAME)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString(
            $sha256.ComputeHash($bytes)
        ).Replace("-", "").Substring(0, 12).ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

try {
    $versionPath = Join-Path $repositoryRoot "version-v3.json"
    $version = Get-Content $versionPath -Raw | ConvertFrom-Json
    $versionStatus = if ([string]$version.version -eq "3.1.0-preview.2") {
        "PASS"
    }
    else {
        "FAIL"
    }
    Add-HomologationResult `
        -Id "HOM-001" `
        -Area "Core" `
        -Status $versionStatus `
        -Summary "Contrato de versao carregado." `
        -Evidence ([pscustomobject]@{
            Version = [string]$version.version
            Channel = [string]$version.channel
            SourceRef = [string]$version.sourceRef
        })
}
catch {
    Add-HomologationResult "HOM-001" "Core" "FAIL" `
        "Falha ao carregar version-v3.json." $_.Exception.Message
}

try {
    $parseErrors = New-Object System.Collections.Generic.List[string]
    foreach ($relativePath in @(
        "ServiceDeskToolkit-CorporateV3.ps1",
        "src\ServiceDeskToolkit.Network\ServiceDeskToolkit.Network.psm1",
        "src\ServiceDeskToolkit.Printers\ServiceDeskToolkit.Printers.psm1"
    )) {
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $repositoryRoot $relativePath),
            [ref]$tokens,
            [ref]$errors
        )
        foreach ($errorItem in @($errors)) {
            [void]$parseErrors.Add(
                "${relativePath}:$($errorItem.Extent.StartLineNumber)"
            )
        }
    }
    Add-HomologationResult `
        -Id "HOM-002" `
        -Area "Core" `
        -Status $(if ($parseErrors.Count -eq 0) { "PASS" } else { "FAIL" }) `
        -Summary "Sintaxe dos componentes principais verificada." `
        -Evidence ([string[]]$parseErrors)
}
catch {
    Add-HomologationResult "HOM-002" "Core" "FAIL" `
        "Falha ao validar sintaxe." $_.Exception.Message
}

$networkModulePath = Join-Path $repositoryRoot `
    "src\ServiceDeskToolkit.Network\ServiceDeskToolkit.Network.psm1"
$printerModulePath = Join-Path $repositoryRoot `
    "src\ServiceDeskToolkit.Printers\ServiceDeskToolkit.Printers.psm1"

try {
    Import-Module $networkModulePath -Force -ErrorAction Stop
    Import-Module $printerModulePath -Force -ErrorAction Stop
    Add-HomologationResult "HOM-003" "Core" "PASS" `
        "Modulos de rede e impressoras importados." $null
}
catch {
    Add-HomologationResult "HOM-003" "Core" "FAIL" `
        "Falha ao importar modulos operacionais." $_.Exception.Message
}

if (Test-HomologationArea "Network") {
    try {
        $network = Get-ToolkitNetworkSnapshot
        $networkStatus = if (
            $network.HasAdapter -and $network.HasIp -and $network.HasGateway
        ) { "PASS" } else { "WARN" }
        Add-HomologationResult `
            -Id "HOM-NET-001" `
            -Area "Network" `
            -Status $networkStatus `
            -Summary "Coleta de rede concluida sem expor enderecos." `
            -Evidence ([pscustomobject]@{
                AdapterCount = @($network.Adapters).Count
                HasAdapter = [bool]$network.HasAdapter
                HasIpv4 = [bool]$network.HasIp
                HasGateway = [bool]$network.HasGateway
                HasDns = [bool]$network.HasDns
                GatewayResponds = [bool]$network.GatewayResponds
                ExternalIpResponds = [bool](
                    $network.CloudflareResponds -or $network.GoogleResponds
                )
                DnsResolves = [bool]$network.MicrosoftDnsResolves
            })

        $advancedReports = @(
            Get-ToolkitAdvancedNetworkReport
            Get-ToolkitDnsReport
            Get-ToolkitRoutesReport
            Test-ToolkitDefaultGateway
        )
        $validReports = @($advancedReports | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        }).Count
        Add-HomologationResult "HOM-NET-002" "Network" `
            $(if ($validReports -eq 4) { "PASS" } else { "WARN" }) `
            "Relatorios avancados de rede executados." `
            ([pscustomobject]@{ ReportsGenerated = $validReports })
    }
    catch {
        Add-HomologationResult "HOM-NET-001" "Network" "FAIL" `
            "Falha na coleta de rede." $_.Exception.Message
    }
}

if (Test-HomologationArea "Printer") {
    try {
        $printer = Get-ToolkitPrinterSnapshot
        $spoolerRunning = (
            $null -ne $printer.Spooler -and
            [string]$printer.Spooler.Status -eq "Running"
        )
        $printerStatus = if ($spoolerRunning) { "PASS" } else { "WARN" }
        if ($Scenario -eq "Printer" -and @($printer.Printers).Count -eq 0) {
            $printerStatus = "WARN"
        }
        Add-HomologationResult `
            -Id "HOM-PRN-001" `
            -Area "Printer" `
            -Status $printerStatus `
            -Summary "Estado de impressao coletado sem nomes de filas." `
            -Evidence ([pscustomobject]@{
                SpoolerFound = ($null -ne $printer.Spooler)
                SpoolerRunning = $spoolerRunning
                PrinterCount = @($printer.Printers).Count
                JobCount = @($printer.Jobs).Count
                OfflineCount = @($printer.OfflinePrinters).Count
                AlertCount = @($printer.AlertPrinters).Count
                HasDefaultPrinter = ($null -ne $printer.DefaultPrinter)
            })

        $printerReports = @(
            Get-ToolkitPrinterListReport
            Get-ToolkitPrintJobsReport
            Get-ToolkitDefaultPrinterReport
            Get-ToolkitOfflinePrintersReport
        )
        $validReports = @($printerReports | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        }).Count
        Add-HomologationResult "HOM-PRN-002" "Printer" `
            $(if ($validReports -eq 4) { "PASS" } else { "WARN" }) `
            "Relatorios de impressao executados." `
            ([pscustomobject]@{ ReportsGenerated = $validReports })
    }
    catch {
        Add-HomologationResult "HOM-PRN-001" "Printer" "FAIL" `
            "Falha na coleta de impressoras." $_.Exception.Message
    }
}

if (Test-HomologationArea "Time") {
    try {
        $timeService = Get-Service w32time -ErrorAction SilentlyContinue
        $timeSourceOutput = @(w32tm /query /source 2>&1)
        $timeSourceText = ($timeSourceOutput -join " ").Trim()
        $sourceClass = if (
            $timeSourceText -match "Local CMOS Clock|Free-running"
        ) { "Local" } elseif ([string]::IsNullOrWhiteSpace($timeSourceText)) {
            "Unavailable"
        } else { "Configured" }
        $timeStatus = if (
            $timeService -and
            $timeService.Status -eq "Running" -and
            $sourceClass -eq "Configured"
        ) { "PASS" } else { "WARN" }
        Add-HomologationResult `
            -Id "HOM-TIME-001" `
            -Area "Time" `
            -Status $timeStatus `
            -Summary "Servico e classe da fonte de horario verificados." `
            -Evidence ([pscustomobject]@{
                ServiceFound = ($null -ne $timeService)
                ServiceStatus = $(if ($timeService) {
                    [string]$timeService.Status
                } else { "NotFound" })
                SourceClass = $sourceClass
            })
    }
    catch {
        Add-HomologationResult "HOM-TIME-001" "Time" "FAIL" `
            "Falha ao verificar horario." $_.Exception.Message
    }
}

if (Test-HomologationArea "Appgate") {
    try {
        $configPath = "C:\Program Files\Appgate SDP\Service\Appgate SDP Service.dll.config"
        $services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -in @("appgatedriver", "AppgateUpdateService") -or
            $_.DisplayName -like "*Appgate*"
        })
        $timeoutValue = $null
        if (Test-Path $configPath) {
            [xml]$configXml = Get-Content $configPath -Raw
            $timeoutNode = $configXml.SelectSingleNode(
                "//applicationSettings/Cryptzone.Stratus.WindowsClient.Properties.Application/setting[@name='RunScriptTimeout']/value"
            )
            if ($timeoutNode) { $timeoutValue = [string]$timeoutNode.InnerText }
        }
        $appgateFound = (Test-Path $configPath) -or $services.Count -gt 0
        Add-HomologationResult `
            -Id "HOM-APP-001" `
            -Area "Appgate" `
            -Status $(if ($appgateFound) { "PASS" } else { "WARN" }) `
            -Summary "Instalacao e servicos Appgate verificados." `
            -Evidence ([pscustomobject]@{
                ConfigFound = (Test-Path $configPath)
                ServiceCount = $services.Count
                RunningServiceCount = @($services | Where-Object {
                    $_.Status -eq "Running"
                }).Count
                RunScriptTimeout = $timeoutValue
            })
    }
    catch {
        Add-HomologationResult "HOM-APP-001" "Appgate" "FAIL" `
            "Falha ao verificar Appgate." $_.Exception.Message
    }
}

try {
    $appText = Get-Content (
        Join-Path $repositoryRoot "ServiceDeskToolkit-CorporateV3.ps1"
    ) -Raw
    $markers = @(
        "BtnV3TimeSync",
        "BtnV3ClearPrintQueue",
        "BtnV3RenewIp",
        "BtnV3Winsock",
        "BtnV3TcpIp",
        "BtnV3AppgateStatus",
        "BtnV3AppgateRestart",
        "BtnV3AppgateFix",
        "Copy-Item `$configPath `$backupPath"
    )
    $missingMarkers = @($markers | Where-Object { -not $appText.Contains($_) })
    Add-HomologationResult `
        -Id "HOM-UI-001" `
        -Area "Core" `
        -Status $(if ($missingMarkers.Count -eq 0) { "PASS" } else { "FAIL" }) `
        -Summary "Controles e protecoes da interface verificados." `
        -Evidence ([string[]]$missingMarkers)
}
catch {
    Add-HomologationResult "HOM-UI-001" "Core" "FAIL" `
        "Falha ao validar contrato da interface." $_.Exception.Message
}

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object `
    Security.Principal.WindowsPrincipal($currentIdentity)
$isAdministrator = $currentPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

$summary = [pscustomobject]@{
    SchemaVersion = 1
    Product = "ServiceDesk Toolkit Corporate"
    Version = "3.1.0-preview.2"
    Scenario = $Scenario
    Phase = $Phase
    GeneratedAt = (Get-Date).ToString("o")
    ComputerHash = Get-ComputerHash
    PowerShell = $PSVersionTable.PSVersion.ToString()
    IsAdministrator = $isAdministrator
    Totals = [pscustomobject]@{
        Pass = @($results | Where-Object Status -eq "PASS").Count
        Warn = @($results | Where-Object Status -eq "WARN").Count
        Fail = @($results | Where-Object Status -eq "FAIL").Count
    }
    Results = [object[]]$results
}

$baseName = "v3.1.0-preview.2-$($Scenario.ToLowerInvariant())-$($Phase.ToLowerInvariant())-$timestamp"
$jsonPath = Join-Path $EvidenceDirectory "$baseName.json"
$markdownPath = Join-Path $EvidenceDirectory "$baseName.md"
$summary | ConvertTo-Json -Depth 8 | Set-Content $jsonPath -Encoding UTF8

$markdown = New-Object System.Text.StringBuilder
[void]$markdown.AppendLine("# Homologação ServiceDesk Toolkit V3.1.0-preview.2")
[void]$markdown.AppendLine("")
[void]$markdown.AppendLine("- Cenário: $Scenario")
[void]$markdown.AppendLine("- Fase: $Phase")
[void]$markdown.AppendLine("- Estação: $($summary.ComputerHash)")
[void]$markdown.AppendLine("- PowerShell: $($summary.PowerShell)")
[void]$markdown.AppendLine("- Resultado: $($summary.Totals.Pass) PASS, $($summary.Totals.Warn) WARN, $($summary.Totals.Fail) FAIL")
[void]$markdown.AppendLine("")
[void]$markdown.AppendLine("| ID | Área | Status | Resumo |")
[void]$markdown.AppendLine("| --- | --- | --- | --- |")
foreach ($result in $results) {
    [void]$markdown.AppendLine(
        "| $($result.Id) | $($result.Area) | $($result.Status) | $($result.Summary) |"
    )
}
$markdown.ToString() | Set-Content $markdownPath -Encoding UTF8

Write-Host ""
Write-Host "Homologacao concluida" -ForegroundColor Cyan
Write-Host "PASS: $($summary.Totals.Pass) | WARN: $($summary.Totals.Warn) | FAIL: $($summary.Totals.Fail)"
Write-Host "JSON: $jsonPath"
Write-Host "Resumo: $markdownPath"

if ($summary.Totals.Fail -gt 0) { exit 1 }
exit 0
