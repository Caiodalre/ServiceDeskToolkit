Set-StrictMode -Version 2.0

function New-ToolkitHealthIndicator {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [ValidateSet("OK", "ATENCAO", "CRITICO")]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    return [pscustomobject]@{
        Name = $Name
        Label = $Label
        Status = $Status
        Detail = $Detail
    }
}

function Get-ToolkitMachineHealthAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Snapshot
    )

    $score = 100
    $issues = New-Object 'System.Collections.Generic.List[string]'
    $actions = New-Object 'System.Collections.Generic.List[string]'
    $indicators = New-Object 'System.Collections.Generic.List[object]'

    $systemStatus = "OK"
    $systemDetail = "Sistema operacional identificado"

    if (-not $Snapshot.SystemAvailable) {
        $systemStatus = "CRITICO"
        $systemDetail = "Nao foi possivel coletar informacoes basicas do sistema"
        $score -= 20
        [void]$issues.Add("Falha ao coletar informacoes basicas do Windows.")
        [void]$actions.Add(
            "Validar WMI/CIM, servicos do Windows e permissoes da ferramenta."
        )
    }
    else {
        $systemDetail = "{0} | Build {1} | {2}" -f
            $Snapshot.SystemCaption,
            $Snapshot.SystemBuildNumber,
            $Snapshot.SystemArchitecture
    }

    [void]$indicators.Add(
        (New-ToolkitHealthIndicator `
            -Name "System" `
            -Label "Sistema" `
            -Status $systemStatus `
            -Detail $systemDetail)
    )

    $memoryStatus = "OK"
    $memoryDetail = "Dados de memoria indisponiveis"
    $totalRamGb = [double]$Snapshot.TotalRamGb
    $memoryUsedPercent = [double]$Snapshot.MemoryUsedPercent

    if ($totalRamGb -gt 0) {
        $memoryDetail = "$totalRamGb GB instalados | Uso atual: $memoryUsedPercent%"
    }

    if (
        ($totalRamGb -gt 0 -and $totalRamGb -lt 8) -or
        $memoryUsedPercent -ge 90
    ) {
        $memoryStatus = "CRITICO"
        $score -= 20
        [void]$issues.Add("Memoria RAM em estado critico: $memoryDetail.")
        [void]$actions.Add(
            "Fechar aplicativos pesados, validar processos com consumo elevado e considerar aumento de memoria."
        )
    }
    elseif (
        ($totalRamGb -gt 0 -and $totalRamGb -lt 12) -or
        $memoryUsedPercent -ge 80
    ) {
        $memoryStatus = "ATENCAO"
        $score -= 10
        [void]$issues.Add("Memoria RAM requer atencao: $memoryDetail.")
        [void]$actions.Add(
            "Validar consumo no Gerenciador de Tarefas e reiniciar aplicativos com uso elevado."
        )
    }

    [void]$indicators.Add(
        (New-ToolkitHealthIndicator `
            -Name "Memory" `
            -Label "Memoria RAM" `
            -Status $memoryStatus `
            -Detail $memoryDetail)
    )

    $diskStatus = "OK"
    $diskDetail = "Disco do Windows nao localizado"

    if (-not $Snapshot.DiskAvailable) {
        $diskStatus = "CRITICO"
        $score -= 20
        [void]$issues.Add("Nao foi possivel consultar o disco do Windows.")
        [void]$actions.Add(
            "Validar armazenamento, WMI/CIM e integridade do sistema."
        )
    }
    else {
        $diskDetail = "{0} {1} GB livres de {2} GB ({3}%)" -f
            $Snapshot.SystemDrive,
            $Snapshot.DiskFreeGb,
            $Snapshot.DiskSizeGb,
            $Snapshot.DiskFreePercent

        if (
            [double]$Snapshot.DiskFreeGb -lt 15 -or
            [double]$Snapshot.DiskFreePercent -lt 10
        ) {
            $diskStatus = "CRITICO"
            $score -= 30
            [void]$issues.Add(
                "Disco do Windows com espaco livre critico: $diskDetail."
            )
            [void]$actions.Add(
                "Liberar espaco em disco antes de executar atualizacoes ou reparos."
            )
        }
        elseif (
            [double]$Snapshot.DiskFreeGb -lt 30 -or
            [double]$Snapshot.DiskFreePercent -lt 20
        ) {
            $diskStatus = "ATENCAO"
            $score -= 15
            [void]$issues.Add(
                "Disco do Windows com pouco espaco livre: $diskDetail."
            )
            [void]$actions.Add(
                "Executar limpeza controlada de temporarios e revisar arquivos grandes."
            )
        }
    }

    [void]$indicators.Add(
        (New-ToolkitHealthIndicator `
            -Name "Disk" `
            -Label "Disco do Windows" `
            -Status $diskStatus `
            -Detail $diskDetail)
    )

    $uptimeStatus = "OK"
    $uptimeDetail = "Uptime nao encontrado"

    if ($Snapshot.UptimeAvailable) {
        $uptimeDetail = "$($Snapshot.UptimeDays) dia(s), $($Snapshot.UptimeHours) hora(s)"

        if ([double]$Snapshot.UptimeTotalDays -ge 30) {
            $uptimeStatus = "CRITICO"
            $score -= 10
            [void]$issues.Add("Maquina esta ligada ha mais de 30 dias.")
            [void]$actions.Add("Agendar reinicio completo da maquina.")
        }
        elseif ([double]$Snapshot.UptimeTotalDays -ge 7) {
            $uptimeStatus = "ATENCAO"
            $score -= 5
            [void]$issues.Add("Maquina esta ligada ha mais de 7 dias.")
            [void]$actions.Add(
                "Recomendar reinicio para limpar estados temporarios."
            )
        }
    }

    [void]$indicators.Add(
        (New-ToolkitHealthIndicator `
            -Name "Uptime" `
            -Label "Uptime" `
            -Status $uptimeStatus `
            -Detail $uptimeDetail)
    )

    $networkStatus = "OK"
    $networkDetail = "Nenhum adaptador ativo encontrado"
    $ipv4List = @($Snapshot.IPv4Addresses)
    $gatewayList = @($Snapshot.Gateways)

    if (-not $Snapshot.NetworkAdapterAvailable) {
        $networkStatus = "CRITICO"
        $score -= 25
        [void]$issues.Add(
            "Nenhum adaptador com endereco IPv4 valido foi encontrado."
        )
        [void]$actions.Add("Validar cabo, Wi-Fi, adaptador, driver e DHCP.")
    }
    else {
        $networkDetail = "$($Snapshot.NetworkDescription) | IP: $($ipv4List -join ', ')"

        if (
            @($ipv4List | Where-Object { $_ -like "169.254.*" }).Count -gt 0
        ) {
            $networkStatus = "CRITICO"
            $score -= 25
            [void]$issues.Add("Adaptador recebeu endereco APIPA 169.254.x.x.")
            [void]$actions.Add("Validar DHCP, cabo, Wi-Fi, switch ou VLAN.")
        }
        elseif ($gatewayList.Count -eq 0) {
            $networkStatus = "ATENCAO"
            $score -= 15
            [void]$issues.Add("Adaptador possui IP, mas nao possui gateway.")
            [void]$actions.Add("Validar configuracao de rede e escopo DHCP.")
        }
        else {
            $networkDetail += " | Gateway: $($gatewayList -join ', ')"
        }
    }

    [void]$indicators.Add(
        (New-ToolkitHealthIndicator `
            -Name "Network" `
            -Label "Rede" `
            -Status $networkStatus `
            -Detail $networkDetail)
    )

    $dnsStatus = "OK"
    $dnsDetail = "Resolucao www.microsoft.com funcionando"

    if (-not $Snapshot.DnsResolved) {
        $dnsStatus = "ATENCAO"
        $dnsDetail = "Falha de resolucao DNS"
        $score -= 10
        [void]$issues.Add("Resolucao DNS falhou durante o diagnostico.")
        [void]$actions.Add(
            "Executar Limpar DNS e validar servidores DNS configurados."
        )
    }

    [void]$indicators.Add(
        (New-ToolkitHealthIndicator `
            -Name "Dns" `
            -Label "DNS" `
            -Status $dnsStatus `
            -Detail $dnsDetail)
    )

    $timeStatus = "OK"
    $timeSource = [string]$Snapshot.TimeSource
    $timeServiceText = if ($Snapshot.TimeServiceFound) {
        [string]$Snapshot.TimeServiceStatus
    }
    else {
        "Nao encontrado"
    }
    $timeDetail = if ([string]::IsNullOrWhiteSpace($timeSource)) {
        "Fonte de horario nao encontrada"
    }
    else {
        "Servico: $timeServiceText | Fonte: $timeSource"
    }

    if (
        -not $Snapshot.TimeServiceFound -or
        [string]$Snapshot.TimeServiceStatus -ne "Running" -or
        $timeSource -match "CMOS|Free-running|nao sincronizado|not synchronized|erro|error"
    ) {
        $timeStatus = "ATENCAO"
        $score -= 5
        [void]$issues.Add("Sincronizacao de horario requer validacao.")
        [void]$actions.Add(
            "Executar Sincronizar horario e validar dominio, NTP ou GPO."
        )
    }

    [void]$indicators.Add(
        (New-ToolkitHealthIndicator `
            -Name "Time" `
            -Label "Horario" `
            -Status $timeStatus `
            -Detail $timeDetail)
    )

    $spoolerStatus = "OK"
    $spoolerDetail = "Servico Spooler em execucao"

    if (-not $Snapshot.SpoolerFound) {
        $spoolerStatus = "ATENCAO"
        $spoolerDetail = "Servico Spooler nao encontrado"
        $score -= 5
        [void]$issues.Add("Servico Spooler nao foi encontrado.")
        [void]$actions.Add(
            "Validar recursos de impressao instalados no Windows."
        )
    }
    elseif ([string]$Snapshot.SpoolerStatus -ne "Running") {
        $spoolerStatus = "ATENCAO"
        $spoolerDetail = "Servico Spooler: $($Snapshot.SpoolerStatus)"
        $score -= 5
        [void]$issues.Add("Servico Spooler nao esta em execucao.")
        [void]$actions.Add(
            "Executar Reiniciar spooler como administrador."
        )
    }

    [void]$indicators.Add(
        (New-ToolkitHealthIndicator `
            -Name "Spooler" `
            -Label "Spooler" `
            -Status $spoolerStatus `
            -Detail $spoolerDetail)
    )

    $rebootStatus = if ($Snapshot.PendingReboot) {
        "ATENCAO"
    }
    else {
        "OK"
    }
    $rebootDetail = if ($Snapshot.PendingReboot) {
        "Sim | Motivo(s): $(@($Snapshot.RebootReasons) -join ', ')"
    }
    else {
        "Nao"
    }

    if ($Snapshot.PendingReboot) {
        $score -= 5
        [void]$issues.Add("Windows possui reinicio pendente.")
        [void]$actions.Add(
            "Agendar reinicio da maquina antes de novos reparos."
        )
    }

    [void]$indicators.Add(
        (New-ToolkitHealthIndicator `
            -Name "PendingReboot" `
            -Label "Reinicio pendente" `
            -Status $rebootStatus `
            -Detail $rebootDetail)
    )

    $score = [Math]::Max(0, $score)
    $classification = if ($score -ge 85) {
        "SAUDAVEL"
    }
    elseif ($score -ge 65) {
        "ATENCAO"
    }
    else {
        "CRITICO"
    }

    return [pscustomobject]@{
        Score = $score
        Classification = $classification
        Indicators = $indicators.ToArray()
        Issues = $issues.ToArray()
        Actions = [string[]]@($actions | Select-Object -Unique)
    }
}

function Format-ToolkitMachineHealthReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Snapshot,

        [Parameter(Mandatory = $true)]
        [psobject]$Assessment
    )

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("PAINEL DE SAUDE DA MAQUINA")
    [void]$sb.AppendLine("==========================")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine(
        "Gerado em: $($Snapshot.CollectedAt.ToString('dd/MM/yyyy HH:mm:ss'))"
    )
    [void]$sb.AppendLine("Hostname: $($Snapshot.ComputerName)")
    [void]$sb.AppendLine("Usuario: $($Snapshot.UserName)")
    [void]$sb.AppendLine(
        "Admin: $(if ($Snapshot.IsAdmin) { 'Sim' } else { 'Nao' })"
    )
    [void]$sb.AppendLine("Tipo de acao: Diagnostico geral sem correcao")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("PONTUACAO GERAL")
    [void]$sb.AppendLine("---------------")
    [void]$sb.AppendLine("Pontuacao: $($Assessment.Score) de 100")
    [void]$sb.AppendLine("Classificacao: $($Assessment.Classification)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("INDICADORES")
    [void]$sb.AppendLine("-----------")

    foreach ($indicator in @($Assessment.Indicators)) {
        [void]$sb.AppendLine(
            "$($indicator.Label): $($indicator.Status) | $($indicator.Detail)"
        )
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("CONCLUSAO AUTOMATICA")
    [void]$sb.AppendLine("--------------------")

    if (@($Assessment.Issues).Count -eq 0) {
        [void]$sb.AppendLine(
            "Resultado: maquina saudavel nos indicadores basicos avaliados."
        )
        [void]$sb.AppendLine(
            "Nao foi identificado alerta tecnico evidente."
        )
    }
    else {
        [void]$sb.AppendLine(
            "Resultado: foram encontrados $(@($Assessment.Issues).Count) ponto(s) de atencao."
        )
        [void]$sb.AppendLine("")

        foreach ($issue in @($Assessment.Issues)) {
            [void]$sb.AppendLine("- $issue")
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("PROXIMAS ACOES")
    [void]$sb.AppendLine("--------------")

    if (@($Assessment.Actions).Count -eq 0) {
        [void]$sb.AppendLine("- Nenhuma correcao imediata recomendada.")
        [void]$sb.AppendLine(
            "- Validar o sintoma especifico informado pelo usuario."
        )
    }
    else {
        foreach ($action in @($Assessment.Actions)) {
            [void]$sb.AppendLine("- $action")
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("OBSERVACAO")
    [void]$sb.AppendLine("----------")
    [void]$sb.AppendLine(
        "Este painel realiza somente diagnostico e nao executa correcoes automaticamente."
    )

    return $sb.ToString()
}

Export-ModuleMember -Function @(
    "Get-ToolkitMachineHealthAssessment",
    "Format-ToolkitMachineHealthReport"
)
