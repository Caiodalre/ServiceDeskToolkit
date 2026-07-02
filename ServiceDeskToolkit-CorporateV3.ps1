Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

$script:RootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:TxtV3Output = $null

function Test-V3Admin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-V3VersionInfo {
    try {
        $versionPath = Join-Path $script:RootPath "version.json"

        if (Test-Path $versionPath) {
            $json = Get-Content $versionPath -Raw | ConvertFrom-Json
            return "$($json.version) / $($json.channel)"
        }

        return "V3 Preview"
    }
    catch {
        return "V3 Preview"
    }
}

function Set-V3Output {
    param([string]$Text)

    if ($null -ne $script:TxtV3Output) {
        $script:TxtV3Output.Text = $Text
    }
}

function Get-V3HomeText {
    $admin = if (Test-V3Admin) { "Sim" } else { "Não" }

    @"
ServiceDesk Toolkit Corporate V3
================================

Nova experiência visual limpa.

Objetivo:
- Guiar o atendimento técnico
- Reduzir excesso de botões
- Separar diagnóstico, evidência e correção
- Manter ações críticas protegidas
- Reaproveitar a base técnica validada da v2.4

Ambiente:
- Hostname: $env:COMPUTERNAME
- Usuário: $env:USERDOMAIN\$env:USERNAME
- Administrador: $admin
- Versão: $(Get-V3VersionInfo)

Próximo passo recomendado:
Use Atendimento Guiado para iniciar uma triagem.
"@
}

function Get-V3InventoryLite {
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("INVENTÁRIO DA MÁQUINA")
    [void]$sb.AppendLine("======================")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
    [void]$sb.AppendLine("")

    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
        $network = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue

        $ramGb = [math]::Round(($computer.TotalPhysicalMemory / 1GB), 2)
        $uptime = (Get-Date) - $os.LastBootUpTime

        [void]$sb.AppendLine("IDENTIFICAÇÃO")
        [void]$sb.AppendLine("--------------")
        [void]$sb.AppendLine("Hostname: $env:COMPUTERNAME")
        [void]$sb.AppendLine("Usuário: $env:USERDOMAIN\$env:USERNAME")
        [void]$sb.AppendLine("Domínio/Workgroup: $($computer.Domain)")
        [void]$sb.AppendLine("Administrador: $(if (Test-V3Admin) { 'Sim' } else { 'Não' })")
        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("EQUIPAMENTO")
        [void]$sb.AppendLine("-----------")
        [void]$sb.AppendLine("Fabricante: $($computer.Manufacturer)")
        [void]$sb.AppendLine("Modelo: $($computer.Model)")
        [void]$sb.AppendLine("Serial Number: $($bios.SerialNumber)")
        [void]$sb.AppendLine("BIOS: $($bios.SMBIOSBIOSVersion)")
        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("WINDOWS")
        [void]$sb.AppendLine("-------")
        [void]$sb.AppendLine("Sistema: $($os.Caption)")
        [void]$sb.AppendLine("Versão: $($os.Version)")
        [void]$sb.AppendLine("Build: $($os.BuildNumber)")
        [void]$sb.AppendLine("Arquitetura: $($os.OSArchitecture)")
        [void]$sb.AppendLine("Último boot: $($os.LastBootUpTime.ToString('dd/MM/yyyy HH:mm:ss'))")
                $uptimeText = "Uptime: {0} dia(s), {1} hora(s), {2} minuto(s)" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
        [void]$sb.AppendLine($uptimeText)
        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("HARDWARE")
        [void]$sb.AppendLine("--------")
        [void]$sb.AppendLine("Processador: $($cpu.Name)")
        [void]$sb.AppendLine("Memória RAM: $ramGb GB")
        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("DISCOS")
        [void]$sb.AppendLine("------")

        if ($disks) {
            foreach ($disk in $disks) {
                $sizeGb = [math]::Round(($disk.Size / 1GB), 2)
                $freeGb = [math]::Round(($disk.FreeSpace / 1GB), 2)

                if ($disk.Size -gt 0) {
                    $usedPercent = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 2)
                }
                else {
                    $usedPercent = 0
                }

                [void]$sb.AppendLine("$($disk.DeviceID) Total: $sizeGb GB | Livre: $freeGb GB | Uso: $usedPercent%")
            }
        }
        else {
            [void]$sb.AppendLine("Nenhum disco local encontrado.")
        }

        [void]$sb.AppendLine("")

        [void]$sb.AppendLine("REDE")
        [void]$sb.AppendLine("----")

        if ($network) {
            foreach ($adapter in $network) {
                [void]$sb.AppendLine("Adaptador: $($adapter.Description)")

                if ($adapter.IPAddress) {
                    [void]$sb.AppendLine("IP: $($adapter.IPAddress -join ', ')")
                }

                if ($adapter.DefaultIPGateway) {
                    [void]$sb.AppendLine("Gateway: $($adapter.DefaultIPGateway -join ', ')")
                }

                if ($adapter.DNSServerSearchOrder) {
                    [void]$sb.AppendLine("DNS: $($adapter.DNSServerSearchOrder -join ', ')")
                }

                [void]$sb.AppendLine("")
            }
        }
        else {
            [void]$sb.AppendLine("Nenhum adaptador de rede ativo encontrado.")
            [void]$sb.AppendLine("")
        }

        [void]$sb.AppendLine("STATUS")
        [void]$sb.AppendLine("------")
        [void]$sb.AppendLine("Inventário gerado com sucesso.")
        [void]$sb.AppendLine("Esta ação é somente leitura e não altera configurações da máquina.")
    }
    catch {
        [void]$sb.AppendLine("ERRO")
        [void]$sb.AppendLine("----")
        [void]$sb.AppendLine("Não foi possível gerar o inventário completo.")
        [void]$sb.AppendLine("Detalhe: $($_.Exception.Message)")
    }

    return $sb.ToString()
}
function Invoke-V3NetworkDiagnostic {
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("Diagnóstico de Rede")
    [void]$sb.AppendLine("===================")
    [void]$sb.AppendLine("")

    try {
        [void]$sb.AppendLine("Configuração IP:")
        [void]$sb.AppendLine((Get-NetIPConfiguration | Format-List | Out-String))
    }
    catch {
        [void]$sb.AppendLine("Erro ao consultar IP: $($_.Exception.Message)")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Testes básicos:")

    foreach ($target in @("8.8.8.8", "google.com")) {
        try {
            $ok = Test-Connection -ComputerName $target -Count 2 -Quiet -ErrorAction SilentlyContinue
            [void]$sb.AppendLine("- Ping $($target): $(if ($ok) { 'OK' } else { 'Falhou' })")
        }
        catch {
            [void]$sb.AppendLine("- Ping $($target): erro - $($_.Exception.Message)")
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Evidência para chamado:")
    [void]$sb.AppendLine("- Anexar esta saída se houver falha de IP, gateway, DNS ou internet.")

    return $sb.ToString()
}

function Invoke-V3QuickInternet {
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("Atendimento Guiado - Sem internet")
    [void]$sb.AppendLine("=================================")
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("Diagnóstico")
    [void]$sb.AppendLine("---------------------------------")
    [void]$sb.AppendLine((Invoke-V3NetworkDiagnostic))

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Causa provável")
    [void]$sb.AppendLine("---------------------------------")
    [void]$sb.AppendLine("- Sem IP ou gateway: possível falha de cabo, Wi-Fi, DHCP ou adaptador.")
    [void]$sb.AppendLine("- Ping por IP OK e domínio falha: possível DNS.")
    [void]$sb.AppendLine("- Tudo falha: possível indisponibilidade local, rota, proxy, firewall ou VPN.")

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Próxima ação")
    [void]$sb.AppendLine("---------------------------------")
    [void]$sb.AppendLine("1. Validar cabo ou Wi-Fi.")
    [void]$sb.AppendLine("2. Limpar DNS.")
    [void]$sb.AppendLine("3. Renovar IP.")
    [void]$sb.AppendLine("4. Testar VPN, proxy ou rota corporativa.")
    [void]$sb.AppendLine("5. Se persistir, escalar com a evidência abaixo.")

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Evidência para chamado")
    [void]$sb.AppendLine("---------------------------------")
    [void]$sb.AppendLine("- Hostname, usuário, IP, gateway, DNS e resultado dos testes.")

    return $sb.ToString()
}

function Invoke-V3QuickVpn {
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("Atendimento Guiado - VPN / Appgate")
    [void]$sb.AppendLine("==================================")
    [void]$sb.AppendLine("")

    try {
        $services = Get-Service | Where-Object {
            $_.Name -like "*appgate*" -or $_.DisplayName -like "*appgate*"
        } | Select-Object Name, DisplayName, Status

        if ($services) {
            [void]$sb.AppendLine(($services | Format-Table -AutoSize | Out-String))
        }
        else {
            [void]$sb.AppendLine("Nenhum serviço Appgate encontrado.")
        }
    }
    catch {
        [void]$sb.AppendLine("Erro ao consultar Appgate: $($_.Exception.Message)")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Próxima ação")
    [void]$sb.AppendLine("---------------------------------")
    [void]$sb.AppendLine("1. Validar se a VPN está instalada.")
    [void]$sb.AppendLine("2. Validar serviço/processo.")
    [void]$sb.AppendLine("3. Validar rede antes da VPN.")
    [void]$sb.AppendLine("4. Escalar com print do erro e esta evidência.")

    return $sb.ToString()
}

function Invoke-V3FlushDns {
    try {
        ipconfig /flushdns | Out-Null
        return "DNS limpo com sucesso."
    }
    catch {
        return "Erro ao limpar DNS:`r`n$($_.Exception.Message)"
    }
}

function Invoke-V3TimeSync {
    try {
        Start-Service w32time -ErrorAction SilentlyContinue
        return (w32tm /resync 2>&1 | Out-String)
    }
    catch {
        return "Erro ao sincronizar horário:`r`n$($_.Exception.Message)"
    }
}

function Invoke-V3RestartSpooler {
    try {
        Restart-Service Spooler -Force -ErrorAction Stop
        return "Spooler reiniciado com sucesso."
    }
    catch {
        return "Erro ao reiniciar spooler:`r`n$($_.Exception.Message)"
    }
}

$script:V3LastExternalLinkUrl = ""
$script:V3LastExternalLinkAt = Get-Date "2000-01-01"

$script:V3LastExternalLinkUrl = ""
$script:V3LastExternalLinkAt = Get-Date "2000-01-01"

function Invoke-V3InternetDiagnosticSummary {
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("DIAGNOSTICO AUTOMATICO DE INTERNET")
    [void]$sb.AppendLine("----------------------------------")
    [void]$sb.AppendLine("")

    try {
        $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue
        $adapter = $adapters | Select-Object -First 1

        if ($null -eq $adapter) {
            [void]$sb.AppendLine("Status: Nenhum adaptador de rede ativo encontrado.")
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("Causa provavel: adaptador desativado, cabo desconectado, Wi-Fi desconectado ou driver de rede indisponivel.")
            [void]$sb.AppendLine("Proxima acao recomendada: validar conexao fisica/Wi-Fi e verificar adaptador de rede.")
            return $sb.ToString()
        }

        $ipList = @()
        if ($adapter.IPAddress) {
            $ipList = $adapter.IPAddress | Where-Object { $_ -and ($_ -notlike "fe80*") }
        }

        $gateway = $null
        if ($adapter.DefaultIPGateway) {
            $gateway = $adapter.DefaultIPGateway | Select-Object -First 1
        }

        $dnsList = @()
        if ($adapter.DNSServerSearchOrder) {
            $dnsList = $adapter.DNSServerSearchOrder
        }

        $hasIp = ($ipList.Count -gt 0)
        $hasGateway = -not [string]::IsNullOrWhiteSpace($gateway)
        $hasDns = ($dnsList.Count -gt 0)

        $gatewayOk = $false
        if ($hasGateway) {
            $gatewayOk = Test-Connection -ComputerName $gateway -Count 1 -Quiet -ErrorAction SilentlyContinue
        }

        $internetIpOk = Test-Connection -ComputerName "1.1.1.1" -Count 1 -Quiet -ErrorAction SilentlyContinue

        $dnsOk = $false
        $dnsError = $null

        try {
            $resolved = Resolve-DnsName -Name "www.microsoft.com" -Type A -ErrorAction Stop
            if ($resolved) {
                $dnsOk = $true
            }
        }
        catch {
            $dnsError = $_.Exception.Message
        }

        [void]$sb.AppendLine("Adaptador: $($adapter.Description)")
        [void]$sb.AppendLine("IP: $(if ($hasIp) { $ipList -join ', ' } else { 'Nao encontrado' })")
        [void]$sb.AppendLine("Gateway: $(if ($hasGateway) { $gateway } else { 'Nao encontrado' })")
        [void]$sb.AppendLine("DNS: $(if ($hasDns) { $dnsList -join ', ' } else { 'Nao encontrado' })")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("TESTES")
        [void]$sb.AppendLine("------")
        [void]$sb.AppendLine("Gateway responde: $(if ($gatewayOk) { 'Sim' } else { 'Nao' })")
        [void]$sb.AppendLine("Internet por IP 1.1.1.1: $(if ($internetIpOk) { 'Sim' } else { 'Nao' })")
        [void]$sb.AppendLine("Resolucao DNS www.microsoft.com: $(if ($dnsOk) { 'Sim' } else { 'Nao' })")

        if (-not $dnsOk -and $dnsError) {
            [void]$sb.AppendLine("Erro DNS: $dnsError")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("CONCLUSAO AUTOMATICA")
        [void]$sb.AppendLine("--------------------")

        $cause = ""
        $nextAction = ""

        if (-not $hasIp) {
            $cause = "A maquina nao possui IP valido no adaptador ativo."
            $nextAction = "Validar cabo, Wi-Fi, DHCP, driver de rede ou reiniciar o adaptador."
        }
        elseif (-not $hasGateway) {
            $cause = "A maquina possui IP, mas nao possui gateway configurado."
            $nextAction = "Validar configuracao de rede, DHCP e escopo entregue ao equipamento."
        }
        elseif (-not $gatewayOk) {
            $cause = "O gateway configurado nao respondeu ao teste."
            $nextAction = "Validar rede local, roteador, switch, VLAN, cabo ou Wi-Fi."
        }
        elseif ($internetIpOk -and -not $dnsOk) {
            $cause = "A internet por IP respondeu, mas a resolucao de nomes falhou. Indicio forte de problema de DNS."
            $nextAction = "Executar Limpar DNS, validar servidores DNS e testar resolucao novamente."
        }
        elseif (-not $internetIpOk -and $gatewayOk) {
            $cause = "A rede local responde, mas nao houve resposta externa por IP."
            $nextAction = "Validar rota, firewall, proxy, provedor ou bloqueio de saida."
        }
        elseif ($internetIpOk -and $dnsOk) {
            $cause = "Conectividade basica aparenta estar funcional."
            $nextAction = "Validar o sistema especifico informado pelo usuario, proxy, VPN ou indisponibilidade do destino."
        }
        else {
            $cause = "Falha de conectividade nao conclusiva com os testes basicos."
            $nextAction = "Coletar evidencias adicionais e escalar para rede se a falha persistir."
        }

        [void]$sb.AppendLine("Causa provavel: $cause")
        [void]$sb.AppendLine("Proxima acao recomendada: $nextAction")
    }
    catch {
        [void]$sb.AppendLine("Falha ao executar diagnostico automatico de internet.")
        [void]$sb.AppendLine("Detalhe: $($_.Exception.Message)")
    }

    return $sb.ToString()
}
function Invoke-V3VpnDiagnosticSummary {
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("DIAGNOSTICO AUTOMATICO DE VPN / APPGATE")
    [void]$sb.AppendLine("---------------------------------------")
    [void]$sb.AppendLine("")

    try {
        $internetIpOk = Test-Connection -ComputerName "1.1.1.1" -Count 1 -Quiet -ErrorAction SilentlyContinue

        $dnsOk = $false
        $dnsError = $null

        try {
            $resolved = Resolve-DnsName -Name "www.microsoft.com" -Type A -ErrorAction Stop

            if ($resolved) {
                $dnsOk = $true
            }
        }
        catch {
            $dnsError = $_.Exception.Message
        }

        $services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like "*appgate*" -or
            $_.DisplayName -like "*appgate*" -or
            $_.Name -like "*sdp*" -or
            $_.DisplayName -like "*sdp*"
        })

        $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessName -like "*appgate*" -or
            $_.ProcessName -like "*sdp*"
        })

        $programPaths = @(
            "C:\Program Files\Appgate SDP",
            "C:\Program Files (x86)\Appgate SDP",
            "C:\Program Files\Appgate",
            "C:\Program Files (x86)\Appgate"
        )

        $installedPaths = @()

        foreach ($path in $programPaths) {
            if (Test-Path $path) {
                $installedPaths += $path
            }
        }

        [void]$sb.AppendLine("CONECTIVIDADE LOCAL")
        [void]$sb.AppendLine("-------------------")
        [void]$sb.AppendLine("Internet por IP 1.1.1.1: $(if ($internetIpOk) { 'Sim' } else { 'Nao' })")
        [void]$sb.AppendLine("Resolucao DNS www.microsoft.com: $(if ($dnsOk) { 'Sim' } else { 'Nao' })")

        if (-not $dnsOk -and $dnsError) {
            [void]$sb.AppendLine("Erro DNS: $dnsError")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("INSTALACAO")
        [void]$sb.AppendLine("----------")

        if ($installedPaths.Count -gt 0) {
            foreach ($path in $installedPaths) {
                [void]$sb.AppendLine("Encontrado: $path")
            }
        }
        else {
            [void]$sb.AppendLine("Nenhum diretorio padrao do Appgate encontrado em Program Files.")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("SERVICOS")
        [void]$sb.AppendLine("--------")

        if ($services.Count -gt 0) {
            foreach ($service in $services) {
                [void]$sb.AppendLine("$($service.DisplayName) | Name: $($service.Name) | Status: $($service.Status) | StartType: $($service.StartType)")
            }
        }
        else {
            [void]$sb.AppendLine("Nenhum servico relacionado a Appgate/SDP encontrado.")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("PROCESSOS")
        [void]$sb.AppendLine("---------")

        if ($processes.Count -gt 0) {
            foreach ($process in $processes) {
                [void]$sb.AppendLine("$($process.ProcessName) | PID: $($process.Id)")
            }
        }
        else {
            [void]$sb.AppendLine("Nenhum processo relacionado a Appgate/SDP encontrado em execucao.")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("CONCLUSAO AUTOMATICA")
        [void]$sb.AppendLine("--------------------")

        $runningServices = @($services | Where-Object { $_.Status -eq "Running" })
        $stoppedServices = @($services | Where-Object { $_.Status -ne "Running" })

        $cause = ""
        $nextAction = ""

        if (-not $internetIpOk) {
            $cause = "A maquina nao possui conectividade externa basica. A VPN pode falhar antes mesmo de autenticar."
            $nextAction = "Resolver primeiro a internet local antes de atuar no Appgate."
        }
        elseif ($internetIpOk -and -not $dnsOk) {
            $cause = "A internet por IP responde, mas DNS falhou. A VPN pode nao resolver o endereco do concentrador."
            $nextAction = "Limpar DNS, validar servidores DNS e testar novamente."
        }
        elseif ($installedPaths.Count -eq 0 -and $services.Count -eq 0 -and $processes.Count -eq 0) {
            $cause = "Nao ha sinais claros de instalacao do Appgate na maquina."
            $nextAction = "Validar se o cliente Appgate esta instalado ou reinstalar conforme padrao corporativo."
        }
        elseif ($services.Count -gt 0 -and $runningServices.Count -eq 0) {
            $cause = "Servicos relacionados ao Appgate foram encontrados, mas nenhum esta em execucao."
            $nextAction = "Abrir a area avancada e reiniciar o Appgate, ou executar como administrador se necessario."
        }
        elseif ($stoppedServices.Count -gt 0) {
            $cause = "Ha servicos relacionados ao Appgate parados ou em estado diferente de Running."
            $nextAction = "Validar servicos parados, reiniciar o cliente e coletar erro se voltar a falhar."
        }
        elseif ($services.Count -gt 0 -and $runningServices.Count -gt 0 -and $processes.Count -eq 0) {
            $cause = "Servico do Appgate esta ativo, mas nenhum processo cliente foi encontrado."
            $nextAction = "Abrir o cliente Appgate manualmente e validar se ele inicia sem erro."
        }
        elseif ($services.Count -gt 0 -and $runningServices.Count -gt 0 -and $processes.Count -gt 0) {
            $cause = "Appgate aparenta estar instalado e em execucao. A falha pode estar em autenticacao, politica, certificado, rota ou servidor."
            $nextAction = "Coletar mensagem exata do erro, horario da tentativa, usuario afetado e escalar com a evidencia."
        }
        else {
            $cause = "Diagnostico nao conclusivo com os testes basicos."
            $nextAction = "Coletar print do erro, validar internet local, reiniciar cliente e escalar se persistir."
        }

        [void]$sb.AppendLine("Causa provavel: $cause")
        [void]$sb.AppendLine("Proxima acao recomendada: $nextAction")
    }
    catch {
        [void]$sb.AppendLine("Falha ao executar diagnostico automatico de VPN / Appgate.")
        [void]$sb.AppendLine("Detalhe: $($_.Exception.Message)")
    }

    return $sb.ToString()
}
function Invoke-V3SafeFlushDns {
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("CORRECAO SEGURA - LIMPAR DNS")
    [void]$sb.AppendLine("----------------------------")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
    [void]$sb.AppendLine("Hostname: $env:COMPUTERNAME")
    [void]$sb.AppendLine("Usuario: $env:USERDOMAIN\$env:USERNAME")
    [void]$sb.AppendLine("Risco da acao: Baixo")
    [void]$sb.AppendLine("")

    try {
        $dnsBeforeOk = $false
        $dnsBeforeError = $null

        try {
            $before = Resolve-DnsName -Name "www.microsoft.com" -Type A -ErrorAction Stop

            if ($before) {
                $dnsBeforeOk = $true
            }
        }
        catch {
            $dnsBeforeError = $_.Exception.Message
        }

        [void]$sb.AppendLine("VALIDACAO ANTES")
        [void]$sb.AppendLine("---------------")
        [void]$sb.AppendLine("Resolucao DNS www.microsoft.com: $(if ($dnsBeforeOk) { 'Sim' } else { 'Nao' })")

        if (-not $dnsBeforeOk -and $dnsBeforeError) {
            [void]$sb.AppendLine("Erro antes: $dnsBeforeError")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("EXECUCAO")
        [void]$sb.AppendLine("--------")

        $flushResult = ipconfig /flushdns 2>&1 | Out-String

        if ([string]::IsNullOrWhiteSpace($flushResult)) {
            [void]$sb.AppendLine("Comando executado: ipconfig /flushdns")
        }
        else {
            [void]$sb.AppendLine($flushResult.Trim())
        }

        Start-Sleep -Seconds 1

        $dnsAfterOk = $false
        $dnsAfterError = $null

        try {
            $after = Resolve-DnsName -Name "www.microsoft.com" -Type A -ErrorAction Stop

            if ($after) {
                $dnsAfterOk = $true
            }
        }
        catch {
            $dnsAfterError = $_.Exception.Message
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("VALIDACAO DEPOIS")
        [void]$sb.AppendLine("----------------")
        [void]$sb.AppendLine("Resolucao DNS www.microsoft.com: $(if ($dnsAfterOk) { 'Sim' } else { 'Nao' })")

        if (-not $dnsAfterOk -and $dnsAfterError) {
            [void]$sb.AppendLine("Erro depois: $dnsAfterError")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("CONCLUSAO AUTOMATICA")
        [void]$sb.AppendLine("--------------------")

        if (-not $dnsBeforeOk -and $dnsAfterOk) {
            [void]$sb.AppendLine("Resultado: DNS corrigido apos limpeza de cache.")
            [void]$sb.AppendLine("Proxima acao recomendada: pedir ao usuario para testar novamente o sistema ou site afetado.")
        }
        elseif ($dnsBeforeOk -and $dnsAfterOk) {
            [void]$sb.AppendLine("Resultado: DNS ja estava funcional antes e continuou funcional depois.")
            [void]$sb.AppendLine("Proxima acao recomendada: se o problema persistir, validar proxy, VPN, firewall ou destino especifico.")
        }
        elseif (-not $dnsAfterOk) {
            [void]$sb.AppendLine("Resultado: limpeza de DNS executada, mas a resolucao continua falhando.")
            [void]$sb.AppendLine("Proxima acao recomendada: validar servidores DNS, rede local, VPN, proxy ou bloqueio externo.")
        }
        else {
            [void]$sb.AppendLine("Resultado: acao concluida, mas o diagnostico nao foi conclusivo.")
            [void]$sb.AppendLine("Proxima acao recomendada: executar o fluxo Sem internet para diagnostico completo.")
        }
    }
    catch {
        [void]$sb.AppendLine("Falha ao executar limpeza segura de DNS.")
        [void]$sb.AppendLine("Detalhe: $($_.Exception.Message)")
    }

    return $sb.ToString()
}
function Invoke-V3SafeTimeSync {
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("CORRECAO SEGURA - SINCRONIZAR HORARIO")
    [void]$sb.AppendLine("-------------------------------------")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
    [void]$sb.AppendLine("Hostname: $env:COMPUTERNAME")
    [void]$sb.AppendLine("Usuario: $env:USERDOMAIN\$env:USERNAME")
    [void]$sb.AppendLine("Admin: $(if (Test-V3Admin) { 'Sim' } else { 'Nao' })")
    [void]$sb.AppendLine("Risco da acao: Baixo")
    [void]$sb.AppendLine("")

    try {
        $serviceBefore = Get-Service -Name "w32time" -ErrorAction SilentlyContinue

        [void]$sb.AppendLine("VALIDACAO ANTES")
        [void]$sb.AppendLine("---------------")

        if ($null -eq $serviceBefore) {
            [void]$sb.AppendLine("Servico Windows Time: Nao encontrado")
        }
        else {
            [void]$sb.AppendLine("Servico Windows Time: $($serviceBefore.Status)")
        }

        $statusBeforeRaw = & w32tm /query /status 2>&1
        $statusBeforeText = $statusBeforeRaw | Out-String

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Status antes:")
        [void]$sb.AppendLine($statusBeforeText.Trim())

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("EXECUCAO")
        [void]$sb.AppendLine("--------")

        if ($null -ne $serviceBefore -and $serviceBefore.Status -ne "Running") {
            if (Test-V3Admin) {
                try {
                    Start-Service -Name "w32time" -ErrorAction Stop
                    [void]$sb.AppendLine("Servico Windows Time iniciado.")
                    Start-Sleep -Seconds 1
                }
                catch {
                    [void]$sb.AppendLine("Nao foi possivel iniciar o servico Windows Time.")
                    [void]$sb.AppendLine("Detalhe: $($_.Exception.Message)")
                }
            }
            else {
                [void]$sb.AppendLine("Servico Windows Time esta parado, mas a ferramenta nao esta em modo administrador.")
                [void]$sb.AppendLine("A sincronizacao sera tentada mesmo assim.")
            }
        }
        else {
            [void]$sb.AppendLine("Servico Windows Time ja estava em execucao ou nao foi localizado.")
        }

        $resyncRaw = & w32tm /resync /force 2>&1
        $resyncExitCode = $LASTEXITCODE
        $resyncText = $resyncRaw | Out-String

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Resultado do comando:")
        [void]$sb.AppendLine($resyncText.Trim())

        Start-Sleep -Seconds 2

        $serviceAfter = Get-Service -Name "w32time" -ErrorAction SilentlyContinue

        $statusAfterRaw = & w32tm /query /status 2>&1
        $statusAfterText = $statusAfterRaw | Out-String

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("VALIDACAO DEPOIS")
        [void]$sb.AppendLine("----------------")

        if ($null -eq $serviceAfter) {
            [void]$sb.AppendLine("Servico Windows Time: Nao encontrado")
        }
        else {
            [void]$sb.AppendLine("Servico Windows Time: $($serviceAfter.Status)")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Status depois:")
        [void]$sb.AppendLine($statusAfterText.Trim())

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("CONCLUSAO AUTOMATICA")
        [void]$sb.AppendLine("--------------------")

        $resyncLooksOk = $false

        if ($resyncExitCode -eq 0) {
            $resyncLooksOk = $true
        }

        if ($resyncText -match "success|successful|exito|concluido|conclu.do") {
            $resyncLooksOk = $true
        }

        if ($resyncLooksOk) {
            [void]$sb.AppendLine("Resultado: sincronizacao de horario solicitada com sucesso.")
            [void]$sb.AppendLine("Proxima acao recomendada: pedir ao usuario para testar novamente login, VPN, Teams, Outlook ou sistema afetado.")
        }
        elseif ($null -ne $serviceAfter -and $serviceAfter.Status -ne "Running") {
            [void]$sb.AppendLine("Resultado: sincronizacao nao confirmada e o servico Windows Time nao esta em execucao.")
            [void]$sb.AppendLine("Proxima acao recomendada: executar como administrador, iniciar o servico Windows Time e tentar novamente.")
        }
        elseif (-not (Test-V3Admin)) {
            [void]$sb.AppendLine("Resultado: sincronizacao nao confirmada. Pode haver restricao por falta de permissao administrativa.")
            [void]$sb.AppendLine("Proxima acao recomendada: executar a ferramenta como administrador e tentar novamente.")
        }
        else {
            [void]$sb.AppendLine("Resultado: sincronizacao nao confirmada pelo comando w32tm.")
            [void]$sb.AppendLine("Proxima acao recomendada: validar GPO de horario, NTP, dominio, firewall, proxy ou conectividade com o controlador de dominio.")
        }
    }
    catch {
        [void]$sb.AppendLine("Falha ao executar sincronizacao segura de horario.")
        [void]$sb.AppendLine("Detalhe: $($_.Exception.Message)")
    }

    return $sb.ToString()
}
function Invoke-V3SafeSpoolerRestart {
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("CORRECAO SEGURA - REINICIAR SPOOLER")
    [void]$sb.AppendLine("-----------------------------------")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
    [void]$sb.AppendLine("Hostname: $env:COMPUTERNAME")
    [void]$sb.AppendLine("Usuario: $env:USERDOMAIN\$env:USERNAME")
    [void]$sb.AppendLine("Admin: $(if (Test-V3Admin) { 'Sim' } else { 'Nao' })")
    [void]$sb.AppendLine("Risco da acao: Baixo")
    [void]$sb.AppendLine("")

    try {
        $serviceBefore = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue

        $jobsBefore = @()

        try {
            $jobsBefore = @(Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue)
        }
        catch {
            $jobsBefore = @()
        }

        [void]$sb.AppendLine("VALIDACAO ANTES")
        [void]$sb.AppendLine("---------------")

        if ($null -eq $serviceBefore) {
            [void]$sb.AppendLine("Servico Spooler: Nao encontrado")
        }
        else {
            [void]$sb.AppendLine("Servico Spooler: $($serviceBefore.Status)")
        }

        [void]$sb.AppendLine("Trabalhos na fila de impressao: $($jobsBefore.Count)")

        if ($jobsBefore.Count -gt 0) {
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("Filas detectadas antes:")
            foreach ($job in ($jobsBefore | Select-Object -First 10)) {
                [void]$sb.AppendLine("- $($job.Name)")
            }

            if ($jobsBefore.Count -gt 10) {
                [void]$sb.AppendLine("- Outros trabalhos omitidos: $($jobsBefore.Count - 10)")
            }
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("EXECUCAO")
        [void]$sb.AppendLine("--------")

        if ($null -eq $serviceBefore) {
            [void]$sb.AppendLine("Nao foi possivel reiniciar. O servico Spooler nao foi encontrado.")
        }
        elseif (-not (Test-V3Admin)) {
            [void]$sb.AppendLine("A ferramenta nao esta em modo administrador.")
            [void]$sb.AppendLine("O Spooler normalmente exige permissao administrativa para reiniciar.")
            [void]$sb.AppendLine("Nenhuma alteracao foi executada.")
        }
        else {
            try {
                if ($serviceBefore.Status -eq "Running") {
                    Restart-Service -Name "Spooler" -Force -ErrorAction Stop
                    [void]$sb.AppendLine("Comando executado: Restart-Service -Name Spooler -Force")
                }
                else {
                    Start-Service -Name "Spooler" -ErrorAction Stop
                    [void]$sb.AppendLine("Servico estava parado. Comando executado: Start-Service -Name Spooler")
                }

                Start-Sleep -Seconds 2
            }
            catch {
                [void]$sb.AppendLine("Falha ao reiniciar/iniciar o Spooler.")
                [void]$sb.AppendLine("Detalhe: $($_.Exception.Message)")
            }
        }

        $serviceAfter = Get-Service -Name "Spooler" -ErrorAction SilentlyContinue

        $jobsAfter = @()

        try {
            $jobsAfter = @(Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue)
        }
        catch {
            $jobsAfter = @()
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("VALIDACAO DEPOIS")
        [void]$sb.AppendLine("----------------")

        if ($null -eq $serviceAfter) {
            [void]$sb.AppendLine("Servico Spooler: Nao encontrado")
        }
        else {
            [void]$sb.AppendLine("Servico Spooler: $($serviceAfter.Status)")
        }

        [void]$sb.AppendLine("Trabalhos na fila de impressao: $($jobsAfter.Count)")

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("CONCLUSAO AUTOMATICA")
        [void]$sb.AppendLine("--------------------")

        if ($null -eq $serviceBefore) {
            [void]$sb.AppendLine("Resultado: o servico Spooler nao foi localizado nesta maquina.")
            [void]$sb.AppendLine("Proxima acao recomendada: validar instalacao do recurso de impressao do Windows.")
        }
        elseif (-not (Test-V3Admin)) {
            [void]$sb.AppendLine("Resultado: nenhuma correcao foi executada por falta de permissao administrativa.")
            [void]$sb.AppendLine("Proxima acao recomendada: executar o Toolkit como administrador e tentar novamente.")
        }
        elseif ($null -ne $serviceAfter -and $serviceAfter.Status -eq "Running") {
            [void]$sb.AppendLine("Resultado: Spooler esta em execucao apos a correcao.")
            [void]$sb.AppendLine("Proxima acao recomendada: pedir ao usuario para testar impressao novamente.")
        }
        elseif ($null -ne $serviceAfter -and $serviceAfter.Status -ne "Running") {
            [void]$sb.AppendLine("Resultado: Spooler foi encontrado, mas nao ficou em execucao.")
            [void]$sb.AppendLine("Proxima acao recomendada: validar driver de impressora, fila travada, permissao, evento do Windows ou reiniciar a maquina.")
        }
        else {
            [void]$sb.AppendLine("Resultado: acao concluida, mas o estado final nao foi conclusivo.")
            [void]$sb.AppendLine("Proxima acao recomendada: validar servico, filas e logs de impressao.")
        }
    }
    catch {
        [void]$sb.AppendLine("Falha ao executar correcao segura do Spooler.")
        [void]$sb.AppendLine("Detalhe: $($_.Exception.Message)")
    }

    return $sb.ToString()
}
function New-V3WorkflowResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Problem,

        [Parameter(Mandatory = $true)]
        [scriptblock]$EvidenceScript,

        [string[]]$LikelyCauses = @(),

        [string[]]$NextActions = @(),

        [string]$RiskLevel = "Baixo"
    )

    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine($Title.ToUpper())
    [void]$sb.AppendLine(("=" * $Title.Length))
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
    [void]$sb.AppendLine("Hostname: $env:COMPUTERNAME")
    [void]$sb.AppendLine("Usuario: $env:USERDOMAIN\$env:USERNAME")
    [void]$sb.AppendLine("Admin: $(if (Test-V3Admin) { 'Sim' } else { 'Nao' })")
    [void]$sb.AppendLine("Risco da acao: $RiskLevel")
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("PROBLEMA")
    [void]$sb.AppendLine("--------")
    [void]$sb.AppendLine($Problem)
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("COLETA AUTOMATICA")
    [void]$sb.AppendLine("-----------------")

    try {
        $evidence = & $EvidenceScript

        if ([string]::IsNullOrWhiteSpace($evidence)) {
            [void]$sb.AppendLine("Nenhuma evidencia automatica retornada.")
        }
        else {
            [void]$sb.AppendLine($evidence.Trim())
        }
    }
    catch {
        [void]$sb.AppendLine("Falha ao coletar evidencia automatica.")
        [void]$sb.AppendLine("Detalhe: $($_.Exception.Message)")
    }

    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("CAUSAS PROVAVEIS")
    [void]$sb.AppendLine("----------------")

    if ($LikelyCauses.Count -gt 0) {
        foreach ($cause in $LikelyCauses) {
            [void]$sb.AppendLine("- $cause")
        }
    }
    else {
        [void]$sb.AppendLine("- Nao definido.")
    }

    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("PROXIMAS ACOES")
    [void]$sb.AppendLine("--------------")

    if ($NextActions.Count -gt 0) {
        foreach ($action in $NextActions) {
            [void]$sb.AppendLine("- $action")
        }
    }
    else {
        [void]$sb.AppendLine("- Nao definido.")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("OBSERVACAO")
    [void]$sb.AppendLine("----------")
    [void]$sb.AppendLine("Este fluxo guiado organiza o atendimento e nao executa correcoes destrutivas automaticamente.")

    return $sb.ToString()
}

function Get-V3GuidedHomeText {
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine("ATENDIMENTO GUIADO")
    [void]$sb.AppendLine("==================")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Escolha um problema para o Toolkit conduzir o atendimento.")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Fluxos disponiveis nesta etapa:")
    [void]$sb.AppendLine("- Sem internet")
    [void]$sb.AppendLine("- VPN / Appgate")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Cada fluxo organiza:")
    [void]$sb.AppendLine("- Problema")
    [void]$sb.AppendLine("- Coleta automatica")
    [void]$sb.AppendLine("- Causas provaveis")
    [void]$sb.AppendLine("- Proximas acoes")
    [void]$sb.AppendLine("- Evidencia para copiar")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Nenhuma correcao critica e executada automaticamente.")

    return $sb.ToString()
}

function Invoke-V3WorkflowNoInternet {
    return New-V3WorkflowResult `
        -Title "Atendimento Guiado - Sem Internet" `
        -Problem "Usuario relata falha de conexao, lentidao, ausencia de internet ou indisponibilidade de acesso a sistemas." `
        -EvidenceScript { Invoke-V3InternetDiagnosticSummary } `
        -LikelyCauses @(
            "Falha de DNS",
            "Gateway indisponivel",
            "Adaptador sem IP valido",
            "Rede local desconectada",
            "Bloqueio temporario de conectividade",
            "Instabilidade externa do provedor ou rota"
        ) `
        -NextActions @(
            "Confirmar se o cabo ou Wi-Fi esta conectado",
            "Validar IP, gateway e DNS retornados na coleta",
            "Testar acesso por nome e por IP",
            "Executar Limpar DNS se houver indicio de cache incorreto",
            "Escalar para rede se gateway ou rota estiver indisponivel"
        ) `
        -RiskLevel "Baixo"
}
function Invoke-V3WorkflowVpn {
    return New-V3WorkflowResult `
        -Title "Atendimento Guiado - VPN / Appgate" `
        -Problem "Usuario relata falha para conectar VPN, Appgate, acesso remoto ou sistemas internos." `
        -EvidenceScript { Invoke-V3VpnDiagnosticSummary } `
        -LikelyCauses @(
            "Servico de VPN parado",
            "Cliente Appgate nao encontrado",
            "Rede local sem internet",
            "Falha de DNS impedindo acesso ao concentrador",
            "Cliente VPN corrompido ou desatualizado",
            "Credencial, certificado ou politica de acesso com falha",
            "Interferencia de firewall, proxy ou antivirus"
        ) `
        -NextActions @(
            "Confirmar se a internet local esta funcionando",
            "Validar se o erro ocorre antes ou depois da autenticacao",
            "Verificar se servicos e processos do Appgate estao ativos",
            "Reiniciar o cliente VPN/Appgate se houver indicio de servico parado",
            "Coletar print ou mensagem exata do erro",
            "Escalar com evidencia se houver falha de certificado, politica ou servidor"
        ) `
        -RiskLevel "Baixo"
}
function Copy-V3OutputToClipboard {
    try {
        if ($null -eq $script:TxtV3Output) {
            return
        }

        $currentText = $script:TxtV3Output.Text

        if ([string]::IsNullOrWhiteSpace($currentText)) {
            Set-V3Output "Nenhum resultado disponível para copiar."
            return
        }

        $cleanText = [regex]::Replace(
            $currentText,
            "(\r?\n){2}\[COPIADO\].*$",
            ""
        )

        [System.Windows.Clipboard]::SetText($cleanText)

        $feedback = "[COPIADO] Resultado copiado para a área de transferência em $(Get-Date -Format 'HH:mm:ss')."

        $script:TxtV3Output.Text = $cleanText.TrimEnd() + "`r`n`r`n" + $feedback
        $script:TxtV3Output.ScrollToEnd()
    }
    catch {
        Set-V3Output "Não foi possível copiar o resultado para a área de transferência.`r`n`r`nDetalhe: $($_.Exception.Message)"
    }
}
function Open-V3ExternalLink {
    param(
        [string]$Url,
        [string]$Label
    )

    try {
        $now = Get-Date
        $elapsed = ($now - $script:V3LastExternalLinkAt).TotalSeconds

        if (($script:V3LastExternalLinkUrl -eq $Url) -and ($elapsed -lt 2)) {
            Set-V3Output "Clique duplicado ignorado para $($Label).`r`n`r`nLink:`r`n$Url"
            return
        }

        $script:V3LastExternalLinkUrl = $Url
        $script:V3LastExternalLinkAt = $now

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Url
        $psi.UseShellExecute = $true

        [System.Diagnostics.Process]::Start($psi) | Out-Null

        Set-V3Output "Abrindo $($Label):`r`n$Url"
    }
    catch {
        Set-V3Output "Erro ao abrir $($Label):`r`n$($_.Exception.Message)"
    }
}
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ServiceDesk Toolkit Corporate V3"
        Height="760"
        Width="1180"
        WindowStartupLocation="CenterScreen"
        Background="#F3F6FA"
        FontFamily="Segoe UI">

    <Window.Resources>
        <Style x:Key="NavButton" TargetType="Button">
            <Setter Property="Height" Value="38"/>
            <Setter Property="Margin" Value="0,4,0,0"/>
            <Setter Property="Padding" Value="12,0"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Background" Value="#162033"/>
            <Setter Property="Foreground" Value="#E5E7EB"/>
            <Setter Property="BorderBrush" Value="#263449"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>

        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Height" Value="38"/>
            <Setter Property="Margin" Value="0,6,8,0"/>
            <Setter Property="Padding" Value="14,0"/>
            <Setter Property="Background" Value="#1D4ED8"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#1D4ED8"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>

        <Style x:Key="SoftButton" TargetType="Button">
            <Setter Property="Height" Value="38"/>
            <Setter Property="Margin" Value="0,6,8,0"/>
            <Setter Property="Padding" Value="14,0"/>
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="Foreground" Value="#0F172A"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>

        <Style x:Key="DangerButton" TargetType="Button">
            <Setter Property="Height" Value="38"/>
            <Setter Property="Margin" Value="0,6,8,0"/>
            <Setter Property="Padding" Value="14,0"/>
            <Setter Property="Background" Value="#FEF2F2"/>
            <Setter Property="Foreground" Value="#991B1B"/>
            <Setter Property="BorderBrush" Value="#FCA5A5"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>

        <Style x:Key="FooterLinkButton" TargetType="Button">
            <Setter Property="Height" Value="28"/>
            <Setter Property="Margin" Value="8,0,0,0"/>
            <Setter Property="Padding" Value="12,0"/>
            <Setter Property="Background" Value="#FFFFFF"/>
            <Setter Property="Foreground" Value="#1D4ED8"/>
            <Setter Property="BorderBrush" Value="#BFDBFE"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="11"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="260"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" Background="#0F172A">
            <StackPanel Margin="18">
                <TextBlock Text="ServiceDesk" Foreground="White" FontSize="24" FontWeight="Bold"/>
                <TextBlock Text="Corporate V3" Foreground="#60A5FA" FontSize="18" FontWeight="Bold"/>
                <TextBlock Text="Central guiada de atendimento" Foreground="#CBD5E1" FontSize="12" Margin="0,4,0,18"/>

                <Button Name="BtnV3NavHome" Content="Início" Style="{StaticResource NavButton}"/>
                <Button Name="BtnV3NavGuided" Content="Atendimento Guiado" Style="{StaticResource NavButton}"/>
                <Button Name="BtnV3NavEvidence" Content="Evidências" Style="{StaticResource NavButton}"/>
                <Button Name="BtnV3NavSafeFix" Content="Correções Seguras" Style="{StaticResource NavButton}"/>
                <Button Name="BtnV3NavAdvanced" Content="Avançado" Style="{StaticResource NavButton}"/>
                <Button Name="BtnV3NavToolkit" Content="Toolkit" Style="{StaticResource NavButton}"/>
            </StackPanel>
        </Border>

        <Grid Grid.Column="1" Margin="24">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Border Grid.Row="0" Background="White" CornerRadius="18" Padding="22" BorderBrush="#E2E8F0" BorderThickness="1">
                <StackPanel>
                    <TextBlock Text="Central de Atendimento Técnico" FontSize="26" FontWeight="Bold" Foreground="#0F172A"/>
                    <TextBlock Text="Experiência limpa, guiada e com menos botões para triagem corporativa." FontSize="13" Foreground="#64748B" Margin="0,4,0,0"/>
                </StackPanel>
            </Border>

            <UniformGrid Grid.Row="1" Columns="4" Margin="0,14,0,14">
                <Border Background="White" CornerRadius="14" Padding="14" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,10,0">
                    <StackPanel>
                        <TextBlock Text="HOSTNAME" Foreground="#64748B" FontSize="11" FontWeight="Bold"/>
                        <TextBlock Name="CardV3Host" Text="-" FontSize="14" FontWeight="Bold" Foreground="#0F172A"/>
                    </StackPanel>
                </Border>

                <Border Background="White" CornerRadius="14" Padding="14" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,10,0">
                    <StackPanel>
                        <TextBlock Text="USUÁRIO" Foreground="#64748B" FontSize="11" FontWeight="Bold"/>
                        <TextBlock Name="CardV3User" Text="-" FontSize="14" FontWeight="Bold" Foreground="#0F172A"/>
                    </StackPanel>
                </Border>

                <Border Background="White" CornerRadius="14" Padding="14" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,10,0">
                    <StackPanel>
                        <TextBlock Text="ADMIN" Foreground="#64748B" FontSize="11" FontWeight="Bold"/>
                        <TextBlock Name="CardV3Admin" Text="-" FontSize="14" FontWeight="Bold" Foreground="#0F172A"/>
                    </StackPanel>
                </Border>

                <Border Background="White" CornerRadius="14" Padding="14" BorderBrush="#E2E8F0" BorderThickness="1">
                    <StackPanel>
                        <TextBlock Text="VERSÃO" Foreground="#64748B" FontSize="11" FontWeight="Bold"/>
                        <TextBlock Name="CardV3Version" Text="-" FontSize="14" FontWeight="Bold" Foreground="#0F172A"/>
                    </StackPanel>
                </Border>
            </UniformGrid>

            <Border Grid.Row="2" Background="White" CornerRadius="18" Padding="18" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,0,14">
                <StackPanel>
                    <TextBlock Text="Ações principais da V3" FontSize="18" FontWeight="Bold" Foreground="#0F172A"/>
                    <TextBlock Text="Poucas ações visíveis. O restante fica protegido ou avançado." FontSize="12" Foreground="#64748B" Margin="0,2,0,10"/>

                    <WrapPanel>
                        <Button Name="BtnV3QuickInternet" Content="Sem internet" Style="{StaticResource PrimaryButton}"/>
                        <Button Name="BtnV3QuickVpn" Content="VPN / Appgate" Style="{StaticResource SoftButton}"/>
                        <Button Name="BtnV3Inventory" Content="Inventário" Style="{StaticResource SoftButton}"/>
                        <Button Name="BtnV3Network" Content="Diagnóstico de rede" Style="{StaticResource SoftButton}"/>
                        <Button Name="BtnV3FlushDns" Content="Limpar DNS" Style="{StaticResource SoftButton}"/>
                        <Button Name="BtnV3TimeSync" Content="Sincronizar horário" Style="{StaticResource SoftButton}"/>
                        <Button Name="BtnV3Spooler" Content="Reiniciar spooler" Style="{StaticResource SoftButton}"/>
                        <Button Name="BtnV3AdvancedInfo" Content="Área avançada protegida" Style="{StaticResource DangerButton}"/>
                        <Button Name="BtnV3CopyOutput" Content="Copiar resultado" Style="{StaticResource SoftButton}"/>
                    </WrapPanel>
                </StackPanel>
            </Border>

            <Border Grid.Row="3" Background="White" CornerRadius="18" Padding="16" BorderBrush="#E2E8F0" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <TextBlock Text="Resultado" FontSize="16" FontWeight="Bold" Foreground="#0F172A" Margin="0,0,0,10"/>

                    <TextBox Name="TxtV3Output"
                             Grid.Row="1"
                             AcceptsReturn="True"
                             TextWrapping="Wrap"
                             VerticalScrollBarVisibility="Auto"
                             HorizontalScrollBarVisibility="Auto"
                             FontFamily="Consolas"
                             FontSize="12"
                             Background="#F8FAFC"
                             BorderBrush="#CBD5E1"
                             BorderThickness="1"/>
                </Grid>
            </Border>
            <Border Grid.Row="4" Background="Transparent" Margin="0,10,0,0">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <TextBlock Grid.Column="0"
                               Text="ServiceDesk Toolkit Corporate V3 - Made by Caio Dal Re"
                               Foreground="#64748B"
                               FontSize="11"
                               VerticalAlignment="Center"/>

                    <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button Name="BtnV3LinkedIn"
                                Content="LinkedIn"
                                Style="{StaticResource FooterLinkButton}"
                                ToolTip="Abrir LinkedIn de Caio Dal Re"/>

                        <Button Name="BtnV3GitHub"
                                Content="GitHub"
                                Style="{StaticResource FooterLinkButton}"
                                ToolTip="Abrir GitHub de Caio Dal Re"/>
                    </StackPanel>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

[xml]$xml = $xaml
$reader = New-Object System.Xml.XmlNodeReader $xml
$window = [Windows.Markup.XamlReader]::Load($reader)

$script:TxtV3Output = $window.FindName("TxtV3Output")

$CardV3Host = $window.FindName("CardV3Host")
$CardV3User = $window.FindName("CardV3User")
$CardV3Admin = $window.FindName("CardV3Admin")
$CardV3Version = $window.FindName("CardV3Version")

$CardV3Host.Text = $env:COMPUTERNAME
$CardV3User.Text = "$env:USERDOMAIN\$env:USERNAME"
$CardV3Admin.Text = if (Test-V3Admin) { "Sim" } else { "Não" }
$CardV3Version.Text = Get-V3VersionInfo

$window.FindName("BtnV3NavHome").Add_Click({ Set-V3Output (Get-V3HomeText) })
$window.FindName("BtnV3NavGuided").Add_Click({ Set-V3Output (Get-V3GuidedHomeText) })
$window.FindName("BtnV3NavEvidence").Add_Click({ Set-V3Output "Evidências:`r`n- Inventário`r`n- Diagnóstico de rede`r`n- Relatório`r`n- Pacote de suporte`r`n- Copiar resultado" })
$window.FindName("BtnV3NavSafeFix").Add_Click({ Set-V3Output "Correções Seguras:`r`n- Limpar DNS`r`n- Renovar IP`r`n- Sincronizar horário`r`n- Reiniciar spooler`r`n- Limpar temporários" })
$window.FindName("BtnV3NavAdvanced").Add_Click({ Set-V3Output "Área avançada:`r`nAções críticas ficarão protegidas por confirmação, mensagem de risco e log.`r`n`r`nExemplos:`r`n- SFC`r`n- DISM`r`n- Reset Winsock`r`n- Reset TCP/IP`r`n- Correções Appgate/TPM" })
$window.FindName("BtnV3NavToolkit").Add_Click({ Set-V3Output "Toolkit:`r`n- Status`r`n- Atualização`r`n- Rollback`r`n- Logs`r`n- Validação`r`n`r`nEssas funções serão conectadas ao motor atual em etapas futuras." })

$window.FindName("BtnV3QuickInternet").Add_Click({ Set-V3Output (Invoke-V3WorkflowNoInternet) })
$window.FindName("BtnV3QuickVpn").Add_Click({ Set-V3Output (Invoke-V3WorkflowVpn) })
$window.FindName("BtnV3Inventory").Add_Click({ Set-V3Output (Get-V3InventoryLite) })
$window.FindName("BtnV3Network").Add_Click({ Set-V3Output (Invoke-V3NetworkDiagnostic) })
$window.FindName("BtnV3FlushDns").Add_Click({ Set-V3Output (Invoke-V3SafeFlushDns) })
$window.FindName("BtnV3TimeSync").Add_Click({ Set-V3Output (Invoke-V3SafeTimeSync) })
$window.FindName("BtnV3Spooler").Add_Click({ Set-V3Output (Invoke-V3SafeSpoolerRestart) })
$window.FindName("BtnV3AdvancedInfo").Add_Click({ Set-V3Output "Área avançada protegida.`r`n`r`nNesta primeira V3, ações críticas não ficam expostas na tela principal.`r`nElas serão conectadas depois com confirmação, risco e log." })
$window.FindName("BtnV3CopyOutput").Add_Click({ Copy-V3OutputToClipboard })
$BtnV3LinkedIn = $window.FindName("BtnV3LinkedIn")
$BtnV3GitHub = $window.FindName("BtnV3GitHub")

if ($null -ne $BtnV3LinkedIn) {
    $BtnV3LinkedIn.Add_Click({
        Open-V3ExternalLink -Url "https://www.linkedin.com/in/caiodalre/" -Label "LinkedIn"
    })
}

if ($null -ne $BtnV3GitHub) {
    $BtnV3GitHub.Add_Click({
        Open-V3ExternalLink -Url "https://github.com/Caiodalre" -Label "GitHub"
    })
}

Set-V3Output (Get-V3HomeText)

[void]$window.ShowDialog()









