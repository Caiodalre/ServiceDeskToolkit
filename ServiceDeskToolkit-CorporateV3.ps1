Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

$script:RootPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:TxtV3Output = $null
$script:V3HealthModulesAvailable = $false
$script:V3HealthModuleError = $null
$script:V3RepairMonitor = $null
$script:V3RepairJob = $null
$script:V3RepairProcessId = $null
$script:V3RepairStartedAt = $null
$script:V3RepairProcessExitObservedAt = $null

try {
    $diagnosticsModulePath = Join-Path `
        $script:RootPath `
        "src\ServiceDeskToolkit.Diagnostics\ServiceDeskToolkit.Diagnostics.psm1"
    $healthModulePath = Join-Path `
        $script:RootPath `
        "src\ServiceDeskToolkit.Health\ServiceDeskToolkit.Health.psm1"

    Import-Module `
        -Name $diagnosticsModulePath `
        -Force `
        -ErrorAction Stop
    Import-Module `
        -Name $healthModulePath `
        -Force `
        -ErrorAction Stop

    $script:V3HealthModulesAvailable = $true
}
catch {
    $script:V3HealthModuleError = $_.Exception.Message
}

$script:V3OperationalModulesAvailable = $false
$script:V3OperationalModuleError = $null

try {
    $operationalModulePaths = @(
        "src\ServiceDeskToolkit.Inventory\ServiceDeskToolkit.Inventory.psm1",
        "src\ServiceDeskToolkit.Network\ServiceDeskToolkit.Network.psm1",
        "src\ServiceDeskToolkit.Printers\ServiceDeskToolkit.Printers.psm1",
        "src\ServiceDeskToolkit.Office\ServiceDeskToolkit.Office.psm1"
    )

    foreach ($relativeModulePath in $operationalModulePaths) {
        $modulePath = Join-Path `
            $script:RootPath `
            $relativeModulePath

        Import-Module `
            -Name $modulePath `
            -Force `
            -ErrorAction Stop
    }

    $script:V3OperationalModulesAvailable = $true
}
catch {
    $script:V3OperationalModuleError = $_.Exception.Message
}

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

function New-V3OperationalFailureReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Header,

        [Parameter(Mandatory = $true)]
        [string]$Divider,

        [Parameter(Mandatory = $true)]
        [string]$ActionType,

        [Parameter(Mandatory = $true)]
        [string]$FailureMessage,

        [string]$ErrorDetail,
        [datetime]$GeneratedAt = (Get-Date)
    )

    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine($Header)
    [void]$sb.AppendLine($Divider)
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine(
        "Gerado em: $($GeneratedAt.ToString('dd/MM/yyyy HH:mm:ss'))"
    )
    [void]$sb.AppendLine("Hostname: $env:COMPUTERNAME")
    [void]$sb.AppendLine(
        "Usuario: $env:USERDOMAIN\$env:USERNAME"
    )
    [void]$sb.AppendLine(
        "Admin: $(if (Test-V3Admin) { 'Sim' } else { 'Nao' })"
    )
    [void]$sb.AppendLine("Tipo de acao: $ActionType")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine($FailureMessage)

    if (-not [string]::IsNullOrWhiteSpace($ErrorDetail)) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Detalhe: $ErrorDetail")
    }

    return $sb.ToString()
}

function Get-V3VersionInfo {
    try {
        $versionPath = Join-Path $script:RootPath "version-v3.json"

        if (Test-Path $versionPath) {
            $json = Get-Content $versionPath -Raw | ConvertFrom-Json

            if (-not [string]::IsNullOrWhiteSpace([string]$json.version)) {
                $channel = if ([string]::IsNullOrWhiteSpace([string]$json.channel)) {
                    "canal não informado"
                }
                else {
                    [string]$json.channel
                }

                return "$($json.version) / $channel"
            }
        }

        return "V3 Preview / versão não informada"
    }
    catch {
        return "V3 Preview / versão inválida"
    }
}

function Set-V3Output {
    param([string]$Text)

    if ($null -ne $script:TxtV3Output) {
        $script:TxtV3Output.Text = $Text
    }
}

function Get-V3WindowsRepairDirectory {
    $repairDirectory = Join-Path $script:RootPath "logs\windows-repair"

    if (-not (Test-Path $repairDirectory)) {
        New-Item -Path $repairDirectory -ItemType Directory -Force | Out-Null
    }

    return $repairDirectory
}

function Write-V3WindowsRepairAudit {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("SFC", "DISM")]
        [string]$Tool,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [string]$Message
    )

    try {
        $repairDirectory = Get-V3WindowsRepairDirectory
        $auditPath = Join-Path $repairDirectory "windows-repair-audit.jsonl"
        $entry = [ordered]@{
            timestamp = (Get-Date).ToString("o")
            computer = $env:COMPUTERNAME
            user = "$env:USERDOMAIN\$env:USERNAME"
            tool = $Tool
            status = $Status
            message = $Message
        }

        Add-Content `
            -Path $auditPath `
            -Value ($entry | ConvertTo-Json -Compress) `
            -Encoding UTF8
    }
    catch {
        # O log de auditoria não deve impedir a execução da ferramenta.
    }
}

function New-V3WindowsRepairWorker {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("SFC", "DISM")]
        [string]$Tool
    )

    $repairDirectory = Get-V3WindowsRepairDirectory
    $stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

    if ($Tool -eq "SFC") {
        $displayName = "SFC /scannow"
        $commandPath = Join-Path $env:SystemRoot "System32\sfc.exe"
        $commandArguments = @("/scannow")
    }
    else {
        $displayName = "DISM RestoreHealth"
        $commandPath = Join-Path $env:SystemRoot "System32\dism.exe"
        $commandArguments = @(
            "/Online",
            "/Cleanup-Image",
            "/RestoreHealth"
        )
    }

    if (-not (Test-Path $commandPath)) {
        throw "Executável do $Tool não encontrado: $commandPath"
    }

    $workerPath = Join-Path $repairDirectory "$($Tool.ToLowerInvariant())-$stamp.ps1"
    $logPath = Join-Path $repairDirectory "$($Tool.ToLowerInvariant())-$stamp.log"
    $summaryPath = Join-Path $repairDirectory "$($Tool.ToLowerInvariant())-$stamp-summary.txt"
    $auditPath = Join-Path $repairDirectory "windows-repair-audit.jsonl"

    $escapeLiteral = {
        param([string]$Value)
        return "'" + $Value.Replace("'", "''") + "'"
    }

    $argumentLiterals = @(
        $commandArguments | ForEach-Object {
            & $escapeLiteral ([string]$_)
        }
    ) -join ", "

    $workerTemplate = @'
$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$toolName = __TOOL_NAME__
$displayName = __DISPLAY_NAME__
$commandPath = __COMMAND_PATH__
$commandArguments = @(__COMMAND_ARGUMENTS__)
$logPath = __LOG_PATH__
$summaryPath = __SUMMARY_PATH__
$auditPath = __AUDIT_PATH__

try {
    $Host.UI.RawUI.WindowTitle = "ServiceDesk Toolkit - $displayName"
}
catch {
}

Clear-Host
Write-Host "ServiceDesk Toolkit Corporate V3" -ForegroundColor Cyan
Write-Host "Reparo protegido do Windows" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "Ferramenta: $displayName" -ForegroundColor White
Write-Host "Início: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Gray
Write-Host "Log: $logPath" -ForegroundColor Gray
Write-Host ""
Write-Host "Não feche esta janela durante a execução." -ForegroundColor Yellow
Write-Host "O progresso abaixo é fornecido pelo próprio Windows." -ForegroundColor Yellow
Write-Host ""

$startedAt = Get-Date
$header = @(
    "ServiceDesk Toolkit Corporate V3"
    "Ferramenta: $displayName"
    "Computador: $env:COMPUTERNAME"
    "Usuário: $env:USERDOMAIN\$env:USERNAME"
    "Início: $($startedAt.ToString('o'))"
    "Comando: $commandPath $($commandArguments -join ' ')"
    "========================================"
)
$header | Set-Content -Path $logPath -Encoding UTF8

$processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.FileName = $commandPath
$processInfo.Arguments = $commandArguments -join " "
$processInfo.UseShellExecute = $false
$processInfo.CreateNoWindow = $true
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$nativeEncoding = [System.Text.Encoding]::GetEncoding(
    (Get-Culture).TextInfo.OEMCodePage
)
$processInfo.StandardOutputEncoding = $nativeEncoding
$processInfo.StandardErrorEncoding = $nativeEncoding

$nativeProcess = New-Object System.Diagnostics.Process
$nativeProcess.StartInfo = $processInfo

if (-not $nativeProcess.Start()) {
    throw "O processo $displayName não pôde ser iniciado."
}

$standardOutputTask = $nativeProcess.StandardOutput.ReadToEndAsync()
$standardErrorTask = $nativeProcess.StandardError.ReadToEndAsync()
$nativeProcess.WaitForExit()

$standardOutput = $standardOutputTask.Result
$standardError = $standardErrorTask.Result
$exitCode = $nativeProcess.ExitCode
$nativeOutput = @(
    $standardOutput
    $standardError
) | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_)
}

$outputText = $nativeOutput -join [Environment]::NewLine

if (-not [string]::IsNullOrWhiteSpace($outputText)) {
    $outputText | Add-Content -Path $logPath -Encoding UTF8
    Write-Host $outputText
}

$completedAt = Get-Date
$status = "Concluído; revise o resultado técnico."
$nextAction = "Guardar o log e validar se o sintoma original foi resolvido."

if ($toolName -eq "SFC") {
    if ($outputText -match "não encontrou nenhuma violação de integridade|did not find any integrity violations") {
        $status = "Íntegro: nenhuma violação de integridade foi encontrada."
        $nextAction = "Nenhum reparo adicional é necessário pelo SFC."
    }
    elseif ($outputText -match "encontrou arquivos corrompidos e os reparou com êxito|found corrupt files and successfully repaired them") {
        $status = "Reparado: o SFC encontrou e corrigiu arquivos corrompidos."
        $nextAction = "Reiniciar o computador e executar o SFC novamente para confirmação."
    }
    elseif ($outputText -match "encontrou arquivos corrompidos, mas não pôde corrigir alguns deles|found corrupt files but was unable to fix some of them") {
        $status = "Atenção: há arquivos que o SFC não conseguiu reparar."
        $nextAction = "Executar DISM RestoreHealth e depois repetir o SFC."
    }
    elseif ($outputText -match "não pôde executar a operação solicitada|could not perform the requested operation") {
        $status = "Falha: o SFC não conseguiu executar a verificação."
        $nextAction = "Reiniciar o Windows e tentar novamente; se persistir, verificar o CBS.log."
    }
}
elseif ($toolName -eq "DISM") {
    if ($outputText -match "operação de restauração foi concluída com êxito|restore operation completed successfully|component store corruption was repaired") {
        $status = "Reparado: a imagem do Windows foi restaurada com êxito."
        $nextAction = "Executar o SFC /scannow para validar e reparar os arquivos do sistema."
    }
    elseif ($exitCode -eq 3010) {
        $status = "Concluído: o DISM solicita reinicialização."
        $nextAction = "Reiniciar o computador e depois executar o SFC /scannow."
    }
}

if ($exitCode -ne 0 -and $exitCode -ne 3010) {
    $status = "Falha ou conclusão com alerta. Código de saída: $exitCode."

    if ($toolName -eq "DISM") {
        $nextAction = "Verificar internet, Windows Update e o log do DISM; depois repetir o reparo."
    }
    else {
        $nextAction = "Verificar o log e o CBS.log antes de repetir a operação."
    }
}

$summary = @"
RESULTADO DO REPARO
===================

Ferramenta: $displayName
Início: $($startedAt.ToString('dd/MM/yyyy HH:mm:ss'))
Fim: $($completedAt.ToString('dd/MM/yyyy HH:mm:ss'))
Duração: $([math]::Round(($completedAt - $startedAt).TotalMinutes, 2)) minuto(s)
Código de saída: $exitCode

Conclusão:
$status

Próxima ação:
$nextAction

Log completo:
$logPath
"@

$summary | Set-Content -Path $summaryPath -Encoding UTF8
$summary | Add-Content -Path $logPath -Encoding UTF8

try {
    $auditEntry = [ordered]@{
        timestamp = (Get-Date).ToString("o")
        computer = $env:COMPUTERNAME
        user = "$env:USERDOMAIN\$env:USERNAME"
        tool = $toolName
        status = "Completed"
        exitCode = $exitCode
        conclusion = $status
        logPath = $logPath
        summaryPath = $summaryPath
    }

    Add-Content `
        -Path $auditPath `
        -Value ($auditEntry | ConvertTo-Json -Compress) `
        -Encoding UTF8
}
catch {
}

Write-Host ""
Write-Host $summary -ForegroundColor Green
Write-Host ""
Write-Host "Resumo salvo em: $summaryPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "A conclusão também foi enviada à tela principal." -ForegroundColor Cyan
Write-Host "Esta janela será fechada automaticamente." -ForegroundColor Gray
Start-Sleep -Seconds 8
'@

    $workerText = $workerTemplate
    $workerText = $workerText.Replace("__TOOL_NAME__", (& $escapeLiteral $Tool))
    $workerText = $workerText.Replace("__DISPLAY_NAME__", (& $escapeLiteral $displayName))
    $workerText = $workerText.Replace("__COMMAND_PATH__", (& $escapeLiteral $commandPath))
    $workerText = $workerText.Replace("__COMMAND_ARGUMENTS__", $argumentLiterals)
    $workerText = $workerText.Replace("__LOG_PATH__", (& $escapeLiteral $logPath))
    $workerText = $workerText.Replace("__SUMMARY_PATH__", (& $escapeLiteral $summaryPath))
    $workerText = $workerText.Replace("__AUDIT_PATH__", (& $escapeLiteral $auditPath))

    [System.IO.File]::WriteAllText(
        $workerPath,
        $workerText,
        (New-Object System.Text.UTF8Encoding($true))
    )

    return [pscustomobject]@{
        Tool = $Tool
        DisplayName = $displayName
        WorkerPath = $workerPath
        LogPath = $logPath
        SummaryPath = $summaryPath
        AuditPath = $auditPath
    }
}

function Invoke-V3WindowsRepair {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("SFC", "DISM")]
        [string]$Tool
    )

    try {
        if ($null -ne $script:V3RepairProcessId) {
            $activeRepairProcess = Get-Process `
                -Id $script:V3RepairProcessId `
                -ErrorAction SilentlyContinue

            if ($null -ne $activeRepairProcess) {
                return @"
JÁ EXISTE UM REPARO EM ANDAMENTO
================================

Aguarde a conclusão da ação atual antes de iniciar outro SFC ou DISM.

Processo: $script:V3RepairProcessId
Início: $($script:V3RepairStartedAt.ToString('dd/MM/yyyy HH:mm:ss'))
"@
            }
        }

        $job = New-V3WindowsRepairWorker -Tool $Tool
        $powerShellPath = Join-Path $PSHOME "powershell.exe"

        if (-not (Test-Path $powerShellPath)) {
            $powerShellCommand = Get-Command "powershell.exe" -ErrorAction Stop
            $powerShellPath = $powerShellCommand.Source
        }

        Write-V3WindowsRepairAudit `
            -Tool $Tool `
            -Status "Requested" `
            -Message "Execução elevada solicitada."

        $argumentList = "-NoProfile -ExecutionPolicy Bypass -File `"$($job.WorkerPath)`""

        $repairProcess = Start-Process `
            -FilePath $powerShellPath `
            -ArgumentList $argumentList `
            -WorkingDirectory $script:RootPath `
            -Verb RunAs `
            -PassThru `
            -ErrorAction Stop

        $repairProcess = Get-Process `
            -Id $repairProcess.Id `
            -ErrorAction SilentlyContinue

        if ($null -eq $repairProcess) {
            throw "O processo administrativo foi solicitado, mas não pôde ser monitorado."
        }

        Start-V3WindowsRepairMonitor `
            -Job $job `
            -ProcessId $repairProcess.Id

        Write-V3WindowsRepairAudit `
            -Tool $Tool `
            -Status "Started" `
            -Message "Processo elevado iniciado. Log: $($job.LogPath)"

        return @"
REPARO DO WINDOWS INICIADO
==========================

Ferramenta: $($job.DisplayName)
Execução: janela administrativa separada

O que fazer agora:
1. Aceite a confirmação do Windows, se for exibida.
2. Acompanhe o progresso na nova janela.
3. Não desligue o computador durante o processo.
4. Ao final, leia a conclusão e a próxima ação recomendada.

Log completo:
$($job.LogPath)

Resumo final:
$($job.SummaryPath)
"@
    }
    catch {
        $message = $_.Exception.Message

        Write-V3WindowsRepairAudit `
            -Tool $Tool `
            -Status "FailedToStart" `
            -Message $message

        return @"
NÃO FOI POSSÍVEL INICIAR O REPARO
=================================

Ferramenta: $Tool
Motivo: $message

Se a janela de permissão administrativa foi cancelada, clique novamente e aceite a solicitação do Windows.
"@
    }
}

function Stop-V3WindowsRepairMonitor {
    if ($null -ne $script:V3RepairMonitor) {
        try {
            $script:V3RepairMonitor.Stop()
        }
        catch {
            Write-Verbose (
                "Falha ao interromper monitor anterior: " +
                $_.Exception.Message
            )
        }
    }

    $script:V3RepairMonitor = $null
}

function Get-V3WindowsRepairProgressText {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Job,

        [Parameter(Mandatory = $true)]
        [datetime]$StartedAt,

        [bool]$ProcessIsRunning
    )

    $elapsed = New-TimeSpan -Start $StartedAt -End (Get-Date)
    $elapsedText = if ($elapsed.TotalMinutes -ge 1) {
        "{0:N1} minuto(s)" -f $elapsed.TotalMinutes
    }
    else {
        "{0:N0} segundo(s)" -f $elapsed.TotalSeconds
    }

    $logAvailable = Test-Path $Job.LogPath

    $statusText = if ($ProcessIsRunning -and $logAvailable) {
        "EM ANDAMENTO"
    }
    elseif ($ProcessIsRunning) {
        "AGUARDANDO INICIALIZAÇÃO"
    }
    else {
        "FINALIZANDO"
    }

    $latestLines = @()

    if ($logAvailable) {
        try {
            $latestLines = @(
                Get-Content `
                    -Path $Job.LogPath `
                    -Tail 12 `
                    -ErrorAction Stop
            ) | Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_)
            }
        }
        catch {
            $latestLines = @()
        }
    }

    $latestText = if ($latestLines.Count -gt 0) {
        $latestLines -join [Environment]::NewLine
    }
    else {
        "Aguardando a primeira mensagem do Windows."
    }

    return @"
REPARO DO WINDOWS - $statusText
===============================

Ferramenta: $($Job.DisplayName)
Início: $($StartedAt.ToString('dd/MM/yyyy HH:mm:ss'))
Tempo decorrido: $elapsedText

O processo pode permanecer alguns minutos sem alterar o percentual.
Não feche a janela administrativa enquanto esta tela indicar EM ANDAMENTO.
Se estiver aguardando inicialização, confira a solicitação administrativa do Windows.

Últimas mensagens:
------------------
$latestText

Log:
$($Job.LogPath)
"@
}

function Start-V3WindowsRepairMonitor {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Job,

        [Parameter(Mandatory = $true)]
        [int]$ProcessId
    )

    Stop-V3WindowsRepairMonitor

    $script:V3RepairJob = $Job
    $script:V3RepairProcessId = $ProcessId
    $script:V3RepairStartedAt = Get-Date
    $script:V3RepairProcessExitObservedAt = $null

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromSeconds(2)
    $timer.Add_Tick({
        try {
            $job = $script:V3RepairJob

            if ($null -eq $job) {
                Stop-V3WindowsRepairMonitor
                return
            }

            if (Test-Path $job.SummaryPath) {
                $summaryText = Get-Content `
                    -Path $job.SummaryPath `
                    -Raw `
                    -ErrorAction Stop

                Set-V3Output @"
REPARO DO WINDOWS - CONCLUÍDO
============================

$summaryText

O resultado acima foi registrado automaticamente pelo toolkit.
"@

                Stop-V3WindowsRepairMonitor
                $script:V3RepairProcessId = $null
                $script:V3RepairJob = $null
                return
            }

            $repairProcess = Get-Process `
                -Id $script:V3RepairProcessId `
                -ErrorAction SilentlyContinue
            $processIsRunning = $null -ne $repairProcess

            if ($processIsRunning) {
                $script:V3RepairProcessExitObservedAt = $null

                $initializationElapsed = New-TimeSpan `
                    -Start $script:V3RepairStartedAt `
                    -End (Get-Date)

                if (
                    -not (Test-Path $job.LogPath) -and
                    $initializationElapsed.TotalSeconds -ge 30
                ) {
                    Set-V3Output @"
REPARO DO WINDOWS - FALHA AO INICIAR
====================================

Ferramenta: $($job.DisplayName)

O toolkit abriu o processo administrativo, mas o worker não começou em até 30 segundos.
Nenhum diagnóstico foi considerado concluído.

Próxima ação:
1. Feche qualquer janela administrativa que tenha ficado aberta.
2. Execute novamente.
3. Aceite a solicitação de administrador do Windows.
"@

                    Write-V3WindowsRepairAudit `
                        -Tool $job.Tool `
                        -Status "FailedToInitialize" `
                        -Message "Worker não criou o log em até 30 segundos."

                    Stop-V3WindowsRepairMonitor
                    $script:V3RepairProcessId = $null
                    $script:V3RepairJob = $null
                    return
                }

                Set-V3Output (
                    Get-V3WindowsRepairProgressText `
                        -Job $job `
                        -StartedAt $script:V3RepairStartedAt `
                        -ProcessIsRunning $true
                )
                return
            }

            if ($null -eq $script:V3RepairProcessExitObservedAt) {
                $script:V3RepairProcessExitObservedAt = Get-Date
                Set-V3Output (
                    Get-V3WindowsRepairProgressText `
                        -Job $job `
                        -StartedAt $script:V3RepairStartedAt `
                        -ProcessIsRunning $false
                )
                return
            }

            $exitWait = New-TimeSpan `
                -Start $script:V3RepairProcessExitObservedAt `
                -End (Get-Date)

            if ($exitWait.TotalSeconds -lt 6) {
                return
            }

            Set-V3Output @"
REPARO DO WINDOWS - INTERROMPIDO
===============================

Ferramenta: $($job.DisplayName)

A janela administrativa foi encerrada antes que o toolkit recebesse uma conclusão.
Não é possível afirmar que o diagnóstico ou reparo resolveu o problema.

Próxima ação:
Execute novamente e mantenha a janela administrativa aberta até aparecer o resumo final.

Log parcial:
$($job.LogPath)
"@

            Write-V3WindowsRepairAudit `
                -Tool $job.Tool `
                -Status "Interrupted" `
                -Message "Processo encerrado sem resumo final."

            Stop-V3WindowsRepairMonitor
            $script:V3RepairProcessId = $null
            $script:V3RepairJob = $null
        }
        catch {
            Set-V3Output @"
FALHA AO MONITORAR O REPARO
===========================

O comando pode ainda estar em execução na janela administrativa.

Detalhe:
$($_.Exception.Message)
"@

            Stop-V3WindowsRepairMonitor
        }
    })

    $script:V3RepairMonitor = $timer
    $script:V3RepairMonitor.Start()
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
    $generatedAt = Get-Date
    $failureParameters = @{
        Header = "INVENTARIO DA MAQUINA - PAINEL CONSOLIDADO"
        Divider = "------------------------------------------"
        ActionType = "Coleta de inventario sem correcao"
        FailureMessage = "Nao foi possivel gerar o inventario completo."
        GeneratedAt = $generatedAt
    }

    if (-not $script:V3OperationalModulesAvailable) {
        $failureParameters.ErrorDetail = $script:V3OperationalModuleError
        return New-V3OperationalFailureReport @failureParameters
    }

    try {
        $snapshot = Get-ToolkitInventorySnapshot -ObservedAt $generatedAt
        $assessment = Get-ToolkitInventoryAssessment -Snapshot $snapshot
        $formatParameters = @{
            Snapshot = $snapshot
            Assessment = $assessment
            ComputerName = $env:COMPUTERNAME
            UserName = "$env:USERDOMAIN\$env:USERNAME"
            IsAdministrator = (Test-V3Admin)
            GeneratedAt = $generatedAt
        }

        return Format-ToolkitInventoryReport @formatParameters
    }
    catch {
        $failureParameters.ErrorDetail = $_.Exception.Message
        return New-V3OperationalFailureReport @failureParameters
    }
}

function Invoke-V3NetworkDiagnostic {
    $generatedAt = Get-Date
    $failureParameters = @{
        Header = "DIAGNOSTICO DE REDE - PAINEL CONSOLIDADO"
        Divider = "----------------------------------------"
        ActionType = "Diagnostico sem correcao"
        FailureMessage = "Falha ao executar diagnostico consolidado de rede."
        GeneratedAt = $generatedAt
    }

    if (-not $script:V3OperationalModulesAvailable) {
        $failureParameters.ErrorDetail = $script:V3OperationalModuleError
        return New-V3OperationalFailureReport @failureParameters
    }

    try {
        $snapshot = Get-ToolkitNetworkSnapshot -ObservedAt $generatedAt
        $assessment = Get-ToolkitNetworkAssessment -Snapshot $snapshot
        $formatParameters = @{
            Snapshot = $snapshot
            Assessment = $assessment
            ComputerName = $env:COMPUTERNAME
            UserName = "$env:USERDOMAIN\$env:USERNAME"
            IsAdministrator = (Test-V3Admin)
            GeneratedAt = $generatedAt
        }

        return Format-ToolkitNetworkReport @formatParameters
    }
    catch {
        $failureParameters.ErrorDetail = $_.Exception.Message
        return New-V3OperationalFailureReport @failureParameters
    }
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
function Invoke-V3PrintersPanel {
    $generatedAt = Get-Date
    $failureParameters = @{
        Header = "PAINEL DE IMPRESSORAS - DIAGNOSTICO CONSOLIDADO"
        Divider = "------------------------------------------------"
        ActionType = "Diagnostico de impressoras sem correcao"
        FailureMessage = "Falha ao gerar painel de impressoras."
        GeneratedAt = $generatedAt
    }

    if (-not $script:V3OperationalModulesAvailable) {
        $failureParameters.ErrorDetail = $script:V3OperationalModuleError
        return New-V3OperationalFailureReport @failureParameters
    }

    try {
        $snapshot = Get-ToolkitPrinterSnapshot -ObservedAt $generatedAt
        $assessment = Get-ToolkitPrinterAssessment -Snapshot $snapshot
        $formatParameters = @{
            Snapshot = $snapshot
            Assessment = $assessment
            ComputerName = $env:COMPUTERNAME
            UserName = "$env:USERDOMAIN\$env:USERNAME"
            IsAdministrator = (Test-V3Admin)
            GeneratedAt = $generatedAt
        }

        return Format-ToolkitPrinterReport @formatParameters
    }
    catch {
        $failureParameters.ErrorDetail = $_.Exception.Message
        return New-V3OperationalFailureReport @failureParameters
    }
}

function Invoke-V3OfficeTpmPanel {
    $generatedAt = Get-Date
    $failureParameters = @{
        Header = "OFFICE / TPM / AUTENTICACAO - DIAGNOSTICO CONSOLIDADO"
        Divider = "====================================================="
        ActionType = "Diagnostico Office / TPM somente leitura"
        FailureMessage = "Falha ao gerar diagnostico Office / TPM."
        GeneratedAt = $generatedAt
    }

    if (-not $script:V3OperationalModulesAvailable) {
        $failureParameters.ErrorDetail = $script:V3OperationalModuleError
        return New-V3OperationalFailureReport @failureParameters
    }

    try {
        $snapshot = Get-ToolkitOfficeTpmSnapshot -ObservedAt $generatedAt
        $assessment = Get-ToolkitOfficeTpmAssessment -Snapshot $snapshot

        return Format-ToolkitOfficeTpmReport `
            -Snapshot $snapshot `
            -Assessment $assessment `
            -ComputerName $env:COMPUTERNAME `
            -UserName "$env:USERDOMAIN\$env:USERNAME" `
            -IsAdministrator (Test-V3Admin) `
            -GeneratedAt $generatedAt
    }
    catch {
        $failureParameters.ErrorDetail = $_.Exception.Message
        return New-V3OperationalFailureReport @failureParameters
    }
}

function Invoke-V3OfficeWamRepair {
    try {
        if (-not $script:V3OperationalModulesAvailable) {
            throw (
                "Modulo Office / TPM indisponivel: " +
                $script:V3OperationalModuleError
            )
        }

        $auditPath = Join-Path `
            $script:RootPath `
            "logs\office-tpm\office-wam-audit.jsonl"
        $result = Repair-ToolkitOfficeWam `
            -Confirmed `
            -AuditPath $auditPath

        return Format-ToolkitOfficeWamRepairReport -Result $result
    }
    catch {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("REPARO DO LOGIN OFFICE - NAO EXECUTADO")
        [void]$sb.AppendLine("======================================")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Motivo: $($_.Exception.Message)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine(
            "Nenhuma credencial, conta Entra ou chave TPM foi removida."
        )
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine(
            "Feche Word, Excel, Outlook, Teams e outros aplicativos Office antes de tentar novamente."
        )

        return $sb.ToString()
    }
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
function Get-V3AppgateStatus {
    $sb = New-Object System.Text.StringBuilder
    $configPath = "C:\Program Files\Appgate SDP\Service\Appgate SDP Service.dll.config"
    [void]$sb.AppendLine("APPGATE SDP - STATUS DETALHADO")
    [void]$sb.AppendLine("==============================")
    [void]$sb.AppendLine("Config: $(if (Test-Path $configPath) { $configPath } else { 'Nao encontrada' })")
    if (Test-Path $configPath) {
        try {
            [xml]$xml = Get-Content $configPath -Raw -ErrorAction Stop
            $node = $xml.SelectSingleNode("//applicationSettings/Cryptzone.Stratus.WindowsClient.Properties.Application/setting[@name='RunScriptTimeout']/value")
            [void]$sb.AppendLine("RunScriptTimeout: $(if ($node) { $node.InnerText } else { 'Nao encontrado' })")
        }
        catch { [void]$sb.AppendLine("Falha ao ler configuracao: $($_.Exception.Message)") }
    }
    try {
        $uac = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction Stop).ConsentPromptBehaviorAdmin
        [void]$sb.AppendLine("UAC ConsentPromptBehaviorAdmin: $uac")
    }
    catch { [void]$sb.AppendLine("UAC: indisponivel") }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("SERVICOS")
    $services = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @("appgatedriver", "AppgateUpdateService") -or $_.DisplayName -like "*Appgate*"
    } | Select-Object Name, DisplayName, Status)
    [void]$sb.AppendLine($(if ($services.Count) { $services | Format-Table -AutoSize | Out-String } else { "Nenhum servico encontrado." }))
    [void]$sb.AppendLine("PROCESSOS")
    $processes = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like "*appgate*" -or $_.ProcessName -like "*sdp*"
    } | Select-Object ProcessName, Id, Path)
    [void]$sb.AppendLine($(if ($processes.Count) { $processes | Format-Table -AutoSize | Out-String } else { "Nenhum processo encontrado." }))
    return $sb.ToString()
}

function Restart-V3Appgate {
    param([switch]$Confirmed)
    if (-not $Confirmed) { throw "Reinicio do Appgate exige confirmacao explicita." }
    if (-not (Test-V3Admin)) { throw "Execute o Toolkit como administrador para reiniciar o Appgate." }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("REINICIO CONTROLADO DO APPGATE")
    [void]$sb.AppendLine("==============================")
    foreach ($name in @("Appgate SDP Service", "appgate-driver")) {
        foreach ($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            [void]$sb.AppendLine("Processo finalizado: $($process.ProcessName) ($($process.Id))")
        }
    }
    Start-Sleep -Seconds 2
    foreach ($name in @("appgatedriver", "AppgateUpdateService")) {
        $service = Get-Service $name -ErrorAction SilentlyContinue
        if ($service) {
            Restart-Service $name -Force -ErrorAction SilentlyContinue
            [void]$sb.AppendLine("Servico reiniciado: $name")
        }
    }
    $exePath = "C:\Program Files\Appgate SDP\Service\Appgate SDP Service.exe"
    if (Test-Path $exePath) {
        Start-Process $exePath
        [void]$sb.AppendLine("Cliente iniciado: $exePath")
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("A VPN foi reiniciada. Valide autenticacao e acesso ao recurso corporativo.")
    return $sb.ToString()
}

function Repair-V3AppgateConfiguration {
    param([switch]$Confirmed)
    if (-not $Confirmed) { throw "Ajuste do Appgate exige confirmacao explicita." }
    if (-not (Test-V3Admin)) { throw "Execute o Toolkit como administrador para ajustar o Appgate." }
    $configPath = "C:\Program Files\Appgate SDP\Service\Appgate SDP Service.dll.config"
    if (-not (Test-Path $configPath)) { throw "Configuracao do Appgate nao encontrada: $configPath" }
    $backupDirectory = Join-Path $script:RootPath "backup-appgate"
    if (-not (Test-Path $backupDirectory)) { New-Item $backupDirectory -ItemType Directory -Force | Out-Null }
    $backupPath = Join-Path $backupDirectory ("Appgate-SDP-Service.dll.config.{0}.bak" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Copy-Item $configPath $backupPath -Force -ErrorAction Stop
    [xml]$xml = Get-Content $configPath -Raw -ErrorAction Stop
    $node = $xml.SelectSingleNode("//applicationSettings/Cryptzone.Stratus.WindowsClient.Properties.Application/setting[@name='RunScriptTimeout']/value")
    if (-not $node) { throw "RunScriptTimeout nao encontrado. Backup preservado em $backupPath" }
    $oldValue = $node.InnerText
    $node.InnerText = "300000"
    $xml.Save($configPath)
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name ConsentPromptBehaviorAdmin -Value 5 -Type DWord -ErrorAction Stop
    return "AJUSTE DO APPGATE CONCLUIDO`r`n============================`r`nRunScriptTimeout: $oldValue -> 300000`r`nUAC ConsentPromptBehaviorAdmin: 5`r`nBackup: $backupPath`r`n`r`nReinicie o Appgate e valide a conexao."
}

function Invoke-V3MachineHealthPanel {
    try {
        if (-not $script:V3HealthModulesAvailable) {
            $moduleError = if ([string]::IsNullOrWhiteSpace($script:V3HealthModuleError)) {
                "Motivo nao informado."
            }
            else {
                $script:V3HealthModuleError
            }

            throw "Modulos do Painel de Saude indisponiveis: $moduleError"
        }

        $snapshot = Get-ToolkitMachineHealthSnapshot
        $assessment = Get-ToolkitMachineHealthAssessment -Snapshot $snapshot

        return Format-ToolkitMachineHealthReport `
            -Snapshot $snapshot `
            -Assessment $assessment
    }
    catch {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("PAINEL DE SAUDE DA MAQUINA")
        [void]$sb.AppendLine("==========================")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Gerado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
        [void]$sb.AppendLine("Hostname: $env:COMPUTERNAME")
        [void]$sb.AppendLine("Usuario: $env:USERDOMAIN\$env:USERNAME")
        [void]$sb.AppendLine("Tipo de acao: Diagnostico geral sem correcao")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Falha ao gerar o Painel de Saude da Maquina.")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Detalhe: $($_.Exception.Message)")

        return $sb.ToString()
    }
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
    [void]$sb.AppendLine("- Impressora nao imprime")
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
function Invoke-V3WorkflowPrinter {
    $workflowParameters = @{
        Title = "Atendimento Guiado - Impressora Nao Imprime"
        Problem = "Usuario relata que a impressora nao imprime, aparece offline, acumula documentos na fila ou apresenta falha durante a impressao."
        EvidenceScript = {
            Invoke-V3PrintersPanel
        }
        LikelyCauses = @(
            "Servico Spooler parado ou instavel",
            "Documentos travados na fila de impressao",
            "Impressora configurada como offline",
            "Impressora padrao incorreta ou nao definida",
            "Porta ou endereco IP incorreto",
            "Equipamento desligado ou desconectado da rede",
            "Falha ou incompatibilidade no driver",
            "Problema especifico no aplicativo de origem"
        )
        NextActions = @(
            "Confirmar qual impressora e qual documento apresentam falha",
            "Validar o estado do Spooler e a quantidade de trabalhos na fila",
            "Confirmar se a impressora correta esta definida como padrao",
            "Validar se a impressora aparece offline ou com status de alerta",
            "Para impressora de rede, validar porta, endereco IP e conectividade",
            "Reiniciar o Spooler somente quando houver indicio de falha no servico ou fila",
            "Nao limpar a fila sem confirmar o impacto com o usuario",
            "Se os testes estiverem normais, validar driver, aplicativo de origem e equipamento fisico"
        )
        RiskLevel = "Baixo"
    }

    return New-V3WorkflowResult @workflowParameters
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

    <Style x:Key="ActionGridButton" TargetType="Button">
        <Setter Property="Height" Value="38"/>
        <Setter Property="Margin" Value="4,4,4,4"/>
        <Setter Property="Padding" Value="8,0"/>
        <Setter Property="HorizontalAlignment" Value="Stretch"/>
        <Setter Property="VerticalAlignment" Value="Stretch"/>
        <Setter Property="HorizontalContentAlignment" Value="Center"/>
        <Setter Property="VerticalContentAlignment" Value="Center"/>
        <Setter Property="Background" Value="#FFFFFF"/>
        <Setter Property="Foreground" Value="#0F172A"/>
        <Setter Property="BorderBrush" Value="#CBD5E1"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Cursor" Value="Hand"/>
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

                    <UniformGrid Columns="4" Margin="0,14,0,0">
    <Button Name="BtnV3QuickInternet" Content="Sem internet" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3QuickVpn" Content="VPN / Appgate" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3Inventory" Content="Inventário" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3Network" Content="Diagnóstico de rede" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3Printers" Content="Impressoras" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3OfficeTpm" Content="Office / TPM" Style="{StaticResource ActionGridButton}" ToolTip="Diagnostica Office, TPM, WAM, licenciamento e estado Entra sem executar correcao."/>
    <Button Name="BtnV3OfficeWam" Content="Reparar login Office" Style="{StaticResource ActionGridButton}" ToolTip="Repara o login WAM de Microsoft 365 e Office 2016, 2019 e 2021. Nao limpa TPM nem credenciais."/>

    <Button Name="BtnV3FlushDns" Content="Limpar DNS" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3TimeSync" Content="Sincronizar horário" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3Spooler" Content="Reiniciar spooler" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3Health" Content="Saúde da máquina" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3CopyOutput" Content="Copiar resultado" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3Sfc" Content="SFC: verificar arquivos" Style="{StaticResource ActionGridButton}" ToolTip="Verifica e tenta reparar arquivos protegidos do Windows. Exige permissão administrativa."/>
    <Button Name="BtnV3Dism" Content="DISM: reparar imagem" Style="{StaticResource ActionGridButton}" ToolTip="Repara a imagem de componentes do Windows. Exige permissão administrativa e pode depender do Windows Update."/>
    <Button Name="BtnV3NetworkAdvanced" Content="Rede: adaptadores e IP" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3DnsDetails" Content="Rede: DNS detalhado" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3Routes" Content="Rede: rotas" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3Gateway" Content="Rede: testar gateway" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3RenewIp" Content="Rede: renovar IP" Style="{StaticResource ActionGridButton}" ToolTip="Interrompe a conexão temporariamente e exige confirmação."/>
    <Button Name="BtnV3Winsock" Content="Rede: reset Winsock" Style="{StaticResource ActionGridButton}" ToolTip="Exige administrador, confirmação e reinicialização."/>
    <Button Name="BtnV3TcpIp" Content="Rede: reset TCP/IP" Style="{StaticResource ActionGridButton}" ToolTip="Exige administrador, confirmação e reinicialização."/>
    <Button Name="BtnV3NetworkConnections" Content="Abrir conexões de rede" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3PrinterList" Content="Impressoras: listar" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3PrintJobs" Content="Impressoras: filas" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3DefaultPrinter" Content="Impressora padrão" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3OfflinePrinters" Content="Impressoras offline" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3ClearPrintQueue" Content="Limpar fila de impressão" Style="{StaticResource ActionGridButton}" ToolTip="Remove trabalhos pendentes e exige confirmação administrativa."/>
    <Button Name="BtnV3PrinterSettings" Content="Abrir impressoras" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3PrintManagement" Content="Gerenciar impressão" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3AppgateStatus" Content="Appgate: status" Style="{StaticResource ActionGridButton}"/>
    <Button Name="BtnV3AppgateRestart" Content="Appgate: reiniciar" Style="{StaticResource ActionGridButton}" ToolTip="Interrompe a VPN temporariamente e exige confirmação."/>
    <Button Name="BtnV3AppgateFix" Content="Appgate: ajustar" Style="{StaticResource ActionGridButton}" ToolTip="Cria backup, ajusta RunScriptTimeout e UAC com confirmação."/>
</UniformGrid>
                </StackPanel>
            </Border>

            <Border Grid.Row="3" Background="White" CornerRadius="18" Padding="16" BorderBrush="#E2E8F0" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <TextBlock Text="Resultado e andamento" FontSize="16" FontWeight="Bold" Foreground="#0F172A" Margin="0,0,0,10"/>

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
$window.FindName("BtnV3NavSafeFix").Add_Click({ Set-V3Output "Correções Seguras:`r`n- Limpar DNS`r`n- Renovar IP`r`n- Sincronizar horário`r`n- Reiniciar spooler`r`n- Reparar login Office (WAM)`r`n- Limpar temporários" })
$window.FindName("BtnV3NavAdvanced").Add_Click({ Set-V3Output "Área avançada:`r`nAções críticas protegidas por confirmação, elevação administrativa e log.`r`n`r`nDisponíveis agora:`r`n- SFC /scannow: verifica e repara arquivos protegidos do Windows.`r`n- DISM RestoreHealth: repara a imagem de componentes do Windows.`r`n- Office / TPM: diagnóstico de TPM, WAM, licenciamento e Entra ID.`r`n`r`nO toolkit não limpa TPM nem remove o dispositivo do Entra automaticamente.`r`n`r`nOrdem recomendada quando o SFC não consegue reparar:`r`n1. Execute o DISM.`r`n2. Reinicie se solicitado.`r`n3. Execute o SFC novamente." })
$window.FindName("BtnV3NavToolkit").Add_Click({ Set-V3Output "Toolkit:`r`n- Status`r`n- Atualização`r`n- Rollback`r`n- Logs`r`n- Validação`r`n`r`nEssas funções serão conectadas ao motor atual em etapas futuras." })

$window.FindName("BtnV3QuickInternet").Add_Click({ Set-V3Output (Invoke-V3WorkflowNoInternet) })
$window.FindName("BtnV3QuickVpn").Add_Click({ Set-V3Output (Invoke-V3WorkflowVpn) })
$window.FindName("BtnV3Inventory").Add_Click({ Set-V3Output (Get-V3InventoryLite) })
$window.FindName("BtnV3Network").Add_Click({ Set-V3Output (Invoke-V3NetworkDiagnostic) })
$window.FindName("BtnV3FlushDns").Add_Click({ Set-V3Output (Invoke-V3SafeFlushDns) })
$window.FindName("BtnV3TimeSync").Add_Click({ Set-V3Output (Invoke-V3SafeTimeSync) })
$window.FindName("BtnV3Spooler").Add_Click({ Set-V3Output (Invoke-V3SafeSpoolerRestart) })
$window.FindName("BtnV3Printers").Add_Click({ Set-V3Output (Invoke-V3WorkflowPrinter) })
$window.FindName("BtnV3NetworkAdvanced").Add_Click({ Set-V3Output (Get-ToolkitAdvancedNetworkReport) })
$window.FindName("BtnV3DnsDetails").Add_Click({ Set-V3Output (Get-ToolkitDnsReport) })
$window.FindName("BtnV3Routes").Add_Click({ Set-V3Output (Get-ToolkitRoutesReport) })
$window.FindName("BtnV3Gateway").Add_Click({ Set-V3Output (Test-ToolkitDefaultGateway) })
$window.FindName("BtnV3NetworkConnections").Add_Click({ Set-V3Output (Open-ToolkitNetworkConnections) })
$window.FindName("BtnV3PrinterList").Add_Click({ Set-V3Output (Get-ToolkitPrinterListReport) })
$window.FindName("BtnV3PrintJobs").Add_Click({ Set-V3Output (Get-ToolkitPrintJobsReport) })
$window.FindName("BtnV3DefaultPrinter").Add_Click({ Set-V3Output (Get-ToolkitDefaultPrinterReport) })
$window.FindName("BtnV3OfflinePrinters").Add_Click({ Set-V3Output (Get-ToolkitOfflinePrintersReport) })
$window.FindName("BtnV3PrinterSettings").Add_Click({ Set-V3Output (Open-ToolkitPrintersSettings) })
$window.FindName("BtnV3PrintManagement").Add_Click({ Set-V3Output (Open-ToolkitPrintManagement) })
$window.FindName("BtnV3AppgateStatus").Add_Click({ Set-V3Output (Get-V3AppgateStatus) })
$window.FindName("BtnV3RenewIp").Add_Click({
    if ([System.Windows.MessageBox]::Show("A renovacao de IP interrompera a conexao temporariamente. Deseja continuar?", "Renovar IP", "YesNo", "Warning") -eq "Yes") {
        Set-V3Output (Invoke-ToolkitRenewIp -Confirmed)
    }
})
$window.FindName("BtnV3Winsock").Add_Click({
    if ([System.Windows.MessageBox]::Show("O reset do Winsock exige administrador e reinicializacao. Deseja continuar?", "Reset Winsock", "YesNo", "Warning") -eq "Yes") {
        Set-V3Output (Invoke-ToolkitNetworkStackReset -Target Winsock -Confirmed)
    }
})
$window.FindName("BtnV3TcpIp").Add_Click({
    if ([System.Windows.MessageBox]::Show("O reset TCP/IP pode remover ajustes locais e exige reinicializacao. Deseja continuar?", "Reset TCP/IP", "YesNo", "Warning") -eq "Yes") {
        Set-V3Output (Invoke-ToolkitNetworkStackReset -Target TcpIp -Confirmed)
    }
})
$window.FindName("BtnV3ClearPrintQueue").Add_Click({
    if ([System.Windows.MessageBox]::Show("Todos os trabalhos pendentes serao removidos da fila. Deseja continuar?", "Limpar fila de impressao", "YesNo", "Warning") -eq "Yes") {
        Set-V3Output (Clear-ToolkitPrintQueue -Confirmed)
    }
})
$window.FindName("BtnV3AppgateRestart").Add_Click({
    if ([System.Windows.MessageBox]::Show("O Appgate e a VPN serao interrompidos temporariamente. Deseja continuar?", "Reiniciar Appgate", "YesNo", "Warning") -eq "Yes") {
        Set-V3Output (Restart-V3Appgate -Confirmed)
    }
})
$window.FindName("BtnV3AppgateFix").Add_Click({
    if ([System.Windows.MessageBox]::Show("Sera criado um backup e aplicado RunScriptTimeout=300000 e UAC=5. Deseja continuar?", "Ajustar Appgate", "YesNo", "Warning") -eq "Yes") {
        Set-V3Output (Repair-V3AppgateConfiguration -Confirmed)
    }
})
$window.FindName("BtnV3Health").Add_Click({ Set-V3Output (Invoke-V3MachineHealthPanel) })
$window.FindName("BtnV3OfficeTpm").Add_Click({
    Set-V3Output (Invoke-V3OfficeTpmPanel)
})
$window.FindName("BtnV3OfficeWam").Add_Click({
    $confirmation = [System.Windows.MessageBox]::Show(
        "O reparo de login para Microsoft 365 e Office 2016, 2019 ou 2021 registrara novamente AAD BrokerPlugin e CloudExperienceHost no perfil atual.`r`n`r`nFeche Word, Excel, Outlook, Teams e outros aplicativos Office antes de continuar.`r`n`r`nA acao nao limpa TPM, nao remove credenciais e nao desconecta o Entra ID.`r`n`r`nDeseja continuar?",
        "Reparar login do Office - WAM",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($confirmation -eq [System.Windows.MessageBoxResult]::Yes) {
        Set-V3Output (Invoke-V3OfficeWamRepair)
    }
    else {
        Set-V3Output (
            "Reparo WAM cancelado pelo usuario. Nenhuma alteracao foi aplicada."
        )
    }
})
$window.FindName("BtnV3CopyOutput").Add_Click({ Copy-V3OutputToClipboard })
$window.FindName("BtnV3Sfc").Add_Click({
    $confirmation = [System.Windows.MessageBox]::Show(
        "O SFC verificará e poderá reparar arquivos protegidos do Windows.`r`n`r`nA execução pode demorar e abrirá uma janela administrativa com progresso e log.`r`n`r`nDeseja continuar?",
        "SFC - Verificar arquivos do Windows",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($confirmation -eq [System.Windows.MessageBoxResult]::Yes) {
        Set-V3Output (Invoke-V3WindowsRepair -Tool "SFC")
    }
    else {
        Set-V3Output "SFC cancelado pelo usuário. Nenhuma alteração foi aplicada."
    }
})
$window.FindName("BtnV3Dism").Add_Click({
    $confirmation = [System.Windows.MessageBox]::Show(
        "O DISM tentará reparar a imagem de componentes do Windows.`r`n`r`nA execução pode demorar, consumir recursos e depender do Windows Update. Uma janela administrativa exibirá o progresso e salvará o log.`r`n`r`nDeseja continuar?",
        "DISM - Reparar imagem do Windows",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($confirmation -eq [System.Windows.MessageBoxResult]::Yes) {
        Set-V3Output (Invoke-V3WindowsRepair -Tool "DISM")
    }
    else {
        Set-V3Output "DISM cancelado pelo usuário. Nenhuma alteração foi aplicada."
    }
})
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
