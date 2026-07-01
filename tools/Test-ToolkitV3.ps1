$ErrorActionPreference = "Continue"

$Root = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Root "ServiceDeskToolkit-CorporateV3.ps1"
$Reports = Join-Path $Root "reports"

if (-not (Test-Path $Reports)) {
    New-Item -ItemType Directory -Path $Reports -Force | Out-Null
}

$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ReportTxt = Join-Path $Reports "v3-validation-$stamp.txt"

$results = New-Object System.Collections.Generic.List[string]
$failures = 0

function Add-Result {
    param(
        [string]$Status,
        [string]$Message
    )

    $line = "[$Status] $Message"
    $script:results.Add($line) | Out-Null
    Write-Host $line

    if ($Status -eq "FALHA") {
        $script:failures++
    }
}

Write-Host ""
Write-Host "ServiceDesk Toolkit Corporate V3 - Validation"
Write-Host "Root: $Root"
Write-Host ""

Add-Result "OK" "Validacao iniciada em $stamp"

if (Test-Path $App) {
    Add-Result "OK" "Arquivo existe: ServiceDeskToolkit-CorporateV3.ps1"
}
else {
    Add-Result "FALHA" "Arquivo nao encontrado: ServiceDeskToolkit-CorporateV3.ps1"
}

if (Test-Path $App) {
    try {
        $content = Get-Content $App -Raw

        $errors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)

        if ($errors.Count -eq 0) {
            Add-Result "OK" "Sintaxe PowerShell OK"
        }
        else {
            Add-Result "FALHA" "Erros de sintaxe PowerShell encontrados"
            foreach ($err in $errors) {
                Add-Result "FALHA" "Linha $($err.Token.StartLine): $($err.Message)"
            }
        }

        $bytes = [System.IO.File]::ReadAllBytes($App)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF

        if ($hasBom) {
            Add-Result "OK" "Encoding UTF-8 BOM detectado"
        }
        else {
            Add-Result "AVISO" "Encoding UTF-8 BOM nao detectado"
        }

        $badEncodingPattern = "Ã|Â|�"
        if ($content -match $badEncodingPattern) {
            Add-Result "FALHA" "Possivel encoding quebrado encontrado"
        }
        else {
            Add-Result "OK" "Sem sinais comuns de encoding quebrado"
        }

        $markers = @(
            "ServiceDesk Toolkit Corporate V3",
            "Central de Atendimento Técnico",
            "function Test-V3Admin",
            "function Get-V3VersionInfo",
            "function Set-V3Output",
            "function Get-V3HomeText",
            "function Invoke-V3QuickInternet",
            "function Invoke-V3QuickVpn",
            "function Open-V3ExternalLink",
            "BtnV3QuickInternet",
            "BtnV3QuickVpn",
            "BtnV3Inventory",
            "BtnV3Network",
            "BtnV3FlushDns",
            "BtnV3TimeSync",
            "BtnV3Spooler",
            "BtnV3AdvancedInfo",
            "BtnV3CopyOutput",
            "BtnV3LinkedIn",
            "BtnV3GitHub",
            "FooterLinkButton",
            "Made by Caio Dal Re",
            "Set-V3Output (Get-V3HomeText)"
        )

        foreach ($marker in $markers) {
            if ($content.Contains($marker)) {
                Add-Result "OK" "Marcador encontrado: $marker"
            }
            else {
                Add-Result "FALHA" "Marcador ausente: $marker"
            }
        }

        $linkedinHandlers = (Select-String -Path $App -Pattern 'BtnV3LinkedIn\.Add_Click').Count
        $githubHandlers = (Select-String -Path $App -Pattern 'BtnV3GitHub\.Add_Click').Count

        if ($linkedinHandlers -eq 1) {
            Add-Result "OK" "Handler LinkedIn unico"
        }
        else {
            Add-Result "FALHA" "Handler LinkedIn esperado: 1, encontrado: $linkedinHandlers"
        }

        if ($githubHandlers -eq 1) {
            Add-Result "OK" "Handler GitHub unico"
        }
        else {
            Add-Result "FALHA" "Handler GitHub esperado: 1, encontrado: $githubHandlers"
        }

        if ($content.Contains('$script:V3LastExternalLinkUrl') -and $content.Contains('$script:V3LastExternalLinkAt')) {
            Add-Result "OK" "Protecao contra abertura dupla dos links encontrada"
        }
        else {
            Add-Result "FALHA" "Protecao contra abertura dupla dos links ausente"
        }
    }
    catch {
        Add-Result "FALHA" "Erro durante validacao: $($_.Exception.Message)"
    }
}

$results | Out-File $ReportTxt -Encoding UTF8

Write-Host ""
Write-Host "Resultado da Validacao V3"
Write-Host "========================="

if ($failures -eq 0) {
    Write-Host "APROVADO - V3 validada sem falhas."
}
else {
    Write-Host "REPROVADO - V3 possui $failures falha(s)."
}

Write-Host ""
Write-Host "Relatorio:"
Write-Host $ReportTxt
