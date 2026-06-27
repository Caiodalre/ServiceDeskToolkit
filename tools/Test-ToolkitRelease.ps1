# ============================================================
# ServiceDesk Toolkit Corporate - Release Validation
# Compatibilidade: Windows PowerShell 5.1 e PowerShell 7+
# ============================================================

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Reports = Join-Path $Root "reports"

if (!(Test-Path $Reports)) {
    New-Item -Path $Reports -ItemType Directory -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ReportPath = Join-Path $Reports ("release-validation-" + $Timestamp + ".txt")

$Results = New-Object System.Collections.Generic.List[string]
$Failures = 0

function Add-Result {
    param(
        [string]$Status,
        [string]$Message
    )

    $line = "[{0}] {1}" -f $Status, $Message
    [void]$Results.Add($line)

    if ($Status -eq "FAIL") {
        $script:Failures++
        Write-Host $line -ForegroundColor Red
    }
    elseif ($Status -eq "WARN") {
        Write-Host $line -ForegroundColor Yellow
    }
    else {
        Write-Host $line -ForegroundColor Green
    }
}

function Test-FileExists {
    param([string]$RelativePath)

    $path = Join-Path $Root $RelativePath

    if (Test-Path $path) {
        Add-Result "OK" "Arquivo existe: $RelativePath"
    }
    else {
        Add-Result "FAIL" "Arquivo ausente: $RelativePath"
    }
}

function Test-PowerShellSyntax {
    param([string]$RelativePath)

    $path = Join-Path $Root $RelativePath

    if (!(Test-Path $path)) {
        Add-Result "FAIL" "Nao foi possivel validar sintaxe. Arquivo ausente: $RelativePath"
        return
    }

    $errors = $null
    $text = Get-Content $path -Raw
    $null = [System.Management.Automation.PSParser]::Tokenize($text, [ref]$errors)

    if ($errors.Count -eq 0) {
        Add-Result "OK" "Sintaxe PowerShell OK: $RelativePath"
    }
    else {
        Add-Result "FAIL" "Erro de sintaxe: $RelativePath"

        foreach ($err in $errors) {
            Add-Result "FAIL" ("Linha {0}: {1}" -f $err.Token.StartLine, $err.Message)
        }
    }
}

function Test-NoGlobalParam {
    param([string]$RelativePath)

    $path = Join-Path $Root $RelativePath

    if (!(Test-Path $path)) {
        Add-Result "FAIL" "Nao foi possivel validar param global. Arquivo ausente: $RelativePath"
        return
    }

    $scriptText = Get-Content $path -Raw
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $scriptText,
        [ref]$tokens,
        [ref]$errors
    )

    if ($null -eq $ast.ParamBlock) {
        Add-Result "OK" "Sem param global: $RelativePath"
    }
    else {
        Add-Result "FAIL" "Param global encontrado: $RelativePath"
    }
}

function Test-NoExit {
    param([string]$RelativePath)

    $path = Join-Path $Root $RelativePath

    if (!(Test-Path $path)) {
        Add-Result "FAIL" "Nao foi possivel validar exit. Arquivo ausente: $RelativePath"
        return
    }

    $exit = Select-String -Path $path -Pattern '^\s*exit\s+[0-9]+' -ErrorAction SilentlyContinue

    if ($exit) {
        Add-Result "FAIL" "Exit encontrado em: $RelativePath"
        foreach ($item in $exit) {
            Add-Result "FAIL" ("Linha {0}: {1}" -f $item.LineNumber, $item.Line.Trim())
        }
    }
    else {
        Add-Result "OK" "Sem exit numerico: $RelativePath"
    }
}

function Test-ContainsText {
    param(
        [string]$RelativePath,
        [string]$Text,
        [string]$Label
    )

    $path = Join-Path $Root $RelativePath

    if (!(Test-Path $path)) {
        Add-Result "FAIL" "Arquivo ausente para marcador: $RelativePath"
        return
    }

    $content = Get-Content $path -Raw

    if ($content.Contains($Text)) {
        Add-Result "OK" $Label
    }
    else {
        Add-Result "FAIL" $Label
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " ServiceDesk Toolkit Corporate - Release Validation" -ForegroundColor Cyan
Write-Host " Root: $Root" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Add-Result "OK" "Validacao iniciada em $Timestamp"

$requiredFiles = @(
    "ServiceDeskToolkit-Corporate.ps1",
    "ServiceDeskToolkit.cmd",
    "install.ps1",
    "update.ps1",
    "rollback.ps1",
    "version.json",
    "bootstrap.ps1",
    "CHANGELOG.md",
    "data\knowledge-base.json",
    "tools\Get-ToolkitDiagnostic.ps1",
    "tools\Test-ToolkitQuality.ps1",
    "tools\Test-ToolkitRelease.ps1",
    "docs\RUNBOOK-OPERACIONAL.md",
    "docs\RELEASE-CHECKLIST.md"
)

foreach ($file in $requiredFiles) {
    Test-FileExists $file
}

$psFiles = @(
    "ServiceDeskToolkit-Corporate.ps1",
    "install.ps1",
    "update.ps1",
    "rollback.ps1",
    "tools\Get-ToolkitDiagnostic.ps1",
    "tools\Test-ToolkitQuality.ps1",
    "tools\Test-ToolkitRelease.ps1"
)

foreach ($file in $psFiles) {
    Test-PowerShellSyntax $file
}

Test-NoGlobalParam "update.ps1"
Test-NoGlobalParam "rollback.ps1"

Test-NoExit "update.ps1"
Test-NoExit "rollback.ps1"

Test-ContainsText "ServiceDeskToolkit-Corporate.ps1" "BtnRunToolkitUpdate" "Interface contem botao Atualizar Toolkit"
Test-ContainsText "ServiceDeskToolkit-Corporate.ps1" "BtnRunRollbackDryRun" "Interface contem botao Rollback Dry-Run"
Test-ContainsText "ServiceDeskToolkit-Corporate.ps1" "BtnOpenUpdateRollbackLogs" "Interface contem botao Abrir Logs"
Test-ContainsText "ServiceDeskToolkit-Corporate.ps1" "BtnOpenBackups" "Interface contem botao Abrir Backups"
Test-ContainsText "ServiceDeskToolkit-Corporate.ps1" "GenerateToolkitDiagnostic" "Interface contem diagnostico automatico"

Test-ContainsText "install.ps1" '$UpdateUrl = "$BaseUrl/update.ps1"' "install.ps1 baixa update.ps1"
Test-ContainsText "install.ps1" '$RollbackUrl = "$BaseUrl/rollback.ps1"' "install.ps1 baixa rollback.ps1"
Test-ContainsText "install.ps1" '$DiagnosticToolUrl = "$BaseUrl/tools/Get-ToolkitDiagnostic.ps1"' "install.ps1 baixa ferramenta de diagnostico"
Test-ContainsText "install.ps1" '$QualityGateToolUrl = "$BaseUrl/tools/Test-ToolkitQuality.ps1"' "install.ps1 baixa Quality Gate"

Test-ContainsText "update.ps1" 'RelativePath = "rollback.ps1"' "update.ps1 inclui rollback.ps1"
Test-ContainsText "update.ps1" 'RelativePath = "tools\Test-ToolkitQuality.ps1"' "update.ps1 inclui Quality Gate"
Test-ContainsText "update.ps1" 'RelativePath = "tools\Get-ToolkitDiagnostic.ps1"' "update.ps1 inclui diagnostico"


try {
    $bootstrapPath = Join-Path $Root "bootstrap.ps1"

    if (Test-Path $bootstrapPath) {
        $bytes = [System.IO.File]::ReadAllBytes($bootstrapPath)

        if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
            Add-Result "FAIL" "Bootstrap sem BOM"
        }
        else {
            Add-Result "OK" "Bootstrap sem BOM"
        }
    }
    else {
        Add-Result "FAIL" "Bootstrap ausente"
    }
}
catch {
    Add-Result "FAIL" ("Falha ao validar bootstrap: " + $_.Exception.Message)
}
try {
    $qualityGate = Join-Path $Root "tools\Test-ToolkitQuality.ps1"

    if (Test-Path $qualityGate) {
        $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $qualityGate 2>&1 | Out-String

        if ($output -match "APROVADO") {
            Add-Result "OK" "Quality Gate aprovado"
        }
        else {
            Add-Result "FAIL" "Quality Gate nao retornou APROVADO"
            [void]$Results.Add($output)
        }
    }
    else {
        Add-Result "FAIL" "Quality Gate ausente"
    }
}
catch {
    Add-Result "FAIL" ("Falha ao executar Quality Gate: " + $_.Exception.Message)
}

Add-Result "OK" "Relatorio: $ReportPath"

$header = @(
    "ServiceDesk Toolkit Corporate - Release Validation",
    "Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "Root: $Root",
    "Falhas: $Failures",
    ""
)

$allLines = @()
$allLines += $header
$allLines += $Results

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllLines($ReportPath, $allLines, $utf8Bom)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan

if ($Failures -eq 0) {
    Write-Host "APROVADO - Release validada sem falhas." -ForegroundColor Green
}
else {
    Write-Host "REPROVADO - Falhas encontradas: $Failures" -ForegroundColor Red
}

Write-Host "Relatorio:" -ForegroundColor Cyan
Write-Host $ReportPath -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""