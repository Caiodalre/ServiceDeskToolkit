$ErrorActionPreference = "Stop"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch {}

$GitHubUser = "Caiodalre"
$RepoName = "ServiceDeskToolkit"

$Ref = $env:SDTK_REF

if ([string]::IsNullOrWhiteSpace($Ref)) {
    $Ref = "v2.3.0"
}

$Timestamp = Get-Date -Format "yyyyMMddHHmmss"
$SafeRef = $Ref -replace '[^a-zA-Z0-9._-]', '_'

$BaseUrl = "https://raw.githubusercontent.com/$GitHubUser/$RepoName/$Ref"
$InstallUrl = "$BaseUrl/install.ps1?cb=$Timestamp"
$TempInstall = Join-Path $env:TEMP ("ServiceDeskToolkit-install-" + $SafeRef + "-" + $Timestamp + ".ps1")

Write-Host ""
Write-Host "ServiceDesk Toolkit Corporate - Bootstrap" -ForegroundColor Cyan
Write-Host "Ref: $Ref" -ForegroundColor Cyan
Write-Host "URL: $InstallUrl" -ForegroundColor DarkGray
Write-Host ""

Invoke-WebRequest -Uri $InstallUrl -OutFile $TempInstall -UseBasicParsing

if (!(Test-Path $TempInstall)) {
    throw "Instalador temporario nao foi baixado: $TempInstall"
}

$errors = $null
$null = [System.Management.Automation.PSParser]::Tokenize(
    (Get-Content $TempInstall -Raw),
    [ref]$errors
)

if ($errors.Count -ne 0) {
    $errors | Format-List *
    throw "Instalador temporario tem erro de sintaxe."
}

$psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

if (!(Test-Path $psExe)) {
    $psExe = "powershell.exe"
}

Write-Host "Executando instalador temporario:" -ForegroundColor Cyan
Write-Host $TempInstall -ForegroundColor Cyan
Write-Host ""

& $psExe -NoProfile -ExecutionPolicy Bypass -File $TempInstall

Write-Host ""
Write-Host "Bootstrap finalizado." -ForegroundColor Green
