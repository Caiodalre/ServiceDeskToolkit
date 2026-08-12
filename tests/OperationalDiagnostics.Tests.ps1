BeforeAll {
$script:RepositoryRoot = Split-Path -Parent $PSScriptRoot

foreach ($moduleName in @(
    "ServiceDeskToolkit.Inventory",
    "ServiceDeskToolkit.Network",
    "ServiceDeskToolkit.Printers",
    "ServiceDeskToolkit.Office"
)) {
    $modulePath = Join-Path `
        $script:RepositoryRoot `
        "src\$moduleName\$moduleName.psm1"

    Import-Module -Name $modulePath -Force
}

function Assert-OperationalCondition {
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

function Assert-OperationalTextContains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Expected
    )

    Assert-OperationalCondition `
        -Condition $Text.Contains($Expected) `
        -Message "Texto esperado nao encontrado: $Expected"
}

function New-NetworkSnapshot {
    param(
        [bool]$HasAdapter = $true,
        [bool]$HasIp = $true,
        [bool]$HasGateway = $true,
        [bool]$GatewayResponds = $true,
        [bool]$CloudflareResponds = $true,
        [bool]$GoogleResponds = $true,
        [bool]$MicrosoftDnsResolves = $true
    )

    $adapter = [pscustomobject]@{
        Description = "Ethernet de teste"
        MACAddress = "00-11-22-33-44-55"
        DHCPEnabled = $true
        IPv4Addresses = [string[]]@("10.0.0.10")
        IPv6Addresses = [string[]]@()
        DnsServers = [string[]]@("10.0.0.2")
        Gateways = [string[]]@("10.0.0.1")
    }

    return [pscustomobject]@{
        ObservedAt = [datetime]"2026-07-27T10:00:00"
        Adapters = if ($HasAdapter) {
            [object[]]@($adapter)
        }
        else {
            [object[]]@()
        }
        PrimaryAdapter = if ($HasAdapter) { $adapter } else { $null }
        PrimaryIpv4 = if ($HasIp) {
            [string[]]@("10.0.0.10")
        }
        else {
            [string[]]@()
        }
        PrimaryGateway = if ($HasGateway) {
            "10.0.0.1"
        }
        else {
            ""
        }
        PrimaryDns = [string[]]@("10.0.0.2")
        HasAdapter = $HasAdapter
        HasIp = $HasIp
        HasGateway = $HasGateway
        HasDns = $true
        GatewayResponds = $GatewayResponds
        CloudflareResponds = $CloudflareResponds
        GoogleResponds = $GoogleResponds
        MicrosoftDnsResolves = $MicrosoftDnsResolves
        DnsError = if ($MicrosoftDnsResolves) {
            ""
        }
        else {
            "Falha DNS simulada"
        }
        RoutesCommandAvailable = $false
        Routes = [object[]]@()
        RoutesError = ""
    }
}

function New-InventorySnapshot {
    param(
        [double]$TotalRamGb = 16,
        [double]$SystemFreeGb = 100,
        [double]$SystemSizeGb = 200,
        [double]$UptimeDays = 2,
        [bool]$HasAdapter = $true
    )

    $observedAt = [datetime]"2026-07-27T10:00:00"
    $lastBoot = $observedAt.AddDays(-$UptimeDays)
    $systemDisk = [pscustomobject]@{
        DeviceID = "C:"
        Size = $SystemSizeGb * 1GB
        FreeSpace = $SystemFreeGb * 1GB
        VolumeName = "Windows"
    }
    $adapter = [pscustomobject]@{
        Description = "Ethernet de teste"
        MACAddress = "00-11-22-33-44-55"
        DHCPEnabled = $true
        IPv4Addresses = [string[]]@("10.0.0.10")
        Gateways = [string[]]@("10.0.0.1")
        DnsServers = [string[]]@("10.0.0.2")
    }

    return [pscustomobject]@{
        ObservedAt = $observedAt
        SystemDrive = "C:"
        Computer = [pscustomobject]@{
            TotalPhysicalMemory = $TotalRamGb * 1GB
            Manufacturer = "Fabricante"
            Model = "Modelo"
            PartOfDomain = $true
            Domain = "CORP"
            Workgroup = ""
        }
        OperatingSystem = [pscustomobject]@{
            Caption = "Windows de teste"
            Version = "10.0"
            BuildNumber = "99999"
            OSArchitecture = "64-bit"
            InstallDate = [datetime]"2025-01-01"
            LastBootUpTime = $lastBoot
        }
        Bios = [pscustomobject]@{
            SerialNumber = "SERIAL"
            SMBIOSBIOSVersion = "1.0"
            ReleaseDate = [datetime]"2024-01-01"
        }
        Processor = [pscustomobject]@{
            Name = "CPU de teste"
            NumberOfCores = 4
            NumberOfLogicalProcessors = 8
            MaxClockSpeed = 3000
        }
        Baseboard = [pscustomobject]@{
            Product = "Placa de teste"
            Manufacturer = "Fabricante"
        }
        MemoryModules = [object[]]@()
        Disks = [object[]]@($systemDisk)
        Adapters = if ($HasAdapter) {
            [object[]]@($adapter)
        }
        else {
            [object[]]@()
        }
        TotalRamGb = $TotalRamGb
        Uptime = New-TimeSpan -Start $lastBoot -End $observedAt
        SystemDisk = $systemDisk
    }
}

function New-PrinterSnapshot {
    param(
        [bool]$HasSpooler = $true,
        [string]$SpoolerStatus = "Running",
        [bool]$HasPrinter = $true,
        [bool]$HasDefaultPrinter = $true,
        [bool]$IsOffline = $false,
        [bool]$HasJob = $false,
        [bool]$HasErrorStatus = $false
    )

    $spooler = if ($HasSpooler) {
        [pscustomobject]@{
            Status = $SpoolerStatus
            Name = "Spooler"
            DisplayName = "Print Spooler"
        }
    }
    else {
        $null
    }
    $printer = [pscustomobject]@{
        Name = "Impressora de teste"
        Default = $HasDefaultPrinter
        Network = $false
        Local = $true
        PrinterStatus = if ($HasErrorStatus) { 7 } else { 3 }
        WorkOffline = $IsOffline
        PortName = "USB001"
        DriverName = "Driver de teste"
    }
    $printers = if ($HasPrinter) {
        [object[]]@($printer)
    }
    else {
        [object[]]@()
    }
    $jobs = if ($HasJob) {
        [object[]]@(
            [pscustomobject]@{
                Name = "Impressora, 1"
                Document = "Documento"
                Owner = "usuario"
                Status = "Printing"
                Size = 1024
                TotalPages = 1
            }
        )
    }
    else {
        [object[]]@()
    }
    $offlinePrinters = if ($HasPrinter -and $IsOffline) {
        [object[]]@($printer)
    }
    else {
        [object[]]@()
    }
    $errorPrinters = if ($HasPrinter -and $HasErrorStatus) {
        [object[]]@($printer)
    }
    else {
        [object[]]@()
    }
    $alerts = @(
        (@($offlinePrinters) + @($errorPrinters)) |
            Sort-Object Name -Unique
    )

    return [pscustomobject]@{
        ObservedAt = [datetime]"2026-07-27T10:00:00"
        Spooler = $spooler
        Printers = $printers
        Jobs = $jobs
        Drivers = [object[]]@()
        Ports = [object[]]@()
        DefaultPrinter = if (
            $HasPrinter -and
            $HasDefaultPrinter
        ) {
            $printer
        }
        else {
            $null
        }
        OfflinePrinters = $offlinePrinters
        ErrorPrinters = $errorPrinters
        NetworkPrinters = [object[]]@()
        LocalPrinters = if ($HasPrinter) {
            [object[]]@($printer)
        }
        else {
            [object[]]@()
        }
        AlertPrinters = [object[]]$alerts
    }
}

function New-OfficeTpmSnapshot {
    param(
        [bool]$TpmPresent = $true,
        [bool]$TpmReady = $true,
        [bool]$RebootPending = $false,
        [bool]$AadBrokerPackagePresent = $true,
        [bool]$CloudExperiencePackagePresent = $true,
        [int]$WamEventCount = 0,
        [string]$DeviceAuthStatus = "SUCCESS",
        [string]$AzureAdPrt = "YES",
        [string]$WamDefaultSet = "YES",
        [int]$OfficeCredentialCount = 0,
        [bool]$LicenseLooksUnlicensed = $false,
        [string]$OfficeEdition = "Microsoft 365 Apps",
        [string]$OfficeProductReleaseIds = "O365ProPlusRetail",
        [string]$VNextDiagPath = "C:\Program Files\Microsoft Office\root\Office16\vnextdiag.ps1",
        [string]$OsppPath = "",
        [bool]$OsppCheckRan = $false,
        [int]$OsppLicensedCount = 0,
        [int]$OsppUnlicensedCount = 0,
        [string[]]$OsppLicenseStatuses = @()
    )

    return [pscustomobject]@{
        ObservedAt = [datetime]"2026-08-09T10:00:00"
        TpmCommandAvailable = $true
        TpmQueryMethod = "Synthetic"
        TpmPresent = $TpmPresent
        TpmReady = $TpmReady
        TpmEnabled = $TpmPresent
        TpmActivated = $TpmPresent
        TpmOwned = $TpmPresent
        TpmAutoProvisioning = "Enabled"
        TpmSpecVersion = "2.0"
        TpmManufacturer = "TEST"
        TpmError = $null
        BitLockerAvailable = $true
        BitLockerProtectionStatus = "On"
        BitLockerVolumeStatus = "FullyEncrypted"
        BitLockerError = $null
        CbsRebootPending = $RebootPending
        WindowsUpdateRebootPending = $false
        PendingFileRenameOperations = $false
        RebootPending = $RebootPending
        OfficeInstalled = $true
        OfficeProductReleaseIds = $OfficeProductReleaseIds
        OfficePlatform = "x64"
        OfficeVersion = "16.0.99999.1"
        OfficeEdition = $OfficeEdition
        OfficeLicensingModel = if (
            $OfficeEdition -eq "Microsoft 365 Apps"
        ) {
            "Assinatura moderna (vnextdiag)"
        }
        else {
            "Perpetuo ou volume (OSPP)"
        }
        VNextDiagPath = $VNextDiagPath
        OsppPath = $OsppPath
        OsppCheckRan = $OsppCheckRan
        OsppExitCode = if ($OsppCheckRan) { 0 } else { $null }
        OsppProductCount = (
            $OsppLicensedCount +
            $OsppUnlicensedCount
        )
        OsppLicensedCount = $OsppLicensedCount
        OsppUnlicensedCount = $OsppUnlicensedCount
        OsppGraceCount = 0
        OsppLicenseStatuses = $OsppLicenseStatuses
        OsppErrorCodes = [string[]]@()
        OsppActivationType = if ($OsppCheckRan) { "KMS" } else { $null }
        OsppCheckError = $null
        OfficeProcesses = [string[]]@()
        AadBrokerPackagePresent = $AadBrokerPackagePresent
        CloudExperiencePackagePresent = $CloudExperiencePackagePresent
        AadBrokerManifestPresent = $true
        CloudExperienceManifestPresent = $true
        WamPackageError = $null
        AadTokenCachePresent = $true
        CloudTokenCachePresent = $true
        AadTokenFileCount = 1
        CloudTokenFileCount = 1
        DsRegCommandAvailable = $true
        DsRegExitCode = 0
        DsRegError = $null
        AzureAdJoined = "YES"
        EnterpriseJoined = "NO"
        DomainJoined = "YES"
        WorkplaceJoined = "NO"
        WamDefaultSet = $WamDefaultSet
        AzureAdPrt = $AzureAdPrt
        TpmProtected = "YES"
        DeviceAuthStatus = $DeviceAuthStatus
        NgcSet = "YES"
        KeySignTest = "PASSED"
        OfficeCredentialCount = $OfficeCredentialCount
        CredentialQueryError = $null
        OfficeLicenseFileCount = 1
        LicenseCheckRan = $true
        LicenseCheckExitCode = 0
        LicenseLooksLicensed = (-not $LicenseLooksUnlicensed)
        LicenseLooksUnlicensed = $LicenseLooksUnlicensed
        LicenseCheckError = $null
        ProtectionPolicy = $null
        WamEvents = [pscustomobject]@{
            Available = $true
            Count = $WamEventCount
            EventIds = [int[]]@()
            Error = $null
        }
        AadEvents = [pscustomobject]@{
            Available = $true
            Count = 0
            EventIds = [int[]]@()
            Error = $null
        }
        TpmEvents = [pscustomobject]@{
            Available = $true
            Count = 0
            EventIds = [int[]]@()
            Error = $null
        }
    }
}

}

Describe "Office and TPM diagnostic assessment" {
    It "keeps a healthy Office authentication environment informational" {
        $assessment = Get-ToolkitOfficeTpmAssessment `
            -Snapshot (New-OfficeTpmSnapshot)

        Assert-OperationalCondition `
            -Condition ($assessment.Severity -eq "Informativo") `
            -Message "Ambiente Office saudavel recebeu severidade incorreta."
        Assert-OperationalCondition `
            -Condition (
                ($assessment.Observations -join "`n") -match
                "nao apresentam alerta evidente"
            ) `
            -Message "Conclusao saudavel do Office nao foi gerada."
    }

    It "identifies Office 2016, 2019 and 2021 licensing families" {
        InModuleScope ServiceDeskToolkit.Office {
            $cases = @(
                @{
                    Product = "ProPlusVolume"
                    Names = @("Office 16, Office16ProPlusVL_KMS_Client edition")
                    Expected = "Office 2016"
                },
                @{
                    Product = "ProPlus2019Volume"
                    Names = @()
                    Expected = "Office 2019"
                },
                @{
                    Product = "ProPlus2021Volume"
                    Names = @()
                    Expected = "Office 2021"
                }
            )

            foreach ($case in $cases) {
                $actual = Get-ToolkitOfficeEdition -ProductReleaseIds $case.Product -LicenseNames $case.Names

                if ($actual -ne $case.Expected) {
                    throw (
                        "Edicao incorreta para $($case.Product): " +
                        "$actual, esperado $($case.Expected)."
                    )
                }
            }
        }
    }

    It "uses OSPP instead of vnextdiag for an unlicensed Office 2021" {
        $snapshot = New-OfficeTpmSnapshot -OfficeEdition "Office 2021" -OfficeProductReleaseIds "ProPlus2021Volume" -VNextDiagPath "" -OsppPath "C:\Program Files\Microsoft Office\root\Office16\ospp.vbs" -OsppCheckRan $true -OsppUnlicensedCount 1 -OsppLicenseStatuses @("NOTIFICATIONS")
        $assessment = Get-ToolkitOfficeTpmAssessment -Snapshot $snapshot
        $codes = @($assessment.Remediations | ForEach-Object Code)

        Assert-OperationalCondition -Condition ($codes -contains "OSPP_UNLICENSED") -Message "Office 2021 nao licenciado nao recebeu fluxo OSPP."
        Assert-OperationalCondition -Condition ($codes -notcontains "VNEXT_NOT_FOUND") -Message "Office 2021 recebeu fluxo vnextdiag indevido."

        $report = Format-ToolkitOfficeTpmReport -Snapshot $snapshot -Assessment $assessment -ComputerName "PC-TESTE" -UserName "CORP\usuario"

        Assert-OperationalTextContains -Text $report -Expected "Edicao identificada: Office 2021"
        Assert-OperationalTextContains -Text $report -Expected "OSPP consultado: Sim"
        Assert-OperationalTextContains -Text $report -Expected "nenhuma chave de produto"
    }

    It "prioritizes a pending restart before authentication changes" {
        $assessment = Get-ToolkitOfficeTpmAssessment `
            -Snapshot (New-OfficeTpmSnapshot -RebootPending $true)
        $codes = @($assessment.Remediations | ForEach-Object Code)

        Assert-OperationalCondition `
            -Condition ($codes -contains "RESTART_PENDING") `
            -Message "Reinicio pendente nao recebeu prioridade."
    }

    It "classifies an unready TPM as critical" {
        $assessment = Get-ToolkitOfficeTpmAssessment `
            -Snapshot (New-OfficeTpmSnapshot -TpmReady $false)
        $codes = @($assessment.Remediations | ForEach-Object Code)

        Assert-OperationalCondition `
            -Condition ($assessment.Severity -eq "Critico") `
            -Message "TPM nao pronto nao foi classificado como critico."
        Assert-OperationalCondition `
            -Condition ($codes -contains "TPM_NOT_READY") `
            -Message "Remediacao TPM_NOT_READY ausente."
    }

    It "offers the protected WAM repair when the package is missing" {
        $assessment = Get-ToolkitOfficeTpmAssessment `
            -Snapshot (
                New-OfficeTpmSnapshot `
                    -AadBrokerPackagePresent $false
            )
        $repair = $assessment.Remediations |
            Where-Object Code -eq "WAM_PACKAGE_MISSING" |
            Select-Object -First 1

        Assert-OperationalCondition `
            -Condition ($null -ne $repair -and $repair.Automatable) `
            -Message "Reparo WAM protegido nao foi recomendado."
    }

    It "escalates a failed device identity to the Entra administrator" {
        $assessment = Get-ToolkitOfficeTpmAssessment `
            -Snapshot (
                New-OfficeTpmSnapshot `
                    -DeviceAuthStatus "FAILED. Device is disabled"
            )
        $codes = @($assessment.Remediations | ForEach-Object Code)

        Assert-OperationalCondition `
            -Condition (
                $assessment.Severity -eq "Critico" -and
                $codes -contains "DEVICE_AUTH_FAILED"
            ) `
            -Message "Falha de identidade Entra nao foi escalada."
    }

    It "formats the safe remediation and official-reference contract" {
        $snapshot = New-OfficeTpmSnapshot -TpmReady $false
        $assessment = Get-ToolkitOfficeTpmAssessment -Snapshot $snapshot
        $report = Format-ToolkitOfficeTpmReport `
            -Snapshot $snapshot `
            -Assessment $assessment `
            -ComputerName "PC-TESTE" `
            -UserName "CORP\usuario"

        Assert-OperationalTextContains `
            -Text $report `
            -Expected "OFFICE / TPM / AUTENTICACAO"
        Assert-OperationalTextContains `
            -Text $report `
            -Expected "ACOES CRITICAS NAO AUTOMATIZADAS"
        Assert-OperationalTextContains `
            -Text $report `
            -Expected "learn.microsoft.com"
        Assert-OperationalTextContains `
            -Text $report `
            -Expected "nenhuma chave BitLocker"
    }

    It "refuses a WAM repair without explicit confirmation" {
        $thrown = $false

        try {
            Repair-ToolkitOfficeWam -ErrorAction Stop
        }
        catch {
            $thrown = $true
        }

        Assert-OperationalCondition `
            -Condition $thrown `
            -Message "Reparo WAM foi aceito sem confirmacao explicita."
    }
}

Describe "Office WAM repair protections" {
    It "registers exactly the two official WAM manifests" {
        InModuleScope ServiceDeskToolkit.Office {
            Mock Get-Process { @() }
            Mock Test-Path { $true }
            Mock Add-AppxPackage {}
            Mock Get-AppxPackage {
                [pscustomobject]@{ Name = $Name }
            }

            $result = Repair-ToolkitOfficeWam -Confirmed

            Assert-MockCalled Add-AppxPackage -Times 2 -Exactly

            if (-not $result.Success) {
                throw "Reparo WAM simulado nao confirmou os dois pacotes."
            }
        }
    }

    It "does not change WAM while an Office process is open" {
        InModuleScope ServiceDeskToolkit.Office {
            Mock Get-Process {
                [pscustomobject]@{ ProcessName = "WINWORD" }
            }
            Mock Add-AppxPackage {}

            $thrown = $false

            try {
                Repair-ToolkitOfficeWam -Confirmed -ErrorAction Stop
            }
            catch {
                $thrown = $true
            }

            Assert-MockCalled Add-AppxPackage -Times 0 -Exactly

            if (-not $thrown) {
                throw "Reparo WAM nao foi bloqueado com Word aberto."
            }
        }
    }
}

Describe "Network diagnostic assessment" {
    It "identifies a missing adapter" {
        $assessment = Get-ToolkitNetworkAssessment `
            -Snapshot (New-NetworkSnapshot -HasAdapter $false)

        Assert-OperationalCondition `
            -Condition ($assessment.Cause -match "Nenhum adaptador") `
            -Message "Adaptador ausente nao foi identificado."
    }

    It "identifies a missing IPv4 address" {
        $assessment = Get-ToolkitNetworkAssessment `
            -Snapshot (New-NetworkSnapshot -HasIp $false)

        Assert-OperationalCondition `
            -Condition ($assessment.Cause -match "sem IPv4") `
            -Message "IPv4 ausente nao foi identificado."
    }

    It "identifies a missing gateway" {
        $assessment = Get-ToolkitNetworkAssessment `
            -Snapshot (New-NetworkSnapshot -HasGateway $false)

        Assert-OperationalCondition `
            -Condition ($assessment.Cause -match "nao possui gateway") `
            -Message "Gateway ausente nao foi identificado."
    }

    It "identifies a gateway connectivity failure" {
        $assessment = Get-ToolkitNetworkAssessment `
            -Snapshot (
                New-NetworkSnapshot -GatewayResponds $false
            )

        Assert-OperationalCondition `
            -Condition ($assessment.Cause -match "Gateway configurado") `
            -Message "Falha de gateway nao foi identificada."
    }

    It "identifies an external connectivity failure" {
        $assessment = Get-ToolkitNetworkAssessment `
            -Snapshot (
                New-NetworkSnapshot `
                    -CloudflareResponds $false `
                    -GoogleResponds $false
            )

        Assert-OperationalCondition `
            -Condition ($assessment.Cause -match "resposta externa") `
            -Message "Falha externa nao foi identificada."
    }

    It "identifies a DNS failure after IP connectivity" {
        $assessment = Get-ToolkitNetworkAssessment `
            -Snapshot (
                New-NetworkSnapshot -MicrosoftDnsResolves $false
            )

        Assert-OperationalCondition `
            -Condition ($assessment.Cause -match "resolucao DNS") `
            -Message "Falha de DNS nao foi identificada."
    }

    It "classifies basic connectivity as functional" {
        $snapshot = New-NetworkSnapshot
        $assessment = Get-ToolkitNetworkAssessment `
            -Snapshot $snapshot
        $report = Format-ToolkitNetworkReport `
            -Snapshot $snapshot `
            -Assessment $assessment `
            -ComputerName "PC-TESTE" `
            -UserName "CORP\usuario"

        Assert-OperationalCondition `
            -Condition ($assessment.Cause -match "funcional") `
            -Message "Conectividade funcional nao foi identificada."
        Assert-OperationalTextContains `
            -Text $report `
            -Expected "TESTES DE CONECTIVIDADE"
        Assert-OperationalTextContains `
            -Text $report `
            -Expected "Causa provavel:"
    }
}

Describe "Inventory assessment" {
    It "keeps a healthy inventory without observations" {
        $assessment = Get-ToolkitInventoryAssessment `
            -Snapshot (New-InventorySnapshot)

        Assert-OperationalCondition `
            -Condition (-not $assessment.HasObservations) `
            -Message "Inventario saudavel gerou observacoes."
    }

    It "identifies memory below eight gigabytes" {
        $assessment = Get-ToolkitInventoryAssessment `
            -Snapshot (
                New-InventorySnapshot -TotalRamGb 7.9
            )

        Assert-OperationalCondition `
            -Condition (
                ($assessment.Observations -join "`n") -match
                "Memoria RAM"
            ) `
            -Message "Memoria baixa nao foi identificada."
    }

    It "identifies low system disk space" {
        $assessment = Get-ToolkitInventoryAssessment `
            -Snapshot (
                New-InventorySnapshot -SystemFreeGb 14.9
            )

        Assert-OperationalCondition `
            -Condition (
                ($assessment.Observations -join "`n") -match
                "pouco espaco"
            ) `
            -Message "Disco baixo nao foi identificado."
    }

    It "identifies uptime of seven days" {
        $assessment = Get-ToolkitInventoryAssessment `
            -Snapshot (
                New-InventorySnapshot -UptimeDays 7
            )

        Assert-OperationalCondition `
            -Condition (
                ($assessment.Observations -join "`n") -match
                "ligada ha 7"
            ) `
            -Message "Uptime elevado nao foi identificado."
    }

    It "identifies an inventory without active adapters" {
        $assessment = Get-ToolkitInventoryAssessment `
            -Snapshot (
                New-InventorySnapshot -HasAdapter $false
            )

        Assert-OperationalCondition `
            -Condition (
                ($assessment.Observations -join "`n") -match
                "Nenhum adaptador"
            ) `
            -Message "Ausencia de adaptadores nao foi identificada."
    }

    It "formats the inventory report contract" {
        $snapshot = New-InventorySnapshot
        $assessment = Get-ToolkitInventoryAssessment `
            -Snapshot $snapshot
        $report = Format-ToolkitInventoryReport `
            -Snapshot $snapshot `
            -Assessment $assessment `
            -ComputerName "PC-TESTE" `
            -UserName "CORP\usuario"

        Assert-OperationalTextContains `
            -Text $report `
            -Expected "INVENTARIO DA MAQUINA"
        Assert-OperationalTextContains `
            -Text $report `
            -Expected "BIOS / SERIAL"
        Assert-OperationalTextContains `
            -Text $report `
            -Expected "REDE RESUMIDA"
    }
}

Describe "Printer diagnostic assessment" {
    It "keeps a healthy print environment without observations" {
        $assessment = Get-ToolkitPrinterAssessment `
            -Snapshot (New-PrinterSnapshot)

        Assert-OperationalCondition `
            -Condition (-not $assessment.HasObservations) `
            -Message "Ambiente saudavel gerou observacoes."
    }

    It "prioritizes restarting a stopped spooler" {
        $assessment = Get-ToolkitPrinterAssessment `
            -Snapshot (
                New-PrinterSnapshot -SpoolerStatus "Stopped"
            )

        Assert-OperationalCondition `
            -Condition ($assessment.NextAction -match "Reiniciar spooler") `
            -Message "Spooler parado nao priorizou reinicio."
    }

    It "identifies an environment without printers" {
        $assessment = Get-ToolkitPrinterAssessment `
            -Snapshot (
                New-PrinterSnapshot -HasPrinter $false
            )

        Assert-OperationalCondition `
            -Condition (
                ($assessment.Observations -join "`n") -match
                "Nenhuma impressora"
            ) `
            -Message "Ausencia de impressoras nao foi identificada."
    }

    It "identifies a missing default printer" {
        $assessment = Get-ToolkitPrinterAssessment `
            -Snapshot (
                New-PrinterSnapshot -HasDefaultPrinter $false
            )

        Assert-OperationalCondition `
            -Condition (
                $assessment.NextAction -match "Definir impressora padrao"
            ) `
            -Message "Impressora padrao ausente nao foi priorizada."
    }

    It "prioritizes queued jobs before offline printers" {
        $assessment = Get-ToolkitPrinterAssessment `
            -Snapshot (
                New-PrinterSnapshot `
                    -HasJob $true `
                    -IsOffline $true
            )

        Assert-OperationalCondition `
            -Condition ($assessment.NextAction -match "fila") `
            -Message "Fila de impressao nao recebeu a prioridade esperada."
    }

    It "formats the printer report contract" {
        $snapshot = New-PrinterSnapshot -IsOffline $true
        $assessment = Get-ToolkitPrinterAssessment `
            -Snapshot $snapshot
        $report = Format-ToolkitPrinterReport `
            -Snapshot $snapshot `
            -Assessment $assessment `
            -ComputerName "PC-TESTE" `
            -UserName "CORP\usuario"

        Assert-OperationalTextContains `
            -Text $report `
            -Expected "PAINEL DE IMPRESSORAS"
        Assert-OperationalTextContains `
            -Text $report `
            -Expected "FILA DE IMPRESSAO"
        Assert-OperationalTextContains `
            -Text $report `
            -Expected "CONCLUSAO AUTOMATICA"
    }
}

Describe "Protected network operations" {
    It "does not renew IP without explicit confirmation" {
        { Invoke-ToolkitRenewIp } |
            Should -Throw "*confirmacao explicita*"
    }

    It "does not reset Winsock without explicit confirmation" {
        { Invoke-ToolkitNetworkStackReset -Target Winsock } |
            Should -Throw "*confirmacao explicita*"
    }

    It "does not reset TCP/IP without explicit confirmation" {
        { Invoke-ToolkitNetworkStackReset -Target TcpIp } |
            Should -Throw "*confirmacao explicita*"
    }

    It "exports the read-only advanced network commands" {
        foreach ($commandName in @(
            "Get-ToolkitAdvancedNetworkReport",
            "Get-ToolkitDnsReport",
            "Get-ToolkitRoutesReport",
            "Test-ToolkitDefaultGateway",
            "Open-ToolkitNetworkConnections"
        )) {
            Get-Command $commandName -ErrorAction Stop |
                Should -Not -BeNullOrEmpty
        }
    }

    It "generates DNS and route reports from mocked read-only data" {
        Mock Get-DnsClientServerAddress {
            [pscustomobject]@{
                InterfaceAlias = "Ethernet"
                InterfaceIndex = 7
                ServerAddresses = @("10.0.0.2")
            }
        } -ModuleName ServiceDeskToolkit.Network
        Mock Get-DnsClientCache {
            [pscustomobject]@{
                Entry = "example.test"
                RecordType = "A"
                Status = "Success"
                Data = "192.0.2.1"
            }
        } -ModuleName ServiceDeskToolkit.Network
        Mock Get-NetRoute {
            [pscustomobject]@{
                DestinationPrefix = "0.0.0.0/0"
                NextHop = "10.0.0.1"
                InterfaceAlias = "Ethernet"
                RouteMetric = 25
            }
        } -ModuleName ServiceDeskToolkit.Network

        (Get-ToolkitDnsReport) | Should -Match "DNS - CONFIGURACAO"
        (Get-ToolkitRoutesReport) | Should -Match "ROTAS IPV4"
    }

    It "tests the discovered gateway without changing network state" {
        Mock Get-NetIPConfiguration {
            [pscustomobject]@{
                IPv4DefaultGateway = [pscustomobject]@{
                    NextHop = "10.0.0.1"
                }
            }
        } -ModuleName ServiceDeskToolkit.Network
        Mock Test-Connection { $true } `
            -ModuleName ServiceDeskToolkit.Network

        (Test-ToolkitDefaultGateway) | Should -Match "10.0.0.1 : OK"
        Should -Invoke Test-Connection `
            -ModuleName ServiceDeskToolkit.Network `
            -Times 1 `
            -Exactly
    }
}

Describe "Protected printer operations" {
    It "does not clear the print queue without explicit confirmation" {
        { Clear-ToolkitPrintQueue } |
            Should -Throw "*confirmacao explicita*"
    }

    It "exports the read-only printer commands" {
        foreach ($commandName in @(
            "Get-ToolkitPrinterListReport",
            "Get-ToolkitPrintJobsReport",
            "Get-ToolkitDefaultPrinterReport",
            "Get-ToolkitOfflinePrintersReport",
            "Open-ToolkitPrintersSettings",
            "Open-ToolkitPrintManagement"
        )) {
            Get-Command $commandName -ErrorAction Stop |
                Should -Not -BeNullOrEmpty
        }
    }

    It "formats printer and job reports from mocked read-only data" {
        Mock Get-CimInstance {
            [pscustomobject]@{
                Name = "Impressora de teste"
                DriverName = "Driver de teste"
                PortName = "IP_192.0.2.10"
                PrinterStatus = 3
                Default = $true
                Shared = $false
                WorkOffline = $false
            }
        } -ParameterFilter {
            $ClassName -eq "Win32_Printer"
        } -ModuleName ServiceDeskToolkit.Printers
        Mock Get-CimInstance {
            [pscustomobject]@{
                Name = "Impressora de teste, 1"
                Document = "Documento de teste"
                Owner = "usuario"
                JobStatus = "Spooling"
                TotalPages = 1
                Size = 1024
                TimeSubmitted = "20260812120000.000000-000"
            }
        } -ParameterFilter {
            $ClassName -eq "Win32_PrintJob"
        } -ModuleName ServiceDeskToolkit.Printers

        (Get-ToolkitPrinterListReport) |
            Should -Match "IMPRESSORAS INSTALADAS"
        (Get-ToolkitPrintJobsReport) |
            Should -Match "FILA DE IMPRESSAO"
        (Get-ToolkitDefaultPrinterReport) |
            Should -Match "IMPRESSORA PADRAO"
    }
}
