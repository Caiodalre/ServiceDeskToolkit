param(
    [string]$Branch = "v3-corporate-redesign",
    [string]$Repo = "Caiodalre/ServiceDeskToolkit",
    [string]$InstallRoot,
    [switch]$NoShortcut,
    [switch]$Launch
)

$ErrorActionPreference = "Stop"

function Write-V3Step {
    param(
        [string]$Message,
        [string]$Color = "Cyan"
    )

    Write-Host $Message -ForegroundColor $Color
}

function Test-V3Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-V3RawText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Write-V3Step "Baixando: $Name" "Yellow"

    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing
    $content = [string]$response.Content
    $content = $content.TrimStart([char]0xFEFF)

    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "Falha: conteudo vazio ao baixar $Name. URL: $Url"
    }

    return $content
}

function Test-V3PowerShellSyntax {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $errors = $null
    $null = [System.Management.Automation.PSParser]::Tokenize($Text, [ref]$errors)

    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "Erro de sintaxe em: $Name" -ForegroundColor Red
        $errors | Format-List *
        throw "Instalacao cancelada por erro de sintaxe em $Name."
    }
}

function New-V3CmdText {
    $lines = @(
        "@echo off",
        "title ServiceDesk Toolkit Corporate V3",
        "cd /d ""%~dp0""",
        "powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File ""%~dp0ServiceDeskToolkit-CorporateV3.ps1""",
        "if errorlevel 1 (",
        "    echo.",
        "    echo Falha ao iniciar o ServiceDesk Toolkit Corporate V3.",
        "    echo.",
        "    pause",
        ")"
    )

    return ($lines -join "`r`n") + "`r`n"
}

function Write-V3TextFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [System.Text.Encoding]$Encoding
    )

    $folder = Split-Path $Path -Parent

    if (-not (Test-Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, $Encoding)
}

function Test-V3CmdHasNoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
        throw "Falha: o launcher CMD foi gravado com BOM."
    }
}

function New-V3Shortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CmdPath,

        [Parameter(Mandatory = $true)]
        [string]$InstallPath
    )

    $desktopPath = [Environment]::GetFolderPath("Desktop")

    if ([string]::IsNullOrWhiteSpace($desktopPath)) {
        $desktopPath = Join-Path $env:USERPROFILE "Desktop"
    }

    $shortcutPath = Join-Path $desktopPath "ServiceDesk Toolkit V3.lnk"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $CmdPath
    $shortcut.WorkingDirectory = $InstallPath
    $shortcut.Description = "ServiceDesk Toolkit Corporate V3"
    $shortcut.Save()

    return $shortcutPath
}

function Install-V3IntoPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$MainText,

        [Parameter(Mandatory = $true)]
        [string]$ValidatorText,

        [Parameter(Mandatory = $true)]
        [string]$ReadmeText,

        [Parameter(Mandatory = $true)]
        [string]$CmdText
    )

    $buildName = "build-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    $installPath = Join-Path $RootPath $buildName

    $mainFile = Join-Path $installPath "ServiceDeskToolkit-CorporateV3.ps1"
    $cmdFile = Join-Path $installPath "ServiceDeskToolkitV3.cmd"
    $validatorFile = Join-Path $installPath "tools\Test-ToolkitV3.ps1"
    $readmeFile = Join-Path $installPath "docs\V3-README.md"
    $latestFile = Join-Path $RootPath "latest.txt"

    New-Item -Path $installPath -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $installPath "tools") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $installPath "docs") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $installPath "reports") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $installPath "logs") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $installPath "backups") -ItemType Directory -Force | Out-Null

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $ascii = [System.Text.Encoding]::ASCII

    Write-V3TextFile -Path $mainFile -Content $MainText -Encoding $utf8Bom
    Write-V3TextFile -Path $validatorFile -Content $ValidatorText -Encoding $utf8Bom
    Write-V3TextFile -Path $readmeFile -Content $ReadmeText -Encoding $utf8Bom
    Write-V3TextFile -Path $cmdFile -Content $CmdText -Encoding $ascii

    Unblock-File $mainFile -ErrorAction SilentlyContinue
    Unblock-File $validatorFile -ErrorAction SilentlyContinue
    Unblock-File $readmeFile -ErrorAction SilentlyContinue
    Unblock-File $cmdFile -ErrorAction SilentlyContinue

    $mainRead = Get-Content $mainFile -Raw

    if ([string]::IsNullOrWhiteSpace($mainRead)) {
        throw "Arquivo principal gravado, mas nao pode ser lido."
    }

    Test-V3CmdHasNoBom -Path $cmdFile

    Write-V3TextFile -Path $latestFile -Content $installPath -Encoding $ascii

    return @{
        InstallPath = $installPath
        MainFile = $mainFile
        CmdFile = $cmdFile
        ValidatorFile = $validatorFile
        ReadmeFile = $readmeFile
        LatestFile = $latestFile
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "ServiceDesk Toolkit Corporate V3 - Instalador Oficial" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Branch: $Branch" -ForegroundColor Cyan
Write-Host "Repo: $Repo" -ForegroundColor Cyan
Write-Host ""

$baseUrl = "https://raw.githubusercontent.com/$Repo/$Branch"

if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $candidateRoots = @(
        (Join-Path $env:LOCALAPPDATA "ServiceDeskToolkitV3"),
        (Join-Path $env:USERPROFILE "ServiceDeskToolkitV3"),
        (Join-Path $env:TEMP "ServiceDeskToolkitV3")
    )
}
else {
    $candidateRoots = @($InstallRoot)
}

Write-V3Step "1/5 - Baixando arquivos do GitHub..." "Cyan"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$mainText = Get-V3RawText -Url "$baseUrl/ServiceDeskToolkit-CorporateV3.ps1" -Name "Script principal V3"
$validatorText = Get-V3RawText -Url "$baseUrl/tools/Test-ToolkitV3.ps1" -Name "Validador V3"
$readmeText = Get-V3RawText -Url "$baseUrl/docs/V3-README.md" -Name "README V3"
$cmdText = New-V3CmdText

Write-V3Step "2/5 - Validando conteudo baixado..." "Cyan"

$requiredMarkers = @(
    "ServiceDesk Toolkit Corporate V3",
    "function Invoke-V3SafeSpoolerRestart",
    "CORRECAO SEGURA - REINICIAR SPOOLER",
    "function Invoke-V3SafeTimeSync",
    "function Invoke-V3SafeFlushDns",
    "function Invoke-V3InternetDiagnosticSummary",
    "function Invoke-V3VpnDiagnosticSummary"
)

foreach ($marker in $requiredMarkers) {
    if (-not $mainText.Contains($marker)) {
        throw "Marcador obrigatorio nao encontrado no script principal: $marker"
    }
}

Test-V3PowerShellSyntax -Text $mainText -Name "ServiceDeskToolkit-CorporateV3.ps1"
Test-V3PowerShellSyntax -Text $validatorText -Name "tools\Test-ToolkitV3.ps1"

Write-V3Step "3/5 - Instalando em pasta limpa..." "Cyan"

$result = $null
$errors = New-Object 'System.Collections.Generic.List[string]'

foreach ($root in $candidateRoots) {
    try {
        Write-V3Step "Tentando instalar em: $root" "Yellow"

        $result = Install-V3IntoPath `
            -RootPath $root `
            -MainText $mainText `
            -ValidatorText $validatorText `
            -ReadmeText $readmeText `
            -CmdText $cmdText

        break
    }
    catch {
        $errors.Add("$root => $($_.Exception.Message)")
        Write-V3Step "Falhou em: $root" "Red"
        Write-V3Step $_.Exception.Message "Red"
    }
}

if ($null -eq $result) {
    Write-Host ""
    Write-Host "Falha em todos os destinos testados:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }
    throw "Instalacao V3 cancelada."
}

Write-V3Step "4/5 - Criando atalho..." "Cyan"

$shortcutPath = $null

if (-not $NoShortcut) {
    try {
        $shortcutPath = New-V3Shortcut -CmdPath $result.CmdFile -InstallPath $result.InstallPath
        Write-V3Step "Atalho criado: $shortcutPath" "Green"
    }
    catch {
        Write-V3Step "Nao foi possivel criar atalho: $($_.Exception.Message)" "Yellow"
    }
}
else {
    Write-V3Step "Criacao de atalho ignorada por parametro -NoShortcut." "Yellow"
}

Write-V3Step "5/5 - Validando instalacao..." "Cyan"

try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $result.ValidatorFile
}
catch {
    Write-V3Step "Validador retornou erro: $($_.Exception.Message)" "Yellow"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "OK - ServiceDesk Toolkit Corporate V3 instalado" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "Pasta: $($result.InstallPath)" -ForegroundColor Green
Write-Host "Launcher: $($result.CmdFile)" -ForegroundColor Green
Write-Host "Latest: $($result.LatestFile)" -ForegroundColor Green

if ($shortcutPath) {
    Write-Host "Atalho: $shortcutPath" -ForegroundColor Green
}

Write-Host ""

if ($Launch) {
    Write-V3Step "Abrindo Toolkit V3..." "Cyan"
    Start-Process -FilePath $result.CmdFile -WorkingDirectory $result.InstallPath
}
