[CmdletBinding()]
param(
    [string]$Root
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (
        Split-Path -Parent $MyInvocation.MyCommand.Path
    )
}

$script:StandardFailures = New-Object System.Collections.Generic.List[string]
$script:StandardResults = New-Object System.Collections.Generic.List[string]
$script:PowerShellAliases = @{}

Get-Alias | ForEach-Object {
    $script:PowerShellAliases[$_.Name] = $_.Definition
}

function Write-StandardLine {
    param(
        [string]$Status,
        [string]$Message
    )

    $line = "[$Status] $Message"
    [void]$script:StandardResults.Add($line)

    switch ($Status) {
        "OK" {
            Write-Host $line -ForegroundColor Green
        }
        "AVISO" {
            Write-Host $line -ForegroundColor Yellow
        }
        default {
            Write-Host $line -ForegroundColor Red
        }
    }
}

function Add-StandardFailure {
    param([string]$Message)

    [void]$script:StandardFailures.Add($Message)
    Write-StandardLine -Status "FALHA" -Message $Message
}

function Get-RepositoryFiles {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue

    if ($null -ne $gitCommand) {
        Push-Location $Root

        try {
            return @(
                & git ls-files --cached --others --exclude-standard |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )
        }
        finally {
            Pop-Location
        }
    }

    return @(
        Get-ChildItem -Path $Root -Recurse -File |
            Where-Object {
                $_.FullName -notmatch "[\\/](\.git|logs|reports|backups)[\\/]"
            } |
            ForEach-Object {
                $_.FullName.Substring($Root.Length + 1).Replace("\", "/")
            } |
            Sort-Object -Unique
    )
}

function Test-TextFileStandards {
    param(
        [string]$RelativePath,
        [string]$FullPath
    )

    $extension = [System.IO.Path]::GetExtension($RelativePath).ToLowerInvariant()
    $bytes = [System.IO.File]::ReadAllBytes($FullPath)
    $text = [System.IO.File]::ReadAllText(
        $FullPath,
        [System.Text.Encoding]::UTF8
    )
    $hasBom = (
        $bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF
    )

    if ($extension -in @(".ps1", ".psm1")) {
        $expectsBom = $RelativePath -ne "bootstrap.ps1"

        if ($expectsBom -and -not $hasBom) {
            Add-StandardFailure "$RelativePath deve usar UTF-8 com BOM."
        }
        elseif (-not $expectsBom -and $hasBom) {
            Add-StandardFailure "bootstrap.ps1 deve permanecer UTF-8 sem BOM."
        }

        $withoutCrLf = $text.Replace("`r`n", "")

        if ($withoutCrLf.Contains("`n")) {
            Add-StandardFailure "$RelativePath contém finais de linha mistos."
        }
    }
    elseif ($extension -eq ".cmd") {
        $withoutCrLf = $text.Replace("`r`n", "")

        if ($withoutCrLf.Contains("`n")) {
            Add-StandardFailure "$RelativePath deve usar CRLF."
        }
    }
    else {
        if ($text.Contains("`r")) {
            Add-StandardFailure "$RelativePath deve usar LF."
        }
    }

    if ($bytes.Length -eq 0 -or $bytes[$bytes.Length - 1] -ne 0x0A) {
        Add-StandardFailure "$RelativePath deve terminar com nova linha."
    }

    if ($extension -ne ".md") {
        $lineNumber = 0

        foreach ($line in ($text -split "`r?`n")) {
            $lineNumber++

            if ($line -match "[ `t]+$") {
                Add-StandardFailure (
                    "$RelativePath possui espaço no fim da linha $lineNumber."
                )
            }
        }
    }
}

function Test-PowerShellFile {
    param(
        [string]$RelativePath,
        [string]$FullPath
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $FullPath,
        [ref]$tokens,
        [ref]$parseErrors
    )

    foreach ($parseError in $parseErrors) {
        Add-StandardFailure (
            "{0}:{1} - {2}" -f
                $RelativePath,
                $parseError.Extent.StartLineNumber,
                $parseError.Message
        )
    }

    $functions = @(
        $ast.FindAll(
            {
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            },
            $true
        )
    )

    foreach ($duplicate in ($functions | Group-Object Name |
        Where-Object { $_.Count -gt 1 })) {
        $lines = @(
            $duplicate.Group |
                ForEach-Object { $_.Extent.StartLineNumber }
        ) -join ", "
        Add-StandardFailure (
            "$RelativePath define $($duplicate.Name) mais de uma vez: $lines."
        )
    }

    $approvedVerbs = @(Get-Verb | Select-Object -ExpandProperty Verb)

    foreach ($function in $functions) {
        if ($function.Name -notmatch "-") {
            continue
        }

        $verb = ($function.Name -split "-", 2)[0]

        if ($verb -notin $approvedVerbs) {
            Add-StandardFailure (
                "{0}:{1} - verbo PowerShell não aprovado em {2}." -f
                    $RelativePath,
                    $function.Extent.StartLineNumber,
                    $function.Name
            )
        }
    }

    $commands = @(
        $ast.FindAll(
            {
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            },
            $true
        )
    )

    foreach ($command in $commands) {
        $commandName = $command.GetCommandName()

        if (
            -not [string]::IsNullOrWhiteSpace($commandName) -and
            $script:PowerShellAliases.ContainsKey($commandName)
        ) {
            Add-StandardFailure (
                "{0}:{1} - alias {2} deve ser substituído por {3}." -f
                    $RelativePath,
                    $command.Extent.StartLineNumber,
                    $commandName,
                    $script:PowerShellAliases[$commandName]
            )
        }

        if ($commandName -in @("Invoke-Expression", "iex")) {
            Add-StandardFailure (
                "{0}:{1} - execução dinâmica não permitida: {2}." -f
                    $RelativePath,
                    $command.Extent.StartLineNumber,
                    $commandName
            )
        }
    }
}

function Test-JsonFile {
    param(
        [string]$RelativePath,
        [string]$FullPath
    )

    try {
        $null = Get-Content $FullPath -Raw | ConvertFrom-Json
    }
    catch {
        Add-StandardFailure (
            "$RelativePath contém JSON inválido: $($_.Exception.Message)"
        )
    }
}

$resolvedRoot = (Resolve-Path $Root).Path
$reportsPath = Join-Path $resolvedRoot "reports"

if (-not (Test-Path $reportsPath)) {
    New-Item -Path $reportsPath -ItemType Directory -Force | Out-Null
}

$repositoryFiles = @(Get-RepositoryFiles)
$textExtensions = @(
    ".cmd",
    ".json",
    ".md",
    ".ps1",
    ".psm1",
    ".yaml",
    ".yml"
)

Write-Host ""
Write-Host "ServiceDesk Toolkit - Repository Standards" -ForegroundColor Cyan
Write-Host "Root: $resolvedRoot" -ForegroundColor DarkCyan
Write-Host "Arquivos no escopo: $($repositoryFiles.Count)" -ForegroundColor DarkCyan
Write-Host ""

foreach ($relativePath in $repositoryFiles) {
    $fullPath = Join-Path $resolvedRoot $relativePath

    if (-not (Test-Path $fullPath -PathType Leaf)) {
        Add-StandardFailure "Arquivo não encontrado: $relativePath"
        continue
    }

    $extension = [System.IO.Path]::GetExtension(
        $relativePath
    ).ToLowerInvariant()

    if ($extension -in $textExtensions -or
        [string]::IsNullOrWhiteSpace($extension)) {
        Test-TextFileStandards `
            -RelativePath $relativePath `
            -FullPath $fullPath
    }

    if ($extension -in @(".ps1", ".psm1")) {
        Test-PowerShellFile `
            -RelativePath $relativePath `
            -FullPath $fullPath
    }

    if ($extension -eq ".json") {
        Test-JsonFile `
            -RelativePath $relativePath `
            -FullPath $fullPath
    }
}

$v3VersionPath = Join-Path $resolvedRoot "version-v3.json"
$v3InstallerPath = Join-Path $resolvedRoot "install-v3.ps1"
$readmePath = Join-Path $resolvedRoot "README.md"
$runbookPath = Join-Path $resolvedRoot "docs\RUNBOOK-OPERACIONAL.md"
$versionPath = Join-Path $resolvedRoot "version.json"
$stableInstallerPath = Join-Path $resolvedRoot "install-stable.ps1"
$checksumManifestPath = Join-Path $resolvedRoot "checksums-v3.json"
$checksumToolPath = Join-Path `
    $resolvedRoot `
    "tools\New-ToolkitChecksumManifest.ps1"

try {
    $v3Version = Get-Content $v3VersionPath -Raw | ConvertFrom-Json
    $expectedSourceRef = "v$($v3Version.version)"
    $v3Installer = Get-Content $v3InstallerPath -Raw
    $readme = Get-Content $readmePath -Raw

    if ([string]$v3Version.sourceRef -ne $expectedSourceRef) {
        Add-StandardFailure (
            "version-v3.json deve usar sourceRef $expectedSourceRef."
        )
    }

    if (-not $v3Installer.Contains(
        "[string]`$Branch = `"$expectedSourceRef`""
    )) {
        Add-StandardFailure (
            "install-v3.ps1 não está fixado em $expectedSourceRef."
        )
    }

    if (-not $readme.Contains($expectedSourceRef)) {
        Add-StandardFailure (
            "README.md não informa a versão V3 atual $expectedSourceRef."
        )
    }
}
catch {
    Add-StandardFailure (
        "Falha no contrato de versão V3: $($_.Exception.Message)"
    )
}

try {
    if (-not (Test-Path -LiteralPath $checksumManifestPath)) {
        throw "checksums-v3.json não foi encontrado."
    }

    if (-not (Test-Path -LiteralPath $checksumToolPath)) {
        throw "Gerador do manifesto SHA-256 não foi encontrado."
    }

    $checksumManifest = Get-Content $checksumManifestPath -Raw |
        ConvertFrom-Json

    if ([string]$checksumManifest.algorithm -ne "SHA256") {
        Add-StandardFailure "checksums-v3.json deve usar SHA256."
    }

    if (
        [string]$checksumManifest.sourceRef -ne
        [string]$v3Version.sourceRef
    ) {
        Add-StandardFailure (
            "checksums-v3.json diverge do sourceRef da V3."
        )
    }

    foreach ($marker in @(
        "Get-FileHash",
        "ExpectedSha256",
        "Falha de integridade",
        "checksums-v3.json"
    )) {
        if (-not $v3Installer.Contains($marker)) {
            Add-StandardFailure (
                "install-v3.ps1 não implementa integridade: $marker"
            )
        }
    }
}
catch {
    Add-StandardFailure (
        "Falha no contrato SHA-256: $($_.Exception.Message)"
    )
}

try {
    $versionInfo = Get-Content $versionPath -Raw | ConvertFrom-Json
    $stableInstaller = Get-Content $stableInstallerPath -Raw

    if (-not $stableInstaller.Contains(
        "`$Branch = `"$($versionInfo.stableVersion)`""
    )) {
        Add-StandardFailure (
            "install-stable.ps1 não aponta para " +
            "$($versionInfo.stableVersion)."
        )
    }

    $metadataText = Get-Content $versionPath -Raw
    $runbookText = Get-Content $runbookPath -Raw

    if ($metadataText -match "(?i)\|\s*(iex|Invoke-Expression)\b") {
        Add-StandardFailure (
            "version.json contém execução remota via pipe."
        )
    }

    if ($runbookText -match "(?i)\|\s*(iex|Invoke-Expression)\b") {
        Add-StandardFailure (
            "RUNBOOK-OPERACIONAL.md contém execução remota via pipe."
        )
    }
}
catch {
    Add-StandardFailure (
        "Falha no contrato de distribuição: $($_.Exception.Message)"
    )
}

if ($script:StandardFailures.Count -eq 0) {
    Write-StandardLine `
        -Status "OK" `
        -Message "Padrões de repositório aprovados."
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsPath "repository-standards-$timestamp.txt"
$reportLines = @(
    "ServiceDesk Toolkit - Repository Standards",
    "Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "Root: $resolvedRoot",
    "Arquivos: $($repositoryFiles.Count)",
    "Falhas: $($script:StandardFailures.Count)",
    ""
)
$reportLines += $script:StandardResults
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllLines($reportPath, $reportLines, $utf8Bom)

Write-Host ""
Write-Host "Relatório: $reportPath" -ForegroundColor DarkCyan

if ($script:StandardFailures.Count -gt 0) {
    Write-Host (
        "REPROVADO - $($script:StandardFailures.Count) falha(s)."
    ) -ForegroundColor Red
    exit 1
}

Write-Host "APROVADO - repositório padronizado." -ForegroundColor Green
exit 0
