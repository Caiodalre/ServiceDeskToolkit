Set-StrictMode -Version 2.0

function Get-ToolkitInventorySnapshot {
    [CmdletBinding()]
    param(
        [datetime]$ObservedAt = (Get-Date),
        [string]$SystemDrive = $env:SystemDrive
    )

    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
    $processor = Get-CimInstance Win32_Processor -ErrorAction Stop |
        Select-Object -First 1
    $baseboard = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $memoryModules = @(
        Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    )
    $disks = @(
        Get-CimInstance `
            Win32_LogicalDisk `
            -Filter "DriveType=3" `
            -ErrorAction SilentlyContinue
    )
    $rawAdapters = @(
        Get-CimInstance `
            Win32_NetworkAdapterConfiguration `
            -Filter "IPEnabled=True" `
            -ErrorAction SilentlyContinue
    )

    $totalRamGb = 0

    if ($computer.TotalPhysicalMemory) {
        $totalRamGb = [Math]::Round(
            ($computer.TotalPhysicalMemory / 1GB),
            2
        )
    }

    $uptime = $null

    if ($os.LastBootUpTime) {
        $uptime = New-TimeSpan `
            -Start $os.LastBootUpTime `
            -End $ObservedAt
    }

    $adapters = @(
        foreach ($adapter in $rawAdapters) {
            $ipv4 = @()
            $gateways = @()
            $dnsServers = @()

            if ($adapter.IPAddress) {
                $ipv4 = @(
                    $adapter.IPAddress |
                        Where-Object {
                            $_ -match '^\d{1,3}(\.\d{1,3}){3}$'
                        }
                )
            }

            if ($adapter.DefaultIPGateway) {
                $gateways = @(
                    $adapter.DefaultIPGateway |
                        Where-Object {
                            $_ -and $_ -notlike 'fe80*'
                        }
                )
            }

            if ($adapter.DNSServerSearchOrder) {
                $dnsServers = @($adapter.DNSServerSearchOrder)
            }

            [pscustomobject]@{
                Description = [string]$adapter.Description
                MACAddress = [string]$adapter.MACAddress
                DHCPEnabled = [bool]$adapter.DHCPEnabled
                IPv4Addresses = [string[]]$ipv4
                Gateways = [string[]]$gateways
                DnsServers = [string[]]$dnsServers
            }
        }
    )

    $systemDisk = $disks |
        Where-Object { $_.DeviceID -eq $SystemDrive } |
        Select-Object -First 1

    return [pscustomobject]@{
        ObservedAt = $ObservedAt
        SystemDrive = $SystemDrive
        Computer = $computer
        OperatingSystem = $os
        Bios = $bios
        Processor = $processor
        Baseboard = $baseboard
        MemoryModules = [object[]]$memoryModules
        Disks = [object[]]$disks
        Adapters = [object[]]$adapters
        TotalRamGb = $totalRamGb
        Uptime = $uptime
        SystemDisk = $systemDisk
    }
}

function Get-ToolkitInventoryAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Snapshot
    )

    $observations = New-Object 'System.Collections.Generic.List[string]'

    if (
        $Snapshot.TotalRamGb -gt 0 -and
        $Snapshot.TotalRamGb -lt 8
    ) {
        $observations.Add(
            "Memoria RAM abaixo de 8 GB pode impactar desempenho em Office, Teams, navegador e ferramentas corporativas."
        )
    }

    $systemDisk = $Snapshot.SystemDisk

    if ($null -ne $systemDisk -and $systemDisk.Size -gt 0) {
        $systemFreeGb = [Math]::Round(
            ($systemDisk.FreeSpace / 1GB),
            2
        )
        $systemFreePercent = [Math]::Round(
            (($systemDisk.FreeSpace / $systemDisk.Size) * 100),
            1
        )

        if (
            $systemFreeGb -lt 15 -or
            $systemFreePercent -lt 10
        ) {
            $observations.Add(
                "Disco do sistema com pouco espaco livre: $systemFreeGb GB livres ($systemFreePercent%)."
            )
        }
    }

    if (
        $null -ne $Snapshot.Uptime -and
        $Snapshot.Uptime.TotalDays -ge 7
    ) {
        $observations.Add(
            "Maquina esta ligada ha $([Math]::Floor($Snapshot.Uptime.TotalDays)) dia(s). Reinicio pode ajudar em falhas intermitentes."
        )
    }

    if (@($Snapshot.Adapters).Count -eq 0) {
        $observations.Add(
            "Nenhum adaptador de rede ativo encontrado no inventario."
        )
    }

    return [pscustomobject]@{
        HasObservations = ($observations.Count -gt 0)
        Observations = $observations.ToArray()
    }
}

function Format-ToolkitInventoryReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Snapshot,

        [Parameter(Mandatory = $true)]
        [psobject]$Assessment,

        [string]$ComputerName = $env:COMPUTERNAME,
        [string]$UserName = "$env:USERDOMAIN\$env:USERNAME",
        [bool]$IsAdministrator = $false,
        [datetime]$GeneratedAt = $Snapshot.ObservedAt
    )

    $sb = New-Object System.Text.StringBuilder
    $computer = $Snapshot.Computer
    $os = $Snapshot.OperatingSystem
    $bios = $Snapshot.Bios
    $processor = $Snapshot.Processor
    $baseboard = $Snapshot.Baseboard
    $memoryModules = @($Snapshot.MemoryModules)
    $disks = @($Snapshot.Disks)
    $adapters = @($Snapshot.Adapters)

    [void]$sb.AppendLine(
        "INVENTARIO DA MAQUINA - PAINEL CONSOLIDADO"
    )
    [void]$sb.AppendLine(
        "------------------------------------------"
    )
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine(
        "Gerado em: $($GeneratedAt.ToString('dd/MM/yyyy HH:mm:ss'))"
    )
    [void]$sb.AppendLine("Hostname: $ComputerName")
    [void]$sb.AppendLine("Usuario: $UserName")
    [void]$sb.AppendLine(
        "Admin: $(if ($IsAdministrator) { 'Sim' } else { 'Nao' })"
    )
    [void]$sb.AppendLine(
        "Tipo de acao: Coleta de inventario sem correcao"
    )
    [void]$sb.AppendLine("")

    $uptimeText = "Nao encontrado"

    if ($null -ne $Snapshot.Uptime) {
        $uptimeText = (
            "{0} dia(s), {1} hora(s), {2} minuto(s)" -f
            $Snapshot.Uptime.Days,
            $Snapshot.Uptime.Hours,
            $Snapshot.Uptime.Minutes
        )
    }

    $installDateText = "Nao encontrado"

    if ($os.InstallDate) {
        $installDateText = $os.InstallDate.ToString(
            "dd/MM/yyyy HH:mm:ss"
        )
    }

    $biosDateText = "Nao encontrado"

    if ($bios.ReleaseDate) {
        $biosDateText = $bios.ReleaseDate.ToString("dd/MM/yyyy")
    }

    if ($computer.PartOfDomain) {
        $domainText = "Dominio: $($computer.Domain)"
    }
    else {
        $domainText = "Grupo de trabalho: $($computer.Workgroup)"
    }

    [void]$sb.AppendLine("IDENTIFICACAO")
    [void]$sb.AppendLine("-------------")
    [void]$sb.AppendLine("Nome da maquina: $ComputerName")
    [void]$sb.AppendLine(
        "Fabricante: $(if ($computer.Manufacturer) { $computer.Manufacturer } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine(
        "Modelo: $(if ($computer.Model) { $computer.Model } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine("Dominio/Workgroup: $domainText")
    [void]$sb.AppendLine("Usuario logado: $UserName")
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("SISTEMA OPERACIONAL")
    [void]$sb.AppendLine("-------------------")
    [void]$sb.AppendLine("Sistema: $($os.Caption)")
    [void]$sb.AppendLine("Versao: $($os.Version)")
    [void]$sb.AppendLine("Build: $($os.BuildNumber)")
    [void]$sb.AppendLine("Arquitetura: $($os.OSArchitecture)")
    [void]$sb.AppendLine("Instalado em: $installDateText")
    [void]$sb.AppendLine(
        "Ultimo boot: $(if ($os.LastBootUpTime) { $os.LastBootUpTime.ToString('dd/MM/yyyy HH:mm:ss') } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine("Uptime: $uptimeText")
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("HARDWARE PRINCIPAL")
    [void]$sb.AppendLine("------------------")
    [void]$sb.AppendLine(
        "Processador: $(if ($processor.Name) { $processor.Name.Trim() } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine(
        "Nucleos fisicos: $(if ($processor.NumberOfCores) { $processor.NumberOfCores } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine(
        "Processadores logicos: $(if ($processor.NumberOfLogicalProcessors) { $processor.NumberOfLogicalProcessors } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine(
        "Clock maximo MHz: $(if ($processor.MaxClockSpeed) { $processor.MaxClockSpeed } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine(
        "Memoria total: $($Snapshot.TotalRamGb) GB"
    )
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("MEMORIA RAM")
    [void]$sb.AppendLine("-----------")

    if ($memoryModules.Count -gt 0) {
        foreach ($module in ($memoryModules | Sort-Object BankLabel)) {
            $capacityGb = 0

            if ($module.Capacity) {
                $capacityGb = [Math]::Round(
                    ($module.Capacity / 1GB),
                    2
                )
            }

            [void]$sb.AppendLine(
                "Slot: $(if ($module.BankLabel) { $module.BankLabel } else { 'Nao informado' }) | Capacidade: $capacityGb GB | Velocidade: $(if ($module.Speed) { "$($module.Speed) MHz" } else { 'Nao informado' }) | Fabricante: $(if ($module.Manufacturer) { $module.Manufacturer } else { 'Nao informado' })"
            )
        }
    }
    else {
        [void]$sb.AppendLine(
            "Modulos de memoria nao encontrados via CIM."
        )
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("DISCOS")
    [void]$sb.AppendLine("------")

    if ($disks.Count -gt 0) {
        foreach ($disk in ($disks | Sort-Object DeviceID)) {
            $sizeGb = 0
            $freeGb = 0
            $freePercent = 0

            if ($disk.Size) {
                $sizeGb = [Math]::Round(($disk.Size / 1GB), 2)
            }

            if ($disk.FreeSpace) {
                $freeGb = [Math]::Round(
                    ($disk.FreeSpace / 1GB),
                    2
                )
            }

            if ($disk.Size -gt 0) {
                $freePercent = [Math]::Round(
                    (($disk.FreeSpace / $disk.Size) * 100),
                    1
                )
            }

            [void]$sb.AppendLine(
                "$($disk.DeviceID) | Tamanho: $sizeGb GB | Livre: $freeGb GB | Livre %: $freePercent% | Volume: $(if ($disk.VolumeName) { $disk.VolumeName } else { 'Sem nome' })"
            )
        }
    }
    else {
        [void]$sb.AppendLine("Nenhum disco local encontrado.")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("BIOS / SERIAL")
    [void]$sb.AppendLine("-------------")
    [void]$sb.AppendLine(
        "Serial Number: $(if ($bios.SerialNumber) { $bios.SerialNumber } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine(
        "BIOS: $(if ($bios.SMBIOSBIOSVersion) { $bios.SMBIOSBIOSVersion } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine("Data BIOS: $biosDateText")
    [void]$sb.AppendLine(
        "Placa mae: $(if ($baseboard.Product) { $baseboard.Product } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine(
        "Fabricante placa mae: $(if ($baseboard.Manufacturer) { $baseboard.Manufacturer } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("REDE RESUMIDA")
    [void]$sb.AppendLine("-------------")

    if ($adapters.Count -gt 0) {
        foreach ($adapter in $adapters) {
            $ipv4 = @($adapter.IPv4Addresses)
            $gateways = @($adapter.Gateways)
            $dnsServers = @($adapter.DnsServers)

            [void]$sb.AppendLine(
                "Adaptador: $($adapter.Description)"
            )
            [void]$sb.AppendLine(
                "MAC: $(if ($adapter.MACAddress) { $adapter.MACAddress } else { 'Nao encontrado' })"
            )
            [void]$sb.AppendLine(
                "DHCP: $(if ($adapter.DHCPEnabled) { 'Sim' } else { 'Nao' })"
            )
            [void]$sb.AppendLine(
                "IPv4: $(if ($ipv4.Count -gt 0) { $ipv4 -join ', ' } else { 'Nao encontrado' })"
            )
            [void]$sb.AppendLine(
                "Gateway: $(if ($gateways.Count -gt 0) { $gateways -join ', ' } else { 'Nao encontrado' })"
            )
            [void]$sb.AppendLine(
                "DNS: $(if ($dnsServers.Count -gt 0) { $dnsServers -join ', ' } else { 'Nao encontrado' })"
            )
            [void]$sb.AppendLine("")
        }
    }
    else {
        [void]$sb.AppendLine(
            "Nenhum adaptador de rede ativo encontrado."
        )
        [void]$sb.AppendLine("")
    }

    [void]$sb.AppendLine("CONCLUSAO AUTOMATICA")
    [void]$sb.AppendLine("--------------------")

    if (-not $Assessment.HasObservations) {
        [void]$sb.AppendLine(
            "Resultado: inventario coletado sem alerta tecnico evidente."
        )
        [void]$sb.AppendLine(
            "Proxima acao recomendada: usar este resumo como base para triagem do chamado."
        )
    }
    else {
        [void]$sb.AppendLine(
            "Resultado: inventario coletado com observacoes relevantes."
        )
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Observacoes:")

        foreach ($item in @($Assessment.Observations)) {
            [void]$sb.AppendLine("- $item")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine(
            "Proxima acao recomendada: considerar as observacoes acima durante a triagem."
        )
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("OBSERVACOES PARA ATENDIMENTO")
    [void]$sb.AppendLine("----------------------------")
    [void]$sb.AppendLine(
        "- Este inventario nao executa nenhuma correcao."
    )
    [void]$sb.AppendLine(
        "- Use o botao Copiar resultado para anexar as informacoes no chamado."
    )
    [void]$sb.AppendLine(
        "- Para falhas de rede, use tambem o Diagnostico de rede."
    )
    [void]$sb.AppendLine(
        "- Para problemas de impressao, use Reiniciar spooler como correcao segura."
    )

    return $sb.ToString()
}

Export-ModuleMember -Function @(
    'Get-ToolkitInventorySnapshot',
    'Get-ToolkitInventoryAssessment',
    'Format-ToolkitInventoryReport'
)
