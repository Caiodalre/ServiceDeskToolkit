BeforeAll {
$script:RepositoryRoot = Split-Path -Parent $PSScriptRoot

foreach ($moduleName in @(
    "ServiceDeskToolkit.Inventory",
    "ServiceDeskToolkit.Network",
    "ServiceDeskToolkit.Printers"
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
