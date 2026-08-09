[CmdletBinding()]
param(
    [string]$Root,
    [switch]$Check
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (
        Split-Path -Parent $MyInvocation.MyCommand.Path
    )
}

$resolvedRoot = (Resolve-Path $Root).Path
$manifestPath = Join-Path $resolvedRoot "checksums-v3.json"
$payloadPaths = @(
    "docs/V3-README.md",
    "install-v3.ps1",
    "ServiceDeskToolkit-CorporateV3.ps1",
    "src/ServiceDeskToolkit.Diagnostics/ServiceDeskToolkit.Diagnostics.psm1",
    "src/ServiceDeskToolkit.Health/ServiceDeskToolkit.Health.psm1",
    "src/ServiceDeskToolkit.Inventory/ServiceDeskToolkit.Inventory.psm1",
    "src/ServiceDeskToolkit.Network/ServiceDeskToolkit.Network.psm1",
    "src/ServiceDeskToolkit.Printers/ServiceDeskToolkit.Printers.psm1",
    "tools/Test-ToolkitV3.ps1",
    "version-v3.json"
)

function Get-RepositoryFileBytes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $sourceBytes = [System.IO.File]::ReadAllBytes($Path)
    $hasUtf8Bom = (
        $sourceBytes.Length -ge 3 -and
        $sourceBytes[0] -eq 0xEF -and
        $sourceBytes[1] -eq 0xBB -and
        $sourceBytes[2] -eq 0xBF
    )
    $text = [System.IO.File]::ReadAllText(
        $Path,
        [System.Text.Encoding]::UTF8
    )
    $normalizedText = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $bodyBytes = $utf8NoBom.GetBytes($normalizedText)
    $offset = 0

    if ($hasUtf8Bom) {
        $offset = 3
    }

    $repositoryBytes = New-Object byte[] ($bodyBytes.Length + $offset)

    if ($hasUtf8Bom) {
        $repositoryBytes[0] = 0xEF
        $repositoryBytes[1] = 0xBB
        $repositoryBytes[2] = 0xBF
    }

    [System.Array]::Copy(
        $bodyBytes,
        0,
        $repositoryBytes,
        $offset,
        $bodyBytes.Length
    )

    return $repositoryBytes
}

function Get-FileRepositorySha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()

    try {
        $bytes = Get-RepositoryFileBytes -Path $Path
        $hashBytes = $sha256.ComputeHash($bytes)
        return (
            [System.BitConverter]::ToString($hashBytes).Replace("-", "").
                ToLowerInvariant()
        )
    }
    finally {
        $sha256.Dispose()
    }
}

function ConvertTo-ManifestJson {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Manifest
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $productJson = ConvertTo-Json -InputObject $Manifest.product -Compress
    $versionJson = ConvertTo-Json -InputObject $Manifest.version -Compress
    $sourceRefJson = ConvertTo-Json -InputObject $Manifest.sourceRef -Compress
    [void]$lines.Add("{")
    [void]$lines.Add('  "schemaVersion": 1,')
    [void]$lines.Add("  `"product`": $productJson,")
    [void]$lines.Add("  `"version`": $versionJson,")
    [void]$lines.Add("  `"sourceRef`": $sourceRefJson,")
    [void]$lines.Add('  "algorithm": "SHA256",')
    [void]$lines.Add('  "files": [')

    for ($index = 0; $index -lt $Manifest.files.Count; $index++) {
        $entry = $Manifest.files[$index]
        $pathJson = ConvertTo-Json -InputObject $entry.path -Compress
        $sha256Json = ConvertTo-Json -InputObject $entry.sha256 -Compress
        $suffix = ","

        if ($index -eq ($Manifest.files.Count - 1)) {
            $suffix = ""
        }

        [void]$lines.Add("    {")
        [void]$lines.Add("      `"path`": $pathJson,")
        [void]$lines.Add("      `"sha256`": $sha256Json")
        [void]$lines.Add("    }$suffix")
    }

    [void]$lines.Add("  ]")
    [void]$lines.Add("}")
    return ($lines -join "`n") + "`n"
}

$versionPath = Join-Path $resolvedRoot "version-v3.json"
$versionInfo = Get-Content $versionPath -Raw | ConvertFrom-Json
$entries = New-Object System.Collections.Generic.List[object]

foreach ($relativePath in $payloadPaths) {
    $fullPath = Join-Path $resolvedRoot $relativePath

    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Arquivo do pacote V3 nao encontrado: $relativePath"
    }

    [void]$entries.Add(
        [pscustomobject][ordered]@{
            path = $relativePath
            sha256 = Get-FileRepositorySha256 -Path $fullPath
        }
    )
}

$manifest = [pscustomobject][ordered]@{
    schemaVersion = 1
    product = "ServiceDesk Toolkit Corporate V3"
    version = [string]$versionInfo.version
    sourceRef = [string]$versionInfo.sourceRef
    algorithm = "SHA256"
    files = $entries.ToArray()
}

if ($Check) {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Manifesto SHA-256 nao encontrado: $manifestPath"
    }

    $published = Get-Content $manifestPath -Raw | ConvertFrom-Json

    foreach ($property in @(
        "schemaVersion",
        "product",
        "version",
        "sourceRef",
        "algorithm"
    )) {
        if ([string]$published.$property -ne [string]$manifest.$property) {
            throw "Manifesto SHA-256 diverge no campo: $property"
        }
    }

    $publishedEntries = @($published.files)

    if ($publishedEntries.Count -ne $entries.Count) {
        throw "Manifesto SHA-256 possui quantidade incorreta de arquivos."
    }

    for ($index = 0; $index -lt $entries.Count; $index++) {
        if (
            [string]$publishedEntries[$index].path -ne
            [string]$entries[$index].path
        ) {
            throw "Ordem ou caminho divergente no manifesto SHA-256."
        }

        if (
            [string]$publishedEntries[$index].sha256 -ne
            [string]$entries[$index].sha256
        ) {
            throw (
                "Checksum divergente no manifesto: " +
                [string]$entries[$index].path
            )
        }
    }

    Write-Host "APROVADO - manifesto SHA-256 consistente." -ForegroundColor Green
    exit 0
}

$json = ConvertTo-ManifestJson -Manifest $manifest
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestPath, $json, $utf8NoBom)

Write-Host "Manifesto SHA-256 atualizado: $manifestPath" -ForegroundColor Green
