Set-StrictMode -Version 2.0

function Test-ToolkitAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)

        return $principal.IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
    }
    catch {
        return $false
    }
}

function Get-ToolkitMachineHealthSnapshot {
    [CmdletBinding()]
    param(
        [datetime]$CollectedAt = (Get-Date)
    )

    $snapshot = [ordered]@{
        CollectedAt = $CollectedAt
        ComputerName = [string]$env:COMPUTERNAME
        UserName = "$env:USERDOMAIN\$env:USERNAME"
        IsAdmin = Test-ToolkitAdministrator
        SystemAvailable = $false
        SystemCaption = $null
        SystemBuildNumber = $null
        SystemArchitecture = $null
        TotalRamGb = 0
        MemoryUsedPercent = 0
        DiskAvailable = $false
        SystemDrive = if ([string]::IsNullOrWhiteSpace($env:SystemDrive)) {
            "C:"
        }
        else {
            [string]$env:SystemDrive
        }
        DiskSizeGb = 0
        DiskFreeGb = 0
        DiskFreePercent = 0
        UptimeAvailable = $false
        UptimeTotalDays = 0
        UptimeDays = 0
        UptimeHours = 0
        NetworkAdapterAvailable = $false
        NetworkDescription = $null
        IPv4Addresses = @()
        Gateways = @()
        DnsResolved = $false
        TimeServiceFound = $false
        TimeServiceStatus = $null
        TimeSource = $null
        SpoolerFound = $false
        SpoolerStatus = $null
        PendingReboot = $false
        RebootReasons = @()
    }

    $os = Get-CimInstance `
        -ClassName Win32_OperatingSystem `
        -ErrorAction SilentlyContinue

    $computer = Get-CimInstance `
        -ClassName Win32_ComputerSystem `
        -ErrorAction SilentlyContinue

    if ($null -ne $os -and $null -ne $computer) {
        $snapshot.SystemAvailable = $true
        $snapshot.SystemCaption = [string]$os.Caption
        $snapshot.SystemBuildNumber = [string]$os.BuildNumber
        $snapshot.SystemArchitecture = [string]$os.OSArchitecture
    }

    if ($null -ne $computer -and $computer.TotalPhysicalMemory) {
        $snapshot.TotalRamGb = [Math]::Round(
            ($computer.TotalPhysicalMemory / 1GB),
            1
        )
    }

    if ($null -ne $os -and $os.TotalVisibleMemorySize -gt 0) {
        $usedMemoryKb = (
            $os.TotalVisibleMemorySize -
            $os.FreePhysicalMemory
        )

        $snapshot.MemoryUsedPercent = [Math]::Round(
            (($usedMemoryKb / $os.TotalVisibleMemorySize) * 100),
            1
        )
    }

    $systemDisk = Get-CimInstance `
        -ClassName Win32_LogicalDisk `
        -Filter "DriveType=3" `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DeviceID -eq $snapshot.SystemDrive
        } |
        Select-Object -First 1

    if ($null -ne $systemDisk -and $systemDisk.Size -gt 0) {
        $snapshot.DiskAvailable = $true
        $snapshot.SystemDrive = [string]$systemDisk.DeviceID
        $snapshot.DiskSizeGb = [Math]::Round(($systemDisk.Size / 1GB), 1)
        $snapshot.DiskFreeGb = [Math]::Round(($systemDisk.FreeSpace / 1GB), 1)
        $snapshot.DiskFreePercent = [Math]::Round(
            (($systemDisk.FreeSpace / $systemDisk.Size) * 100),
            1
        )
    }

    if ($null -ne $os -and $os.LastBootUpTime) {
        $uptime = New-TimeSpan `
            -Start $os.LastBootUpTime `
            -End $CollectedAt

        $snapshot.UptimeAvailable = $true
        $snapshot.UptimeTotalDays = [double]$uptime.TotalDays
        $snapshot.UptimeDays = [int]$uptime.Days
        $snapshot.UptimeHours = [int]$uptime.Hours
    }

    $adapters = @(
        Get-CimInstance `
            -ClassName Win32_NetworkAdapterConfiguration `
            -Filter "IPEnabled=True" `
            -ErrorAction SilentlyContinue
    )

    foreach ($candidate in $adapters) {
        $candidateIpv4 = @(
            $candidate.IPAddress |
            Where-Object {
                $_ -match '^\d{1,3}(\.\d{1,3}){3}$'
            }
        )

        if ($candidateIpv4.Count -gt 0) {
            $snapshot.NetworkAdapterAvailable = $true
            $snapshot.NetworkDescription = [string]$candidate.Description
            $snapshot.IPv4Addresses = @($candidateIpv4)
            $snapshot.Gateways = @(
                $candidate.DefaultIPGateway |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                }
            )
            break
        }
    }

    try {
        $dnsResult = Resolve-DnsName `
            -Name "www.microsoft.com" `
            -Type A `
            -ErrorAction Stop

        $snapshot.DnsResolved = ($null -ne $dnsResult)
    }
    catch {
        $snapshot.DnsResolved = $false
    }

    $timeService = Get-Service `
        -Name "w32time" `
        -ErrorAction SilentlyContinue

    if ($null -ne $timeService) {
        $snapshot.TimeServiceFound = $true
        $snapshot.TimeServiceStatus = [string]$timeService.Status
    }

    try {
        $timeSourceRaw = & w32tm.exe /query /source 2>&1
        $snapshot.TimeSource = ($timeSourceRaw | Out-String).Trim()
    }
    catch {
        $snapshot.TimeSource = $_.Exception.Message
    }

    $spooler = Get-Service `
        -Name "Spooler" `
        -ErrorAction SilentlyContinue

    if ($null -ne $spooler) {
        $snapshot.SpoolerFound = $true
        $snapshot.SpoolerStatus = [string]$spooler.Status
    }

    $rebootReasons = New-Object 'System.Collections.Generic.List[string]'
    $cbsPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    $wuPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    $sessionManagerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"

    if (Test-Path $cbsPath) {
        [void]$rebootReasons.Add("Component Based Servicing")
    }

    if (Test-Path $wuPath) {
        [void]$rebootReasons.Add("Windows Update")
    }

    $sessionManager = Get-ItemProperty `
        -Path $sessionManagerPath `
        -Name "PendingFileRenameOperations" `
        -ErrorAction SilentlyContinue

    if (
        $null -ne $sessionManager -and
        $null -ne $sessionManager.PendingFileRenameOperations
    ) {
        [void]$rebootReasons.Add("PendingFileRenameOperations")
    }

    $snapshot.RebootReasons = @($rebootReasons)
    $snapshot.PendingReboot = ($snapshot.RebootReasons.Count -gt 0)

    return [pscustomobject]$snapshot
}

Export-ModuleMember -Function Get-ToolkitMachineHealthSnapshot
