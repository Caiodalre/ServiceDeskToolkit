$script:RepositoryRoot = Split-Path -Parent $PSScriptRoot
$script:HealthModulePath = Join-Path `
    $script:RepositoryRoot `
    "src\ServiceDeskToolkit.Health\ServiceDeskToolkit.Health.psm1"

Import-Module -Name $script:HealthModulePath -Force

function Assert-HealthCondition {
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

function New-HealthySnapshot {
    param(
        [double]$TotalRamGb = 16,
        [double]$MemoryUsedPercent = 50,
        [double]$DiskFreeGb = 100,
        [double]$DiskFreePercent = 50,
        [double]$UptimeTotalDays = 2,
        [string[]]$IPv4Addresses = @("10.0.0.10"),
        [string[]]$Gateways = @("10.0.0.1"),
        [bool]$PendingReboot = $false
    )

    return [pscustomobject]@{
        CollectedAt = [datetime]"2026-07-27T10:00:00"
        ComputerName = "TEST-PC"
        UserName = "CONTOSO\tecnico"
        IsAdmin = $false
        SystemAvailable = $true
        SystemCaption = "Microsoft Windows 11 Enterprise"
        SystemBuildNumber = "26100"
        SystemArchitecture = "64-bit"
        TotalRamGb = $TotalRamGb
        MemoryUsedPercent = $MemoryUsedPercent
        DiskAvailable = $true
        SystemDrive = "C:"
        DiskSizeGb = 256
        DiskFreeGb = $DiskFreeGb
        DiskFreePercent = $DiskFreePercent
        UptimeAvailable = $true
        UptimeTotalDays = $UptimeTotalDays
        UptimeDays = [Math]::Floor($UptimeTotalDays)
        UptimeHours = 0
        NetworkAdapterAvailable = $true
        NetworkDescription = "Ethernet"
        IPv4Addresses = @($IPv4Addresses)
        Gateways = @($Gateways)
        DnsResolved = $true
        TimeServiceFound = $true
        TimeServiceStatus = "Running"
        TimeSource = "dc01.contoso.local"
        SpoolerFound = $true
        SpoolerStatus = "Running"
        PendingReboot = $PendingReboot
        RebootReasons = if ($PendingReboot) {
            @("Windows Update")
        }
        else {
            @()
        }
    }
}

function Get-Indicator {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Assessment,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return @($Assessment.Indicators | Where-Object Name -eq $Name)[0]
}

Describe "Machine health assessment" {
    It "classifies a healthy snapshot with score 100" {
        $assessment = Get-ToolkitMachineHealthAssessment `
            -Snapshot (New-HealthySnapshot)

        Assert-HealthCondition `
            -Condition ($assessment.Score -eq 100) `
            -Message "A pontuacao saudavel deveria ser 100."
        Assert-HealthCondition `
            -Condition ($assessment.Classification -eq "SAUDAVEL") `
            -Message "A classificacao saudavel nao foi retornada."
        Assert-HealthCondition `
            -Condition (@($assessment.Issues).Count -eq 0) `
            -Message "O cenario saudavel nao deveria gerar alertas."
    }

    It "keeps memory healthy below 80 percent" {
        $assessment = Get-ToolkitMachineHealthAssessment `
            -Snapshot (New-HealthySnapshot -MemoryUsedPercent 79.9)
        $memory = Get-Indicator -Assessment $assessment -Name "Memory"

        Assert-HealthCondition `
            -Condition ($memory.Status -eq "OK") `
            -Message "Memoria abaixo de 80% deveria permanecer OK."
    }

    It "marks memory attention at 80 percent" {
        $assessment = Get-ToolkitMachineHealthAssessment `
            -Snapshot (New-HealthySnapshot -MemoryUsedPercent 80)
        $memory = Get-Indicator -Assessment $assessment -Name "Memory"

        Assert-HealthCondition `
            -Condition ($memory.Status -eq "ATENCAO") `
            -Message "Memoria em 80% deveria gerar atencao."
        Assert-HealthCondition `
            -Condition ($assessment.Score -eq 90) `
            -Message "Memoria em atencao deveria descontar 10 pontos."
    }

    It "marks memory critical at 90 percent" {
        $assessment = Get-ToolkitMachineHealthAssessment `
            -Snapshot (New-HealthySnapshot -MemoryUsedPercent 90)
        $memory = Get-Indicator -Assessment $assessment -Name "Memory"

        Assert-HealthCondition `
            -Condition ($memory.Status -eq "CRITICO") `
            -Message "Memoria em 90% deveria ser critica."
        Assert-HealthCondition `
            -Condition ($assessment.Score -eq 80) `
            -Message "Memoria critica deveria descontar 20 pontos."
    }

    It "keeps disk healthy at exact warning boundaries" {
        $assessment = Get-ToolkitMachineHealthAssessment `
            -Snapshot (
                New-HealthySnapshot `
                    -DiskFreeGb 30 `
                    -DiskFreePercent 20
            )
        $disk = Get-Indicator -Assessment $assessment -Name "Disk"

        Assert-HealthCondition `
            -Condition ($disk.Status -eq "OK") `
            -Message "Os limites exatos de 30 GB e 20% deveriam permanecer OK."
    }

    It "marks disk attention below warning boundaries" {
        $assessment = Get-ToolkitMachineHealthAssessment `
            -Snapshot (
                New-HealthySnapshot `
                    -DiskFreeGb 29.9 `
                    -DiskFreePercent 19.9
            )
        $disk = Get-Indicator -Assessment $assessment -Name "Disk"

        Assert-HealthCondition `
            -Condition ($disk.Status -eq "ATENCAO") `
            -Message "Disco abaixo do limite de atencao nao foi identificado."
        Assert-HealthCondition `
            -Condition ($assessment.Score -eq 85) `
            -Message "Disco em atencao deveria descontar 15 pontos."
    }

    It "marks disk critical below critical boundaries" {
        $assessment = Get-ToolkitMachineHealthAssessment `
            -Snapshot (
                New-HealthySnapshot `
                    -DiskFreeGb 14.9 `
                    -DiskFreePercent 9.9
            )
        $disk = Get-Indicator -Assessment $assessment -Name "Disk"

        Assert-HealthCondition `
            -Condition ($disk.Status -eq "CRITICO") `
            -Message "Disco abaixo do limite critico nao foi identificado."
        Assert-HealthCondition `
            -Condition ($assessment.Score -eq 70) `
            -Message "Disco critico deveria descontar 30 pontos."
    }

    It "marks uptime attention at seven days" {
        $assessment = Get-ToolkitMachineHealthAssessment `
            -Snapshot (New-HealthySnapshot -UptimeTotalDays 7)
        $uptime = Get-Indicator -Assessment $assessment -Name "Uptime"

        Assert-HealthCondition `
            -Condition ($uptime.Status -eq "ATENCAO") `
            -Message "Uptime de sete dias deveria gerar atencao."
        Assert-HealthCondition `
            -Condition ($assessment.Score -eq 95) `
            -Message "Uptime em atencao deveria descontar 5 pontos."
    }

    It "marks uptime critical at thirty days" {
        $assessment = Get-ToolkitMachineHealthAssessment `
            -Snapshot (New-HealthySnapshot -UptimeTotalDays 30)
        $uptime = Get-Indicator -Assessment $assessment -Name "Uptime"

        Assert-HealthCondition `
            -Condition ($uptime.Status -eq "CRITICO") `
            -Message "Uptime de trinta dias deveria ser critico."
        Assert-HealthCondition `
            -Condition ($assessment.Score -eq 90) `
            -Message "Uptime critico deveria descontar 10 pontos."
    }

    It "marks an APIPA address as critical" {
        $assessment = Get-ToolkitMachineHealthAssessment `
            -Snapshot (
                New-HealthySnapshot `
                    -IPv4Addresses @("169.254.10.20") `
                    -Gateways @()
            )
        $network = Get-Indicator -Assessment $assessment -Name "Network"

        Assert-HealthCondition `
            -Condition ($network.Status -eq "CRITICO") `
            -Message "Endereco APIPA deveria ser critico."
        Assert-HealthCondition `
            -Condition ($assessment.Score -eq 75) `
            -Message "Rede critica deveria descontar 25 pontos."
    }

    It "marks a missing gateway as attention" {
        $assessment = Get-ToolkitMachineHealthAssessment `
            -Snapshot (
                New-HealthySnapshot `
                    -IPv4Addresses @("10.0.0.10") `
                    -Gateways @()
            )
        $network = Get-Indicator -Assessment $assessment -Name "Network"

        Assert-HealthCondition `
            -Condition ($network.Status -eq "ATENCAO") `
            -Message "Gateway ausente deveria gerar atencao."
        Assert-HealthCondition `
            -Condition ($assessment.Score -eq 85) `
            -Message "Gateway ausente deveria descontar 15 pontos."
    }

    It "discounts a pending reboot" {
        $assessment = Get-ToolkitMachineHealthAssessment `
            -Snapshot (New-HealthySnapshot -PendingReboot $true)
        $reboot = Get-Indicator -Assessment $assessment -Name "PendingReboot"

        Assert-HealthCondition `
            -Condition ($reboot.Status -eq "ATENCAO") `
            -Message "Reinicio pendente deveria gerar atencao."
        Assert-HealthCondition `
            -Condition ($assessment.Score -eq 95) `
            -Message "Reinicio pendente deveria descontar 5 pontos."
    }

    It "never returns a negative score" {
        $snapshot = New-HealthySnapshot `
            -TotalRamGb 4 `
            -MemoryUsedPercent 95 `
            -DiskFreeGb 1 `
            -DiskFreePercent 1 `
            -UptimeTotalDays 45 `
            -IPv4Addresses @("169.254.1.1") `
            -Gateways @() `
            -PendingReboot $true

        $snapshot.SystemAvailable = $false
        $snapshot.DnsResolved = $false
        $snapshot.TimeServiceFound = $false
        $snapshot.TimeServiceStatus = "Stopped"
        $snapshot.SpoolerFound = $false

        $assessment = Get-ToolkitMachineHealthAssessment -Snapshot $snapshot

        Assert-HealthCondition `
            -Condition ($assessment.Score -eq 0) `
            -Message "A pontuacao minima deveria ser zero."
        Assert-HealthCondition `
            -Condition ($assessment.Classification -eq "CRITICO") `
            -Message "Pontuacao zero deveria ser critica."
    }

    It "formats the operational report contract" {
        $snapshot = New-HealthySnapshot
        $assessment = Get-ToolkitMachineHealthAssessment -Snapshot $snapshot
        $report = Format-ToolkitMachineHealthReport `
            -Snapshot $snapshot `
            -Assessment $assessment

        foreach ($marker in @(
            "PAINEL DE SAUDE DA MAQUINA",
            "Pontuacao: 100 de 100",
            "Classificacao: SAUDAVEL",
            "Memoria RAM: OK",
            "Disco do Windows: OK",
            "Tipo de acao: Diagnostico geral sem correcao"
        )) {
            Assert-HealthCondition `
                -Condition $report.Contains($marker) `
                -Message "Marcador ausente no relatorio: $marker"
        }
    }
}
