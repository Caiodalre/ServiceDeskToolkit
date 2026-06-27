# ============================================================
# ServiceDesk Toolkit Corporate - Validador de Instalação
# Objetivo: validar a instalação em C:\ServiceDeskToolkit
# Compatibilidade: Windows PowerShell 5.1 e PowerShell 7+
# ============================================================

$ErrorActionPreference = "Continue"

$InstallPath = "C:\ServiceDeskToolkit"
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ReportsPath = Join-Path $InstallPath "reports"
$ReportTxtPath = Join-Path $ReportsPath "installed-validation-$Timestamp.txt"
$ReportJsonPath = Join-Path $ReportsPath "installed-validation-$Timestamp.json"

$Results = New-Object System.Collections.Generic.List[object]

function Add-InstalledCheck {
    param(
        [string]$Status,
        [string]$Name,
        [string]$Message
    )

    $item = [pscustomobject]@{
        Status = $Status
        Name = $Name
        Message = $Message
    }

    [void]$script:Results.Add($item)

    if ($Status -eq "OK") {
        Write-Host "OK - $Name" -ForegroundColor Green
    }
    elseif ($Status -eq "WARN") {
        Write-Host "WARN - $Name - $Message" -ForegroundColor Yellow
    }
    else {
        Write-Host "FAIL - $Name - $Message" -ForegroundColor Red
    }
}

function Test-RequiredFolder {
    param([string]$RelativePath)

    $path = Join-Path $InstallPath $RelativePath

    if (Test-Path $path) {
        Add-InstalledCheck -Status "OK" -Name "Pasta: $RelativePath" -Message $path
    }
    else {
        Add-InstalledCheck -Status "FAIL" -Name "Pasta: $RelativePath" -Message "Pasta ausente: $path"
    }
}

function Test-RequiredFile {
    param([string]$RelativePath)

    $path = Join-Path $InstallPath $RelativePath

    if (Test-Path $path) {
        Add-InstalledCheck -Status "OK" -Name "Arquivo: $RelativePath" -Message $path
    }
    else {
        Add-InstalledCheck -Status "FAIL" -Name "Arquivo: $RelativePath" -Message "Arquivo ausente: $path"
    }
}

function Test-PowerShellSyntax {
    param([string]$RelativePath)

    $path = Join-Path $InstallPath $RelativePath

    if (!(Test-Path $path)) {
        Add-InstalledCheck -Status "FAIL" -Name "Sintaxe: $RelativePath" -Message "Arquivo ausente."
        return
    }

    try {
        $tokens = $null
        $errors = $null
        $scriptText = Get-Content $path -Raw

        $null = [System.Management.Automation.Language.Parser]::ParseInput(
            $scriptText,
            [ref]$tokens,
            [ref]$errors
        )

        if ($errors.Count -eq 0) {
            Add-InstalledCheck -Status "OK" -Name "Sintaxe: $RelativePath" -Message "Sem erro de sintaxe."
        }
        else {
            $msg = ($errors | ForEach-Object { $_.Message }) -join " | "
            Add-InstalledCheck -Status "FAIL" -Name "Sintaxe: $RelativePath" -Message $msg
        }
    }
    catch {
        Add-InstalledCheck -Status "FAIL" -Name "Sintaxe: $RelativePath" -Message $_.Exception.Message
    }
}

function Test-JsonFile {
    param([string]$RelativePath)

    $path = Join-Path $InstallPath $RelativePath

    if (!(Test-Path $path)) {
        Add-InstalledCheck -Status "FAIL" -Name "JSON: $RelativePath" -Message "Arquivo ausente."
        return
    }

    try {
        $null = Get-Content $path -Raw | ConvertFrom-Json
        Add-InstalledCheck -Status "OK" -Name "JSON: $RelativePath" -Message "JSON valido."
    }
    catch {
        Add-InstalledCheck -Status "FAIL" -Name "JSON: $RelativePath" -Message $_.Exception.Message
    }
}

Write-Host ""
Write-Host "Resultado da Validacao da Instalacao" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host "Instalacao: $InstallPath"
Write-Host ""

if (!(Test-Path $InstallPath)) {
    Add-InstalledCheck -Status "FAIL" -Name "Raiz da instalacao" -Message "Caminho ausente: $InstallPath"
}
else {
    Add-InstalledCheck -Status "OK" -Name "Raiz da instalacao" -Message $InstallPath
}

$folders = @(
    "data",
    "tools",
    "logs",
    "reports",
    "backups",
    "config"
)

foreach ($folder in $folders) {
    Test-RequiredFolder -RelativePath $folder
}

$files = @(
    "ServiceDeskToolkit-Corporate.ps1",
    "ServiceDeskToolkit.cmd",
    "install.ps1",
    "update.ps1",
    "rollback.ps1",
    "version.json",
    "data\knowledge-base.json",
    "config\source-ref.json",
    "tools\Get-ToolkitDiagnostic.ps1",
    "tools\Test-ToolkitQuality.ps1",
    "tools\Test-ToolkitRelease.ps1",
    "tools\Test-ToolkitInstalled.ps1"
)

foreach ($file in $files) {
    Test-RequiredFile -RelativePath $file
}

$psScripts = @(
    "ServiceDeskToolkit-Corporate.ps1",
    "install.ps1",
    "update.ps1",
    "rollback.ps1",
    "tools\Get-ToolkitDiagnostic.ps1",
    "tools\Test-ToolkitQuality.ps1",
    "tools\Test-ToolkitRelease.ps1",
    "tools\Test-ToolkitInstalled.ps1"
)

foreach ($script in $psScripts) {
    Test-PowerShellSyntax -RelativePath $script
}

$jsonFiles = @(
    "version.json",
    "data\knowledge-base.json",
    "config\source-ref.json"
)

foreach ($json in $jsonFiles) {
    Test-JsonFile -RelativePath $json
}

$qualityGatePath = Join-Path $InstallPath "tools\Test-ToolkitQuality.ps1"

if (Test-Path $qualityGatePath) {
    try {
        $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

        if (!(Test-Path $psExe)) {
            $psExe = "powershell.exe"
        }

        $qualityOutput = & $psExe -NoProfile -ExecutionPolicy Bypass -File $qualityGatePath 2>&1 | Out-String

        if ($qualityOutput -match "APROVADO") {
            Add-InstalledCheck -Status "OK" -Name "Quality Gate instalado" -Message "Quality Gate aprovado."
        }
        else {
            Add-InstalledCheck -Status "FAIL" -Name "Quality Gate instalado" -Message $qualityOutput
        }
    }
    catch {
        Add-InstalledCheck -Status "FAIL" -Name "Quality Gate instalado" -Message $_.Exception.Message
    }
}
else {
    Add-InstalledCheck -Status "FAIL" -Name "Quality Gate instalado" -Message "Script ausente."
}

if (!(Test-Path $ReportsPath)) {
    New-Item -Path $ReportsPath -ItemType Directory -Force | Out-Null
}

$failures = @($Results | Where-Object { $_.Status -eq "FAIL" })
$warnings = @($Results | Where-Object { $_.Status -eq "WARN" })

$summary = [ordered]@{
    installPath = $InstallPath
    generatedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    total = $Results.Count
    ok = @($Results | Where-Object { $_.Status -eq "OK" }).Count
    warn = $warnings.Count
    fail = $failures.Count
    result = if ($failures.Count -eq 0) { "APROVADO" } else { "REPROVADO" }
    checks = $Results
}

$json = $summary | ConvertTo-Json -Depth 8
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

[System.IO.File]::WriteAllText($ReportJsonPath, $json, $utf8Bom)

$txtLines = New-Object System.Collections.Generic.List[string]
[void]$txtLines.Add("Resultado da Validacao da Instalacao")
[void]$txtLines.Add("====================================")
[void]$txtLines.Add("Instalacao: $InstallPath")
[void]$txtLines.Add("Gerado em: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$txtLines.Add("")
[void]$txtLines.Add("Resumo")
[void]$txtLines.Add("------")
[void]$txtLines.Add("Total: $($summary.total)")
[void]$txtLines.Add("OK: $($summary.ok)")
[void]$txtLines.Add("WARN: $($summary.warn)")
[void]$txtLines.Add("FAIL: $($summary.fail)")
[void]$txtLines.Add("Resultado: $($summary.result)")
[void]$txtLines.Add("")
[void]$txtLines.Add("Checks")
[void]$txtLines.Add("------")

foreach ($item in $Results) {
    [void]$txtLines.Add("[$($item.Status)] $($item.Name) - $($item.Message)")
}

[System.IO.File]::WriteAllLines($ReportTxtPath, $txtLines, $utf8Bom)

Write-Host ""
Write-Host "Relatorios gerados:" -ForegroundColor Cyan
Write-Host $ReportTxtPath -ForegroundColor DarkGray
Write-Host $ReportJsonPath -ForegroundColor DarkGray
Write-Host ""

if ($failures.Count -eq 0) {
    Write-Host "APROVADO - Instalacao validada sem falhas." -ForegroundColor Green
}
else {
    Write-Host "REPROVADO - Falhas encontradas: $($failures.Count)" -ForegroundColor Red
}