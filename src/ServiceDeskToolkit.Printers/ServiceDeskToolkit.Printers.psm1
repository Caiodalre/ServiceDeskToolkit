Set-StrictMode -Version 2.0

function Get-ToolkitPrinterSnapshot {
    [CmdletBinding()]
    param(
        [datetime]$ObservedAt = (Get-Date)
    )

    $spooler = Get-Service `
        -Name "Spooler" `
        -ErrorAction SilentlyContinue
    $printers = @(
        Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue
    )
    $jobs = @(
        Get-CimInstance Win32_PrintJob -ErrorAction SilentlyContinue
    )
    $drivers = @(
        Get-CimInstance `
            Win32_PrinterDriver `
            -ErrorAction SilentlyContinue
    )
    $ports = @()

    if (Get-Command Get-PrinterPort -ErrorAction SilentlyContinue) {
        try {
            $ports = @(
                Get-PrinterPort -ErrorAction SilentlyContinue
            )
        }
        catch {
            $ports = @()
        }
    }

    $defaultPrinter = $printers |
        Where-Object { $_.Default -eq $true } |
        Select-Object -First 1
    $offlinePrinters = @(
        $printers |
            Where-Object { $_.WorkOffline -eq $true }
    )
    $errorPrinters = @(
        $printers |
            Where-Object {
                $_.PrinterStatus -in @(4, 5, 6, 7)
            }
    )
    $networkPrinters = @(
        $printers |
            Where-Object { $_.Network -eq $true }
    )
    $localPrinters = @(
        $printers |
            Where-Object { $_.Local -eq $true }
    )
    $alertPrinters = @(
        $offlinePrinters + $errorPrinters |
            Sort-Object Name -Unique
    )

    return [pscustomobject]@{
        ObservedAt = $ObservedAt
        Spooler = $spooler
        Printers = [object[]]$printers
        Jobs = [object[]]$jobs
        Drivers = [object[]]$drivers
        Ports = [object[]]$ports
        DefaultPrinter = $defaultPrinter
        OfflinePrinters = [object[]]$offlinePrinters
        ErrorPrinters = [object[]]$errorPrinters
        NetworkPrinters = [object[]]$networkPrinters
        LocalPrinters = [object[]]$localPrinters
        AlertPrinters = [object[]]$alertPrinters
    }
}

function Get-ToolkitPrinterAssessment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Snapshot
    )

    $observations = New-Object 'System.Collections.Generic.List[string]'
    $spooler = $Snapshot.Spooler
    $printers = @($Snapshot.Printers)
    $jobs = @($Snapshot.Jobs)
    $offlinePrinters = @($Snapshot.OfflinePrinters)
    $errorPrinters = @($Snapshot.ErrorPrinters)

    if ($null -eq $spooler) {
        $observations.Add("Servico Spooler nao foi encontrado.")
    }
    elseif ($spooler.Status -ne "Running") {
        $observations.Add(
            "Servico Spooler nao esta em execucao."
        )
    }

    if ($printers.Count -eq 0) {
        $observations.Add(
            "Nenhuma impressora instalada foi encontrada."
        )
    }

    if (
        $null -eq $Snapshot.DefaultPrinter -and
        $printers.Count -gt 0
    ) {
        $observations.Add(
            "Ha impressoras instaladas, mas nenhuma impressora padrao foi encontrada."
        )
    }

    if ($offlinePrinters.Count -gt 0) {
        $observations.Add(
            "Existem $($offlinePrinters.Count) impressora(s) offline."
        )
    }

    if ($jobs.Count -gt 0) {
        $observations.Add(
            "Existem $($jobs.Count) job(s) na fila de impressao."
        )
    }

    if ($errorPrinters.Count -gt 0) {
        $observations.Add(
            "Existem $($errorPrinters.Count) impressora(s) com status de alerta."
        )
    }

    $nextAction = $null

    if ($observations.Count -gt 0) {
        if ($null -eq $spooler -or $spooler.Status -ne "Running") {
            $nextAction = (
                "Executar Reiniciar spooler como administrador."
            )
        }
        elseif ($jobs.Count -gt 0) {
            $nextAction = (
                "Validar documentos travados na fila e considerar " +
                "limpeza controlada da fila."
            )
        }
        elseif ($offlinePrinters.Count -gt 0) {
            $nextAction = (
                "Validar conexao da impressora, porta, IP, cabo/rede " +
                "e status fisico do equipamento."
            )
        }
        elseif (
            $null -eq $Snapshot.DefaultPrinter -and
            $printers.Count -gt 0
        ) {
            $nextAction = (
                "Definir impressora padrao conforme unidade/setor."
            )
        }
        else {
            $nextAction = (
                "Coletar erro exato, validar driver, porta e " +
                "aplicativo de origem."
            )
        }
    }

    return [pscustomobject]@{
        HasObservations = ($observations.Count -gt 0)
        Observations = $observations.ToArray()
        NextAction = $nextAction
    }
}

function Get-ToolkitPrinterStatusText {
    param(
        $PrinterStatus
    )

    $statusText = switch ($PrinterStatus) {
        1 { "Outro" }
        2 { "Desconhecido" }
        3 { "Ociosa/Pronta" }
        4 { "Imprimindo" }
        5 { "Aquecendo" }
        6 { "Parada" }
        7 { "Offline" }
        default { "Status $PrinterStatus" }
    }

    return $statusText
}

function Format-ToolkitPrinterReport {
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
    $spooler = $Snapshot.Spooler
    $printers = @($Snapshot.Printers)
    $jobs = @($Snapshot.Jobs)
    $drivers = @($Snapshot.Drivers)
    $ports = @($Snapshot.Ports)
    $offlinePrinters = @($Snapshot.OfflinePrinters)
    $errorPrinters = @($Snapshot.ErrorPrinters)
    $networkPrinters = @($Snapshot.NetworkPrinters)
    $localPrinters = @($Snapshot.LocalPrinters)
    $alertPrinters = @($Snapshot.AlertPrinters)

    [void]$sb.AppendLine(
        "PAINEL DE IMPRESSORAS - DIAGNOSTICO CONSOLIDADO"
    )
    [void]$sb.AppendLine(
        "------------------------------------------------"
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
        "Tipo de acao: Diagnostico de impressoras sem correcao"
    )
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("SERVICO SPOOLER")
    [void]$sb.AppendLine("---------------")

    if ($null -eq $spooler) {
        [void]$sb.AppendLine(
            "Status: Servico Spooler nao encontrado"
        )
    }
    else {
        [void]$sb.AppendLine("Status: $($spooler.Status)")
        [void]$sb.AppendLine("Nome: $($spooler.Name)")
        [void]$sb.AppendLine(
            "DisplayName: $($spooler.DisplayName)"
        )
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("RESUMO")
    [void]$sb.AppendLine("------")
    [void]$sb.AppendLine(
        "Total de impressoras: $($printers.Count)"
    )
    [void]$sb.AppendLine(
        "Impressoras locais: $($localPrinters.Count)"
    )
    [void]$sb.AppendLine(
        "Impressoras de rede: $($networkPrinters.Count)"
    )
    [void]$sb.AppendLine(
        "Impressoras offline: $($offlinePrinters.Count)"
    )
    [void]$sb.AppendLine(
        "Impressoras com possivel erro: $($errorPrinters.Count)"
    )
    [void]$sb.AppendLine("Jobs na fila: $($jobs.Count)")
    [void]$sb.AppendLine(
        "Impressora padrao: $(if ($Snapshot.DefaultPrinter) { $Snapshot.DefaultPrinter.Name } else { 'Nao encontrada' })"
    )
    [void]$sb.AppendLine("")

    [void]$sb.AppendLine("IMPRESSORAS INSTALADAS")
    [void]$sb.AppendLine("----------------------")

    if ($printers.Count -eq 0) {
        [void]$sb.AppendLine("Nenhuma impressora encontrada.")
    }
    else {
        foreach ($printer in ($printers | Sort-Object Name)) {
            $statusText = Get-ToolkitPrinterStatusText `
                -PrinterStatus $printer.PrinterStatus

            [void]$sb.AppendLine("Nome: $($printer.Name)")
            [void]$sb.AppendLine(
                "Padrao: $(if ($printer.Default) { 'Sim' } else { 'Nao' })"
            )
            [void]$sb.AppendLine(
                "Local/Rede: $(if ($printer.Network) { 'Rede' } elseif ($printer.Local) { 'Local' } else { 'Nao identificado' })"
            )
            [void]$sb.AppendLine("Status: $statusText")
            [void]$sb.AppendLine(
                "Offline: $(if ($printer.WorkOffline) { 'Sim' } else { 'Nao' })"
            )
            [void]$sb.AppendLine(
                "Porta: $(if ($printer.PortName) { $printer.PortName } else { 'Nao informada' })"
            )
            [void]$sb.AppendLine(
                "Driver: $(if ($printer.DriverName) { $printer.DriverName } else { 'Nao informado' })"
            )
            [void]$sb.AppendLine("")
        }
    }

    [void]$sb.AppendLine("FILA DE IMPRESSAO")
    [void]$sb.AppendLine("-----------------")

    if ($jobs.Count -eq 0) {
        [void]$sb.AppendLine(
            "Nenhum job de impressao encontrado."
        )
    }
    else {
        foreach ($job in ($jobs | Sort-Object Name)) {
            [void]$sb.AppendLine("Job: $($job.Name)")
            [void]$sb.AppendLine(
                "Documento: $(if ($job.Document) { $job.Document } else { 'Nao informado' })"
            )
            [void]$sb.AppendLine(
                "Usuario: $(if ($job.Owner) { $job.Owner } else { 'Nao informado' })"
            )
            [void]$sb.AppendLine(
                "Status: $(if ($job.Status) { $job.Status } else { 'Nao informado' })"
            )
            [void]$sb.AppendLine(
                "Tamanho: $(if ($job.Size) { "$($job.Size) bytes" } else { 'Nao informado' })"
            )
            [void]$sb.AppendLine(
                "Paginas: $(if ($job.TotalPages) { $job.TotalPages } else { 'Nao informado' })"
            )
            [void]$sb.AppendLine("")
        }
    }

    [void]$sb.AppendLine("IMPRESSORAS OFFLINE / COM ALERTA")
    [void]$sb.AppendLine("--------------------------------")

    if ($alertPrinters.Count -eq 0) {
        [void]$sb.AppendLine(
            "Nenhuma impressora offline ou com alerta evidente encontrada."
        )
    }
    else {
        foreach ($printer in $alertPrinters) {
            [void]$sb.AppendLine(
                "- $($printer.Name) | Offline: $(if ($printer.WorkOffline) { 'Sim' } else { 'Nao' }) | Status: $($printer.PrinterStatus) | Porta: $($printer.PortName)"
            )
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("PORTAS UTILIZADAS")
    [void]$sb.AppendLine("-----------------")

    if ($ports.Count -gt 0) {
        foreach (
            $port in (
                $ports |
                    Sort-Object Name |
                    Select-Object -First 30
            )
        ) {
            $hostAddress = ""

            if (
                $port.PSObject.Properties.Name -contains
                "PrinterHostAddress"
            ) {
                $hostAddress = $port.PrinterHostAddress
            }

            [void]$sb.AppendLine(
                "Porta: $($port.Name) | Host/IP: $(if ($hostAddress) { $hostAddress } else { 'Nao informado' })"
            )
        }

        if ($ports.Count -gt 30) {
            [void]$sb.AppendLine(
                "Observacao: exibindo as primeiras 30 portas de $($ports.Count)."
            )
        }
    }
    else {
        $usedPorts = @(
            $printers |
                Where-Object { $_.PortName } |
                Select-Object -ExpandProperty PortName -Unique |
                Sort-Object
        )

        if ($usedPorts.Count -gt 0) {
            foreach ($portName in $usedPorts) {
                [void]$sb.AppendLine("Porta em uso: $portName")
            }
        }
        else {
            [void]$sb.AppendLine("Nenhuma porta encontrada.")
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("DRIVERS PRINCIPAIS")
    [void]$sb.AppendLine("------------------")

    $usedDrivers = @(
        $printers |
            Where-Object { $_.DriverName } |
            Select-Object -ExpandProperty DriverName -Unique |
            Sort-Object
    )

    if ($usedDrivers.Count -eq 0) {
        [void]$sb.AppendLine(
            "Nenhum driver associado encontrado."
        )
    }
    else {
        foreach ($driverName in $usedDrivers) {
            $driverInfo = $drivers |
                Where-Object { $_.Name -like "*$driverName*" } |
                Select-Object -First 1

            if ($driverInfo) {
                [void]$sb.AppendLine(
                    "Driver: $driverName | Versao: $(if ($driverInfo.DriverVersion) { $driverInfo.DriverVersion } else { 'Nao informada' })"
                )
            }
            else {
                [void]$sb.AppendLine("Driver: $driverName")
            }
        }
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("CONCLUSAO AUTOMATICA")
    [void]$sb.AppendLine("--------------------")

    if (-not $Assessment.HasObservations) {
        [void]$sb.AppendLine(
            "Resultado: ambiente de impressao sem alerta evidente nos testes basicos."
        )
        [void]$sb.AppendLine(
            "Proxima acao recomendada: validar erro especifico do usuario, aplicativo de origem e impressora de destino."
        )
    }
    else {
        [void]$sb.AppendLine(
            "Resultado: foram encontrados pontos de atencao no ambiente de impressao."
        )
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Observacoes:")

        foreach ($item in @($Assessment.Observations)) {
            [void]$sb.AppendLine("- $item")
        }

        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Proxima acao recomendada:")
        [void]$sb.AppendLine("- $($Assessment.NextAction)")
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("OBSERVACOES PARA ATENDIMENTO")
    [void]$sb.AppendLine("----------------------------")
    [void]$sb.AppendLine(
        "- Este painel nao executa nenhuma correcao."
    )
    [void]$sb.AppendLine(
        "- Use Reiniciar spooler apenas quando fizer sentido para o erro apresentado."
    )
    [void]$sb.AppendLine(
        "- Para limpeza de fila, validar impacto antes de remover jobs."
    )
    [void]$sb.AppendLine(
        "- Use Copiar resultado para anexar o diagnostico ao chamado."
    )

    return $sb.ToString()
}

Export-ModuleMember -Function @(
    'Get-ToolkitPrinterSnapshot',
    'Get-ToolkitPrinterAssessment',
    'Format-ToolkitPrinterReport'
)
