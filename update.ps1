# ============================================================
# ServiceDesk Toolkit Corporate - Update
# Execucao suportada: irm <url> | iex
# Compatibilidade: Windows PowerShell 5.1 e PowerShell 7+
# ============================================================

$ErrorActionPreference = "Stop"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch {}

$GitHubUser = "Caiodalre"
$RepoName = "ServiceDeskToolkit"
$InstallPath = "C:\ServiceDeskToolkit"
$DataPath = Join-Path $InstallPath "data"
$ToolsPath = Join-Path $InstallPath "tools"
$LogsPath = Join-Path $InstallPath "logs"
$ReportsPath = Join-Path $InstallPath "reports"
$BackupsPath = Join-Path $InstallPath "backups"
$ConfigPath = Join-Path $InstallPath "config"
$SourceRefPath = Join-Path $ConfigPath "source-ref.json"

$DefaultRef = "v2.1-hardening"
$Ref = $env:SDTK_REF

if ([string]::IsNullOrWhiteSpace($Ref) -and (Test-Path $SourceRefPath)) {
    try {
        $sourceRefInfo = Get-Content $SourceRefPath -Raw | ConvertFrom-Json

        if ($null -ne $sourceRefInfo.ref -and ![string]::IsNullOrWhiteSpace([string]$sourceRefInfo.ref)) {
            $Ref = [string]$sourceRefInfo.ref
        }
    }
    catch {}
}

if ([string]::IsNullOrWhiteSpace($Ref)) {
    $Ref = $DefaultRef
}

$Branch = $Ref

$BaseUrl = "https://raw.githubusercontent.com/$GitHubUser/$RepoName/$Branch"

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$UpdateRoot = Join-Path $BackupsPath "update-$Timestamp"
$CurrentBackupPath = Join-Path $UpdateRoot "current"
$StagingPath = Join-Path $UpdateRoot "staging"
$UpdateLogPath = Join-Path $LogsPath "update-$Timestamp.log"

function Ensure-Folder {
    param([string]$Path)

    if (!(Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}


function Write-ToolkitUpdateSummary {
    param(
        [string]$InstallPath,
        [string]$LogsPath,
        [string]$ReportsPath,
        [string]$Branch,
        [string]$SourceRefPath
    )

    try {
        if (!(Test-Path $ReportsPath)) {
            New-Item -Path $ReportsPath -ItemType Directory -Force | Out-Null
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $summaryTxtPath = Join-Path $ReportsPath "update-summary-$timestamp.txt"
        $summaryJsonPath = Join-Path $ReportsPath "update-summary-$timestamp.json"

        $latestUpdateLog = Get-ChildItem $LogsPath -Filter "update-*.log" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        $logLines = @()

        if ($null -ne $latestUpdateLog -and (Test-Path $latestUpdateLog.FullName)) {
            $logLines = @(Get-Content $latestUpdateLog.FullName -ErrorAction SilentlyContinue)
        }

        $okCount = @($logLines | Where-Object { $_ -match '\[OK\]| OK |concluido|baixado|atualizado' }).Count
        $warnCount = @($logLines | Where-Object { $_ -match '\[WARN\]| WARN |AVISO|Nao foi possivel' }).Count
        $failCount = @($logLines | Where-Object { $_ -match '\[FAIL\]|\[ERROR\]| ERRO |Falha|REPROVADO' }).Count

        $sourceRefContent = $null

        if (Test-Path $SourceRefPath) {
            try {
                $sourceRefContent = Get-Content $SourceRefPath -Raw | ConvertFrom-Json
            }
            catch {
                $sourceRefContent = $null
            }
        }

        $summary = [ordered]@{
            generatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            installPath = $InstallPath
            branch = $Branch
            sourceRefPath = $SourceRefPath
            sourceRef = $sourceRefContent
            latestUpdateLog = if ($latestUpdateLog) { $latestUpdateLog.FullName } else { $null }
            ok = $okCount
            warn = $warnCount
            fail = $failCount
            result = if ($failCount -eq 0) { "APROVADO" } else { "VERIFICAR" }
        }

        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        $json = $summary | ConvertTo-Json -Depth 8

        [System.IO.File]::WriteAllText($summaryJsonPath, $json, $utf8Bom)

        $lines = New-Object System.Collections.Generic.List[string]

        [void]$lines.Add("Resumo Final do Update")
        [void]$lines.Add("=======================")
        [void]$lines.Add("Gerado em: $($summary.generatedAt)")
        [void]$lines.Add("Instalacao: $InstallPath")
        [void]$lines.Add("Branch usada: $Branch")
        [void]$lines.Add("Source ref: $SourceRefPath")
        [void]$lines.Add("Log analisado: $($summary.latestUpdateLog)")
        [void]$lines.Add("")
        [void]$lines.Add("Resultado")
        [void]$lines.Add("---------")
        [void]$lines.Add("OK: $okCount")
        [void]$lines.Add("WARN: $warnCount")
        [void]$lines.Add("FAIL: $failCount")
        [void]$lines.Add("Status: $($summary.result)")
        [void]$lines.Add("")
        [void]$lines.Add("Arquivos gerados")
        [void]$lines.Add("---------------")
        [void]$lines.Add($summaryTxtPath)
        [void]$lines.Add($summaryJsonPath)

        [System.IO.File]::WriteAllLines($summaryTxtPath, $lines, $utf8Bom)

        Write-UpdateLog "Resumo final do update gerado: $summaryTxtPath" "OK"
        Write-UpdateLog "Resumo final do update JSON: $summaryJsonPath" "OK"

        Write-Host ""
        Write-Host "Resumo Final do Update" -ForegroundColor Cyan
        Write-Host "=======================" -ForegroundColor Cyan
        Write-Host "Branch usada: $Branch"
        Write-Host "OK: $okCount" -ForegroundColor Green
        Write-Host "WARN: $warnCount" -ForegroundColor Yellow
        Write-Host "FAIL: $failCount" -ForegroundColor Red
        Write-Host "Relatorio TXT: $summaryTxtPath" -ForegroundColor Cyan
        Write-Host "Relatorio JSON: $summaryJsonPath" -ForegroundColor Cyan
        Write-Host ""
    }
    catch {
        Write-UpdateLog "Falha ao gerar resumo final do update: $($_.Exception.Message)" "WARN"
    }
}


function Write-ToolkitUpdateSummaryV2 {
    param(
        [string]$InstallPath,
        [string]$LogsPath,
        [string]$ReportsPath,
        [string]$Branch,
        [string]$SourceRefPath,
        [string]$UpdateLogPath
    )

    try {
        Ensure-Folder $ReportsPath

        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $summaryTxtPath = Join-Path $ReportsPath "update-summary-$timestamp.txt"
        $summaryJsonPath = Join-Path $ReportsPath "update-summary-$timestamp.json"

        $logLines = @()

        if (Test-Path $UpdateLogPath) {
            $logLines = @(Get-Content $UpdateLogPath -ErrorAction SilentlyContinue)
        }

        $okCount = @($logLines | Where-Object { $_ -match '\[OK\]| OK |baixado|Atualizado|concluido|salvo' }).Count
        $warnCount = @($logLines | Where-Object { $_ -match '\[WARN\]| WARN |AVISO|ignorado|Nao foi possivel' }).Count
        $failCount = @($logLines | Where-Object { $_ -match '\[FAIL\]|\[ERROR\]| ERRO |Falha|REPROVADO|throw' }).Count

        $sourceRefContent = $null

        if (Test-Path $SourceRefPath) {
            try {
                $sourceRefContent = Get-Content $SourceRefPath -Raw | ConvertFrom-Json
            }
            catch {
                $sourceRefContent = $null
            }
        }

        $summary = [ordered]@{
            generatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            installPath = $InstallPath
            branch = $Branch
            sourceRefPath = $SourceRefPath
            sourceRef = $sourceRefContent
            updateLogPath = $UpdateLogPath
            ok = $okCount
            warn = $warnCount
            fail = $failCount
            result = if ($failCount -eq 0) { "APROVADO" } else { "VERIFICAR" }
        }

        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        $json = $summary | ConvertTo-Json -Depth 8

        [System.IO.File]::WriteAllText($summaryJsonPath, $json, $utf8Bom)

        $lines = New-Object System.Collections.Generic.List[string]

        [void]$lines.Add("Resumo Final do Update")
        [void]$lines.Add("=======================")
        [void]$lines.Add("Gerado em: $($summary.generatedAt)")
        [void]$lines.Add("Instalacao: $InstallPath")
        [void]$lines.Add("Branch usada: $Branch")
        [void]$lines.Add("Source ref: $SourceRefPath")
        [void]$lines.Add("Log analisado: $UpdateLogPath")
        [void]$lines.Add("")
        [void]$lines.Add("Resultado")
        [void]$lines.Add("---------")
        [void]$lines.Add("OK: $okCount")
        [void]$lines.Add("WARN: $warnCount")
        [void]$lines.Add("FAIL: $failCount")
        [void]$lines.Add("Status: $($summary.result)")
        [void]$lines.Add("")
        [void]$lines.Add("Arquivos gerados")
        [void]$lines.Add("---------------")
        [void]$lines.Add($summaryTxtPath)
        [void]$lines.Add($summaryJsonPath)

        [System.IO.File]::WriteAllLines($summaryTxtPath, $lines, $utf8Bom)

        Write-UpdateLog "Resumo final do update gerado: $summaryTxtPath" "OK"
        Write-UpdateLog "Resumo final do update JSON: $summaryJsonPath" "OK"

        Write-Host ""
        Write-Host "Resumo Final do Update" -ForegroundColor Cyan
        Write-Host "=======================" -ForegroundColor Cyan
        Write-Host "Branch usada: $Branch"
        Write-Host "OK: $okCount" -ForegroundColor Green
        Write-Host "WARN: $warnCount" -ForegroundColor Yellow
        Write-Host "FAIL: $failCount" -ForegroundColor Red
        Write-Host "Relatorio TXT: $summaryTxtPath" -ForegroundColor Cyan
        Write-Host "Relatorio JSON: $summaryJsonPath" -ForegroundColor Cyan
        Write-Host ""
    }
    catch {
        try {
            Write-UpdateLog "Falha ao gerar resumo final do update V2: $($_.Exception.Message)" "WARN"
        }
        catch {}
    }
}

function Write-UpdateLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    try {
        Add-Content -Path $UpdateLogPath -Value $line -Encoding UTF8
    }
    catch {}

    if ($Level -eq "ERROR") {
        Write-Host $Message -ForegroundColor Red
    }
    elseif ($Level -eq "WARN") {
        Write-Host $Message -ForegroundColor Yellow
    }
    elseif ($Level -eq "OK") {
        Write-Host $Message -ForegroundColor Green
    }
    else {
        Write-Host $Message -ForegroundColor Cyan
    }
}

function Convert-ToUtf8Bom {
    param(
        [string]$Path,
        [string]$Name
    )

    if (!(Test-Path $Path)) {
        throw "Arquivo nao encontrado para normalizar: $Path"
    }

    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($Path, $text, $utf8Bom)

    Write-UpdateLog "OK - $Name salvo em UTF-8 BOM." "OK"
}

function Test-Syntax {
    param(
        [string]$Path,
        [string]$Name
    )

    if (!(Test-Path $Path)) {
        throw "Arquivo nao encontrado para validar sintaxe: $Path"
    }

    $errors = $null
    $text = Get-Content $Path -Raw
    $null = [System.Management.Automation.PSParser]::Tokenize($text, [ref]$errors)

    if ($errors.Count -eq 0) {
        Write-UpdateLog "OK - $Name sem erro de sintaxe." "OK"
        return
    }

    foreach ($err in $errors) {
        Write-UpdateLog "Erro de sintaxe em $Name - Linha $($err.Token.StartLine): $($err.Message)" "ERROR"
    }

    throw "$Name possui erro de sintaxe."
}

function Download-File {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$Name,
        [bool]$Required
    )

    try {
        $folder = Split-Path $Destination -Parent
        Ensure-Folder $folder

        Write-UpdateLog "Baixando $Name..."
        Write-UpdateLog $Url

        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing

        Write-UpdateLog "OK - $Name baixado." "OK"
        return $true
    }
    catch {
        if ($Required) {
            throw "Falha ao baixar $Name. URL: $Url. Erro: $($_.Exception.Message)"
        }

        Write-UpdateLog "Aviso: $Name nao encontrado. Continuando." "WARN"
        return $false
    }
}

function Backup-CurrentFile {
    param([string]$RelativePath)

    $source = Join-Path $InstallPath $RelativePath

    if (!(Test-Path $source)) {
        Write-UpdateLog "Backup ignorado, arquivo ausente: $RelativePath" "WARN"
        return
    }

    $destination = Join-Path $CurrentBackupPath $RelativePath
    Ensure-Folder (Split-Path $destination -Parent)

    Copy-Item $source $destination -Force
    Write-UpdateLog "Backup criado: $RelativePath" "OK"
}

function Apply-StagedFile {
    param([string]$RelativePath)

    $source = Join-Path $StagingPath $RelativePath
    $destination = Join-Path $InstallPath $RelativePath

    if (!(Test-Path $source)) {
        throw "Arquivo staged nao encontrado: $source"
    }

    Ensure-Folder (Split-Path $destination -Parent)

    Copy-Item $source $destination -Force
    Write-UpdateLog "Atualizado: $RelativePath" "OK"
}

$Files = @(
    @{
        Name = "Script principal"
        RelativePath = "ServiceDeskToolkit-Corporate.ps1"
        Url = "$BaseUrl/ServiceDeskToolkit-Corporate.ps1"
        Required = $true
        NormalizeBom = $true
        ValidateSyntax = $true
    },
    @{
        Name = "Launcher CMD"
        RelativePath = "ServiceDeskToolkit.cmd"
        Url = "$BaseUrl/ServiceDeskToolkit.cmd"
        Required = $true
        NormalizeBom = $false
        ValidateSyntax = $false
    },
    @{
        Name = "Base de Conhecimento"
        RelativePath = "data\knowledge-base.json"
        Url = "$BaseUrl/data/knowledge-base.json"
        Required = $true
        NormalizeBom = $true
        ValidateSyntax = $false
    },
    @{
        Name = "Controle de Versao"
        RelativePath = "version.json"
        Url = "$BaseUrl/version.json"
        Required = $true
        NormalizeBom = $true
        ValidateSyntax = $false
    },
    @{
        Name = "Diagnostico do Toolkit"
        RelativePath = "tools\Get-ToolkitDiagnostic.ps1"
        Url = "$BaseUrl/tools/Get-ToolkitDiagnostic.ps1"
        Required = $true
        NormalizeBom = $true
        ValidateSyntax = $true
    },
    @{
        Name = "Quality Gate"
        RelativePath = "tools\Test-ToolkitQuality.ps1"
        Url = "$BaseUrl/tools/Test-ToolkitQuality.ps1"
        Required = $true
        NormalizeBom = $true
        ValidateSyntax = $true
    },
    @{
        Name = "Instalador"
        RelativePath = "install.ps1"
        Url = "$BaseUrl/install.ps1"
        Required = $true
        NormalizeBom = $true
        ValidateSyntax = $true
    },
    @{
        Name = "Atualizador"
        RelativePath = "update.ps1"
        Url = "$BaseUrl/update.ps1"
        Required = $true
        NormalizeBom = $true
        ValidateSyntax = $true
    },
    @{
        Name = "Rollback"
        RelativePath = "rollback.ps1"
        Url = "$BaseUrl/rollback.ps1"
        Required = $true
        NormalizeBom = $true
        ValidateSyntax = $true
    },

    @{
        Name = "Exportador de Pacote de Suporte"
        RelativePath = "tools\Export-ToolkitSupportPackage.ps1"
        Url = "$BaseUrl/tools/Export-ToolkitSupportPackage.ps1"
        Required = $true
        Utf8Bom = $true
    },

    @{
        Name = "README"
        RelativePath = "README.md"
        Url = "$BaseUrl/README.md"
        Required = $false
        NormalizeBom = $true
        ValidateSyntax = $false
    }
)

try {
    Ensure-Folder $InstallPath
    Ensure-Folder $DataPath
    Ensure-Folder $ToolsPath
    Ensure-Folder $LogsPath
    Ensure-Folder $ReportsPath
    Ensure-Folder $BackupsPath
    Ensure-Folder $UpdateRoot
    Ensure-Folder $CurrentBackupPath
    Ensure-Folder $StagingPath

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " ServiceDesk Toolkit Corporate - Update" -ForegroundColor Cyan
    Write-Host " Branch: $Branch" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-UpdateLog "Update iniciado."
    Write-UpdateLog "InstallPath: $InstallPath"
    Write-UpdateLog "StagingPath: $StagingPath"
    Write-UpdateLog "BackupPath: $CurrentBackupPath"

    foreach ($file in $Files) {
        $relativePath = [string]$file["RelativePath"]
        $destination = Join-Path $StagingPath $relativePath

        $downloaded = Download-File `
            -Url ([string]$file["Url"]) `
            -Destination $destination `
            -Name ([string]$file["Name"]) `
            -Required ([bool]$file["Required"])

        if ($downloaded -and [bool]$file["NormalizeBom"]) {
            Convert-ToUtf8Bom -Path $destination -Name ([string]$file["Name"])
        }
    }

    Write-UpdateLog "Validando arquivos staged..."

    foreach ($file in $Files) {
        $relativePath = [string]$file["RelativePath"]
        $staged = Join-Path $StagingPath $relativePath

        if ([bool]$file["Required"] -and !(Test-Path $staged)) {
            throw "Arquivo obrigatorio ausente no staging: $relativePath"
        }

        if ([bool]$file["ValidateSyntax"] -and (Test-Path $staged)) {
            Test-Syntax -Path $staged -Name ([string]$file["Name"])
        }
    }

    Write-UpdateLog "Criando backup da instalacao atual..."

    foreach ($file in $Files) {
        Backup-CurrentFile -RelativePath ([string]$file["RelativePath"])
    }

    Write-UpdateLog "Aplicando arquivos atualizados..."

    foreach ($file in $Files) {
        $relativePath = [string]$file["RelativePath"]
        $staged = Join-Path $StagingPath $relativePath

        if (Test-Path $staged) {
            Apply-StagedFile -RelativePath $relativePath
        }
    }

    
try {
    if (!(Test-Path $ConfigPath)) {
        New-Item -Path $ConfigPath -ItemType Directory -Force | Out-Null
    }

    $sourceRefInfo = [ordered]@{
        repository = "https://github.com/$GitHubUser/$RepoName"
        ref = $Ref
        defaultRef = $DefaultRef
        updatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        installPath = $InstallPath
    }

    $sourceRefJson = $sourceRefInfo | ConvertTo-Json -Depth 4
    $sourceRefEncoding = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($SourceRefPath, $sourceRefJson, $sourceRefEncoding)

    Write-UpdateLog "source-ref.json atualizado pelo update: $SourceRefPath" "OK"
}
catch {
    Write-UpdateLog "Nao foi possivel atualizar source-ref.json: $($_.Exception.Message)" "WARN"
}

Write-ToolkitUpdateSummary `
    -InstallPath $InstallPath `
    -LogsPath $LogsPath `
    -ReportsPath $ReportsPath `
    -Branch $Branch `
    -SourceRefPath $SourceRefPath

Write-ToolkitUpdateSummaryV2 `
    -InstallPath $InstallPath `
    -LogsPath $LogsPath `
    -ReportsPath $ReportsPath `
    -Branch $Branch `
    -SourceRefPath $SourceRefPath `
    -UpdateLogPath $UpdateLogPath
Write-UpdateLog "Update concluido com sucesso." "OK"

    Write-Host ""
    Write-Host "Update concluido com sucesso." -ForegroundColor Green
    Write-Host "Log:" -ForegroundColor Cyan
    Write-Host $UpdateLogPath -ForegroundColor Cyan
    Write-Host "Backup:" -ForegroundColor Cyan
    Write-Host $CurrentBackupPath -ForegroundColor Cyan
    Write-Host ""
$global:ServiceDeskToolkitUpdateExitCode = 0
}
catch {
    try {
        Write-UpdateLog "Update falhou: $($_.Exception.Message)" "ERROR"
    }
    catch {
        Write-Host "Update falhou: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "UPDATE FALHOU." -ForegroundColor Red
    Write-Host "Log:" -ForegroundColor Cyan
    Write-Host $UpdateLogPath -ForegroundColor Cyan
    Write-Host "Backup/staging:" -ForegroundColor Cyan
    Write-Host $UpdateRoot -ForegroundColor Cyan
    Write-Host ""
$global:ServiceDeskToolkitUpdateExitCode = 1
}
