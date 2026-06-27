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
$Branch = "v2.1-hardening"

$BaseUrl = "https://raw.githubusercontent.com/$GitHubUser/$RepoName/$Branch"

$InstallPath = "C:\ServiceDeskToolkit"
$DataPath = Join-Path $InstallPath "data"
$ToolsPath = Join-Path $InstallPath "tools"
$LogsPath = Join-Path $InstallPath "logs"
$ReportsPath = Join-Path $InstallPath "reports"
$BackupsPath = Join-Path $InstallPath "backups"

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