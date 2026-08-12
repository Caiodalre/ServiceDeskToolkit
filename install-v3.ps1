param(
    [string]$Branch = "v3.1.0-preview.1",
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

function Get-V3DownloadedText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,

        [string]$ExpectedSha256
    )

    Write-V3Step "Baixando: $Name" "Yellow"

    Invoke-WebRequest `
        -Uri $Url `
        -OutFile $DestinationPath `
        -UseBasicParsing

    $fileInfo = Get-Item -LiteralPath $DestinationPath

    if ($fileInfo.Length -eq 0) {
        throw "Falha: conteudo vazio ao baixar $Name. URL: $Url"
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        $actualSha256 = (
            Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        $normalizedExpected = $ExpectedSha256.ToLowerInvariant()

        if ($actualSha256 -ne $normalizedExpected) {
            throw (
                "Falha de integridade em {0}. Esperado: {1}. Obtido: {2}." -f
                    $Name,
                    $normalizedExpected,
                    $actualSha256
            )
        }

        Write-V3Step "SHA-256 confirmado: $Name" "Green"
    }

    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $content = [System.IO.File]::ReadAllText($DestinationPath, $strictUtf8)
    $content = $content.TrimStart([char]0xFEFF)

    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "Falha: conteudo vazio ao baixar $Name. URL: $Url"
    }

    return $content
}

function Get-V3ChecksumManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ManifestText,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedSourceRef,

        [Parameter(Mandatory = $true)]
        [string[]]$RequiredPaths
    )

    try {
        $manifest = $ManifestText | ConvertFrom-Json
    }
    catch {
        throw "Manifesto SHA-256 invalido: $($_.Exception.Message)"
    }

    if ([int]$manifest.schemaVersion -ne 1) {
        throw "Manifesto SHA-256 usa schemaVersion nao suportado."
    }

    if ([string]$manifest.algorithm -ne "SHA256") {
        throw "Manifesto SHA-256 informa algoritmo nao suportado."
    }

    if ([string]$manifest.sourceRef -ne $ExpectedSourceRef) {
        throw (
            "Manifesto pertence a {0}, mas o instalador solicitou {1}." -f
                [string]$manifest.sourceRef,
                $ExpectedSourceRef
        )
    }

    $checksums = @{}

    foreach ($entry in @($manifest.files)) {
        $relativePath = ([string]$entry.path).Replace("\", "/")
        $sha256 = [string]$entry.sha256

        if ($relativePath -notmatch "^[A-Za-z0-9._/-]+$") {
            throw "Caminho invalido no manifesto SHA-256: $relativePath"
        }

        if ($sha256 -notmatch "^[A-Fa-f0-9]{64}$") {
            throw "Hash SHA-256 invalido no manifesto: $relativePath"
        }

        if ($checksums.ContainsKey($relativePath)) {
            throw "Caminho duplicado no manifesto SHA-256: $relativePath"
        }

        $checksums[$relativePath] = $sha256.ToLowerInvariant()
    }

    foreach ($requiredPath in $RequiredPaths) {
        if (-not $checksums.ContainsKey($requiredPath)) {
            throw "Arquivo obrigatorio ausente do manifesto: $requiredPath"
        }
    }

    return $checksums
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
        [string]$VersionText,

        [Parameter(Mandatory = $true)]
        [string]$ManifestText,

        [Parameter(Mandatory = $true)]
        [string]$DiagnosticsModuleText,

        [Parameter(Mandatory = $true)]
        [string]$HealthModuleText,

        [Parameter(Mandatory = $true)]
        [string]$InventoryModuleText,

        [Parameter(Mandatory = $true)]
        [string]$NetworkModuleText,

        [Parameter(Mandatory = $true)]
        [string]$PrintersModuleText,

        [Parameter(Mandatory = $true)]
        [string]$OfficeModuleText,

        [Parameter(Mandatory = $true)]
        [string]$CmdText
    )

    $buildName = "build-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    $installPath = Join-Path $RootPath $buildName

    $mainFile = Join-Path $installPath "ServiceDeskToolkit-CorporateV3.ps1"
    $cmdFile = Join-Path $installPath "ServiceDeskToolkitV3.cmd"
    $validatorFile = Join-Path $installPath "tools\Test-ToolkitV3.ps1"
    $readmeFile = Join-Path $installPath "docs\V3-README.md"
    $versionFile = Join-Path $installPath "version-v3.json"
    $manifestFile = Join-Path $installPath "checksums-v3.json"
    $diagnosticsModuleFile = Join-Path `
        $installPath `
        "src\ServiceDeskToolkit.Diagnostics\ServiceDeskToolkit.Diagnostics.psm1"
    $healthModuleFile = Join-Path `
        $installPath `
        "src\ServiceDeskToolkit.Health\ServiceDeskToolkit.Health.psm1"
    $inventoryModuleFile = Join-Path `
        $installPath `
        "src\ServiceDeskToolkit.Inventory\ServiceDeskToolkit.Inventory.psm1"
    $networkModuleFile = Join-Path `
        $installPath `
        "src\ServiceDeskToolkit.Network\ServiceDeskToolkit.Network.psm1"
    $printersModuleFile = Join-Path `
        $installPath `
        "src\ServiceDeskToolkit.Printers\ServiceDeskToolkit.Printers.psm1"
    $officeModuleFile = Join-Path `
        $installPath `
        "src\ServiceDeskToolkit.Office\ServiceDeskToolkit.Office.psm1"
    $latestFile = Join-Path $RootPath "latest.txt"

    New-Item -Path $installPath -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $installPath "tools") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $installPath "docs") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $installPath "reports") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $installPath "logs") -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $installPath "backups") -ItemType Directory -Force | Out-Null
    New-Item `
        -Path (Split-Path $diagnosticsModuleFile -Parent) `
        -ItemType Directory `
        -Force | Out-Null
    New-Item `
        -Path (Split-Path $healthModuleFile -Parent) `
        -ItemType Directory `
        -Force | Out-Null
    New-Item `
        -Path (Split-Path $inventoryModuleFile -Parent) `
        -ItemType Directory `
        -Force | Out-Null
    New-Item `
        -Path (Split-Path $networkModuleFile -Parent) `
        -ItemType Directory `
        -Force | Out-Null
    New-Item `
        -Path (Split-Path $printersModuleFile -Parent) `
        -ItemType Directory `
        -Force | Out-Null
    New-Item `
        -Path (Split-Path $officeModuleFile -Parent) `
        -ItemType Directory `
        -Force | Out-Null

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    $ascii = [System.Text.Encoding]::ASCII

    Write-V3TextFile -Path $mainFile -Content $MainText -Encoding $utf8Bom
    Write-V3TextFile -Path $validatorFile -Content $ValidatorText -Encoding $utf8Bom
    Write-V3TextFile -Path $readmeFile -Content $ReadmeText -Encoding $utf8Bom
    Write-V3TextFile -Path $versionFile -Content $VersionText -Encoding $utf8Bom
    Write-V3TextFile -Path $manifestFile -Content $ManifestText -Encoding $utf8Bom
    Write-V3TextFile `
        -Path $diagnosticsModuleFile `
        -Content $DiagnosticsModuleText `
        -Encoding $utf8Bom
    Write-V3TextFile `
        -Path $healthModuleFile `
        -Content $HealthModuleText `
        -Encoding $utf8Bom
    Write-V3TextFile `
        -Path $inventoryModuleFile `
        -Content $InventoryModuleText `
        -Encoding $utf8Bom
    Write-V3TextFile `
        -Path $networkModuleFile `
        -Content $NetworkModuleText `
        -Encoding $utf8Bom
    Write-V3TextFile `
        -Path $printersModuleFile `
        -Content $PrintersModuleText `
        -Encoding $utf8Bom
    Write-V3TextFile `
        -Path $officeModuleFile `
        -Content $OfficeModuleText `
        -Encoding $utf8Bom
    Write-V3TextFile -Path $cmdFile -Content $CmdText -Encoding $ascii

    Unblock-File $mainFile -ErrorAction SilentlyContinue
    Unblock-File $validatorFile -ErrorAction SilentlyContinue
    Unblock-File $readmeFile -ErrorAction SilentlyContinue
    Unblock-File $versionFile -ErrorAction SilentlyContinue
    Unblock-File $manifestFile -ErrorAction SilentlyContinue
    Unblock-File $diagnosticsModuleFile -ErrorAction SilentlyContinue
    Unblock-File $healthModuleFile -ErrorAction SilentlyContinue
    Unblock-File $inventoryModuleFile -ErrorAction SilentlyContinue
    Unblock-File $networkModuleFile -ErrorAction SilentlyContinue
    Unblock-File $printersModuleFile -ErrorAction SilentlyContinue
    Unblock-File $officeModuleFile -ErrorAction SilentlyContinue
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
        VersionFile = $versionFile
        ManifestFile = $manifestFile
        DiagnosticsModuleFile = $diagnosticsModuleFile
        HealthModuleFile = $healthModuleFile
        InventoryModuleFile = $inventoryModuleFile
        NetworkModuleFile = $networkModuleFile
        PrintersModuleFile = $printersModuleFile
        OfficeModuleFile = $officeModuleFile
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

Write-V3Step "1/5 - Baixando e validando integridade..." "Cyan"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$integrityPaths = @(
    "install-v3.ps1",
    "ServiceDeskToolkit-CorporateV3.ps1",
    "tools/Test-ToolkitV3.ps1",
    "docs/V3-README.md",
    "version-v3.json",
    "src/ServiceDeskToolkit.Diagnostics/ServiceDeskToolkit.Diagnostics.psm1",
    "src/ServiceDeskToolkit.Health/ServiceDeskToolkit.Health.psm1",
    "src/ServiceDeskToolkit.Inventory/ServiceDeskToolkit.Inventory.psm1",
    "src/ServiceDeskToolkit.Network/ServiceDeskToolkit.Network.psm1",
    "src/ServiceDeskToolkit.Printers/ServiceDeskToolkit.Printers.psm1",
    "src/ServiceDeskToolkit.Office/ServiceDeskToolkit.Office.psm1"
)
$downloadRoot = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    ("ServiceDeskToolkitV3-download-" + [guid]::NewGuid().ToString("N"))
New-Item -Path $downloadRoot -ItemType Directory -Force | Out-Null

try {
    $manifestText = Get-V3DownloadedText `
        -Url "$baseUrl/checksums-v3.json" `
        -Name "Manifesto SHA-256" `
        -DestinationPath (Join-Path $downloadRoot "checksums-v3.json")
    $checksumMap = Get-V3ChecksumManifest `
        -ManifestText $manifestText `
        -ExpectedSourceRef $Branch `
        -RequiredPaths $integrityPaths

    $payloads = @{}
    $payloadNames = @{
        "ServiceDeskToolkit-CorporateV3.ps1" = "Script principal V3"
        "tools/Test-ToolkitV3.ps1" = "Validador V3"
        "docs/V3-README.md" = "README V3"
        "version-v3.json" = "Metadados de versao V3"
        "src/ServiceDeskToolkit.Diagnostics/ServiceDeskToolkit.Diagnostics.psm1" = "Modulo de diagnosticos V3"
        "src/ServiceDeskToolkit.Health/ServiceDeskToolkit.Health.psm1" = "Modulo de avaliacao de saude V3"
        "src/ServiceDeskToolkit.Inventory/ServiceDeskToolkit.Inventory.psm1" = "Modulo de inventario V3"
        "src/ServiceDeskToolkit.Network/ServiceDeskToolkit.Network.psm1" = "Modulo de diagnostico de rede V3"
        "src/ServiceDeskToolkit.Printers/ServiceDeskToolkit.Printers.psm1" = "Modulo de diagnostico de impressoras V3"
        "src/ServiceDeskToolkit.Office/ServiceDeskToolkit.Office.psm1" = "Modulo Office, TPM e autenticacao V3"
    }

    foreach ($relativePath in ($payloadNames.Keys | Sort-Object)) {
        $destinationName = $relativePath.Replace("/", "-")
        $payloads[$relativePath] = Get-V3DownloadedText `
            -Url "$baseUrl/$relativePath" `
            -Name $payloadNames[$relativePath] `
            -DestinationPath (Join-Path $downloadRoot $destinationName) `
            -ExpectedSha256 $checksumMap[$relativePath]
    }
}
finally {
    if (Test-Path -LiteralPath $downloadRoot) {
        Remove-Item `
            -LiteralPath $downloadRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

$mainText = $payloads["ServiceDeskToolkit-CorporateV3.ps1"]
$validatorText = $payloads["tools/Test-ToolkitV3.ps1"]
$readmeText = $payloads["docs/V3-README.md"]
$versionText = $payloads["version-v3.json"]
$diagnosticsModuleText = $payloads[
    "src/ServiceDeskToolkit.Diagnostics/ServiceDeskToolkit.Diagnostics.psm1"
]
$healthModuleText = $payloads[
    "src/ServiceDeskToolkit.Health/ServiceDeskToolkit.Health.psm1"
]
$inventoryModuleText = $payloads[
    "src/ServiceDeskToolkit.Inventory/ServiceDeskToolkit.Inventory.psm1"
]
$networkModuleText = $payloads[
    "src/ServiceDeskToolkit.Network/ServiceDeskToolkit.Network.psm1"
]
$printersModuleText = $payloads[
    "src/ServiceDeskToolkit.Printers/ServiceDeskToolkit.Printers.psm1"
]
$officeModuleText = $payloads[
    "src/ServiceDeskToolkit.Office/ServiceDeskToolkit.Office.psm1"
]
$cmdText = New-V3CmdText

Write-V3Step "2/5 - Validando conteudo baixado..." "Cyan"

$requiredMarkers = @(
    "ServiceDesk Toolkit Corporate V3",
    "function Invoke-V3SafeSpoolerRestart",
    "CORRECAO SEGURA - REINICIAR SPOOLER",
    "function Invoke-V3SafeTimeSync",
    "function Invoke-V3SafeFlushDns",
    "function New-V3WindowsRepairWorker",
    "function Invoke-V3WindowsRepair",
    "function Start-V3WindowsRepairMonitor",
    "function Get-V3WindowsRepairProgressText",
    "BtnV3Sfc",
    "BtnV3Dism",
    "Invoke-V3WindowsRepair -Tool ""SFC""",
    "Invoke-V3WindowsRepair -Tool ""DISM""",
    "System32\sfc.exe",
    "System32\dism.exe",
    "-Verb RunAs",
    "StandardOutputEncoding",
    "OEMCodePage",
    "ReadToEndAsync",
    "System.Windows.Threading.DispatcherTimer",
    "REPARO DO WINDOWS - CONCLUÍDO",
    "REPARO DO WINDOWS - INTERROMPIDO",
    "REPARO DO WINDOWS - FALHA AO INICIAR",
    "windows-repair-audit.jsonl",
    "RESULTADO DO REPARO",
    "Resumo final:",
    "function Invoke-V3InternetDiagnosticSummary",
    "function Invoke-V3VpnDiagnosticSummary",
    "Get-ToolkitInventorySnapshot",
    "Get-ToolkitInventoryAssessment",
    "Format-ToolkitInventoryReport",
    "INVENTARIO DA MAQUINA - PAINEL CONSOLIDADO",
    "Tipo de acao: Coleta de inventario sem correcao",
    "REDE RESUMIDA",
    "BIOS / SERIAL",
    "Get-ToolkitNetworkSnapshot",
    "Get-ToolkitNetworkAssessment",
    "Format-ToolkitNetworkReport",
    "function Invoke-V3PrintersPanel",
    "BtnV3Printers",
    "Invoke-V3PrintersPanel",
    "PAINEL DE IMPRESSORAS - DIAGNOSTICO CONSOLIDADO",
    "Tipo de acao: Diagnostico de impressoras sem correcao",
    "SERVICO SPOOLER",
    "IMPRESSORAS INSTALADAS",
    "FILA DE IMPRESSAO",
    "IMPRESSORAS OFFLINE / COM ALERTA",
    "PORTAS UTILIZADAS",
    "DRIVERS PRINCIPAIS",
    "Get-ToolkitPrinterSnapshot",
    "Get-ToolkitPrinterAssessment",
    "Format-ToolkitPrinterReport",
    "function Invoke-V3OfficeTpmPanel",
    "function Invoke-V3OfficeWamRepair",
    "Get-ToolkitOfficeTpmSnapshot",
    "Get-ToolkitOfficeTpmAssessment",
    "Format-ToolkitOfficeTpmReport",
    "Repair-ToolkitOfficeWam",
    "Get-ToolkitOfficeEdition",
    "Office 2016",
    "Office 2019",
    "Office 2021",
    "/dstatusall",
    "OSPP_UNLICENSED",
    "BtnV3OfficeTpm",
    "BtnV3OfficeWam",
    "OFFICE / TPM / AUTENTICACAO - DIAGNOSTICO CONSOLIDADO",
    "ACOES CRITICAS NAO AUTOMATIZADAS",
    "CONCLUSAO AUTOMATICA",
    "ActionGridButton",
    "UniformGrid Columns",
    "function Invoke-V3WorkflowPrinter",
    "Atendimento Guiado - Impressora Nao Imprime",
    "Impressora nao imprime",
    "return New-V3WorkflowResult @workflowParameters",
    "Set-V3Output (Invoke-V3WorkflowPrinter)",
    "Reiniciar o Spooler somente quando houver indicio de falha no servico ou fila",
    "function Invoke-V3MachineHealthPanel",
    "Get-ToolkitMachineHealthSnapshot",
    "Get-ToolkitMachineHealthAssessment",
    "Format-ToolkitMachineHealthReport",
    "PAINEL DE SAUDE DA MAQUINA",
    "Tipo de acao: Diagnostico geral sem correcao",
    "PONTUACAO GERAL",
    "Pontuacao:",
    "Classificacao:",
    "INDICADORES",
    "-Label ""Memoria RAM""",
    "-Label ""Disco do Windows""",
    "-Label ""Reinicio pendente""",
    "BtnV3Health",
    "Set-V3Output (Invoke-V3MachineHealthPanel)"
)

$validationText = @(
    $mainText
    $diagnosticsModuleText
    $healthModuleText
    $inventoryModuleText
    $networkModuleText
    $printersModuleText
    $officeModuleText
) -join [Environment]::NewLine

foreach ($marker in $requiredMarkers) {
    if (-not $validationText.Contains($marker)) {
        throw "Marcador obrigatorio nao encontrado no pacote V3: $marker"
    }
}

Test-V3PowerShellSyntax -Text $mainText -Name "ServiceDeskToolkit-CorporateV3.ps1"
Test-V3PowerShellSyntax -Text $validatorText -Name "tools\Test-ToolkitV3.ps1"
Test-V3PowerShellSyntax `
    -Text $diagnosticsModuleText `
    -Name "ServiceDeskToolkit.Diagnostics.psm1"
Test-V3PowerShellSyntax `
    -Text $healthModuleText `
    -Name "ServiceDeskToolkit.Health.psm1"
Test-V3PowerShellSyntax `
    -Text $inventoryModuleText `
    -Name "ServiceDeskToolkit.Inventory.psm1"
Test-V3PowerShellSyntax `
    -Text $networkModuleText `
    -Name "ServiceDeskToolkit.Network.psm1"
Test-V3PowerShellSyntax `
    -Text $printersModuleText `
    -Name "ServiceDeskToolkit.Printers.psm1"
Test-V3PowerShellSyntax `
    -Text $officeModuleText `
    -Name "ServiceDeskToolkit.Office.psm1"

try {
    $versionInfo = $versionText | ConvertFrom-Json

    if ([string]::IsNullOrWhiteSpace([string]$versionInfo.version)) {
        throw "Campo version ausente."
    }

    if ([string]::IsNullOrWhiteSpace([string]$versionInfo.channel)) {
        throw "Campo channel ausente."
    }
}
catch {
    throw "version-v3.json invalido: $($_.Exception.Message)"
}

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
            -VersionText $versionText `
            -ManifestText $manifestText `
            -DiagnosticsModuleText $diagnosticsModuleText `
            -HealthModuleText $healthModuleText `
            -InventoryModuleText $inventoryModuleText `
            -NetworkModuleText $networkModuleText `
            -PrintersModuleText $printersModuleText `
            -OfficeModuleText $officeModuleText `
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

    if ($LASTEXITCODE -ne 0) {
        throw "Validador V3 finalizou com codigo $LASTEXITCODE."
    }
}
catch {
    Write-V3Step "Validador retornou erro: $($_.Exception.Message)" "Red"
    throw
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
