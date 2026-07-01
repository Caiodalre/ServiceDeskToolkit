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
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $os = Get-CimInstance Win32_OperatingSystem
        $bios = Get-CimInstance Win32_BIOS

        [pscustomobject]@{
            Hostname = $env:COMPUTERNAME
            Usuario = "$env:USERDOMAIN\$env:USERNAME"
            Fabricante = $cs.Manufacturer
            Modelo = $cs.Model
            Dominio = $cs.Domain
            Windows = $os.Caption
            Versao = $os.Version
            Build = $os.BuildNumber
            Serial = $bios.SerialNumber
            RAM_GB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
        } | Format-List | Out-String
    }
    catch {
        "Erro ao coletar inventário:`r`n$($_.Exception.Message)"
    }
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

$window.FindName("BtnV3NavHome").Add_Click({ $BtnV3LinkedIn = $window.FindName("BtnV3LinkedIn")
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
Set-V3Output (Get-V3HomeText) })
$window.FindName("BtnV3NavGuided").Add_Click({ Set-V3Output "Atendimento Guiado:`r`n- Sem internet`r`n- VPN / Appgate`r`n- Teams / Outlook`r`n- Impressora`r`n- Windows Update`r`n- Máquina lenta" })
$window.FindName("BtnV3NavEvidence").Add_Click({ Set-V3Output "Evidências:`r`n- Inventário`r`n- Diagnóstico de rede`r`n- Relatório`r`n- Pacote de suporte`r`n- Copiar resultado" })
$window.FindName("BtnV3NavSafeFix").Add_Click({ Set-V3Output "Correções Seguras:`r`n- Limpar DNS`r`n- Renovar IP`r`n- Sincronizar horário`r`n- Reiniciar spooler`r`n- Limpar temporários" })
$window.FindName("BtnV3NavAdvanced").Add_Click({ Set-V3Output "Área avançada:`r`nAções críticas ficarão protegidas por confirmação, mensagem de risco e log.`r`n`r`nExemplos:`r`n- SFC`r`n- DISM`r`n- Reset Winsock`r`n- Reset TCP/IP`r`n- Correções Appgate/TPM" })
$window.FindName("BtnV3NavToolkit").Add_Click({ Set-V3Output "Toolkit:`r`n- Status`r`n- Atualização`r`n- Rollback`r`n- Logs`r`n- Validação`r`n`r`nEssas funções serão conectadas ao motor atual em etapas futuras." })

$window.FindName("BtnV3QuickInternet").Add_Click({ Set-V3Output (Invoke-V3QuickInternet) })
$window.FindName("BtnV3QuickVpn").Add_Click({ Set-V3Output (Invoke-V3QuickVpn) })
$window.FindName("BtnV3Inventory").Add_Click({ Set-V3Output (Get-V3InventoryLite) })
$window.FindName("BtnV3Network").Add_Click({ Set-V3Output (Invoke-V3NetworkDiagnostic) })
$window.FindName("BtnV3FlushDns").Add_Click({ Set-V3Output (Invoke-V3FlushDns) })
$window.FindName("BtnV3TimeSync").Add_Click({ Set-V3Output (Invoke-V3TimeSync) })
$window.FindName("BtnV3Spooler").Add_Click({ Set-V3Output (Invoke-V3RestartSpooler) })
$window.FindName("BtnV3AdvancedInfo").Add_Click({ Set-V3Output "Área avançada protegida.`r`n`r`nNesta primeira V3, ações críticas não ficam expostas na tela principal.`r`nElas serão conectadas depois com confirmação, risco e log." })
$window.FindName("BtnV3CopyOutput").Add_Click({
    try {
        [System.Windows.Clipboard]::SetText($script:TxtV3Output.Text)
        [System.Windows.MessageBox]::Show("Resultado copiado.", "ServiceDesk Toolkit V3") | Out-Null
    }
    catch {
        [System.Windows.MessageBox]::Show("Erro ao copiar: $($_.Exception.Message)", "ServiceDesk Toolkit V3") | Out-Null
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

