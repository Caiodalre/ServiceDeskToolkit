# ============================================================
# ServiceDesk Toolkit Corporate - Instalador via GitHub
# Repositorio: github.com/Caiodalre/ServiceDeskToolkit
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

$MainScriptUrl = "$BaseUrl/ServiceDeskToolkit-Corporate.ps1"
$CmdUrl = "$BaseUrl/ServiceDeskToolkit.cmd"
$KnowledgeUrl = "$BaseUrl/data/knowledge-base.json"
$ReadmeUrl = "$BaseUrl/README.md"
$VersionUrl = "$BaseUrl/version.json"
$UpdateUrl = "$BaseUrl/update.ps1"
$RollbackUrl = "$BaseUrl/rollback.ps1"
$DiagnosticToolUrl = "$BaseUrl/tools/Get-ToolkitDiagnostic.ps1"
$QualityGateToolUrl = "$BaseUrl/tools/Test-ToolkitQuality.ps1"

$MainScriptPath = Join-Path $InstallPath "ServiceDeskToolkit-Corporate.ps1"
$CmdPath = Join-Path $InstallPath "ServiceDeskToolkit.cmd"
$KnowledgePath = Join-Path $DataPath "knowledge-base.json"
$ReadmePath = Join-Path $InstallPath "README.md"
$VersionPath = Join-Path $InstallPath "version.json"
$UpdatePath = Join-Path $InstallPath "update.ps1"
$RollbackPath = Join-Path $InstallPath "rollback.ps1"
$DiagnosticToolPath = Join-Path $ToolsPath "Get-ToolkitDiagnostic.ps1"
$QualityGateToolPath = Join-Path $ToolsPath "Test-ToolkitQuality.ps1"

function Download-ToolkitFile {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Destination,
        [Parameter(Mandatory=$true)][string]$Name
    )

    Write-Host "Baixando $Name..." -ForegroundColor Cyan
    Write-Host $Url -ForegroundColor DarkGray

    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        Write-Host "OK - $Name baixado." -ForegroundColor Green
    }
    catch {
        throw "Falha ao baixar $Name. URL: $Url. Erro: $($_.Exception.Message)"
    }
}

function Convert-ToolkitFileToUtf8Bom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name
    )

    try {
        if (!(Test-Path $Path)) {
            Write-Host "Aviso: arquivo nao encontrado para normalizar encoding: $Path" -ForegroundColor Yellow
            return
        }

        $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($Path, $text, $utf8Bom)

        Write-Host "OK - $Name salvo em UTF-8 com BOM." -ForegroundColor Green
    }
    catch {
        Write-Host "Aviso: nao foi possivel normalizar encoding de $Name." -ForegroundColor Yellow
        Write-Host $_.Exception.Message -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ServiceDesk Toolkit Corporate - Instalador GitHub" -ForegroundColor Cyan
Write-Host " github.com/Caiodalre/ServiceDeskToolkit" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Criando estrutura local..." -ForegroundColor Cyan

$folders = @(
    $InstallPath,
    $DataPath,
    $ToolsPath,
    (Join-Path $InstallPath "logs"),
    (Join-Path $InstallPath "reports"),
    (Join-Path $InstallPath "exports"),
    (Join-Path $InstallPath "FINAL"),
    (Join-Path $InstallPath "backup-appgate"),
    (Join-Path $InstallPath "backups-antigos")
)

foreach ($folder in $folders) {
    if (!(Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }
}

# Log de instalação
$InstallLogPath = Join-Path (Join-Path $InstallPath "logs") ("install-" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") + ".log")

try {
    Start-Transcript -Path $InstallLogPath -Append | Out-Null
    Write-Host "Log de instalação:" -ForegroundColor Cyan
    Write-Host $InstallLogPath -ForegroundColor Cyan
}
catch {
    Write-Host "Aviso: não foi possível iniciar log de instalação." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}
Download-ToolkitFile -Url $MainScriptUrl -Destination $MainScriptPath -Name "Script principal"
Convert-ToolkitFileToUtf8Bom -Path $MainScriptPath -Name "Script principal"

Download-ToolkitFile -Url $CmdUrl -Destination $CmdPath -Name "Launcher CMD"

Download-ToolkitFile -Url $KnowledgeUrl -Destination $KnowledgePath -Name "Base de Conhecimento"
Convert-ToolkitFileToUtf8Bom -Path $KnowledgePath -Name "Base de Conhecimento"

Download-ToolkitFile -Url $VersionUrl -Destination $VersionPath -Name "Controle de Versao"
Convert-ToolkitFileToUtf8Bom -Path $VersionPath -Name "Controle de Versao"

Download-ToolkitFile -Url $DiagnosticToolUrl -Destination $DiagnosticToolPath -Name "Diagnostico do Toolkit"
Convert-ToolkitFileToUtf8Bom -Path $DiagnosticToolPath -Name "Diagnostico do Toolkit"

Download-ToolkitFile -Url $QualityGateToolUrl -Destination $QualityGateToolPath -Name "Quality Gate"
Convert-ToolkitFileToUtf8Bom -Path $QualityGateToolPath -Name "Quality Gate"

Download-ToolkitFile -Url $UpdateUrl -Destination $UpdatePath -Name "Atualizador"
Convert-ToolkitFileToUtf8Bom -Path $UpdatePath -Name "Atualizador"

Download-ToolkitFile -Url $RollbackUrl -Destination $RollbackPath -Name "Rollback"
Convert-ToolkitFileToUtf8Bom -Path $RollbackPath -Name "Rollback"

try {
    Download-ToolkitFile -Url $ReadmeUrl -Destination $ReadmePath -Name "README"
}
catch {
    Write-Host "Aviso: README nao encontrado. Continuando instalacao." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Validando arquivos baixados..." -ForegroundColor Cyan

$requiredFiles = @(
    $MainScriptPath,
    $CmdPath,
    $KnowledgePath,
    $VersionPath,
    $DiagnosticToolPath,
    $QualityGateToolPath,
    $UpdatePath,
    $RollbackPath
)

foreach ($file in $requiredFiles) {
    if (!(Test-Path $file)) {
        throw "Arquivo obrigatorio nao encontrado apos download: $file"
    }
}

Write-Host "Arquivos principais encontrados." -ForegroundColor Green

Write-Host ""
Write-Host "Validando sintaxe do script principal..." -ForegroundColor Cyan

try {
    $errors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize(
        (Get-Content $MainScriptPath -Raw),
        [ref]$errors
    )

    if ($errors.Count -gt 0) {
        Write-Host "Aviso: o parser encontrou possiveis problemas de sintaxe nesta versao do PowerShell." -ForegroundColor Yellow
        Write-Host "A instalacao vai continuar. Se o Toolkit nao abrir, execute o CMD para ver o erro." -ForegroundColor Yellow
        $errors | Format-List *
    }
    else {
        Write-Host "OK - Sem erro de sintaxe." -ForegroundColor Green
    }
}
catch {
    Write-Host "Aviso: nao foi possivel validar a sintaxe automaticamente." -ForegroundColor Yellow
    Write-Host "A instalacao vai continuar." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Criando atalhos..." -ForegroundColor Cyan

$Desktop = [Environment]::GetFolderPath("Desktop")
$StartMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"

$ShortcutDesktop = Join-Path $Desktop "ServiceDesk Toolkit Corporate.lnk"
$ShortcutStartMenu = Join-Path $StartMenu "ServiceDesk Toolkit Corporate.lnk"

try {
    $WshShell = New-Object -ComObject WScript.Shell

    $Shortcut = $WshShell.CreateShortcut($ShortcutDesktop)
    $Shortcut.TargetPath = $CmdPath
    $Shortcut.WorkingDirectory = $InstallPath
    $Shortcut.Description = "ServiceDesk Toolkit Corporate"
    $Shortcut.Save()

    $Shortcut2 = $WshShell.CreateShortcut($ShortcutStartMenu)
    $Shortcut2.TargetPath = $CmdPath
    $Shortcut2.WorkingDirectory = $InstallPath
    $Shortcut2.Description = "ServiceDesk Toolkit Corporate"
    $Shortcut2.Save()

    Write-Host "Atalhos criados com sucesso." -ForegroundColor Green
}
catch {
    Write-Host "Aviso: nao foi possivel criar atalhos automaticamente." -ForegroundColor Yellow
    Write-Host $_.Exception.Message -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Instalacao concluida" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Pasta instalada:" -ForegroundColor Cyan
Write-Host $InstallPath
Write-Host ""
Write-Host "Base de Conhecimento:" -ForegroundColor Cyan
Write-Host $KnowledgePath
Write-Host ""
Write-Host ""
Write-Host "Versao instalada:" -ForegroundColor Cyan
try {
    $versionInfo = Get-Content $VersionPath -Raw | ConvertFrom-Json
    Write-Host "$($versionInfo.name) $($versionInfo.version) [$($versionInfo.channel)]" -ForegroundColor Green
}
catch {
    Write-Host "Nao foi possivel ler o version.json." -ForegroundColor Yellow
}
Write-Host "Launcher:" -ForegroundColor Cyan
Write-Host $CmdPath
Write-Host ""

Write-Host "Abrindo o Toolkit..." -ForegroundColor Cyan

try {
    Start-Process -FilePath $CmdPath -WorkingDirectory $InstallPath
    Write-Host "Toolkit iniciado com sucesso." -ForegroundColor Green
}
catch {
    Write-Host "Instalacao concluida, mas nao foi possivel abrir automaticamente o Toolkit." -ForegroundColor Yellow
    Write-Host "Abra manualmente pelo atalho ou execute:" -ForegroundColor Yellow
    Write-Host $CmdPath -ForegroundColor Cyan
}

