Set-StrictMode -Version 2.0

function Get-ToolkitObjectPropertyValue {
    param(
        $InputObject,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        $DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    $property = $InputObject.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $DefaultValue
    }

    return $property.Value
}

function Get-ToolkitDsRegField {
    param(
        [string]$Text,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $pattern = "(?im)^\s*" + [regex]::Escape($Name) + "\s*:\s*(.*?)\s*$"
    $match = [regex]::Match($Text, $pattern)

    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value.Trim()
}

function Get-ToolkitTpmToolField {
    param(
        [string]$Text,
        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    foreach ($name in $Names) {
        $namePattern = if ($name.StartsWith('regex:')) {
            $name.Substring(6)
        }
        else {
            [regex]::Escape($name)
        }
        $pattern = (
            '(?im)^\s*-\s*' +
            $namePattern +
            '\s*:\s*(.*?)\s*$'
        )
        $match = [regex]::Match($Text, $pattern)

        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }

    return $null
}

function Get-ToolkitOfficeEventSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogName,

        [string]$ProviderName,
        [string[]]$MessagePatterns = @(),
        [datetime]$StartTime = (Get-Date).AddDays(-7)
    )

    try {
        $filter = @{
            LogName = $LogName
            StartTime = $StartTime
            Level = @(2, 3)
        }

        if (-not [string]::IsNullOrWhiteSpace($ProviderName)) {
            $filter.ProviderName = $ProviderName
        }

        $events = @(
            Get-WinEvent `
                -FilterHashtable $filter `
                -MaxEvents 100 `
                -ErrorAction Stop
        )

        if ($MessagePatterns.Count -gt 0) {
            $events = @(
                $events |
                    Where-Object {
                        $message = [string]$_.Message

                        foreach ($pattern in $MessagePatterns) {
                            if ($message -match $pattern) {
                                return $true
                            }
                        }

                        return $false
                    }
            )
        }

        return [pscustomobject]@{
            Available = $true
            Count = $events.Count
            EventIds = [int[]]@(
                $events |
                    Select-Object -ExpandProperty Id -Unique
            )
            Error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            Available = $false
            Count = 0
            EventIds = [int[]]@()
            Error = $_.Exception.Message
        }
    }
}

function Get-ToolkitOfficeEdition {
    [CmdletBinding()]
    param(
        [string]$ProductReleaseIds,
        [string[]]$LicenseNames = @(),
        [string[]]$DisplayNames = @()
    )

    $evidence = @(
        $ProductReleaseIds
        $LicenseNames
        $DisplayNames
    ) -join ' '

    if ($evidence -match '(?i)(?:O365|M365|Microsoft365)') {
        return 'Microsoft 365 Apps'
    }

    if ($evidence -match '(?i)(?:Office\s*21|2021|LTSC\s*2021)') {
        return 'Office 2021'
    }

    if ($evidence -match '(?i)(?:Office\s*19|2019)') {
        return 'Office 2019'
    }

    if (
        $evidence -match '(?i)(?:Office\s*16|2016)' -or
        $ProductReleaseIds -match '(?i)(?:ProPlus|Standard|HomeBusiness|HomeStudent)Retail'
    ) {
        return 'Office 2016'
    }

    if (-not [string]::IsNullOrWhiteSpace($ProductReleaseIds)) {
        return 'Office 16.x - edicao nao identificada'
    }

    return 'Nao identificado'
}
function Get-ToolkitOfficeInstallInformation {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
    )
    $configuration = $null

    foreach ($registryPath in $registryPaths) {
        try {
            $configuration = Get-ItemProperty `
                -Path $registryPath `
                -ErrorAction Stop
            break
        }
        catch {
            Write-Verbose (
                "Office Click-to-Run nao encontrado em $registryPath."
            )
        }
    }

    $officeRoots = New-Object 'System.Collections.Generic.List[string]'

    $programFilesX86 = [Environment]::GetEnvironmentVariable(
        'ProgramFiles(x86)'
    )

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $officeRoots.Add(
            (Join-Path $env:ProgramFiles 'Microsoft Office\root\Office16')
        )
        $officeRoots.Add(
            (Join-Path $env:ProgramFiles 'Microsoft Office\Office16')
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $officeRoots.Add(
            (Join-Path $programFilesX86 'Microsoft Office\root\Office16')
        )
        $officeRoots.Add(
            (Join-Path $programFilesX86 'Microsoft Office\Office16')
        )
    }

    $existingRoots = @(
        $officeRoots.ToArray() |
            Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
            Select-Object -Unique
    )
    $vnextDiagPath = $null
    $osppPath = $null

    foreach ($root in $existingRoots) {
        if ([string]::IsNullOrWhiteSpace($vnextDiagPath)) {
            $vnextCandidate = Join-Path $root 'vnextdiag.ps1'

            if (Test-Path -LiteralPath $vnextCandidate -PathType Leaf) {
                $vnextDiagPath = $vnextCandidate
            }
        }

        if ([string]::IsNullOrWhiteSpace($osppPath)) {
            $osppCandidate = Join-Path $root 'ospp.vbs'

            if (Test-Path -LiteralPath $osppCandidate -PathType Leaf) {
                $osppPath = $osppCandidate
            }
        }
    }    $productIds = $null
    $platform = $null
    $version = $null

    if ($null -ne $configuration) {
        $productProperty = $configuration.PSObject.Properties['ProductReleaseIds']
        $platformProperty = $configuration.PSObject.Properties['Platform']
        $versionProperty = $configuration.PSObject.Properties['VersionToReport']

        if ($null -ne $productProperty) {
            $productIds = [string]$productProperty.Value
        }

        if ($null -ne $platformProperty) {
            $platform = [string]$platformProperty.Value
        }

        if ($null -ne $versionProperty) {
            $version = [string]$versionProperty.Value
        }
    }

    $edition = Get-ToolkitOfficeEdition -ProductReleaseIds $productIds

    return [pscustomobject]@{
        Installed = ($null -ne $configuration -or $existingRoots.Count -gt 0)
        ProductReleaseIds = $productIds
        Platform = $platform
        Version = $version
        Edition = $edition
        OfficeRoots = [string[]]$existingRoots
        VNextDiagPath = $vnextDiagPath
        OsppPath = $osppPath
    }
}

function Get-ToolkitOfficeTpmSnapshot {
    [CmdletBinding()]
    param(
        [datetime]$ObservedAt = (Get-Date),
        [int]$EventLookbackDays = 7
    )

    $tpmCommandAvailable = $false
    $tpm = $null
    $tpmError = $null

    try {
        if (Get-Command Get-Tpm -ErrorAction SilentlyContinue) {
            $tpmCommandAvailable = $true
            $tpmCandidate = Get-Tpm -ErrorAction Stop
            $readyProperty = $tpmCandidate.PSObject.Properties['TpmReady']

            if ($null -eq $readyProperty) {
                $tpmError = [string]$tpmCandidate
            }
            else {
                $tpm = $tpmCandidate
            }
        }
    }
    catch {
        $tpmError = $_.Exception.Message
    }

    $tpmSpecVersion = $null
    $tpmManufacturer = $null
    $wmiTpm = $null

    try {
        $wmiTpm = Get-CimInstance `
            -Namespace 'root\CIMV2\Security\MicrosoftTpm' `
            -ClassName Win32_Tpm `
            -ErrorAction Stop

        if ($null -ne $wmiTpm) {
            $tpmSpecVersion = [string]$wmiTpm.SpecVersion
            $tpmManufacturer = [string]$wmiTpm.ManufacturerIdTxt
        }
    }
    catch {
        Write-Verbose (
            'Win32_Tpm indisponivel: ' + $_.Exception.Message
        )
    }

    $tpmToolAvailable = $false
    $tpmToolExitCode = $null
    $tpmToolPresent = $null
    $tpmToolInitialized = $false
    $tpmToolReadyForStorage = $false

    if ($null -eq $tpm -and $null -eq $wmiTpm) {
        try {
            $tpmToolPath = Join-Path $env:SystemRoot 'System32\tpmtool.exe'

            if (Test-Path -LiteralPath $tpmToolPath -PathType Leaf) {
                $tpmToolAvailable = $true
                $tpmToolRaw = & $tpmToolPath getdeviceinformation 2>&1
                $tpmToolExitCode = $LASTEXITCODE
                $tpmToolText = $tpmToolRaw | Out-String
                $presentText = Get-ToolkitTpmToolField `
                    -Text $tpmToolText `
                    -Names @('TPM Present', 'TPM Presente')
                $initializedText = Get-ToolkitTpmToolField `
                    -Text $tpmToolText `
                    -Names @('Is Initialized', 'regex:.*Inicializado')
                $storageText = Get-ToolkitTpmToolField `
                    -Text $tpmToolText `
                    -Names @('Ready For Storage', 'Pronto para Armazenamento')

                if ($presentText -match '^(?i:true|false)$') {
                    $tpmToolPresent = [bool]::Parse($presentText)
                }

                if ($initializedText -match '^(?i:true|false)$') {
                    $tpmToolInitialized = [bool]::Parse($initializedText)
                }

                if ($storageText -match '^(?i:true|false)$') {
                    $tpmToolReadyForStorage = [bool]::Parse($storageText)
                }

                if ([string]::IsNullOrWhiteSpace($tpmSpecVersion)) {
                    $tpmSpecVersion = Get-ToolkitTpmToolField `
                        -Text $tpmToolText `
                        -Names @('TPM Version', 'regex:Vers.o do TPM')
                }

                if ([string]::IsNullOrWhiteSpace($tpmManufacturer)) {
                    $tpmManufacturer = Get-ToolkitTpmToolField `
                        -Text $tpmToolText `
                        -Names @(
                            'TPM Manufacturer ID',
                            'ID do Fabricante do TPM'
                        )
                }
            }
        }
        catch {
            Write-Verbose (
                'tpmtool indisponivel: ' + $_.Exception.Message
            )
        }
    }

    $bitLockerAvailable = $false
    $bitLockerProtectionStatus = $null
    $bitLockerVolumeStatus = $null
    $bitLockerError = $null

    try {
        if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
            $bitLockerAvailable = $true
            $bitLocker = Get-BitLockerVolume `
                -MountPoint $env:SystemDrive `
                -ErrorAction Stop
            $bitLockerProtectionStatus = [string]$bitLocker.ProtectionStatus
            $bitLockerVolumeStatus = [string]$bitLocker.VolumeStatus
        }
    }
    catch {
        $bitLockerError = $_.Exception.Message
    }

    $cbsRebootPending = Test-Path `
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    $windowsUpdateRebootPending = Test-Path `
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    $pendingFileRename = $false

    try {
        $sessionManager = Get-ItemProperty `
            'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
            -Name PendingFileRenameOperations `
            -ErrorAction Stop
        $pendingFileRename = $null -ne $sessionManager.PendingFileRenameOperations
    }
    catch {
        Write-Verbose (
            'PendingFileRenameOperations nao encontrado: ' +
            $_.Exception.Message
        )
    }

    $officeInfo = Get-ToolkitOfficeInstallInformation
    $officeProcessNames = @(
        'WINWORD',
        'EXCEL',
        'OUTLOOK',
        'POWERPNT',
        'ONENOTE',
        'MSACCESS',
        'MSPUB',
        'VISIO',
        'WINPROJ',
        'Teams',
        'ms-teams'
    )
    $officeProcesses = @(
        Get-Process `
            -Name $officeProcessNames `
            -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty ProcessName -Unique
    )

    $aadPackage = $null
    $cloudExperiencePackage = $null
    $wamPackageError = $null

    try {
        $aadPackage = Get-AppxPackage `
            -Name Microsoft.AAD.BrokerPlugin `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1
        $cloudExperiencePackage = Get-AppxPackage `
            -Name Microsoft.Windows.CloudExperienceHost `
            -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    catch {
        $wamPackageError = $_.Exception.Message
    }

    $aadManifest = Join-Path `
        $env:windir `
        'SystemApps\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\Appxmanifest.xml'
    $cloudManifest = Join-Path `
        $env:windir `
        'SystemApps\Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy\Appxmanifest.xml'
    $aadTokenPath = Join-Path `
        $env:LOCALAPPDATA `
        'Packages\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\AC\TokenBroker\Accounts'
    $cloudTokenPath = Join-Path `
        $env:LOCALAPPDATA `
        'Packages\Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy\AC\TokenBroker\Accounts'

    $aadTokenCount = 0
    $cloudTokenCount = 0

    try {
        if (Test-Path -LiteralPath $aadTokenPath -PathType Container) {
            $aadTokenCount = @(
                Get-ChildItem `
                    -LiteralPath $aadTokenPath `
                    -File `
                    -Force `
                    -ErrorAction SilentlyContinue
            ).Count
        }

        if (Test-Path -LiteralPath $cloudTokenPath -PathType Container) {
            $cloudTokenCount = @(
                Get-ChildItem `
                    -LiteralPath $cloudTokenPath `
                    -File `
                    -Force `
                    -ErrorAction SilentlyContinue
            ).Count
        }
    }
    catch {
        Write-Verbose (
            'Nao foi possivel consultar os caches WAM: ' +
            $_.Exception.Message
        )
    }

    $dsregCommandAvailable = $false
    $dsregExitCode = $null
    $dsregError = $null
    $dsregText = ''

    try {
        $dsregPath = Join-Path $env:SystemRoot 'System32\dsregcmd.exe'

        if (Test-Path -LiteralPath $dsregPath -PathType Leaf) {
            $dsregCommandAvailable = $true
            $dsregRaw = & $dsregPath /status 2>&1
            $dsregExitCode = $LASTEXITCODE
            $dsregText = $dsregRaw | Out-String
        }
    }
    catch {
        $dsregError = $_.Exception.Message
    }

    $credentialCount = 0
    $credentialQueryError = $null

    try {
        $cmdkeyPath = Join-Path $env:SystemRoot 'System32\cmdkey.exe'
        $credentialText = (& $cmdkeyPath /list 2>&1) | Out-String
        $credentialCount = @(
            [regex]::Matches(
                $credentialText,
                '(?im)^\s*(?:Target|Alvo)\s*:.*(?:MicrosoftOffice16|MicrosoftOffice|ADAL|OneAuth).*$'
            )
        ).Count
    }
    catch {
        $credentialQueryError = $_.Exception.Message
    }

    $licenseRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Office\Licenses'
    $licenseFileCount = 0

    try {
        if (Test-Path -LiteralPath $licenseRoot -PathType Container) {
            $licenseFileCount = @(
                Get-ChildItem `
                    -LiteralPath $licenseRoot `
                    -File `
                    -Recurse `
                    -ErrorAction SilentlyContinue
            ).Count
        }
    }
    catch {
        Write-Verbose (
            'Nao foi possivel contar arquivos de licenca: ' +
            $_.Exception.Message
        )
    }

    $licenseCheckRan = $false
    $licenseCheckExitCode = $null
    $licenseLooksLicensed = $false
    $licenseLooksUnlicensed = $false
    $licenseCheckError = $null

    if (-not [string]::IsNullOrWhiteSpace($officeInfo.VNextDiagPath)) {
        try {
            $licenseCheckRaw = & powershell.exe `
                -NoProfile `
                -ExecutionPolicy Bypass `
                -File $officeInfo.VNextDiagPath `
                -action list 2>&1
            $licenseCheckExitCode = $LASTEXITCODE
            $licenseCheckText = $licenseCheckRaw | Out-String
            $licenseCheckRan = $true
            $licenseLooksLicensed = $licenseCheckText -match '(?im)\bLicensed\b|\bLicenciado\b'
            $licenseLooksUnlicensed = $licenseCheckText -match '(?im)\bUnlicensed\b|\bUnlicensedProduct\b|\bNao licenciado\b|\bNão licenciado\b'
        }
        catch {
            $licenseCheckError = $_.Exception.Message
        }
    }

    $officeEdition = [string]$officeInfo.Edition
    $officeLicensingModel = if ($officeEdition -eq 'Microsoft 365 Apps') {
        'Assinatura moderna (vnextdiag)'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($officeInfo.OsppPath)) {
        'Perpetuo ou volume (OSPP)'
    }
    else {
        'Nao identificado'
    }
    $osppCheckRan = $false
    $osppExitCode = $null
    $osppProductCount = 0
    $osppLicensedCount = 0
    $osppUnlicensedCount = 0
    $osppGraceCount = 0
    $osppLicenseNames = [string[]]@()
    $osppLicenseStatuses = [string[]]@()
    $osppErrorCodes = [string[]]@()
    $osppActivationType = $null
    $osppCheckError = $null

    if (
        $officeEdition -ne 'Microsoft 365 Apps' -and
        -not [string]::IsNullOrWhiteSpace($officeInfo.OsppPath)
    ) {
        try {
            $cscriptPath = Join-Path $env:SystemRoot 'System32\cscript.exe'
            $osppRaw = & $cscriptPath //NoLogo $officeInfo.OsppPath /dstatusall 2>&1
            $osppExitCode = $LASTEXITCODE
            $osppText = $osppRaw | Out-String
            $osppCheckRan = $true

            $osppLicenseNames = [string[]]@(
                [regex]::Matches(
                    $osppText,
                    '(?im)^\s*(?:LICENSE NAME|NOME DA LICEN[CÇ]A)\s*:\s*(.+?)\s*$'
                ) |
                    ForEach-Object { $_.Groups[1].Value.Trim() } |
                    Select-Object -Unique
            )
            $osppLicenseStatuses = [string[]]@(
                [regex]::Matches(
                    $osppText,
                    '(?im)^\s*(?:LICENSE STATUS|STATUS DA LICEN[CÇ]A|ESTADO DA LICEN[CÇ]A)\s*:\s*(.+?)\s*$'
                ) |
                    ForEach-Object {
                        $_.Groups[1].Value.Trim().Trim('-').Trim()
                    } |
                    Select-Object -Unique
            )
            $osppErrorCodes = [string[]]@(
                [regex]::Matches($osppText, '(?i)\b0x[0-9a-f]{8}\b') |
                    ForEach-Object { $_.Value.ToUpperInvariant() } |
                    Select-Object -Unique
            )
            $osppProductCount = [math]::Max(
                $osppLicenseNames.Count,
                $osppLicenseStatuses.Count
            )
            $osppLicensedCount = @(
                $osppLicenseStatuses |
                    Where-Object {
                        $_ -match '(?i)^(?:LICENSED|LICENCIADO)$'
                    }
            ).Count
            $osppUnlicensedCount = @(
                $osppLicenseStatuses |
                    Where-Object {
                        $_ -notmatch '(?i)^(?:LICENSED|LICENCIADO)$'
                    }
            ).Count
            $osppGraceCount = @(
                $osppLicenseStatuses |
                    Where-Object {
                        $_ -match '(?i)(?:GRACE|NOTIFICATION|NOTIFIC)'
                    }
            ).Count
            $osppNameEvidence = $osppLicenseNames -join ' '
            $osppActivationType = if ($osppNameEvidence -match '(?i)KMS') {
                'KMS'
            }
            elseif ($osppNameEvidence -match '(?i)MAK') {
                'MAK'
            }
            elseif ($osppNameEvidence -match '(?i)RETAIL') {
                'Retail'
            }
            else {
                'OSPP'
            }
            $officeEdition = Get-ToolkitOfficeEdition -ProductReleaseIds $officeInfo.ProductReleaseIds -LicenseNames $osppLicenseNames
        }
        catch {
            $osppCheckError = $_.Exception.Message
        }
    }

    $protectionPolicy = $null

    try {
        $policy = Get-ItemProperty `
            -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography\Protect\Providers\df9d8cd0-1501-11d1-8c7a-00c04fc297eb' `
            -Name ProtectionPolicy `
            -ErrorAction Stop
        $protectionPolicy = [int]$policy.ProtectionPolicy
    }
    catch {
        Write-Verbose (
            'ProtectionPolicy nao configurada: ' +
            $_.Exception.Message
        )
    }

    $eventStart = $ObservedAt.AddDays(-1 * [math]::Abs($EventLookbackDays))
    $wamEvents = Get-ToolkitOfficeEventSummary `
        -LogName 'Application' `
        -ProviderName 'AppModel-State' `
        -MessagePatterns @(
            'Microsoft\.AAD\.BrokerPlugin',
            'Microsoft\.Windows\.CloudExperienceHost'
        ) `
        -StartTime $eventStart
    $aadEvents = Get-ToolkitOfficeEventSummary `
        -LogName 'Microsoft-Windows-AAD/Operational' `
        -StartTime $eventStart
    $tpmEvents = Get-ToolkitOfficeEventSummary `
        -LogName 'System' `
        -ProviderName 'Microsoft-Windows-TPM-WMI' `
        -StartTime $eventStart

    $tpmSource = if ($null -ne $tpm) { $tpm } else { $wmiTpm }
    $tpmQueryMethod = if ($null -ne $tpm) {
        'Get-Tpm'
    }
    elseif ($null -ne $wmiTpm) {
        'Win32_Tpm'
    }
    elseif ($null -ne $tpmToolPresent) {
        'tpmtool'
    }
    else {
        'Indisponivel'
    }
    $tpmEnabledProperty = if ($null -ne $tpm) {
        'TpmEnabled'
    }
    else {
        'IsEnabled_InitialValue'
    }
    $tpmActivatedProperty = if ($null -ne $tpm) {
        'TpmActivated'
    }
    else {
        'IsActivated_InitialValue'
    }
    $tpmOwnedProperty = if ($null -ne $tpm) {
        'TpmOwned'
    }
    else {
        'IsOwned_InitialValue'
    }
    $tpmEnabled = if ($null -ne $tpmSource) {
        [bool](
            Get-ToolkitObjectPropertyValue `
                -InputObject $tpmSource `
                -Name $tpmEnabledProperty `
                -DefaultValue $false
        )
    }
    else {
        [bool]$tpmToolPresent
    }
    $tpmActivated = if ($null -ne $tpmSource) {
        [bool](
            Get-ToolkitObjectPropertyValue `
                -InputObject $tpmSource `
                -Name $tpmActivatedProperty `
                -DefaultValue $false
        )
    }
    else {
        $tpmToolInitialized
    }
    $tpmOwned = if ($null -ne $tpmSource) {
        [bool](
            Get-ToolkitObjectPropertyValue `
                -InputObject $tpmSource `
                -Name $tpmOwnedProperty `
                -DefaultValue $false
        )
    }
    else {
        $tpmToolInitialized
    }
    $tpmReady = if ($null -ne $tpm) {
        [bool](
            Get-ToolkitObjectPropertyValue `
                -InputObject $tpm `
                -Name 'TpmReady' `
                -DefaultValue $false
        )
    }
    elseif ($null -ne $wmiTpm) {
        ($tpmEnabled -and $tpmActivated -and $tpmOwned)
    }
    else {
        (
            [bool]$tpmToolPresent -and
            $tpmToolInitialized -and
            $tpmToolReadyForStorage
        )
    }

    return [pscustomobject]@{
        ObservedAt = $ObservedAt
        TpmCommandAvailable = $tpmCommandAvailable
        TpmToolAvailable = $tpmToolAvailable
        TpmToolExitCode = $tpmToolExitCode
        TpmQueryMethod = $tpmQueryMethod
        TpmPresent = if ($null -ne $tpmSource) {
            $true
        }
        else {
            [bool]$tpmToolPresent
        }
        TpmEnabled = $tpmEnabled
        TpmActivated = $tpmActivated
        TpmOwned = $tpmOwned
        TpmReady = $tpmReady
        TpmAutoProvisioning = [string](
            Get-ToolkitObjectPropertyValue `
                -InputObject $tpm `
                -Name 'AutoProvisioning'
        )
        TpmSpecVersion = $tpmSpecVersion
        TpmManufacturer = $tpmManufacturer
        TpmError = $tpmError
        BitLockerAvailable = $bitLockerAvailable
        BitLockerProtectionStatus = $bitLockerProtectionStatus
        BitLockerVolumeStatus = $bitLockerVolumeStatus
        BitLockerError = $bitLockerError
        CbsRebootPending = $cbsRebootPending
        WindowsUpdateRebootPending = $windowsUpdateRebootPending
        PendingFileRenameOperations = $pendingFileRename
        RebootPending = (
            $cbsRebootPending -or
            $windowsUpdateRebootPending -or
            $pendingFileRename
        )
        OfficeInstalled = [bool]$officeInfo.Installed
        OfficeProductReleaseIds = $officeInfo.ProductReleaseIds
        OfficePlatform = $officeInfo.Platform
        OfficeVersion = $officeInfo.Version
        OfficeEdition = $officeEdition
        OfficeLicensingModel = $officeLicensingModel
        VNextDiagPath = $officeInfo.VNextDiagPath
        OsppPath = $officeInfo.OsppPath
        OsppCheckRan = $osppCheckRan
        OsppExitCode = $osppExitCode
        OsppProductCount = $osppProductCount
        OsppLicensedCount = $osppLicensedCount
        OsppUnlicensedCount = $osppUnlicensedCount
        OsppGraceCount = $osppGraceCount
        OsppLicenseStatuses = [string[]]$osppLicenseStatuses
        OsppErrorCodes = [string[]]$osppErrorCodes
        OsppActivationType = $osppActivationType
        OsppCheckError = $osppCheckError
        OfficeProcesses = [string[]]$officeProcesses
        AadBrokerPackagePresent = ($null -ne $aadPackage)
        CloudExperiencePackagePresent = ($null -ne $cloudExperiencePackage)
        AadBrokerManifestPresent = Test-Path -LiteralPath $aadManifest -PathType Leaf
        CloudExperienceManifestPresent = Test-Path -LiteralPath $cloudManifest -PathType Leaf
        WamPackageError = $wamPackageError
        AadTokenCachePresent = Test-Path -LiteralPath $aadTokenPath -PathType Container
        CloudTokenCachePresent = Test-Path -LiteralPath $cloudTokenPath -PathType Container
        AadTokenFileCount = $aadTokenCount
        CloudTokenFileCount = $cloudTokenCount
        DsRegCommandAvailable = $dsregCommandAvailable
        DsRegExitCode = $dsregExitCode
        DsRegError = $dsregError
        AzureAdJoined = Get-ToolkitDsRegField -Text $dsregText -Name 'AzureAdJoined'
        EnterpriseJoined = Get-ToolkitDsRegField -Text $dsregText -Name 'EnterpriseJoined'
        DomainJoined = Get-ToolkitDsRegField -Text $dsregText -Name 'DomainJoined'
        WorkplaceJoined = Get-ToolkitDsRegField -Text $dsregText -Name 'WorkplaceJoined'
        WamDefaultSet = Get-ToolkitDsRegField -Text $dsregText -Name 'WamDefaultSet'
        AzureAdPrt = Get-ToolkitDsRegField -Text $dsregText -Name 'AzureAdPrt'
        TpmProtected = Get-ToolkitDsRegField -Text $dsregText -Name 'TpmProtected'
        DeviceAuthStatus = Get-ToolkitDsRegField -Text $dsregText -Name 'DeviceAuthStatus'
        NgcSet = Get-ToolkitDsRegField -Text $dsregText -Name 'NgcSet'
        KeySignTest = Get-ToolkitDsRegField -Text $dsregText -Name 'KeySignTest'
        OfficeCredentialCount = $credentialCount
        CredentialQueryError = $credentialQueryError
        OfficeLicenseFileCount = $licenseFileCount
        LicenseCheckRan = $licenseCheckRan
        LicenseCheckExitCode = $licenseCheckExitCode
        LicenseLooksLicensed = $licenseLooksLicensed
        LicenseLooksUnlicensed = $licenseLooksUnlicensed
        LicenseCheckError = $licenseCheckError
        ProtectionPolicy = $protectionPolicy
        WamEvents = $wamEvents
        AadEvents = $aadEvents
        TpmEvents = $tpmEvents
    }
}

function New-ToolkitOfficeRemediation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code,
        [Parameter(Mandatory = $true)]
        [string]$Risk,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$Details,
        [bool]$Automatable = $false,
        [bool]$RequiresRestart = $false
    )

    return [pscustomobject]@{
        Code = $Code
        Risk = $Risk
        Title = $Title
        Details = $Details
        Automatable = $Automatable
        RequiresRestart = $RequiresRestart
    }
}

function Get-ToolkitOfficeTpmAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Snapshot
    )

    $observations = New-Object 'System.Collections.Generic.List[string]'
    $actions = New-Object 'System.Collections.Generic.List[object]'
    $severity = 'Informativo'

    if (-not $Snapshot.OfficeInstalled) {
        $observations.Add('Microsoft Office nao foi detectado nos caminhos e no registro padrao.')
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'OFFICE_NOT_FOUND' `
            -Risk 'Baixo' `
            -Title 'Confirmar instalacao e edicao do Office' `
            -Details 'Validar se o equipamento usa Microsoft 365 Apps, Office LTSC ou instalacao personalizada.'))
    }

    if ($Snapshot.RebootPending) {
        $severity = 'Atencao'
        $observations.Add('O Windows possui reinicializacao ou operacoes de arquivos pendentes.')
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'RESTART_PENDING' `
            -Risk 'Baixo' `
            -Title 'Reiniciar antes de alterar autenticacao' `
            -Details 'Salvar o trabalho do usuario, reiniciar o Windows e repetir o diagnostico.' `
            -RequiresRestart $true))
    }

    if (-not $Snapshot.TpmPresent) {
        $severity = 'Critico'
        $observations.Add('TPM nao foi detectado pelo Windows ou Get-Tpm falhou.')
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'TPM_NOT_FOUND' `
            -Risk 'Alto' `
            -Title 'Validar TPM no Windows e no firmware' `
            -Details 'Abrir tpm.msc, verificar BIOS/UEFI e atualizar firmware conforme o fabricante. Nao limpar o TPM automaticamente.'))
    }
    elseif (
        -not $Snapshot.TpmReady -or
        -not $Snapshot.TpmEnabled -or
        -not $Snapshot.TpmActivated
    ) {
        $severity = 'Critico'
        $observations.Add('TPM presente, mas nao esta pronto, habilitado e ativado ao mesmo tempo.')
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'TPM_NOT_READY' `
            -Risk 'Alto' `
            -Title 'Corrigir provisionamento do TPM' `
            -Details 'Validar tpm.msc, firmware e conectividade corporativa. Limpar TPM somente como ultimo recurso, com chave BitLocker e aprovacao.' `
            -RequiresRestart $true))
    }

    if (
        -not $Snapshot.AadBrokerManifestPresent -or
        -not $Snapshot.CloudExperienceManifestPresent
    ) {
        $severity = 'Critico'
        $observations.Add('Um ou mais manifestos WAM do Windows nao foram encontrados.')
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'WAM_MANIFEST_MISSING' `
            -Risk 'Medio' `
            -Title 'Reparar componentes do Windows antes do WAM' `
            -Details 'Executar Windows Update e, se necessario, DISM/SFC. O toolkit nao deve registrar um pacote sem o manifesto oficial.'))
    }
    elseif (
        -not $Snapshot.AadBrokerPackagePresent -or
        -not $Snapshot.CloudExperiencePackagePresent
    ) {
        if ($severity -ne 'Critico') {
            $severity = 'Atencao'
        }

        $observations.Add('Um ou mais pacotes WAM nao estao registrados no perfil do usuario.')
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'WAM_PACKAGE_MISSING' `
            -Risk 'Medio' `
            -Title 'Reparar login do Office (WAM)' `
            -Details 'Fechar Office e registrar novamente AAD BrokerPlugin e CloudExperienceHost no perfil afetado.' `
            -Automatable $true))
    }

    if ($Snapshot.WamEvents.Count -gt 0) {
        if ($severity -eq 'Informativo') {
            $severity = 'Atencao'
        }

        $observations.Add("Foram encontrados $($Snapshot.WamEvents.Count) evento(s) AppModel-State relacionado(s) ao WAM.")
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'WAM_EVENTS' `
            -Risk 'Medio' `
            -Title 'Reparar WAM e revisar software de seguranca' `
            -Details 'Registrar novamente os pacotes WAM. Se o erro voltar, revisar antivirus, proxy e drivers WFP conforme a Microsoft.' `
            -Automatable $true))
    }

    if (
        -not [string]::IsNullOrWhiteSpace($Snapshot.DeviceAuthStatus) -and
        $Snapshot.DeviceAuthStatus -notmatch '^SUCCESS'
    ) {
        $severity = 'Critico'
        $observations.Add("Identidade do dispositivo no Entra apresenta estado: $($Snapshot.DeviceAuthStatus).")
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'DEVICE_AUTH_FAILED' `
            -Risk 'Alto' `
            -Title 'Validar o objeto do dispositivo no Microsoft Entra' `
            -Details 'Confirmar se o dispositivo existe e esta habilitado. Recuperacao ou novo registro dependem do tipo de ingresso e do administrador do tenant.' `
            -RequiresRestart $true))
    }

    if (
        $Snapshot.AzureAdJoined -eq 'YES' -and
        $Snapshot.AzureAdPrt -eq 'NO'
    ) {
        if ($severity -ne 'Critico') {
            $severity = 'Atencao'
        }

        $observations.Add('Dispositivo ingressado no Entra sem PRT do usuario.')
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'PRT_MISSING' `
            -Risk 'Medio' `
            -Title 'Recuperar sessao do usuario' `
            -Details 'Bloquear/desbloquear ou sair/entrar no Windows e revisar os diagnosticos PRT do dsregcmd.'))
    }

    if (
        ($Snapshot.AzureAdJoined -eq 'YES' -or $Snapshot.WorkplaceJoined -eq 'YES') -and
        $Snapshot.WamDefaultSet -eq 'NO'
    ) {
        if ($severity -ne 'Critico') {
            $severity = 'Atencao'
        }

        $observations.Add('Conta WAM padrao nao esta configurada para o usuario afetado.')
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'WAM_DEFAULT_MISSING' `
            -Risk 'Medio' `
            -Title 'Revisar conta corporativa e WAM' `
            -Details 'Executar o diagnostico no contexto do usuario afetado, reparar WAM e revisar Acessar trabalho ou escola.'))
    }

    if ($Snapshot.OfficeCredentialCount -gt 0) {
        $observations.Add("Existem $($Snapshot.OfficeCredentialCount) credencial(is) do Office/ADAL/OneAuth no Gerenciador de Credenciais.")
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'OFFICE_CREDENTIALS' `
            -Risk 'Medio' `
            -Title 'Remover somente credenciais antigas do Office' `
            -Details 'Usar o Gerenciador de Credenciais e remover entradas MicrosoftOffice16 somente após confirmar a conta afetada. O usuario precisara entrar novamente.'))
    }

    if ($Snapshot.LicenseLooksUnlicensed) {
        if ($severity -ne 'Critico') {
            $severity = 'Atencao'
        }

        $observations.Add('O vnextdiag encontrou indicio de produto nao licenciado.')
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'OFFICE_UNLICENSED' `
            -Risk 'Medio' `
            -Title 'Redefinir a licenca especifica do Microsoft 365 Apps' `
            -Details 'Listar licencas com vnextdiag e remover somente o LicenseId afetado; depois autenticar novamente.'))
    }

    if (
        $Snapshot.OsppCheckRan -and
        $Snapshot.OsppUnlicensedCount -gt 0
    ) {
        if ($severity -ne 'Critico') {
            $severity = 'Atencao'
        }

        $observations.Add(
            "O OSPP encontrou $($Snapshot.OsppUnlicensedCount) produto(s) sem estado LICENSED."
        )
        $actions.Add((New-ToolkitOfficeRemediation -Code 'OSPP_UNLICENSED' -Risk 'Medio' -Title 'Corrigir ativacao do Office 2016, 2019 ou 2021' -Details 'Usar ospp.vbs /dstatusall e /ddescr para identificar o erro. Validar KMS, DNS, proxy ou MAK e executar /act somente com autorizacao. Nao remover chaves automaticamente.'))
    }

    if (
        -not [string]::IsNullOrWhiteSpace($Snapshot.OsppPath) -and
        -not $Snapshot.OsppCheckRan -and
        -not [string]::IsNullOrWhiteSpace($Snapshot.OsppCheckError)
    ) {
        if ($severity -eq 'Informativo') {
            $severity = 'Atencao'
        }

        $observations.Add('O OSPP foi localizado, mas o estado de ativacao nao pôde ser consultado.')
        $actions.Add((New-ToolkitOfficeRemediation -Code 'OSPP_CHECK_FAILED' -Risk 'Baixo' -Title 'Executar o diagnostico OSPP com elevacao' -Details 'Abrir PowerShell como administrador, repetir o painel e preservar o codigo de erro.'))
    }

    if ($Snapshot.OfficeEdition -in @('Office 2016', 'Office 2019')) {
        if ($severity -eq 'Informativo') {
            $severity = 'Atencao'
        }

        $observations.Add("$($Snapshot.OfficeEdition) esta fora do suporte da Microsoft desde 14/10/2025.")
        $actions.Add((New-ToolkitOfficeRemediation -Code 'OFFICE_END_OF_SUPPORT' -Risk 'Medio' -Title 'Planejar atualizacao da versao do Office' -Details 'O reparo local pode recuperar o login, mas a versao nao recebe mais correcoes de seguranca ou produto.'))
    }
    elseif ($Snapshot.OfficeEdition -eq 'Office 2021') {
        $observations.Add('Office 2021 foi identificado; o suporte termina em 13/10/2026.')
        $actions.Add((New-ToolkitOfficeRemediation -Code 'OFFICE_2021_LIFECYCLE' -Risk 'Baixo' -Title 'Registrar o ciclo de vida do Office 2021' -Details 'Manter o Office atualizado e planejar migracao antes do fim do suporte.'))
    }

    if (
        $Snapshot.OfficeInstalled -and
        [string]::IsNullOrWhiteSpace($Snapshot.VNextDiagPath) -and
        [string]::IsNullOrWhiteSpace($Snapshot.OsppPath)
    ) {
        $observations.Add('vnextdiag.ps1 nao foi encontrado; a edicao pode ser LTSC, volume ou anterior ao metodo moderno.')
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'VNEXT_NOT_FOUND' `
            -Risk 'Baixo' `
            -Title 'Identificar o modelo de licenciamento do Office' `
            -Details 'Usar vnextdiag para Microsoft 365 Apps moderno e ospp.vbs somente para edicoes perpetuas ou por volume compativeis.'))
    }

    if (
        $observations.Count -eq 0 -and
        $Snapshot.OfficeInstalled -and
        $Snapshot.TpmReady -and
        $Snapshot.AadBrokerPackagePresent -and
        $Snapshot.CloudExperiencePackagePresent
    ) {
        $observations.Add('TPM, WAM e instalacao do Office nao apresentam alerta evidente nos testes basicos.')
        $actions.Add((New-ToolkitOfficeRemediation `
            -Code 'COLLECT_EXACT_ERROR' `
            -Risk 'Baixo' `
            -Title 'Coletar codigo e contexto exatos' `
            -Details 'Registrar codigo completo, aplicativo, usuario afetado e momento do erro antes de redefinir credenciais ou ativacao.'))
    }

    return [pscustomobject]@{
        Severity = $severity
        HasObservations = ($observations.Count -gt 0)
        Observations = [string[]]$observations.ToArray()
        Remediations = [object[]]$actions.ToArray()
    }
}

function Format-ToolkitOfficeTpmReport {
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

    $yesNo = {
        param([bool]$Value)
        if ($Value) { return 'Sim' }
        return 'Nao'
    }
    $valueOrUnknown = {
        param($Value)
        if ([string]::IsNullOrWhiteSpace([string]$Value)) {
            return 'Nao identificado'
        }
        return [string]$Value
    }
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine('OFFICE / TPM / AUTENTICACAO - DIAGNOSTICO CONSOLIDADO')
    [void]$sb.AppendLine('=====================================================')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Gerado em: $($GeneratedAt.ToString('dd/MM/yyyy HH:mm:ss'))")
    [void]$sb.AppendLine("Hostname: $ComputerName")
    [void]$sb.AppendLine("Usuario avaliado: $UserName")
    [void]$sb.AppendLine("Admin: $(if ($IsAdministrator) { 'Sim' } else { 'Nao' })")
    [void]$sb.AppendLine('Tipo de acao: Diagnostico somente leitura')
    [void]$sb.AppendLine("Severidade: $($Assessment.Severity)")
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('TPM E PROTECAO DO DISCO')
    [void]$sb.AppendLine('------------------------')
    [void]$sb.AppendLine("TPM detectado: $(& $yesNo $Snapshot.TpmPresent)")
    [void]$sb.AppendLine("Metodo de consulta: $(& $valueOrUnknown $Snapshot.TpmQueryMethod)")
    [void]$sb.AppendLine("TPM pronto: $(& $yesNo $Snapshot.TpmReady)")
    [void]$sb.AppendLine("TPM habilitado: $(& $yesNo $Snapshot.TpmEnabled)")
    [void]$sb.AppendLine("TPM ativado: $(& $yesNo $Snapshot.TpmActivated)")
    [void]$sb.AppendLine("TPM provisionado: $(& $yesNo $Snapshot.TpmOwned)")
    [void]$sb.AppendLine("Versao TPM: $(& $valueOrUnknown $Snapshot.TpmSpecVersion)")
    [void]$sb.AppendLine("Fabricante TPM: $(& $valueOrUnknown $Snapshot.TpmManufacturer)")
    [void]$sb.AppendLine("BitLocker: $(& $valueOrUnknown $Snapshot.BitLockerProtectionStatus)")
    [void]$sb.AppendLine("Estado do volume: $(& $valueOrUnknown $Snapshot.BitLockerVolumeStatus)")
    [void]$sb.AppendLine("Reinicio pendente: $(& $yesNo $Snapshot.RebootPending)")
    [void]$sb.AppendLine('Observacao: nenhuma chave BitLocker e exibida ou coletada.')
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('OFFICE E LICENCIAMENTO')
    [void]$sb.AppendLine('----------------------')
    [void]$sb.AppendLine("Office detectado: $(& $yesNo $Snapshot.OfficeInstalled)")
    [void]$sb.AppendLine("Produto: $(& $valueOrUnknown $Snapshot.OfficeProductReleaseIds)")
    [void]$sb.AppendLine("Edicao identificada: $(& $valueOrUnknown $Snapshot.OfficeEdition)")
    [void]$sb.AppendLine("Modelo de licenciamento: $(& $valueOrUnknown $Snapshot.OfficeLicensingModel)")
    [void]$sb.AppendLine("Plataforma: $(& $valueOrUnknown $Snapshot.OfficePlatform)")
    [void]$sb.AppendLine("Versao: $(& $valueOrUnknown $Snapshot.OfficeVersion)")
    [void]$sb.AppendLine("vnextdiag disponivel: $(& $yesNo (-not [string]::IsNullOrWhiteSpace($Snapshot.VNextDiagPath)))")
    [void]$sb.AppendLine("OSPP disponivel: $(& $yesNo (-not [string]::IsNullOrWhiteSpace($Snapshot.OsppPath)))")
    [void]$sb.AppendLine("OSPP consultado: $(& $yesNo $Snapshot.OsppCheckRan)")
    [void]$sb.AppendLine("Tipo de ativacao OSPP: $(& $valueOrUnknown $Snapshot.OsppActivationType)")
    [void]$sb.AppendLine("Produtos OSPP: $($Snapshot.OsppProductCount)")
    [void]$sb.AppendLine("Produtos OSPP licenciados: $($Snapshot.OsppLicensedCount)")
    [void]$sb.AppendLine("Produtos OSPP com alerta: $($Snapshot.OsppUnlicensedCount)")
    [void]$sb.AppendLine("Status OSPP: $(if (@($Snapshot.OsppLicenseStatuses).Count) { @($Snapshot.OsppLicenseStatuses) -join ', ' } else { 'Nao consultado' })")
    [void]$sb.AppendLine("Codigos OSPP: $(if (@($Snapshot.OsppErrorCodes).Count) { @($Snapshot.OsppErrorCodes) -join ', ' } else { 'Nenhum' })")
    [void]$sb.AppendLine("Arquivos de licenca modernos: $($Snapshot.OfficeLicenseFileCount)")
    [void]$sb.AppendLine("Verificacao de licenca moderna: $(& $yesNo $Snapshot.LicenseCheckRan)")
    [void]$sb.AppendLine("Indicio de licenca moderna valida: $(& $yesNo $Snapshot.LicenseLooksLicensed)")
    [void]$sb.AppendLine("Indicio de produto moderno nao licenciado: $(& $yesNo $Snapshot.LicenseLooksUnlicensed)")
    [void]$sb.AppendLine('Observacao: nenhuma chave de produto completa ou parcial e registrada no relatorio.')
    [void]$sb.AppendLine("Aplicativos Office abertos: $(if (@($Snapshot.OfficeProcesses).Count) { @($Snapshot.OfficeProcesses) -join ', ' } else { 'Nenhum' })")
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('WAM / AAD BROKER')
    [void]$sb.AppendLine('----------------')
    [void]$sb.AppendLine("AAD BrokerPlugin registrado: $(& $yesNo $Snapshot.AadBrokerPackagePresent)")
    [void]$sb.AppendLine("CloudExperienceHost registrado: $(& $yesNo $Snapshot.CloudExperiencePackagePresent)")
    [void]$sb.AppendLine("Manifesto AAD BrokerPlugin: $(& $yesNo $Snapshot.AadBrokerManifestPresent)")
    [void]$sb.AppendLine("Manifesto CloudExperienceHost: $(& $yesNo $Snapshot.CloudExperienceManifestPresent)")
    [void]$sb.AppendLine("Cache AAD presente: $(& $yesNo $Snapshot.AadTokenCachePresent)")
    [void]$sb.AppendLine("Cache Cloud presente: $(& $yesNo $Snapshot.CloudTokenCachePresent)")
    [void]$sb.AppendLine("Credenciais Office/ADAL/OneAuth detectadas: $($Snapshot.OfficeCredentialCount)")
    [void]$sb.AppendLine("Eventos WAM com erro/aviso: $($Snapshot.WamEvents.Count)")
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('ENTRA ID E SSO')
    [void]$sb.AppendLine('--------------')
    [void]$sb.AppendLine("AzureAdJoined: $(& $valueOrUnknown $Snapshot.AzureAdJoined)")
    [void]$sb.AppendLine("DomainJoined: $(& $valueOrUnknown $Snapshot.DomainJoined)")
    [void]$sb.AppendLine("WorkplaceJoined: $(& $valueOrUnknown $Snapshot.WorkplaceJoined)")
    [void]$sb.AppendLine("DeviceAuthStatus: $(& $valueOrUnknown $Snapshot.DeviceAuthStatus)")
    [void]$sb.AppendLine("WamDefaultSet: $(& $valueOrUnknown $Snapshot.WamDefaultSet)")
    [void]$sb.AppendLine("AzureAdPrt: $(& $valueOrUnknown $Snapshot.AzureAdPrt)")
    [void]$sb.AppendLine("Chave do dispositivo protegida por TPM: $(& $valueOrUnknown $Snapshot.TpmProtected)")
    [void]$sb.AppendLine("Windows Hello configurado: $(& $valueOrUnknown $Snapshot.NgcSet)")
    [void]$sb.AppendLine("KeySignTest: $(& $valueOrUnknown $Snapshot.KeySignTest)")
    [void]$sb.AppendLine("Eventos AAD com erro/aviso: $($Snapshot.AadEvents.Count)")
    [void]$sb.AppendLine("Eventos TPM-WMI com erro/aviso: $($Snapshot.TpmEvents.Count)")
    [void]$sb.AppendLine('')

    [void]$sb.AppendLine('CONCLUSAO AUTOMATICA')
    [void]$sb.AppendLine('--------------------')

    foreach ($observation in @($Assessment.Observations)) {
        [void]$sb.AppendLine("- $observation")
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('PLANO DE CORRECAO PRIORIZADO')
    [void]$sb.AppendLine('----------------------------')
    $index = 1

    foreach ($action in @($Assessment.Remediations)) {
        [void]$sb.AppendLine("$index. [$($action.Risk)] $($action.Title)")
        [void]$sb.AppendLine("   $($action.Details)")
        [void]$sb.AppendLine("   Codigo: $($action.Code)")
        $index++
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('ACOES DISPONIVEIS NO TOOLKIT')
    [void]$sb.AppendLine('----------------------------')
    [void]$sb.AppendLine('- Diagnostico Office / TPM: somente leitura.')
    [void]$sb.AppendLine('- Reparar login Office (WAM): registra novamente os pacotes oficiais no perfil atual.')
    [void]$sb.AppendLine('- Gerenciador de Credenciais, Contas corporativas e tpm.msc permanecem acoes guiadas.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('ACOES CRITICAS NAO AUTOMATIZADAS')
    [void]$sb.AppendLine('--------------------------------')
    [void]$sb.AppendLine('- Limpar TPM: pode remover PIN, chaves, certificado e acesso a dados protegidos.')
    [void]$sb.AppendLine('- Desconectar/reingressar no Entra ID: depende do tipo de ingresso e do administrador do tenant.')
    [void]$sb.AppendLine('- Apagar caches ou licencas: exige confirmar usuario, conta e LicenseId afetados.')
    [void]$sb.AppendLine('- Alterar BIOS/UEFI ou firmware: seguir somente o procedimento do fabricante.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('REFERENCIAS OFICIAIS MICROSOFT')
    [void]$sb.AppendLine('------------------------------')
    [void]$sb.AppendLine('- https://learn.microsoft.com/en-us/previous-versions/troubleshoot/microsoft-365/microsoft-365-apps/activation/tpm-malfunctioned')
    [void]$sb.AppendLine('- https://learn.microsoft.com/en-us/previous-versions/troubleshoot/microsoft-365/microsoft-365-apps/activation/cannot-sign-in-microsoft-365-desktop-apps')
    [void]$sb.AppendLine('- https://learn.microsoft.com/en-us/entra/identity/devices/troubleshoot-device-dsregcmd')
    [void]$sb.AppendLine('- https://learn.microsoft.com/en-us/windows/security/hardware-security/tpm/initialize-and-configure-ownership-of-the-tpm')
    [void]$sb.AppendLine('- https://learn.microsoft.com/en-us/microsoft-365-apps/licensing-activation/vnextdiag')
    [void]$sb.AppendLine('- https://learn.microsoft.com/en-us/office/volume-license-activation/tools-to-manage-volume-activation-of-office')
    [void]$sb.AppendLine('- https://learn.microsoft.com/en-us/office/volume-license-activation/troubleshoot-volume-activation-of-office')
    [void]$sb.AppendLine('- https://learn.microsoft.com/en-us/microsoft-365-apps/end-of-support/plan-upgrade-older-versions-office')

    return $sb.ToString()
}

function Repair-ToolkitOfficeWam {
    [CmdletBinding()]
    param(
        [switch]$Confirmed,
        [string]$AuditPath
    )

    if (-not $Confirmed) {
        throw 'Reparo WAM recusado: confirmacao explicita ausente.'
    }

    $officeProcessNames = @(
        'WINWORD',
        'EXCEL',
        'OUTLOOK',
        'POWERPNT',
        'ONENOTE',
        'MSACCESS',
        'MSPUB',
        'VISIO',
        'WINPROJ',
        'Teams',
        'ms-teams'
    )
    $openProcesses = @(
        Get-Process `
            -Name $officeProcessNames `
            -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty ProcessName -Unique
    )

    if ($openProcesses.Count -gt 0) {
        throw (
            'Feche os aplicativos antes do reparo WAM: ' +
            ($openProcesses -join ', ')
        )
    }

    $manifests = [ordered]@{
        AadBrokerPlugin = Join-Path `
            $env:windir `
            'SystemApps\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\Appxmanifest.xml'
        CloudExperienceHost = Join-Path `
            $env:windir `
            'SystemApps\Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy\Appxmanifest.xml'
    }

    foreach ($entry in $manifests.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
            throw "Manifesto oficial ausente para $($entry.Key): $($entry.Value)"
        }
    }

    $startedAt = Get-Date
    $steps = New-Object 'System.Collections.Generic.List[string]'

    foreach ($entry in $manifests.GetEnumerator()) {
        Add-AppxPackage `
            -Register $entry.Value `
            -DisableDevelopmentMode `
            -ForceApplicationShutdown `
            -ErrorAction Stop
        $steps.Add("Pacote registrado: $($entry.Key)")
    }

    $aadAfter = Get-AppxPackage `
        -Name Microsoft.AAD.BrokerPlugin `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $cloudAfter = Get-AppxPackage `
        -Name Microsoft.Windows.CloudExperienceHost `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    $success = ($null -ne $aadAfter -and $null -ne $cloudAfter)
    $completedAt = Get-Date
    $result = [pscustomobject]@{
        Success = $success
        StartedAt = $startedAt
        CompletedAt = $completedAt
        DurationSeconds = [math]::Round(
            ($completedAt - $startedAt).TotalSeconds,
            2
        )
        Steps = [string[]]$steps.ToArray()
        AadBrokerPluginPresent = ($null -ne $aadAfter)
        CloudExperienceHostPresent = ($null -ne $cloudAfter)
        NextAction = (
            'Abrir novamente o Office e autenticar. Se o erro persistir, ' +
            'reiniciar o Windows e executar o diagnostico novamente.'
        )
    }

    if (-not [string]::IsNullOrWhiteSpace($AuditPath)) {
        try {
            $auditFolder = Split-Path $AuditPath -Parent

            if (-not (Test-Path -LiteralPath $auditFolder)) {
                New-Item `
                    -Path $auditFolder `
                    -ItemType Directory `
                    -Force | Out-Null
            }

            [ordered]@{
                timestamp = $completedAt.ToString('o')
                computer = $env:COMPUTERNAME
                user = "$env:USERDOMAIN\$env:USERNAME"
                action = 'RepairOfficeWam'
                success = $success
                durationSeconds = $result.DurationSeconds
            } | ConvertTo-Json -Compress | Add-Content `
                -Path $AuditPath `
                -Encoding UTF8
        }
        catch {
            Write-Verbose (
                'Nao foi possivel registrar a auditoria WAM: ' +
                $_.Exception.Message
            )
        }
    }

    return $result
}

function Format-ToolkitOfficeWamRepairReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Result
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('REPARO DO LOGIN OFFICE - WAM')
    [void]$sb.AppendLine('============================')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Resultado: $(if ($Result.Success) { 'Concluido' } else { 'Nao confirmado' })")
    [void]$sb.AppendLine("Duracao: $($Result.DurationSeconds) segundo(s)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('ACOES EXECUTADAS')
    [void]$sb.AppendLine('----------------')

    foreach ($step in @($Result.Steps)) {
        [void]$sb.AppendLine("- $step")
    }

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("AAD BrokerPlugin presente: $(if ($Result.AadBrokerPluginPresent) { 'Sim' } else { 'Nao' })")
    [void]$sb.AppendLine("CloudExperienceHost presente: $(if ($Result.CloudExperienceHostPresent) { 'Sim' } else { 'Nao' })")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Proxima acao:')
    [void]$sb.AppendLine($Result.NextAction)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Nenhuma credencial, conta Entra ou chave TPM foi removida.')

    return $sb.ToString()
}

Export-ModuleMember -Function @(
    'Get-ToolkitOfficeTpmSnapshot',
    'Get-ToolkitOfficeTpmAssessment',
    'Format-ToolkitOfficeTpmReport',
    'Repair-ToolkitOfficeWam',
    'Format-ToolkitOfficeWamRepairReport'
)
