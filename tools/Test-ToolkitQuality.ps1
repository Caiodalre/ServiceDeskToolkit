param(
    [string]$ScriptPath = ".\ServiceDeskToolkit-Corporate.ps1"
)

$failures = New-Object System.Collections.Generic.List[string]

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message) | Out-Null
}

function Write-Ok {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

try {
    if (!(Test-Path $ScriptPath)) {
        Add-Failure "Arquivo nao encontrado: $ScriptPath"
    }
    else {
        $fullPath = (Resolve-Path $ScriptPath).Path
        $bytes = [System.IO.File]::ReadAllBytes($fullPath)

        if ($bytes.Length -lt 3) {
            Add-Failure "Arquivo muito pequeno ou invalido."
        }
        else {
            $hasBom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

            if ($hasBom) {
                Write-Ok "Encoding UTF-8 BOM detectado."
            }
            else {
                Add-Failure "Arquivo nao esta salvo com UTF-8 BOM."
            }
        }

        $text = [System.IO.File]::ReadAllText($fullPath, [System.Text.Encoding]::UTF8)

        $parseErrors = $null
        $null = [System.Management.Automation.PSParser]::Tokenize($text, [ref]$parseErrors)

        if ($parseErrors.Count -eq 0) {
            Write-Ok "Sem erro de sintaxe PowerShell."
        }
        else {
            Add-Failure "Erros de sintaxe encontrados: $($parseErrors.Count)"
            $parseErrors | Select-Object -First 10 | Format-List *
        }

        if ([regex]::IsMatch($text, '[\u2500-\u257F]')) {
            Add-Failure "Foram encontrados caracteres box drawing Unicode. Usar ASCII seguro."
        }
        else {
            Write-Ok "Sem caracteres box drawing Unicode."
        }

        $mojibakePatterns = @(
            'â”',
            'â€“',
            'â€”',
            'â€œ',
            'â€',
            'Ã£',
            'Ã§',
            'Ã©',
            'Â'
        )

        foreach ($pattern in $mojibakePatterns) {
            if ($text.Contains($pattern)) {
                Add-Failure "Possivel residuo de encoding quebrado encontrado: $pattern"
            }
        }

        if ($failures.Count -eq 0) {
            Write-Ok "Sem residuos fortes de encoding quebrado."
        }

        $requiredMarkers = @(
            'function Write-ToolkitStructuredLog',
            'function Write-ToolkitRuntimeLog',
            'function Write-ToolkitActionLog',
            'function Write-ToolkitErrorLog',
            'Toolkit iniciado com logs estruturados',
            '$window.ShowDialog()'
        )

        foreach ($marker in $requiredMarkers) {
            if ($text.Contains($marker)) {
                Write-Ok "Marcador encontrado: $marker"
            }
            else {
                Add-Failure "Marcador obrigatorio nao encontrado: $marker"
            }
        }
    }
}
catch {
    Add-Failure "Falha inesperada no validador: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Resultado do Quality Gate" -ForegroundColor Cyan
Write-Host "=========================" -ForegroundColor Cyan

if ($failures.Count -eq 0) {
    Write-Host "APROVADO - Toolkit passou no Quality Gate." -ForegroundColor Green
    exit 0
}
else {
    foreach ($failure in $failures) {
        Write-Fail $failure
    }

    Write-Host ""
    Write-Host "REPROVADO - Corrija os pontos acima antes de commitar novas mudancas." -ForegroundColor Red
    exit 1
}