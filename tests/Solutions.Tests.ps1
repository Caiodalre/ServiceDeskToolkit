BeforeAll {
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $source = [IO.File]::ReadAllText((Join-Path $repositoryRoot 'ServiceDeskToolkit-CorporateV3.ps1'))
    $source = $source.Replace('$script:RootPath = Split-Path -Parent $MyInvocation.MyCommand.Path', '$script:RootPath = "' + $repositoryRoot.Replace('\', '/') + '"').Replace('[void]$window.ShowDialog()', '')
    . ([scriptblock]::Create($source))
    $productionWorkerText = Get-V3SolutionWorkerText
}

Describe 'Guided solution catalogue and operation routing' {
    BeforeEach {
        Mock Invoke-V3SafeFlushDns { 'DNS simulado' }
        Mock Invoke-V3SafeSpoolerRestart { 'Spooler simulado' }
        Mock Invoke-V3OfficeWamRepair { 'WAM simulado' }
        Mock Get-ToolkitDnsReport { 'Diagnostico DNS simulado' }
        Mock Invoke-V3PrintersPanel { 'Diagnostico impressao simulado' }
        Mock Invoke-V3OfficeTpmPanel { 'Diagnostico Office simulado' }
        Mock Test-V3Admin { $false }
        Mock Test-V3SolutionPrerequisites { }
    }

    It 'contains three reviewed solutions with conditions impact command and validation' {
        $catalog = @(Get-V3SolutionCatalog)
        $catalog.Count | Should -Be 3
        @($catalog.Id | Select-Object -Unique).Count | Should -Be 3
        foreach ($entry in $catalog) {
            $entry.Situation | Should -Not -BeNullOrEmpty
            $entry.Preconditions | Should -Not -BeNullOrEmpty
            $entry.Impact | Should -Not -BeNullOrEmpty
            $entry.Command | Should -Not -BeNullOrEmpty
            $entry.Validate | Should -Not -BeNullOrEmpty
        }
    }

    It 'rejects unknown identifiers and repair without confirmation' {
        { Invoke-V3SolutionOperation -Id 'comando-livre' -Stage Diagnose } | Should -Throw
        foreach ($id in @('dns-cache', 'print-spooler', 'office-wam')) {
            { Invoke-V3SolutionOperation -Id $id -Stage Repair } | Should -Throw '*confirmacao*'
        }
        Should -Invoke Invoke-V3SafeFlushDns -Times 0
        Should -Invoke Invoke-V3SafeSpoolerRestart -Times 0
        Should -Invoke Invoke-V3OfficeWamRepair -Times 0
    }

    It 'routes diagnosis and validation to read only functions' {
        foreach ($stage in @('Diagnose', 'Validate')) {
            Invoke-V3SolutionOperation 'dns-cache' $stage | Should -Be 'Diagnostico DNS simulado'
            Invoke-V3SolutionOperation 'print-spooler' $stage | Should -Be 'Diagnostico impressao simulado'
            Invoke-V3SolutionOperation 'office-wam' $stage | Should -Be 'Diagnostico Office simulado'
        }
        Should -Invoke Invoke-V3SafeFlushDns -Times 0
        Should -Invoke Invoke-V3SafeSpoolerRestart -Times 0
        Should -Invoke Invoke-V3OfficeWamRepair -Times 0
    }

    It 'requires admin for spooler and routes confirmed corrections only to the selected function' {
        { Invoke-V3SolutionOperation 'print-spooler' Repair -Confirmed } | Should -Throw '*administrador*'
        Should -Invoke Invoke-V3SafeSpoolerRestart -Times 0
        Mock Test-V3Admin { $true }
        Invoke-V3SolutionOperation 'dns-cache' Repair -Confirmed | Should -Be 'DNS simulado'
        Invoke-V3SolutionOperation 'print-spooler' Repair -Confirmed | Should -Be 'Spooler simulado'
        Invoke-V3SolutionOperation 'office-wam' Repair -Confirmed | Should -Be 'WAM simulado'
        Should -Invoke Invoke-V3SafeFlushDns -Times 1
        Should -Invoke Invoke-V3SafeSpoolerRestart -Times 1
        Should -Invoke Invoke-V3OfficeWamRepair -Times 1
    }

    It 'builds valid worker code from the approved functions without executing catalogue strings' {
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseInput($productionWorkerText, [ref]$tokens, [ref]$errors)
        $errors.Count | Should -Be 0
        $productionWorkerText | Should -BeLike '*Invoke-V3SolutionOperation -Id $id*'
        $productionWorkerText | Should -Not -BeLike '*Invoke-Expression*'
        $productionWorkerText | Should -Not -BeLike '*ConsentPromptBehaviorAdmin*'
    }

    It 'adjusts Appgate timeout with a preserved backup and no registry policy mutation' {
        Mock Test-V3Admin { $true }
        $configPath = Join-Path $TestDrive 'appgate.config'
        $backupPath = Join-Path $TestDrive 'backup-appgate'
        $xmlText = '<configuration><applicationSettings><Cryptzone.Stratus.WindowsClient.Properties.Application><setting name="RunScriptTimeout"><value>30000</value></setting></Cryptzone.Stratus.WindowsClient.Properties.Application></applicationSettings></configuration>'
        [IO.File]::WriteAllText($configPath, $xmlText)
        Repair-V3AppgateConfiguration -Confirmed -ConfigPath $configPath -BackupDirectory $backupPath | Should -BeLike '*30000 -> 300000*'
        [xml]$changed = [IO.File]::ReadAllText($configPath)
        $changed.SelectSingleNode('//setting/value').InnerText | Should -Be '300000'
        $backup = @(Get-ChildItem $backupPath -File)
        $backup.Count | Should -Be 1
        [IO.File]::ReadAllText($backup[0].FullName) | Should -Be $xmlText
        $definition = (Get-Command Repair-V3AppgateConfiguration).Definition
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($definition, [ref]$tokens, [ref]$errors)
        @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in @('Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty') }, $true)).Count | Should -Be 0
    }
}

Describe 'Guided solution prerequisites before any mutation' {
    BeforeEach {
        Mock Test-V3Admin { $true }
        Mock Get-Service { [pscustomobject]@{ StartType = 'Automatic' } }
        Mock Get-Process { @() }
        Mock Test-Path { $true }
        Mock Invoke-V3SafeSpoolerRestart { 'Spooler simulado' }
        Mock Invoke-V3OfficeWamRepair { 'WAM simulado' }
    }
    It 'blocks a disabled spooler before a correction and explains the policy prerequisite' {
        Mock Get-Service { [pscustomobject]@{ StartType = 'Disabled' } }
        $result = Invoke-V3SolutionOperation 'print-spooler' Repair -Confirmed
        $result.Status | Should -Be 'Blocked'
        $result.Report | Should -BeLike '*politica*'
        Should -Invoke Invoke-V3SafeSpoolerRestart -Times 0
    }
    It 'blocks DNS correction when ipconfig is unavailable' {
        Mock Get-Command { $null } -ParameterFilter { $Name -eq 'ipconfig.exe' }
        Mock Invoke-V3SafeFlushDns { 'DNS simulado' }
        $result = Invoke-V3SolutionOperation 'dns-cache' Repair -Confirmed
        $result.Status | Should -Be 'Blocked'
        $result.Report | Should -BeLike '*ipconfig indisponivel*'
        Should -Invoke Invoke-V3SafeFlushDns -Times 0
    }
    It 'blocks WAM while an Office application is open and does not close it' {
        Mock Get-Process { [pscustomobject]@{ ProcessName = 'OUTLOOK' } }
        $result = Invoke-V3SolutionOperation 'office-wam' Repair -Confirmed
        $result.Status | Should -Be 'Blocked'
        $result.Report | Should -BeLike '*OUTLOOK*'
        Should -Invoke Invoke-V3OfficeWamRepair -Times 0
    }
    It 'blocks WAM when the official manifests are unavailable' {
        Mock Test-Path { $false }
        $result = Invoke-V3SolutionOperation 'office-wam' Repair -Confirmed
        $result.Status | Should -Be 'Blocked'
        $result.Report | Should -BeLike '*Manifesto oficial WAM ausente*'
        Should -Invoke Invoke-V3OfficeWamRepair -Times 0
    }
    It 'allows WAM only when applications are closed and official manifests exist' {
        Invoke-V3SolutionOperation 'office-wam' Repair -Confirmed | Should -Be 'WAM simulado'
        Should -Invoke Invoke-V3OfficeWamRepair -Times 1
    }
}

Describe 'Guided solution session and background execution' {
    BeforeEach {
        $script:RootPath = $TestDrive
        $session = New-V3SolutionSession
        $session.Dialog.FindName('SolutionChoice').SelectedIndex = 0
        Set-V3SolutionSelection $session
        Mock Confirm-V3SolutionRepair { $false }
        Mock Test-V3Admin { $false }
        Mock Get-V3SolutionWorkerText { 'param($rootPath, $id, $stage, $confirmed); "SIMULADO: $id / $stage"' }
        function Wait-TestSolution {
            $deadline = (Get-Date).AddSeconds(15)
            while ($null -ne $session.Job -and (Get-Date) -lt $deadline) { Complete-V3SolutionStage $session; Start-Sleep -Milliseconds 20 }
            if ($null -ne $session.Job) { throw 'Worker de teste nao encerrou.' }
        }
    }
    AfterEach {
        $session.Timer.Stop()
        if ($null -ne $session.Job) { $session.Job.Pipeline.Stop(); $session.Job.Pipeline.Dispose() }
    }

    It 'does not start repair before diagnosis or without confirmation' {
        Start-V3SolutionStage $session Repair
        $session.Job | Should -BeNullOrEmpty
        Should -Invoke Confirm-V3SolutionRepair -Times 0
        $session.Diagnosed = $true
        Start-V3SolutionStage $session Repair
        $session.Job | Should -BeNullOrEmpty
        $session.History.ToString() | Should -BeLike '*Correcao cancelada*'
        Should -Invoke Get-V3SolutionWorkerText -Times 0
    }

    It 'runs the three stages asynchronously and records the history without claiming resolution' {
        Start-V3SolutionStage $session Diagnose
        $session.Dialog.FindName('SolutionChoice').IsEnabled | Should -BeFalse
        Start-V3SolutionStage $session Diagnose
        Should -Invoke Get-V3SolutionWorkerText -Times 1
        Wait-TestSolution
        $session.Diagnosed | Should -BeTrue
        $session.Dialog.FindName('SolutionRepair').IsEnabled | Should -BeTrue
        Mock Confirm-V3SolutionRepair { $true }
        Start-V3SolutionStage $session Repair
        Wait-TestSolution
        $session.RepairAttempted | Should -BeTrue
        $session.Dialog.FindName('SolutionRepair').IsEnabled | Should -BeFalse
        $session.Dialog.FindName('SolutionValidate').IsEnabled | Should -BeTrue
        Start-V3SolutionStage $session Validate
        Wait-TestSolution
        $session.EntryCount | Should -Be 3
        $session.History.ToString() | Should -BeLike '*VALIDACAO DO CHAMADO*'
        $session.Dialog.FindName('SolutionStatus').Text | Should -BeLike '*nao significa problema resolvido*'
        $script:TxtV3Output.Text | Should -BeLike '*SIMULADO: dns-cache / Repair*'
        $entries = @(Get-Content (Join-Path $TestDrive 'logs/solutions/solutions-audit.jsonl') | ConvertFrom-Json)
        @($entries | Where-Object { $_.Solution -eq 'dns-cache' -and $_.Stage -eq 'Repair' -and $_.Confirmed -and $_.Status -eq 'Started' }).Count | Should -Be 1
    }

    It 'blocks privileged correction before confirmation when admin is unavailable' {
        $session.Dialog.FindName('SolutionChoice').SelectedIndex = 1
        Set-V3SolutionSelection $session
        $session.Diagnosed = $true
        Start-V3SolutionStage $session Repair
        $session.Job | Should -BeNullOrEmpty
        $session.Dialog.FindName('SolutionStatus').Text | Should -BeLike '*exige administrador*'
        Should -Invoke Confirm-V3SolutionRepair -Times 0
    }

    It 'resets the correction gates when the selected problem changes' {
        $session.Diagnosed = $true
        $session.RepairAttempted = $true
        $session.Dialog.FindName('SolutionChoice').SelectedIndex = 2
        Set-V3SolutionSelection $session
        $session.Diagnosed | Should -BeFalse
        $session.RepairAttempted | Should -BeFalse
        $session.Id | Should -Be 'office-wam'
        $session.Dialog.FindName('SolutionRepair').IsEnabled | Should -BeFalse
        $session.Dialog.FindName('SolutionPlan').Text | Should -BeLike '*Nao limpa TPM*'
    }

    It 'keeps correction blocked after a failed diagnosis and recovers the controls' {
        Mock Get-V3SolutionWorkerText { "param(`$rootPath, `$id, `$stage, `$confirmed); throw 'falha simulada'" }
        Start-V3SolutionStage $session Diagnose
        Wait-TestSolution
        $session.Diagnosed | Should -BeFalse
        $session.Dialog.FindName('SolutionRepair').IsEnabled | Should -BeFalse
        $session.Dialog.FindName('SolutionDiagnose').IsEnabled | Should -BeTrue
        $session.History.ToString() | Should -BeLike '*Falha na etapa*'
    }

    It 'records a blocked preflight without marking a repair attempted' {
        $session.Diagnosed = $true
        Mock Confirm-V3SolutionRepair { $true }
        Mock Get-V3SolutionWorkerText { 'param($rootPath, $id, $stage, $confirmed); [pscustomobject]@{ Status="Blocked"; Report="Feche o Office" }' }
        Start-V3SolutionStage $session Repair
        Wait-TestSolution
        $session.Diagnosed | Should -BeFalse
        $session.RepairAttempted | Should -BeFalse
        $session.Validated | Should -BeFalse
        $session.Dialog.FindName('SolutionRepair').IsEnabled | Should -BeFalse
        $session.History.ToString() | Should -BeLike '*Feche o Office*'
        $entries = @(Get-Content (Join-Path $TestDrive 'logs/solutions/solutions-audit.jsonl') | ConvertFrom-Json)
        @($entries | Where-Object Status -eq 'Blocked').Count | Should -Be 1
    }

    It 'requires validation before recording the operator outcome and clears it on a new diagnosis' {
        $session.Dialog.FindName('SolutionOutcome').SelectedIndex = 1
        Save-V3SolutionOutcome $session
        $session.EntryCount | Should -Be 0
        $session.Validated = $true
        Update-V3SolutionControls $session
        $session.Dialog.FindName('SolutionRecordOutcome').IsEnabled | Should -BeTrue
        Save-V3SolutionOutcome $session
        $session.History.ToString() | Should -BeLike '*Operador informa: sintoma original testado e resolvido*'
        $entries = @(Get-Content (Join-Path $TestDrive 'logs/solutions/solutions-audit.jsonl') | ConvertFrom-Json)
        @($entries | Where-Object { $_.Stage -eq 'Outcome' -and $_.Status -eq 'ResolvedByOperator' }).Count | Should -Be 1
        Start-V3SolutionStage $session Diagnose
        Wait-TestSolution
        $session.Validated | Should -BeFalse
        $session.Dialog.FindName('SolutionOutcome').SelectedIndex | Should -Be 0
        $session.Dialog.FindName('SolutionRecordOutcome').IsEnabled | Should -BeFalse
    }

    It 'records persistent and untested symptoms separately and preserves history when audit fails' {
        $session.Validated = $true
        $session.Dialog.FindName('SolutionOutcome').SelectedIndex = 2
        Save-V3SolutionOutcome $session
        $session.Dialog.FindName('SolutionOutcome').SelectedIndex = 3
        Save-V3SolutionOutcome $session
        $entries = @(Get-Content (Join-Path $TestDrive 'logs/solutions/solutions-audit.jsonl') | ConvertFrom-Json)
        $entries.Status | Should -Contain 'PersistsByOperator'
        $entries.Status | Should -Contain 'NotTestedByOperator'
        Mock Write-V3SolutionAudit { throw 'sem acesso' }
        Save-V3SolutionOutcome $session
        $session.EntryCount | Should -Be 2
        $session.Dialog.FindName('SolutionStatus').Text | Should -BeLike '*nao registrado*'
    }

    It 'does not execute an action if its initial audit cannot be written' {
        Mock Write-V3SolutionAudit { throw 'registro indisponivel' }
        Start-V3SolutionStage $session Diagnose
        $session.Job | Should -BeNullOrEmpty
        $session.Diagnosed | Should -BeFalse
        Should -Invoke Get-V3SolutionWorkerText -Times 0
        $session.History.ToString() | Should -BeLike '*Etapa nao iniciada*'
    }

    It 'cancels a consultation without enabling correction and records its cancellation' {
        Mock Get-V3SolutionWorkerText { 'param($rootPath, $id, $stage, $confirmed); Start-Sleep -Milliseconds 300; "Consulta simulada"' }
        Start-V3SolutionStage $session Diagnose
        Stop-V3SolutionConsultation $session
        $session.Dialog.FindName('SolutionCancel').IsEnabled | Should -BeFalse
        Wait-TestSolution
        $session.Diagnosed | Should -BeFalse
        $session.Dialog.FindName('SolutionRepair').IsEnabled | Should -BeFalse
        $session.History.ToString() | Should -BeLike '*Consulta cancelada*'
        $entries = @(Get-Content (Join-Path $TestDrive 'logs/solutions/solutions-audit.jsonl') | ConvertFrom-Json)
        @($entries | Where-Object Status -eq 'Cancelled').Count | Should -BeGreaterThan 0
    }

    It 'does not interrupt an approved correction through consultation cancellation' {
        Mock Confirm-V3SolutionRepair { $true }
        Mock Get-V3SolutionWorkerText { 'param($rootPath, $id, $stage, $confirmed); Start-Sleep -Milliseconds 100; "Correcao simulada"' }
        $session.Diagnosed = $true
        Start-V3SolutionStage $session Repair
        Stop-V3SolutionConsultation $session
        $session.Job.Cancelled | Should -BeFalse
        $session.Dialog.FindName('SolutionCancel').Visibility | Should -Be 'Collapsed'
        Wait-TestSolution
        $session.RepairAttempted | Should -BeTrue
    }

    It 'keeps the history readable in a short solution window' {
        $surface = $session.Dialog.Content
        $surface.Width = 720
        $surface.Height = 450
        $surface.Measure([Windows.Size]::new(720, 450))
        $surface.Arrange([Windows.Rect]::new(0, 0, 720, 450))
        $surface.UpdateLayout()
        Update-V3SolutionLayout $session
        $surface.UpdateLayout()
        $session.Dialog.FindName('SolutionOutput').ActualHeight | Should -BeGreaterThan 100
        $session.Dialog.FindName('SolutionPlan').MaxHeight | Should -Be 110
    }
}
