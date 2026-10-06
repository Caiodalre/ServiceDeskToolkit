BeforeAll {
    Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ServiceDeskToolkit.Storage\ServiceDeskToolkit.Storage.psm1') -Force
}

Describe 'Storage diagnosis and guidance' {
    It 'classifies overlapping findings without treating cloud size as recovered space' {
        $kinds = @(Get-ToolkitStorageFileKinds 'Users\Test\OneDrive - Empresa\backup.pst' 600MB)
        $kinds | Should -Contain 'Pst'
        $kinds | Should -Contain 'OneDrive'
        $kinds = @(Get-ToolkitStorageFileKinds 'Windows\Temp\trace.evtx' 2MB)
        $kinds | Should -Contain 'WindowsTemp'
        $kinds | Should -Contain 'TempEvtx'
        Get-ToolkitStorageFileKinds 'Windows\ccmcache-other\x.bin' 1MB | Should -Not -Contain 'Ccm'
    }

    It 'distinguishes protected system files from disposable categories' {
        Get-ToolkitStorageFileKinds 'pagefile.sys' 1GB | Should -Contain 'Paging'
        Get-ToolkitStorageFileKinds 'Users\Test\pagefile.sys' 1GB | Should -Not -Contain 'Paging'
        Get-ToolkitStorageFileKinds 'Windows.old\Windows\file.dll' 1MB | Should -Contain 'Upgrade'
        Get-ToolkitStorageFileKinds 'Windows\MEMORY.DMP' 101MB | Should -Contain 'MemoryDump'
        Get-ToolkitStorageFileKinds 'Windows\MEMORY.DMP' 101MB | Should -Contain 'Dumps'
    }

    It 'collects a fixture without changing files and reports its limits honestly' {
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } } -ModuleName ServiceDeskToolkit.Storage
        $folder = Join-Path $TestDrive 'fixture'
        $temp = Join-Path $folder 'Windows\Temp'
        New-Item $temp -ItemType Directory -Force | Out-Null
        $path = Join-Path $temp 'trace.evtx'
        [IO.File]::WriteAllText($path, 'evidencia')
        $userTemp = Join-Path $folder 'Users\Test\AppData\Local\Temp'
        New-Item $userTemp -ItemType Directory -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $userTemp 'small.tmp'), 'abc')
        $before = Get-FileHash $path
        $snapshot = Get-ToolkitStorageSnapshot -ScanRoot $folder -MaxFiles 100 -MaxSeconds 30
        $snapshot.Categories['TempEvtx'].Count | Should -Be 1
        ($snapshot.UserTemps | Where-Object Name -eq 'Test').Bytes | Should -Be 3
        $snapshot.Categories['WindowsTemp'].Bytes | Should -Be 9
        (Get-FileHash $path).Hash | Should -Be $before.Hash
        $report = Format-ToolkitStorageReport $snapshot
        $report | Should -BeLike '*Categorias se sobrepoem*'
        $report | Should -BeLike '*SOLUCAO E PASSO A PASSO*'
        $report | Should -BeLike '*Nao observado no escopo lido*'
        $report | Should -BeLike '*Nao excluir a pasta ccmcache*'
        $report | Should -BeLike '*nao mede ganho de limpeza*'
        [IO.File]::WriteAllText((Join-Path $temp 'another.log'), 'abc')
        $limited = Get-ToolkitStorageSnapshot -ScanRoot $folder -MaxFiles 1 -MaxSeconds 30
        $limited.LimitReached | Should -BeTrue
        $limited.Partial | Should -BeTrue
        $limited.FilesVisited | Should -Be 1
    }

    It 'provides specific guidance for each measured category' {
        $guide = @(Get-ToolkitStorageGuidance)
        $guide.Count | Should -Be 20
        @($guide.Key | Select-Object -Unique).Count | Should -Be 20
        foreach ($entry in $guide) {
            $entry.Steps.Count | Should -BeGreaterOrEqual 4
        }
    }
}
Describe 'Storage distribution' {
    It 'installs the storage module and guide together with the V3 payload' {
        $root = Split-Path -Parent $PSScriptRoot
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'install-v3.ps1'), [ref]$tokens, [ref]$errors)
        foreach ($name in @('Write-V3TextFile', 'Test-V3CmdHasNoBom', 'Install-V3IntoPath')) {
            $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $arguments = @{
            RootPath = (Join-Path $TestDrive 'installed')
            MainText = 'payload'; ValidatorText = 'payload'; ReadmeText = 'payload'
            VersionText = 'payload'; ManifestText = 'payload'; DiagnosticsModuleText = 'payload'
            HealthModuleText = 'payload'; InventoryModuleText = 'payload'; NetworkModuleText = 'payload'
            PrintersModuleText = 'payload'; OfficeModuleText = 'payload'
            StorageModuleText = (Get-Content (Join-Path $root 'src\ServiceDeskToolkit.Storage\ServiceDeskToolkit.Storage.psm1') -Raw)
            StorageGuideText = (Get-Content (Join-Path $root 'docs\V3-ESPACO-EM-DISCO.md') -Raw)
            HomologationToolText = 'payload'; HomologationGuideText = 'payload'; CmdText = '@echo off'
        }
        $result = Install-V3IntoPath @arguments
        $module = Join-Path $result.InstallPath 'src\ServiceDeskToolkit.Storage\ServiceDeskToolkit.Storage.psm1'
        $guide = Join-Path $result.InstallPath 'docs\V3-ESPACO-EM-DISCO.md'
        Test-Path $module | Should -BeTrue
        Test-Path $guide | Should -BeTrue
        (Get-Content $module -Raw) | Should -BeLike '*function Get-ToolkitStorageSnapshot*'
        (Get-Content $guide -Raw) | Should -BeLike '*CCMCache*'
    }
}
