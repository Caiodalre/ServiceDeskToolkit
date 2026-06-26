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

Download-ToolkitFile -Url $MainScriptUrl -Destination $MainScriptPath -Name "Script principal"
Convert-ToolkitFileToUtf8Bom -Path $MainScriptPath -Name "Script principal"

Download-ToolkitFile -Url $CmdUrl -Destination $CmdPath -Name "Launcher CMD"

Download-ToolkitFile -Url $KnowledgeUrl -Destination $KnowledgePath -Name "Base de Conhecimento"
Convert-ToolkitFileToUtf8Bom -Path $KnowledgePath -Name "Base de Conhecimento"

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
    $KnowledgePath
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
