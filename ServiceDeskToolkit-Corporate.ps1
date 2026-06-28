Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$Root='C:\ServiceDeskToolkit'
$Reports=Join-Path $Root 'reports'
$Logs=Join-Path $Root 'logs'
$Backups=Join-Path $Root 'backup-appgate'
foreach($p in @($Root,$Reports,$Logs,$Backups)){ if(!(Test-Path $p)){ New-Item -Path $p -ItemType Directory -Force | Out-Null } }

function Test-Admin { try { $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent()); return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) } catch { return $false } }
function New-ReportName($Prefix,$Ext){ Join-Path $Reports ("$Prefix-$env:COMPUTERNAME-$(Get-Date -Format yyyy-MM-dd_HH-mm-ss).$Ext") }
function OutText($t){ if($script:TxtOutput){ $script:TxtOutput.Text=$t } }

function Get-InventoryObj {
  try{
    $cs=Get-CimInstance Win32_ComputerSystem; $bios=Get-CimInstance Win32_BIOS; $os=Get-CimInstance Win32_OperatingSystem; $cpu=Get-CimInstance Win32_Processor|Select-Object -First 1; $d=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"; $net=Get-NetIPConfiguration|Where-Object IPv4Address|Select-Object -First 1; $up=(Get-Date)-$os.LastBootUpTime
    [pscustomobject]@{Hostname=$env:COMPUTERNAME;Usuario="$env:USERDOMAIN\$env:USERNAME";Dominio=$cs.Domain;Fabricante=$cs.Manufacturer;Modelo=$cs.Model;Serial=$bios.SerialNumber;Processador=$cpu.Name;RAM=([math]::Round($cs.TotalPhysicalMemory/1GB,2).ToString()+" GB");Windows=$os.Caption;Versao=$os.Version;Build=$os.BuildNumber;Arquitetura=$os.OSArchitecture;DiscoC="$([math]::Round($d.FreeSpace/1GB,2)) GB livres de $([math]::Round($d.Size/1GB,2)) GB";IP=($net.IPv4Address.IPAddress -join ', ');Gateway=($net.IPv4DefaultGateway.NextHop -join ', ');DNS=($net.DNSServer.ServerAddresses -join ', ');Uptime="$($up.Days)d $($up.Hours)h $($up.Minutes)m"}
  }catch{"Erro ao coletar inventário: $($_.Exception.Message)"}
}
function Get-InventoryText { $i=Get-InventoryObj; if($i -is [string]){return $i}; return ($i|Format-List|Out-String) }
function Test-NetworkBasic { try{ $o=@(); $o+='Diagnóstico de rede'; $o+=''; $o+='Ping 8.8.8.8: '+$(if(Test-Connection 8.8.8.8 -Count 2 -Quiet -ErrorAction SilentlyContinue){'OK'}else{'Falha'}); $o+='Ping google.com: '+$(if(Test-Connection google.com -Count 2 -Quiet -ErrorAction SilentlyContinue){'OK'}else{'Falha'}); try{Resolve-DnsName google.com -ErrorAction Stop|Out-Null;$o+='DNS: OK'}catch{$o+='DNS: Falha'}; $o+=''; $o+='Adaptadores ativos:'; $o+=(Get-NetAdapter|Where Status -eq Up|Select Name,InterfaceDescription,MacAddress,LinkSpeed,Status|Format-Table -AutoSize|Out-String); $o -join "`n" }catch{"Erro na rede: $($_.Exception.Message)"} }
function Invoke-FlushDns { try{ipconfig /flushdns|Out-Null;'Cache DNS limpo com sucesso.'}catch{"Erro: $($_.Exception.Message)"} }
function Invoke-RenewIp { try{ipconfig /release|Out-Null;Start-Sleep 2;ipconfig /renew|Out-Null;'IP renovado. Verifique a conexão.'}catch{"Erro: $($_.Exception.Message)"} }
function Invoke-TimeSync { try{Start-Service w32time -ErrorAction SilentlyContinue; w32tm /resync 2>&1|Out-String}catch{"Erro: $($_.Exception.Message)"} }
function Invoke-SpoolerRestart { try{Restart-Service Spooler -Force;'Spooler reiniciado.'}catch{"Erro: $($_.Exception.Message)"} }
function Get-TpmBasic { try{ if(Get-Command Get-Tpm -ErrorAction SilentlyContinue){Get-Tpm|Format-List|Out-String}else{'Get-Tpm indisponível.'}}catch{"Erro TPM: $($_.Exception.Message)"} }
function Get-BitlockerBasic { try{manage-bde -status 2>&1|Out-String}catch{"Erro BitLocker: $($_.Exception.Message)"} }
function Get-DefenderBasic { try{ if(Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue){Get-MpComputerStatus|Select AMServiceEnabled,AntivirusEnabled,RealTimeProtectionEnabled,AntivirusSignatureLastUpdated|Format-List|Out-String}else{'Get-MpComputerStatus indisponível.'}}catch{"Erro Defender: $($_.Exception.Message)"} }
function Get-UacBasic { try{Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'|Select EnableLUA,ConsentPromptBehaviorAdmin,PromptOnSecureDesktop|Format-List|Out-String}catch{"Erro UAC: $($_.Exception.Message)"} }
function Get-AdminsBasic { try{Get-LocalGroupMember -Group Administradores|Select Name,ObjectClass,PrincipalSource|Format-Table -AutoSize|Out-String}catch{net localgroup Administradores 2>&1|Out-String} }
function Get-StoppedAutoServices { try{Get-CimInstance Win32_Service|Where {$_.StartMode -eq 'Auto' -and $_.State -ne 'Running'}|Select Name,DisplayName,State|Sort DisplayName|Format-Table -AutoSize|Out-String}catch{"Erro: $($_.Exception.Message)"} }
function Get-CriticalEvents { try{$e=Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=(Get-Date).AddHours(-24)} -MaxEvents 30 -ErrorAction SilentlyContinue|Select TimeCreated,ProviderName,Id,LevelDisplayName,Message; if($e){$e|Format-List|Out-String}else{'Nenhum evento crítico/erro nas últimas 24h.'}}catch{"Erro eventos: $($_.Exception.Message)"} }
function Invoke-GpUpdate { try{gpupdate /force 2>&1|Out-String}catch{"Erro: $($_.Exception.Message)"} }
function Invoke-GpResult { try{$f=New-ReportName 'GPResult' 'html'; gpresult /h $f /f 2>&1|Out-Null; Start-Process $f; "GPResult gerado:`n$f"}catch{"Erro: $($_.Exception.Message)"} }
function Test-TcpPort($hostName,[int]$port){ try{Test-NetConnection -ComputerName $hostName -Port $port -InformationLevel Detailed|Format-List|Out-String}catch{"Erro TCP: $($_.Exception.Message)"} }
function Export-ReportTxt { try{$f=New-ReportName 'RelatorioCompleto' 'txt'; @("INVENTÃRIO",(Get-InventoryText),"REDE",(Test-NetworkBasic),"TPM",(Get-TpmBasic),"BITLOCKER",(Get-BitlockerBasic),"DEFENDER",(Get-DefenderBasic),"UAC",(Get-UacBasic),"ADMINS",(Get-AdminsBasic),"EVENTOS",(Get-CriticalEvents)) -join "`n`n"|Out-File $f -Encoding UTF8; "Relatório TXT gerado:`n$f"}catch{"Erro: $($_.Exception.Message)"} }
function Export-ReportHtml { try{$f=New-ReportName 'RelatorioCompleto' 'html'; $inv=Get-InventoryText; $net=Test-NetworkBasic; $html="<html><head><meta charset='utf-8'><title>ServiceDesk Toolkit</title><style>body{font-family:Segoe UI,Arial;background:#f5f7fa;padding:30px}.hero{background:#1849A9;color:white;padding:24px;border-radius:16px}pre{background:white;padding:16px;border-radius:12px;white-space:pre-wrap}</style></head><body><div class='hero'><h1>ServiceDesk Toolkit</h1><p>Relatório $env:COMPUTERNAME - $(Get-Date)</p></div><h2>Inventário</h2><pre>$([System.Net.WebUtility]::HtmlEncode($inv))</pre><h2>Rede</h2><pre>$([System.Net.WebUtility]::HtmlEncode($net))</pre></body></html>"; $html|Out-File $f -Encoding UTF8; Start-Process $f; "Relatório HTML gerado:`n$f"}catch{"Erro: $($_.Exception.Message)"} }

# VPN / Appgate
function Invoke-AppgateFix { try{ if(!(Test-Admin)){return 'ERRO: execute como administrador.'}; $cfg='C:\Program Files\Appgate SDP\Service\Appgate SDP Service.dll.config'; if(!(Test-Path $cfg)){return "Arquivo não encontrado:`n$cfg"}; $b=Join-Path $Backups ("Appgate SDP Service.dll.config.backup-$(Get-Date -Format yyyy-MM-dd_HH-mm-ss)"); Copy-Item $cfg $b -Force; $xml=New-Object System.Xml.XmlDocument; $xml.PreserveWhitespace=$true; $xml.Load($cfg); $n=$xml.SelectSingleNode("//applicationSettings/Cryptzone.Stratus.WindowsClient.Properties.Application/setting[@name='RunScriptTimeout']/value"); if(!$n){return "RunScriptTimeout não encontrado. Backup: $b"}; $old=$n.InnerText; $n.InnerText='300000'; $xml.Save($cfg); Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name ConsentPromptBehaviorAdmin -Value 5 -Type DWord; "Correção Appgate concluída.`nRunScriptTimeout: $old -> 300000`nUAC ConsentPromptBehaviorAdmin = 5`nBackup: $b" }catch{"ERRO Appgate: $($_.Exception.Message)"} }
function Restart-Appgate { try{ if(!(Test-Admin)){return 'ERRO: execute como administrador.'}; $o=New-Object Text.StringBuilder; foreach($p in 'Appgate SDP Service','appgate-driver'){ $ps=Get-Process -Name $p -ErrorAction SilentlyContinue; if($ps){$ps|%{[void]$o.AppendLine("Finalizando $($_.ProcessName) PID $($_.Id)"); Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue}}else{[void]$o.AppendLine("Processo não encontrado: $p")}}; Start-Sleep 3; foreach($s in 'appgatedriver','AppgateUpdateService'){ if(Get-Service $s -ErrorAction SilentlyContinue){[void]$o.AppendLine("Reiniciando serviço: $s"); Restart-Service $s -Force -ErrorAction SilentlyContinue; Start-Sleep 2}}; $exe='C:\Program Files\Appgate SDP\service\Appgate SDP Service.exe'; if(Test-Path $exe){Start-Process $exe; [void]$o.AppendLine("Iniciado: $exe")}; [void]$o.AppendLine('Concluído.'); $o.ToString()}catch{"ERRO ao reiniciar Appgate: $($_.Exception.Message)"} }
function Get-AppgateStatus { try{ $o=New-Object Text.StringBuilder; $cfg='C:\Program Files\Appgate SDP\Service\Appgate SDP Service.dll.config'; [void]$o.AppendLine('Status VPN / Appgate'); [void]$o.AppendLine(''); if(Test-Path $cfg){[void]$o.AppendLine("Config OK: $cfg"); try{$xml=New-Object Xml.XmlDocument; $xml.Load($cfg); $n=$xml.SelectSingleNode("//applicationSettings/Cryptzone.Stratus.WindowsClient.Properties.Application/setting[@name='RunScriptTimeout']/value"); [void]$o.AppendLine("RunScriptTimeout: $($n.InnerText)")}catch{[void]$o.AppendLine("Erro XML: $($_.Exception.Message)")}}else{[void]$o.AppendLine("Config não encontrado: $cfg")}; $u=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System').ConsentPromptBehaviorAdmin; [void]$o.AppendLine("UAC ConsentPromptBehaviorAdmin: $u"); [void]$o.AppendLine(''); [void]$o.AppendLine('Serviços:'); [void]$o.AppendLine((Get-Service|Where {$_.Name -eq 'appgatedriver' -or $_.Name -eq 'AppgateUpdateService' -or $_.DisplayName -like '*Appgate*'}|Select Name,DisplayName,Status|Format-Table -AutoSize|Out-String)); [void]$o.AppendLine('Processos:'); [void]$o.AppendLine((Get-Process|Where {$_.ProcessName -like '*appgate*' -or $_.ProcessName -like '*sdp*'}|Select ProcessName,Id,Path|Format-Table -AutoSize|Out-String)); $o.ToString() }catch{"ERRO status Appgate: $($_.Exception.Message)"} }

# TPM / Office
function Invoke-TpmOfficeFix { try{ if(!(Test-Admin)){return 'ERRO: execute como administrador.'}; $p='HKLM:\Software\Microsoft\Cryptography\Protect\Providers\df9d8cd0-1501-11d1-8c7a-00c04fc297eb'; $o='HKCU:\Software\Microsoft\Office\16.0\Common\Identity'; if(!(Test-Path $p)){New-Item $p -Force|Out-Null}; New-ItemProperty -Path $p -Name ProtectionPolicy -Value 1 -PropertyType DWord -Force|Out-Null; if(!(Test-Path $o)){New-Item $o -Force|Out-Null}; New-ItemProperty -Path $o -Name EnableADAL -Value 0 -PropertyType DWord -Force|Out-Null; "Ajuste TPM 2 aplicado.`nProtectionPolicy=1`nEnableADAL=0`nReinicie o computador."}catch{"ERRO TPM 2: $($_.Exception.Message)"} }
function Invoke-BrokenPluginFix { try{ if(!(Test-Admin)){return 'ERRO: execute como administrador.'}; $paths=@("$env:LOCALAPPDATA\ConnectedDevicesPlatform\BrokenPlugin",'C:\Users\suporte\AppData\Local\ConnectedDevicesPlatform\BrokenPlugin','C:\Users\Suporte\AppData\Local\ConnectedDevicesPlatform\BrokenPlugin')|Select-Object -Unique; $o=@(); foreach($p in $paths){ if(Test-Path $p){Remove-Item $p -Recurse -Force; $o+="Removido: $p"}else{$o+="Não encontrado: $p"}}; ($o -join "`n")+"`nReinicie o computador."}catch{"ERRO BrokenPlugin: $($_.Exception.Message)"} }
function Start-DismSfc { try{ if(!(Test-Admin)){return 'ERRO: execute como administrador.'}; $d=Get-Date -Format yyyy-MM-dd_HH-mm-ss; $sp=Join-Path $Logs "Executar-DISM-SFC-$d.ps1"; $lp=Join-Path $Logs "DISM-SFC-$d.log"; "Dism /Online /Cleanup-Image /RestoreHealth 2>&1 | Tee-Object -FilePath '$lp' -Append`nsfc /scannow 2>&1 | Tee-Object -FilePath '$lp' -Append`nPause"|Set-Content $sp -Encoding UTF8; Start-Process pwsh.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$sp`"" -Verb RunAs; "DISM + SFC iniciado.`nLog: $lp"}catch{"ERRO DISM/SFC: $($_.Exception.Message)"} }
function Get-TpmOfficeStatus { try{ $o=New-Object Text.StringBuilder; [void]$o.AppendLine('Status TPM / Office'); [void]$o.AppendLine(''); [void]$o.AppendLine((Get-TpmBasic)); $p='HKLM:\Software\Microsoft\Cryptography\Protect\Providers\df9d8cd0-1501-11d1-8c7a-00c04fc297eb'; $id='HKCU:\Software\Microsoft\Office\16.0\Common\Identity'; if(Test-Path $p){try{[void]$o.AppendLine("ProtectionPolicy: $((Get-ItemProperty $p).ProtectionPolicy)")}catch{[void]$o.AppendLine('ProtectionPolicy não encontrado')}}else{[void]$o.AppendLine('Chave ProtectionPolicy não encontrada')}; if(Test-Path $id){try{[void]$o.AppendLine("EnableADAL: $((Get-ItemProperty $id).EnableADAL)")}catch{[void]$o.AppendLine('EnableADAL não encontrado')}}else{[void]$o.AppendLine('Chave Office Identity não encontrada')}; $o.ToString()}catch{"ERRO status TPM/Office: $($_.Exception.Message)"} }

# Windows / Reparo
function Get-WindowsRepairStatus { try{ $os=Get-CimInstance Win32_OperatingSystem; $d=Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"; $o=@(); $o+='Status Windows / Reparo'; $o+=''; $o+="Windows: $($os.Caption) $($os.Version) Build $($os.BuildNumber)"; $o+="Disco C: $([math]::Round($d.FreeSpace/1GB,2)) GB livres de $([math]::Round($d.Size/1GB,2)) GB"; $o+=''; $o+='Serviços WU:'; $o+=(Get-Service wuauserv,bits,cryptsvc,msiserver -ErrorAction SilentlyContinue|Select Name,DisplayName,Status|Format-Table -AutoSize|Out-String); $o+='Eventos 24h:'; $o+=(Get-CriticalEvents); $o -join "`n"}catch{"ERRO status Windows: $($_.Exception.Message)"} }
function Restart-WUServices { try{ if(!(Test-Admin)){return 'ERRO: execute como administrador.'}; $o=@(); foreach($s in 'wuauserv','bits','cryptsvc','msiserver'){ if(Get-Service $s -ErrorAction SilentlyContinue){Restart-Service $s -Force -ErrorAction SilentlyContinue; $o+="Reiniciado: $s"}else{$o+="Não encontrado: $s"}}; $o -join "`n"}catch{"ERRO WU: $($_.Exception.Message)"} }
function Clear-WUCache { try{ if(!(Test-Admin)){return 'ERRO: execute como administrador.'}; foreach($s in 'wuauserv','bits','cryptsvc'){Stop-Service $s -Force -ErrorAction SilentlyContinue}; Start-Sleep 2; $d=Get-Date -Format yyyy-MM-dd_HH-mm-ss; if(Test-Path 'C:\Windows\SoftwareDistribution'){Rename-Item 'C:\Windows\SoftwareDistribution' "SoftwareDistribution.old-$d" -Force}; if(Test-Path 'C:\Windows\System32\catroot2'){Rename-Item 'C:\Windows\System32\catroot2' "catroot2.old-$d" -Force}; foreach($s in 'wuauserv','bits','cryptsvc'){Start-Service $s -ErrorAction SilentlyContinue}; 'Cache Windows Update limpo. Teste o Windows Update novamente.'}catch{"ERRO cache WU: $($_.Exception.Message)"} }
function Clear-UserTemp { try{$c=0; foreach($p in @($env:TEMP,"$env:LOCALAPPDATA\Temp")|Select -Unique){if(Test-Path $p){Get-ChildItem $p -Force -ErrorAction SilentlyContinue|%{Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue;$c++}}}; "Temporários processados: $c"}catch{"ERRO temp: $($_.Exception.Message)"} }
function Start-DismOnly { try{ if(!(Test-Admin)){return 'ERRO: execute como administrador.'}; $d=Get-Date -Format yyyy-MM-dd_HH-mm-ss; $sp=Join-Path $Logs "Executar-DISM-$d.ps1"; $lp=Join-Path $Logs "DISM-$d.log"; "Dism /Online /Cleanup-Image /RestoreHealth 2>&1 | Tee-Object -FilePath '$lp' -Append`nPause"|Set-Content $sp -Encoding UTF8; Start-Process pwsh.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$sp`"" -Verb RunAs; "DISM iniciado.`nLog: $lp"}catch{"ERRO DISM: $($_.Exception.Message)"} }
function Start-SfcOnly { try{ if(!(Test-Admin)){return 'ERRO: execute como administrador.'}; $d=Get-Date -Format yyyy-MM-dd_HH-mm-ss; $sp=Join-Path $Logs "Executar-SFC-$d.ps1"; $lp=Join-Path $Logs "SFC-$d.log"; "sfc /scannow 2>&1 | Tee-Object -FilePath '$lp' -Append`nPause"|Set-Content $sp -Encoding UTF8; Start-Process pwsh.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$sp`"" -Verb RunAs; "SFC iniciado.`nLog: $lp"}catch{"ERRO SFC: $($_.Exception.Message)"} }


# ============================================================
# Impressoras - Funções
# ============================================================

function Get-ToolkitPrinterStatus {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Status de Impressoras")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        $spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue

        [void]$o.AppendLine("Spooler:")
        if ($spooler) {
            [void]$o.AppendLine("Serviço: $($spooler.DisplayName)")
            [void]$o.AppendLine("Status: $($spooler.Status)")
        }
        else {
            [void]$o.AppendLine("Serviço Spooler não encontrado.")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Impressoras instaladas:")

        try {
            $printers = Get-Printer -ErrorAction Stop |
                Select-Object Name, DriverName, PortName, PrinterStatus, Shared, Default

            if ($printers) {
                [void]$o.AppendLine(($printers | Format-Table -AutoSize | Out-String))
            }
            else {
                [void]$o.AppendLine("Nenhuma impressora encontrada.")
            }
        }
        catch {
            [void]$o.AppendLine("Erro ao listar impressoras: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Fila de impressão:")

        try {
            $jobs = Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
                Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue
            } | Select-Object PrinterName, ID, DocumentName, JobStatus, Submitter, Size, TimeSubmitted

            if ($jobs) {
                [void]$o.AppendLine(($jobs | Format-Table -AutoSize | Out-String))
            }
            else {
                [void]$o.AppendLine("Nenhum trabalho na fila de impressão.")
            }
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar fila: $($_.Exception.Message)")
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao consultar status de impressoras:`n$($_.Exception.Message)"
    }
}

function Get-ToolkitPrinterList {
    try {
        $printers = Get-Printer -ErrorAction Stop |
            Sort-Object Name |
            Select-Object Name, DriverName, PortName, PrinterStatus, Shared, Default

        if ($printers) {
            return "Lista de Impressoras Instaladas`n======================================`n`n" + ($printers | Format-Table -AutoSize | Out-String)
        }
        else {
            return "Nenhuma impressora encontrada."
        }
    }
    catch {
        return "ERRO ao listar impressoras:`n$($_.Exception.Message)"
    }
}

function Get-ToolkitPrintJobs {
    try {
        $jobs = Get-Printer -ErrorAction SilentlyContinue | ForEach-Object {
            Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue
        } | Select-Object PrinterName, ID, DocumentName, JobStatus, Submitter, Size, TimeSubmitted

        if ($jobs) {
            return "Fila de Impressão`n======================================`n`n" + ($jobs | Format-Table -AutoSize | Out-String)
        }
        else {
            return "Nenhum trabalho na fila de impressão."
        }
    }
    catch {
        return "ERRO ao consultar fila de impressão:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitRestartSpoolerAdvanced {
    try {
        if (!(Test-Admin)) {
            return "ERRO: execute a ferramenta como administrador para reiniciar o Spooler."
        }

        Restart-Service -Name Spooler -Force -ErrorAction Stop
        Start-Sleep -Seconds 2

        $spooler = Get-Service -Name Spooler

        return "Spooler reiniciado com sucesso.`nStatus atual: $($spooler.Status)"
    }
    catch {
        return "ERRO ao reiniciar Spooler:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitClearPrintQueue {
    try {
        if (!(Test-Admin)) {
            return "ERRO: execute a ferramenta como administrador para limpar a fila de impressão."
        }

        $spoolPath = "C:\Windows\System32\spool\PRINTERS"
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Limpeza da Fila de Impressão")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        [void]$o.AppendLine("Parando Spooler...")
        Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        $count = 0

        if (Test-Path $spoolPath) {
            Get-ChildItem -Path $spoolPath -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                    $count++
                }
                catch {}
            }

            [void]$o.AppendLine("Arquivos removidos da fila: $count")
        }
        else {
            [void]$o.AppendLine("Pasta da fila não encontrada: $spoolPath")
        }

        [void]$o.AppendLine("Iniciando Spooler...")
        Start-Service -Name Spooler -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        $spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue

        if ($spooler) {
            [void]$o.AppendLine("Status atual do Spooler: $($spooler.Status)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Limpeza da fila concluída.")

        return $o.ToString()
    }
    catch {
        return "ERRO ao limpar fila de impressão:`n$($_.Exception.Message)"
    }
}

function Get-ToolkitDefaultPrinter {
    try {
        $default = Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop |
            Where-Object { $_.Default -eq $true } |
            Select-Object Name, DriverName, PortName, Default, WorkOffline

        if ($default) {
            return "Impressora Padrão`n======================================`n`n" + ($default | Format-List | Out-String)
        }
        else {
            return "Nenhuma impressora padrão encontrada."
        }
    }
    catch {
        return "ERRO ao consultar impressora padrão:`n$($_.Exception.Message)"
    }
}

function Get-ToolkitOfflinePrinters {
    try {
        $offline = Get-CimInstance -ClassName Win32_Printer -ErrorAction Stop |
            Where-Object { $_.WorkOffline -eq $true } |
            Select-Object Name, DriverName, PortName, WorkOffline, Default

        if ($offline) {
            return "Impressoras Offline`n======================================`n`n" + ($offline | Format-Table -AutoSize | Out-String)
        }
        else {
            return "Nenhuma impressora marcada como offline."
        }
    }
    catch {
        return "ERRO ao consultar impressoras offline:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenPrintersSettings {
    try {
        Start-Process "ms-settings:printers"
        return "Tela Impressoras e Scanners aberta."
    }
    catch {
        return "ERRO ao abrir Impressoras e Scanners:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenPrintManagement {
    try {
        Start-Process "printmanagement.msc"
        return "Gerenciamento de Impressão aberto."
    }
    catch {
        return "ERRO ao abrir Gerenciamento de Impressão:`n$($_.Exception.Message)`nObservação: em algumas edições do Windows, o printmanagement.msc pode não estar disponível."
    }
}


# ============================================================
# Teams / Office - Funções
# ============================================================

function Get-ToolkitTeamsOfficeStatus {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Status Teams / Office")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        [void]$o.AppendLine("Usuário atual:")
        [void]$o.AppendLine("$env:USERDOMAIN\$env:USERNAME")
        [void]$o.AppendLine("")

        [void]$o.AppendLine("Processos Teams / Office em execução:")
        $processes = Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessName -like "*teams*" -or
                $_.ProcessName -like "outlook" -or
                $_.ProcessName -like "winword" -or
                $_.ProcessName -like "excel" -or
                $_.ProcessName -like "powerpnt" -or
                $_.ProcessName -like "onenote" -or
                $_.ProcessName -like "msedgewebview2"
            } |
            Select-Object ProcessName, Id, Path

        if ($processes) {
            [void]$o.AppendLine(($processes | Format-Table -AutoSize | Out-String))
        }
        else {
            [void]$o.AppendLine("Nenhum processo Teams/Office encontrado.")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Instalações encontradas:")

        $paths = @(
            "$env:LOCALAPPDATA\Microsoft\Teams",
            "$env:LOCALAPPDATA\Microsoft\TeamsMeetingAddin",
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\ms-teams.exe",
            "$env:ProgramFiles\WindowsApps",
            "$env:ProgramFiles\Microsoft Office",
            "${env:ProgramFiles(x86)}\Microsoft Office"
        ) | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -Unique

        foreach ($path in $paths) {
            if (Test-Path $path) {
                [void]$o.AppendLine("OK: $path")
            }
            else {
                [void]$o.AppendLine("Não encontrado: $path")
            }
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Chaves Office Identity:")

        $identityPaths = @(
            "HKCU:\Software\Microsoft\Office\16.0\Common\Identity",
            "HKCU:\Software\Microsoft\Office\15.0\Common\Identity"
        )

        foreach ($reg in $identityPaths) {
            if (Test-Path $reg) {
                [void]$o.AppendLine("OK: $reg")

                try {
                    $props = Get-ItemProperty -Path $reg
                    [void]$o.AppendLine(($props | Select-Object EnableADAL, DisableADALatopWAMOverride, DisableAADWAM | Format-List | Out-String))
                }
                catch {
                    [void]$o.AppendLine("Erro ao ler propriedades: $($_.Exception.Message)")
                }
            }
            else {
                [void]$o.AppendLine("Não encontrado: $reg")
            }
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Credenciais relacionadas no Credential Manager:")
        try {
            $cmdkey = cmdkey /list 2>&1 | Out-String
            $filtered = ($cmdkey -split "`r?`n") | Where-Object {
                $_ -match "Microsoft|Office|Teams|ADAL|OneDrive|Outlook"
            }

            if ($filtered) {
                [void]$o.AppendLine(($filtered -join "`n"))
            }
            else {
                [void]$o.AppendLine("Nenhuma entrada relacionada encontrada pelo filtro.")
            }
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar cmdkey: $($_.Exception.Message)")
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao consultar status Teams / Office:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitCloseTeamsOffice {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Fechamento de Teams / Office")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        $processNames = @(
            "Teams",
            "ms-teams",
            "MSTeams",
            "Update",
            "Outlook",
            "WINWORD",
            "EXCEL",
            "POWERPNT",
            "ONENOTE",
            "MSACCESS",
            "MSPUB",
            "lync",
            "OneDrive"
        )

        foreach ($name in $processNames) {
            $items = Get-Process -Name $name -ErrorAction SilentlyContinue

            if ($items) {
                foreach ($p in $items) {
                    try {
                        [void]$o.AppendLine("Finalizando: $($p.ProcessName) - PID $($p.Id)")
                        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                    }
                    catch {
                        [void]$o.AppendLine("Falha ao finalizar $($p.ProcessName): $($_.Exception.Message)")
                    }
                }
            }
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Processos solicitados foram finalizados.")
        return $o.ToString()
    }
    catch {
        return "ERRO ao fechar Teams / Office:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitClearClassicTeamsCache {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Limpeza de cache - Teams clássico")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        [void]$o.AppendLine("Fechando Teams...")
        Get-Process -Name "Teams" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        $paths = @(
            "$env:APPDATA\Microsoft\Teams\application cache\cache",
            "$env:APPDATA\Microsoft\Teams\blob_storage",
            "$env:APPDATA\Microsoft\Teams\Cache",
            "$env:APPDATA\Microsoft\Teams\databases",
            "$env:APPDATA\Microsoft\Teams\GPUCache",
            "$env:APPDATA\Microsoft\Teams\IndexedDB",
            "$env:APPDATA\Microsoft\Teams\Local Storage",
            "$env:APPDATA\Microsoft\Teams\tmp"
        )

        $count = 0

        foreach ($path in $paths) {
            [void]$o.AppendLine("Verificando: $path")

            if (Test-Path $path) {
                try {
                    Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        $count++
                    }

                    [void]$o.AppendLine("Limpo.")
                }
                catch {
                    [void]$o.AppendLine("Falha ao limpar: $($_.Exception.Message)")
                }
            }
            else {
                [void]$o.AppendLine("Não encontrado.")
            }

            [void]$o.AppendLine("")
        }

        [void]$o.AppendLine("Limpeza concluída. Itens processados: $count")
        return $o.ToString()
    }
    catch {
        return "ERRO ao limpar cache do Teams clássico:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitClearNewTeamsCache {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Limpeza de cache - Novo Teams")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        [void]$o.AppendLine("Fechando Novo Teams...")
        Get-Process -Name "ms-teams" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Get-Process -Name "MSTeams" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        $paths = @(
            "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache",
            "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\TempState",
            "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\AC"
        )

        $count = 0

        foreach ($path in $paths) {
            [void]$o.AppendLine("Verificando: $path")

            if (Test-Path $path) {
                try {
                    Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                        $count++
                    }

                    [void]$o.AppendLine("Limpo.")
                }
                catch {
                    [void]$o.AppendLine("Falha ao limpar: $($_.Exception.Message)")
                }
            }
            else {
                [void]$o.AppendLine("Não encontrado.")
            }

            [void]$o.AppendLine("")
        }

        [void]$o.AppendLine("Limpeza concluída. Itens processados: $count")
        return $o.ToString()
    }
    catch {
        return "ERRO ao limpar cache do Novo Teams:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenTeamsFolder {
    try {
        $paths = @(
            "$env:APPDATA\Microsoft\Teams",
            "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe"
        )

        foreach ($path in $paths) {
            if (Test-Path $path) {
                Start-Process explorer.exe $path
                return "Pasta aberta:`n$path"
            }
        }

        return "Nenhuma pasta local do Teams foi encontrada para o usuário atual."
    }
    catch {
        return "ERRO ao abrir pasta do Teams:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenCredentialManager {
    try {
        Start-Process "control.exe" "/name Microsoft.CredentialManager"
        return "Gerenciador de Credenciais aberto."
    }
    catch {
        return "ERRO ao abrir Gerenciador de Credenciais:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenAccountsSettings {
    try {
        Start-Process "ms-settings:emailandaccounts"
        return "Tela Contas de email e aplicativo aberta."
    }
    catch {
        return "ERRO ao abrir Contas:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenOfficeRepair {
    try {
        Start-Process "appwiz.cpl"
        return "Programas e Recursos aberto.`nLocalize Microsoft 365/Office, clique em Alterar e escolha Reparo Rápido ou Reparo Online."
    }
    catch {
        return "ERRO ao abrir Programas e Recursos:`n$($_.Exception.Message)"
    }
}

function Get-ToolkitOfficeIdentityKeys {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Office Identity - Registro")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        $paths = @(
            "HKCU:\Software\Microsoft\Office\16.0\Common\Identity",
            "HKCU:\Software\Microsoft\Office\15.0\Common\Identity"
        )

        foreach ($path in $paths) {
            [void]$o.AppendLine("Chave: $path")

            if (Test-Path $path) {
                try {
                    $props = Get-ItemProperty -Path $path
                    [void]$o.AppendLine(($props | Format-List | Out-String))
                }
                catch {
                    [void]$o.AppendLine("Erro ao ler chave: $($_.Exception.Message)")
                }
            }
            else {
                [void]$o.AppendLine("Não encontrada.")
            }

            [void]$o.AppendLine("")
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao consultar Office Identity:`n$($_.Exception.Message)"
    }
}


# ============================================================
# Microsoft Store / Apps - Funções
# ============================================================

function Get-ToolkitStoreAppsStatus {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Status Microsoft Store / Apps")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        [void]$o.AppendLine("Usuário atual:")
        [void]$o.AppendLine("$env:USERDOMAIN\$env:USERNAME")
        [void]$o.AppendLine("")

        [void]$o.AppendLine("Microsoft Store:")
        try {
            $store = Get-AppxPackage -Name "Microsoft.WindowsStore" -ErrorAction SilentlyContinue

            if ($store) {
                [void]$o.AppendLine("Nome: $($store.Name)")
                [void]$o.AppendLine("Versão: $($store.Version)")
                [void]$o.AppendLine("InstallLocation: $($store.InstallLocation)")
                [void]$o.AppendLine("PackageFullName: $($store.PackageFullName)")
            }
            else {
                [void]$o.AppendLine("Microsoft Store não encontrada para o usuário atual.")
            }
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar Microsoft Store: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("App Installer:")
        try {
            $installer = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue

            if ($installer) {
                [void]$o.AppendLine("Nome: $($installer.Name)")
                [void]$o.AppendLine("Versão: $($installer.Version)")
            }
            else {
                [void]$o.AppendLine("App Installer não encontrado.")
            }
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar App Installer: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Novo Teams:")
        try {
            $teams = Get-AppxPackage -Name "MSTeams" -ErrorAction SilentlyContinue

            if ($teams) {
                [void]$o.AppendLine("Nome: $($teams.Name)")
                [void]$o.AppendLine("Versão: $($teams.Version)")
                [void]$o.AppendLine("PackageFullName: $($teams.PackageFullName)")
            }
            else {
                [void]$o.AppendLine("Novo Teams não encontrado via AppxPackage.")
            }
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar Novo Teams: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Serviços relacionados:")
        $services = @(
            "InstallService",
            "AppXSvc",
            "ClipSVC",
            "TokenBroker",
            "WpnService"
        )

        foreach ($svc in $services) {
            $service = Get-Service -Name $svc -ErrorAction SilentlyContinue

            if ($service) {
                [void]$o.AppendLine("$($service.Name) - $($service.DisplayName) - $($service.Status)")
            }
            else {
                [void]$o.AppendLine("$svc - não encontrado")
            }
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Processos relacionados:")
        $processes = Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessName -like "*WinStore*" -or
                $_.ProcessName -like "*Store*" -or
                $_.ProcessName -like "*wsreset*" -or
                $_.ProcessName -like "*teams*" -or
                $_.ProcessName -like "*MSTeams*"
            } |
            Select-Object ProcessName, Id, Path

        if ($processes) {
            [void]$o.AppendLine(($processes | Format-Table -AutoSize | Out-String))
        }
        else {
            [void]$o.AppendLine("Nenhum processo relacionado encontrado.")
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao consultar status Microsoft Store / Apps:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitRestartMicrosoftStore {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Reiniciar Microsoft Store")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        $processes = Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessName -like "*WinStore*" -or
                $_.ProcessName -like "*MicrosoftStore*" -or
                $_.ProcessName -like "*StoreExperienceHost*"
            }

        if ($processes) {
            foreach ($p in $processes) {
                try {
                    [void]$o.AppendLine("Finalizando: $($p.ProcessName) - PID $($p.Id)")
                    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                }
                catch {
                    [void]$o.AppendLine("Falha ao finalizar $($p.ProcessName): $($_.Exception.Message)")
                }
            }
        }
        else {
            [void]$o.AppendLine("Nenhum processo da Microsoft Store encontrado em execução.")
        }

        Start-Sleep -Seconds 2

        try {
            Start-Process "ms-windows-store:"
            [void]$o.AppendLine("")
            [void]$o.AppendLine("Microsoft Store aberta novamente.")
        }
        catch {
            [void]$o.AppendLine("Não foi possível abrir a Store via protocolo ms-windows-store.")
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao reiniciar Microsoft Store:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitResetMicrosoftStore {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Reset Microsoft Store")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")
        [void]$o.AppendLine("Executando wsreset.exe...")
        [void]$o.AppendLine("Uma janela pode abrir e fechar automaticamente.")

        Start-Process "wsreset.exe"

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Reset da Microsoft Store iniciado.")
        [void]$o.AppendLine("Aguarde a Store abrir automaticamente.")

        return $o.ToString()
    }
    catch {
        return "ERRO ao executar wsreset.exe:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitRepairMicrosoftStorePackage {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Reparar pacote Microsoft Store")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        $store = Get-AppxPackage -Name "Microsoft.WindowsStore" -ErrorAction SilentlyContinue

        if (!$store) {
            return "Microsoft Store não encontrada para o usuário atual."
        }

        $manifest = Join-Path $store.InstallLocation "AppxManifest.xml"

        if (!(Test-Path $manifest)) {
            return "Manifesto da Microsoft Store não encontrado:`n$manifest"
        }

        [void]$o.AppendLine("Registrando novamente:")
        [void]$o.AppendLine($manifest)
        [void]$o.AppendLine("")

        Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop

        [void]$o.AppendLine("Microsoft Store registrada/reparada com sucesso.")
        [void]$o.AppendLine("Recomendação: abrir a Store e testar novamente.")

        return $o.ToString()
    }
    catch {
        return "ERRO ao reparar Microsoft Store:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitRepairAllWindowsApps {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Reparar Apps do Windows")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")
        [void]$o.AppendLine("Re-registrando pacotes Appx do usuário atual...")
        [void]$o.AppendLine("Esse processo pode demorar alguns minutos.")
        [void]$o.AppendLine("")

        $packages = Get-AppxPackage -ErrorAction SilentlyContinue
        $count = 0
        $fail = 0

        foreach ($pkg in $packages) {
            try {
                $manifest = Join-Path $pkg.InstallLocation "AppxManifest.xml"

                if (Test-Path $manifest) {
                    Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction SilentlyContinue
                    $count++
                }
            }
            catch {
                $fail++
            }
        }

        [void]$o.AppendLine("Pacotes processados: $count")
        [void]$o.AppendLine("Falhas ignoradas: $fail")
        [void]$o.AppendLine("")
        [void]$o.AppendLine("Reparo de Apps concluído.")
        [void]$o.AppendLine("Recomendação: reiniciar o computador se o problema persistir.")

        return $o.ToString()
    }
    catch {
        return "ERRO ao reparar Apps do Windows:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenInstalledApps {
    try {
        Start-Process "ms-settings:appsfeatures"
        return "Tela Apps Instalados aberta."
    }
    catch {
        return "ERRO ao abrir Apps Instalados:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenMicrosoftStore {
    try {
        Start-Process "ms-windows-store:"
        return "Microsoft Store aberta."
    }
    catch {
        return "ERRO ao abrir Microsoft Store:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenOfficeTeamsRepair {
    try {
        Start-Process "appwiz.cpl"
        return @"
Reparo Office / Teams aberto.

Na janela Programas e Recursos:
1. Localize Microsoft 365 Apps ou Microsoft Office.
2. Clique com o botão direito ou selecione Alterar.
3. Escolha Reparo Rápido.
4. Se não resolver, execute Reparo Online.

Esse reparo ajuda em problemas de:
- Teams integrado ao Office;
- Outlook/Teams;
- autenticação;
- add-ins;
- componentes do Microsoft 365.
"@
    }
    catch {
        return "ERRO ao abrir Reparo Office / Teams:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenStoreTroubleshoot {
    try {
        Start-Process "ms-settings:troubleshoot"
        return "Tela de Solução de Problemas aberta.`nProcure por solucionadores relacionados a Apps da Microsoft Store."
    }
    catch {
        return "ERRO ao abrir Solução de Problemas:`n$($_.Exception.Message)"
    }
}


# ============================================================
# Rede Avançada - Funções
# ============================================================

function Get-ToolkitAdvancedNetworkStatus {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Status de Rede Avançada")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        [void]$o.AppendLine("Adaptadores ativos:")
        try {
            $adapters = Get-NetAdapter -ErrorAction SilentlyContinue |
                Sort-Object Status, Name |
                Select-Object Name, InterfaceDescription, Status, MacAddress, LinkSpeed

            [void]$o.AppendLine(($adapters | Format-Table -AutoSize | Out-String))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar adaptadores: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Configuração IP:")
        try {
            [void]$o.AppendLine((Get-NetIPConfiguration | Format-List | Out-String))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar IP: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Perfil de rede:")
        try {
            [void]$o.AppendLine((Get-NetConnectionProfile | Format-Table -AutoSize | Out-String))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar perfil de rede: $($_.Exception.Message)")
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao consultar status de rede avançada:`n$($_.Exception.Message)"
    }
}

function Get-ToolkitDnsConfiguration {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("DNS configurado")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        try {
            $dns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Select-Object InterfaceAlias, InterfaceIndex, ServerAddresses

            if ($dns) {
                [void]$o.AppendLine(($dns | Format-Table -AutoSize | Out-String))
            }
            else {
                [void]$o.AppendLine("Nenhum DNS IPv4 encontrado.")
            }
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar DNS: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Cache DNS atual:")
        try {
            $cache = Get-DnsClientCache -ErrorAction SilentlyContinue |
                Select-Object -First 30 Entry, RecordType, Status, Data

            if ($cache) {
                [void]$o.AppendLine(($cache | Format-Table -AutoSize | Out-String))
            }
            else {
                [void]$o.AppendLine("Cache DNS vazio ou indisponível.")
            }
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar cache DNS: $($_.Exception.Message)")
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao consultar DNS:`n$($_.Exception.Message)"
    }
}

function Get-ToolkitNetworkRoutes {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Rotas de Rede")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        try {
            [void]$o.AppendLine("Rotas IPv4 principais:")
            $routes = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Sort-Object RouteMetric |
                Select-Object DestinationPrefix, NextHop, InterfaceAlias, RouteMetric |
                Select-Object -First 80

            [void]$o.AppendLine(($routes | Format-Table -AutoSize | Out-String))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar Get-NetRoute: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("route print:")
        try {
            [void]$o.AppendLine((route print 2>&1 | Out-String))
        }
        catch {
            [void]$o.AppendLine("Erro ao executar route print: $($_.Exception.Message)")
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao consultar rotas:`n$($_.Exception.Message)"
    }
}

function Test-ToolkitGateway {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Teste de Gateway")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        $gateways = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $_.IPv4DefaultGateway -and $_.IPv4DefaultGateway.NextHop } |
            ForEach-Object { $_.IPv4DefaultGateway.NextHop } |
            Select-Object -Unique

        if (!$gateways) {
            return "Nenhum gateway IPv4 encontrado."
        }

        foreach ($gateway in $gateways) {
            [void]$o.AppendLine("Gateway: $gateway")

            $result = Test-Connection -ComputerName $gateway -Count 4 -ErrorAction SilentlyContinue

            if ($result) {
                [void]$o.AppendLine("Status: OK")
                [void]$o.AppendLine(($result | Select-Object Address, ResponseTime, StatusCode | Format-Table -AutoSize | Out-String))
            }
            else {
                [void]$o.AppendLine("Status: Falha no ping")
            }

            [void]$o.AppendLine("")
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao testar gateway:`n$($_.Exception.Message)"
    }
}

function Test-ToolkitInternetAdvanced {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Teste de Internet")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        $targets = @(
            "8.8.8.8",
            "1.1.1.1",
            "google.com",
            "microsoft.com"
        )

        foreach ($target in $targets) {
            [void]$o.AppendLine("Testando: $target")

            try {
                $ping = Test-Connection -ComputerName $target -Count 2 -Quiet -ErrorAction SilentlyContinue

                if ($ping) {
                    [void]$o.AppendLine("Ping: OK")
                }
                else {
                    [void]$o.AppendLine("Ping: Falha")
                }
            }
            catch {
                [void]$o.AppendLine("Ping: Erro - $($_.Exception.Message)")
            }

            [void]$o.AppendLine("")
        }

        [void]$o.AppendLine("Resolução DNS:")
        try {
            $dns = Resolve-DnsName "microsoft.com" -ErrorAction Stop
            [void]$o.AppendLine("DNS: OK")
            [void]$o.AppendLine(($dns | Select-Object -First 5 Name, Type, IPAddress | Format-Table -AutoSize | Out-String))
        }
        catch {
            [void]$o.AppendLine("DNS: Falha - $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Teste HTTPS microsoft.com:443")
        try {
            $tcp = Test-NetConnection -ComputerName "microsoft.com" -Port 443 -InformationLevel Detailed
            [void]$o.AppendLine(($tcp | Format-List | Out-String))
        }
        catch {
            [void]$o.AppendLine("Erro no teste HTTPS: $($_.Exception.Message)")
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao testar internet:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitResetWinsock {
    try {
        if (!(Test-Admin)) {
            return "ERRO: execute a ferramenta como administrador para resetar Winsock."
        }

        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Reset Winsock")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        netsh winsock reset 2>&1 | ForEach-Object {
            [void]$o.AppendLine($_)
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Reset Winsock executado.")
        [void]$o.AppendLine("Recomendação: reiniciar o computador.")

        return $o.ToString()
    }
    catch {
        return "ERRO ao resetar Winsock:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitResetTcpIp {
    try {
        if (!(Test-Admin)) {
            return "ERRO: execute a ferramenta como administrador para resetar TCP/IP."
        }

        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Reset TCP/IP")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        netsh int ip reset 2>&1 | ForEach-Object {
            [void]$o.AppendLine($_)
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Reset TCP/IP executado.")
        [void]$o.AppendLine("Recomendação: reiniciar o computador.")

        return $o.ToString()
    }
    catch {
        return "ERRO ao resetar TCP/IP:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitReleaseRenewAdvanced {
    try {
        if (!(Test-Admin)) {
            return "ERRO: execute a ferramenta como administrador para renovar IP."
        }

        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Release/Renew IP")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")
        [void]$o.AppendLine("Executando ipconfig /release...")

        ipconfig /release 2>&1 | ForEach-Object {
            [void]$o.AppendLine($_)
        }

        Start-Sleep -Seconds 3

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Executando ipconfig /renew...")

        ipconfig /renew 2>&1 | ForEach-Object {
            [void]$o.AppendLine($_)
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Release/Renew finalizado.")

        return $o.ToString()
    }
    catch {
        return "ERRO ao renovar IP:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitFlushDnsAdvanced {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Flush DNS")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")

        ipconfig /flushdns 2>&1 | ForEach-Object {
            [void]$o.AppendLine($_)
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao limpar DNS:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenNetworkConnectionsAdvanced {
    try {
        Start-Process "ncpa.cpl"
        return "Conexões de Rede abertas."
    }
    catch {
        return "ERRO ao abrir Conexões de Rede:`n$($_.Exception.Message)"
    }
}


# ============================================================
# Apps Corporativos - Diagnóstico de Erros Windows
# ============================================================

function Get-ToolkitAppEventErrors {
    param(
        [string]$AppName,
        [string[]]$Keywords,
        [int]$Days = 7
    )

    try {
        $o = New-Object System.Text.StringBuilder
        $start = (Get-Date).AddDays(-$Days)
        $pattern = ($Keywords | ForEach-Object { [regex]::Escape($_) }) -join "|"

        [void]$o.AppendLine("Erros Windows - $AppName")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("Período analisado: últimos $Days dias")
        [void]$o.AppendLine("")

        [void]$o.AppendLine("Eventos de Aplicativo:")
        [void]$o.AppendLine("--------------------------------------")

        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName = "Application"
                Level = 1,2,3
                StartTime = $start
            } -ErrorAction SilentlyContinue | Where-Object {
                "$($_.ProviderName) $($_.Message)" -match $pattern
            } | Select-Object -First 25 TimeCreated, ProviderName, Id, LevelDisplayName, Message

            if ($events) {
                [void]$o.AppendLine(($events | Format-List | Out-String))
            }
            else {
                [void]$o.AppendLine("Nenhum erro relevante encontrado no log Application.")
            }
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar Application Log: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Monitor de Confiabilidade:")
        [void]$o.AppendLine("--------------------------------------")

        try {
            $reliability = Get-CimInstance -ClassName Win32_ReliabilityRecords -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.TimeGenerated -ge $start -and (
                        "$($_.ProductName) $($_.Message) $($_.SourceName)" -match $pattern
                    )
                } |
                Select-Object -First 20 TimeGenerated, SourceName, ProductName, EventIdentifier, Message

            if ($reliability) {
                [void]$o.AppendLine(($reliability | Format-List | Out-String))
            }
            else {
                [void]$o.AppendLine("Nenhum registro relevante encontrado no Monitor de Confiabilidade.")
            }
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar Monitor de Confiabilidade: $($_.Exception.Message)")
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao consultar erros do app ${AppName}:`n$($_.Exception.Message)"
    }
}

function Get-ToolkitCorporateAppsStatus {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Status - Apps Corporativos")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")
        [void]$o.AppendLine("Usuário atual:")
        [void]$o.AppendLine("$env:USERDOMAIN\$env:USERNAME")
        [void]$o.AppendLine("")

        [void]$o.AppendLine("Processos em execução:")
        [void]$o.AppendLine("--------------------------------------")

        $processes = Get-Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.ProcessName -match "outlook|teams|ms-teams|msteams|onedrive|snippingtool|screenclippinghost|whatsapp|msedgewebview2"
            } |
            Select-Object ProcessName, Id, Path

        if ($processes) {
            [void]$o.AppendLine(($processes | Format-Table -AutoSize | Out-String))
        }
        else {
            [void]$o.AppendLine("Nenhum processo corporativo monitorado encontrado em execução.")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Pacotes Appx relevantes:")
        [void]$o.AppendLine("--------------------------------------")

        $packages = Get-AppxPackage -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -match "MSTeams|WhatsApp|ScreenSketch|SnippingTool|WindowsStore|MicrosoftOfficeHub|OneDrive"
            } |
            Select-Object Name, Version, PackageFullName

        if ($packages) {
            [void]$o.AppendLine(($packages | Format-Table -AutoSize | Out-String))
        }
        else {
            [void]$o.AppendLine("Nenhum pacote Appx relevante encontrado para o usuário atual.")
        }

        return $o.ToString()
    }
    catch {
        return "ERRO ao consultar status de apps corporativos:`n$($_.Exception.Message)"
    }
}

function Get-ToolkitOutlookErrors {
    return Get-ToolkitAppEventErrors -AppName "Outlook" -Keywords @("Outlook","OUTLOOK.EXE","Microsoft Outlook","Office","Microsoft 365","Application Error","Windows Error Reporting")
}

function Get-ToolkitTeamsErrors {
    return Get-ToolkitAppEventErrors -AppName "Teams" -Keywords @("Teams","MSTeams","ms-teams","Teams.exe","WebView2","msedgewebview2","Application Error","Windows Error Reporting")
}

function Get-ToolkitOneDriveErrors {
    return Get-ToolkitAppEventErrors -AppName "OneDrive" -Keywords @("OneDrive","OneDrive.exe","Microsoft OneDrive","Sync","Application Error","Windows Error Reporting")
}

function Get-ToolkitScreenshotErrors {
    return Get-ToolkitAppEventErrors -AppName "Captura de Tela" -Keywords @("SnippingTool","Snipping Tool","ScreenSketch","ScreenClippingHost","Captura","Ferramenta de Captura","Application Error","Windows Error Reporting")
}

function Get-ToolkitWhatsAppErrors {
    return Get-ToolkitAppEventErrors -AppName "WhatsApp" -Keywords @("WhatsApp","WhatsApp.exe","WhatsAppDesktop","5319275A.WhatsAppDesktop","Application Error","Windows Error Reporting")
}

function Get-ToolkitAllCorporateAppErrors {
    try {
        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("Erros gerais - Apps Corporativos")
        [void]$o.AppendLine("======================================")
        [void]$o.AppendLine("")
        [void]$o.AppendLine((Get-ToolkitOutlookErrors))
        [void]$o.AppendLine("")
        [void]$o.AppendLine((Get-ToolkitTeamsErrors))
        [void]$o.AppendLine("")
        [void]$o.AppendLine((Get-ToolkitOneDriveErrors))
        [void]$o.AppendLine("")
        [void]$o.AppendLine((Get-ToolkitScreenshotErrors))
        [void]$o.AppendLine("")
        [void]$o.AppendLine((Get-ToolkitWhatsAppErrors))

        return $o.ToString()
    }
    catch {
        return "ERRO ao consultar erros gerais dos apps corporativos:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenReliabilityMonitor {
    try {
        Start-Process "perfmon.exe" "/rel"
        return "Monitor de Confiabilidade aberto."
    }
    catch {
        return "ERRO ao abrir Monitor de Confiabilidade:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenEventViewerApplication {
    try {
        Start-Process "eventvwr.msc"
        return "Visualizador de Eventos aberto.`nVerifique principalmente: Logs do Windows > Aplicativo."
    }
    catch {
        return "ERRO ao abrir Visualizador de Eventos:`n$($_.Exception.Message)"
    }
}


# ============================================================
# Atendimento Rápido - Funções
# ============================================================

function New-ToolkitQuickHeader {
    param(
        [string]$Title
    )

    $o = New-Object System.Text.StringBuilder

    [void]$o.AppendLine($Title)
    [void]$o.AppendLine("======================================")
    [void]$o.AppendLine("Data/hora: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')")
    [void]$o.AppendLine("Máquina: $env:COMPUTERNAME")
    [void]$o.AppendLine("Usuário: $env:USERDOMAIN\$env:USERNAME")
    [void]$o.AppendLine("Administrador: $(if (Test-Admin) { 'Sim' } else { 'Não' })")
    [void]$o.AppendLine("")

    return $o
}

function Invoke-ToolkitQuickInternet {
    try {
        $o = New-ToolkitQuickHeader -Title "Atendimento Rápido - Problema de Internet"

        [void]$o.AppendLine("1. Status de IP")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-NetIPConfiguration | Format-List | Out-String))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar IP: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("2. Teste de Gateway")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Test-ToolkitGateway))
        }
        catch {
            [void]$o.AppendLine("Erro no teste de gateway: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("3. Teste de Internet")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Test-ToolkitInternetAdvanced))
        }
        catch {
            [void]$o.AppendLine("Erro no teste de internet: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Sugestão:")
        [void]$o.AppendLine("- Se IP/gateway estiverem ausentes, validar cabo/Wi-Fi/VPN.")
        [void]$o.AppendLine("- Se ping por IP funcionar e domínio falhar, provável problema de DNS.")
        [void]$o.AppendLine("- Se nada responder, avaliar rede local, DHCP, proxy, VPN ou bloqueio.")

        return $o.ToString()
    }
    catch {
        return "ERRO no atendimento rápido de Internet:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitQuickTeams {
    try {
        $o = New-ToolkitQuickHeader -Title "Atendimento Rápido - Problema no Teams"

        [void]$o.AppendLine("1. Status Teams / Office")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-ToolkitTeamsOfficeStatus))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar Teams / Office: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("2. Erros recentes do Teams")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-ToolkitTeamsErrors))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar erros do Teams: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("3. Status Microsoft Store / Apps")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-ToolkitStoreAppsStatus))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar Store / Apps: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Sugestão:")
        [void]$o.AppendLine("- Se houver erro de WebView2, validar Microsoft Edge WebView2 Runtime.")
        [void]$o.AppendLine("- Se for autenticação, validar Credential Manager e Contas Windows.")
        [void]$o.AppendLine("- Se persistir, limpar cache do Novo Teams ou Teams clássico conforme versão instalada.")

        return $o.ToString()
    }
    catch {
        return "ERRO no atendimento rápido de Teams:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitQuickOutlook {
    try {
        $o = New-ToolkitQuickHeader -Title "Atendimento Rápido - Problema no Outlook"

        [void]$o.AppendLine("1. Status Teams / Office")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-ToolkitTeamsOfficeStatus))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar Office: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("2. Erros recentes do Outlook")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-ToolkitOutlookErrors))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar erros do Outlook: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("3. Office Identity")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-ToolkitOfficeIdentityKeys))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar Office Identity: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Sugestão:")
        [void]$o.AppendLine("- Se houver erro de autenticação, validar contas Windows e credenciais salvas.")
        [void]$o.AppendLine("- Se Outlook travar ao abrir, testar modo seguro: outlook.exe /safe.")
        [void]$o.AppendLine("- Se persistir, executar Reparo Rápido do Microsoft 365/Office.")

        return $o.ToString()
    }
    catch {
        return "ERRO no atendimento rápido de Outlook:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitQuickOneDrive {
    try {
        $o = New-ToolkitQuickHeader -Title "Atendimento Rápido - Problema no OneDrive"

        [void]$o.AppendLine("1. Status Apps Corporativos")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-ToolkitCorporateAppsStatus))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar apps corporativos: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("2. Erros recentes do OneDrive")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-ToolkitOneDriveErrors))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar erros do OneDrive: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("3. Processo OneDrive")
        [void]$o.AppendLine("--------------------------------------")
        try {
            $proc = Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Select-Object ProcessName, Id, Path
            if ($proc) {
                [void]$o.AppendLine(($proc | Format-Table -AutoSize | Out-String))
            }
            else {
                [void]$o.AppendLine("OneDrive não está em execução.")
            }
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar processo OneDrive: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Sugestão:")
        [void]$o.AppendLine("- Validar login corporativo no OneDrive.")
        [void]$o.AppendLine("- Validar espaço em disco e caminho de sincronização.")
        [void]$o.AppendLine("- Se necessário, reiniciar OneDrive ou redefinir o cliente.")

        return $o.ToString()
    }
    catch {
        return "ERRO no atendimento rápido de OneDrive:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitQuickPrinter {
    try {
        $o = New-ToolkitQuickHeader -Title "Atendimento Rápido - Problema de Impressora"

        [void]$o.AppendLine("1. Status de Impressoras")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-ToolkitPrinterStatus))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar impressoras: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("2. Fila de Impressão")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-ToolkitPrintJobs))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar fila: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("3. Impressora padrão")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-ToolkitDefaultPrinter))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar impressora padrão: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Sugestão:")
        [void]$o.AppendLine("- Se houver documentos presos, usar Limpar fila.")
        [void]$o.AppendLine("- Se spooler estiver parado, usar Reiniciar Spooler.")
        [void]$o.AppendLine("- Se impressora estiver offline, validar rede, porta, driver e status físico.")

        return $o.ToString()
    }
    catch {
        return "ERRO no atendimento rápido de Impressora:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitQuickWindowsUpdate {
    try {
        $o = New-ToolkitQuickHeader -Title "Atendimento Rápido - Problema no Windows Update"

        [void]$o.AppendLine("1. Status Windows / Reparo")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-WindowsRepairStatus))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar Windows / Reparo: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("2. Serviços Windows Update")
        [void]$o.AppendLine("--------------------------------------")
        try {
            $services = Get-Service wuauserv,bits,cryptsvc,msiserver -ErrorAction SilentlyContinue |
                Select-Object Name, DisplayName, Status

            if ($services) {
                [void]$o.AppendLine(($services | Format-Table -AutoSize | Out-String))
            }
            else {
                [void]$o.AppendLine("Serviços principais do Windows Update não encontrados.")
            }
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar serviços WU: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Sugestão:")
        [void]$o.AppendLine("- Se serviços estiverem parados, usar Reiniciar serviços WU.")
        [void]$o.AppendLine("- Se erro persistir, usar Limpar cache WU.")
        [void]$o.AppendLine("- Se houver corrupção de imagem, executar DISM e depois SFC.")

        return $o.ToString()
    }
    catch {
        return "ERRO no atendimento rápido de Windows Update:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitQuickAppgate {
    try {
        $o = New-ToolkitQuickHeader -Title "Atendimento Rápido - Problema no Appgate"

        [void]$o.AppendLine("1. Status VPN / Appgate")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Get-AppgateStatus))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar Appgate: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("2. Rede")
        [void]$o.AppendLine("--------------------------------------")
        try {
            [void]$o.AppendLine((Test-NetworkBasic))
        }
        catch {
            [void]$o.AppendLine("Erro ao consultar rede: $($_.Exception.Message)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("Sugestão:")
        [void]$o.AppendLine("- Se RunScriptTimeout estiver diferente de 300000, aplicar Correção VPN / Appgate.")
        [void]$o.AppendLine("- Se serviços/processos estiverem travados, usar Reiniciar VPN / Appgate.")
        [void]$o.AppendLine("- Se não houver internet, resolver rede antes da VPN.")

        return $o.ToString()
    }
    catch {
        return "ERRO no atendimento rápido de Appgate:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitQuickFullReport {
    try {
        $o = New-ToolkitQuickHeader -Title "Atendimento Rápido - Relatório Geral"

        [void]$o.AppendLine("Gerando relatório HTML completo...")
        [void]$o.AppendLine("")

        $result = Export-ReportHtml

        [void]$o.AppendLine($result)
        [void]$o.AppendLine("")
        [void]$o.AppendLine("Sugestão:")
        [void]$o.AppendLine("- Anexe o relatório HTML no chamado.")
        [void]$o.AppendLine("- Caso precise de evidência técnica simples, gere também o TXT.")

        return $o.ToString()
    }
    catch {
        return "ERRO ao gerar relatório geral:`n$($_.Exception.Message)"
    }
}


# ============================================================
# Proteção - Ações Críticas
# ============================================================

function Test-ToolkitIsAdminSafe {
    try {
        if (Get-Command Test-Admin -ErrorAction SilentlyContinue) {
            return [bool](Test-Admin)
        }

        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Show-ToolkitInfoMessage {
    param(
        [string]$Title,
        [string]$Message
    )

    try {
        [System.Windows.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information
        ) | Out-Null
    }
    catch {
        Write-Host "$Title - $Message"
    }
}

function Show-ToolkitWarningMessage {
    param(
        [string]$Title,
        [string]$Message
    )

    try {
        [System.Windows.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Warning
        ) | Out-Null
    }
    catch {
        Write-Host "$Title - $Message"
    }
}

function Confirm-ToolkitCriticalAction {
    param(
        [string]$Title,
        [string]$Message
    )

    try {
        $result = [System.Windows.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )

        return ($result -eq [System.Windows.MessageBoxResult]::Yes)
    }
    catch {
        $answer = Read-Host "$Title - $Message Digite S para continuar"
        return ($answer -match '^(S|s|SIM|sim)$')
    }
}

function Invoke-ToolkitProtectedAction {
    param(
        [string]$Title,
        [string]$RiskMessage,
        [scriptblock]$Action,
        [bool]$RequireAdmin = $true,
        [bool]$Critical = $true
    )

    try {
        if ($RequireAdmin -and -not (Test-ToolkitIsAdminSafe)) {
            $msg = @"
Essa ação precisa ser executada como administrador.

Ação:
$Title

Como resolver:
1. Feche o ServiceDesk Toolkit.
2. Clique com o botão direito no ServiceDeskToolkit.cmd.
3. Escolha "Executar como administrador".
4. Tente novamente.
"@

            Show-ToolkitWarningMessage -Title "Permissão de administrador necessária" -Message $msg

            return @"
AÇÃƒO BLOQUEADA

Ação: $Title
Motivo: o toolkit não está sendo executado como administrador.

Feche a ferramenta e abra novamente como administrador.
"@
        }

        if ($Critical) {
            $confirmMessage = @"
Essa ação pode alterar configurações do Windows, reiniciar serviços, limpar cache ou exigir reinício da máquina.

Ação:
$Title

Risco/impacto:
$RiskMessage

Deseja continuar?
"@

            $confirmed = Confirm-ToolkitCriticalAction -Title "Confirmar ação crítica" -Message $confirmMessage

            if (-not $confirmed) {
                return @"
AÇÃƒO CANCELADA

Ação: $Title
Status: cancelada pelo usuário.
Nenhuma alteração foi aplicada.
"@
            }
        }

        $inicio = Get-Date

        $resultado = & $Action

        $fim = Get-Date
        $duracao = New-TimeSpan -Start $inicio -End $fim

        return @"
AÇÃƒO EXECUTADA

Ação: $Title
Início: $($inicio.ToString("dd/MM/yyyy HH:mm:ss"))
Fim: $($fim.ToString("dd/MM/yyyy HH:mm:ss"))
Duração: $([math]::Round($duracao.TotalSeconds, 2)) segundos

Resultado:
$resultado
"@
    }
    catch {
        return @"
ERRO AO EXECUTAR AÇÃƒO PROTEGIDA

Ação: $Title
Erro: $($_.Exception.Message)
"@
    }
}


# ============================================================
# Wrappers Protegidos - Ações Críticas
# ============================================================

function Invoke-ToolkitProtectedResetWinsock {
    Invoke-ToolkitProtectedAction `
        -Title "Reset Winsock" `
        -RiskMessage "Redefine o catálogo Winsock. Pode afetar conectividade, VPN, proxy, agentes de segurança e normalmente exige reinício." `
        -RequireAdmin $true `
        -Critical $true `
        -Action { Invoke-ToolkitResetWinsock }
}

function Invoke-ToolkitProtectedResetTcpIp {
    Invoke-ToolkitProtectedAction `
        -Title "Reset TCP/IP" `
        -RiskMessage "Redefine parÃ¢metros da pilha TCP/IP. Pode impactar rede, VPN e políticas locais. Normalmente exige reinício." `
        -RequireAdmin $true `
        -Critical $true `
        -Action { Invoke-ToolkitResetTcpIp }
}

function Invoke-ToolkitProtectedClearWUCache {
    Invoke-ToolkitProtectedAction `
        -Title "Limpar cache do Windows Update" `
        -RiskMessage "Para serviços do Windows Update e limpa cache de atualização. Pode exigir nova verificação de updates e reinício." `
        -RequireAdmin $true `
        -Critical $true `
        -Action { Clear-WUCache }
}

function Invoke-ToolkitProtectedRepairWindowsApps {
    Invoke-ToolkitProtectedAction `
        -Title "Reparar Apps Windows" `
        -RiskMessage "Re-registra pacotes Appx do Windows para o usuário atual. Pode demorar e impactar Microsoft Store, Teams novo, Captura de Tela e outros apps." `
        -RequireAdmin $true `
        -Critical $true `
        -Action { Invoke-ToolkitRepairAllWindowsApps }
}

function Invoke-ToolkitProtectedDismOnly {
    Invoke-ToolkitProtectedAction `
        -Title "DISM RestoreHealth" `
        -RiskMessage "Executa reparo da imagem do Windows. Pode demorar bastante, consumir recursos e depender do Windows Update." `
        -RequireAdmin $true `
        -Critical $true `
        -Action { Start-DismOnly }
}

function Invoke-ToolkitProtectedSfcOnly {
    Invoke-ToolkitProtectedAction `
        -Title "SFC Scannow" `
        -RiskMessage "Verifica e repara arquivos protegidos do Windows. Pode demorar e exigir reinício dependendo do resultado." `
        -RequireAdmin $true `
        -Critical $true `
        -Action { Start-SfcOnly }
}

function Invoke-ToolkitProtectedDismSfc {
    Invoke-ToolkitProtectedAction `
        -Title "DISM + SFC" `
        -RiskMessage "Executa reparos avançados do Windows. Pode demorar bastante, abrir nova janela e exigir reinício." `
        -RequireAdmin $true `
        -Critical $true `
        -Action { Start-DismSfc }
}

function Invoke-ToolkitProtectedAppgateFix {
    Invoke-ToolkitProtectedAction `
        -Title "Corrigir VPN / Appgate" `
        -RiskMessage "Altera configuração do Appgate e política UAC relacionada. Pode impactar autenticação, VPN e execução de scripts." `
        -RequireAdmin $true `
        -Critical $true `
        -Action { Invoke-AppgateFix }
}

function Invoke-ToolkitProtectedTpmOfficeFix {
    Invoke-ToolkitProtectedAction `
        -Title "Ajuste TPM / Office" `
        -RiskMessage "Altera chaves de registro relacionadas a TPM, criptografia e autenticação do Office. Pode exigir novo login nos aplicativos Microsoft." `
        -RequireAdmin $true `
        -Critical $true `
        -Action { Invoke-TpmOfficeFix }
}

function Invoke-ToolkitProtectedBrokenPluginFix {
    Invoke-ToolkitProtectedAction `
        -Title "Limpar BrokenPlugin" `
        -RiskMessage "Remove chaves relacionadas ao Connected Devices Platform. Pode afetar integrações temporárias de autenticação/dispositivos." `
        -RequireAdmin $true `
        -Critical $true `
        -Action { Invoke-BrokenPluginFix }
}

function Invoke-ToolkitProtectedClearPrintQueue {
    Invoke-ToolkitProtectedAction `
        -Title "Limpar fila de impressão" `
        -RiskMessage "Remove documentos parados na fila de impressão. Trabalhos pendentes podem ser perdidos." `
        -RequireAdmin $true `
        -Critical $true `
        -Action { Invoke-ToolkitClearPrintQueue }
}


# ============================================================
# v2.0 - Base de Conhecimento Local
# ============================================================

function Get-ToolkitKnowledgeBasePath {
    return "C:\ServiceDeskToolkit\data\knowledge-base.json"
}

function Get-ToolkitKnowledgeBase {
    try {
        $path = Get-ToolkitKnowledgeBasePath

        if (!(Test-Path $path)) {
            return @()
        }

        $json = Get-Content $path -Raw -Encoding UTF8
        $kb = $json | ConvertFrom-Json

        return @($kb)
    }
    catch {
        return @()
    }
}

function Format-ToolkitKnowledgeArticle {
    param(
        [Parameter(Mandatory=$true)]
        $Article,

        [Parameter(Mandatory=$false)]
        [int]$Score = 0
    )

    $titulo = $Article.title
    $categoria = $Article.category
    $risco = $Article.risk
    $problema = $Article.problem
    $causa = $Article.probableCause
    $quandoEscalar = $Article.whenToEscalate

    $passos = @()
    if ($Article.steps) {
        $i = 1
        foreach ($step in $Article.steps) {
            $passos += "$i. $step"
            $i++
        }
    }

    $acoes = @()
    if ($Article.toolkitActions) {
        foreach ($action in $Article.toolkitActions) {
            $acoes += "- $action"
        }
    }

    $palavras = @()
    if ($Article.keywords) {
        foreach ($keyword in $Article.keywords) {
            $palavras += "- $keyword"
        }
    }

    $scoreTexto = "Não informado"
    if ($Score -gt 0) {
        $scoreTexto = "$Score ponto(s) de correspondência"
    }

    $texto = @"
============================================================
BASE DE CONHECIMENTO - ARTIGO ENCONTRADO
============================================================

Título:
$titulo

Categoria:
$categoria

Risco:
$risco

Correspondência:
$scoreTexto

Problema identificado:
$problema

Causa provável:
$causa

------------------------------------------------------------
PASSOS RECOMENDADOS
------------------------------------------------------------
$($passos -join "`r`n")

------------------------------------------------------------
AÇÕES RELACIONADAS NO TOOLKIT
------------------------------------------------------------
$($acoes -join "`r`n")

------------------------------------------------------------
QUANDO ESCALAR
------------------------------------------------------------
$quandoEscalar

------------------------------------------------------------
PALAVRAS-CHAVE
------------------------------------------------------------
$($palavras -join "`r`n")

============================================================
"@

    return $texto
}

function Search-ToolkitKnowledgeBase {
    param(
        [string]$Query
    )

    try {
        if ([string]::IsNullOrWhiteSpace($Query)) {
            return "Digite um resumo do problema para buscar na base de conhecimento."
        }

        $kb = Get-ToolkitKnowledgeBase

        if (!$kb -or $kb.Count -eq 0) {
            return "Base de conhecimento não encontrada ou vazia.`nCaminho esperado: $(Get-ToolkitKnowledgeBasePath)"
        }

        $queryNorm = $Query.ToLower().Trim()
        $terms = $queryNorm -split '\s+' | Where-Object { $_.Length -ge 3 } | Select-Object -Unique

        $results = foreach ($article in $kb) {
            $score = 0

            $titulo = [string]$article.titulo
            $categoria = [string]$article.categoria
            $causa = [string]$article.causaProvavel
            $resumo = [string]$article.resumo
            $risco = [string]$article.risco

            $keywords = @()
            if ($null -ne $article.palavrasChave) {
                $keywords = @($article.palavrasChave)
            }

            $haystack = @(
                $titulo,
                $categoria,
                $causa,
                $resumo,
                $risco,
                ($keywords -join " "),
                ($article.passos -join " "),
                ($article.acoesToolkit -join " ")
            ) -join " "

            $haystackNorm = $haystack.ToLower()

            foreach ($kw in $keywords) {
                if ($queryNorm -like "*$($kw.ToLower())*") {
                    $score += 10
                }
            }

            foreach ($term in $terms) {
                if ($haystackNorm -like "*$term*") {
                    $score += 2
                }

                if ($titulo.ToLower() -like "*$term*") {
                    $score += 4
                }
            }

            if ($score -gt 0) {
                [PSCustomObject]@{
                    Score = $score
                    Article = $article
                }
            }
        }

        $top = @($results | Sort-Object Score -Descending | Select-Object -First 3)

        if ($top.Count -eq 0) {
            return @"
Nenhuma resolução encontrada para:

$Query

Sugestões:
- Tente termos mais simples, como: teams, outlook, senha, impressora, appgate, vpn, onedrive, store, internet, dns.
- Cadastre um novo artigo na base de conhecimento se esse problema for recorrente.
"@
        }

        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("BASE DE CONHECIMENTO - RESULTADOS")
        [void]$o.AppendLine("============================================================")
        [void]$o.AppendLine("Busca: $Query")
        [void]$o.AppendLine("Resultados encontrados: $($top.Count)")
        [void]$o.AppendLine("")

        foreach ($item in $top) {
            [void]$o.AppendLine((Format-ToolkitKnowledgeArticle -Article $item.Article -Score $item.Score))
        }

        return $o.ToString()
    }
    catch {
        return "Erro ao buscar na base de conhecimento:`n$($_.Exception.Message)"
    }
}

function Get-ToolkitKnowledgeBaseSummary {
    try {
        $kb = Get-ToolkitKnowledgeBase

        if (!$kb -or $kb.Count -eq 0) {
            return "Base de conhecimento não encontrada ou vazia.`nCaminho esperado: $(Get-ToolkitKnowledgeBasePath)"
        }

        $o = New-Object System.Text.StringBuilder

        [void]$o.AppendLine("BASE DE CONHECIMENTO")
        [void]$o.AppendLine("============================================================")
        [void]$o.AppendLine("Arquivo: $(Get-ToolkitKnowledgeBasePath)")
        [void]$o.AppendLine("Artigos cadastrados: $($kb.Count)")
        [void]$o.AppendLine("")

        $categorias = $kb | Group-Object categoria | Sort-Object Name

        [void]$o.AppendLine("CATEGORIAS")
        [void]$o.AppendLine("----------------------------------------")

        foreach ($cat in $categorias) {
            [void]$o.AppendLine("- $($cat.Name): $($cat.Count)")
        }

        [void]$o.AppendLine("")
        [void]$o.AppendLine("ARTIGOS")
        [void]$o.AppendLine("----------------------------------------")

        foreach ($article in ($kb | Sort-Object categoria, titulo)) {
            [void]$o.AppendLine("- [$($article.categoria)] $($article.titulo) | Risco: $($article.risco)")
        }

        return $o.ToString()
    }
    catch {
        return "Erro ao listar base de conhecimento:`n$($_.Exception.Message)"
    }
}

function Invoke-ToolkitOpenKnowledgeBaseFile {
    try {
        $path = Get-ToolkitKnowledgeBasePath

        if (!(Test-Path $path)) {
            return "Arquivo não encontrado: $path"
        }

        Start-Process notepad.exe $path
        return "Base de conhecimento aberta no Bloco de Notas.`nArquivo: $path"
    }
    catch {
        return "Erro ao abrir base de conhecimento:`n$($_.Exception.Message)"
    }
}


# ============================================================
# Navegação - Selecionar aba por título
# ============================================================

function Select-ToolkitTabByHeader {
    param([string]$Header)

    try {
        if ($null -eq $script:MainTabs) {
            return $false
        }

        for ($i = 0; $i -lt $script:MainTabs.Items.Count; $i++) {
            $item = $script:MainTabs.Items[$i]

            if ([string]$item.Header -eq $Header) {
                $script:MainTabs.SelectedIndex = $i
                return $true
            }
        }

        return $false
    }
    catch {
        return $false
    }
}


# ============================================================
# Structured Logs - ServiceDesk Toolkit
# Compatibilidade: Windows PowerShell 5.1 e PowerShell 7+
# ============================================================

function Get-ToolkitRootPath {
    try {
        if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) {
            return $PSScriptRoot
        }

        return "C:\ServiceDeskToolkit"
    }
    catch {
        return "C:\ServiceDeskToolkit"
    }
}

function Get-ToolkitIsAdmin {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-ToolkitLogDirectory {
    try {
        $root = Get-ToolkitRootPath
        $logDir = Join-Path $root "logs"

        if (!(Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }

        return $logDir
    }
    catch {
        return "C:\ServiceDeskToolkit\logs"
    }
}

function Get-ToolkitStructuredLogPath {
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet("runtime","actions","errors","install","diagnostic")]
        [string]$LogType = "runtime"
    )

    $logDir = Get-ToolkitLogDirectory
    $month = Get-Date -Format "yyyy-MM"
    $fileName = "$LogType-$month.jsonl"

    return (Join-Path $logDir $fileName)
}

function Write-ToolkitStructuredLog {
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet("runtime","actions","errors","install","diagnostic")]
        [string]$LogType = "runtime",

        [Parameter(Mandatory=$false)]
        [ValidateSet("DEBUG","INFO","WARN","ERROR","CRITICAL")]
        [string]$Level = "INFO",

        [Parameter(Mandatory=$false)]
        [string]$Module = "General",

        [Parameter(Mandatory=$false)]
        [string]$Action = "None",

        [Parameter(Mandatory=$false)]
        [string]$Status = "None",

        [Parameter(Mandatory=$false)]
        [string]$Message = "",

        [Parameter(Mandatory=$false)]
        $Data = $null,

        [Parameter(Mandatory=$false)]
        $ErrorRecord = $null
    )

    try {
        $logPath = Get-ToolkitStructuredLogPath -LogType $LogType

        $errorInfo = $null

        if ($null -ne $ErrorRecord) {
            $errorInfo = [ordered]@{
                message = $ErrorRecord.Exception.Message
                type = $ErrorRecord.Exception.GetType().FullName
                category = [string]$ErrorRecord.CategoryInfo.Category
                fullyQualifiedErrorId = [string]$ErrorRecord.FullyQualifiedErrorId
                scriptStackTrace = [string]$ErrorRecord.ScriptStackTrace
            }
        }

        $event = [ordered]@{
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
            machine = $env:COMPUTERNAME
            user = $env:USERNAME
            userDomain = $env:USERDOMAIN
            isAdmin = Get-ToolkitIsAdmin
            processId = $PID
            powershellVersion = $PSVersionTable.PSVersion.ToString()
            logType = $LogType
            level = $Level
            module = $Module
            action = $Action
            status = $Status
            message = $Message
            data = $Data
            error = $errorInfo
        }

        $json = $event | ConvertTo-Json -Depth 12 -Compress
        Add-Content -Path $logPath -Value $json -Encoding UTF8

        return $true
    }
    catch {
        return $false
    }
}

function Write-ToolkitRuntimeLog {
    param(
        [string]$Module = "Runtime",
        [string]$Action = "None",
        [string]$Status = "Info",
        [string]$Message = "",
        $Data = $null
    )

    Write-ToolkitStructuredLog `
        -LogType "runtime" `
        -Level "INFO" `
        -Module $Module `
        -Action $Action `
        -Status $Status `
        -Message $Message `
        -Data $Data | Out-Null
}

function Write-ToolkitActionLog {
    param(
        [string]$Module = "Action",
        [string]$Action = "None",
        [string]$Status = "Executed",
        [string]$Message = "",
        $Data = $null
    )

    Write-ToolkitStructuredLog `
        -LogType "actions" `
        -Level "INFO" `
        -Module $Module `
        -Action $Action `
        -Status $Status `
        -Message $Message `
        -Data $Data | Out-Null
}

function Write-ToolkitErrorLog {
    param(
        [string]$Module = "Error",
        [string]$Action = "None",
        [string]$Status = "Error",
        [string]$Message = "",
        $ErrorRecord = $null,
        $Data = $null
    )

    Write-ToolkitStructuredLog `
        -LogType "errors" `
        -Level "ERROR" `
        -Module $Module `
        -Action $Action `
        -Status $Status `
        -Message $Message `
        -ErrorRecord $ErrorRecord `
        -Data $Data | Out-Null
}

[xml]$xaml=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="ServiceDesk Toolkit Corporate" Height="820" Width="1380" MinHeight="740" MinWidth="1220" WindowStartupLocation="CenterScreen" Background="#E9EEF5">
<Window.Resources>

    <Style TargetType="Button">
        <Setter Property="Height" Value="38"/>
        <Setter Property="Margin" Value="0,0,0,7"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Background" Value="#F8FAFC"/>
        <Setter Property="Foreground" Value="#0F172A"/>
        <Setter Property="BorderBrush" Value="#CBD5E1"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="Padding" Value="12,0"/>
        <Setter Property="HorizontalContentAlignment" Value="Left"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Border Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}"
                            CornerRadius="10"
                            Padding="{TemplateBinding Padding}">
                        <ContentPresenter VerticalAlignment="Center"
                                          HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"/>
                    </Border>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
        <Style.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#EFF6FF"/>
                <Setter Property="BorderBrush" Value="#60A5FA"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
                <Setter Property="Background" Value="#DBEAFE"/>
            </Trigger>
        </Style.Triggers>
    </Style>

    <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Background" Value="#FFF1F2"/>
        <Setter Property="BorderBrush" Value="#FDA4AF"/>
        <Setter Property="Foreground" Value="#9F1239"/>
        <Style.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#FFE4E6"/>
                <Setter Property="BorderBrush" Value="#FB7185"/>
                <Setter Property="Foreground" Value="#881337"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
                <Setter Property="Background" Value="#FECDD3"/>
            </Trigger>
        </Style.Triggers>
    </Style>

    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Background" Value="#1D4ED8"/>
        <Setter Property="BorderBrush" Value="#1D4ED8"/>
        <Setter Property="Foreground" Value="White"/>
        <Style.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#2563EB"/>
                <Setter Property="BorderBrush" Value="#2563EB"/>
                <Setter Property="Foreground" Value="White"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
                <Setter Property="Background" Value="#1E40AF"/>
                <Setter Property="BorderBrush" Value="#1E40AF"/>
            </Trigger>
        </Style.Triggers>
    </Style>
    <Style TargetType="TextBox">
        <Setter Property="FontFamily" Value="Consolas"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="TextWrapping" Value="Wrap"/>
        <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
        <Setter Property="HorizontalScrollBarVisibility" Value="Auto"/>
        <Setter Property="IsReadOnly" Value="True"/>
        <Setter Property="Background" Value="#F8FAFC"/>
        <Setter Property="BorderBrush" Value="#CBD5E1"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Foreground" Value="#0F172A"/>
        <Setter Property="Padding" Value="12"/>
    </Style>

    <Style TargetType="TabControl">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="BorderBrush" Value="Transparent"/>
        <Setter Property="Padding" Value="0"/>
    </Style>

    <Style TargetType="TabItem">
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="FontSize" Value="11"/>
        <Setter Property="Padding" Value="14,7"/>
        <Setter Property="Margin" Value="0,0,4,0"/>
        <Setter Property="Foreground" Value="#334155"/>
    </Style>

    <Style TargetType="Expander">
        <Setter Property="Margin" Value="0,0,0,10"/>
        <Setter Property="FontWeight" Value="Bold"/>
        <Setter Property="Foreground" Value="#334155"/>
    </Style>

    <Style x:Key="AreaPanel" TargetType="Border">
        <Setter Property="Background" Value="#F8FAFC"/>
        <Setter Property="BorderBrush" Value="#E2E8F0"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="CornerRadius" Value="10"/>
        <Setter Property="Padding" Value="10"/>
        <Setter Property="Margin" Value="0,6,0,0"/>
    </Style>

    <Style x:Key="SidebarGroup" TargetType="Border">
        <Setter Property="Background" Value="#0F1B2D"/>
        <Setter Property="BorderBrush" Value="#1E293B"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="CornerRadius" Value="12"/>
        <Setter Property="Padding" Value="10"/>
        <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>

    <Style x:Key="SidebarSectionTitle" TargetType="TextBlock">
        <Setter Property="Foreground" Value="#93C5FD"/>
        <Setter Property="FontWeight" Value="Bold"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="Margin" Value="0,0,0,8"/>
    </Style>
</Window.Resources>
<Grid><Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
<Border Grid.Column="0" Background="#07111F">
    <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel Margin="14">
            <TextBlock Text="ServiceDesk" Foreground="White" FontSize="22" FontWeight="Bold"/>
            <TextBlock Text="Toolkit" Foreground="#60A5FA" FontSize="22" FontWeight="Bold"/>
            <TextBlock Text="Corporate Toolkit" Foreground="#D0D5DD" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,12"/>

            <Border Background="#0F1B2D" CornerRadius="10" Padding="10" Margin="0,6,0,14">
                <StackPanel>
                    <TextBlock Text="Ambiente" Foreground="#98A2B3" FontSize="12"/>
                    <TextBlock Name="TxtAdminStatus" Foreground="#FACC15" TextWrapping="Wrap" FontSize="12"/>
                </StackPanel>
            </Border>

            <Border Style="{StaticResource SidebarGroup}">
                <StackPanel>
                    <TextBlock Text="Ações principais" Style="{StaticResource SidebarSectionTitle}"/>
                    <Button Name="BtnInventory" Content="Inventário completo"/>
                    <Button Name="BtnNetwork" Content="Diagnóstico rápido de rede"/>
                    <Button Name="BtnFlushDns" Content="Limpar DNS"/>
                    <Button Name="BtnRenewIp" Content="Renovar IP" Style="{StaticResource DangerButton}"/>
                    <Button Name="BtnTimeSync" Content="Sincronizar horário"/>
                    <Button Name="BtnSpooler" Content="Reiniciar spooler"/>
                </StackPanel>
            </Border>

            <Border Style="{StaticResource SidebarGroup}">
                <StackPanel>
                    <TextBlock Text="Windows" Style="{StaticResource SidebarSectionTitle}"/>
                    <Button Name="BtnWindowsUpdate" Content="Abrir Windows Update"/>
                    <Button Name="BtnPrograms" Content="Programas e Recursos"/>
                    <Button Name="BtnDeviceManager" Content="Gerenciador de Dispositivos"/>
                    <Button Name="BtnNetworkConnections" Content="Conexões de Rede"/>
                </StackPanel>
            </Border>

            <Border Style="{StaticResource SidebarGroup}">
                <StackPanel>
                    <TextBlock Text="VPN / Appgate" Style="{StaticResource SidebarSectionTitle}"/>
                    <Button Name="BtnAppgateFix" Content="Corrigir VPN / Appgate"/>
                    <Button Name="BtnAppgateRestart" Content="Reiniciar VPN / Appgate" Style="{StaticResource DangerButton}"/>
                    <Button Name="BtnAppgateStatus" Content="Status VPN / Appgate"/>
                </StackPanel>
            </Border>

            <Border Style="{StaticResource SidebarGroup}">
                <StackPanel>
                    <TextBlock Text="Evidências / Relatórios" Style="{StaticResource SidebarSectionTitle}"/>
                    <Button Name="BtnReportHtml" Content="Gerar relatório visual HTML" Style="{StaticResource PrimaryButton}"/>
                    <Button Name="BtnReportTxt" Content="Gerar relatório técnico TXT"/>
                    <Button Name="BtnOpenReports" Content="Abrir pasta de relatórios"/>
                    <Button Name="BtnToolkitDiagnostic" Content="Gerar diagnóstico do Toolkit" Style="{StaticResource PrimaryButton}" Margin="0,8,0,0"/>
                    <Button Name="BtnValidateToolkitInstalled" Content="Validar instalação do Toolkit" Style="{StaticResource PrimaryButton}"/>
                </StackPanel>
            </Border>

            <Border Style="{StaticResource SidebarGroup}">
                <StackPanel>
                    <TextBlock Text="Administracao do Toolkit" Style="{StaticResource SidebarSectionTitle}"/>
                    <Button Name="BtnToolkitStatus" Content="Status do Toolkit" Style="{StaticResource PrimaryButton}"/>
                    <Button Name="BtnRunToolkitUpdate" Content="Atualizar Toolkit" Style="{StaticResource PrimaryButton}"/>
                    <Button Name="BtnRunRollbackDryRun" Content="Testar rollback dry-run"/>
                    <Button Name="BtnOpenUpdateRollbackLogs" Content="Abrir logs de update/rollback"/>
                    <Button Name="BtnShowToolkitLogSummary" Content="Resumo dos logs do Toolkit" Style="{StaticResource PrimaryButton}"/>
                    <Button Name="BtnOpenLatestUpdateSummary" Content="Abrir último resumo do update" Style="{StaticResource PrimaryButton}"/>
                    <Button Name="BtnExportToolkitSupportPackage" Content="Gerar pacote de suporte" Style="{StaticResource PrimaryButton}"/>
                    <Button Name="BtnOpenBackups" Content="Abrir backups"/>
                    <Button Name="BtnCopyOutput" Content="Copiar resultado"/>
                </StackPanel>
            </Border>
        </StackPanel>
    </ScrollViewer>
</Border>
<Grid Grid.Column="1" Margin="18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
<Border Background="White" CornerRadius="16" Padding="18" Margin="0,0,0,10"><StackPanel><TextBlock Text="Central de Suporte Técnico" FontSize="22" FontWeight="Bold" Foreground="#101828"/><TextBlock Text="Selecione uma área, execute a ação desejada e acompanhe o resultado técnico no painel ao lado." FontSize="13" Foreground="#667085"/></StackPanel></Border>
<Grid Grid.Row="1" Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions><Border Grid.Column="0" Background="White" CornerRadius="16" Padding="18" Margin="0,0,10,0"><StackPanel><TextBlock Text="Hostname" Foreground="#667085" FontSize="12"/><TextBlock Name="CardHostname" Text="-" FontWeight="Bold" FontSize="13" TextWrapping="Wrap"/></StackPanel></Border><Border Grid.Column="1" Background="White" CornerRadius="16" Padding="18" Margin="0,0,10,0"><StackPanel><TextBlock Text="Usuário" Foreground="#667085" FontSize="12"/><TextBlock Name="CardUser" Text="-" FontWeight="Bold" FontSize="13" TextWrapping="Wrap"/></StackPanel></Border><Border Grid.Column="2" Background="White" CornerRadius="16" Padding="18" Margin="0,0,10,0"><StackPanel><TextBlock Text="Windows" Foreground="#667085" FontSize="12"/><TextBlock Name="CardWindows" Text="-" FontWeight="Bold" FontSize="13" TextWrapping="Wrap"/></StackPanel></Border><Border Grid.Column="3" Background="White" CornerRadius="16" Padding="18"><StackPanel><TextBlock Text="IP" Foreground="#667085" FontSize="12"/><TextBlock Name="CardIp" Text="-" FontWeight="Bold" FontSize="13" TextWrapping="Wrap"/></StackPanel></Border></Grid>
<TabControl Name="MainTabs" Grid.Row="2" Background="Transparent" BorderBrush="Transparent">

                
                
                <TabItem Header="Base de Conhecimento">
                    <Border Background="White" CornerRadius="18" Padding="18">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="320"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Column="0" Margin="0,0,14,0">

                                <TextBlock Text="Base de Conhecimento"
                                           FontSize="22"
                                           FontWeight="Bold"
                                           Foreground="#0F172A"
                                           Margin="0,0,0,4"/>

                                <TextBlock Text="Digite um resumo do problema para buscar métodos de resolução cadastrados."
                                           FontSize="12"
                                           Foreground="#64748B"
                                           TextWrapping="Wrap"
                                           Margin="0,0,0,14"/>

                                <Expander Header="Buscar resolução" IsExpanded="True">
                                    <Border Style="{StaticResource AreaPanel}">
                                        <StackPanel>
                                            <TextBlock Text="Resumo do problema"
                                                       Foreground="#64748B"
                                                       FontSize="11"
                                                       FontWeight="SemiBold"
                                                       Margin="0,0,0,4"/>

                                            <TextBox Name="TxtKnowledgeQuery"
                                                     Height="90"
                                                     IsReadOnly="False"
                                                     FontFamily="Segoe UI"
                                                     FontSize="12"
                                                     TextWrapping="Wrap"
                                                     AcceptsReturn="True"
                                                     VerticalScrollBarVisibility="Auto"
                                                     Margin="0,0,0,8"/>

                                            <Button Name="BtnKnowledgeSearch"
                                                    Content="Buscar resolução"
                                                    Style="{StaticResource PrimaryButton}"/>

                                            <Button Name="BtnKnowledgeSummary"
                                                    Content="Ver artigos cadastrados"/>

                                            <Button Name="BtnOpenKnowledgeBaseFile"
                                                    Content="Abrir base JSON"/>
                                        </StackPanel>
                                    </Border>
                                </Expander>

                                <Expander Header="Exemplos de busca" IsExpanded="False">
                                    <Border Style="{StaticResource AreaPanel}">
                                        <StackPanel>
                                            <TextBlock Text="teams não abre"
                                                       Foreground="#334155"
                                                       FontSize="12"
                                                       Margin="0,0,0,4"/>
                                            <TextBlock Text="outlook pedindo senha"
                                                       Foreground="#334155"
                                                       FontSize="12"
                                                       Margin="0,0,0,4"/>
                                            <TextBlock Text="impressora offline"
                                                       Foreground="#334155"
                                                       FontSize="12"
                                                       Margin="0,0,0,4"/>
                                            <TextBlock Text="appgate não conecta"
                                                       Foreground="#334155"
                                                       FontSize="12"
                                                       Margin="0,0,0,4"/>
                                            <TextBlock Text="dns não resolve"
                                                       Foreground="#334155"
                                                       FontSize="12"/>
                                        </StackPanel>
                                    </Border>
                                </Expander>

                            </StackPanel>

                            <TextBox Name="TxtKnowledgeOutput"
                                     Grid.Column="1"
                                     MinHeight="460"/>
                        </Grid>
                    </Border>
                </TabItem>
                <TabItem Header="Atendimento Rápido">
                    <Border Background="White" CornerRadius="18" Padding="22">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                            </Grid.RowDefinitions>

                            <StackPanel Grid.Row="0" Margin="0,0,0,16">
                                <TextBlock Text="Atendimento Rápido"
                                           FontSize="24"
                                           FontWeight="Bold"
                                           Foreground="#0F172A"/>

                                <TextBlock Text="Escolha o tipo de problema. O toolkit executa uma coleta segura de diagnóstico e mostra sugestões para o atendimento."
                                           FontSize="13"
                                           Foreground="#64748B"
                                           TextWrapping="Wrap"
                                           Margin="0,4,0,0"/>
                            </StackPanel>

                            <Grid Grid.Row="1">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="320"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto" Margin="0,0,18,0">
                                    <StackPanel>

                                        <TextBlock Text="Cenários comuns"
                                                   Foreground="#667085"
                                                   FontSize="12"
                                                   FontWeight="SemiBold"
                                                   Margin="0,0,0,8"/>

                                        <Button Name="BtnQuickInternet"
                                                Height="48"
                                                Content="Problema de Internet / Rede"
                                                Style="{StaticResource PrimaryButton}"/>

                                        <Button Name="BtnQuickTeams"
                                                Height="48"
                                                Content="Problema no Teams"/>

                                        <Button Name="BtnQuickOutlook"
                                                Height="48"
                                                Content="Problema no Outlook"/>

                                        <Button Name="BtnQuickOneDrive"
                                                Height="48"
                                                Content="Problema no OneDrive"/>

                                        <Button Name="BtnQuickPrinter"
                                                Height="48"
                                                Content="Problema de Impressora"/>

                                        <Button Name="BtnQuickWindowsUpdate"
                                                Height="48"
                                                Content="Problema no Windows Update"/>

                                        <Button Name="BtnQuickAppgate"
                                                Height="48"
                                                Content="Problema no Appgate / VPN"/>

                                        <Button Name="BtnQuickFullReport"
                                                Height="48"
                                                Content="Gerar relatório geral"
                                                Style="{StaticResource PrimaryButton}"/>

                                        <TextBlock Text="Esses botões fazem diagnóstico e coleta de evidências. Reparos críticos continuam nas abas específicas e pedem confirmação."
                                                   Foreground="#667085"
                                                   FontSize="11"
                                                   TextWrapping="Wrap"
                                                   Margin="0,14,0,0"/>
                                    </StackPanel>
                                </ScrollViewer>

                                <TextBox Name="TxtQuickSupportOutput"
                                         Grid.Column="1"
                                         MinHeight="460"/>
                            </Grid>
                        </Grid>
                    </Border>
                </TabItem>
                <TabItem Header="Visão Geral">
                    <Border Background="White" CornerRadius="18" Padding="22">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <StackPanel>

                                <TextBlock Text="Visão Geral do Toolkit"
                                           FontSize="24"
                                           FontWeight="Bold"
                                           Foreground="#0F172A"
                                           Margin="0,0,0,4"/>

                                <TextBlock Text="Escolha uma área abaixo para orientar o atendimento. As ações técnicas continuam disponíveis nas abas específicas."
                                           FontSize="13"
                                           Foreground="#64748B"
                                           TextWrapping="Wrap"
                                           Margin="0,0,0,20"/>

                                <UniformGrid Columns="3" Rows="3">
                            <Border Background="#EFF6FF" BorderBrush="#93C5FD" BorderThickness="1" CornerRadius="16" Padding="16" Margin="8">
                                <StackPanel>
                                    <TextBlock Text="Base de Conhecimento" FontSize="16" FontWeight="Bold" Foreground="#0F172A"/>
                                    <TextBlock Text="Buscar métodos de resolução por resumo do problema." FontSize="12" Foreground="#475569" TextWrapping="Wrap" Margin="0,4,0,12"/>
                                    <Button Name="BtnHomeKnowledge" Content="Abrir Base de Conhecimento" Style="{StaticResource PrimaryButton}"/>
                                </StackPanel>
                            </Border>


                                    <Border Background="#EFF6FF" BorderBrush="#BFDBFE" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,14,14">
                                        <StackPanel>
                                            <TextBlock Text="Rede" FontSize="18" FontWeight="Bold" Foreground="#1E3A8A"/>
                                            <TextBlock Text="Diagnóstico, DNS, rotas, gateway, internet, reset TCP/IP e Winsock."
                                                       Foreground="#475569" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,12"/>
                                            <Button Name="BtnHomeNetwork" Content="Abrir Rede Avançada" Style="{StaticResource PrimaryButton}"/>
                                        </StackPanel>
                                    </Border>

                                    <Border Background="#F8FAFC" BorderBrush="#CBD5E1" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,14,14">
                                        <StackPanel>
                                            <TextBlock Text="Windows / Reparo" FontSize="18" FontWeight="Bold" Foreground="#0F172A"/>
                                            <TextBlock Text="Windows Update, DISM, SFC, temporários, horário e eventos críticos."
                                                       Foreground="#475569" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,12"/>
                                            <Button Name="BtnHomeWindowsRepair" Content="Abrir Windows / Reparo"/>
                                        </StackPanel>
                                    </Border>

                                    <Border Background="#F0FDF4" BorderBrush="#BBF7D0" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,0,14">
                                        <StackPanel>
                                            <TextBlock Text="VPN / Appgate" FontSize="18" FontWeight="Bold" Foreground="#166534"/>
                                            <TextBlock Text="Correção de timeout, status de configuração, serviços e reinício do Appgate."
                                                       Foreground="#475569" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,12"/>
                                            <Button Name="BtnHomeAppgate" Content="Abrir VPN / Appgate"/>
                                        </StackPanel>
                                    </Border>

                                    <Border Background="#F5F3FF" BorderBrush="#DDD6FE" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,14,14">
                                        <StackPanel>
                                            <TextBlock Text="Office / Teams" FontSize="18" FontWeight="Bold" Foreground="#5B21B6"/>
                                            <TextBlock Text="Cache do Teams, credenciais, contas Windows, Office Identity e reparo Office."
                                                       Foreground="#475569" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,12"/>
                                            <Button Name="BtnHomeTeamsOffice" Content="Abrir Teams / Office"/>
                                        </StackPanel>
                                    </Border>

                                    <Border Background="#FFF7ED" BorderBrush="#FED7AA" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,14,14">
                                        <StackPanel>
                                            <TextBlock Text="Store / Apps" FontSize="18" FontWeight="Bold" Foreground="#9A3412"/>
                                            <TextBlock Text="Microsoft Store, apps instalados, reset da Store e reparo de apps Windows."
                                                       Foreground="#475569" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,12"/>
                                            <Button Name="BtnHomeStoreApps" Content="Abrir Store / Apps"/>
                                        </StackPanel>
                                    </Border>

                                    <Border Background="#ECFEFF" BorderBrush="#A5F3FC" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,0,14">
                                        <StackPanel>
                                            <TextBlock Text="Impressoras" FontSize="18" FontWeight="Bold" Foreground="#155E75"/>
                                            <TextBlock Text="Spooler, fila de impressão, impressoras instaladas, padrão e offline."
                                                       Foreground="#475569" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,12"/>
                                            <Button Name="BtnHomePrinters" Content="Abrir Impressoras"/>
                                        </StackPanel>
                                    </Border>

                                    <Border Background="#FEF2F2" BorderBrush="#FECACA" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,14,0">
                                        <StackPanel>
                                            <TextBlock Text="Segurança" FontSize="18" FontWeight="Bold" Foreground="#991B1B"/>
                                            <TextBlock Text="TPM, BitLocker, Defender, UAC e administradores locais."
                                                       Foreground="#475569" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,12"/>
                                            <Button Name="BtnHomeSecurity" Content="Abrir Segurança"/>
                                        </StackPanel>
                                    </Border>

                                    <Border Background="#F1F5F9" BorderBrush="#CBD5E1" BorderThickness="1" CornerRadius="16" Padding="18" Margin="0,0,14,0">
                                        <StackPanel>
                                            <TextBlock Text="GPO / Sistema" FontSize="18" FontWeight="Bold" Foreground="#334155"/>
                                            <TextBlock Text="gpupdate, gpresult, serviços automáticos parados e eventos do sistema."
                                                       Foreground="#475569" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,12"/>
                                            <Button Name="BtnHomeSystem" Content="Abrir GPO / Sistema"/>
                                        </StackPanel>
                                    </Border>

                                    <Border Background="#EFF6FF" BorderBrush="#BFDBFE" BorderThickness="1" CornerRadius="16" Padding="18">
                                        <StackPanel>
                                            <TextBlock Text="Relatórios" FontSize="18" FontWeight="Bold" Foreground="#1D4ED8"/>
                                            <TextBlock Text="Gere evidências técnicas em HTML ou TXT para anexar em chamados."
                                                       Foreground="#475569" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,12"/>
                                            <Button Name="BtnHomeReports" Content="Gerar Relatório HTML" Style="{StaticResource PrimaryButton}"/>
</StackPanel>
                                    </Border>

                                </UniformGrid>
                            </StackPanel>
                        </ScrollViewer>
                    </Border>
                </TabItem>
                <TabItem Header="Resultado"><Border Background="White" CornerRadius="16" Padding="18"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><TextBlock Text="Saída da execução" FontSize="17" FontWeight="Bold" Margin="0,0,0,8"/><TextBox MinHeight="460" Name="TxtOutput" Grid.Row="1"/></Grid></Border></TabItem>
<TabItem Header="Segurança"><Border Background="White" CornerRadius="16" Padding="18"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0" Margin="0,0,18,0"><Button Name="BtnTpm" Content="Verificar TPM"/><Button Name="BtnBitLocker" Content="Verificar BitLocker"/><Button Name="BtnDefender" Content="Windows Defender"/><Button Name="BtnUac" Content="Verificar UAC"/><Button Name="BtnAdmins" Content="Administradores locais"/></StackPanel><TextBox MinHeight="460" Name="TxtSecurityOutput" Grid.Column="1"/></Grid></Border></TabItem>
                <TabItem Header="Rede Avançada">
                    <Border Background="White" CornerRadius="18" Padding="18">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="230"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto" Margin="0,0,14,0">
                                <StackPanel>

                                    <Expander Header="Diagnóstico" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnAdvancedNetworkStatus" Content="Status IP completo"/>
                                                <Button Name="BtnDnsConfiguration" Content="Ver DNS"/>
                                                <Button Name="BtnNetworkRoutes" Content="Ver rotas"/>
                                                <Button Name="BtnTestGateway" Content="Teste Gateway"/>
                                                <Button Name="BtnTestInternetAdvanced" Content="Teste Internet" Style="{StaticResource PrimaryButton}"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Correções" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnFlushDnsAdvanced" Content="Flush DNS"/>
                                                <Button Name="BtnReleaseRenewAdvanced" Content="Release/Renew IP"/>
                                                <Button Name="BtnResetWinsock" Content="Reset Winsock" Style="{StaticResource DangerButton}"/>
                                                <Button Name="BtnResetTcpIp" Content="Reset TCP/IP" Style="{StaticResource DangerButton}"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Ferramentas" IsExpanded="False">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnOpenNetworkConnectionsAdvanced" Content="Conexões de Rede"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                </StackPanel>
                            </ScrollViewer>

                            <TextBox Name="TxtAdvancedNetworkOutput" Grid.Column="1" MinHeight="460"/>
                        </Grid>
                    </Border>
                </TabItem>
                <TabItem Header="Apps Corporativos">
                    <Border Background="White" CornerRadius="18" Padding="18">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="230"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto" Margin="0,0,14,0">
                                <StackPanel>

                                    <Expander Header="Diagnóstico" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnCorporateAppsStatus" Content="Status Apps"/>
                                                <Button Name="BtnAllCorporateAppErrors" Content="Erros gerais" Style="{StaticResource PrimaryButton}"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Apps" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnOutlookErrors" Content="Outlook"/>
                                                <Button Name="BtnTeamsErrors" Content="Teams"/>
                                                <Button Name="BtnOneDriveErrors" Content="OneDrive"/>
                                                <Button Name="BtnScreenshotErrors" Content="Captura de Tela"/>
                                                <Button Name="BtnWhatsAppErrors" Content="WhatsApp"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Ferramentas Windows" IsExpanded="False">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnOpenReliabilityMonitor" Content="Monitor Confiabilidade"/>
                                                <Button Name="BtnOpenEventViewerApplication" Content="Eventos Windows"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                </StackPanel>
                            </ScrollViewer>

                            <TextBox Name="TxtCorporateAppsOutput" Grid.Column="1" MinHeight="460"/>
                        </Grid>
                    </Border>
                </TabItem>
                <TabItem Header="Microsoft Store / Apps">
                    <Border Background="White" CornerRadius="18" Padding="18">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="230"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto" Margin="0,0,14,0">
                                <StackPanel>

                                    <Expander Header="Diagnóstico" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnStoreAppsStatus" Content="Status Store / Apps"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Correções" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnRestartMicrosoftStore" Content="Reiniciar Store"/>
                                                <Button Name="BtnResetMicrosoftStore" Content="Resetar Store"/>
                                                <Button Name="BtnRepairMicrosoftStore" Content="Reparar Store"/>
                                                <Button Name="BtnRepairWindowsApps" Content="Reparar Apps Windows" Style="{StaticResource DangerButton}"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Ferramentas" IsExpanded="False">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnOpenInstalledApps" Content="Apps Instalados"/>
                                                <Button Name="BtnOpenMicrosoftStore" Content="Microsoft Store"/>
                                                <Button Name="BtnOpenOfficeTeamsRepair" Content="Reparo Office / Teams"/>
                                                <Button Name="BtnOpenStoreTroubleshoot" Content="Solução de Problemas"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                </StackPanel>
                            </ScrollViewer>

                            <TextBox Name="TxtStoreAppsOutput" Grid.Column="1" MinHeight="460"/>
                        </Grid>
                    </Border>
                </TabItem>
                <TabItem Header="Teams / Office">
                    <Border Background="White" CornerRadius="18" Padding="18">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="230"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto" Margin="0,0,14,0">
                                <StackPanel>

                                    <Expander Header="Diagnóstico" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnTeamsOfficeStatus" Content="Status"/>
                                                <Button Name="BtnOfficeIdentityKeys" Content="Office Identity"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Correções" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnCloseTeamsOffice" Content="Fechar Teams/Office"/>
                                                <Button Name="BtnClearClassicTeamsCache" Content="Limpar Teams clássico"/>
                                                <Button Name="BtnClearNewTeamsCache" Content="Limpar Novo Teams"/>
                                                <Button Name="BtnOpenOfficeRepair" Content="Reparo Office" Style="{StaticResource PrimaryButton}"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Ferramentas" IsExpanded="False">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnOpenTeamsFolder" Content="Pasta Teams"/>
                                                <Button Name="BtnOpenCredentialManager" Content="Credential Manager"/>
                                                <Button Name="BtnOpenAccountsSettings" Content="Contas Windows"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                </StackPanel>
                            </ScrollViewer>

                            <TextBox Name="TxtTeamsOfficeOutput" Grid.Column="1" MinHeight="460"/>
                        </Grid>
                    </Border>
                </TabItem>
                <TabItem Header="Impressoras">
                    <Border Background="White" CornerRadius="18" Padding="18">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="230"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto" Margin="0,0,14,0">
                                <StackPanel>

                                    <Expander Header="Diagnóstico" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnPrinterStatus" Content="Status Impressoras"/>
                                                <Button Name="BtnPrinterList" Content="Listar impressoras"/>
                                                <Button Name="BtnPrintJobs" Content="Fila de impressão"/>
                                                <Button Name="BtnDefaultPrinter" Content="Impressora padrão"/>
                                                <Button Name="BtnOfflinePrinters" Content="Impressoras offline"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Correções" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnRestartSpoolerAdvanced" Content="Reiniciar Spooler"/>
                                                <Button Name="BtnClearPrintQueue" Content="Limpar fila" Style="{StaticResource DangerButton}"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Ferramentas" IsExpanded="False">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnOpenPrintersSettings" Content="Abrir Impressoras"/>
                                                <Button Name="BtnOpenPrintManagement" Content="Gerenc. Impressão"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                </StackPanel>
                            </ScrollViewer>

                            <TextBox Name="TxtPrintersOutput" Grid.Column="1" MinHeight="460"/>
                        </Grid>
                    </Border>
                </TabItem>
                <TabItem Header="Windows / Reparo">
                    <Border Background="White" CornerRadius="18" Padding="18">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="230"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto" Margin="0,0,14,0">
                                <StackPanel>

                                    <Expander Header="Diagnóstico" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnWinRepairStatus" Content="Status Windows"/>
                                                <Button Name="BtnOpenWindowsUpdateRepair" Content="Windows Update"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Windows Update" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnRestartWU" Content="Reiniciar serviços WU"/>
                                                <Button Name="BtnClearWUCache" Content="Limpar cache WU" Style="{StaticResource DangerButton}"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Reparo do Sistema" IsExpanded="True">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnDismOnly" Content="DISM RestoreHealth" Style="{StaticResource DangerButton}"/>
                                                <Button Name="BtnSfcOnly" Content="SFC Scannow" Style="{StaticResource DangerButton}"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                    <Expander Header="Manutenção" IsExpanded="False">
                                        <Border Style="{StaticResource AreaPanel}">
                                            <StackPanel>
                                                <Button Name="BtnClearUserTemp" Content="Limpar temporários"/>
                                                <Button Name="BtnTimeSyncRepair" Content="Sincronizar horário"/>
                                            </StackPanel>
                                        </Border>
                                    </Expander>

                                </StackPanel>
                            </ScrollViewer>

                            <TextBox Name="TxtWindowsRepairOutput" Grid.Column="1" MinHeight="460"/>
                        </Grid>
                    </Border>
                </TabItem>
<TabItem Header="TPM / Office"><Border Background="White" CornerRadius="16" Padding="18"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0" Margin="0,0,18,0"><TextBlock Text="Ajustes TPM / Office" Foreground="#667085" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,8"/><Button Name="BtnTpmOfficeFix" Content="Ajuste TPM 2"/><Button Name="BtnTpmBrokenPlugin" Content="Limpar BrokenPlugin"/><Button Name="BtnDismSfcRepair" Content="Reparo DISM + SFC" Style="{StaticResource DangerButton}"/><Button Name="BtnTpmOfficeStatus" Content="Status TPM / Office"/><TextBlock Text="Observação: alguns ajustes exigem reinício do computador." Foreground="#667085" FontSize="11" TextWrapping="Wrap" Margin="0,12,0,0"/></StackPanel><TextBox MinHeight="460" Name="TxtTpmOfficeOutput" Grid.Column="1"/></Grid></Border></TabItem>
<TabItem Header="GPO / Sistema"><Border Background="White" CornerRadius="16" Padding="18"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><StackPanel Grid.Column="0" Margin="0,0,18,0"><Button Name="BtnGpUpdate" Content="Executar gpupdate /force"/><Button Name="BtnGpResult" Content="Gerar gpresult HTML"/><Button Name="BtnStoppedServices" Content="Serviços automáticos parados"/><Button Name="BtnCriticalEvents" Content="Eventos últimas 24h"/></StackPanel><TextBox MinHeight="460" Name="TxtSystemOutput" Grid.Column="1"/></Grid></Border></TabItem>
<TabItem Header="Teste TCP"><Border Background="White" CornerRadius="16" Padding="18"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions><StackPanel Orientation="Horizontal" Margin="0,0,0,10"><StackPanel Width="220" Margin="0,0,12,0"><TextBlock Text="Host ou IP" Foreground="#667085"/><TextBox Name="InputTcpHost" IsReadOnly="False" Height="30" Text="google.com"/></StackPanel><StackPanel Width="120" Margin="0,0,12,0"><TextBlock Text="Porta" Foreground="#667085"/><TextBox Name="InputTcpPort" IsReadOnly="False" Height="30" Text="443"/></StackPanel><Button Name="BtnTcpTest" Content="Testar porta" Width="120" Margin="0,18,0,0"/></StackPanel><TextBox MinHeight="460" Name="TxtTcpOutput" Grid.Row="1"/></Grid></Border></TabItem>
</TabControl></Grid></Grid></Window>
"@

$reader=New-Object System.Xml.XmlNodeReader $xaml
$window=[Windows.Markup.XamlReader]::Load($reader)



# Visão Geral - Base de Conhecimento
$script:MainTabs = $window.FindName("MainTabs")
$BtnHomeKnowledge = $window.FindName("BtnHomeKnowledge")


# Base de Conhecimento
$TxtKnowledgeQuery = $window.FindName("TxtKnowledgeQuery")
$TxtKnowledgeOutput = $window.FindName("TxtKnowledgeOutput")
$BtnKnowledgeSearch = $window.FindName("BtnKnowledgeSearch")
$BtnKnowledgeSummary = $window.FindName("BtnKnowledgeSummary")
$BtnOpenKnowledgeBaseFile = $window.FindName("BtnOpenKnowledgeBaseFile")



function Test-ToolkitAdmin {
    return Test-Admin
}

# Teams / Office
$BtnTeamsOfficeStatus = $window.FindName("BtnTeamsOfficeStatus")
$BtnCloseTeamsOffice = $window.FindName("BtnCloseTeamsOffice")
$BtnClearClassicTeamsCache = $window.FindName("BtnClearClassicTeamsCache")
$BtnClearNewTeamsCache = $window.FindName("BtnClearNewTeamsCache")
$BtnOpenTeamsFolder = $window.FindName("BtnOpenTeamsFolder")
$BtnOpenCredentialManager = $window.FindName("BtnOpenCredentialManager")
$BtnOpenAccountsSettings = $window.FindName("BtnOpenAccountsSettings")
$BtnOpenOfficeRepair = $window.FindName("BtnOpenOfficeRepair")
$BtnOfficeIdentityKeys = $window.FindName("BtnOfficeIdentityKeys")
$TxtTeamsOfficeOutput = $window.FindName("TxtTeamsOfficeOutput")

# Microsoft Store / Apps
$BtnStoreAppsStatus = $window.FindName("BtnStoreAppsStatus")
$BtnRestartMicrosoftStore = $window.FindName("BtnRestartMicrosoftStore")
$BtnResetMicrosoftStore = $window.FindName("BtnResetMicrosoftStore")
$BtnRepairMicrosoftStore = $window.FindName("BtnRepairMicrosoftStore")
$BtnRepairWindowsApps = $window.FindName("BtnRepairWindowsApps")
$BtnOpenInstalledApps = $window.FindName("BtnOpenInstalledApps")
$BtnOpenMicrosoftStore = $window.FindName("BtnOpenMicrosoftStore")
$BtnOpenOfficeTeamsRepair = $window.FindName("BtnOpenOfficeTeamsRepair")
$BtnOpenStoreTroubleshoot = $window.FindName("BtnOpenStoreTroubleshoot")
$TxtStoreAppsOutput = $window.FindName("TxtStoreAppsOutput")

# Apps Corporativos
$BtnCorporateAppsStatus = $window.FindName("BtnCorporateAppsStatus")
$BtnAllCorporateAppErrors = $window.FindName("BtnAllCorporateAppErrors")
$BtnOutlookErrors = $window.FindName("BtnOutlookErrors")
$BtnTeamsErrors = $window.FindName("BtnTeamsErrors")
$BtnOneDriveErrors = $window.FindName("BtnOneDriveErrors")
$BtnScreenshotErrors = $window.FindName("BtnScreenshotErrors")
$BtnWhatsAppErrors = $window.FindName("BtnWhatsAppErrors")
$BtnOpenReliabilityMonitor = $window.FindName("BtnOpenReliabilityMonitor")
$BtnOpenEventViewerApplication = $window.FindName("BtnOpenEventViewerApplication")
$TxtCorporateAppsOutput = $window.FindName("TxtCorporateAppsOutput")

# Atendimento Rápido
$BtnQuickInternet = $window.FindName("BtnQuickInternet")
$BtnQuickTeams = $window.FindName("BtnQuickTeams")
$BtnQuickOutlook = $window.FindName("BtnQuickOutlook")
$BtnQuickOneDrive = $window.FindName("BtnQuickOneDrive")
$BtnQuickPrinter = $window.FindName("BtnQuickPrinter")
$BtnQuickWindowsUpdate = $window.FindName("BtnQuickWindowsUpdate")
$BtnQuickAppgate = $window.FindName("BtnQuickAppgate")
$BtnQuickFullReport = $window.FindName("BtnQuickFullReport")
$TxtQuickSupportOutput = $window.FindName("TxtQuickSupportOutput")



# Rede Avançada
$BtnAdvancedNetworkStatus = $window.FindName("BtnAdvancedNetworkStatus")
$BtnDnsConfiguration = $window.FindName("BtnDnsConfiguration")
$BtnNetworkRoutes = $window.FindName("BtnNetworkRoutes")
$BtnTestGateway = $window.FindName("BtnTestGateway")
$BtnTestInternetAdvanced = $window.FindName("BtnTestInternetAdvanced")
$BtnFlushDnsAdvanced = $window.FindName("BtnFlushDnsAdvanced")
$BtnReleaseRenewAdvanced = $window.FindName("BtnReleaseRenewAdvanced")
$BtnResetWinsock = $window.FindName("BtnResetWinsock")
$BtnResetTcpIp = $window.FindName("BtnResetTcpIp")
$BtnOpenNetworkConnectionsAdvanced = $window.FindName("BtnOpenNetworkConnectionsAdvanced")
$TxtAdvancedNetworkOutput = $window.FindName("TxtAdvancedNetworkOutput")


# Impressoras
$BtnPrinterStatus = $window.FindName("BtnPrinterStatus")
$BtnPrinterList = $window.FindName("BtnPrinterList")
$BtnPrintJobs = $window.FindName("BtnPrintJobs")
$BtnRestartSpoolerAdvanced = $window.FindName("BtnRestartSpoolerAdvanced")
$BtnClearPrintQueue = $window.FindName("BtnClearPrintQueue")
$BtnDefaultPrinter = $window.FindName("BtnDefaultPrinter")
$BtnOfflinePrinters = $window.FindName("BtnOfflinePrinters")
$BtnOpenPrintersSettings = $window.FindName("BtnOpenPrintersSettings")
$BtnOpenPrintManagement = $window.FindName("BtnOpenPrintManagement")
$TxtPrintersOutput = $window.FindName("TxtPrintersOutput")


# Find names
$names='BtnInventory','BtnNetwork','BtnFlushDns','BtnRenewIp','BtnTimeSync','BtnSpooler','BtnWindowsUpdate','BtnPrograms','BtnDeviceManager','BtnNetworkConnections','BtnAppgateFix','BtnAppgateRestart','BtnAppgateStatus','BtnReportHtml','BtnReportTxt','BtnOpenReports','BtnToolkitDiagnostic','BtnValidateToolkitInstalled','BtnToolkitStatus','BtnRunToolkitUpdate','BtnRunRollbackDryRun','BtnOpenUpdateRollbackLogs','BtnShowToolkitLogSummary','BtnOpenLatestUpdateSummary','BtnExportToolkitSupportPackage','BtnOpenBackups','BtnCopyOutput','TxtOutput','TxtAdminStatus','CardHostname','CardUser','CardWindows','CardIp','BtnTpm','BtnBitLocker','BtnDefender','BtnUac','BtnAdmins','TxtSecurityOutput','BtnWinRepairStatus','BtnOpenWindowsUpdateRepair','BtnRestartWU','BtnClearWUCache','BtnDismOnly','BtnSfcOnly','BtnClearUserTemp','BtnTimeSyncRepair','TxtWindowsRepairOutput','BtnTpmOfficeFix','BtnTpmBrokenPlugin','BtnDismSfcRepair','BtnTpmOfficeStatus','TxtTpmOfficeOutput','BtnGpUpdate','BtnGpResult','BtnStoppedServices','BtnCriticalEvents','TxtSystemOutput','InputTcpHost','InputTcpPort','BtnTcpTest','TxtTcpOutput'
foreach($n in $names){ Set-Variable -Name $n -Value ($window.FindName($n)) -Scope Script }

if(Test-Admin){$TxtAdminStatus.Text='Executando como administrador.'}else{$TxtAdminStatus.Text='Atenção: não está como administrador. Algumas funções podem falhar.'}
try{$i=Get-InventoryObj;if($i -isnot [string]){$CardHostname.Text=$i.Hostname;$CardUser.Text=$i.Usuario;$CardWindows.Text=$i.Windows;$CardIp.Text=$i.IP}}catch{}

# main events
$BtnInventory.Add_Click({
    try { Write-ToolkitActionLog -Module "Overview" -Action "Inventory" -Status "Started" -Message "Inventario da maquina solicitado." } catch {}OutText (Get-InventoryText)})
$BtnNetwork.Add_Click({
    try { Write-ToolkitActionLog -Module "Network" -Action "BasicNetworkTest" -Status "Started" -Message "Teste basico de rede iniciado." } catch {}OutText (Test-NetworkBasic)})
$BtnFlushDns.Add_Click({
    try { Write-ToolkitActionLog -Module "Network" -Action "FlushDns" -Status "Started" -Message "Flush DNS iniciado." } catch {}OutText (Invoke-FlushDns)})
$BtnRenewIp.Add_Click({
    try { Write-ToolkitActionLog -Module "Network" -Action "RenewIp" -Status "Started" -Message "Renovacao de IP solicitada." } catch {}if([System.Windows.MessageBox]::Show('Renovar IP pode derrubar a conexão temporariamente. Continuar?','Renovar IP','YesNo','Warning') -eq 'Yes'){OutText (Invoke-RenewIp)}})
$BtnTimeSync.Add_Click({
    try { Write-ToolkitActionLog -Module "System" -Action "TimeSync" -Status "Started" -Message "Sincronizacao de horario iniciada." } catch {}OutText (Invoke-TimeSync)})
$BtnSpooler.Add_Click({
    try { Write-ToolkitActionLog -Module "Printers" -Action "RestartSpooler" -Status "Started" -Message "Reinicio do spooler solicitado." } catch {}OutText (Invoke-SpoolerRestart)})
$BtnWindowsUpdate.Add_Click({
    try { Write-ToolkitActionLog -Module "Windows" -Action "OpenWindowsUpdate" -Status "Started" -Message "Abertura do Windows Update solicitada." } catch {}Start-Process 'ms-settings:windowsupdate';OutText 'Windows Update aberto.'})
$BtnPrograms.Add_Click({
    try { Write-ToolkitActionLog -Module "Windows" -Action "OpenProgramsAndFeatures" -Status "Started" -Message "Abertura de Programas e Recursos solicitada." } catch {}Start-Process 'appwiz.cpl';OutText 'Programas e Recursos aberto.'})
$BtnDeviceManager.Add_Click({
    try { Write-ToolkitActionLog -Module "Windows" -Action "OpenDeviceManager" -Status "Started" -Message "Abertura do Gerenciador de Dispositivos solicitada." } catch {}Start-Process 'devmgmt.msc';OutText 'Gerenciador de Dispositivos aberto.'})
$BtnNetworkConnections.Add_Click({
    try { Write-ToolkitActionLog -Module "Network" -Action "OpenNetworkConnections" -Status "Started" -Message "Abertura de Conexoes de Rede solicitada." } catch {}Start-Process 'ncpa.cpl';OutText 'Conexões de Rede aberto.'})
$BtnAppgateFix.Add_Click({
    try { Write-ToolkitActionLog -Module "Appgate" -Action "AppgateFix" -Status "Started" -Message "Correcao Appgate/UAC solicitada." } catch {}if([System.Windows.MessageBox]::Show('Alterar config do Appgate e UAC para 5?','Corrigir Appgate','YesNo','Warning') -eq 'Yes'){OutText (Invoke-ToolkitProtectedAppgateFix)}})
$BtnAppgateRestart.Add_Click({
    try { Write-ToolkitActionLog -Module "Appgate" -Action "AppgateRestart" -Status "Started" -Message "Reinicio de processos e servicos Appgate solicitado." } catch {}if([System.Windows.MessageBox]::Show('Reiniciar processos/serviços Appgate? A VPN pode cair.','Reiniciar Appgate','YesNo','Warning') -eq 'Yes'){OutText (Restart-Appgate)}})
$BtnAppgateStatus.Add_Click({
    try { Write-ToolkitActionLog -Module "Appgate" -Action "AppgateStatus" -Status "Started" -Message "Consulta de status Appgate solicitada." } catch {}OutText (Get-AppgateStatus)})
$BtnReportHtml.Add_Click({
    try { Write-ToolkitActionLog -Module "Reports" -Action "ExportReportHtml" -Status "Started" -Message "Exportacao de relatorio HTML solicitada." } catch {}OutText (Export-ReportHtml)})
$BtnReportTxt.Add_Click({
    try { Write-ToolkitActionLog -Module "Reports" -Action "ExportReportTxt" -Status "Started" -Message "Exportacao de relatorio TXT solicitada." } catch {}OutText (Export-ReportTxt)})
$BtnOpenReports.Add_Click({
    try { Write-ToolkitActionLog -Module "Reports" -Action "OpenReportsFolder" -Status "Started" -Message "Abertura da pasta de relatorios solicitada." } catch {}Start-Process $Reports;OutText "Pasta aberta: $Reports"})
if ($null -ne $BtnToolkitDiagnostic) {
    $BtnToolkitDiagnostic.Add_Click({
        try {
            Write-ToolkitActionLog `
                -Module "Reports" `
                -Action "GenerateToolkitDiagnostic" `
                -Status "Started" `
                -Message "Diagnostico automatico do Toolkit solicitado."
        }
        catch {}

        try {
            $toolkitRoot = Get-ToolkitRootPath
            $diagnosticReports = Join-Path $toolkitRoot "reports"
            $diagnosticScript = Join-Path $toolkitRoot "tools\Get-ToolkitDiagnostic.ps1"

            if (!(Test-Path $diagnosticScript)) {
                OutText "Ferramenta de diagnostico não encontrada.`r`n`r`nArquivo esperado:`r`n$diagnosticScript"
                return
            }

            $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

            if (!(Test-Path $psExe)) {
                $psExe = "powershell.exe"
            }

            $diagnosticOutput = & $psExe `
                -NoProfile `
                -ExecutionPolicy Bypass `
                -File $diagnosticScript `
                -ToolkitRoot $toolkitRoot `
                -OpenReport 2>&1 | Out-String

            $latestDiagnostic = Get-ChildItem $diagnosticReports -Filter "diagnostic-*.txt" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

            if ($null -ne $latestDiagnostic) {
                OutText "Diagnostico gerado com sucesso.`r`n`r`nArquivo:`r`n$($latestDiagnostic.FullName)`r`n`r`nSaida:`r`n$diagnosticOutput"
            }
            else {
                OutText "Comando de diagnostico executado, mas nenhum TXT foi encontrado em:`r`n$diagnosticReports`r`n`r`nSaida:`r`n$diagnosticOutput"
            }
        }
        catch {
            try {
                Write-ToolkitErrorLog `
                    -Module "Reports" `
                    -Action "GenerateToolkitDiagnostic" `
                    -Status "Failed" `
                    -Message "Falha ao gerar diagnostico automatico do Toolkit." `
                    -ErrorRecord $_
            }
            catch {}

            OutText "Erro ao gerar diagnostico do Toolkit:`r`n$($_.Exception.Message)"
        }
    })
}

if ($null -ne $BtnToolkitStatus) {
    $BtnToolkitStatus.Add_Click({
        $toolkitRoot = "C:\ServiceDeskToolkit"
        $versionPath = Join-Path $toolkitRoot "version.json"
        $sourceRefPath = Join-Path $toolkitRoot "config\source-ref.json"

        $status = "APROVADO"

        $versionName = "Não encontrado"
        $versionNumber = "Não encontrado"
        $versionChannel = "Não encontrado"
        $versionBranch = "Não encontrado"
        $versionStable = "Não encontrado"

        $sourceRepository = "Não encontrado"
        $sourceRef = "Não encontrado"
        $sourceInstalledAt = "Não encontrado"

        $latestUpdateLogText = "Não encontrado"
        $latestUpdateSummaryText = "Não encontrado"
        $latestBackupText = "Não encontrado"
        $latestSupportPackageText = "Não encontrado"

        if (Test-Path $versionPath) {
            $versionInfo = Get-Content $versionPath -Raw -ErrorAction Stop | ConvertFrom-Json

            $versionName = $versionInfo.name
            $versionNumber = $versionInfo.version
            $versionChannel = $versionInfo.channel
            $versionBranch = $versionInfo.branch
            $versionStable = $versionInfo.stableVersion
        }
        else {
            $status = "VERIFICAR"
        }

        if (Test-Path $sourceRefPath) {
            $sourceInfo = Get-Content $sourceRefPath -Raw -ErrorAction Stop | ConvertFrom-Json

            $sourceRepository = $sourceInfo.repository
            $sourceRef = $sourceInfo.ref
            $sourceInstalledAt = $sourceInfo.installedAt

            if ([string]::IsNullOrWhiteSpace($sourceInstalledAt)) {
                $sourceInstalledAt = $sourceInfo.updatedAt
            }
            if ([string]::IsNullOrWhiteSpace($sourceInstalledAt)) {
                $sourceInstalledAt = (Get-Item $sourceRefPath).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
        else {
            $status = "VERIFICAR"
        }

        $logsPath = Join-Path $toolkitRoot "logs"
        $reportsPath = Join-Path $toolkitRoot "reports"

        $latestUpdateLog = Get-ChildItem $logsPath -Filter "update-*.log" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($null -ne $latestUpdateLog) {
            $latestUpdateLogText = $latestUpdateLog.FullName
        }

        $latestUpdateSummary = Get-ChildItem $reportsPath -Filter "update-summary-*.txt" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($null -ne $latestUpdateSummary) {
            $latestUpdateSummaryText = $latestUpdateSummary.FullName
        }

        $backupsPath = Join-Path $toolkitRoot "backups"

        $latestBackup = Get-ChildItem $backupsPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "update-*" } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($null -ne $latestBackup) {
            $latestBackupText = $latestBackup.FullName
        }

        $supportPackagesPath = Join-Path $reportsPath "support-packages"

        $latestSupportPackage = Get-ChildItem $supportPackagesPath -Filter "ServiceDeskToolkit-SupportPackage-*.zip" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($null -ne $latestSupportPackage) {
            $latestSupportPackageText = $latestSupportPackage.FullName
        }
        $output = @"
PAINEL DE STATUS DO TOOLKIT
===========================

Status geral:
$status

Versão instalada
----------------
Nome: $versionName
Versão: $versionNumber
Canal: $versionChannel
Branch declarada: $versionBranch
Versão estável base: $versionStable

Origem instalada
----------------
Repositório: $sourceRepository
Referência instalada: $sourceRef
Instalado em: $sourceInstalledAt
Arquivo:
$sourceRefPath

Último update
-------------
$latestUpdateLogText

Último resumo do update
-----------------------
$latestUpdateSummaryText

Último backup
-------------
$($latestBackupText)

Último pacote de suporte
------------------------
$($latestSupportPackageText)
"@

        OutText $output
    })
}
if ($null -ne $BtnValidateToolkitInstalled) {
    $BtnValidateToolkitInstalled.Add_Click({
        try {
            Write-ToolkitActionLog `
                -Module "Administration" `
                -Action "ValidateToolkitInstalled" `
                -Status "Started" `
                -Message "Validacao da integridade instalada solicitada pela interface."
        }
        catch {}

        try {
            $toolkitRoot = "C:\ServiceDeskToolkit"
            $validatorScript = Join-Path $toolkitRoot "tools\Test-ToolkitInstalled.ps1"

            if (!(Test-Path $validatorScript)) {
                OutText "Validador de instalacao não encontrado.`r`n`r`nArquivo esperado:`r`n$validatorScript"
                return
            }

            $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

            if (!(Test-Path $psExe)) {
                $psExe = "powershell.exe"
            }

            $validationOutput = & $psExe `
                -NoProfile `
                -ExecutionPolicy Bypass `
                -File $validatorScript 2>&1 | Out-String

            $reportsPath = Join-Path $toolkitRoot "reports"

            $latestValidation = Get-ChildItem $reportsPath -Filter "installed-validation-*.txt" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

            if ($null -ne $latestValidation) {
                OutText "Validacao da instalacao executada.`r`n`r`nRelatorio:`r`n$($latestValidation.FullName)`r`n`r`nSaida:`r`n$validationOutput"
            }
            else {
                OutText "Validacao executada, mas nenhum relatorio TXT foi encontrado em:`r`n$reportsPath`r`n`r`nSaida:`r`n$validationOutput"
            }
        }
        catch {
            try {
                Write-ToolkitErrorLog `
                    -Module "Administration" `
                    -Action "ValidateToolkitInstalled" `
                    -Status "Failed" `
                    -Message "Falha ao validar integridade instalada pela interface." `
                    -ErrorRecord $_
            }
            catch {}

            OutText "Erro ao validar instalacao do Toolkit:`r`n$($_.Exception.Message)"
        }
    })
}
if ($null -ne $BtnRunToolkitUpdate) {
    $BtnRunToolkitUpdate.Add_Click({
        try {
            Write-ToolkitActionLog `
                -Module "Administration" `
                -Action "RunToolkitUpdate" `
                -Status "Started" `
                -Message "Atualizacao segura do Toolkit solicitada pela interface."
        }
        catch {}

        try {
            $toolkitRoot = Get-ToolkitRootPath
            $updateScript = Join-Path $toolkitRoot "update.ps1"

            if (!(Test-Path $updateScript)) {
                OutText "Atualizador não encontrado.`r`n`r`nArquivo esperado:`r`n$updateScript"
                return
            }

            $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

            if (!(Test-Path $psExe)) {
                $psExe = "powershell.exe"
            }

            Start-Process `
                -FilePath $psExe `
                -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $updateScript) `
                -WorkingDirectory $toolkitRoot

            OutText "Atualizacao iniciada em processo separado.`r`n`r`nScript:`r`n$updateScript`r`n`r`nAcompanhe em:`r`n$(Join-Path $toolkitRoot "logs")"
        }
        catch {
            try {
                Write-ToolkitErrorLog `
                    -Module "Administration" `
                    -Action "RunToolkitUpdate" `
                    -Status "Failed" `
                    -Message "Falha ao iniciar update pela interface." `
                    -ErrorRecord $_
            }
            catch {}

            OutText "Erro ao iniciar update:`r`n$($_.Exception.Message)"
        }
    })
}

if ($null -ne $BtnRunRollbackDryRun) {
    $BtnRunRollbackDryRun.Add_Click({
        try {
            Write-ToolkitActionLog `
                -Module "Administration" `
                -Action "RunRollbackDryRun" `
                -Status "Started" `
                -Message "Rollback dry-run solicitado pela interface."
        }
        catch {}

        try {
            $toolkitRoot = Get-ToolkitRootPath
            $rollbackScript = Join-Path $toolkitRoot "rollback.ps1"

            if (!(Test-Path $rollbackScript)) {
                OutText "Rollback não encontrado.`r`n`r`nArquivo esperado:`r`n$rollbackScript"
                return
            }

            Remove-Item Env:\SDTK_ROLLBACK_CONFIRM -ErrorAction SilentlyContinue

            $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

            if (!(Test-Path $psExe)) {
                $psExe = "powershell.exe"
            }

            Start-Process `
                -FilePath $psExe `
                -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $rollbackScript) `
                -WorkingDirectory $toolkitRoot

            OutText "Rollback DRY-RUN iniciado em processo separado.`r`n`r`nNenhum arquivo sera alterado.`r`n`r`nScript:`r`n$rollbackScript`r`n`r`nAcompanhe em:`r`n$(Join-Path $toolkitRoot "logs")"
        }
        catch {
            try {
                Write-ToolkitErrorLog `
                    -Module "Administration" `
                    -Action "RunRollbackDryRun" `
                    -Status "Failed" `
                    -Message "Falha ao iniciar rollback dry-run pela interface." `
                    -ErrorRecord $_
            }
            catch {}

            OutText "Erro ao iniciar rollback dry-run:`r`n$($_.Exception.Message)"
        }
    })
}

if ($null -ne $BtnExportToolkitSupportPackage) {
    $BtnExportToolkitSupportPackage.Add_Click({
        try {
            Write-ToolkitActionLog `
                -Module "Administration" `
                -Action "ExportToolkitSupportPackage" `
                -Status "Started" `
                -Message "Exportacao de pacote de suporte solicitada pela interface."
        }
        catch {}

        try {
            $toolkitRoot = "C:\ServiceDeskToolkit"
            $exportScript = Join-Path $toolkitRoot "tools\Export-ToolkitSupportPackage.ps1"

            if (!(Test-Path $exportScript)) {
                OutText "Exportador de pacote de suporte não encontrado.`r`n`r`nArquivo esperado:`r`n$exportScript"
                return
            }

            $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

            if (!(Test-Path $psExe)) {
                $psExe = "powershell.exe"
            }

            $exportOutput = & $psExe `
                -NoProfile `
                -ExecutionPolicy Bypass `
                -File $exportScript 2>&1 | Out-String

            $packagesPath = Join-Path $toolkitRoot "reports\support-packages"

            $latestPackage = Get-ChildItem $packagesPath -Filter "*.zip" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

            if ($null -ne $latestPackage) {
                OutText "Pacote de suporte gerado com sucesso.`r`n`r`nArquivo:`r`n$($latestPackage.FullName)`r`n`r`nSaida:`r`n$exportOutput"
            }
            else {
                OutText "Exportacao executada, mas nenhum ZIP foi encontrado em:`r`n$packagesPath`r`n`r`nSaida:`r`n$exportOutput"
            }
        }
        catch {
            try {
                Write-ToolkitErrorLog `
                    -Module "Administration" `
                    -Action "ExportToolkitSupportPackage" `
                    -Status "Failed" `
                    -Message "Falha ao exportar pacote de suporte pela interface." `
                    -ErrorRecord $_
            }
            catch {}

            OutText "Erro ao gerar pacote de suporte:`r`n$($_.Exception.Message)"
        }
    })
}
if ($null -ne $BtnOpenLatestUpdateSummary) {
    $BtnOpenLatestUpdateSummary.Add_Click({
        try {
            Write-ToolkitActionLog `
                -Module "Administration" `
                -Action "OpenLatestUpdateSummary" `
                -Status "Started" `
                -Message "Abertura do ultimo resumo do update solicitada pela interface."
        }
        catch {}

        try {
            $toolkitRoot = "C:\ServiceDeskToolkit"
            $reportsPath = Join-Path $toolkitRoot "reports"

            if (!(Test-Path $reportsPath)) {
                OutText "Pasta de reports não encontrada:`r`n$reportsPath"
                return
            }

            $latestSummary = Get-ChildItem $reportsPath -Filter "update-summary-*.txt" -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

            if ($null -eq $latestSummary) {
                OutText "Nenhum resumo de update foi encontrado.`r`n`r`nPasta analisada:`r`n$reportsPath`r`n`r`nExecute o update.ps1 novamente para gerar o primeiro resumo."
                return
            }

            $summaryContent = Get-Content $latestSummary.FullName -Raw -ErrorAction Stop

            $jsonPath = [System.IO.Path]::ChangeExtension($latestSummary.FullName, ".json")
            $jsonInfo = ""

            if (Test-Path $jsonPath) {
                $jsonInfo = "`r`nJSON correspondente:`r`n$jsonPath`r`n"
            }
            else {
                $jsonInfo = "`r`nJSON correspondente: não encontrado.`r`n"
            }


        $output = @"
ULTIMO RESUMO DO UPDATE
=======================

Arquivo TXT:
$($latestSummary.FullName)

Ultima alteracao:
$($latestSummary.LastWriteTime)

$jsonInfo
Conteudo:
---------

$summaryContent
"@

            OutText $output
        }
        catch {
            try {
                Write-ToolkitErrorLog `
                    -Module "Administration" `
                    -Action "OpenLatestUpdateSummary" `
                    -Status "Failed" `
                    -Message "Falha ao abrir ultimo resumo do update pela interface." `
                    -ErrorRecord $_
            }
            catch {}

            OutText "Erro ao abrir ultimo resumo do update:`r`n$($_.Exception.Message)"
        }
    })
}
if ($null -ne $BtnShowToolkitLogSummary) {
    $BtnShowToolkitLogSummary.Add_Click({
        try {
            Write-ToolkitActionLog `
                -Module "Administration" `
                -Action "ShowToolkitLogSummary" `
                -Status "Started" `
                -Message "Resumo dos logs solicitado pela interface."
        }
        catch {}

        try {
            $toolkitRoot = "C:\ServiceDeskToolkit"
            $logsPath = Join-Path $toolkitRoot "logs"

            if (!(Test-Path $logsPath)) {
                OutText "Pasta de logs não encontrada:`r`n$logsPath"
                return
            }

            $patterns = @(
                @{
                    Title = "Runtime estruturado"
                    Filter = "runtime-*.jsonl"
                    Tail = 5
                },
                @{
                    Title = "Acoes estruturadas"
                    Filter = "actions-*.jsonl"
                    Tail = 5
                },
                @{
                    Title = "Erros estruturados"
                    Filter = "errors-*.jsonl"
                    Tail = 8
                },
                @{
                    Title = "Install"
                    Filter = "install-*.log"
                    Tail = 8
                },
                @{
                    Title = "Update"
                    Filter = "update-*.log"
                    Tail = 8
                },
                @{
                    Title = "Rollback"
                    Filter = "rollback-*.log"
                    Tail = 8
                }
            )

            $sb = New-Object System.Text.StringBuilder

            [void]$sb.AppendLine("RESUMO DOS LOGS DO TOOLKIT")
            [void]$sb.AppendLine("==========================")
            [void]$sb.AppendLine("Pasta: $logsPath")
            [void]$sb.AppendLine("Gerado em: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
            [void]$sb.AppendLine("")

            foreach ($pattern in $patterns) {
                $files = @(Get-ChildItem $logsPath -Filter $pattern.Filter -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending)

                [void]$sb.AppendLine("[$($pattern.Title)]")
                [void]$sb.AppendLine("Filtro: $($pattern.Filter)")
                [void]$sb.AppendLine("Arquivos encontrados: $($files.Count)")

                if ($files.Count -gt 0) {
                    $latest = $files | Select-Object -First 1

                    [void]$sb.AppendLine("Ultimo arquivo: $($latest.FullName)")
                    [void]$sb.AppendLine("Ultima alteracao: $($latest.LastWriteTime)")
                    [void]$sb.AppendLine("Tamanho: $([math]::Round(($latest.Length / 1KB), 2)) KB")
                    [void]$sb.AppendLine("")
                    [void]$sb.AppendLine("Ultimas linhas:")

                    try {
                        $tailLines = Get-Content $latest.FullName -Tail $pattern.Tail -ErrorAction Stop

                        if ($null -ne $tailLines) {
                            foreach ($line in $tailLines) {
                                [void]$sb.AppendLine("  $line")
                            }
                        }
                        else {
                            [void]$sb.AppendLine("  Nenhum conteudo encontrado.")
                        }
                    }
                    catch {
                        [void]$sb.AppendLine("  Nao foi possivel ler o arquivo: $($_.Exception.Message)")
                    }
                }
                else {
                    [void]$sb.AppendLine("Nenhum arquivo encontrado para este tipo de log.")
                }

                [void]$sb.AppendLine("")
                [void]$sb.AppendLine("----------------------------------------")
                [void]$sb.AppendLine("")
            }

            OutText $sb.ToString()
        }
        catch {
            try {
                Write-ToolkitErrorLog `
                    -Module "Administration" `
                    -Action "ShowToolkitLogSummary" `
                    -Status "Failed" `
                    -Message "Falha ao gerar resumo dos logs pela interface." `
                    -ErrorRecord $_
            }
            catch {}

            OutText "Erro ao gerar resumo dos logs:`r`n$($_.Exception.Message)"
        }
    })
}
if ($null -ne $BtnOpenUpdateRollbackLogs) {
    $BtnOpenUpdateRollbackLogs.Add_Click({
        try {
            Write-ToolkitActionLog `
                -Module "Administration" `
                -Action "OpenUpdateRollbackLogs" `
                -Status "Started" `
                -Message "Abertura da pasta de logs solicitada pela interface."
        }
        catch {}

        try {
            $toolkitRoot = Get-ToolkitRootPath
            $logsFolder = Join-Path $toolkitRoot "logs"

            if (!(Test-Path $logsFolder)) {
                New-Item -Path $logsFolder -ItemType Directory -Force | Out-Null
            }

            Start-Process $logsFolder
            OutText "Pasta de logs aberta:`r`n$logsFolder"
        }
        catch {
            OutText "Erro ao abrir pasta de logs:`r`n$($_.Exception.Message)"
        }
    })
}

if ($null -ne $BtnOpenBackups) {
    $BtnOpenBackups.Add_Click({
        try {
            Write-ToolkitActionLog `
                -Module "Administration" `
                -Action "OpenBackupsFolder" `
                -Status "Started" `
                -Message "Abertura da pasta de backups solicitada pela interface."
        }
        catch {}

        try {
            $toolkitRoot = Get-ToolkitRootPath
            $backupsFolder = Join-Path $toolkitRoot "backups"

            if (!(Test-Path $backupsFolder)) {
                New-Item -Path $backupsFolder -ItemType Directory -Force | Out-Null
            }

            Start-Process $backupsFolder
            OutText "Pasta de backups aberta:`r`n$backupsFolder"
        }
        catch {
            OutText "Erro ao abrir pasta de backups:`r`n$($_.Exception.Message)"
        }
    })
}
$BtnCopyOutput.Add_Click({try{[System.Windows.Clipboard]::SetText($TxtOutput.Text);[System.Windows.MessageBox]::Show('Copiado.','ServiceDesk Toolkit','OK','Information')|Out-Null}catch{}})

# security
$BtnTpm.Add_Click({
    try { Write-ToolkitActionLog -Module "Security" -Action "TpmStatus" -Status "Started" -Message "Consulta TPM solicitada." } catch {}$TxtSecurityOutput.Text=Get-TpmBasic})
$BtnBitLocker.Add_Click({
    try { Write-ToolkitActionLog -Module "Security" -Action "BitLockerStatus" -Status "Started" -Message "Consulta BitLocker solicitada." } catch {}$TxtSecurityOutput.Text=Get-BitlockerBasic})
$BtnDefender.Add_Click({
    try { Write-ToolkitActionLog -Module "Security" -Action "DefenderStatus" -Status "Started" -Message "Consulta Defender solicitada." } catch {}$TxtSecurityOutput.Text=Get-DefenderBasic})
$BtnUac.Add_Click({
    try { Write-ToolkitActionLog -Module "Security" -Action "UacStatus" -Status "Started" -Message "Consulta UAC solicitada." } catch {}$TxtSecurityOutput.Text=Get-UacBasic})
$BtnAdmins.Add_Click({
    try { Write-ToolkitActionLog -Module "Security" -Action "LocalAdmins" -Status "Started" -Message "Consulta de administradores locais solicitada." } catch {}$TxtSecurityOutput.Text=Get-AdminsBasic})

# Windows repair
$BtnWinRepairStatus.Add_Click({
    try { Write-ToolkitActionLog -Module "WindowsRepair" -Action "RepairStatus" -Status "Started" -Message "Consulta de status de reparo Windows solicitada." } catch {}$TxtWindowsRepairOutput.Text=Get-WindowsRepairStatus})
$BtnOpenWindowsUpdateRepair.Add_Click({
    try { Write-ToolkitActionLog -Module "WindowsRepair" -Action "OpenWindowsUpdateRepair" -Status "Started" -Message "Abertura do Windows Update pela aba de reparo solicitada." } catch {}$TxtWindowsRepairOutput.Text=Invoke-ToolkitOpenWindowsUpdate})
$BtnRestartWU.Add_Click({
    try { Write-ToolkitActionLog -Module "WindowsRepair" -Action "RestartWindowsUpdateServices" -Status "Started" -Message "Reinicio dos servicos Windows Update solicitado." } catch {}if([System.Windows.MessageBox]::Show('Reiniciar serviços do Windows Update?','Windows Update','YesNo','Warning') -eq 'Yes'){$TxtWindowsRepairOutput.Text=Restart-WUServices}})
$BtnClearWUCache.Add_Click({
    try { Write-ToolkitActionLog -Module "WindowsRepair" -Action "ClearWindowsUpdateCache" -Status "Started" -Message "Limpeza do cache Windows Update solicitada." } catch {}if([System.Windows.MessageBox]::Show('Limpar cache do Windows Update renomeando SoftwareDistribution e catroot2?','Limpar cache WU','YesNo','Warning') -eq 'Yes'){$TxtWindowsRepairOutput.Text = Invoke-ToolkitProtectedClearWUCache}})
$BtnDismOnly.Add_Click({
    try { Write-ToolkitActionLog -Module "WindowsRepair" -Action "DismRestoreHealth" -Status "Started" -Message "Execucao DISM RestoreHealth solicitada." } catch {}if([System.Windows.MessageBox]::Show('Executar DISM RestoreHealth? Pode demorar.','DISM','YesNo','Warning') -eq 'Yes'){$TxtWindowsRepairOutput.Text = Invoke-ToolkitProtectedDismOnly}})
$BtnSfcOnly.Add_Click({
    try { Write-ToolkitActionLog -Module "WindowsRepair" -Action "SfcScannow" -Status "Started" -Message "Execucao SFC Scannow solicitada." } catch {}if([System.Windows.MessageBox]::Show('Executar SFC Scannow? Pode demorar.','SFC','YesNo','Warning') -eq 'Yes'){$TxtWindowsRepairOutput.Text = Invoke-ToolkitProtectedSfcOnly}})
$BtnClearUserTemp.Add_Click({
    try { Write-ToolkitActionLog -Module "WindowsRepair" -Action "ClearUserTemp" -Status "Started" -Message "Limpeza de temporarios do usuario solicitada." } catch {}if([System.Windows.MessageBox]::Show('Limpar temporários do usuário atual?','Temporários','YesNo','Warning') -eq 'Yes'){$TxtWindowsRepairOutput.Text=Clear-UserTemp}})
$BtnTimeSyncRepair.Add_Click({
    try { Write-ToolkitActionLog -Module "WindowsRepair" -Action "TimeSyncRepair" -Status "Started" -Message "Sincronizacao de horario pela aba de reparo solicitada." } catch {}$TxtWindowsRepairOutput.Text=Invoke-TimeSync})

# TPM/Office
$BtnTpmOfficeFix.Add_Click({
    try { Write-ToolkitActionLog -Module "TpmOffice" -Action "TpmOfficeFix" -Status "Started" -Message "Ajuste TPM Office solicitado." } catch {}if([System.Windows.MessageBox]::Show('Aplicar ajuste TPM 2? Reinício recomendado.','TPM 2','YesNo','Warning') -eq 'Yes'){$TxtTpmOfficeOutput.Text = Invoke-ToolkitProtectedTpmOfficeFix}})
$BtnTpmBrokenPlugin.Add_Click({
    try { Write-ToolkitActionLog -Module "TpmOffice" -Action "RemoveBrokenPlugin" -Status "Started" -Message "Remocao de BrokenPlugin solicitada." } catch {}if([System.Windows.MessageBox]::Show('Remover BrokenPlugin? Reinício recomendado.','BrokenPlugin','YesNo','Warning') -eq 'Yes'){$TxtTpmOfficeOutput.Text = Invoke-ToolkitProtectedBrokenPluginFix}})
$BtnDismSfcRepair.Add_Click({
    try { Write-ToolkitActionLog -Module "TpmOffice" -Action "DismSfcRepair" -Status "Started" -Message "Execucao DISM mais SFC solicitada." } catch {}if([System.Windows.MessageBox]::Show('Executar DISM + SFC? Pode demorar.','DISM + SFC','YesNo','Warning') -eq 'Yes'){$TxtTpmOfficeOutput.Text = Invoke-ToolkitProtectedDismSfc}})
$BtnTpmOfficeStatus.Add_Click({
    try { Write-ToolkitActionLog -Module "TpmOffice" -Action "TpmOfficeStatus" -Status "Started" -Message "Consulta de status TPM Office solicitada." } catch {}$TxtTpmOfficeOutput.Text=Get-TpmOfficeStatus})

# system
$BtnGpUpdate.Add_Click({
    try { Write-ToolkitActionLog -Module "System" -Action "GpUpdate" -Status "Started" -Message "Execucao GPUpdate solicitada." } catch {}$TxtSystemOutput.Text=Invoke-GpUpdate})
$BtnGpResult.Add_Click({
    try { Write-ToolkitActionLog -Module "System" -Action "GpResult" -Status "Started" -Message "Execucao GPResult solicitada." } catch {}$TxtSystemOutput.Text=Invoke-GpResult})
$BtnStoppedServices.Add_Click({
    try { Write-ToolkitActionLog -Module "System" -Action "StoppedAutoServices" -Status "Started" -Message "Consulta de servicos automaticos parados solicitada." } catch {}$TxtSystemOutput.Text=Get-StoppedAutoServices})
$BtnCriticalEvents.Add_Click({
    try { Write-ToolkitActionLog -Module "System" -Action "CriticalEvents" -Status "Started" -Message "Consulta de eventos criticos solicitada." } catch {}$TxtSystemOutput.Text=Get-CriticalEvents})

# tcp
$BtnTcpTest.Add_Click({
    try { Write-ToolkitActionLog -Module "Network" -Action "TcpTest" -Status "Started" -Message "Teste TCP solicitado." } catch {}[int]$p=0;if(![int]::TryParse($InputTcpPort.Text,[ref]$p)){$TxtTcpOutput.Text='Porta inválida.';return};$TxtTcpOutput.Text=Test-TcpPort $InputTcpHost.Text $p})


# Eventos - Impressoras
$BtnPrinterStatus.Add_Click({
    $TxtPrintersOutput.Text = Get-ToolkitPrinterStatus
})

$BtnPrinterList.Add_Click({
    $TxtPrintersOutput.Text = Get-ToolkitPrinterList
})

$BtnPrintJobs.Add_Click({
    $TxtPrintersOutput.Text = Get-ToolkitPrintJobs
})

$BtnRestartSpoolerAdvanced.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Esta ação vai reiniciar o Spooler de Impressão. Impressões em andamento podem ser interrompidas. Deseja continuar?",
        "Confirmar reinício do Spooler",
        "YesNo",
        "Warning"
    )

    if ($confirm -eq "Yes") {
        $TxtPrintersOutput.Text = Invoke-ToolkitRestartSpoolerAdvanced
    }
})

$BtnClearPrintQueue.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Esta ação vai parar o Spooler e remover arquivos da fila de impressão. Deseja continuar?",
        "Confirmar limpeza da fila",
        "YesNo",
        "Warning"
    )

    if ($confirm -eq "Yes") {
        $TxtPrintersOutput.Text = Invoke-ToolkitProtectedClearPrintQueue
    }
})

$BtnDefaultPrinter.Add_Click({
    $TxtPrintersOutput.Text = Get-ToolkitDefaultPrinter
})

$BtnOfflinePrinters.Add_Click({
    $TxtPrintersOutput.Text = Get-ToolkitOfflinePrinters
})

$BtnOpenPrintersSettings.Add_Click({
    $TxtPrintersOutput.Text = Invoke-ToolkitOpenPrintersSettings
})

$BtnOpenPrintManagement.Add_Click({
    $TxtPrintersOutput.Text = Invoke-ToolkitOpenPrintManagement
})


# Eventos - Teams / Office
$BtnTeamsOfficeStatus.Add_Click({
    $TxtTeamsOfficeOutput.Text = Get-ToolkitTeamsOfficeStatus
})

$BtnCloseTeamsOffice.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Esta ação vai fechar Teams, Outlook, Word, Excel, PowerPoint, OneNote, OneDrive e processos relacionados. Deseja continuar?",
        "Confirmar fechamento Teams / Office",
        "YesNo",
        "Warning"
    )

    if ($confirm -eq "Yes") {
        $TxtTeamsOfficeOutput.Text = Invoke-ToolkitCloseTeamsOffice
    }
})

$BtnClearClassicTeamsCache.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Esta ação vai fechar o Teams clássico e limpar o cache local do usuário atual. Deseja continuar?",
        "Confirmar limpeza Teams clássico",
        "YesNo",
        "Warning"
    )

    if ($confirm -eq "Yes") {
        $TxtTeamsOfficeOutput.Text = Invoke-ToolkitClearClassicTeamsCache
    }
})

$BtnClearNewTeamsCache.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Esta ação vai fechar o Novo Teams e limpar o cache local do usuário atual. Deseja continuar?",
        "Confirmar limpeza Novo Teams",
        "YesNo",
        "Warning"
    )

    if ($confirm -eq "Yes") {
        $TxtTeamsOfficeOutput.Text = Invoke-ToolkitClearNewTeamsCache
    }
})

$BtnOpenTeamsFolder.Add_Click({
    $TxtTeamsOfficeOutput.Text = Invoke-ToolkitOpenTeamsFolder
})

$BtnOpenCredentialManager.Add_Click({
    $TxtTeamsOfficeOutput.Text = Invoke-ToolkitOpenCredentialManager
})

$BtnOpenAccountsSettings.Add_Click({
    $TxtTeamsOfficeOutput.Text = Invoke-ToolkitOpenAccountsSettings
})

$BtnOpenOfficeRepair.Add_Click({
    $TxtTeamsOfficeOutput.Text = Invoke-ToolkitOpenOfficeRepair
})

$BtnOfficeIdentityKeys.Add_Click({
    $TxtTeamsOfficeOutput.Text = Get-ToolkitOfficeIdentityKeys
})


# Eventos - Microsoft Store / Apps
$BtnStoreAppsStatus.Add_Click({
    $TxtStoreAppsOutput.Text = Get-ToolkitStoreAppsStatus
})

$BtnRestartMicrosoftStore.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Esta ação vai fechar processos relacionados Ã  Microsoft Store e tentar abrir a Store novamente. Deseja continuar?",
        "Confirmar reinício da Microsoft Store",
        "YesNo",
        "Warning"
    )

    if ($confirm -eq "Yes") {
        $TxtStoreAppsOutput.Text = Invoke-ToolkitRestartMicrosoftStore
    }
})

$BtnResetMicrosoftStore.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Esta ação vai executar wsreset.exe para resetar o cache da Microsoft Store. Uma janela pode abrir temporariamente. Deseja continuar?",
        "Confirmar reset da Microsoft Store",
        "YesNo",
        "Warning"
    )

    if ($confirm -eq "Yes") {
        $TxtStoreAppsOutput.Text = Invoke-ToolkitResetMicrosoftStore
    }
})

$BtnRepairMicrosoftStore.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Esta ação vai registrar novamente o pacote da Microsoft Store para o usuário atual. Deseja continuar?",
        "Confirmar reparo da Microsoft Store",
        "YesNo",
        "Warning"
    )

    if ($confirm -eq "Yes") {
        $TxtStoreAppsOutput.Text = Invoke-ToolkitRepairMicrosoftStorePackage
    }
})

$BtnRepairWindowsApps.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Esta ação vai tentar registrar novamente os Apps do Windows para o usuário atual. O processo pode demorar alguns minutos. Deseja continuar?",
        "Confirmar reparo de Apps do Windows",
        "YesNo",
        "Warning"
    )

    if ($confirm -eq "Yes") {
        $TxtStoreAppsOutput.Text = Invoke-ToolkitProtectedRepairWindowsApps
    }
})

$BtnOpenInstalledApps.Add_Click({
    $TxtStoreAppsOutput.Text = Invoke-ToolkitOpenInstalledApps
})

$BtnOpenMicrosoftStore.Add_Click({
    $TxtStoreAppsOutput.Text = Invoke-ToolkitOpenMicrosoftStore
})

$BtnOpenOfficeTeamsRepair.Add_Click({
    $TxtStoreAppsOutput.Text = Invoke-ToolkitOpenOfficeTeamsRepair
})

$BtnOpenStoreTroubleshoot.Add_Click({
    $TxtStoreAppsOutput.Text = Invoke-ToolkitOpenStoreTroubleshoot
})


# Eventos - Rede Avançada
$BtnAdvancedNetworkStatus.Add_Click({
    $TxtAdvancedNetworkOutput.Text = Get-ToolkitAdvancedNetworkStatus
})

$BtnDnsConfiguration.Add_Click({
    $TxtAdvancedNetworkOutput.Text = Get-ToolkitDnsConfiguration
})

$BtnNetworkRoutes.Add_Click({
    $TxtAdvancedNetworkOutput.Text = Get-ToolkitNetworkRoutes
})

$BtnTestGateway.Add_Click({
    $TxtAdvancedNetworkOutput.Text = Test-ToolkitGateway
})

$BtnTestInternetAdvanced.Add_Click({
    $TxtAdvancedNetworkOutput.Text = Test-ToolkitInternetAdvanced
})

$BtnFlushDnsAdvanced.Add_Click({
    $TxtAdvancedNetworkOutput.Text = Invoke-ToolkitFlushDnsAdvanced
})

$BtnReleaseRenewAdvanced.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Esta ação vai executar ipconfig /release e ipconfig /renew. A conexão pode cair temporariamente. Deseja continuar?",
        "Confirmar Release/Renew IP",
        "YesNo",
        "Warning"
    )

    if ($confirm -eq "Yes") {
        $TxtAdvancedNetworkOutput.Text = Invoke-ToolkitReleaseRenewAdvanced
    }
})

$BtnResetWinsock.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Esta ação vai executar netsh winsock reset. Será recomendado reiniciar o computador. Deseja continuar?",
        "Confirmar Reset Winsock",
        "YesNo",
        "Warning"
    )

    if ($confirm -eq "Yes") {
        $TxtAdvancedNetworkOutput.Text = Invoke-ToolkitProtectedResetWinsock
    }
})

$BtnResetTcpIp.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show(
        "Esta ação vai executar netsh int ip reset. Será recomendado reiniciar o computador. Deseja continuar?",
        "Confirmar Reset TCP/IP",
        "YesNo",
        "Warning"
    )

    if ($confirm -eq "Yes") {
        $TxtAdvancedNetworkOutput.Text = Invoke-ToolkitProtectedResetTcpIp
    }
})

$BtnOpenNetworkConnectionsAdvanced.Add_Click({
    $TxtAdvancedNetworkOutput.Text = Invoke-ToolkitOpenNetworkConnectionsAdvanced
})


# Eventos - Apps Corporativos
$BtnCorporateAppsStatus.Add_Click({
    $TxtCorporateAppsOutput.Text = Get-ToolkitCorporateAppsStatus
})

$BtnAllCorporateAppErrors.Add_Click({
    $TxtCorporateAppsOutput.Text = Get-ToolkitAllCorporateAppErrors
})

$BtnOutlookErrors.Add_Click({
    $TxtCorporateAppsOutput.Text = Get-ToolkitOutlookErrors
})

$BtnTeamsErrors.Add_Click({
    $TxtCorporateAppsOutput.Text = Get-ToolkitTeamsErrors
})

$BtnOneDriveErrors.Add_Click({
    $TxtCorporateAppsOutput.Text = Get-ToolkitOneDriveErrors
})

$BtnScreenshotErrors.Add_Click({
    $TxtCorporateAppsOutput.Text = Get-ToolkitScreenshotErrors
})

$BtnWhatsAppErrors.Add_Click({
    $TxtCorporateAppsOutput.Text = Get-ToolkitWhatsAppErrors
})

$BtnOpenReliabilityMonitor.Add_Click({
    $TxtCorporateAppsOutput.Text = Invoke-ToolkitOpenReliabilityMonitor
})

$BtnOpenEventViewerApplication.Add_Click({
    $TxtCorporateAppsOutput.Text = Invoke-ToolkitOpenEventViewerApplication
})


# Eventos - Atendimento Rápido
$BtnQuickInternet.Add_Click({
    $TxtQuickSupportOutput.Text = "Executando diagnóstico rápido de Internet / Rede..."
    $TxtQuickSupportOutput.Text = Invoke-ToolkitQuickInternet
})

$BtnQuickTeams.Add_Click({
    $TxtQuickSupportOutput.Text = "Executando diagnóstico rápido do Teams..."
    $TxtQuickSupportOutput.Text = Invoke-ToolkitQuickTeams
})

$BtnQuickOutlook.Add_Click({
    $TxtQuickSupportOutput.Text = "Executando diagnóstico rápido do Outlook..."
    $TxtQuickSupportOutput.Text = Invoke-ToolkitQuickOutlook
})

$BtnQuickOneDrive.Add_Click({
    $TxtQuickSupportOutput.Text = "Executando diagnóstico rápido do OneDrive..."
    $TxtQuickSupportOutput.Text = Invoke-ToolkitQuickOneDrive
})

$BtnQuickPrinter.Add_Click({
    $TxtQuickSupportOutput.Text = "Executando diagnóstico rápido de Impressora..."
    $TxtQuickSupportOutput.Text = Invoke-ToolkitQuickPrinter
})

$BtnQuickWindowsUpdate.Add_Click({
    $TxtQuickSupportOutput.Text = "Executando diagnóstico rápido do Windows Update..."
    $TxtQuickSupportOutput.Text = Invoke-ToolkitQuickWindowsUpdate
})

$BtnQuickAppgate.Add_Click({
    $TxtQuickSupportOutput.Text = "Executando diagnóstico rápido do Appgate / VPN..."
    $TxtQuickSupportOutput.Text = Invoke-ToolkitQuickAppgate
})

$BtnQuickFullReport.Add_Click({
    $TxtQuickSupportOutput.Text = "Gerando relatório geral..."
    $TxtQuickSupportOutput.Text = Invoke-ToolkitQuickFullReport
})


# Eventos - Base de Conhecimento
$BtnKnowledgeSearch.Add_Click({
    try {
        Write-ToolkitActionLog `
            -Module "KnowledgeBase" `
            -Action "KnowledgeSearch" `
            -Status "Started" `
            -Message "Busca realizada na Base de Conhecimento." `
            -Data @{
                query = $TxtKnowledgeQuery.Text
            }
    }
    catch {}
    try {
        $query = $TxtKnowledgeQuery.Text

        $TxtKnowledgeOutput.Text = "Buscando resolução na Base de Conhecimento...`r`n`r`nAguarde..."

        $resultado = Search-ToolkitKnowledgeBase -Query $query

        if (Get-Command Set-ToolkitResultText -ErrorAction SilentlyContinue) {
            Set-ToolkitResultText `
                -OutputControl $TxtKnowledgeOutput `
                -Title "Base de Conhecimento" `
                -Category "Resolução Guiada" `
                -Status "OK" `
                -Summary "Busca concluída na base local de conhecimento." `
                -Details $resultado `
                -Recommendation "Use os passos recomendados e acesse as abas relacionadas do toolkit para executar as ações necessárias." | Out-Null
        }
        else {
            $TxtKnowledgeOutput.Text = $resultado
        }
    }
    catch {
        $TxtKnowledgeOutput.Text = "Erro ao buscar na Base de Conhecimento:`r`n$($_.Exception.Message)"
    }
})

$BtnKnowledgeSummary.Add_Click({
    try {
        Write-ToolkitActionLog `
            -Module "KnowledgeBase" `
            -Action "KnowledgeSummary" `
            -Status "Started" `
            -Message "Listagem de artigos cadastrados solicitada."
    }
    catch {}
    try {
        $resultado = Get-ToolkitKnowledgeBaseSummary

        if (Get-Command Set-ToolkitResultText -ErrorAction SilentlyContinue) {
            Set-ToolkitResultText `
                -OutputControl $TxtKnowledgeOutput `
                -Title "Artigos Cadastrados" `
                -Category "Base de Conhecimento" `
                -Status "OK" `
                -Summary "Listagem de artigos disponíveis na base local." `
                -Details $resultado `
                -Recommendation "Use o campo de busca para localizar resoluções por palavras-chave como Teams, Outlook, Appgate, impressora, DNS ou Windows Update." | Out-Null
        }
        else {
            $TxtKnowledgeOutput.Text = $resultado
        }
    }
    catch {
        $TxtKnowledgeOutput.Text = "Erro ao listar Base de Conhecimento:`r`n$($_.Exception.Message)"
    }
})

$BtnOpenKnowledgeBaseFile.Add_Click({
    try {
        Write-ToolkitActionLog `
            -Module "KnowledgeBase" `
            -Action "OpenKnowledgeBaseJson" `
            -Status "Started" `
            -Message "Abertura do arquivo JSON da Base de Conhecimento solicitada."
    }
    catch {}
    try {
        $TxtKnowledgeOutput.Text = Invoke-ToolkitOpenKnowledgeBaseFile
    }
    catch {
        $TxtKnowledgeOutput.Text = "Erro ao abrir arquivo da Base de Conhecimento:`r`n$($_.Exception.Message)"
    }
})


# Evento - Visão Geral - Base de Conhecimento
$BtnHomeKnowledge.Add_Click({
    Select-ToolkitTabByHeader "Base de Conhecimento" | Out-Null
})



# ============================================================
# Action Logs - Lote 2
# Instrumentacao isolada: nao altera handlers originais
# ============================================================

function Register-ToolkitActionLogHandlersLote2 {
    function Add-ToolkitButtonActionLog {
        param(
            [string]$ButtonName,
            [string]$Module,
            [string]$Action,
            [string]$Message
        )

        try {
            $buttonVariable = Get-Variable -Name $ButtonName -Scope Script -ErrorAction SilentlyContinue

            if ($null -eq $buttonVariable) {
                return
            }

            $button = $buttonVariable.Value

            if ($null -eq $button) {
                return
            }

            $button.Add_Click({
                try {
                    Write-ToolkitActionLog `
                        -Module $Module `
                        -Action $Action `
                        -Status "Clicked" `
                        -Message $Message
                }
                catch {}
            }.GetNewClosure())
        }
        catch {}
    }

    # Impressoras
    Add-ToolkitButtonActionLog -ButtonName "BtnPrinterStatus" -Module "Printers" -Action "PrinterStatus" -Message "Consulta de status de impressoras solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnPrinterList" -Module "Printers" -Action "PrinterList" -Message "Listagem de impressoras solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnPrintJobs" -Module "Printers" -Action "PrintJobs" -Message "Consulta de fila de impressao solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnRestartSpoolerAdvanced" -Module "Printers" -Action "RestartSpoolerAdvanced" -Message "Reinicio avancado do spooler solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnClearPrintQueue" -Module "Printers" -Action "ClearPrintQueue" -Message "Limpeza da fila de impressao solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnDefaultPrinter" -Module "Printers" -Action "DefaultPrinter" -Message "Consulta de impressora padrao solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOfflinePrinters" -Module "Printers" -Action "OfflinePrinters" -Message "Consulta de impressoras offline solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenPrintersSettings" -Module "Printers" -Action "OpenPrintersSettings" -Message "Abertura das configuracoes de impressoras solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenPrintManagement" -Module "Printers" -Action "OpenPrintManagement" -Message "Abertura do gerenciamento de impressao solicitada."

    # Teams e Office
    Add-ToolkitButtonActionLog -ButtonName "BtnTeamsOfficeStatus" -Module "TeamsOffice" -Action "TeamsOfficeStatus" -Message "Consulta de status Teams e Office solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnCloseTeamsOffice" -Module "TeamsOffice" -Action "CloseTeamsOffice" -Message "Fechamento de processos Teams e Office solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnClearClassicTeamsCache" -Module "TeamsOffice" -Action "ClearClassicTeamsCache" -Message "Limpeza de cache do Teams classico solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnClearNewTeamsCache" -Module "TeamsOffice" -Action "ClearNewTeamsCache" -Message "Limpeza de cache do novo Teams solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenTeamsFolder" -Module "TeamsOffice" -Action "OpenTeamsFolder" -Message "Abertura da pasta do Teams solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenCredentialManager" -Module "TeamsOffice" -Action "OpenCredentialManager" -Message "Abertura do Gerenciador de Credenciais solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenAccountsSettings" -Module "TeamsOffice" -Action "OpenAccountsSettings" -Message "Abertura das configuracoes de contas solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenOfficeRepair" -Module "TeamsOffice" -Action "OpenOfficeRepair" -Message "Abertura do reparo do Office solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOfficeIdentityKeys" -Module "TeamsOffice" -Action "OfficeIdentityKeys" -Message "Consulta de chaves de identidade do Office solicitada."

    # Microsoft Store e Apps
    Add-ToolkitButtonActionLog -ButtonName "BtnStoreAppsStatus" -Module "StoreApps" -Action "StoreAppsStatus" -Message "Consulta de status Microsoft Store e Apps solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnRestartMicrosoftStore" -Module "StoreApps" -Action "RestartMicrosoftStore" -Message "Reinicio da Microsoft Store solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnResetMicrosoftStore" -Module "StoreApps" -Action "ResetMicrosoftStore" -Message "Reset da Microsoft Store solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnRepairMicrosoftStore" -Module "StoreApps" -Action "RepairMicrosoftStore" -Message "Reparo da Microsoft Store solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnRepairWindowsApps" -Module "StoreApps" -Action "RepairWindowsApps" -Message "Reparo de apps Windows solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenInstalledApps" -Module "StoreApps" -Action "OpenInstalledApps" -Message "Abertura de apps instalados solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenMicrosoftStore" -Module "StoreApps" -Action "OpenMicrosoftStore" -Message "Abertura da Microsoft Store solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenOfficeTeamsRepair" -Module "StoreApps" -Action "OpenOfficeTeamsRepair" -Message "Abertura do reparo Office Teams solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenStoreTroubleshoot" -Module "StoreApps" -Action "OpenStoreTroubleshoot" -Message "Abertura do solucionador da Store solicitada."

    # Rede Avancada
    Add-ToolkitButtonActionLog -ButtonName "BtnAdvancedNetworkStatus" -Module "AdvancedNetwork" -Action "AdvancedNetworkStatus" -Message "Consulta avancada de rede solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnDnsConfiguration" -Module "AdvancedNetwork" -Action "DnsConfiguration" -Message "Consulta de configuracao DNS solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnNetworkRoutes" -Module "AdvancedNetwork" -Action "NetworkRoutes" -Message "Consulta de rotas de rede solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnTestGateway" -Module "AdvancedNetwork" -Action "TestGateway" -Message "Teste de gateway solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnTestInternetAdvanced" -Module "AdvancedNetwork" -Action "TestInternetAdvanced" -Message "Teste avancado de internet solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnFlushDnsAdvanced" -Module "AdvancedNetwork" -Action "FlushDnsAdvanced" -Message "Flush DNS avancado solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnReleaseRenewAdvanced" -Module "AdvancedNetwork" -Action "ReleaseRenewAdvanced" -Message "Release Renew avancado solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnResetWinsock" -Module "AdvancedNetwork" -Action "ResetWinsock" -Message "Reset Winsock solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnResetTcpIp" -Module "AdvancedNetwork" -Action "ResetTcpIp" -Message "Reset TCP IP solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenNetworkConnectionsAdvanced" -Module "AdvancedNetwork" -Action "OpenNetworkConnectionsAdvanced" -Message "Abertura avancada de conexoes de rede solicitada."

    # Apps Corporativos
    Add-ToolkitButtonActionLog -ButtonName "BtnCorporateAppsStatus" -Module "CorporateApps" -Action "CorporateAppsStatus" -Message "Consulta de status de apps corporativos solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnAllCorporateAppErrors" -Module "CorporateApps" -Action "AllCorporateAppErrors" -Message "Consulta de erros de apps corporativos solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOutlookErrors" -Module "CorporateApps" -Action "OutlookErrors" -Message "Consulta de erros do Outlook solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnTeamsErrors" -Module "CorporateApps" -Action "TeamsErrors" -Message "Consulta de erros do Teams solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOneDriveErrors" -Module "CorporateApps" -Action "OneDriveErrors" -Message "Consulta de erros do OneDrive solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnScreenshotErrors" -Module "CorporateApps" -Action "ScreenshotErrors" -Message "Consulta de erros de captura de tela solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnWhatsAppErrors" -Module "CorporateApps" -Action "WhatsAppErrors" -Message "Consulta de erros do WhatsApp solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenReliabilityMonitor" -Module "CorporateApps" -Action "OpenReliabilityMonitor" -Message "Abertura do Monitor de Confiabilidade solicitada."
    Add-ToolkitButtonActionLog -ButtonName "BtnOpenEventViewerApplication" -Module "CorporateApps" -Action "OpenEventViewerApplication" -Message "Abertura do Event Viewer Application solicitada."

    # Atendimento Rapido
    Add-ToolkitButtonActionLog -ButtonName "BtnQuickInternet" -Module "QuickSupport" -Action "QuickInternet" -Message "Atendimento rapido de internet solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnQuickTeams" -Module "QuickSupport" -Action "QuickTeams" -Message "Atendimento rapido de Teams solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnQuickOutlook" -Module "QuickSupport" -Action "QuickOutlook" -Message "Atendimento rapido de Outlook solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnQuickOneDrive" -Module "QuickSupport" -Action "QuickOneDrive" -Message "Atendimento rapido de OneDrive solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnQuickPrinter" -Module "QuickSupport" -Action "QuickPrinter" -Message "Atendimento rapido de impressora solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnQuickWindowsUpdate" -Module "QuickSupport" -Action "QuickWindowsUpdate" -Message "Atendimento rapido de Windows Update solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnQuickAppgate" -Module "QuickSupport" -Action "QuickAppgate" -Message "Atendimento rapido de Appgate solicitado."
    Add-ToolkitButtonActionLog -ButtonName "BtnQuickFullReport" -Module "QuickSupport" -Action "QuickFullReport" -Message "Atendimento rapido de relatorio completo solicitado."
}

try {
    Register-ToolkitActionLogHandlersLote2
}
catch {
    try {
        Write-ToolkitErrorLog `
            -Module "Instrumentation" `
            -Action "RegisterActionLogHandlersLote2" `
            -Status "Failed" `
            -Message "Falha ao registrar action logs do lote 2." `
            -ErrorRecord $_
    }
    catch {}
}


# ============================================================
# Action Logs e Error Handlers - Lote 3
# Instrumentacao isolada: botoes restantes e erros globais
# ============================================================

function Register-ToolkitActionLogHandlersLote3 {
    function Add-ToolkitButtonActionLogLote3 {
        param(
            [string]$ButtonName,
            [string]$Module,
            [string]$Action,
            [string]$Message
        )

        try {
            $buttonVariable = Get-Variable -Name $ButtonName -Scope Script -ErrorAction SilentlyContinue

            if ($null -eq $buttonVariable) {
                return
            }

            $button = $buttonVariable.Value

            if ($null -eq $button) {
                return
            }

            $button.Add_Click({
                try {
                    Write-ToolkitActionLog `
                        -Module $Module `
                        -Action $Action `
                        -Status "Clicked" `
                        -Message $Message
                }
                catch {}
            }.GetNewClosure())
        }
        catch {}
    }

    Add-ToolkitButtonActionLogLote3 -ButtonName "BtnCopyOutput" -Module "Output" -Action "CopyOutput" -Message "Copia da saida para area de transferencia solicitada."
    Add-ToolkitButtonActionLogLote3 -ButtonName "BtnHomeKnowledge" -Module "KnowledgeBase" -Action "HomeKnowledgeShortcut" -Message "Atalho da Base de Conhecimento na tela inicial solicitado."
}

function Register-ToolkitGlobalErrorHandlersLote3 {
    try {
        if ($null -ne $window -and $null -ne $window.Dispatcher) {
            $window.Dispatcher.Add_UnhandledException({
                param($sender, $eventArgs)

                try {
                    $exceptionMessage = ""
                    $exceptionType = ""
                    $exceptionStack = ""

                    if ($null -ne $eventArgs -and $null -ne $eventArgs.Exception) {
                        $exceptionMessage = [string]$eventArgs.Exception.Message
                        $exceptionType = [string]$eventArgs.Exception.GetType().FullName
                        $exceptionStack = [string]$eventArgs.Exception.StackTrace
                    }

                    Write-ToolkitStructuredLog `
                        -LogType "errors" `
                        -Level "ERROR" `
                        -Module "WPF" `
                        -Action "DispatcherUnhandledException" `
                        -Status "Unhandled" `
                        -Message "Erro nao tratado capturado no dispatcher WPF." `
                        -Data @{
                            exceptionMessage = $exceptionMessage
                            exceptionType = $exceptionType
                            stackTrace = $exceptionStack
                        }
                }
                catch {}
            }.GetNewClosure())
        }
    }
    catch {
        try {
            Write-ToolkitErrorLog `
                -Module "Instrumentation" `
                -Action "RegisterWpfErrorHandler" `
                -Status "Failed" `
                -Message "Falha ao registrar handler de erro WPF." `
                -ErrorRecord $_
        }
        catch {}
    }

    try {
        [System.AppDomain]::CurrentDomain.Add_UnhandledException({
            param($sender, $eventArgs)

            try {
                $exceptionMessage = ""
                $exceptionType = ""
                $exceptionStack = ""

                if ($null -ne $eventArgs -and $null -ne $eventArgs.ExceptionObject) {
                    $exceptionObject = $eventArgs.ExceptionObject

                    if ($exceptionObject -is [System.Exception]) {
                        $exceptionMessage = [string]$exceptionObject.Message
                        $exceptionType = [string]$exceptionObject.GetType().FullName
                        $exceptionStack = [string]$exceptionObject.StackTrace
                    }
                    else {
                        $exceptionMessage = [string]$exceptionObject
                        $exceptionType = [string]$exceptionObject.GetType().FullName
                    }
                }

                Write-ToolkitStructuredLog `
                    -LogType "errors" `
                    -Level "CRITICAL" `
                    -Module "Application" `
                    -Action "UnhandledException" `
                    -Status "Unhandled" `
                    -Message "Erro critico nao tratado capturado no AppDomain." `
                    -Data @{
                        exceptionMessage = $exceptionMessage
                        exceptionType = $exceptionType
                        stackTrace = $exceptionStack
                        isTerminating = [string]$eventArgs.IsTerminating
                    }
            }
            catch {}
        }.GetNewClosure())
    }
    catch {
        try {
            Write-ToolkitErrorLog `
                -Module "Instrumentation" `
                -Action "RegisterAppDomainErrorHandler" `
                -Status "Failed" `
                -Message "Falha ao registrar handler de erro do AppDomain." `
                -ErrorRecord $_
        }
        catch {}
    }

    try {
        Write-ToolkitRuntimeLog `
            -Module "Instrumentation" `
            -Action "RegisterGlobalErrorHandlers" `
            -Status "Registered" `
            -Message "Handlers globais de erro registrados."
    }
    catch {}
}

try {
    Register-ToolkitActionLogHandlersLote3
}
catch {
    try {
        Write-ToolkitErrorLog `
            -Module "Instrumentation" `
            -Action "RegisterActionLogHandlersLote3" `
            -Status "Failed" `
            -Message "Falha ao registrar action logs do lote 3." `
            -ErrorRecord $_
    }
    catch {}
}

try {
    Register-ToolkitGlobalErrorHandlersLote3
}
catch {
    try {
        Write-ToolkitErrorLog `
            -Module "Instrumentation" `
            -Action "RegisterGlobalErrorHandlersLote3" `
            -Status "Failed" `
            -Message "Falha ao registrar handlers globais de erro do lote 3." `
            -ErrorRecord $_
    }
    catch {}
}

# Runtime log - abertura do Toolkit
try {
    Write-ToolkitRuntimeLog `
        -Module "Application" `
        -Action "Start" `
        -Status "Started" `
        -Message "Toolkit iniciado com logs estruturados." `
        -Data @{
            rootPath = Get-ToolkitRootPath
            scriptPath = $PSCommandPath
        }

    if ($null -ne $window) {
        $window.Add_Closed({
            try {
                Write-ToolkitRuntimeLog `
                    -Module "Application" `
                    -Action "Close" `
                    -Status "Closed" `
                    -Message "Toolkit encerrado pelo usuario."
            }
            catch {}
        })
    }
}
catch {
    Write-ToolkitErrorLog `
        -Module "Application" `
        -Action "Start" `
        -Status "LogFailed" `
        -Message "Falha ao registrar inicializacao do Toolkit." `
        -ErrorRecord $_
}

$window.ShowDialog()|Out-Null



















































