# ============================================================
# ServiceDesk Toolkit Corporate - Exportador de Pacote de Suporte
# Objetivo: gerar pacote ZIP com evidencias para troubleshooting
# Compatibilidade: Windows PowerShell 5.1 e PowerShell 7+
# ============================================================

$ErrorActionPreference = "Continue"

$InstallPath = "C:\ServiceDeskToolkit"
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$ReportsPath = Join-Path $InstallPath "reports"
$LogsPath = Join-Path $InstallPath "logs"
$ConfigPath = Join-Path $InstallPath "config"
$ToolsPath = Join-Path $InstallPath "tools"

$PackagesPath = Join-Path $ReportsPath "support-packages"
$StagingPath = Join-Path $env:TEMP "ServiceDeskToolkit-SupportPackage-$Timestamp"
$ZipPath = Join-Path $PackagesPath "ServiceDeskToolkit-SupportPackage-$Timestamp.zip"

function Copy-SupportItem {
    param(
        [string]$Source,
        [string]$Destination
    )

    try {
        if (Test-Path $Source) {
            $destinationFolder = Split-Path $Destination -Parent

            if (!(Test-Path $destinationFolder)) {
                New-Item -Path $destinationFolder -ItemType Directory -Force | Out-Null
            }

            Copy-Item -Path $Source -Destination $Destination -Force -ErrorAction Stop
            Write-Host "OK - Copiado: $Source" -ForegroundColor Green
        }
        else {
            Write-Host "WARN - Ausente: $Source" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "FAIL - Erro ao copiar $Source - $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Copy-LatestFiles {
    param(
        [string]$SourceFolder,
        [string]$Filter,
        [string]$DestinationFolder,
        [int]$Limit = 5
    )

    if (!(Test-Path $SourceFolder)) {
        Write-Host "WARN - Pasta ausente: $SourceFolder" -ForegroundColor Yellow
        return
    }

    $files = @(Get-ChildItem $SourceFolder -Filter $Filter -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $Limit)

    if ($files.Count -eq 0) {
        Write-Host "WARN - Nenhum arquivo encontrado: $Filter" -ForegroundColor Yellow
        return
    }

    foreach ($file in $files) {
        $dest = Join-Path $DestinationFolder $file.Name
        Copy-SupportItem -Source $file.FullName -Destination $dest
    }
}

Write-Host ""
Write-Host "Gerando Pacote de Suporte do Toolkit" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host "Instalacao: $InstallPath"
Write-Host "Staging: $StagingPath"
Write-Host "ZIP: $ZipPath"
Write-Host ""

if (!(Test-Path $InstallPath)) {
    throw "ABORTADO: instalacao nao encontrada em $InstallPath"
}

if (!(Test-Path $PackagesPath)) {
    New-Item -Path $PackagesPath -ItemType Directory -Force | Out-Null
}

if (Test-Path $StagingPath) {
    Remove-Item $StagingPath -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -Path $StagingPath -ItemType Directory -Force | Out-Null

$metadataPath = Join-Path $StagingPath "metadata"
$logsOutPath = Join-Path $StagingPath "logs"
$reportsOutPath = Join-Path $StagingPath "reports"
$checksOutPath = Join-Path $StagingPath "checks"

New-Item -Path $metadataPath -ItemType Directory -Force | Out-Null
New-Item -Path $logsOutPath -ItemType Directory -Force | Out-Null
New-Item -Path $reportsOutPath -ItemType Directory -Force | Out-Null
New-Item -Path $checksOutPath -ItemType Directory -Force | Out-Null

Copy-SupportItem -Source (Join-Path $InstallPath "version.json") -Destination (Join-Path $metadataPath "version.json")
Copy-SupportItem -Source (Join-Path $ConfigPath "source-ref.json") -Destination (Join-Path $metadataPath "source-ref.json")

$treePath = Join-Path $checksOutPath "installed-files.txt"

try {
    Get-ChildItem $InstallPath -Recurse -File -ErrorAction SilentlyContinue |
        Select-Object FullName, Length, LastWriteTime |
        Sort-Object FullName |
        Format-Table -AutoSize |
        Out-String -Width 4096 |
        Set-Content -Path $treePath -Encoding UTF8

    Write-Host "OK - Inventario de arquivos gerado." -ForegroundColor Green
}
catch {
    Write-Host "WARN - Falha ao gerar inventario de arquivos: $($_.Exception.Message)" -ForegroundColor Yellow
}

$validatorPath = Join-Path $ToolsPath "Test-ToolkitInstalled.ps1"
$validatorOutputPath = Join-Path $checksOutPath "installed-validation-output.txt"

if (Test-Path $validatorPath) {
    try {
        $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

        if (!(Test-Path $psExe)) {
            $psExe = "powershell.exe"
        }

        & $psExe -NoProfile -ExecutionPolicy Bypass -File $validatorPath 2>&1 |
            Out-String -Width 4096 |
            Set-Content -Path $validatorOutputPath -Encoding UTF8

        Write-Host "OK - Validacao instalada executada." -ForegroundColor Green
    }
    catch {
        "Falha ao executar Test-ToolkitInstalled.ps1: $($_.Exception.Message)" |
            Set-Content -Path $validatorOutputPath -Encoding UTF8

        Write-Host "WARN - Falha ao executar validador instalado." -ForegroundColor Yellow
    }
}
else {
    "Validador ausente: $validatorPath" |
        Set-Content -Path $validatorOutputPath -Encoding UTF8

    Write-Host "WARN - Validador instalado ausente." -ForegroundColor Yellow
}

Copy-LatestFiles -SourceFolder $LogsPath -Filter "runtime-*.jsonl" -DestinationFolder $logsOutPath -Limit 3
Copy-LatestFiles -SourceFolder $LogsPath -Filter "actions-*.jsonl" -DestinationFolder $logsOutPath -Limit 3
Copy-LatestFiles -SourceFolder $LogsPath -Filter "errors-*.jsonl" -DestinationFolder $logsOutPath -Limit 3
Copy-LatestFiles -SourceFolder $LogsPath -Filter "install-*.log" -DestinationFolder $logsOutPath -Limit 3
Copy-LatestFiles -SourceFolder $LogsPath -Filter "update-*.log" -DestinationFolder $logsOutPath -Limit 3
Copy-LatestFiles -SourceFolder $LogsPath -Filter "rollback-*.log" -DestinationFolder $logsOutPath -Limit 3

Copy-LatestFiles -SourceFolder $ReportsPath -Filter "diagnostic-*.txt" -DestinationFolder $reportsOutPath -Limit 3
Copy-LatestFiles -SourceFolder $ReportsPath -Filter "diagnostic-*.json" -DestinationFolder $reportsOutPath -Limit 3
Copy-LatestFiles -SourceFolder $ReportsPath -Filter "installed-validation-*.txt" -DestinationFolder $reportsOutPath -Limit 3
Copy-LatestFiles -SourceFolder $ReportsPath -Filter "installed-validation-*.json" -DestinationFolder $reportsOutPath -Limit 3
Copy-LatestFiles -SourceFolder $ReportsPath -Filter "update-summary-*.txt" -DestinationFolder $reportsOutPath -Limit 3
Copy-LatestFiles -SourceFolder $ReportsPath -Filter "update-summary-*.json" -DestinationFolder $reportsOutPath -Limit 3

$summary = [ordered]@{
    generatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    installPath = $InstallPath
    stagingPath = $StagingPath
    zipPath = $ZipPath
    computerName = $env:COMPUTERNAME
    userName = $env:USERNAME
    powershellVersion = $PSVersionTable.PSVersion.ToString()
}

$summaryJson = $summary | ConvertTo-Json -Depth 5
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText((Join-Path $StagingPath "support-package-summary.json"), $summaryJson, $utf8Bom)

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
}

try {
    Compress-Archive -Path (Join-Path $StagingPath "*") -DestinationPath $ZipPath -Force -ErrorAction Stop

    Write-Host ""
    Write-Host "APROVADO - Pacote de suporte gerado com sucesso." -ForegroundColor Green
    Write-Host $ZipPath -ForegroundColor Cyan
}
catch {
    Write-Host ""
    Write-Host "REPROVADO - Falha ao gerar ZIP: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    if (Test-Path $StagingPath) {
        Remove-Item $StagingPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}