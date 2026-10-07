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

$script:V3StorageScan = $null
$script:V3StorageSnapshot = $null
$script:V3StorageBaseline = $null
function Start-V3StorageDiagnostic {
    param(
        [string]$ScanRoot = ($env:SystemDrive + "\"),
        [int]$MaxSeconds = 120,
        [int]$MaxFiles = 200000
    )

    if ($null -ne $script:V3StorageScan) {
        $window.FindName("ResultStatus").Text = "Diagnostico de disco ja em andamento"
        return
    }
    $pipeline = [powershell]::Create()
    try {
        $modulePath = Join-Path $script:RootPath "src\ServiceDeskToolkit.Storage\ServiceDeskToolkit.Storage.psm1"
        [void]$pipeline.AddScript({
            param($modulePath, $scanRoot, $maxSeconds, $maxFiles)
            $ErrorActionPreference = "Stop"
            Import-Module $modulePath -Force
            $snapshot = Get-ToolkitStorageSnapshot -ScanRoot $scanRoot -MaxSeconds $maxSeconds -MaxFiles $maxFiles
            [pscustomobject]@{ Snapshot = $snapshot; Report = (Format-ToolkitStorageReport -Snapshot $snapshot) }
        }).AddArgument($modulePath).AddArgument($ScanRoot).AddArgument($MaxSeconds).AddArgument($MaxFiles)
        $handle = $pipeline.BeginInvoke()
        $script:V3StorageScan = [pscustomobject]@{ Pipeline = $pipeline; Handle = $handle; Cancelled = $false; StopHandle = $null }
        $window.FindName("BtnV3Storage").IsEnabled = $false
        $window.FindName("BtnV3CancelStorage").Visibility = "Visible"
        $window.FindName("BtnV3CancelStorage").IsEnabled = $true
        Set-V3Output "ESPACO EM DISCO - COLETA EM ANDAMENTO`r`n`r`nLeitura de discos, perfis e arquivos. Nenhum arquivo sera apagado.`r`nA varredura usa limites de tempo e quantidade; acessos negados e cobertura parcial serao indicados.`r`nVoce pode navegar e cancelar a coleta. Ao terminar, o resultado sera substituido pelo plano de liberacao."
        $window.FindName("ResultStatus").Text = "Lendo espaco em disco..."
        $script:V3StorageTimer.Start()
    }
    catch {
        $pipeline.Dispose()
        $script:V3StorageScan = $null
        $window.FindName("BtnV3Storage").IsEnabled = $true
        $window.FindName("BtnV3CancelStorage").Visibility = "Collapsed"
        Set-V3Output "Nao foi possivel iniciar o diagnostico de disco. Detalhe: $($_.Exception.Message)"
    }
}

function Complete-V3StorageDiagnostic {
    if ($null -eq $script:V3StorageScan -or -not $script:V3StorageScan.Handle.IsCompleted) { return }
    $scan = $script:V3StorageScan
    if ($null -ne $scan.StopHandle -and -not $scan.StopHandle.IsCompleted) { return }
    try {
        if ($null -ne $scan.StopHandle) { $scan.Pipeline.EndStop($scan.StopHandle) }
        if ($scan.Cancelled) {
            Set-V3Output "Diagnostico de disco cancelado. Nenhuma limpeza foi executada. Repita a coleta quando puder concluir a leitura."
        }
        else {
            $result = $scan.Pipeline.EndInvoke($scan.Handle)
            if ($scan.Pipeline.HadErrors) { throw "A coleta falhou; consulte as permissoes e repita o diagnostico." }
            if ($result.Count -ne 1 -or $null -eq $result[0].Snapshot) { throw 'Resultado de coleta indisponivel.' }
            $script:V3StorageSnapshot = $result[0].Snapshot
            Set-V3Output $result[0].Report
            Set-V3ResultExpanded -Expanded $true
        }
    }
    catch {
        Set-V3Output "Nao foi possivel concluir o diagnostico de disco. Nenhuma limpeza foi executada.`r`nDetalhe: $($_.Exception.Message)"
    }
    finally {
        $scan.Pipeline.Dispose()
        $script:V3StorageScan = $null
        $script:V3StorageTimer.Stop()
        $window.FindName("BtnV3Storage").IsEnabled = $true
        $window.FindName("BtnV3CancelStorage").Visibility = "Collapsed"
        Update-V3StorageFollowup
    }
}

function Update-V3StorageFollowup {
    $available = $null -ne $script:V3StorageSnapshot -and $null -eq $script:V3StorageScan -and $script:TxtV3Output.Text.StartsWith('ESPACO EM DISCO')
    $window.FindName("StorageFollowup").Visibility = if ($available) { "Visible" } else { "Collapsed" }
    $window.FindName("BtnV3CompareStorage").IsEnabled = $available -and $null -ne $script:V3StorageBaseline -and -not [object]::ReferenceEquals($script:V3StorageBaseline, $script:V3StorageSnapshot)
    $window.FindName("StorageBaselineStatus").Text = if ($null -eq $script:V3StorageBaseline) { "Defina a leitura inicial antes da limpeza" } else { "Inicial: " + $script:V3StorageBaseline.GeneratedAt.ToString('HH:mm:ss') }
}

function Set-V3StorageBaseline {
    if ($null -eq $script:V3StorageSnapshot -or $null -ne $script:V3StorageScan) { return }
    $script:V3StorageBaseline = $script:V3StorageSnapshot
    Update-V3StorageFollowup
    $window.FindName("ResultStatus").Text = "Leitura inicial definida. Repita o diagnostico apos a acao."
}

function Compare-V3StorageReadings {
    if ($null -eq $script:V3StorageBaseline -or $null -eq $script:V3StorageSnapshot -or $null -ne $script:V3StorageScan) { return }
    try {
        Import-Module (Join-Path $script:RootPath 'src\ServiceDeskToolkit.Storage\ServiceDeskToolkit.Storage.psm1') -Force
        $report = Format-ToolkitStorageComparison -Before $script:V3StorageBaseline -After $script:V3StorageSnapshot
        Set-V3Output $report
        Set-V3ResultExpanded -Expanded $true
    }
    catch { $window.FindName("ResultStatus").Text = "Comparacao indisponivel: $($_.Exception.Message)" }
}

function Get-V3ReportSavePath {
    $dialog = [Microsoft.Win32.SaveFileDialog]::new()
    $dialog.Title = 'Salvar relatorio do atendimento'
    $dialog.Filter = 'Relatorio de texto (*.txt)|*.txt'
    $dialog.DefaultExt = '.txt'
    $dialog.AddExtension = $true
    $dialog.OverwritePrompt = $true
    $dialog.FileName = 'atendimento-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt'
    if ($dialog.ShowDialog($window) -eq $true) { return $dialog.FileName }
    return $null
}

function Save-V3Output {
    if ([string]::IsNullOrWhiteSpace($script:TxtV3Output.Text)) { $window.FindName("ResultStatus").Text = 'Nenhum resultado para salvar'; return }
    $reportToSave = $script:TxtV3Output.Text
    try {
        $path = Get-V3ReportSavePath
        if ([string]::IsNullOrEmpty($path)) { return }
        [IO.File]::WriteAllText($path, $reportToSave, [Text.UTF8Encoding]::new($true))
        $window.FindName("ResultStatus").Text = 'Relatorio salvo em ' + $path
    }
    catch { $window.FindName("ResultStatus").Text = "Nao foi possivel salvar: $($_.Exception.Message)" }
}

function Stop-V3StorageDiagnostic {
    if ($null -ne $script:V3StorageScan -and -not $script:V3StorageScan.Cancelled) {
        $script:V3StorageScan.Cancelled = $true
        $script:V3StorageScan.StopHandle = $script:V3StorageScan.Pipeline.BeginStop($null, $null)
        $window.FindName("BtnV3CancelStorage").IsEnabled = $false
        $window.FindName("ResultStatus").Text = "Cancelando coleta de disco..."
    }
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
        $script:TxtV3Output.ScrollToHome()
        if ($window.FindName("ResultSearchPanel").Visibility -eq "Visible") { Update-V3ResultSearch }
        if ($null -ne $window -and $null -ne $window.FindName("ResultStatus")) {
            $window.FindName("ResultStatus").Text = "Atualizado às " + (Get-Date -Format "HH:mm")
        }
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

Escolha um tema no índice à esquerda para iniciar o atendimento.

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
Comece por Saúde da máquina em Visão geral ou selecione o tema do problema.
Busque pelo nome da ação ou role a lista para ver as demais opções.
Arraste a divisória para ampliar o resultado e use Copiar resultado para coletar a evidência.
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
    param(
        [switch]$Confirmed,
        [string]$ConfigPath = "C:\Program Files\Appgate SDP\Service\Appgate SDP Service.dll.config",
        [string]$BackupDirectory = (Join-Path $script:RootPath 'backup-appgate')
    )
    if (-not $Confirmed) { throw "Ajuste do Appgate exige confirmacao explicita." }
    if (-not (Test-V3Admin)) { throw "Execute o Toolkit como administrador para ajustar o Appgate." }
    if (-not (Test-Path $configPath)) { throw "Configuracao do Appgate nao encontrada: $configPath" }
    if (-not (Test-Path $backupDirectory)) { New-Item $backupDirectory -ItemType Directory -Force | Out-Null }
    $backupPath = Join-Path $backupDirectory ("Appgate-SDP-Service.dll.config.{0}.bak" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
    Copy-Item $configPath $backupPath -Force -ErrorAction Stop
    [xml]$xml = Get-Content $configPath -Raw -ErrorAction Stop
    $node = $xml.SelectSingleNode("//applicationSettings/Cryptzone.Stratus.WindowsClient.Properties.Application/setting[@name='RunScriptTimeout']/value")
    if (-not $node) { throw "RunScriptTimeout nao encontrado. Backup preservado em $backupPath" }
    $oldValue = $node.InnerText
    $node.InnerText = "300000"
    $xml.Save($configPath)
    return "AJUSTE DO APPGATE CONCLUIDO`r`n============================`r`nRunScriptTimeout: $oldValue -> 300000`r`nBackup: $backupPath`r`n`r`nReinicie o Appgate e valide a conexao."
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
function Set-V3ClipboardText {
    param([string]$Text)

    [System.Windows.Clipboard]::SetText($Text)
}

function Copy-V3OutputToClipboard {
    if ($null -eq $script:TxtV3Output) {
        return
    }
    if ([string]::IsNullOrWhiteSpace($script:TxtV3Output.Text)) {
        $window.FindName("ResultStatus").Text = "Nenhum resultado para copiar"
        return
    }
    try {
        Set-V3ClipboardText -Text $script:TxtV3Output.Text
        $window.FindName("ResultStatus").Text = "Resultado copiado às " + (Get-Date -Format "HH:mm")
    }
    catch {
        $window.FindName("ResultStatus").Text = "Cópia indisponível. Tente novamente."
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
function Get-V3SolutionCatalog {
    @(
        [pscustomobject]@{ Id = 'dns-cache'; Title = 'Site ou sistema com falha de DNS'; Situation = 'Use quando a resolucao de nomes falha ou pode estar usando cache antigo. Nao corrige proxy, VPN ou indisponibilidade do destino.'; Preconditions = 'Confirme o site afetado e confira os servidores DNS no diagnostico. A consulta usa alvos de teste; valide tambem o destino do chamado.'; Impact = 'Limpa o cache DNS local. Os nomes serao consultados novamente; nao altera servidores DNS.'; Command = 'ipconfig /flushdns'; RequiresAdmin = $false; Validate = 'Abra novamente o site ou sistema afetado. Se persistir, investigar rede, VPN, proxy e DNS corporativo.' }
        [pscustomobject]@{ Id = 'print-spooler'; Title = 'Impressora nao imprime: servico de impressao'; Situation = 'Use quando o diagnostico indicar Spooler parado ou com falha. Impressora offline, driver ou conectividade podem exigir outra solucao.'; Preconditions = 'Confira servico, impressoras e filas. Requer administrador; avise os usuarios com impressao em andamento.'; Impact = 'Inicia ou reinicia o Spooler e interrompe a impressao temporariamente. Esta solucao nao exclui os trabalhos da fila.'; Command = 'Start-Service ou Restart-Service -Name Spooler'; RequiresAdmin = $true; Validate = 'Envie uma pagina de teste e confira a fila. Servico em execucao sozinho nao comprova que a impressora voltou a imprimir.' }
        [pscustomobject]@{ Id = 'office-wam'; Title = 'Office com falha de login: componentes WAM'; Situation = 'Use em falhas de login compatíveis com componentes WAM. Nao e uma correcao universal para erros TPM, licenca ou conta bloqueada.'; Preconditions = 'Use o perfil do usuario afetado. Feche Word, Excel, Outlook, Teams e demais aplicativos Office; o reparo verifica processos abertos.'; Impact = 'Registra novamente AAD BrokerPlugin e CloudExperienceHost no perfil atual. Nao limpa TPM, credenciais ou vinculo Entra.'; Command = 'Novo registro dos manifestos WAM com Add-AppxPackage'; RequiresAdmin = $false; Validate = 'Abra o Office no perfil afetado e teste o login original. Nao marcar como resolvido apenas por concluir o registro dos componentes.' }
    )
}

function Test-V3SolutionPrerequisites {
    param([ValidateSet('dns-cache', 'print-spooler', 'office-wam')][string]$Id)
    switch ($Id) {
        'dns-cache' {
            if (-not (Get-Command ipconfig.exe -CommandType Application -ErrorAction SilentlyContinue)) { throw 'ipconfig indisponivel. Encaminhe para suporte do Windows.' }
        }
        'print-spooler' {
            if (-not (Test-V3Admin)) { throw 'Reinicio do Spooler exige administrador.' }
            $service = Get-Service -Name Spooler -ErrorAction Stop
            if ($service.StartType -eq 'Disabled') { throw 'Spooler desabilitado. Confira a politica com o administrador; esta solucao nao altera o tipo de inicializacao.' }
        }
        'office-wam' {
            $apps = @(Get-Process -Name WINWORD, EXCEL, OUTLOOK, POWERPNT, MSACCESS, ONENOTE, MSPUB, VISIO, WINPROJ, Teams, ms-teams -ErrorAction SilentlyContinue)
            if ($apps.Count -gt 0) { throw ('Feche os aplicativos antes de repetir: ' + (($apps.ProcessName | Sort-Object -Unique) -join ', ')) }
            foreach ($manifest in @('SystemApps\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\Appxmanifest.xml', 'SystemApps\Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy\Appxmanifest.xml')) {
                if (-not (Test-Path -LiteralPath (Join-Path $env:windir $manifest) -PathType Leaf)) { throw 'Manifesto oficial WAM ausente. Encaminhe para suporte do Windows; nao use pacotes de origem desconhecida.' }
            }
        }
    }
}

function Invoke-V3SolutionOperation {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('dns-cache', 'print-spooler', 'office-wam')][string]$Id,
        [Parameter(Mandatory = $true)][ValidateSet('Diagnose', 'Repair', 'Validate')][string]$Stage,
        [switch]$Confirmed
    )
    if ($Stage -eq 'Repair') {
        if (-not $Confirmed) { throw 'Correcao exige confirmacao explicita.' }
        try { Test-V3SolutionPrerequisites -Id $Id }
        catch { return [pscustomobject]@{ Status = 'Blocked'; Report = "CORRECAO NAO INICIADA`r`n$($_.Exception.Message)`r`nResolva a condicao indicada e execute um novo diagnostico." } }
        switch ($Id) {
            'dns-cache' { return Invoke-V3SafeFlushDns }
            'print-spooler' {
                if (-not (Test-V3Admin)) { throw 'Reinicio do Spooler exige administrador.' }
                return Invoke-V3SafeSpoolerRestart
            }
            'office-wam' { return Invoke-V3OfficeWamRepair }
        }
    }
    else {
        switch ($Id) {
            'dns-cache' { return Get-ToolkitDnsReport }
            'print-spooler' { return Invoke-V3PrintersPanel }
            'office-wam' { return Invoke-V3OfficeTpmPanel }
        }
    }
}

function Get-V3SolutionWorkerText {
    # Somente definicoes do proprio programa; o catalogo nao fornece codigo executavel.
    $definitions = foreach ($name in @('Test-V3Admin', 'New-V3OperationalFailureReport', 'Invoke-V3SafeFlushDns', 'Invoke-V3SafeSpoolerRestart', 'Invoke-V3OfficeWamRepair', 'Invoke-V3PrintersPanel', 'Invoke-V3OfficeTpmPanel', 'Test-V3SolutionPrerequisites', 'Invoke-V3SolutionOperation')) {
        $command = Get-Command -Name $name -CommandType Function -ErrorAction Stop
        'function ' + $name + ' {' + [Environment]::NewLine + $command.Definition + [Environment]::NewLine + '}'
    }
    $setup = @'
param($rootPath, $id, $stage, $confirmed)
$ErrorActionPreference = 'Stop'
$script:RootPath = $rootPath
$moduleName = switch ($id) {
    'dns-cache' { 'Network' }
    'print-spooler' { 'Printers' }
    'office-wam' { 'Office' }
    default { throw 'Solucao desconhecida.' }
}
Import-Module (Join-Path $rootPath ("src\ServiceDeskToolkit.{0}\ServiceDeskToolkit.{0}.psm1" -f $moduleName)) -Force -ErrorAction Stop
$script:V3OperationalModulesAvailable = $true
$script:V3OperationalModuleError = $null
'@
    return $setup + [Environment]::NewLine + ($definitions -join [Environment]::NewLine) + [Environment]::NewLine + 'Invoke-V3SolutionOperation -Id $id -Stage $stage -Confirmed:$confirmed'
}

function Write-V3SolutionAudit {
    param([string]$Id, [string]$Stage, [string]$Status, [bool]$Confirmed)
    $folder = Join-Path $script:RootPath 'logs\solutions'
    [void][IO.Directory]::CreateDirectory($folder)
    $entry = [ordered]@{ Timestamp = (Get-Date).ToString('o'); Solution = $Id; Stage = $Stage; Status = $Status; Confirmed = $Confirmed }
    [IO.File]::AppendAllText((Join-Path $folder 'solutions-audit.jsonl'), (($entry | ConvertTo-Json -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
}

function Confirm-V3SolutionRepair {
    param($Solution, $Dialog)
    $message = $Solution.Impact + "`r`n`r`nAntes de executar:`r`n" + $Solution.Preconditions + "`r`n`r`nConfirme que o diagnostico e o sintoma justificam esta correcao. Deseja continuar?"
    return [Windows.MessageBox]::Show($Dialog, $message, $Solution.Title, 'YesNo', 'Warning') -eq [Windows.MessageBoxResult]::Yes
}

function Update-V3SolutionControls {
    param($Session)
    $busy = $null -ne $Session.Job
    $Session.Dialog.FindName('SolutionChoice').IsEnabled = -not $busy
    $Session.Dialog.FindName('SolutionDiagnose').IsEnabled = -not $busy
    $Session.Dialog.FindName('SolutionRepair').IsEnabled = -not $busy -and $Session.Diagnosed -and -not $Session.RepairAttempted
    $Session.Dialog.FindName('SolutionValidate').IsEnabled = -not $busy -and $Session.RepairAttempted
    $Session.Dialog.FindName('SolutionOutcome').IsEnabled = -not $busy -and $Session.Validated
    $Session.Dialog.FindName('SolutionRecordOutcome').IsEnabled = -not $busy -and $Session.Validated -and $Session.Dialog.FindName('SolutionOutcome').SelectedIndex -gt 0
    $Session.Dialog.FindName('SolutionCancel').Visibility = if ($busy -and $Session.Job.Stage -ne 'Repair') { 'Visible' } else { 'Collapsed' }
    $Session.Dialog.FindName('SolutionCancel').IsEnabled = $busy -and -not $Session.Job.Cancelled
}

function Add-V3SolutionHistory {
    param($Session, [string]$Stage, [string]$Report)
    $Session.EntryCount++
    [void]$Session.History.AppendLine("[$($Session.EntryCount)] $($Session.Id) - $Stage - $(Get-Date -Format 'HH:mm:ss')")
    [void]$Session.History.AppendLine($Report)
    [void]$Session.History.AppendLine('')
    $text = "ATENDIMENTO POR SOLUCOES GUIDADAS`r`nEtapas registradas; resolucao do chamado depende de testar o sintoma original.`r`n`r`n" + $Session.History.ToString()
    $Session.Dialog.FindName('SolutionOutput').Text = $text
    $Session.Dialog.FindName('SolutionOutput').ScrollToEnd()
    Set-V3Output $text
}

function Save-V3SolutionOutcome {
    param($Session)
    if ($null -ne $Session.Job -or -not $Session.Validated) { return }
    $index = $Session.Dialog.FindName('SolutionOutcome').SelectedIndex
    if ($index -notin @(1, 2, 3)) { return }
    $code = @('Pending', 'ResolvedByOperator', 'PersistsByOperator', 'NotTestedByOperator')[$index]
    $description = @('', 'Operador informa: sintoma original testado e resolvido.', 'Operador informa: sintoma original testado e persiste. Investigue as outras causas descritas no plano.', 'Operador informa: sintoma original ainda nao testado. Atendimento pendente de validacao com o usuario.')[$index]
    try {
        Write-V3SolutionAudit -Id $Session.Id -Stage 'Outcome' -Status $code -Confirmed $false
        Add-V3SolutionHistory $Session 'Resultado informado pelo operador' $description
        $Session.Dialog.FindName('SolutionStatus').Text = $description
    }
    catch { $Session.Dialog.FindName('SolutionStatus').Text = 'Resultado nao registrado: arquivo de auditoria indisponivel. Tente novamente.' }
}

function Start-V3SolutionStage {
    param($Session, [ValidateSet('Diagnose', 'Repair', 'Validate')][string]$Stage)
    if ($null -ne $Session.Job) { return }
    $solution = @(Get-V3SolutionCatalog | Where-Object Id -eq $Session.Id)
    if ($solution.Count -ne 1) { throw 'Solucao desconhecida.' }
    $confirmed = $false
    if ($Stage -eq 'Repair') {
        if (-not $Session.Diagnosed -or $Session.RepairAttempted) { $Session.Dialog.FindName('SolutionStatus').Text = 'Execute um novo diagnostico antes da correcao.'; return }
        if ($solution[0].RequiresAdmin -and -not (Test-V3Admin)) { $Session.Dialog.FindName('SolutionStatus').Text = 'Esta correcao exige administrador. O diagnostico permanece disponivel.'; return }
        $confirmed = Confirm-V3SolutionRepair -Solution $solution[0] -Dialog $Session.Dialog
        if (-not $confirmed) { Add-V3SolutionHistory $Session 'Repair' 'Correcao cancelada. Nenhuma acao executada.'; $Session.Dialog.FindName('SolutionStatus').Text = 'Correcao cancelada. Nenhuma acao executada.'; return }
    }
    if ($Stage -eq 'Validate' -and -not $Session.RepairAttempted) { return }
    if ($Stage -eq 'Diagnose') { $Session.Diagnosed = $false; $Session.RepairAttempted = $false }
    $Session.Validated = $false
    $Session.Dialog.FindName('SolutionOutcome').SelectedIndex = 0
    $pipeline = [powershell]::Create()
    $startedRecorded = $false
    try {
        Write-V3SolutionAudit -Id $Session.Id -Stage $Stage -Status 'Started' -Confirmed $confirmed
        $startedRecorded = $true
        [void]$pipeline.AddScript((Get-V3SolutionWorkerText)).AddArgument($script:RootPath).AddArgument($Session.Id).AddArgument($Stage).AddArgument($confirmed)
        $handle = $pipeline.BeginInvoke()
        $Session.Job = [pscustomobject]@{ Pipeline = $pipeline; Handle = $handle; Stage = $Stage; Confirmed = $confirmed; Cancelled = $false; StopHandle = $null }
        $Session.Dialog.FindName('SolutionStatus').Text = 'Etapa em andamento. Aguarde; o diagnostico do Office pode demorar.'
        Update-V3SolutionControls $Session
        $Session.Timer.Start()
    }
    catch {
        $pipeline.Dispose()
        if ($startedRecorded) { try { Write-V3SolutionAudit -Id $Session.Id -Stage $Stage -Status 'NotStarted' -Confirmed $confirmed } catch { } }
        Add-V3SolutionHistory $Session $Stage ("Etapa nao iniciada: $($_.Exception.Message)")
        $Session.Dialog.FindName('SolutionStatus').Text = 'Etapa nao iniciada. Confira o registro e as permissoes.'
        Update-V3SolutionControls $Session
    }
}

function Stop-V3SolutionConsultation {
    param($Session)
    if ($null -eq $Session.Job -or $Session.Job.Stage -eq 'Repair' -or $Session.Job.Cancelled) { return }
    $Session.Job.Cancelled = $true
    $Session.Job.StopHandle = $Session.Job.Pipeline.BeginStop($null, $null)
    $Session.Dialog.FindName('SolutionStatus').Text = 'Cancelando consulta. Aguarde a conclusao.'
    Update-V3SolutionControls $Session
}

function Complete-V3SolutionStage {
    param($Session)
    if ($null -eq $Session.Job -or -not $Session.Job.Handle.IsCompleted) { return }
    $job = $Session.Job
    if ($null -ne $job.StopHandle -and -not $job.StopHandle.IsCompleted) { return }
    $status = 'Error'
    try {
        if ($null -ne $job.StopHandle) { $job.Pipeline.EndStop($job.StopHandle) }
        if ($job.Cancelled) {
            Add-V3SolutionHistory $Session $job.Stage 'Consulta cancelada. Esta etapa nao executa correcao.'
            $status = 'Cancelled'
            $Session.Dialog.FindName('SolutionStatus').Text = 'Consulta cancelada. Repita quando puder concluir a leitura.'
            return
        }
        $result = $job.Pipeline.EndInvoke($job.Handle)
        if ($job.Pipeline.HadErrors) { throw 'A etapa apresentou erro de execucao.' }
        if ($result.Count -eq 1 -and $result[0].PSObject.Properties['Status'] -and $result[0].Status -eq 'Blocked') {
            $Session.Diagnosed = $false
            Add-V3SolutionHistory $Session $job.Stage $result[0].Report
            $status = 'Blocked'
            $Session.Dialog.FindName('SolutionStatus').Text = 'Correcao bloqueada antes de executar. Confira a orientacao no historico.'
            return
        }
        $report = $result -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($report)) { throw 'A etapa nao retornou um relatorio.' }
        if ($job.Stage -eq 'Diagnose') { $Session.Diagnosed = $true }
        if ($job.Stage -eq 'Repair') { $Session.RepairAttempted = $true }
        if ($job.Stage -eq 'Validate') {
            $Session.Validated = $true
            $solution = Get-V3SolutionCatalog | Where-Object Id -eq $Session.Id
            $report += "`r`n`r`nVALIDACAO DO CHAMADO:`r`n" + $solution.Validate
        }
        Add-V3SolutionHistory $Session $job.Stage $report
        $status = 'Completed'
        $Session.Dialog.FindName('SolutionStatus').Text = 'Etapa encerrada. Confira o relatorio; conclusao nao significa problema resolvido.'
    }
    catch {
        if ($job.Stage -eq 'Repair') { $Session.RepairAttempted = $true }
        $guidance = if ($job.Stage -eq 'Repair') { 'Uma correcao iniciada pode ter sido parcialmente aplicada. Valide o estado antes de repetir.' } else { 'A consulta falhou. Um diagnostico inicial incompleto nao libera a correcao.' }
        Add-V3SolutionHistory $Session $job.Stage ("Falha na etapa: $($_.Exception.Message)`r`n$guidance")
        $Session.Dialog.FindName('SolutionStatus').Text = 'Falha registrada. Confira o relatorio antes de repetir.'
    }
    finally {
        try { Write-V3SolutionAudit -Id $Session.Id -Stage $job.Stage -Status $status -Confirmed $job.Confirmed }
        catch { $Session.Dialog.FindName('SolutionStatus').Text += ' Registro em arquivo indisponivel; salve o relatorio.' }
        $job.Pipeline.Dispose()
        $Session.Job = $null
        $Session.Timer.Stop()
        Update-V3SolutionControls $Session
    }
}

function Set-V3SolutionSelection {
    param($Session)
    $solution = $Session.Dialog.FindName('SolutionChoice').SelectedItem
    if ($null -eq $solution -or $null -ne $Session.Job) { return }
    $Session.Id = $solution.Id
    $Session.Diagnosed = $false
    $Session.RepairAttempted = $false
    $Session.Validated = $false
    $Session.Dialog.FindName('SolutionOutcome').SelectedIndex = 0
    $Session.Dialog.FindName('SolutionPlan').Text = "QUANDO USAR`r`n$($solution.Situation)`r`n`r`nANTES DE EXECUTAR`r`n$($solution.Preconditions)`r`n`r`nIMPACTO E COMANDO`r`n$($solution.Impact)`r`n$($solution.Command)`r`n`r`nCOMO VALIDAR`r`n$($solution.Validate)"
    $Session.Dialog.FindName('SolutionStatus').Text = 'Comece pelo diagnostico. As correcoes exigem confirmacao.'
    Update-V3SolutionControls $Session
}

function New-V3SolutionSession {
    $solutionXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Solucoes guiadas - ServiceDesk Toolkit" Width="860" Height="700" MinWidth="720" MinHeight="480" WindowStartupLocation="CenterOwner" Background="#F3F6FA" FontFamily="Segoe UI">
  <Grid Margin="16" Background="#F3F6FA">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel><TextBlock Text="Soluções guiadas" FontSize="22" FontWeight="Bold" Foreground="#0F172A"/><TextBlock Text="Selecione o problema e siga uma etapa por vez." Margin="0,4,0,10"/><ComboBox Name="SolutionChoice" DisplayMemberPath="Title" Height="32" AutomationProperties.Name="Problema do atendimento"/><WrapPanel Margin="0,10,0,8"><Button Name="SolutionDiagnose" Content="1. Diagnosticar" Padding="12,6" Margin="0,0,8,0"/><Button Name="SolutionRepair" Content="2. Aplicar correção" Padding="12,6" Margin="0,0,8,0" IsEnabled="False"/><Button Name="SolutionValidate" Content="3. Validar novamente" Padding="12,6" Margin="0,0,8,0" IsEnabled="False"/><Button Name="SolutionCancel" Content="Cancelar consulta" Padding="12,6" Visibility="Collapsed"/></WrapPanel></StackPanel>
    <TextBox Name="SolutionPlan" Grid.Row="1" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" MaxHeight="180" Padding="10" Margin="0,0,0,10" AutomationProperties.Name="Condições e impacto da solução"/>
    <TextBox Name="SolutionOutput" Grid.Row="2" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12" Padding="10" AutomationProperties.Name="Histórico das etapas do atendimento"/>
    <StackPanel Grid.Row="3" Margin="0,10,0,0"><WrapPanel Margin="0,0,0,8"><ComboBox Name="SolutionOutcome" Width="310" Height="30" SelectedIndex="0" IsEnabled="False" AutomationProperties.Name="Resultado do teste do sintoma"><ComboBoxItem Content="Após validar, informe o resultado"/><ComboBoxItem Content="Testei o sintoma: resolvido"/><ComboBoxItem Content="Testei o sintoma: persiste"/><ComboBoxItem Content="Ainda não testei o sintoma"/></ComboBox><Button Name="SolutionRecordOutcome" Content="4. Registrar resultado" Padding="12,6" Margin="8,0,0,0" IsEnabled="False"/></WrapPanel><TextBlock Name="SolutionStatus" TextWrapping="Wrap" Foreground="#334155" AutomationProperties.LiveSetting="Polite"/><TextBlock Text="Ao fechar, use Salvar relatório na janela principal para guardar o histórico. Durante uma etapa, aguarde a conclusão antes de fechar." FontSize="11" TextWrapping="Wrap" Margin="0,4,0,0"/></StackPanel>
  </Grid>
</Window>
'@
    [xml]$layout = $solutionXaml
    $dialog = [Windows.Markup.XamlReader]::Load([Xml.XmlNodeReader]::new($layout))
    if ($window.IsVisible) { $dialog.Owner = $window }
    $dialog.Width = [math]::Min($dialog.Width, [Windows.SystemParameters]::WorkArea.Width)
    $dialog.Height = [math]::Min($dialog.Height, [Windows.SystemParameters]::WorkArea.Height)
    $session = [pscustomobject]@{ Dialog = $dialog; Id = ''; Diagnosed = $false; RepairAttempted = $false; Validated = $false; Job = $null; Timer = [Windows.Threading.DispatcherTimer]::new(); History = [Text.StringBuilder]::new(); EntryCount = 0 }
    foreach ($solution in Get-V3SolutionCatalog) { [void]$dialog.FindName('SolutionChoice').Items.Add($solution) }
    return $session
}

function Update-V3SolutionLayout {
    param($Session)
    $Session.Dialog.FindName('SolutionPlan').MaxHeight = if ($Session.Dialog.Content.ActualHeight -lt 560) { 110 } else { 180 }
}

function Open-V3SolutionCatalog {
    $script:V3SolutionSession = New-V3SolutionSession
    $session = $script:V3SolutionSession
    $session.Timer.Interval = [TimeSpan]::FromMilliseconds(300)
    $session.Timer.Add_Tick({ Complete-V3SolutionStage $script:V3SolutionSession })
    $session.Dialog.Content.Add_SizeChanged({ Update-V3SolutionLayout $script:V3SolutionSession })
    $session.Dialog.FindName('SolutionChoice').Add_SelectionChanged({ Set-V3SolutionSelection $script:V3SolutionSession })
    $session.Dialog.FindName('SolutionDiagnose').Add_Click({ Start-V3SolutionStage $script:V3SolutionSession 'Diagnose' })
    $session.Dialog.FindName('SolutionRepair').Add_Click({ Start-V3SolutionStage $script:V3SolutionSession 'Repair' })
    $session.Dialog.FindName('SolutionValidate').Add_Click({ Start-V3SolutionStage $script:V3SolutionSession 'Validate' })
    $session.Dialog.FindName('SolutionCancel').Add_Click({ Stop-V3SolutionConsultation $script:V3SolutionSession })
    $session.Dialog.FindName('SolutionOutcome').Add_SelectionChanged({ Update-V3SolutionControls $script:V3SolutionSession })
    $session.Dialog.FindName('SolutionRecordOutcome').Add_Click({ Save-V3SolutionOutcome $script:V3SolutionSession })
    $session.Dialog.Add_Closing({
        param($sender, $eventArgs)
        if ($null -ne $script:V3SolutionSession.Job) { $eventArgs.Cancel = $true; $script:V3SolutionSession.Dialog.FindName('SolutionStatus').Text = 'Aguarde a etapa em andamento antes de fechar.' }
    })
    $session.Dialog.FindName('SolutionChoice').SelectedIndex = 0
    try { [void]$session.Dialog.ShowDialog() }
    finally { $session.Timer.Stop(); $script:V3SolutionSession = $null }
}

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="ServiceDesk Toolkit Corporate V3 | Temas" Height="820" Width="1180" WindowStartupLocation="CenterScreen" Background="#F3F6FA" FontFamily="Segoe UI" MinWidth="820" MinHeight="480">
    <Window.Resources>
        <Style x:Key="NavButton" TargetType="Button">
            <Setter Property="Height" Value="44" />
            <Setter Property="Margin" Value="0,4,0,0" />
            <Setter Property="Padding" Value="12,0" />
            <Setter Property="HorizontalContentAlignment" Value="Left" />
            <Setter Property="Background" Value="#162033" />
            <Setter Property="Foreground" Value="#E5E7EB" />
            <Setter Property="BorderBrush" Value="#263449" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="ButtonSurface" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="7" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonSurface" Property="BorderBrush" Value="#2563EB" />
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="ButtonSurface" Property="BorderBrush" Value="#60A5FA" />
                                <Setter TargetName="ButtonSurface" Property="BorderThickness" Value="2" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonSurface" Property="Opacity" Value="0.65" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonSurface" Property="Opacity" Value="0.45" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Height" Value="38" />
            <Setter Property="Margin" Value="0,6,8,0" />
            <Setter Property="Padding" Value="14,0" />
            <Setter Property="Background" Value="#1D4ED8" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="BorderBrush" Value="#1D4ED8" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="FontWeight" Value="SemiBold" />
        </Style>
        <Style x:Key="ActionGridButton" TargetType="Button">
            <Setter Property="MinHeight" Value="82" />
            <Setter Property="Margin" Value="4,4,4,4" />
            <Setter Property="Padding" Value="12,10" />
            <Setter Property="HorizontalAlignment" Value="Stretch" />
            <Setter Property="VerticalAlignment" Value="Stretch" />
            <Setter Property="HorizontalContentAlignment" Value="Left" />
            <Setter Property="VerticalContentAlignment" Value="Center" />
            <Setter Property="Background" Value="#FFFFFF" />
            <Setter Property="Foreground" Value="#0F172A" />
            <Setter Property="BorderBrush" Value="#CBD5E1" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="ButtonSurface" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="7" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonSurface" Property="BorderBrush" Value="#2563EB" />
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="ButtonSurface" Property="BorderBrush" Value="#60A5FA" />
                                <Setter TargetName="ButtonSurface" Property="BorderThickness" Value="2" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonSurface" Property="Opacity" Value="0.65" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonSurface" Property="Opacity" Value="0.45" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="SoftButton" TargetType="Button">
            <Setter Property="Height" Value="38" />
            <Setter Property="Margin" Value="0,6,8,0" />
            <Setter Property="Padding" Value="14,0" />
            <Setter Property="Background" Value="#FFFFFF" />
            <Setter Property="Foreground" Value="#0F172A" />
            <Setter Property="BorderBrush" Value="#CBD5E1" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="FontWeight" Value="SemiBold" />
        </Style>
        <Style x:Key="DangerButton" TargetType="Button">
            <Setter Property="Height" Value="38" />
            <Setter Property="Margin" Value="0,6,8,0" />
            <Setter Property="Padding" Value="14,0" />
            <Setter Property="Background" Value="#FEF2F2" />
            <Setter Property="Foreground" Value="#991B1B" />
            <Setter Property="BorderBrush" Value="#FCA5A5" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="FontWeight" Value="SemiBold" />
        </Style>
        <Style x:Key="FooterLinkButton" TargetType="Button">
            <Setter Property="Height" Value="28" />
            <Setter Property="Margin" Value="8,0,0,0" />
            <Setter Property="Padding" Value="12,0" />
            <Setter Property="Background" Value="#FFFFFF" />
            <Setter Property="Foreground" Value="#1D4ED8" />
            <Setter Property="BorderBrush" Value="#BFDBFE" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="FontSize" Value="11" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="ButtonSurface" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="7" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonSurface" Property="BorderBrush" Value="#2563EB" />
                            </Trigger>
                            <Trigger Property="IsKeyboardFocused" Value="True">
                                <Setter TargetName="ButtonSurface" Property="BorderBrush" Value="#60A5FA" />
                                <Setter TargetName="ButtonSurface" Property="BorderThickness" Value="2" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonSurface" Property="Opacity" Value="0.65" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonSurface" Property="Opacity" Value="0.45" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Name="AppSurface" Background="#F3F6FA">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="220" />
            <ColumnDefinition Width="*" />
        </Grid.ColumnDefinitions>
        <Border Grid.Column="0" Background="#0F172A">
            <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
                <StackPanel Margin="18,24">
                    <TextBlock Text="ServiceDesk" Foreground="White" FontSize="24" FontWeight="Bold" />
                    <TextBlock Text="Corporate V3" Foreground="#60A5FA" FontSize="18" FontWeight="Bold" Margin="0,0,0,24" />
                    <TextBlock Text="EXPLORAR TEMAS" Foreground="#94A3B8" FontSize="11" FontWeight="Bold" Margin="0,0,0,12" />
                    <Button Name="NavAll" Tag="All" Content="Todos os temas" Style="{StaticResource NavButton}" />
                    <Button Name="NavOverview" Tag="Overview" Content="Visão geral" Style="{StaticResource NavButton}" />
                    <Button Name="NavNetwork" Tag="Network" Content="Rede e internet" Style="{StaticResource NavButton}" />
                    <Button Name="NavVpn" Tag="Vpn" Content="VPN / Appgate" Style="{StaticResource NavButton}" />
                    <Button Name="NavPrinters" Tag="Printers" Content="Impressoras" Style="{StaticResource NavButton}" />
                    <Button Name="NavOffice" Tag="Office" Content="Office / TPM" Style="{StaticResource NavButton}" />
                    <Button Name="NavWindows" Tag="Windows" Content="Windows" Style="{StaticResource NavButton}" />
                    <TextBlock Text="TIPO DE AÇÃO" Foreground="#94A3B8" FontSize="11" FontWeight="Bold" Margin="0,18,0,6" />
                    <ComboBox Name="ActionKind" SelectedIndex="0" Height="34" Padding="8,4" FontSize="12" AutomationProperties.Name="Filtrar por tipo de ação" ToolTip="Combina o tipo de ação com o tema e a busca atuais.">
                        <ComboBoxItem Tag="All" Content="Todas as ações" />
                        <ComboBoxItem Tag="Consultation" Content="Diagnósticos e consultas" />
                        <ComboBoxItem Tag="Maintenance" Content="Correções e manutenção" />
                    </ComboBox>
                    <TextBlock Text="Comece por uma consulta. As ações de manutenção ficam separadas em cada tema." Foreground="#CBD5E1" FontSize="12" TextWrapping="Wrap" Margin="0,24,0,0" />
                    <TextBlock Text="Ctrl+F  Buscar ações&#x0a;Ctrl+Shift+F  Localizar no resultado&#x0a;F6  Busca / resultado&#x0a;Esc  Limpar busca / voltar" Foreground="#CBD5E1" FontSize="12" TextWrapping="Wrap" Margin="0,18,0,0" />
                </StackPanel>
            </ScrollViewer>
        </Border>
        <Grid Name="WorkspaceGrid" Grid.Column="1" Margin="20">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="Auto" />
                <RowDefinition Height="*" MinHeight="100" />
                <RowDefinition Height="12" />
                <RowDefinition Height="230" MinHeight="200" />
                <RowDefinition Height="Auto" />
            </Grid.RowDefinitions>
            <Border Grid.Row="0" Background="White" CornerRadius="12" Padding="16" BorderBrush="#E2E8F0" BorderThickness="1">
                <StackPanel>
                    <TextBlock Name="WorkspaceTitle" Text="Central de Atendimento Técnico" FontSize="24" FontWeight="Bold" Foreground="#0F172A" />
                    <TextBlock Name="WorkspaceDescription" Text="Escolha um tema, consulte o diagnóstico e acompanhe o resultado." FontSize="13" Foreground="#64748B" Margin="0,4,0,0" TextWrapping="Wrap" />
                </StackPanel>
            </Border>
            <ScrollViewer Name="ActionsScroll" Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Margin="0,0,0,10">
                <Border Background="White" CornerRadius="12" Padding="16" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,0,14">
                    <StackPanel>
                        <StackPanel Name="TopicOverview" Margin="0,0,0,20">
                            <UniformGrid Name="StationCards" Columns="4" Margin="0,0,0,18">
                                <Border Background="White" CornerRadius="14" Padding="14" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,10,0">
                                    <StackPanel>
                                        <TextBlock Text="COMPUTADOR" Foreground="#64748B" FontSize="11" FontWeight="Bold" />
                                        <TextBlock Name="CardV3Host" Text="-" FontSize="14" FontWeight="Bold" Foreground="#0F172A" TextTrimming="CharacterEllipsis" ToolTip="{Binding Text, RelativeSource={RelativeSource Self}}" />
                                    </StackPanel>
                                </Border>
                                <Border Background="White" CornerRadius="14" Padding="14" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,10,0">
                                    <StackPanel>
                                        <TextBlock Text="USUÁRIO" Foreground="#64748B" FontSize="11" FontWeight="Bold" />
                                        <TextBlock Name="CardV3User" Text="-" FontSize="14" FontWeight="Bold" Foreground="#0F172A" TextTrimming="CharacterEllipsis" ToolTip="{Binding Text, RelativeSource={RelativeSource Self}}" />
                                    </StackPanel>
                                </Border>
                                <Border Background="White" CornerRadius="14" Padding="14" BorderBrush="#E2E8F0" BorderThickness="1" Margin="0,0,10,0">
                                    <StackPanel>
                                        <TextBlock Text="ADMINISTRADOR" Foreground="#64748B" FontSize="11" FontWeight="Bold" />
                                        <TextBlock Name="CardV3Admin" Text="-" FontSize="14" FontWeight="Bold" Foreground="#0F172A" TextTrimming="CharacterEllipsis" ToolTip="{Binding Text, RelativeSource={RelativeSource Self}}" />
                                    </StackPanel>
                                </Border>
                                <Border Background="White" CornerRadius="14" Padding="14" BorderBrush="#E2E8F0" BorderThickness="1">
                                    <StackPanel>
                                        <TextBlock Text="VERSÃO" Foreground="#64748B" FontSize="11" FontWeight="Bold" />
                                        <TextBlock Name="CardV3Version" Text="-" FontSize="14" FontWeight="Bold" Foreground="#0F172A" TextTrimming="CharacterEllipsis" ToolTip="{Binding Text, RelativeSource={RelativeSource Self}}" />
                                    </StackPanel>
                                </Border>
                            </UniformGrid>
                            <TextBlock Text="Visão geral" FontSize="20" FontWeight="Bold" Foreground="#0F172A" />
                            <TextBlock Text="Comece pela saúde e pelo inventário." TextWrapping="Wrap" Foreground="#64748B" Margin="0,4,0,12" />
                            <StackPanel Tag="ActionsGroup" Uid="Consultation">
                                <TextBlock Text="DIAGNÓSTICOS E CONSULTAS" FontSize="11" FontWeight="Bold" Foreground="#64748B" Margin="4,10,0,6" />
                                <UniformGrid Columns="2">
                                    <Button Name="BtnV3Health" Style="{StaticResource ActionGridButton}" Tag="Visão geral Saúde da máquina Avalia memória, disco e reinicialização pendente." ToolTip="Avalia memória, disco e reinicialização pendente.">
                                        <StackPanel>
                                            <TextBlock Text="Saúde da máquina" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Avalia memória, disco e reinicialização pendente." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3Inventory" Style="{StaticResource ActionGridButton}" Tag="Visão geral Inventário Consulta hardware e sistema operacional." ToolTip="Consulta hardware e sistema operacional.">
                                        <StackPanel>
                                            <TextBlock Text="Inventário" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Consulta hardware e sistema operacional." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3Solutions" Style="{StaticResource ActionGridButton}" Tag="Visão geral Soluções guiadas resolver DNS impressora spooler Office login WAM comandos PowerShell" ToolTip="Diagnosticar, avaliar impacto, aplicar correção confirmada e validar o sintoma.">
                                        <StackPanel><TextBlock Text="Soluções guiadas" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13"/><TextBlock Text="DNS, impressão e login do Office, com etapas e histórico." TextWrapping="Wrap" FontSize="11" Foreground="#64748B" Margin="0,5,0,0"/></StackPanel>
                                    </Button>
                                </UniformGrid>
                            </StackPanel>
                        </StackPanel>
                        <StackPanel Name="TopicNetwork" Margin="0,0,0,20">
                            <TextBlock Text="Rede e internet" FontSize="20" FontWeight="Bold" Foreground="#0F172A" />
                            <TextBlock Text="Investigue conectividade, DNS e rotas." TextWrapping="Wrap" Foreground="#64748B" Margin="0,4,0,12" />
                            <StackPanel Tag="ActionsGroup" Uid="Consultation">
                                <TextBlock Text="DIAGNÓSTICOS E CONSULTAS" FontSize="11" FontWeight="Bold" Foreground="#64748B" Margin="4,10,0,6" />
                                <UniformGrid Columns="2">
                                    <Button Name="BtnV3QuickInternet" Style="{StaticResource ActionGridButton}" Tag="Rede e internet Sem internet Conduz a triagem de falhas de internet." ToolTip="Conduz a triagem de falhas de internet.">
                                        <StackPanel>
                                            <TextBlock Text="Sem internet" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Conduz a triagem de falhas de internet." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3Network" Style="{StaticResource ActionGridButton}" Tag="Rede e internet Diagnóstico de rede Reúne os principais indicadores de conectividade." ToolTip="Reúne os principais indicadores de conectividade.">
                                        <StackPanel>
                                            <TextBlock Text="Diagnóstico de rede" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Reúne os principais indicadores de conectividade." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3NetworkAdvanced" Style="{StaticResource ActionGridButton}" Tag="Rede e internet Rede: adaptadores e IP Exibe adaptadores, endereços e configuração IP." ToolTip="Exibe adaptadores, endereços e configuração IP.">
                                        <StackPanel>
                                            <TextBlock Text="Rede: adaptadores e IP" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Exibe adaptadores, endereços e configuração IP." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3DnsDetails" Style="{StaticResource ActionGridButton}" Tag="Rede e internet Rede: DNS detalhado Consulta servidores DNS e resolução de nomes." ToolTip="Consulta servidores DNS e resolução de nomes.">
                                        <StackPanel>
                                            <TextBlock Text="Rede: DNS detalhado" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Consulta servidores DNS e resolução de nomes." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3Routes" Style="{StaticResource ActionGridButton}" Tag="Rede e internet Rede: rotas Exibe caminhos e rotas configuradas." ToolTip="Exibe caminhos e rotas configuradas.">
                                        <StackPanel>
                                            <TextBlock Text="Rede: rotas" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Exibe caminhos e rotas configuradas." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3Gateway" Style="{StaticResource ActionGridButton}" Tag="Rede e internet Rede: testar gateway Verifica a resposta do gateway padrão." ToolTip="Verifica a resposta do gateway padrão.">
                                        <StackPanel>
                                            <TextBlock Text="Rede: testar gateway" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Verifica a resposta do gateway padrão." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3NetworkConnections" Style="{StaticResource ActionGridButton}" Tag="Rede e internet Abrir conexões de rede Abre os adaptadores nas configurações do Windows." ToolTip="Abre os adaptadores nas configurações do Windows.">
                                        <StackPanel>
                                            <TextBlock Text="Abrir conexões de rede" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Abre os adaptadores nas configurações do Windows." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                </UniformGrid>
                            </StackPanel>
                            <StackPanel Tag="ActionsGroup" Uid="Maintenance">
                                <TextBlock Text="CORREÇÕES E MANUTENÇÃO" FontSize="11" FontWeight="Bold" Foreground="#64748B" Margin="4,10,0,6" />
                                <TextBlock Text="Confira o impacto indicado antes de executar uma correção." TextWrapping="Wrap" Foreground="#92400E" Margin="4,0,0,6" />
                                <UniformGrid Columns="2">
                                    <Button Name="BtnV3FlushDns" Style="{StaticResource ActionGridButton}" Background="#FFFBEB" BorderBrush="#FDE68A" Tag="Rede e internet Limpar DNS Limpa o cache DNS e verifica o resultado." ToolTip="Limpa o cache DNS e verifica o resultado.">
                                        <StackPanel>
                                            <TextBlock Text="Limpar DNS" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Limpa o cache DNS e verifica o resultado." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3RenewIp" Style="{StaticResource ActionGridButton}" ToolTip="Interrompe a conexão temporariamente e exige confirmação." Background="#FFFBEB" BorderBrush="#FDE68A" Tag="Rede e internet Rede: renovar IP Renova o IP; interrompe a conexão temporariamente.">
                                        <StackPanel>
                                            <TextBlock Text="Rede: renovar IP" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Renova o IP; interrompe a conexão temporariamente." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3Winsock" Style="{StaticResource ActionGridButton}" ToolTip="Exige administrador, confirmação e reinicialização." Background="#FFFBEB" BorderBrush="#FDE68A" Tag="Rede e internet Rede: reset Winsock Redefine Winsock; exige administrador e reinício.">
                                        <StackPanel>
                                            <TextBlock Text="Rede: reset Winsock" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Redefine Winsock; exige administrador e reinício." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3TcpIp" Style="{StaticResource ActionGridButton}" ToolTip="Exige administrador, confirmação e reinicialização." Background="#FFFBEB" BorderBrush="#FDE68A" Tag="Rede e internet Rede: reset TCP/IP Redefine TCP/IP; exige administrador e reinício.">
                                        <StackPanel>
                                            <TextBlock Text="Rede: reset TCP/IP" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Redefine TCP/IP; exige administrador e reinício." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                </UniformGrid>
                            </StackPanel>
                        </StackPanel>
                        <StackPanel Name="TopicVpn" Margin="0,0,0,20">
                            <TextBlock Text="VPN / Appgate" FontSize="20" FontWeight="Bold" Foreground="#0F172A" />
                            <TextBlock Text="Confira o cliente e os serviços antes de corrigir." TextWrapping="Wrap" Foreground="#64748B" Margin="0,4,0,12" />
                            <StackPanel Tag="ActionsGroup" Uid="Consultation">
                                <TextBlock Text="DIAGNÓSTICOS E CONSULTAS" FontSize="11" FontWeight="Bold" Foreground="#64748B" Margin="4,10,0,6" />
                                <UniformGrid Columns="2">
                                    <Button Name="BtnV3QuickVpn" Style="{StaticResource ActionGridButton}" Tag="VPN / Appgate VPN / Appgate Conduz a triagem de acesso pela VPN." ToolTip="Conduz a triagem de acesso pela VPN.">
                                        <StackPanel>
                                            <TextBlock Text="VPN / Appgate" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Conduz a triagem de acesso pela VPN." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3AppgateStatus" Style="{StaticResource ActionGridButton}" Tag="VPN / Appgate Appgate: status Consulta configuração, serviços e processos." ToolTip="Consulta configuração, serviços e processos.">
                                        <StackPanel>
                                            <TextBlock Text="Appgate: status" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Consulta configuração, serviços e processos." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                </UniformGrid>
                            </StackPanel>
                            <StackPanel Tag="ActionsGroup" Uid="Maintenance">
                                <TextBlock Text="CORREÇÕES E MANUTENÇÃO" FontSize="11" FontWeight="Bold" Foreground="#64748B" Margin="4,10,0,6" />
                                <TextBlock Text="Confira o impacto indicado antes de executar uma correção." TextWrapping="Wrap" Foreground="#92400E" Margin="4,0,0,6" />
                                <UniformGrid Columns="2">
                                    <Button Name="BtnV3AppgateRestart" Style="{StaticResource ActionGridButton}" ToolTip="Interrompe a VPN temporariamente e exige confirmação." Background="#FFFBEB" BorderBrush="#FDE68A" Tag="VPN / Appgate Appgate: reiniciar Reinicia o cliente; interrompe a VPN temporariamente.">
                                        <StackPanel>
                                            <TextBlock Text="Appgate: reiniciar" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Reinicia o cliente; interrompe a VPN temporariamente." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3AppgateFix" Style="{StaticResource ActionGridButton}" ToolTip="Cria backup e ajusta RunScriptTimeout com confirmação." Background="#FFFBEB" BorderBrush="#FDE68A" Tag="VPN / Appgate Appgate: ajustar Cria backup e ajusta timeout.">
                                        <StackPanel>
                                            <TextBlock Text="Appgate: ajustar" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Cria backup e ajusta timeout." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                </UniformGrid>
                            </StackPanel>
                        </StackPanel>
                        <StackPanel Name="TopicPrinters" Margin="0,0,0,20">
                            <TextBlock Text="Impressoras" FontSize="20" FontWeight="Bold" Foreground="#0F172A" />
                            <TextBlock Text="Consulte impressoras, filas e serviço de impressão." TextWrapping="Wrap" Foreground="#64748B" Margin="0,4,0,12" />
                            <StackPanel Tag="ActionsGroup" Uid="Consultation">
                                <TextBlock Text="DIAGNÓSTICOS E CONSULTAS" FontSize="11" FontWeight="Bold" Foreground="#64748B" Margin="4,10,0,6" />
                                <UniformGrid Columns="2">
                                    <Button Name="BtnV3Printers" Style="{StaticResource ActionGridButton}" Tag="Impressoras Impressoras Conduz a triagem de uma impressora que não imprime." ToolTip="Conduz a triagem de uma impressora que não imprime.">
                                        <StackPanel>
                                            <TextBlock Text="Impressoras" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Conduz a triagem de uma impressora que não imprime." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3PrinterList" Style="{StaticResource ActionGridButton}" Tag="Impressoras Impressoras: listar Lista as impressoras instaladas." ToolTip="Lista as impressoras instaladas.">
                                        <StackPanel>
                                            <TextBlock Text="Impressoras: listar" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Lista as impressoras instaladas." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3PrintJobs" Style="{StaticResource ActionGridButton}" Tag="Impressoras Impressoras: filas Consulta documentos pendentes nas filas." ToolTip="Consulta documentos pendentes nas filas.">
                                        <StackPanel>
                                            <TextBlock Text="Impressoras: filas" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Consulta documentos pendentes nas filas." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3DefaultPrinter" Style="{StaticResource ActionGridButton}" Tag="Impressoras Impressora padrão Identifica a impressora padrão." ToolTip="Identifica a impressora padrão.">
                                        <StackPanel>
                                            <TextBlock Text="Impressora padrão" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Identifica a impressora padrão." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3OfflinePrinters" Style="{StaticResource ActionGridButton}" Tag="Impressoras Impressoras offline Consulta impressoras offline ou com alertas." ToolTip="Consulta impressoras offline ou com alertas.">
                                        <StackPanel>
                                            <TextBlock Text="Impressoras offline" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Consulta impressoras offline ou com alertas." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3PrinterSettings" Style="{StaticResource ActionGridButton}" Tag="Impressoras Abrir impressoras Abre as configurações de impressoras do Windows." ToolTip="Abre as configurações de impressoras do Windows.">
                                        <StackPanel>
                                            <TextBlock Text="Abrir impressoras" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Abre as configurações de impressoras do Windows." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3PrintManagement" Style="{StaticResource ActionGridButton}" Tag="Impressoras Gerenciar impressão Abre o console de gerenciamento de impressão." ToolTip="Abre o console de gerenciamento de impressão.">
                                        <StackPanel>
                                            <TextBlock Text="Gerenciar impressão" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Abre o console de gerenciamento de impressão." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                </UniformGrid>
                            </StackPanel>
                            <StackPanel Tag="ActionsGroup" Uid="Maintenance">
                                <TextBlock Text="CORREÇÕES E MANUTENÇÃO" FontSize="11" FontWeight="Bold" Foreground="#64748B" Margin="4,10,0,6" />
                                <TextBlock Text="Confira o impacto indicado antes de executar uma correção." TextWrapping="Wrap" Foreground="#92400E" Margin="4,0,0,6" />
                                <UniformGrid Columns="2">
                                    <Button Name="BtnV3Spooler" Style="{StaticResource ActionGridButton}" Background="#FFFBEB" BorderBrush="#FDE68A" Tag="Impressoras Reiniciar spooler Reinicia o serviço de impressão e verifica o estado." ToolTip="Reinicia o serviço de impressão e verifica o estado.">
                                        <StackPanel>
                                            <TextBlock Text="Reiniciar spooler" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Reinicia o serviço de impressão e verifica o estado." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3ClearPrintQueue" Style="{StaticResource ActionGridButton}" ToolTip="Remove trabalhos pendentes e exige confirmação administrativa." Background="#FFFBEB" BorderBrush="#FDE68A" Tag="Impressoras Limpar fila de impressão Remove documentos pendentes; exige confirmação.">
                                        <StackPanel>
                                            <TextBlock Text="Limpar fila de impressão" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Remove documentos pendentes; exige confirmação." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                </UniformGrid>
                            </StackPanel>
                        </StackPanel>
                        <StackPanel Name="TopicOffice" Margin="0,0,0,20">
                            <TextBlock Text="Office / TPM" FontSize="20" FontWeight="Bold" Foreground="#0F172A" />
                            <TextBlock Text="Investigue autenticação, licenças e proteção." TextWrapping="Wrap" Foreground="#64748B" Margin="0,4,0,12" />
                            <StackPanel Tag="ActionsGroup" Uid="Consultation">
                                <TextBlock Text="DIAGNÓSTICOS E CONSULTAS" FontSize="11" FontWeight="Bold" Foreground="#64748B" Margin="4,10,0,6" />
                                <UniformGrid Columns="2">
                                    <Button Name="BtnV3OfficeTpm" Style="{StaticResource ActionGridButton}" ToolTip="Diagnostica Office, TPM, WAM, licenciamento e estado Entra sem executar correcao." Tag="Office / TPM Office / TPM Consulta Office, TPM, WAM, licenças e Entra.">
                                        <StackPanel>
                                            <TextBlock Text="Office / TPM" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Consulta Office, TPM, WAM, licenças e Entra." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                </UniformGrid>
                            </StackPanel>
                            <StackPanel Tag="ActionsGroup" Uid="Maintenance">
                                <TextBlock Text="CORREÇÕES E MANUTENÇÃO" FontSize="11" FontWeight="Bold" Foreground="#64748B" Margin="4,10,0,6" />
                                <TextBlock Text="Confira o impacto indicado antes de executar uma correção." TextWrapping="Wrap" Foreground="#92400E" Margin="4,0,0,6" />
                                <UniformGrid Columns="2">
                                    <Button Name="BtnV3OfficeWam" Style="{StaticResource ActionGridButton}" ToolTip="Repara o login WAM de Microsoft 365 e Office 2016, 2019 e 2021. Nao limpa TPM nem credenciais." Background="#FFFBEB" BorderBrush="#FDE68A" Tag="Office / TPM Reparar login Office Registra componentes WAM novamente no perfil atual.">
                                        <StackPanel>
                                            <TextBlock Text="Reparar login Office" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Registra componentes WAM novamente no perfil atual." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                </UniformGrid>
                            </StackPanel>
                        </StackPanel>
                        <StackPanel Name="TopicWindows" Margin="0,0,0,20">
                            <TextBlock Text="Windows" FontSize="20" FontWeight="Bold" Foreground="#0F172A" />
                            <TextBlock Text="Horário e manutenção dos componentes do Windows." TextWrapping="Wrap" Foreground="#64748B" Margin="0,4,0,12" />
                            <StackPanel Tag="ActionsGroup" Uid="Consultation">
                                <TextBlock Text="DIAGNÓSTICOS E CONSULTAS" FontSize="11" FontWeight="Bold" Foreground="#64748B" Margin="4,10,0,6" />
                                <UniformGrid Columns="2">
                                    <Button Name="BtnV3Storage" Style="{StaticResource ActionGridButton}" Tag="Windows espaço disco armazenamento liberar limpeza temporários Outlook OST PST OneDrive SCCM Lixeira arquivos grandes passo a passo" ToolTip="Coleta somente leitura em segundo plano, com limites. Mostra achados e um plano por situação; não apaga arquivos.">
                                        <StackPanel>
                                            <TextBlock Text="Espaço em disco: diagnóstico e plano" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Identifica arquivos e orienta a liberação por situação." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                </UniformGrid>
                            </StackPanel>
                            <StackPanel Tag="ActionsGroup" Uid="Maintenance">
                                <TextBlock Text="CORREÇÕES E MANUTENÇÃO" FontSize="11" FontWeight="Bold" Foreground="#64748B" Margin="4,10,0,6" />
                                <TextBlock Text="Confira o impacto indicado antes de executar uma correção." TextWrapping="Wrap" Foreground="#92400E" Margin="4,0,0,6" />
                                <UniformGrid Columns="2">
                                    <Button Name="BtnV3TimeSync" Style="{StaticResource ActionGridButton}" Background="#FFFBEB" BorderBrush="#FDE68A" Tag="Windows Sincronizar horário Sincroniza o horário e verifica antes e depois." ToolTip="Sincroniza o horário e verifica antes e depois.">
                                        <StackPanel>
                                            <TextBlock Text="Sincronizar horário" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Sincroniza o horário e verifica antes e depois." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3Sfc" Style="{StaticResource ActionGridButton}" ToolTip="Verifica e tenta reparar arquivos protegidos do Windows. Exige permissão administrativa." Background="#FFFBEB" BorderBrush="#FDE68A" Tag="Windows SFC: verificar arquivos Verifica e pode reparar arquivos do Windows.">
                                        <StackPanel>
                                            <TextBlock Text="SFC: verificar arquivos" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Verifica e pode reparar arquivos do Windows." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                    <Button Name="BtnV3Dism" Style="{StaticResource ActionGridButton}" ToolTip="Repara a imagem de componentes do Windows. Exige permissão administrativa e pode depender do Windows Update." Background="#FFFBEB" BorderBrush="#FDE68A" Tag="Windows DISM: reparar imagem Repara componentes; pode depender do Windows Update.">
                                        <StackPanel>
                                            <TextBlock Text="DISM: reparar imagem" TextWrapping="Wrap" FontWeight="SemiBold" FontSize="13" />
                                            <TextBlock Text="Repara componentes; pode depender do Windows Update." TextWrapping="Wrap" FontWeight="Normal" FontSize="11" Foreground="#64748B" Margin="0,5,0,0" />
                                        </StackPanel>
                                    </Button>
                                </UniformGrid>
                            </StackPanel>
                        </StackPanel>
                        <TextBlock Name="NoActions" Visibility="Collapsed" Text="Nenhuma ação encontrada neste tema. Limpe a busca ou selecione Todos os temas." TextWrapping="Wrap" FontSize="14" Foreground="#64748B" Margin="0,12" />
                        <Button Name="BtnV3ResetFilters" Visibility="Collapsed" Content="Exibir todas as ações" Style="{StaticResource FooterLinkButton}" HorizontalAlignment="Left" Height="34" Margin="0,0,0,12" ToolTip="Limpa a busca, seleciona todos os temas e todos os tipos de ação. Preserva o relatório." />
                    </StackPanel>
                </Border>
            </ScrollViewer>
            <Border Name="ResultContainer" Grid.Row="4" Background="White" CornerRadius="12" Padding="16" BorderBrush="#E2E8F0" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto" />
                        <RowDefinition Height="*" />
                    </Grid.RowDefinitions>
                    <StackPanel Name="ResultHeader" Margin="0,0,0,10">
                        <DockPanel>
                            <TextBlock Name="ResultStatus" DockPanel.Dock="Right" Text="Pronto para consultar" MaxWidth="300" TextTrimming="CharacterEllipsis" ToolTip="{Binding Text, RelativeSource={RelativeSource Self}}" FontSize="11" Foreground="#475569" VerticalAlignment="Center" />
                            <TextBlock Text="Resultado e andamento" FontSize="16" FontWeight="Bold" Foreground="#0F172A" />
                        </DockPanel>
                        <WrapPanel Margin="-8,8,0,0">
                            <Button Name="BtnV3CancelStorage" Content="Cancelar coleta" Visibility="Collapsed" Style="{StaticResource FooterLinkButton}" ToolTip="Interrompe a leitura de disco sem executar limpeza." />
                            <Button Name="BtnV3CopyOutput" Content="Copiar resultado" Style="{StaticResource FooterLinkButton}" ToolTip="Copiar o relatório exibido." />
                            <Button Name="BtnV3SaveOutput" Content="Salvar relatório" Style="{StaticResource FooterLinkButton}" ToolTip="Salvar o texto exibido no local escolhido. O relatório pode conter caminhos e dados corporativos." />
                            <Button Name="BtnV3FindResult" Content="Localizar no resultado" Style="{StaticResource FooterLinkButton}" ToolTip="Buscar texto neste relatório. Ctrl+Shift+F." />
                            <Button Name="BtnV3ExpandResult" Content="Ampliar resultado" Style="{StaticResource FooterLinkButton}" ToolTip="Usar o espaço das ações para ler o relatório. Clique novamente para voltar." />
                            <Button Name="BtnV3SmallerText" Content="A−" Style="{StaticResource FooterLinkButton}" AutomationProperties.Name="Diminuir texto do resultado" ToolTip="Diminuir texto do resultado." />
                            <Button Name="BtnV3LargerText" Content="A+" Style="{StaticResource FooterLinkButton}" AutomationProperties.Name="Aumentar texto do resultado" ToolTip="Aumentar texto do resultado." />
                            <ComboBox Name="ResultSections" Visibility="Collapsed" Width="240" Height="30" Margin="8,0,0,0" VerticalAlignment="Center" DisplayMemberPath="Label" AutomationProperties.Name="Ir para seção do resultado" AutomationProperties.HelpText="Selecione uma seção numerada para ampliar a leitura e ir ao trecho correspondente. Não altera o relatório." ToolTip="Ir diretamente a uma seção deste relatório." />
                        </WrapPanel>
                        <WrapPanel Name="StorageFollowup" Visibility="Collapsed" Margin="-8,8,0,0">
                            <Button Name="BtnV3StorageBaseline" Content="Definir leitura inicial" Style="{StaticResource FooterLinkButton}" ToolTip="Guardar esta leitura na sessão para comparar com um novo diagnóstico após a ação do suporte." />
                            <Button Name="BtnV3CompareStorage" Content="Comparar leituras" IsEnabled="False" Style="{StaticResource FooterLinkButton}" ToolTip="Comparar o espaço livre por unidade com a leitura inicial. Não executa limpeza." />
                            <TextBlock Name="StorageBaselineStatus" VerticalAlignment="Center" Margin="8,0,0,0" FontSize="11" Foreground="#475569" TextWrapping="Wrap" />
                        </WrapPanel>
                        <Grid Name="ResultSearchPanel" Visibility="Collapsed" Margin="0,8,0,0">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*" />
                                <ColumnDefinition Width="Auto" />
                            </Grid.ColumnDefinitions>
                            <TextBox Name="SearchResult" Height="30" VerticalContentAlignment="Center" Padding="8,0" BorderBrush="#CBD5E1" AutomationProperties.Name="Localizar texto no resultado" AutomationProperties.HelpText="Busca literal sem distinguir maiúsculas. Enter avança, Shift+Enter volta, Esc fecha. Não altera o relatório." ToolTip="Digite uma categoria, arquivo ou trecho do relatório." />
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <TextBlock Name="ResultMatchStatus" Text="Digite um texto" VerticalAlignment="Center" Margin="8,0" Foreground="#475569" AutomationProperties.LiveSetting="Polite" />
                                <Button Name="BtnV3PreviousMatch" Content="Anterior" IsEnabled="False" Style="{StaticResource FooterLinkButton}" ToolTip="Ocorrência anterior. Shift+F3." />
                                <Button Name="BtnV3NextMatch" Content="Próxima" IsEnabled="False" Style="{StaticResource FooterLinkButton}" ToolTip="Próxima ocorrência. F3." />
                                <Button Name="BtnV3CloseResultSearch" Content="Fechar" Style="{StaticResource FooterLinkButton}" ToolTip="Fechar busca no resultado. Esc." />
                            </StackPanel>
                        </Grid>
                    </StackPanel>
                    <TextBox Name="TxtV3Output" AutomationProperties.Name="Resultado do atendimento" AutomationProperties.HelpText="Relatório somente leitura. Ctrl+Shift+F localiza texto neste relatório. F6 alterna entre resultado e busca de ações. Esc fecha a busca ou retorna às ações." Grid.Row="1" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" FontFamily="Consolas" FontSize="13" Background="#F8FAFC" BorderBrush="#CBD5E1" BorderThickness="1" IsReadOnly="True" IsInactiveSelectionHighlightEnabled="True" Padding="12" />
                </Grid>
            </Border>
            <Border Name="WorkspaceFooter" Grid.Row="5" Background="Transparent" Margin="0,10,0,0">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*" />
                        <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="ServiceDesk Toolkit Corporate V3 - Made by Caio Dal Re" Foreground="#64748B" FontSize="11" VerticalAlignment="Center" />
                    <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button Name="BtnV3LinkedIn" Content="LinkedIn" Style="{StaticResource FooterLinkButton}" ToolTip="Abrir LinkedIn de Caio Dal Re" />
                        <Button Name="BtnV3GitHub" Content="GitHub" Style="{StaticResource FooterLinkButton}" ToolTip="Abrir GitHub de Caio Dal Re" />
                    </StackPanel>
                </Grid>
            </Border>
            <GridSplitter Name="ResultSplitter" Grid.Row="3" Height="6" HorizontalAlignment="Stretch" VerticalAlignment="Center" Background="#CBD5E1" ResizeDirection="Rows" ResizeBehavior="PreviousAndNext" ToolTip="Arraste para ajustar o espaço de ações e resultado." />
            <Grid Grid.Row="1" Margin="0,12,0,14">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto" />
                    <RowDefinition Height="Auto" />
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                <TextBlock Name="SearchScope" Text="Buscar ações neste tema" FontSize="12" FontWeight="SemiBold" Foreground="#475569" Margin="0,0,0,6" />
                <TextBlock Name="ActionCount" Grid.Column="1" FontSize="11" Foreground="#64748B" VerticalAlignment="Center" />
                <Grid Grid.Row="1">
                    <TextBox Name="SearchActions" Height="34" Padding="10,6" VerticalContentAlignment="Center" FontSize="13" Background="White" BorderBrush="#CBD5E1" BorderThickness="1" AutomationProperties.Name="Buscar ações" AutomationProperties.HelpText="Busca no tema selecionado. Use Buscar em todos para ampliar a procura. Ctrl+F seleciona o campo; Esc limpa a busca." ToolTip="Digite o nome da ação ou uma palavra como DNS, fila ou licença. Ctrl+F para buscar; Esc para limpar." />
                    <TextBlock Name="SearchHint" Text="Ex.: DNS, impressora ou licença" IsHitTestVisible="False" Foreground="#64748B" Margin="11,0" VerticalAlignment="Center" />
                </Grid>
                <StackPanel Grid.Row="1" Grid.Column="1" Orientation="Horizontal">
                    <Button Name="BtnV3SearchAll" Content="Buscar em todos" Style="{StaticResource FooterLinkButton}" Height="34" ToolTip="Mantém o texto da busca e procura em todos os temas." />
                    <Button Name="BtnV3ClearSearch" Content="Limpar busca" Style="{StaticResource FooterLinkButton}" Height="34" ToolTip="Exibe novamente todas as ações do tema atual. Esc para limpar." />
                </StackPanel>
            </Grid>
        </Grid>
    </Grid>
</Window>
"@

[xml]$xml = $xaml
$reader = New-Object System.Xml.XmlNodeReader $xml
$window = [Windows.Markup.XamlReader]::Load($reader)

$window.Width = [Math]::Min($window.Width, [System.Windows.SystemParameters]::WorkArea.Width)
$window.Height = [Math]::Min($window.Height, [System.Windows.SystemParameters]::WorkArea.Height)
$script:TxtV3Output = $window.FindName("TxtV3Output")

$CardV3Host = $window.FindName("CardV3Host")
$CardV3User = $window.FindName("CardV3User")
$CardV3Admin = $window.FindName("CardV3Admin")
$CardV3Version = $window.FindName("CardV3Version")

$CardV3Host.Text = $env:COMPUTERNAME
$CardV3User.Text = "$env:USERDOMAIN\$env:USERNAME"
$CardV3Admin.Text = if (Test-V3Admin) { "Sim" } else { "Não" }
$CardV3Version.Text = Get-V3VersionInfo

$script:V3ResultExpanded = $false
$script:V3CompactLayout = $false
function Update-V3ResultSections {
    $picker = $window.FindName("ResultSections")
    $script:V3UpdatingResultSections = $true
    try {
        $picker.Items.Clear()
        $sections = @([regex]::Matches($script:TxtV3Output.Text, '(?m)^\[(\d+)\] ([^\r\n|]+)\r?$'))
        $picker.Visibility = if ($sections.Count -gt 0) { "Visible" } else { "Collapsed" }
        if ($sections.Count -eq 0) { return }
        [void]$picker.Items.Add([pscustomobject]@{ Label = "Ir para uma seção..."; Position = -1; Length = 0 })
        foreach ($section in $sections) {
            [void]$picker.Items.Add([pscustomobject]@{
                Label = $section.Value.TrimEnd("`r")
                Position = $section.Index
                Length = $section.Value.TrimEnd("`r").Length
            })
        }
        $picker.SelectedIndex = 0
    }
    finally { $script:V3UpdatingResultSections = $false }
}

function Move-V3ResultSection {
    if ($script:V3UpdatingResultSections) { return }
    $selected = $window.FindName("ResultSections").SelectedItem
    if ($null -eq $selected -or $selected.Position -lt 0) { return }
    Set-V3ResultSearchVisible -Visible $false
    Set-V3ResultExpanded -Expanded $true
    $script:TxtV3Output.Select($selected.Position, $selected.Length)
    $line = $script:TxtV3Output.GetLineIndexFromCharacterIndex($selected.Position)
    if ($line -ge 0) { $script:TxtV3Output.ScrollToLine($line) }
}

function Update-V3ResultSearch {
    $query = $window.FindName("SearchResult").Text
    $script:V3ResultMatches = @()
    $script:V3ResultMatchIndex = -1
    if (-not [string]::IsNullOrEmpty($query)) {
        $matches = [Collections.Generic.List[int]]::new()
        $offset = 0
        $text = $script:TxtV3Output.Text
        while ($offset -le $text.Length - $query.Length) {
            $position = $text.IndexOf($query, $offset, [StringComparison]::OrdinalIgnoreCase)
            if ($position -lt 0) { break }
            $matches.Add($position)
            $offset = $position + $query.Length
        }
        $script:V3ResultMatches = @($matches.ToArray())
    }
    $found = $script:V3ResultMatches.Count -gt 0
    $window.FindName("BtnV3PreviousMatch").IsEnabled = $found
    $window.FindName("BtnV3NextMatch").IsEnabled = $found
    $window.FindName("ResultMatchStatus").Text = if ([string]::IsNullOrEmpty($query)) { "Digite um texto" } elseif (-not $found) { "Nenhuma ocorrência" } else { "$($script:V3ResultMatches.Count) ocorrência(s)" }
    if ($found) { Move-V3ResultMatch -Direction 1 }
}

function Move-V3ResultMatch {
    param([int]$Direction = 1)
    if ($script:V3ResultMatches.Count -eq 0) { return }
    $count = $script:V3ResultMatches.Count
    $script:V3ResultMatchIndex = ($script:V3ResultMatchIndex + $Direction + $count) % $count
    $position = $script:V3ResultMatches[$script:V3ResultMatchIndex]
    $script:TxtV3Output.Select($position, $window.FindName("SearchResult").Text.Length)
    $line = $script:TxtV3Output.GetLineIndexFromCharacterIndex($position)
    if ($line -ge 0) { $script:TxtV3Output.ScrollToLine($line) }
    $window.FindName("ResultMatchStatus").Text = "$($script:V3ResultMatchIndex + 1) de $count"
}

function Set-V3ResultSearchVisible {
    param([bool]$Visible)
    $window.FindName("ResultSearchPanel").Visibility = if ($Visible) { "Visible" } else { "Collapsed" }
    if ($Visible) {
        Set-V3ResultExpanded -Expanded $true
        Update-V3ResultSearch
        [void]$window.FindName("SearchResult").Focus()
        $window.FindName("SearchResult").SelectAll()
    }
    else { [void]$script:TxtV3Output.Focus() }
}

$script:V3ResultMatches = @()
$script:V3ResultMatchIndex = -1
$script:V3UpdatingResultSections = $false
$window.FindName("ResultSections").Add_SelectionChanged({ Move-V3ResultSection })
$window.FindName("BtnV3FindResult").Add_Click({ Set-V3ResultSearchVisible -Visible $true })
$window.FindName("BtnV3SaveOutput").Add_Click({ Save-V3Output })
$window.FindName("BtnV3StorageBaseline").Add_Click({ Set-V3StorageBaseline })
$window.FindName("BtnV3CompareStorage").Add_Click({ Compare-V3StorageReadings })
$window.FindName("BtnV3CloseResultSearch").Add_Click({ Set-V3ResultSearchVisible -Visible $false })
$window.FindName("BtnV3PreviousMatch").Add_Click({ Move-V3ResultMatch -Direction -1 })
$window.FindName("BtnV3NextMatch").Add_Click({ Move-V3ResultMatch -Direction 1 })
$window.FindName("SearchResult").Add_TextChanged({ Update-V3ResultSearch })
$script:TxtV3Output.Add_TextChanged({
    Update-V3StorageFollowup
    Update-V3ResultSections
    if ($window.FindName("ResultSearchPanel").Visibility -eq "Visible") { Update-V3ResultSearch }
})
$window.FindName("SearchResult").Add_PreviewKeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.Key -eq [System.Windows.Input.Key]::Return) {
        $direction = if (([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0) { -1 } else { 1 }
        Move-V3ResultMatch -Direction $direction
        $eventArgs.Handled = $true
    }
})

function Set-V3ResultExpanded {
    param([bool]$Expanded)

    $grid = $window.FindName("WorkspaceGrid")
    if ($Expanded -and -not $script:V3ResultExpanded) {
        $script:V3ActionsHeight = $grid.RowDefinitions[2].Height
        $script:V3ResultHeight = $grid.RowDefinitions[4].Height
    }
    $script:V3ResultExpanded = $Expanded
    $grid.RowDefinitions[2].MinHeight = if ($Expanded) { 0 } elseif ($script:V3CompactLayout) { 80 } else { 100 }
    $grid.RowDefinitions[2].Height = if ($Expanded) {
        [System.Windows.GridLength]::new(0)
    }
    else {
        $script:V3ActionsHeight
    }
    $grid.RowDefinitions[4].Height = if ($Expanded) {
        [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    }
    else {
        $script:V3ResultHeight
    }
    $window.FindName("ActionsScroll").Visibility = if ($Expanded) { "Collapsed" } else { "Visible" }
    $window.FindName("ResultSplitter").Visibility = if ($Expanded) { "Collapsed" } else { "Visible" }
    $window.FindName("BtnV3ExpandResult").Content = if ($Expanded) { "Voltar às ações" } else { "Ampliar resultado" }
    if ($Expanded) {
        [void]$script:TxtV3Output.Focus()
    }
}

function Update-V3CompactLayout {
    $surface = $window.FindName("AppSurface")
    $compact = $surface.ActualHeight -lt 660
    $grid = $window.FindName("WorkspaceGrid")
    $margin = if ($compact) { 12 } else { 20 }
    $grid.Margin = [System.Windows.Thickness]::new($margin)
    $grid.MaxHeight = [Math]::Max(0, $surface.ActualHeight - 2 * $margin)
    $window.FindName("WorkspaceDescription").Visibility = if ($compact) { "Collapsed" } else { "Visible" }
    $window.FindName("WorkspaceFooter").Visibility = if ($compact) { "Collapsed" } else { "Visible" }
    $window.FindName("ResultContainer").Padding = [System.Windows.Thickness]::new($(if ($compact) { 12 } else { 16 }))
    $window.FindName("ResultHeader").Margin = [System.Windows.Thickness]::new(0, 0, 0, $(if ($compact) { 6 } else { 10 }))
    $grid.RowDefinitions[2].MinHeight = if ($script:V3ResultExpanded) { 0 } elseif ($compact) { 80 } else { 100 }
    $grid.RowDefinitions[4].MinHeight = if ($compact) { 170 } else { 200 }
    if ($compact -ne $script:V3CompactLayout) {
        if ($compact) {
            $script:V3BeforeCompactActionsHeight = if ($script:V3ResultExpanded) { $script:V3ActionsHeight } else { $grid.RowDefinitions[2].Height }
            $actionsHeight = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        }
        else {
            $actionsHeight = $script:V3BeforeCompactActionsHeight
        }
        if ($script:V3ResultExpanded) {
            $script:V3ActionsHeight = $actionsHeight
        }
        else {
            $grid.RowDefinitions[2].Height = $actionsHeight
        }
        $readingHeight = [System.Windows.GridLength]::new($(if ($compact) { 180 } else { 230 }))
        if ($script:V3ResultExpanded) {
            $script:V3ResultHeight = $readingHeight
        }
        else {
            $grid.RowDefinitions[4].Height = $readingHeight
        }
    }
    $script:V3CompactLayout = $compact
}

function Update-V3ResponsiveLayout {
    $columns = if ($window.FindName("ActionsScroll").ActualWidth -lt 670) { 1 } else { 2 }
    foreach ($key in @("Overview", "Network", "Vpn", "Printers", "Office", "Windows")) {
        foreach ($group in $window.FindName("Topic$key").Children) {
            if ($group -is [System.Windows.Controls.StackPanel] -and $group.Tag -eq "ActionsGroup") {
                foreach ($child in $group.Children) {
                    if ($child -is [System.Windows.Controls.Primitives.UniformGrid]) {
                        $child.Columns = $columns
                    }
                }
            }
        }
    }
    $window.FindName("StationCards").Columns = if ($columns -eq 1) { 2 } else { 4 }
}
$window.FindName("AppSurface").Add_SizeChanged({
    Update-V3CompactLayout
})
$window.FindName("ActionsScroll").Add_SizeChanged({ Update-V3ResponsiveLayout })
$window.FindName("BtnV3ExpandResult").Add_Click({ Set-V3ResultExpanded -Expanded (-not $script:V3ResultExpanded) })
$window.FindName("BtnV3SmallerText").Add_Click({
    $script:TxtV3Output.FontSize = [Math]::Max(11, $script:TxtV3Output.FontSize - 1)
})
$window.FindName("BtnV3LargerText").Add_Click({
    $script:TxtV3Output.FontSize = [Math]::Min(22, $script:TxtV3Output.FontSize + 1)
})

function ConvertTo-V3SearchText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }
    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    return ([regex]::Replace($normalized, '\p{Mn}', '')).Trim().ToLowerInvariant()
}

function Update-V3ActionFilter {
    $query = ConvertTo-V3SearchText -Text $window.FindName("SearchActions").Text
    $window.FindName("SearchHint").Visibility = if ([string]::IsNullOrEmpty($query)) {
        [System.Windows.Visibility]::Visible
    }
    else {
        [System.Windows.Visibility]::Collapsed
    }
    $window.FindName("BtnV3ClearSearch").IsEnabled = -not [string]::IsNullOrEmpty($window.FindName("SearchActions").Text)
    $window.FindName("BtnV3SearchAll").Visibility = if ($script:V3SelectedTopic -eq "All") {
        [System.Windows.Visibility]::Collapsed
    }
    else {
        [System.Windows.Visibility]::Visible
    }
    $tokens = @($query -split '\s+' | Where-Object { $_ })
    $kind = [string]$window.FindName("ActionKind").SelectedItem.Tag
    $total = 0
    foreach ($key in @("Overview", "Network", "Vpn", "Printers", "Office", "Windows")) {
        $section = $window.FindName("Topic$key")
        $inTopic = $script:V3SelectedTopic -eq "All" -or $script:V3SelectedTopic -eq $key
        foreach ($heading in @($section.Children | Where-Object { $_ -is [System.Windows.Controls.TextBlock] })) {
            $heading.Visibility = if ($script:V3SelectedTopic -eq "All") { "Visible" } else { "Collapsed" }
        }
        $sectionMatches = 0
        foreach ($group in @($section.Children | Where-Object {
            $_ -is [System.Windows.Controls.StackPanel] -and $_.Tag -eq "ActionsGroup"
        })) {
            $groupMatches = 0
            foreach ($grid in @($group.Children | Where-Object {
                $_ -is [System.Windows.Controls.Primitives.UniformGrid]
            })) {
                foreach ($button in $grid.Children) {
                    $searchText = ConvertTo-V3SearchText -Text ([string]$button.Tag)
                    $matches = $inTopic -and ($kind -eq "All" -or $kind -eq $group.Uid)
                    foreach ($token in $tokens) {
                        if (-not $searchText.Contains($token)) {
                            $matches = $false
                        }
                    }
                    $button.Visibility = if ($matches) {
                        [System.Windows.Visibility]::Visible
                    }
                    else {
                        [System.Windows.Visibility]::Collapsed
                    }
                    if ($matches) {
                        $groupMatches++
                    }
                }
            }
            $group.Visibility = if ($groupMatches -gt 0) {
                [System.Windows.Visibility]::Visible
            }
            else {
                [System.Windows.Visibility]::Collapsed
            }
            $sectionMatches += $groupMatches
        }
        $section.Visibility = if ($inTopic -and $sectionMatches -gt 0) {
            [System.Windows.Visibility]::Visible
        }
        else {
            [System.Windows.Visibility]::Collapsed
        }
        $total += $sectionMatches
    }
    $window.FindName("NoActions").Text = if ($script:V3SelectedTopic -eq "All") {
        "Nenhuma ação encontrada. Revise o tipo de ação, tente outro nome ou limpe a busca."
    }
    else {
        "Nenhuma ação encontrada neste tema. Revise o tipo de ação, use Buscar em todos ou limpe a busca."
    }
    $window.FindName("NoActions").Visibility = if ($total -eq 0) {
        [System.Windows.Visibility]::Visible
    }
    else {
        [System.Windows.Visibility]::Collapsed
    }
    $window.FindName("BtnV3ResetFilters").Visibility = $window.FindName("NoActions").Visibility
    $window.FindName("ActionCount").Text = if ($total -eq 1) {
        "1 ação disponível"
    }
    elseif ($total -eq 0) {
        "Nenhuma ação disponível"
    }
    else {
        "$total ações disponíveis"
    }
    $window.FindName("ActionsScroll").ScrollToTop()
}

function Set-V3Topic {
    param(
        [ValidateSet("All", "Overview", "Network", "Vpn", "Printers", "Office", "Windows")]
        [string]$Topic = "All"
    )

    $script:V3SelectedTopic = $Topic
    $topicLabel = [string]$window.FindName("Nav$Topic").Content
    $window.FindName("SearchScope").Text = "Buscar ações · $topicLabel"
    $window.FindName("WorkspaceTitle").Text = $topicLabel
    $descriptions = @{
        All = "Explore as ferramentas ou procure uma ação pelo nome."
        Overview = "Comece pelo estado da estação e pelo inventário."
        Network = "Consulte conectividade, DNS e rotas antes de escolher uma correção."
        Vpn = "Verifique a conexão e o cliente Appgate."
        Printers = "Consulte impressoras e filas para identificar a causa da falha."
        Office = "Investigue Office, TPM e autenticação com os diagnósticos disponíveis."
        Windows = "Consulte o sistema e revise as opções de manutenção."
    }
    $window.FindName("WorkspaceDescription").Text = $descriptions[$Topic]
    if ($script:V3ResultExpanded) {
        Set-V3ResultExpanded -Expanded $false
    }
    foreach ($key in @("All", "Overview", "Network", "Vpn", "Printers", "Office", "Windows")) {
        $button = $window.FindName("Nav$key")
        [System.Windows.Automation.AutomationProperties]::SetItemStatus($button, $(if ($key -eq $Topic) { "Tema selecionado" } else { "" }))
        $button.Background = if ($key -eq $Topic) {
            [System.Windows.Media.Brushes]::RoyalBlue
        }
        else {
            [System.Windows.Media.Brushes]::Transparent
        }
    }
    Update-V3ActionFilter
}

foreach ($key in @("All", "Overview", "Network", "Vpn", "Printers", "Office", "Windows")) {
    $window.FindName("Nav$key").Add_Click({
        param($sender, $eventArgs)
        Set-V3Topic -Topic ([string]$sender.Tag)
    })
}
function Reset-V3ActionFilters {
    $window.FindName("SearchActions").Clear()
    $window.FindName("ActionKind").SelectedIndex = 0
    Set-V3Topic -Topic "All"
    [void]$window.FindName("SearchActions").Focus()
}
$window.FindName("BtnV3ResetFilters").Add_Click({ Reset-V3ActionFilters })

function Update-V3SearchResults {
    if ($script:V3ResultExpanded) {
        Set-V3ResultExpanded -Expanded $false
    }
    Update-V3ActionFilter
}
$window.FindName("SearchActions").Add_TextChanged({ Update-V3SearchResults })
$window.FindName("ActionKind").Add_SelectionChanged({ Update-V3SearchResults })
$window.FindName("BtnV3ClearSearch").Add_Click({
    $window.FindName("SearchActions").Clear()
    [void]$window.FindName("SearchActions").Focus()
})
$window.FindName("BtnV3SearchAll").Add_Click({
    Set-V3Topic -Topic "All"
    [void]$window.FindName("SearchActions").Focus()
})
$window.Add_PreviewKeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.Key -eq [System.Windows.Input.Key]::F -and
        [System.Windows.Input.Keyboard]::Modifiers -eq ([System.Windows.Input.ModifierKeys]::Control -bor [System.Windows.Input.ModifierKeys]::Shift)) {
        Set-V3ResultSearchVisible -Visible $true
        $eventArgs.Handled = $true
    }
    elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::F3) {
        if ($window.FindName("ResultSearchPanel").Visibility -ne "Visible") { Set-V3ResultSearchVisible -Visible $true }
        else {
            $direction = if (([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0) { -1 } else { 1 }
            Move-V3ResultMatch -Direction $direction
        }
        $eventArgs.Handled = $true
    }
    elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::F -and
        [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control) {
        [void]$window.FindName("SearchActions").Focus()
        $window.FindName("SearchActions").SelectAll()
        $eventArgs.Handled = $true
    }
    elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::F6) {
        if ($script:TxtV3Output.IsKeyboardFocusWithin) {
            [void]$window.FindName("SearchActions").Focus()
        }
        else {
            [void]$script:TxtV3Output.Focus()
        }
        $eventArgs.Handled = $true
    }
    elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
        if ($window.FindName("ResultSearchPanel").Visibility -eq "Visible" -and
            ($window.FindName("ResultSearchPanel").IsKeyboardFocusWithin -or $script:TxtV3Output.IsKeyboardFocusWithin)) {
            Set-V3ResultSearchVisible -Visible $false
            $eventArgs.Handled = $true
        }
        elseif ($window.FindName("SearchActions").IsKeyboardFocusWithin -and
            -not [string]::IsNullOrEmpty($window.FindName("SearchActions").Text)) {
            $window.FindName("SearchActions").Clear()
            $eventArgs.Handled = $true
        }
        elseif ($script:V3ResultExpanded) {
            Set-V3ResultExpanded -Expanded $false
            [void]$window.FindName("BtnV3ExpandResult").Focus()
            $eventArgs.Handled = $true
        }
    }
})
Set-V3Topic -Topic "Overview"

$script:V3StorageTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:V3StorageTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$script:V3StorageTimer.Add_Tick({ Complete-V3StorageDiagnostic })
$window.FindName("BtnV3Storage").Add_Click({ Start-V3StorageDiagnostic })
$window.FindName("BtnV3CancelStorage").Add_Click({ Stop-V3StorageDiagnostic })
$window.Add_Closed({
    $script:V3StorageTimer.Stop()
    if ($null -ne $script:V3StorageScan) {
        $script:V3StorageScan.Pipeline.Stop()
        $script:V3StorageScan.Pipeline.Dispose()
        $script:V3StorageScan = $null
    }
})

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
    if ([System.Windows.MessageBox]::Show("Sera criado um backup da configuracao do Appgate e aplicado RunScriptTimeout=300000. Deseja continuar?", "Ajustar Appgate", "YesNo", "Warning") -eq "Yes") {
        Set-V3Output (Repair-V3AppgateConfiguration -Confirmed)
    }
})
$window.FindName("BtnV3Health").Add_Click({ Set-V3Output (Invoke-V3MachineHealthPanel) })
$window.FindName("BtnV3Solutions").Add_Click({ Open-V3SolutionCatalog })
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
