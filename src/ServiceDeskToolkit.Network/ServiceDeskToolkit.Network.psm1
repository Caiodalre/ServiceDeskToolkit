Set-StrictMode -Version 2.0

function ConvertTo-ToolkitNetworkAdapter {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Adapter
    )

    $ipv4 = @()
    $ipv6 = @()
    $dnsServers = @()
    $gateways = @()

    if ($Adapter.IPAddress) {
        $ipv4 = @(
            $Adapter.IPAddress |
                Where-Object {
                    $_ -match '^\d{1,3}(\.\d{1,3}){3}$'
                }
        )
        $ipv6 = @(
            $Adapter.IPAddress |
                Where-Object {
                    $_ -and
                    $_ -notmatch '^\d{1,3}(\.\d{1,3}){3}$' -and
                    $_ -notlike 'fe80*'
                }
        )
    }

    if ($Adapter.DNSServerSearchOrder) {
        $dnsServers = @($Adapter.DNSServerSearchOrder)
    }

    if ($Adapter.DefaultIPGateway) {
        $gateways = @(
            $Adapter.DefaultIPGateway |
                Where-Object {
                    $_ -and $_ -notlike 'fe80*'
                }
        )
    }

    return [pscustomobject]@{
        Description = [string]$Adapter.Description
        MACAddress = [string]$Adapter.MACAddress
        DHCPEnabled = [bool]$Adapter.DHCPEnabled
        IPv4Addresses = [string[]]$ipv4
        IPv6Addresses = [string[]]$ipv6
        DnsServers = [string[]]$dnsServers
        Gateways = [string[]]$gateways
    }
}

function Get-ToolkitNetworkSnapshot {
    [CmdletBinding()]
    param(
        [datetime]$ObservedAt = (Get-Date)
    )

    $rawAdapters = @(
        Get-CimInstance `
            Win32_NetworkAdapterConfiguration `
            -Filter "IPEnabled=True" `
            -ErrorAction SilentlyContinue
    )
    $adapters = @(
        foreach ($adapter in $rawAdapters) {
            ConvertTo-ToolkitNetworkAdapter -Adapter $adapter
        }
    )

    $primaryRawAdapter = $rawAdapters |
        Where-Object {
            $_.DefaultIPGateway -and $_.IPAddress
        } |
        Select-Object -First 1

    if ($null -eq $primaryRawAdapter) {
        $primaryRawAdapter = $rawAdapters | Select-Object -First 1
    }

    $primaryAdapter = $null

    if ($null -ne $primaryRawAdapter) {
        $primaryAdapter = ConvertTo-ToolkitNetworkAdapter `
            -Adapter $primaryRawAdapter
    }

    $primaryIpv4 = @()
    $primaryGateway = $null
    $primaryDns = @()

    if ($null -ne $primaryAdapter) {
        $primaryIpv4 = @($primaryAdapter.IPv4Addresses)
        $primaryGateway = $primaryAdapter.Gateways |
            Select-Object -First 1
        $primaryDns = @($primaryAdapter.DnsServers)
    }

    $hasAdapter = ($null -ne $primaryAdapter)
    $hasIp = ($primaryIpv4.Count -gt 0)
    $hasGateway = -not [string]::IsNullOrWhiteSpace(
        [string]$primaryGateway
    )
    $hasDns = ($primaryDns.Count -gt 0)

    $gatewayOk = $false

    if ($hasGateway) {
        $gatewayOk = [bool](
            Test-Connection `
                -ComputerName $primaryGateway `
                -Count 1 `
                -Quiet `
                -ErrorAction SilentlyContinue
        )
    }

    $internetCloudflareOk = [bool](
        Test-Connection `
            -ComputerName "1.1.1.1" `
            -Count 1 `
            -Quiet `
            -ErrorAction SilentlyContinue
    )
    $internetGoogleOk = [bool](
        Test-Connection `
            -ComputerName "8.8.8.8" `
            -Count 1 `
            -Quiet `
            -ErrorAction SilentlyContinue
    )

    $dnsMicrosoftOk = $false
    $dnsError = $null

    try {
        $resolved = Resolve-DnsName `
            -Name "www.microsoft.com" `
            -Type A `
            -ErrorAction Stop

        if ($resolved) {
            $dnsMicrosoftOk = $true
        }
    }
    catch {
        $dnsError = $_.Exception.Message
    }

    $routesCommandAvailable = $false
    $routes = @()
    $routesError = $null

    try {
        if (Get-Command Get-NetRoute -ErrorAction SilentlyContinue) {
            $routesCommandAvailable = $true
            $routes = @(
                Get-NetRoute `
                    -DestinationPrefix "0.0.0.0/0" `
                    -ErrorAction SilentlyContinue |
                    Sort-Object RouteMetric, InterfaceMetric |
                    Select-Object -First 8 `
                        DestinationPrefix,
                        NextHop,
                        InterfaceAlias,
                        RouteMetric,
                        InterfaceMetric
            )
        }
    }
    catch {
        $routesError = $_.Exception.Message
    }

    return [pscustomobject]@{
        ObservedAt = $ObservedAt
        Adapters = [object[]]$adapters
        PrimaryAdapter = $primaryAdapter
        PrimaryIpv4 = [string[]]$primaryIpv4
        PrimaryGateway = [string]$primaryGateway
        PrimaryDns = [string[]]$primaryDns
        HasAdapter = $hasAdapter
        HasIp = $hasIp
        HasGateway = $hasGateway
        HasDns = $hasDns
        GatewayResponds = $gatewayOk
        CloudflareResponds = $internetCloudflareOk
        GoogleResponds = $internetGoogleOk
        MicrosoftDnsResolves = $dnsMicrosoftOk
        DnsError = [string]$dnsError
        RoutesCommandAvailable = $routesCommandAvailable
        Routes = [object[]]$routes
        RoutesError = [string]$routesError
    }
}

function Get-ToolkitNetworkAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Snapshot
    )

    if (-not $Snapshot.HasAdapter) {
        $cause = "Nenhum adaptador de rede ativo foi encontrado."
        $nextAction = (
            "Validar cabo, Wi-Fi, adaptador desativado, " +
            "driver de rede ou placa de rede."
        )
    }
    elseif (-not $Snapshot.HasIp) {
        $cause = "Adaptador ativo encontrado, mas sem IPv4 valido."
        $nextAction = (
            "Validar DHCP, cabo/Wi-Fi, VLAN, driver de rede " +
            "ou renovar IP."
        )
    }
    elseif (-not $Snapshot.HasGateway) {
        $cause = (
            "A maquina possui IPv4, mas nao possui gateway principal."
        )
        $nextAction = (
            "Validar escopo DHCP, configuracao manual, VLAN " +
            "ou politica de rede."
        )
    }
    elseif (-not $Snapshot.GatewayResponds) {
        $cause = "Gateway configurado nao respondeu ao teste."
        $nextAction = (
            "Validar rede local, switch, roteador, Wi-Fi, " +
            "VLAN ou bloqueio ICMP."
        )
    }
    elseif (
        $Snapshot.GatewayResponds -and
        -not $Snapshot.CloudflareResponds -and
        -not $Snapshot.GoogleResponds
    ) {
        $cause = (
            "Rede local responde, mas nao houve resposta externa por IP."
        )
        $nextAction = (
            "Validar rota externa, firewall, proxy, provedor, " +
            "VPN ou bloqueio de saida."
        )
    }
    elseif (
        (
            $Snapshot.CloudflareResponds -or
            $Snapshot.GoogleResponds
        ) -and
        -not $Snapshot.MicrosoftDnsResolves
    ) {
        $cause = (
            "Internet por IP responde, mas resolucao DNS falhou."
        )
        $nextAction = (
            "Executar Limpar DNS, validar servidores DNS e " +
            "testar novamente."
        )
    }
    elseif (
        $Snapshot.GatewayResponds -and
        (
            $Snapshot.CloudflareResponds -or
            $Snapshot.GoogleResponds
        ) -and
        $Snapshot.MicrosoftDnsResolves
    ) {
        $cause = "Conectividade basica aparenta estar funcional."
        $nextAction = (
            "Validar sistema especifico, proxy, VPN, URL de " +
            "destino ou indisponibilidade externa."
        )
    }
    else {
        $cause = (
            "Diagnostico nao conclusivo com os testes basicos."
        )
        $nextAction = (
            "Executar fluxo Sem internet, coletar erro exato " +
            "e escalar se persistir."
        )
    }

    return [pscustomobject]@{
        Cause = $cause
        NextAction = $nextAction
    }
}

function Format-ToolkitNetworkReport {
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
    $adapters = @($Snapshot.Adapters)

    [void]$sb.AppendLine(
        "DIAGNOSTICO DE REDE - PAINEL CONSOLIDADO"
    )
    [void]$sb.AppendLine(
        "----------------------------------------"
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
        "Tipo de acao: Diagnostico sem correcao"
    )
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("ADAPTADORES ATIVOS")
    [void]$sb.AppendLine("------------------")

    if ($adapters.Count -eq 0) {
        [void]$sb.AppendLine(
            "Nenhum adaptador com IP ativo encontrado."
        )
    }
    else {
        foreach ($adapter in $adapters) {
            $ipv4 = @($adapter.IPv4Addresses)
            $ipv6 = @($adapter.IPv6Addresses)
            $dnsServers = @($adapter.DnsServers)
            $gateways = @($adapter.Gateways)

            [void]$sb.AppendLine(
                "Adaptador: $($adapter.Description)"
            )
            [void]$sb.AppendLine(
                "MAC: $(if ($adapter.MACAddress) { $adapter.MACAddress } else { 'Nao encontrado' })"
            )
            [void]$sb.AppendLine(
                "DHCP ativo: $(if ($adapter.DHCPEnabled) { 'Sim' } else { 'Nao' })"
            )
            [void]$sb.AppendLine(
                "IPv4: $(if ($ipv4.Count -gt 0) { $ipv4 -join ', ' } else { 'Nao encontrado' })"
            )
            [void]$sb.AppendLine(
                "IPv6: $(if ($ipv6.Count -gt 0) { $ipv6 -join ', ' } else { 'Nao listado' })"
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

    $primaryIpv4 = @($Snapshot.PrimaryIpv4)
    $hasAdapter = $Snapshot.HasAdapter
    $hasIp = $Snapshot.HasIp
    $hasGateway = $Snapshot.HasGateway

    [void]$sb.AppendLine("TESTES DE CONECTIVIDADE")
    [void]$sb.AppendLine("-----------------------")
    [void]$sb.AppendLine(
        "Adaptador principal: $(if ($hasAdapter) { $Snapshot.PrimaryAdapter.Description } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine(
        "IPv4 principal: $(if ($hasIp) { $primaryIpv4 -join ', ' } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine(
        "Gateway principal: $(if ($hasGateway) { $Snapshot.PrimaryGateway } else { 'Nao encontrado' })"
    )
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine(
        "Gateway responde: $(if ($Snapshot.GatewayResponds) { 'Sim' } else { 'Nao' })"
    )
    [void]$sb.AppendLine(
        "Internet por IP 1.1.1.1: $(if ($Snapshot.CloudflareResponds) { 'Sim' } else { 'Nao' })"
    )
    [void]$sb.AppendLine(
        "Internet por IP 8.8.8.8: $(if ($Snapshot.GoogleResponds) { 'Sim' } else { 'Nao' })"
    )
    [void]$sb.AppendLine(
        "Resolucao DNS www.microsoft.com: $(if ($Snapshot.MicrosoftDnsResolves) { 'Sim' } else { 'Nao' })"
    )

    if (
        -not $Snapshot.MicrosoftDnsResolves -and
        $Snapshot.DnsError
    ) {
        [void]$sb.AppendLine("Erro DNS: $($Snapshot.DnsError)")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("ROTAS PRINCIPAIS")
    [void]$sb.AppendLine("----------------")

    if ($Snapshot.RoutesError) {
        [void]$sb.AppendLine(
            "Falha ao consultar rotas principais."
        )
        [void]$sb.AppendLine(
            "Detalhe: $($Snapshot.RoutesError)"
        )
    }
    elseif (-not $Snapshot.RoutesCommandAvailable) {
        [void]$sb.AppendLine(
            "Get-NetRoute indisponivel nesta versao do PowerShell/Windows."
        )
    }
    elseif (@($Snapshot.Routes).Count -eq 0) {
        [void]$sb.AppendLine(
            "Nenhuma rota padrao IPv4 encontrada via Get-NetRoute."
        )
    }
    else {
        $routesText = (
            $Snapshot.Routes |
                Format-Table -AutoSize |
                Out-String
        ).Trim()
        [void]$sb.AppendLine($routesText)
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("CONCLUSAO AUTOMATICA")
    [void]$sb.AppendLine("--------------------")
    [void]$sb.AppendLine(
        "Causa provavel: $($Assessment.Cause)"
    )
    [void]$sb.AppendLine(
        "Proxima acao recomendada: $($Assessment.NextAction)"
    )
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine(
        "Observacao: este diagnostico nao executa nenhuma correcao automaticamente."
    )

    return $sb.ToString()
}

function Get-ToolkitAdvancedNetworkReport {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("REDE AVANCADA - CONFIGURACAO LOCAL")
    [void]$sb.AppendLine("=================================")
    [void]$sb.AppendLine("")

    try {
        [void]$sb.AppendLine("ADAPTADORES")
        [void]$sb.AppendLine((Get-NetAdapter -ErrorAction Stop |
            Sort-Object Status, Name |
            Select-Object Name, InterfaceDescription, Status, MacAddress, LinkSpeed |
            Format-Table -AutoSize | Out-String))
    }
    catch { [void]$sb.AppendLine("Falha ao consultar adaptadores: $($_.Exception.Message)") }

    try {
        [void]$sb.AppendLine("CONFIGURACAO IP")
        [void]$sb.AppendLine((Get-NetIPConfiguration -ErrorAction Stop |
            Select-Object InterfaceAlias, InterfaceIndex, IPv4Address, IPv4DefaultGateway, DNSServer |
            Format-List | Out-String))
    }
    catch { [void]$sb.AppendLine("Falha ao consultar IP: $($_.Exception.Message)") }

    try {
        [void]$sb.AppendLine("PERFIL DE REDE")
        [void]$sb.AppendLine((Get-NetConnectionProfile -ErrorAction Stop |
            Select-Object Name, InterfaceAlias, NetworkCategory, IPv4Connectivity, IPv6Connectivity |
            Format-Table -AutoSize | Out-String))
    }
    catch { [void]$sb.AppendLine("Falha ao consultar perfil: $($_.Exception.Message)") }

    return $sb.ToString()
}

function Get-ToolkitDnsReport {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("DNS - CONFIGURACAO E CACHE")
    [void]$sb.AppendLine("==========================")
    [void]$sb.AppendLine("")
    try {
        $dns = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
            Select-Object InterfaceAlias, InterfaceIndex, ServerAddresses)
        if ($dns.Count -gt 0) {
            [void]$sb.AppendLine(($dns | Format-Table -AutoSize | Out-String))
        }
        else { [void]$sb.AppendLine("Nenhum servidor DNS IPv4 encontrado.") }
    }
    catch { [void]$sb.AppendLine("Falha ao consultar DNS: $($_.Exception.Message)") }

    [void]$sb.AppendLine("CACHE DNS (30 PRIMEIROS REGISTROS)")
    try {
        $cache = @(Get-DnsClientCache -ErrorAction Stop |
            Select-Object -First 30 Entry, RecordType, Status, Data)
        if ($cache.Count -gt 0) {
            [void]$sb.AppendLine(($cache | Format-Table -AutoSize | Out-String))
        }
        else { [void]$sb.AppendLine("Cache DNS vazio.") }
    }
    catch { [void]$sb.AppendLine("Cache DNS indisponivel: $($_.Exception.Message)") }
    return $sb.ToString()
}

function Get-ToolkitRoutesReport {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("ROTAS IPV4")
    [void]$sb.AppendLine("==========")
    try {
        $routes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop |
            Sort-Object RouteMetric |
            Select-Object -First 80 DestinationPrefix, NextHop, InterfaceAlias, RouteMetric)
        [void]$sb.AppendLine(($routes | Format-Table -AutoSize | Out-String))
    }
    catch { [void]$sb.AppendLine("Falha ao consultar rotas: $($_.Exception.Message)") }
    return $sb.ToString()
}

function Test-ToolkitDefaultGateway {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("TESTE DO GATEWAY PADRAO")
    [void]$sb.AppendLine("=======================")
    try {
        $gateways = @(Get-NetIPConfiguration -ErrorAction Stop |
            Where-Object { $_.IPv4DefaultGateway.NextHop } |
            ForEach-Object { $_.IPv4DefaultGateway.NextHop } |
            Select-Object -Unique)
        if ($gateways.Count -eq 0) { return "Nenhum gateway IPv4 encontrado." }
        foreach ($gateway in $gateways) {
            $ok = Test-Connection -ComputerName $gateway -Count 2 -Quiet -ErrorAction SilentlyContinue
            [void]$sb.AppendLine("$gateway : $(if ($ok) { 'OK' } else { 'SEM RESPOSTA' })")
        }
    }
    catch { [void]$sb.AppendLine("Falha ao testar gateway: $($_.Exception.Message)") }
    return $sb.ToString()
}

function Invoke-ToolkitRenewIp {
    param([switch]$Confirmed)
    if (-not $Confirmed) { throw "Renovacao de IP exige confirmacao explicita." }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("RENOVACAO DE IP")
    [void]$sb.AppendLine("===============")
    [void]$sb.AppendLine("A conexao pode ser interrompida temporariamente.")
    [void]$sb.AppendLine((ipconfig /release 2>&1 | Out-String))
    Start-Sleep -Seconds 2
    [void]$sb.AppendLine((ipconfig /renew 2>&1 | Out-String))
    return $sb.ToString()
}

function Invoke-ToolkitNetworkStackReset {
    param(
        [ValidateSet("Winsock", "TcpIp")][string]$Target,
        [switch]$Confirmed
    )
    if (-not $Confirmed) { throw "Reset da pilha de rede exige confirmacao explicita." }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $identity
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Execute o Toolkit como administrador para resetar a pilha de rede."
    }
    $output = if ($Target -eq "Winsock") {
        netsh winsock reset 2>&1 | Out-String
    }
    else {
        netsh int ip reset 2>&1 | Out-String
    }
    return "RESET $($Target.ToUpperInvariant())`r`n================`r`n$output`r`nReinicie o computador para concluir."
}

function Open-ToolkitNetworkConnections {
    Start-Process "ncpa.cpl"
    return "Conexoes de Rede abertas."
}

Export-ModuleMember -Function @(
    'Get-ToolkitNetworkSnapshot',
    'Get-ToolkitNetworkAssessment',
    'Format-ToolkitNetworkReport',
    'Get-ToolkitAdvancedNetworkReport',
    'Get-ToolkitDnsReport',
    'Get-ToolkitRoutesReport',
    'Test-ToolkitDefaultGateway',
    'Invoke-ToolkitRenewIp',
    'Invoke-ToolkitNetworkStackReset',
    'Open-ToolkitNetworkConnections'
)
