# ============================================================
# ServiceDesk Toolkit Corporate - Instalador via GitHub
# Autor/Repositório: github.com/Caiodalre/ServiceDeskToolkit
# ============================================================

$ErrorActionPreference = "Stop"

$GitHubUser = "Caiodalre"
$RepoName = "ServiceDeskToolkit"
$Branch = "main"

$BaseUrl = "https://raw.githubusercontent.com/$GitHubUser/$RepoName/$Branch"

$InstallPath = "C:\ServiceDeskToolkit"
$DataPath = Join-Path $InstallPath "data"

$MainScriptUrl = "$BaseUrl/ServiceDeskToolkit-Corporate.ps1"
$CmdUrl = "$BaseUrl/ServiceDeskToolkit.cmd"
$KnowledgeUrl = "$BaseUrl/data/knowledge-base.json"
$ReadmeUrl = "$BaseUrl/README.md"

$MainScriptPath = Join-Path $InstallPath "ServiceDeskToolkit-Corporate.ps1"
$CmdPath = Join-Path $InstallPath "ServiceDeskToolkit.cmd"
$KnowledgePath = Join-Path $DataPath "knowledge-base.json"
$ReadmePath = Join-Path $InstallPath "README.md"

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

Download-ToolkitFile -Url $MainScriptUrl -Destination $MainScriptPath -Name "Script principal"
Download-ToolkitFile -Url $CmdUrl -Destination $CmdPath -Name "Launcher CMD"
Download-ToolkitFile -Url $KnowledgeUrl -Destination $KnowledgePath -Name "Base de Conhecimento"

try {
    Download-ToolkitFile -Url $ReadmeUrl -Destination $ReadmePath -Name "README"
}
catch {
    Write-Host "Aviso: README não encontrado. Continuando instalação." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Validando arquivos baixados..." -ForegroundColor Cyan

$requiredFiles = @(
    $MainScriptPath,
    $CmdPath,
    $KnowledgePath
)

foreach ($file in $requiredFiles) {
    if (!(Test-Path $file)) {
        throw "Arquivo obrigatório não encontrado após download: $file"
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
        Write-Host "Aviso: o parser encontrou possíveis problemas de sintaxe nesta versão do PowerShell." -ForegroundColor Yellow
        Write-Host "A instalação continuará, pois o Toolkit pode funcionar normalmente em PowerShell 7 ou pelo launcher." -ForegroundColor Yellow
        Write-Host ""
        $errors | Format-List *
    }
    else {
        Write-Host "OK - Sem erro de sintaxe." -ForegroundColor Green
    }
}
catch {
    Write-Host "Aviso: não foi possível validar a sintaxe automaticamente." -ForegroundColor Yellow
    Write-Host "A instalação continuará mesmo assim." -ForegroundColor Yellow
    Write-Host # ============================================================
# ServiceDesk Toolkit Corporate - Instalador via GitHub
# Autor/Repositório: github.com/Caiodalre/ServiceDeskToolkit
# ============================================================

$ErrorActionPreference = "Stop"

$GitHubUser = "Caiodalre"
$RepoName = "ServiceDeskToolkit"
$Branch = "main"

$BaseUrl = "https://raw.githubusercontent.com/$GitHubUser/$RepoName/$Branch"

$InstallPath = "C:\ServiceDeskToolkit"
$DataPath = Join-Path $InstallPath "data"

$MainScriptUrl = "$BaseUrl/ServiceDeskToolkit-Corporate.ps1"
$CmdUrl = "$BaseUrl/ServiceDeskToolkit.cmd"
$KnowledgeUrl = "$BaseUrl/data/knowledge-base.json"
$ReadmeUrl = "$BaseUrl/README.md"

$MainScriptPath = Join-Path $InstallPath "ServiceDeskToolkit-Corporate.ps1"
$CmdPath = Join-Path $InstallPath "ServiceDeskToolkit.cmd"
$KnowledgePath = Join-Path $DataPath "knowledge-base.json"
$ReadmePath = Join-Path $InstallPath "README.md"

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

Download-ToolkitFile -Url $MainScriptUrl -Destination $MainScriptPath -Name "Script principal"
Download-ToolkitFile -Url $CmdUrl -Destination $CmdPath -Name "Launcher CMD"
Download-ToolkitFile -Url $KnowledgeUrl -Destination $KnowledgePath -Name "Base de Conhecimento"

try {
    Download-ToolkitFile -Url $ReadmeUrl -Destination $ReadmePath -Name "README"
}
catch {
    Write-Host "Aviso: README não encontrado. Continuando instalação." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Validando arquivos baixados..." -ForegroundColor Cyan

$requiredFiles = @(
    $MainScriptPath,
    $CmdPath,
    $KnowledgePath
)

foreach ($file in $requiredFiles) {
    if (!(Test-Path $file)) {
        throw "Arquivo obrigatório não encontrado após download: $file"
    }
}

Write-Host "Arquivos principais encontrados." -ForegroundColor Green

Write-Host ""
Write-Host "Validando sintaxe do script principal..." -ForegroundColor Cyan

$errors = $null
$null = [System.Management.Automation.PSParser]::Tokenize(
    (Get-Content $MainScriptPath -Raw),
    [ref]$errors
)

if ($errors.Count -gt 0) {
    Write-Host "Erro de sintaxe encontrado no script principal:" -ForegroundColor Red
    $errors | Format-List *
    throw "Instalação interrompida por erro de sintaxe."
}

Write-Host "OK - Sem erro de sintaxe." -ForegroundColor Green

Write-Host ""
Write-Host "Criando atalhos..." -ForegroundColor Cyan

$Desktop = [Environment]::GetFolderPath("Desktop")
$StartMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"

$ShortcutDesktop = Join-Path $Desktop "ServiceDesk Toolkit Corporate.lnk"
$ShortcutStartMenu = Join-Path $StartMenu "ServiceDesk Toolkit Corporate.lnk"

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

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Instalação concluída com sucesso" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Pasta instalada:" -ForegroundColor Cyan
Write-Host $InstallPath
Write-Host ""
Write-Host "Base de Conhecimento:" -ForegroundColor Cyan
Write-Host $KnowledgePath
Write-Host ""
Write-Host "Atalho Área de Trabalho:" -ForegroundColor Cyan
Write-Host $ShortcutDesktop
Write-Host ""
Write-Host "Atalho Menu Iniciar:" -ForegroundColor Cyan
Write-Host $ShortcutStartMenu
Write-Host ""

Write-Host "Abrindo o Toolkit..." -ForegroundColor Cyan

try {
    Start-Process -FilePath $CmdPath -WorkingDirectory $InstallPath
    Write-Host "Toolkit iniciado com sucesso." -ForegroundColor Green
}
catch {
    Write-Host "Instalação concluída, mas não foi possível abrir automaticamente o Toolkit." -ForegroundColor Yellow
    Write-Host "Abra manualmente pelo atalho ou execute:" -ForegroundColor Yellow
    Write-Host $CmdPath -ForegroundColor Cyan
}

.Exception.Message -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Criando atalhos..." -ForegroundColor Cyan

$Desktop = [Environment]::GetFolderPath("Desktop")
$StartMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"

$ShortcutDesktop = Join-Path $Desktop "ServiceDesk Toolkit Corporate.lnk"
$ShortcutStartMenu = Join-Path $StartMenu "ServiceDesk Toolkit Corporate.lnk"

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

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Instalação concluída com sucesso" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Pasta instalada:" -ForegroundColor Cyan
Write-Host $InstallPath
Write-Host ""
Write-Host "Base de Conhecimento:" -ForegroundColor Cyan
Write-Host $KnowledgePath
Write-Host ""
Write-Host "Atalho Área de Trabalho:" -ForegroundColor Cyan
Write-Host $ShortcutDesktop
Write-Host ""
Write-Host "Atalho Menu Iniciar:" -ForegroundColor Cyan
Write-Host $ShortcutStartMenu
Write-Host ""

Write-Host "Abrindo o Toolkit..." -ForegroundColor Cyan

try {
    Start-Process -FilePath $CmdPath -WorkingDirectory $InstallPath
    Write-Host "Toolkit iniciado com sucesso." -ForegroundColor Green
}
catch {
    Write-Host "Instalação concluída, mas não foi possível abrir automaticamente o Toolkit." -ForegroundColor Yellow
    Write-Host "Abra manualmente pelo atalho ou execute:" -ForegroundColor Yellow
    Write-Host $CmdPath -ForegroundColor Cyan
}


