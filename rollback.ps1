# ============================================================
# ServiceDesk Toolkit Corporate - Rollback
# Execucao segura: powershell.exe -File rollback.ps1
# Por padrao roda em DRY-RUN e nao altera arquivos.
# Para aplicar: definir SDTK_ROLLBACK_CONFIRM=YES
# ============================================================

$ErrorActionPreference = "Stop"

$InstallPath = "C:\ServiceDeskToolkit"
$BackupsPath = Join-Path $InstallPath "backups"
$LogsPath = Join-Path $InstallPath "logs"

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$RollbackLogPath = Join-Path $LogsPath ("rollback-" + $Timestamp + ".log")

$DryRun = $true
if ($env:SDTK_ROLLBACK_CONFIRM -eq "YES") {
    $DryRun = $false
}

$RequestedBackup = $env:SDTK_ROLLBACK_BACKUP

function Ensure-Folder {
    param([string]$Path)

    if (!(Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

function Write-RollbackLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    try {
        Add-Content -Path $RollbackLogPath -Value $line -Encoding UTF8
    }
    catch {}

    if ($Level -eq "ERROR") {
        Write-Host $Message -ForegroundColor Red
    }
    elseif ($Level -eq "WARN") {
        Write-Host $Message -ForegroundColor Yellow
    }
    elseif ($Level -eq "OK") {
        Write-Host $Message -ForegroundColor Green
    }
    else {
        Write-Host $Message -ForegroundColor Cyan
    }
}

function Test-PowerShellSyntax {
    param(
        [string]$Path,
        [string]$Name
    )

    $errors = $null
    $text = Get-Content $Path -Raw
    $null = [System.Management.Automation.PSParser]::Tokenize($text, [ref]$errors)

    if ($errors.Count -eq 0) {
        Write-RollbackLog "OK - $Name sem erro de sintaxe." "OK"
        return
    }

    foreach ($err in $errors) {
        Write-RollbackLog "Erro de sintaxe em $Name - Linha $($err.Token.StartLine): $($err.Message)" "ERROR"
    }

    throw "$Name possui erro de sintaxe no backup."
}

function Get-SelectedBackupRoot {
    if ($RequestedBackup -and $RequestedBackup.Trim().Length -gt 0) {
        if (!(Test-Path $RequestedBackup)) {
            throw "Backup solicitado nao encontrado: $RequestedBackup"
        }

        $item = Get-Item $RequestedBackup

        if ($item.Name -eq "current") {
            return $item.Parent.FullName
        }

        return $item.FullName
    }

    $latest = Get-ChildItem $BackupsPath -Directory -ErrorAction Stop |
        Where-Object { $_.Name -like "update-*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $latest) {
        throw "Nenhum backup update-* encontrado em: $BackupsPath"
    }

    return $latest.FullName
}

function Restore-BackupFile {
    param(
        [string]$SourcePath,
        [string]$BackupCurrentPath
    )

    $relativePath = $SourcePath.Substring($BackupCurrentPath.Length).TrimStart("\")
    $destinationPath = Join-Path $InstallPath $relativePath
    $destinationFolder = Split-Path $destinationPath -Parent

    if ($DryRun) {
        Write-RollbackLog "[DRY-RUN] Restauraria: $relativePath"
        return
    }

    Ensure-Folder $destinationFolder
    Copy-Item $SourcePath $destinationPath -Force

    Write-RollbackLog "Restaurado: $relativePath" "OK"
}

try {
    Ensure-Folder $LogsPath

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " ServiceDesk Toolkit Corporate - Rollback" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-RollbackLog "Rollback iniciado."
    Write-RollbackLog "InstallPath: $InstallPath"
    Write-RollbackLog "BackupsPath: $BackupsPath"

    if ($DryRun) {
        Write-RollbackLog "Modo: DRY-RUN. Nenhum arquivo sera alterado." "WARN"
    }
    else {
        Write-RollbackLog "Modo: APLICACAO REAL. Arquivos serao restaurados." "WARN"
    }

    if (!(Test-Path $BackupsPath)) {
        throw "Pasta de backups nao encontrada: $BackupsPath"
    }

    $backupRoot = Get-SelectedBackupRoot
    $backupCurrent = Join-Path $backupRoot "current"

    if (!(Test-Path $backupCurrent)) {
        throw "Pasta current nao encontrada no backup: $backupCurrent"
    }

    Write-RollbackLog "Backup selecionado: $backupRoot"
    Write-RollbackLog "Origem da restauracao: $backupCurrent"

    $files = Get-ChildItem $backupCurrent -File -Recurse

    if ($files.Count -eq 0) {
        throw "Backup vazio. Nenhum arquivo para restaurar."
    }

    Write-RollbackLog "Validando scripts PowerShell no backup..."

    $psFiles = $files | Where-Object { $_.Extension -eq ".ps1" }

    foreach ($psFile in $psFiles) {
        Test-PowerShellSyntax -Path $psFile.FullName -Name $psFile.Name
    }

    Write-RollbackLog "Arquivos encontrados no backup: $($files.Count)"

    foreach ($file in $files) {
        Restore-BackupFile -SourcePath $file.FullName -BackupCurrentPath $backupCurrent
    }

    if ($DryRun) {
        Write-RollbackLog "Dry-run concluido com sucesso. Nenhum arquivo foi alterado." "OK"
        Write-Host ""
        Write-Host "Para aplicar rollback real, rode:" -ForegroundColor Yellow
        Write-Host '$env:SDTK_ROLLBACK_CONFIRM = "YES"' -ForegroundColor Yellow
        Write-Host 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\ServiceDeskToolkit\rollback.ps1"' -ForegroundColor Yellow
        Write-Host 'Remove-Item Env:\SDTK_ROLLBACK_CONFIRM' -ForegroundColor Yellow
        Write-Host ""
    }
    else {
        Write-RollbackLog "Rollback aplicado com sucesso." "OK"
    }

    Write-Host "Log:" -ForegroundColor Cyan
    Write-Host $RollbackLogPath -ForegroundColor Cyan
}
catch {
    Write-RollbackLog "Rollback falhou: $($_.Exception.Message)" "ERROR"

    Write-Host ""
    Write-Host "ROLLBACK FALHOU." -ForegroundColor Red
    Write-Host "Log:" -ForegroundColor Cyan
    Write-Host $RollbackLogPath -ForegroundColor Cyan
    Write-Host ""

    throw
}