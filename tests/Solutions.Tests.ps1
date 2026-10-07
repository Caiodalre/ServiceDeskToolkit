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

Describe 'Collector failure preservation with simulated Windows queries' {
    It 'marks DNS cache query errors as failed reads while preserving the other collected data' {
        Mock Get-DnsClientServerAddress { [pscustomobject]@{ InterfaceAlias='FICTICIO'; InterfaceIndex=1; ServerAddresses=@('192.0.2.1') } } -ModuleName ServiceDeskToolkit.Network
        Mock Get-DnsClientCache { throw 'cache inacessivel' } -ModuleName ServiceDeskToolkit.Network
        $result = Get-ToolkitDnsReport -PassThru
        $result.Status | Should -Be 'ReadFailed'
        $result.Report | Should -BeLike '*FICTICIO*'
        $result.Report | Should -BeLike '*cache inacessivel*'
        Mock Get-DnsClientCache { @() } -ModuleName ServiceDeskToolkit.Network
        (Get-ToolkitDnsReport -PassThru).Status | Should -Be 'ReadSucceeded'
    }
    It 'marks DNS configuration query errors as failed reads and keeps text reports compatible' {
        Mock Get-DnsClientServerAddress { throw 'configuracao inacessivel' } -ModuleName ServiceDeskToolkit.Network
        Mock Get-DnsClientCache { @() } -ModuleName ServiceDeskToolkit.Network
        (Get-ToolkitDnsReport -PassThru).Status | Should -Be 'ReadFailed'
        Get-ToolkitDnsReport | Should -BeOfType ([string])
    }
    It 'preserves printing query errors and avoids recommending repair from incomplete data' {
        Mock Get-Service { [pscustomobject]@{ Status='Running' } } -ModuleName ServiceDeskToolkit.Printers
        Mock Get-CimInstance { if ($ClassName -eq 'Win32_PrintJob') { throw 'fila inacessivel' }; @() } -ModuleName ServiceDeskToolkit.Printers
        Mock Get-Command { $null } -ModuleName ServiceDeskToolkit.Printers -ParameterFilter { $Name -eq 'Get-PrinterPort' }
        $snapshot = Get-ToolkitPrinterSnapshot
        $snapshot.CollectionErrors.Count | Should -Be 1
        $snapshot.CollectionErrors[0] | Should -BeLike '*fila inacessivel*'
        $assessment = Get-ToolkitPrinterAssessment $snapshot
        $assessment.NextAction | Should -BeLike '*repita o diagnostico*'
        $assessment.Observations[0] | Should -BeLike '*nao comprova ausencia*'
        Mock Get-CimInstance { @() } -ModuleName ServiceDeskToolkit.Printers
        (Get-ToolkitPrinterSnapshot).CollectionErrors.Count | Should -Be 0
    }
}

Describe 'Consultation results with simulated collectors' {
    BeforeEach {
        $script:V3OperationalModulesAvailable = $true
        Mock Get-ToolkitPrinterSnapshot { [pscustomobject]@{ CollectionErrors = @() } }
        Mock Get-ToolkitPrinterAssessment { [pscustomobject]@{} }
        Mock Format-ToolkitPrinterReport { 'IMPRESSAO FICTICIA' }
        Mock Get-ToolkitOfficeTpmSnapshot { [pscustomobject]@{ WamPackageError = $null } }
        Mock Get-ToolkitOfficeTpmAssessment { [pscustomobject]@{} }
        Mock Format-ToolkitOfficeTpmReport { 'OFFICE FICTICIO' }
    }
    It 'returns failed reads when collectors raise exceptions rather than unlocking repair' {
        Mock Get-ToolkitPrinterSnapshot { throw 'CIM inacessivel' }
        Mock Get-ToolkitOfficeTpmSnapshot { throw 'pacotes inacessiveis' }
        (Invoke-V3PrintersPanel -PassThru).Status | Should -Be 'ReadFailed'
        (Invoke-V3OfficeTpmPanel -PassThru).Status | Should -Be 'ReadFailed'
    }
    It 'reports partial printing queries and WAM package errors as failed reads' {
        Mock Get-ToolkitPrinterSnapshot { [pscustomobject]@{ CollectionErrors = @('Fila inacessivel') } }
        Mock Get-ToolkitOfficeTpmSnapshot { [pscustomobject]@{ WamPackageError = 'Consulta Appx recusada' } }
        $printing = Invoke-V3PrintersPanel -PassThru
        $printing.Status | Should -Be 'ReadFailed'
        $printing.Report | Should -BeLike '*Fila inacessivel*'
        $office = Invoke-V3OfficeTpmPanel -PassThru
        $office.Status | Should -Be 'ReadFailed'
        $office.Report | Should -BeLike '*perfil afetado*'
    }
    It 'keeps existing text reports and returns successful reads only when collection succeeded' {
        (Invoke-V3PrintersPanel -PassThru).Status | Should -Be 'ReadSucceeded'
        (Invoke-V3OfficeTpmPanel -PassThru).Status | Should -Be 'ReadSucceeded'
        Invoke-V3PrintersPanel | Should -Be 'IMPRESSAO FICTICIA'
        Invoke-V3OfficeTpmPanel | Should -Be 'OFFICE FICTICIO'
    }
    It 'returns failed reads when operational modules are unavailable' {
        $script:V3OperationalModulesAvailable = $false
        (Invoke-V3PrintersPanel -PassThru).Status | Should -Be 'ReadFailed'
        (Invoke-V3OfficeTpmPanel -PassThru).Status | Should -Be 'ReadFailed'
        Should -Invoke Get-ToolkitPrinterSnapshot -Times 0
        Should -Invoke Get-ToolkitOfficeTpmSnapshot -Times 0
    }
}

Describe 'Correction execution results with simulated commands' {
    BeforeEach {
        Mock Invoke-V3DnsFlushCommand { [pscustomobject]@{ ExitCode = 0; Output = 'SIMULADO' } }
        Mock Resolve-DnsName { throw 'alvo indisponivel' }
        Mock Start-Sleep { }
        Mock Test-V3Admin { $true }
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock Get-CimInstance { @() }
        Mock Restart-Service { }
        Mock Start-Service { }
        Mock Repair-ToolkitOfficeWam { [pscustomobject]@{ Success = $true } }
        Mock Format-ToolkitOfficeWamRepairReport { 'WAM SIMULADO' }
        $script:V3OperationalModulesAvailable = $true
    }
    It 'reports failed DNS exit code without claiming the cache was cleared' {
        Mock Invoke-V3DnsFlushCommand { [pscustomobject]@{ ExitCode = 5; Output = 'recusado' } }
        $result = Invoke-V3SafeFlushDns -PassThru
        $result.Status | Should -Be 'Failed'
        $result.Report | Should -BeLike '*Codigo de saida do ipconfig: 5*'
        $result.Report | Should -BeLike '*nao confirmou a limpeza*'
        Should -Invoke Resolve-DnsName -Times 1
    }
    It 'distinguishes DNS command success from an unresolved target and preserves plain reports' {
        $result = Invoke-V3SafeFlushDns -PassThru
        $result.Status | Should -Be 'Applied'
        $result.Report | Should -BeLike '*resolucao continua falhando*'
        Invoke-V3SafeFlushDns | Should -BeOfType ([string])
    }
    It 'does not report spooler restart success when the command fails but service is running' {
        Mock Restart-Service { throw 'acesso negado' }
        $result = Invoke-V3SafeSpoolerRestart -PassThru
        $result.Status | Should -Be 'Failed'
        $result.Report | Should -BeLike '*estado atual do servico nao comprova*'
        $result.Report | Should -Not -BeLike '*Spooler esta em execucao apos a correcao*'
    }
    It 'reports applied spooler correction only after command completion and running state' {
        $result = Invoke-V3SafeSpoolerRestart -PassThru
        $result.Status | Should -Be 'Applied'
        Should -Invoke Restart-Service -Times 1
        Should -Invoke Start-Service -Times 0
    }
    It 'reports an unsuccessful start when the spooler remains stopped' {
        Mock Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        (Invoke-V3SafeSpoolerRestart -PassThru).Status | Should -Be 'Failed'
        Should -Invoke Start-Service -Times 1
    }
    It 'reports blocked spooler action when administrator permission is lost' {
        Mock Test-V3Admin { $false }
        (Invoke-V3SafeSpoolerRestart -PassThru).Status | Should -Be 'Blocked'
        Should -Invoke Restart-Service -Times 0
        Should -Invoke Start-Service -Times 0
    }
    It 'uses the WAM module success flag rather than inferring success from report text' {
        (Invoke-V3OfficeWamRepair -PassThru).Status | Should -Be 'Applied'
        Mock Repair-ToolkitOfficeWam { [pscustomobject]@{ Success = $false } }
        (Invoke-V3OfficeWamRepair -PassThru).Status | Should -Be 'Failed'
    }
    It 'preserves WAM partial failure guidance when registration raises an exception' {
        Mock Repair-ToolkitOfficeWam { throw 'segundo manifesto falhou' }
        $result = Invoke-V3OfficeWamRepair -PassThru
        $result.Status | Should -Be 'Failed'
        $result.Report | Should -BeLike '*parcialmente aplicado*'
        $result.Report | Should -Not -BeLike '*NAO EXECUTADO*'
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

    It 'keeps correction blocked when a collector returns a partial report without throwing' {
        Mock Get-V3SolutionWorkerText { 'param($rootPath,$id,$stage,$confirmed); [pscustomobject]@{Status="ReadFailed"; Report="CIM inacessivel"}' }
        Start-V3SolutionStage $session Diagnose
        Wait-TestSolution
        $session.Diagnosed | Should -BeFalse
        $session.Dialog.FindName('SolutionRepair').IsEnabled | Should -BeFalse
        $session.History.ToString() | Should -BeLike '*CIM inacessivel*'
        $session.Dialog.FindName('SolutionStatus').Text | Should -BeLike '*Consulta incompleta*'
    }

    It 'does not enable outcome registration after an incomplete validation' {
        $session.RepairAttempted = $true
        $session.Validated = $true
        Mock Get-V3SolutionWorkerText { 'param($rootPath,$id,$stage,$confirmed); [pscustomobject]@{Status="ReadFailed"; Report="WAM inacessivel"}' }
        Start-V3SolutionStage $session Validate
        Wait-TestSolution
        $session.RepairAttempted | Should -BeTrue
        $session.Validated | Should -BeFalse
        $session.Dialog.FindName('SolutionRecordOutcome').IsEnabled | Should -BeFalse
        $session.Dialog.FindName('SolutionValidate').IsEnabled | Should -BeTrue
    }

    It 'accepts a structured successful consultation without inferring symptom resolution' {
        Mock Get-V3SolutionWorkerText { 'param($rootPath,$id,$stage,$confirmed); [pscustomobject]@{Status="ReadSucceeded"; Report="LEITURA FICTICIA"}' }
        Start-V3SolutionStage $session Diagnose
        Wait-TestSolution
        $session.Diagnosed | Should -BeTrue
        $session.Validated | Should -BeFalse
        $session.History.ToString() | Should -BeLike '*LEITURA FICTICIA*'
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

    It 'records a failed correction as Failed and permits validation without blind repetition' {
        $session.Diagnosed = $true
        Mock Confirm-V3SolutionRepair { $true }
        Mock Get-V3SolutionWorkerText { 'param($rootPath, $id, $stage, $confirmed); [pscustomobject]@{Status="Failed"; Report="Comando falhou"}' }
        Start-V3SolutionStage $session Repair
        Wait-TestSolution
        $session.RepairAttempted | Should -BeTrue
        $session.Dialog.FindName('SolutionRepair').IsEnabled | Should -BeFalse
        $session.Dialog.FindName('SolutionValidate').IsEnabled | Should -BeTrue
        $session.Dialog.FindName('SolutionStatus').Text | Should -BeLike '*alteracoes parciais*'
        $session.History.ToString() | Should -BeLike '*Comando falhou*'
        $entries = @(Get-Content (Join-Path $TestDrive 'logs/solutions/solutions-audit.jsonl') | ConvertFrom-Json)
        $entries.Status | Should -Contain 'Failed'
    }

    It 'records applied commands without marking the operator symptom resolved' {
        $session.Diagnosed = $true
        Mock Confirm-V3SolutionRepair { $true }
        Mock Get-V3SolutionWorkerText { 'param($rootPath, $id, $stage, $confirmed); [pscustomobject]@{Status="Applied"; Report="Comando aplicado"}' }
        Start-V3SolutionStage $session Repair
        Wait-TestSolution
        $session.Validated | Should -BeFalse
        $session.Dialog.FindName('SolutionRecordOutcome').IsEnabled | Should -BeFalse
        $session.Dialog.FindName('SolutionStatus').Text | Should -BeLike '*teste o sintoma original*'
        $session.History.ToString() | Should -BeLike '*Comando aplicado*'
        $entries = @(Get-Content (Join-Path $TestDrive 'logs/solutions/solutions-audit.jsonl') | ConvertFrom-Json)
        $entries.Status | Should -Contain 'Applied'
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

    It 'restores history on reopening without restoring authorization to repair or record resolution' {
        Add-V3SolutionHistory $session Diagnose 'EVIDENCIA FICTICIA'
        $session.Diagnosed = $true
        $session.RepairAttempted = $true
        $session.Validated = $true
        $checkpoint = Get-V3SolutionCheckpoint $session
        $restored = New-V3SolutionSession -Checkpoint $checkpoint
        $restored.Dialog.FindName('SolutionChoice').SelectedIndex = 0
        Set-V3SolutionSelection $restored
        $restored.History.ToString() | Should -Be $session.History.ToString()
        $restored.EntryCount | Should -Be 1
        $restored.Diagnosed | Should -BeFalse
        $restored.RepairAttempted | Should -BeFalse
        $restored.Validated | Should -BeFalse
        $restored.Dialog.FindName('SolutionRepair').IsEnabled | Should -BeFalse
        $restored.Dialog.FindName('SolutionRecordOutcome').IsEnabled | Should -BeFalse
        $restored.Dialog.FindName('SolutionSave').IsEnabled | Should -BeTrue
        $restored.Dialog.FindName('SolutionOutput').Text | Should -BeLike '*EVIDENCIA FICTICIA*'
        $restored.Dialog.FindName('SolutionOutput').Text | Should -BeLike '*apenas enquanto o programa estiver aberto*'
        Add-V3SolutionHistory $restored Diagnose 'SEGUNDA LEITURA FICTICIA'
        $restored.EntryCount | Should -Be 2
        $restored.History.ToString() | Should -BeLike '*[[]2[]]*'
        $checkpoint.History | Should -Not -BeLike '*SEGUNDA LEITURA*'
        $restored.Timer.Stop()
    }

    It 'keeps checkpoints free of window and execution objects and rejects capture during a running stage' {
        $session.Dialog.FindName('SolutionChoice').SelectedIndex = 1
        Set-V3SolutionSelection $session
        $checkpoint = Get-V3SolutionCheckpoint $session
        $checkpoint.Id | Should -Be 'print-spooler'
        $checkpoint.EntryCount | Should -Be 0
        @($checkpoint.PSObject.Properties.Name).Count | Should -Be 3
        Start-V3SolutionStage $session Diagnose
        { Get-V3SolutionCheckpoint $session } | Should -Throw '*Aguarde*'
        Wait-TestSolution
    }

    It 'uses readable Portuguese titles and stage names in the exported history' {
        Add-V3SolutionHistory $session Diagnose 'LEITURA FICTICIA'
        Add-V3SolutionHistory $session Repair 'CORRECAO FICTICIA'
        Add-V3SolutionHistory $session Validate 'VALIDACAO FICTICIA'
        $history = $session.History.ToString()
        $history | Should -BeLike '*Site ou sistema com falha de DNS - Diagnostico*'
        $history | Should -BeLike '*Site ou sistema com falha de DNS - Correcao*'
        $history | Should -BeLike '*Site ou sistema com falha de DNS - Validacao*'
        $history | Should -Not -BeLike '*dns-cache - Diagnose*'
    }

    It 'exports only a completed nonempty history' {
        Mock Set-V3ClipboardText { }
        Mock Get-V3ReportSavePath { $null }
        Export-V3SolutionHistory $session Copy
        Export-V3SolutionHistory $session Save
        Should -Invoke Set-V3ClipboardText -Times 0
        Should -Invoke Get-V3ReportSavePath -Times 0
        $session.Dialog.FindName('SolutionCopy').IsEnabled | Should -BeFalse
        Add-V3SolutionHistory $session Diagnose 'DADOS FICTICIOS'
        $session.Dialog.FindName('SolutionSave').IsEnabled | Should -BeTrue
        Start-V3SolutionStage $session Diagnose
        $session.Dialog.FindName('SolutionCopy').IsEnabled | Should -BeFalse
        Export-V3SolutionHistory $session Copy
        Export-V3SolutionHistory $session Save
        Should -Invoke Set-V3ClipboardText -Times 0
        Should -Invoke Get-V3ReportSavePath -Times 0
        Wait-TestSolution
        $session.Dialog.FindName('SolutionCopy').IsEnabled | Should -BeTrue
    }

    It 'copies the complete history without modifying its content or adding feedback to it' {
        Add-V3SolutionHistory $session Diagnose 'Relatorio ficticio com acentuação'
        $original = $session.Dialog.FindName('SolutionOutput').Text
        Mock Set-V3ClipboardText { }
        Export-V3SolutionHistory $session Copy
        Should -Invoke Set-V3ClipboardText -Times 1 -ParameterFilter { $Text -eq $original }
        $session.Dialog.FindName('SolutionOutput').Text | Should -Be $original
        $session.Dialog.FindName('SolutionStatus').Text | Should -BeLike '*Historico copiado*'
        Mock Set-V3ClipboardText { throw 'ocupado' }
        Export-V3SolutionHistory $session Copy
        $session.Dialog.FindName('SolutionOutput').Text | Should -Be $original
        $session.Dialog.FindName('SolutionStatus').Text | Should -BeLike '*Copia indisponivel*'
    }

    It 'saves a faithful UTF8 history using the catalogue window as owner' {
        Add-V3SolutionHistory $session Diagnose 'Relatorio ficticio com acentuação'
        $original = $session.Dialog.FindName('SolutionOutput').Text
        $savePath = Join-Path $TestDrive 'solution-history.txt'
        Mock Get-V3ReportSavePath { $savePath }
        Export-V3SolutionHistory $session Save
        Should -Invoke Get-V3ReportSavePath -Times 1 -ParameterFilter { $Owner -eq $session.Dialog }
        [IO.File]::ReadAllText($savePath) | Should -Be $original
        [BitConverter]::ToString([IO.File]::ReadAllBytes($savePath)[0..2]) | Should -Be 'EF-BB-BF'
        $session.Dialog.FindName('SolutionOutput').Text | Should -Be $original
    }

    It 'preserves history and feedback on cancelled saving and reports inaccessible destinations' {
        Add-V3SolutionHistory $session Diagnose 'DADOS FICTICIOS'
        $original = $session.Dialog.FindName('SolutionOutput').Text
        $status = $session.Dialog.FindName('SolutionStatus').Text
        Mock Get-V3ReportSavePath { $null }
        Export-V3SolutionHistory $session Save
        $session.Dialog.FindName('SolutionStatus').Text | Should -Be $status
        Mock Get-V3ReportSavePath { $TestDrive }
        Export-V3SolutionHistory $session Save
        $session.Dialog.FindName('SolutionStatus').Text | Should -BeLike '*Nao foi possivel salvar*'
        $session.Dialog.FindName('SolutionOutput').Text | Should -Be $original
    }

    It 'saves the captured history even if the content changes while choosing the destination' {
        Add-V3SolutionHistory $session Diagnose 'DADOS FICTICIOS INICIAIS'
        $original = $session.Dialog.FindName('SolutionOutput').Text
        $savePath = Join-Path $TestDrive 'captured-history.txt'
        Mock Get-V3ReportSavePath { $session.Dialog.FindName('SolutionOutput').Text = 'OUTRO TEXTO'; $savePath }
        Export-V3SolutionHistory $session Save
        [IO.File]::ReadAllText($savePath) | Should -Be $original
    }
}
