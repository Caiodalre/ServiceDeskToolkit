param(
    [string]$InstallPath = "C:\ServiceDeskToolkit",
    [string]$Branch = "v2.1-hardening",
    [switch]$NoLaunch
)

$ErrorActionPreference = "Stop"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch {}

$GitHubUser = "Caiodalre"
$RepoName = "ServiceDeskToolkit"
$BaseUrl = "https://raw.githubusercontent.com/$GitHubUser/$RepoName/$Branch"

$DataPath = Join-Path $InstallPath "data"
$ToolsPath = Join-Path $InstallPath "tools"
$LogsPath = Join-Path $InstallPath "logs"
$ReportsPath = Join-Path $InstallPath "reports"
$BackupsPath = Join-Path $InstallPath "backups"

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$UpdateBackupPath = Join-Path $BackupsPath "update-$Timestamp"
$CurrentBackupPath = Join-Path $UpdateBackupPath "current"
$StagingPath = Join-Path $UpdateBackupPath "staging"
$UpdateLogPath = Join-Path $LogsPath "update-$Timestamp.log"

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
        Name = "README"
        RelativePath = "README.md"
        Url = "$BaseUrl/README.md"
        Required = $false
        NormalizeBom = $true
        ValidateSyntax = $false
    }
)

function Write-ToolkitUpdateLog {
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

function Ensure-Folder {
    param([string]$Path)

    if (!(Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Convert-ToolkitFileToUtf8Bom {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        if (!(Test-Path $Path)) {
            throw "Arquivo nao encontrado: $Path"
        }

        $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($Path, $text, $utf8Bom)

        Write-ToolkitUpdateLog "OK - $Name normalizado em UTF-8 BOM." "OK"
    }
    catch {
        throw "Falha ao normalizar $Name. Erro: $($_.Exception.Message)"
    }
}

function Download-ToolkitFile {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$Name,
        [bool]$Required
    )

    try {
        $folder = Split-Path $Destination -Parent
        Ensure-Folder -Path $folder

        Write-ToolkitUpdateLog "Baixando $Name..."
        Write-ToolkitUpdateLog $Url

        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing

        Write-ToolkitUpdateLog "OK - $Name baixado." "OK"
        return $true
    }
    catch {
        if ($Required) {
            throw "Falha ao baixar $Name. URL: $Url. Erro: $($_.Exception.Message)"
        }

        Write-ToolkitUpdateLog "Aviso: $Name nao encontrado. Continuando." "WARN"
        return $false
    }
}

function Test-ToolkitPowerShellSyntax {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        if (!(Test-Path $Path)) {
            throw "Arquivo nao encontrado: $Path"
        }

        $errors = $null
        $text = Get-Content $Path -Raw
        $null = [System.Management.Automation.PSParser]::Tokenize($text, [ref]$errors)

        if ($errors.Count -eq 0) {
            Write-ToolkitUpdateLog "OK - $Name sem erro de sintaxe." "OK"
            return $true
        }

        foreach ($err in $errors) {
            Write-ToolkitUpdateLog "Erro de sintaxe em $Name - Linha $($err.Token.StartLine): $($err.Message)" "ERROR"
        }

        throw "$Name possui erro de sintaxe."
    }
    catch {
        throw "Falha na validacao de sintaxe de $Name. Erro: $($_.Exception.Message)"
    }
}

function Copy-ExistingFileToBackup {
    param([string]$RelativePath)

    try {
        $source = Join-Path $InstallPath $RelativePath

        if (!(Test-Path $source)) {
            Write-ToolkitUpdateLog "Backup ignorado. Arquivo nao existe: $RelativePath" "WARN"
            return
        }

        $destination = Join-Path $CurrentBackupPath $RelativePath
        $destinationFolder = Split-Path $destination -Parent
        Ensure-Folder -Path $destinationFolder

        Copy-Item $source $destination -Force
        Write-ToolkitUpdateLog "Backup criado: $RelativePath" "OK"
    }
    catch {
        throw "Falha ao criar backup de $RelativePath. Erro: $($_.Exception.Message)"
    }
}

function Apply-StagedFile {
    param([string]$RelativePath)

    try {
        $source = Join-Path $StagingPath $RelativePath
        $destination = Join-Path $InstallPath $RelativePath

        if (!(Test-Path $source)) {
            throw "Arquivo staged nao encontrado: $source"
        }

        $destinationFolder = Split-Path $destination -Parent
        Ensure-Folder -Path $destinationFolder

        Copy-Item $source $destination -Force
        Write-ToolkitUpdateLog "Atualizado: $RelativePath" "OK"
    }
    catch {
        throw "Falha ao aplicar $RelativePath. Erro: $($_.Exception.Message)"
    }
}

function Get-ToolkitVersionInfo {
    param([string]$Path)

    try {
        if (Test-Path $Path) {
            return (Get-Content $Path -Raw | ConvertFrom-Json)
        }

        return $null
    }
    catch {
        return $null
    }
}

try {
    Ensure-Folder -Path $InstallPath
    Ensure-Folder -Path $DataPath
    Ensure-Folder -Path $ToolsPath
    Ensure-Folder -Path $LogsPath
    Ensure-Folder -Path $ReportsPath
    Ensure-Folder -Path $BackupsPath
    Ensure-Folder -Path $UpdateBackupPath
    Ensure-Folder -Path $CurrentBackupPath
    Ensure-Folder -Path $StagingPath

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " ServiceDesk Toolkit Corporate - Update" -ForegroundColor Cyan
    Write-Host " Branch: $Branch" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-ToolkitUpdateLog "Update iniciado."
    Write-ToolkitUpdateLog "InstallPath: $InstallPath"
    Write-ToolkitUpdateLog "StagingPath: $StagingPath"
    Write-ToolkitUpdateLog "BackupPath: $CurrentBackupPath"

    $localVersionPath = Join-Path $InstallPath "version.json"
    $localVersion = Get-ToolkitVersionInfo -Path $localVersionPath

    if ($null -ne $localVersion) {
        Write-ToolkitUpdateLog "Versao local: $($localVersion.version)"
        Write-ToolkitUpdateLog "Branch local: $($localVersion.branch)"
    }
    else {
        Write-ToolkitUpdateLog "Versao local nao encontrada." "WARN"
    }

    Write-ToolkitUpdateLog "Baixando arquivos para staging..."

    foreach ($file in $Files) {
        $destination = Join-Path $StagingPath $file.RelativePath

        $downloaded = Download-ToolkitFile `
            -Url $file.Url `
            -Destination $destination `
            -Name $file.Name `
            -Required $file.Required

        if ($downloaded -and $file.NormalizeBom) {
            Convert-ToolkitFileToUtf8Bom -Path $destination -Name $file.Name
        }
    }

    Write-ToolkitUpdateLog "Validando arquivos em staging..."

    foreach ($file in $Files) {
        if ($file.Required) {
            $staged = Join-Path $StagingPath $file.RelativePath

            if (!(Test-Path $staged)) {
                throw "Arquivo obrigatorio ausente no staging: $($file.RelativePath)"
            }
        }

        if ($file.ValidateSyntax) {
            $staged = Join-Path $StagingPath $file.RelativePath

            if (Test-Path $staged) {
                Test-ToolkitPowerShellSyntax -Path $staged -Name $file.Name | Out-Null
            }
        }
    }

    $remoteVersionPath = Join-Path $StagingPath "version.json"
    $remoteVersion = Get-ToolkitVersionInfo -Path $remoteVersionPath

    if ($null -ne $remoteVersion) {
        Write-ToolkitUpdateLog "Versao remota/staging: $($remoteVersion.version)"
        Write-ToolkitUpdateLog "Branch remota/staging: $($remoteVersion.branch)"
    }

    Write-ToolkitUpdateLog "Criando backup da instalacao atual..."

    foreach ($file in $Files) {
        Copy-ExistingFileToBackup -RelativePath $file.RelativePath
    }

    Write-ToolkitUpdateLog "Aplicando arquivos atualizados..."

    foreach ($file in $Files) {
        $staged = Join-Path $StagingPath $file.RelativePath

        if (Test-Path $staged) {
            Apply-StagedFile -RelativePath $file.RelativePath
        }
    }

    Write-ToolkitUpdateLog "Update concluido com sucesso." "OK"

    Write-Host ""
    Write-Host "Update concluido com sucesso." -ForegroundColor Green
    Write-Host "Log:" -ForegroundColor Cyan
    Write-Host $UpdateLogPath -ForegroundColor Cyan
    Write-Host "Backup:" -ForegroundColor Cyan
    Write-Host $CurrentBackupPath -ForegroundColor Cyan
    Write-Host ""

    if (-not $NoLaunch) {
        $cmd = Join-Path $InstallPath "ServiceDeskToolkit.cmd"

        if (Test-Path $cmd) {
            Write-Host "Abrindo Toolkit..." -ForegroundColor Cyan
            Start-Process $cmd
        }
    }

    exit 0
}
catch {
    Write-ToolkitUpdateLog "Update falhou: $($_.Exception.Message)" "ERROR"

    Write-Host ""
    Write-Host "UPDATE FALHOU." -ForegroundColor Red
    Write-Host "Nada deveria ter sido aplicado se a falha ocorreu antes da etapa de aplicacao." -ForegroundColor Yellow
    Write-Host "Log:" -ForegroundColor Cyan
    Write-Host $UpdateLogPath -ForegroundColor Cyan
    Write-Host "Backup/staging:" -ForegroundColor Cyan
    Write-Host $UpdateBackupPath -ForegroundColor Cyan
    Write-Host ""

    exit 1
}