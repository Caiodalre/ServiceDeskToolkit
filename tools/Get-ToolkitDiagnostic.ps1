param(
    [string]$ToolkitRoot = ".",
    [switch]$OpenReport
)

$ErrorActionPreference = "Continue"

function Get-IsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-Utf8Bom {
    param([string]$Path)

    try {
        if (!(Test-Path $Path)) {
            return $false
        }

        $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $Path).Path)

        if ($bytes.Length -lt 3) {
            return $false
        }

        return ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    }
    catch {
        return $false
    }
}

function Test-PowerShellSyntax {
    param([string]$Path)

    $result = [ordered]@{
        ok = $false
        errorCount = 0
        errors = @()
    }

    try {
        if (!(Test-Path $Path)) {
            $result.errors = @("Arquivo nao encontrado.")
            return $result
        }

        $text = Get-Content $Path -Raw
        $parseErrors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize($text, [ref]$parseErrors)

        $result.errorCount = $parseErrors.Count
        $result.ok = ($parseErrors.Count -eq 0)

        if ($parseErrors.Count -gt 0) {
            $result.errors = @(
                $parseErrors |
                    Select-Object -First 10 |
                    ForEach-Object {
                        "Linha $($_.Token.StartLine): $($_.Message)"
                    }
            )
        }

        return $result
    }
    catch {
        $result.errors = @($_.Exception.Message)
        return $result
    }
}

function Get-FileStatus {
    param([string]$Path)

    try {
        if (Test-Path $Path) {
            $item = Get-Item $Path
            return [ordered]@{
                exists = $true
                fullName = $item.FullName
                length = $item.Length
                lastWriteTime = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                utf8Bom = Test-Utf8Bom -Path $item.FullName
            }
        }

        return [ordered]@{
            exists = $false
            fullName = $Path
            length = 0
            lastWriteTime = $null
            utf8Bom = $false
        }
    }
    catch {
        return [ordered]@{
            exists = $false
            fullName = $Path
            length = 0
            lastWriteTime = $null
            utf8Bom = $false
            error = $_.Exception.Message
        }
    }
}

function Get-RecentLogSummary {
    param(
        [string]$LogFolder,
        [string]$Pattern
    )

    try {
        if (!(Test-Path $LogFolder)) {
            return @()
        }

        return @(
            Get-ChildItem $LogFolder -Filter $Pattern -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 5 |
                ForEach-Object {
                    [ordered]@{
                        name = $_.Name
                        fullName = $_.FullName
                        length = $_.Length
                        lastWriteTime = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    }
                }
        )
    }
    catch {
        return @(
            [ordered]@{
                error = $_.Exception.Message
            }
        )
    }
}

function Test-GitHubRawAccess {
    try {
        $url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/v2.1-hardening/version.json"

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10

        return [ordered]@{
            ok = $true
            statusCode = [int]$response.StatusCode
            url = $url
        }
    }
    catch {
        return [ordered]@{
            ok = $false
            statusCode = $null
            url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/v2.1-hardening/version.json"
            error = $_.Exception.Message
        }
    }
}

try {
    $root = (Resolve-Path $ToolkitRoot).Path
}
catch {
    $root = $ToolkitRoot
}

$scriptPath = Join-Path $root "ServiceDeskToolkit-Corporate.ps1"
$cmdPath = Join-Path $root "ServiceDeskToolkit.cmd"
$installPath = Join-Path $root "install.ps1"
$versionPath = Join-Path $root "version.json"
$kbPath = Join-Path $root "data\knowledge-base.json"
$logsPath = Join-Path $root "logs"
$reportsPath = Join-Path $root "reports"

if (!(Test-Path $reportsPath)) {
    New-Item -Path $reportsPath -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$jsonReportPath = Join-Path $reportsPath "diagnostic-$timestamp.json"
$txtReportPath = Join-Path $reportsPath "diagnostic-$timestamp.txt"

$versionInfo = $null

try {
    if (Test-Path $versionPath) {
        $versionInfo = Get-Content $versionPath -Raw | ConvertFrom-Json
    }
}
catch {
    $versionInfo = [ordered]@{
        error = $_.Exception.Message
    }
}

$osInfo = $null

try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $osInfo = [ordered]@{
        caption = $os.Caption
        version = $os.Version
        buildNumber = $os.BuildNumber
        architecture = $os.OSArchitecture
        installDate = [string]$os.InstallDate
        lastBootUpTime = [string]$os.LastBootUpTime
    }
}
catch {
    $osInfo = [ordered]@{
        error = $_.Exception.Message
    }
}

$diagnostic = [ordered]@{
    generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    machine = $env:COMPUTERNAME
    user = $env:USERNAME
    userDomain = $env:USERDOMAIN
    isAdmin = Get-IsAdmin
    toolkitRoot = $root
    powershell = [ordered]@{
        version = $PSVersionTable.PSVersion.ToString()
        edition = [string]$PSVersionTable.PSEdition
        processId = $PID
        executionPolicy = [string](Get-ExecutionPolicy)
    }
    operatingSystem = $osInfo
    versionInfo = $versionInfo
    files = [ordered]@{
        mainScript = Get-FileStatus -Path $scriptPath
        launcherCmd = Get-FileStatus -Path $cmdPath
        installScript = Get-FileStatus -Path $installPath
        versionJson = Get-FileStatus -Path $versionPath
        knowledgeBase = Get-FileStatus -Path $kbPath
    }
    syntax = [ordered]@{
        mainScript = Test-PowerShellSyntax -Path $scriptPath
    }
    logs = [ordered]@{
        runtime = Get-RecentLogSummary -LogFolder $logsPath -Pattern "runtime-*.jsonl"
        actions = Get-RecentLogSummary -LogFolder $logsPath -Pattern "actions-*.jsonl"
        errors = Get-RecentLogSummary -LogFolder $logsPath -Pattern "errors-*.jsonl"
        install = Get-RecentLogSummary -LogFolder $logsPath -Pattern "install-*.log"
    }
    connectivity = [ordered]@{
        githubRaw = Test-GitHubRawAccess
    }
}

$json = $diagnostic | ConvertTo-Json -Depth 12
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($jsonReportPath, $json, $utf8Bom)

$lines = New-Object System.Collections.Generic.List[string]

$lines.Add("SERVICE DESK TOOLKIT - DIAGNOSTICO")
$lines.Add("===================================")
$lines.Add("")
$lines.Add("Gerado em: $($diagnostic.generatedAt)")
$lines.Add("Maquina: $($diagnostic.machine)")
$lines.Add("Usuario: $($diagnostic.userDomain)\$($diagnostic.user)")
$lines.Add("Admin: $($diagnostic.isAdmin)")
$lines.Add("Toolkit Root: $($diagnostic.toolkitRoot)")
$lines.Add("")
$lines.Add("POWERSHELL")
$lines.Add("----------")
$lines.Add("Versao: $($diagnostic.powershell.version)")
$lines.Add("Edicao: $($diagnostic.powershell.edition)")
$lines.Add("ExecutionPolicy: $($diagnostic.powershell.executionPolicy)")
$lines.Add("")
$lines.Add("WINDOWS")
$lines.Add("-------")
$lines.Add("Sistema: $($diagnostic.operatingSystem.caption)")
$lines.Add("Versao: $($diagnostic.operatingSystem.version)")
$lines.Add("Build: $($diagnostic.operatingSystem.buildNumber)")
$lines.Add("")
$lines.Add("VERSAO DO TOOLKIT")
$lines.Add("-----------------")

if ($null -ne $diagnostic.versionInfo) {
    $lines.Add("Nome: $($diagnostic.versionInfo.name)")
    $lines.Add("Versao: $($diagnostic.versionInfo.version)")
    $lines.Add("Branch: $($diagnostic.versionInfo.branch)")
    $lines.Add("Canal: $($diagnostic.versionInfo.channel)")
}
else {
    $lines.Add("version.json nao carregado.")
}

$lines.Add("")
$lines.Add("ARQUIVOS ESSENCIAIS")
$lines.Add("-------------------")

foreach ($name in $diagnostic.files.Keys) {
    $file = $diagnostic.files[$name]
    $lines.Add("$name | Existe: $($file.exists) | UTF8-BOM: $($file.utf8Bom) | Tamanho: $($file.length)")
}

$lines.Add("")
$lines.Add("SINTAXE")
$lines.Add("-------")
$lines.Add("Script principal OK: $($diagnostic.syntax.mainScript.ok)")
$lines.Add("Erros de sintaxe: $($diagnostic.syntax.mainScript.errorCount)")

if ($diagnostic.syntax.mainScript.errorCount -gt 0) {
    foreach ($err in $diagnostic.syntax.mainScript.errors) {
        $lines.Add("ERRO: $err")
    }
}

$lines.Add("")
$lines.Add("CONECTIVIDADE")
$lines.Add("-------------")
$lines.Add("GitHub Raw OK: $($diagnostic.connectivity.githubRaw.ok)")
$lines.Add("Status Code: $($diagnostic.connectivity.githubRaw.statusCode)")

if (-not $diagnostic.connectivity.githubRaw.ok) {
    $lines.Add("Erro GitHub: $($diagnostic.connectivity.githubRaw.error)")
}

$lines.Add("")
$lines.Add("LOGS RECENTES")
$lines.Add("-------------")
$lines.Add("Runtime logs: $($diagnostic.logs.runtime.Count)")
$lines.Add("Actions logs: $($diagnostic.logs.actions.Count)")
$lines.Add("Errors logs: $($diagnostic.logs.errors.Count)")
$lines.Add("Install logs: $($diagnostic.logs.install.Count)")
$lines.Add("")
$lines.Add("Arquivos gerados:")
$lines.Add($txtReportPath)
$lines.Add($jsonReportPath)

[System.IO.File]::WriteAllLines($txtReportPath, $lines, $utf8Bom)

if ((Test-Path $txtReportPath) -and (Test-Path $jsonReportPath)) {
    Write-Host "Diagnostico gerado com sucesso." -ForegroundColor Green
    Write-Host $txtReportPath -ForegroundColor Cyan
    Write-Host $jsonReportPath -ForegroundColor Cyan
}
else {
    Write-Host "ERRO: diagnostico nao foi gerado corretamente." -ForegroundColor Red
    Write-Host $txtReportPath -ForegroundColor Yellow
    Write-Host $jsonReportPath -ForegroundColor Yellow
    exit 1
}

if ($OpenReport) {
    Start-Process notepad.exe $txtReportPath
}