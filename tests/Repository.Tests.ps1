$initializeRepositoryTests = {
$script:RepositoryRoot = Split-Path -Parent $PSScriptRoot

function Assert-RepositoryCondition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

}

if ((Get-Module Pester).Version.Major -ge 5) {
    BeforeAll $initializeRepositoryTests
}
else {
    . $initializeRepositoryTests
}

Describe "PowerShell source integrity" {
    It "parses every versioned PowerShell source without errors" {
        $parseFailures = New-Object System.Collections.Generic.List[string]
        $scripts = Get-ChildItem -Path $script:RepositoryRoot -Recurse -File |
            Where-Object {
                $_.Extension -in @(".ps1", ".psm1") -and
                $_.FullName -notmatch "[\\/](backups|reports|logs)[\\/]"
            }

        foreach ($scriptFile in $scripts) {
            $tokens = $null
            $errors = $null

            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $scriptFile.FullName,
                [ref]$tokens,
                [ref]$errors
            )

            foreach ($parseError in $errors) {
                $relativePath = $scriptFile.FullName.Substring($script:RepositoryRoot.Length + 1)
                $parseFailures.Add(
                    ("{0}:{1} - {2}" -f
                        $relativePath,
                        $parseError.Extent.StartLineNumber,
                        $parseError.Message
                    )
                )
            }
        }

        if ($parseFailures.Count -gt 0) {
            Write-Host ($parseFailures -join [Environment]::NewLine)
        }

        Assert-RepositoryCondition `
            -Condition ($parseFailures.Count -eq 0) `
            -Message "Foram encontrados $($parseFailures.Count) erro(s) de sintaxe."
    }
}

Describe "V3 version contract" {
    BeforeAll {
        $script:V3VersionPath = Join-Path $script:RepositoryRoot "version-v3.json"
        $script:V3Version = Get-Content $script:V3VersionPath -Raw | ConvertFrom-Json
        $script:V3AppText = Get-Content (
            Join-Path $script:RepositoryRoot "ServiceDeskToolkit-CorporateV3.ps1"
        ) -Raw
        $script:V3InstallerText = Get-Content (
            Join-Path $script:RepositoryRoot "install-v3.ps1"
        ) -Raw
    }

    It "provides dedicated V3 metadata" {
        Assert-RepositoryCondition `
            -Condition (Test-Path $script:V3VersionPath) `
            -Message "version-v3.json nao foi encontrado."
        Assert-RepositoryCondition `
            -Condition ([string]$script:V3Version.name -eq "ServiceDesk Toolkit Corporate V3") `
            -Message "Nome do produto V3 incorreto."
        Assert-RepositoryCondition `
            -Condition ([string]$script:V3Version.version -match "^3\.") `
            -Message "A versao V3 deve iniciar com 3."
        Assert-RepositoryCondition `
            -Condition (-not [string]::IsNullOrWhiteSpace([string]$script:V3Version.channel)) `
            -Message "Canal V3 nao informado."
        Assert-RepositoryCondition `
            -Condition (-not [string]::IsNullOrWhiteSpace([string]$script:V3Version.sourceRef)) `
            -Message "Referencia de origem V3 nao informada."
    }

    It "makes the application read the dedicated metadata" {
        Assert-RepositoryCondition `
            -Condition ($script:V3AppText -match 'Join-Path \$script:RootPath "version-v3\.json"') `
            -Message "A aplicacao V3 nao le version-v3.json."
        Assert-RepositoryCondition `
            -Condition ($script:V3AppText -notmatch 'Join-Path \$script:RootPath "version\.json"') `
            -Message "A aplicacao V3 ainda depende dos metadados da V2."
    }

    It "ships the metadata through the V3 installer" {
        Assert-RepositoryCondition `
            -Condition ($script:V3InstallerText -match 'version-v3\.json') `
            -Message "O instalador V3 nao inclui version-v3.json."
        Assert-RepositoryCondition `
            -Condition ($script:V3InstallerText -match 'VersionText') `
            -Message "O instalador V3 nao grava os metadados de versao."
    }

    It "ships the modular health panel through the V3 installer" {
        Assert-RepositoryCondition `
            -Condition ($script:V3InstallerText -match 'ServiceDeskToolkit\.Diagnostics\.psm1') `
            -Message "O instalador V3 nao inclui o modulo de diagnosticos."
        Assert-RepositoryCondition `
            -Condition ($script:V3InstallerText -match 'ServiceDeskToolkit\.Health\.psm1') `
            -Message "O instalador V3 nao inclui o modulo de avaliacao de saude."
    }

    It "ships the operational diagnostic modules through the V3 installer" {
        $requiredModules = @(
            "ServiceDeskToolkit\.Inventory\.psm1",
            "ServiceDeskToolkit\.Network\.psm1",
            "ServiceDeskToolkit\.Printers\.psm1"
        )

        foreach ($requiredModule in $requiredModules) {
            Assert-RepositoryCondition `
                -Condition ($script:V3InstallerText -match $requiredModule) `
                -Message "O instalador V3 nao inclui: $requiredModule"
        }
    }

    It "connects useful and protected SFC and DISM actions" {
        $requiredRepairMarkers = @(
            'function New-V3WindowsRepairWorker',
            'function Invoke-V3WindowsRepair',
            'function Start-V3WindowsRepairMonitor',
            'function Get-V3WindowsRepairProgressText',
            'BtnV3Sfc',
            'BtnV3Dism',
            'Invoke-V3WindowsRepair -Tool "SFC"',
            'Invoke-V3WindowsRepair -Tool "DISM"',
            'System32\sfc.exe',
            'System32\dism.exe',
            '-Verb RunAs',
            'StandardOutputEncoding',
            'OEMCodePage',
            'ReadToEndAsync',
            'System.Windows.Threading.DispatcherTimer',
            'REPARO DO WINDOWS - CONCLUÍDO',
            'REPARO DO WINDOWS - INTERROMPIDO',
            'REPARO DO WINDOWS - FALHA AO INICIAR',
            'windows-repair-audit.jsonl',
            'Resumo final:'
        )

        foreach ($repairMarker in $requiredRepairMarkers) {
            Assert-RepositoryCondition `
                -Condition ($script:V3AppText.Contains($repairMarker)) `
                -Message "Acao de reparo V3 incompleta. Marcador ausente: $repairMarker"
        }

        $sfcHandlers = (
            [regex]::Matches(
                $script:V3AppText,
                'BtnV3Sfc"\)\.Add_Click'
            )
        ).Count
        $dismHandlers = (
            [regex]::Matches(
                $script:V3AppText,
                'BtnV3Dism"\)\.Add_Click'
            )
        ).Count

        Assert-RepositoryCondition `
            -Condition ($sfcHandlers -eq 1) `
            -Message "Esperado um handler SFC, encontrado: $sfcHandlers"
        Assert-RepositoryCondition `
            -Condition ($dismHandlers -eq 1) `
            -Message "Esperado um handler DISM, encontrado: $dismHandlers"
    }
}

Describe "Knowledge base contract" {
    BeforeAll {
        $script:KnowledgeBase = Get-Content (
            Join-Path $script:RepositoryRoot "data/knowledge-base.json"
        ) -Raw | ConvertFrom-Json
    }

    It "contains articles" {
        Assert-RepositoryCondition `
            -Condition (@($script:KnowledgeBase).Count -gt 0) `
            -Message "A base de conhecimento esta vazia."
    }

    It "uses unique article identifiers" {
        $duplicates = @($script:KnowledgeBase) |
            Group-Object -Property id |
            Where-Object Count -gt 1

        Assert-RepositoryCondition `
            -Condition (@($duplicates).Count -eq 0) `
            -Message "A base de conhecimento possui IDs duplicados."
    }

    It "provides the required operational fields" {
        $requiredFields = @(
            "id",
            "titulo",
            "categoria",
            "palavrasChave",
            "causaProvavel",
            "resumo",
            "passos",
            "acoesToolkit",
            "risco"
        )

        $invalidArticles = New-Object System.Collections.Generic.List[string]

        foreach ($article in @($script:KnowledgeBase)) {
            foreach ($field in $requiredFields) {
                if ($article.PSObject.Properties.Name -notcontains $field) {
                    $invalidArticles.Add("$($article.id): campo ausente $field")
                }
            }
        }

        if ($invalidArticles.Count -gt 0) {
            Write-Host ($invalidArticles -join [Environment]::NewLine)
        }

        Assert-RepositoryCondition `
            -Condition ($invalidArticles.Count -eq 0) `
            -Message "A base de conhecimento possui $($invalidArticles.Count) campo(s) ausente(s)."
    }
}

Describe "Automation contracts" {
    It "returns failure exit codes from release validators" {
        $v3Validator = Get-Content (
            Join-Path $script:RepositoryRoot "tools/Test-ToolkitV3.ps1"
        ) -Raw
        $releaseValidator = Get-Content (
            Join-Path $script:RepositoryRoot "tools/Test-ToolkitRelease.ps1"
        ) -Raw

        Assert-RepositoryCondition `
            -Condition ($v3Validator -match 'exit \$exitCode') `
            -Message "O validador V3 nao retorna codigo de saida."
        Assert-RepositoryCondition `
            -Condition ($releaseValidator -match 'exit \$exitCode') `
            -Message "O validador de release nao retorna codigo de saida."
    }

    It "does not execute downloaded V3 content through Invoke-Expression" {
        $installer = Get-Content (
            Join-Path $script:RepositoryRoot "install-v3.ps1"
        ) -Raw

        Assert-RepositoryCondition `
            -Condition ($installer -notmatch "(?im)^\s*(iex|Invoke-Expression)\b") `
            -Message "O instalador V3 executa conteudo baixado via Invoke-Expression."
    }
}
