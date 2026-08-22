[CmdletBinding()]
param(
    [string]$InstallRoot,
    [switch]$NoShortcut,
    [switch]$Launch
)

$ErrorActionPreference = "Stop"

$Branch = "v3.0.1"
$Repo = "Caiodalre/ServiceDeskToolkit"
$installerPath = Join-Path $env:TEMP "ServiceDeskToolkitV3-install.ps1"
$installerUrl = "https://raw.githubusercontent.com/$Repo/$Branch/install-v3.ps1"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ServiceDesk Toolkit Corporate V3 - Canal Estável" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Versão: $Branch" -ForegroundColor Cyan
Write-Host "Origem: $Repo" -ForegroundColor Cyan
Write-Host ""

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "Baixando o instalador oficial para arquivo..." -ForegroundColor Yellow
Invoke-WebRequest `
    -Uri $installerUrl `
    -OutFile $installerPath `
    -UseBasicParsing

if (-not (Test-Path $installerPath)) {
    throw "O instalador oficial não foi baixado: $installerPath"
}

$installerText = Get-Content $installerPath -Raw
$parseErrors = $null
$null = [System.Management.Automation.PSParser]::Tokenize(
    $installerText,
    [ref]$parseErrors
)

if ($parseErrors.Count -gt 0) {
    throw "O instalador baixado contém erro de sintaxe."
}

if (-not $installerText.Contains(
    "ServiceDesk Toolkit Corporate V3 - Instalador Oficial"
)) {
    throw "O arquivo baixado não corresponde ao instalador oficial da V3."
}

Unblock-File $installerPath -ErrorAction SilentlyContinue

$installerParameters = @{
    Branch = $Branch
    Repo = $Repo
}

if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) {
    $installerParameters.InstallRoot = $InstallRoot
}

if ($NoShortcut) {
    $installerParameters.NoShortcut = $true
}

if ($Launch) {
    $installerParameters.Launch = $true
}

Write-Host "Executando a instalação validada..." -ForegroundColor Yellow
& $installerPath @installerParameters

Write-Host ""
Write-Host "Instalação estável concluída." -ForegroundColor Green
Write-Host "Referência instalada: $Branch" -ForegroundColor Green
