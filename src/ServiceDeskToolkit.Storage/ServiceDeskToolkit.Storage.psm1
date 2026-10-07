Set-StrictMode -Version 2.0

function Get-ToolkitStorageGuidance {
    @(
        @{ Key = 'Large'; Title = 'Maiores arquivos'; Steps = @('Identifique o aplicativo e o dono do arquivo.', 'Separe documentos, instaladores e backups de arquivos de sistema.', 'Mova dados autorizados para um destino aprovado e confirme a copia antes de remover a origem.', 'Para aplicativos sem uso, prefira desinstalar em Configuracoes > Aplicativos.') }
        @{ Key = 'Ost'; Title = 'Outlook - OST'; Steps = @('Confirme que a caixa esta sincronizada e que nao existem itens locais pendentes.', 'No Outlook classico, revise o periodo de email mantido offline conforme a politica da empresa.', 'Use Configuracoes de Conta > Arquivos de Dados > Configuracoes para verificar as opcoes de compactacao.', 'Recriar OST exige suporte, sincronizacao confirmada e espaco para novo download; nao apagar diretamente.') }
        @{ Key = 'Pst'; Title = 'Outlook - PST'; Steps = @('PST pode conter a unica copia de emails: confirme o proprietario e a retencao.', 'Feche o Outlook e guarde uma copia verificada em destino aprovado.', 'Revise os itens com o usuario; no Outlook classico use Arquivos de Dados > Configuracoes > Compactar Agora quando disponivel.', 'Reabra o Outlook e confira pastas e mensagens; nao excluir PST para liberar espaco sem validar seu conteudo.') }
        @{ Key = 'Nst'; Title = 'Outlook - NST'; Steps = @('Identifique a conta, grupos e versao do Outlook que usam o arquivo.', 'Confirme sincronizacao e integridade com o suporte de mensageria.', 'Revise a configuracao de cache suportada nessa versao; nao tratar NST como arquivo descartavel.', 'Valide os grupos e a sincronizacao antes de qualquer recriacao supervisionada.') }
        @{ Key = 'Search'; Title = 'Windows Search'; Steps = @('Compare o tamanho do indice e confira o estado do WSearch.', 'Abra Opcoes de Indexacao e reduza locais sem necessidade de pesquisa conforme a politica.', 'Se houver falha ou crescimento anormal, use Avancado > Recriar com autorizacao; a busca ficara incompleta durante a indexacao.', 'Aguarde a conclusao e valide a pesquisa no Windows e Outlook. Nao remover Windows.edb ou Windows.db manualmente.') }
        @{ Key = 'WindowsTemp'; Title = 'Windows Temp'; Steps = @('Feche aplicativos e confirme que nao ha instalacao ou atualizacao em andamento.', 'Abra Configuracoes > Sistema > Armazenamento > Arquivos temporarios.', 'Revise cada categoria e execute a limpeza aprovada; Downloads exige revisao separada.', 'Arquivos em uso devem permanecer; se o volume voltar a crescer, investigue o processo gerador.') }
        @{ Key = 'TempTop'; Title = 'Maiores arquivos do Windows Temp'; Steps = @('Use a lista para identificar os maiores produtores de temporarios.', 'Confira data, aplicativo e se o arquivo esta em uso.', 'Aplique a limpeza de temporarios pela ferramenta do Windows ou pelo aplicativo responsavel.', 'Compare o tamanho depois e investigue recorrencia; idade sozinha nao autoriza exclusao.') }
        @{ Key = 'TempEvtx'; Title = 'EVTX no Windows Temp'; Steps = @('Identifique qual processo esta gravando os eventos e se existe incidente em investigacao.', 'Guarde a evidencia necessaria em destino aprovado e valide a retencao.', 'Apos autorizacao, revise os arquivos temporarios elegiveis; nao limpar logs ativos do Windows indiscriminadamente.', 'Se os EVTX reaparecerem, corrija a causa com a equipe responsavel.') }
        @{ Key = 'UserTemp'; Title = 'Temporarios dos usuarios'; Steps = @('Confirme quais usuarios e sessoes estao ativos.', 'Para o perfil atual, feche aplicativos e use a limpeza de temporarios suportada.', 'Outros perfis exigem contato com o dono e suporte administrativo; nao apagar dados de sessoes ativas.', 'Repita a leitura e valide os aplicativos afetados.') }
        @{ Key = 'Hibernation'; Title = 'Hibernacao - hiberfil.sys'; Steps = @('Confirme se a estacao usa hibernacao ou Inicializacao Rapida.', 'Prefira limpeza de dados e caches antes de alterar energia.', 'Somente se a politica permitir, o suporte pode avaliar powercfg /hibernate off com elevacao; isso altera recursos de energia.', 'Para reverter use powercfg /hibernate on; valide suspensao/hibernacao. Nunca excluir hiberfil.sys manualmente.') }
        @{ Key = 'Paging'; Title = 'Memoria virtual - pagefile e swapfile'; Steps = @('Esses arquivos atendem memoria virtual e podem ser necessarios para dumps.', 'Mantenha o gerenciamento pelo sistema como ponto de partida.', 'Se o tamanho parecer anormal, encaminhe ao suporte para avaliar RAM, carga e configuracao de dump.', 'Nao remover, desativar ou reduzir automaticamente para ganhar espaco; valide estabilidade apos qualquer alteracao aprovada.') }
        @{ Key = 'MemoryDump'; Title = 'MEMORY.DMP'; Steps = @('Confirme se ha tela azul ou incidente pendente.', 'Preserve a evidencia em destino aprovado conforme retencao e confidencialidade.', 'Apos encerramento e autorizacao, use a categoria de dumps de erro na limpeza do Windows quando disponivel.', 'Se retornar, investigar a falha; a limpeza nao resolve a causa.') }
        @{ Key = 'Update'; Title = 'Cache do Windows Update'; Steps = @('Confira atualizacoes pendentes e reinicie se solicitado pelo Windows.', 'Use Arquivos temporarios ou Limpeza de Disco > Limpar arquivos do sistema > Limpeza do Windows Update, quando disponivel.', 'Nao apagar SoftwareDistribution durante uma instalacao; reset de cache pertence ao atendimento de falhas de update.', 'Valide historico, nova verificacao de updates e espaco livre.') }
        @{ Key = 'Ccm'; Title = 'SCCM / CCMCache'; Steps = @('Confirme instalacoes ou distribuicoes pendentes no Software Center.', 'Solicite ao suporte a revisao do cache no Painel de Controle > Configuration Manager > Cache.', 'Use Delete Files pela interface suportada, respeitando conteudo persistente e a politica corporativa.', 'Nao excluir a pasta ccmcache pelo Explorer ou por comandos; valide as implantacoes depois.') }
        @{ Key = 'Upgrade'; Title = 'Windows.old e caches de upgrade'; Steps = @('Confirme que o upgrade foi validado e que nao sera necessario voltar a versao anterior.', 'Confira se existem dados do usuario a recuperar na instalacao antiga.', 'Use Armazenamento > Arquivos temporarios > Instalacoes anteriores do Windows, quando disponivel.', 'A remocao elimina a possibilidade de voltar pela instalacao anterior; nao apagar essas pastas manualmente.') }
        @{ Key = 'Dumps'; Title = 'DMP grandes (>=100 MB)'; Steps = @('Identifique o aplicativo ou sistema que gerou o dump.', 'Confirme incidente e retencao; preserve amostras necessarias antes da limpeza.', 'Use a limpeza suportada pelo aplicativo ou Windows depois da autorizacao.', 'Monitore novas falhas; dumps recorrentes exigem corrigir a causa.') }
        @{ Key = 'Logs'; Title = 'Logs grandes (>=200 MB)'; Steps = @('Identifique servico/aplicativo e politica de retencao.', 'Preserve evidencias e confirme se o log esta aberto.', 'Configure rotacao, limite e arquivamento pela ferramenta do produtor.', 'Nao apagar um log ativo indiscriminadamente; acompanhe o crescimento apos a correcao.') }
        @{ Key = 'ListSync'; Title = 'OneDrive - Microsoft.ListSync.db'; Steps = @('Confirme a versao, saude da sincronizacao e o componente que usa a base.', 'O tamanho nao demonstra que a base pode ser descartada.', 'Encaminhe ao suporte de OneDrive/Lists para procedimento especifico da versao; nao excluir a base ou resetar a conta automaticamente.', 'Valide listas e sincronizacao; use arquivos sob demanda para reduzir dados locais elegiveis.') }
        @{ Key = 'OneDrive'; Title = 'OneDrive - arquivos grandes (>=500 MB)'; Steps = @('Confirme que o arquivo esta sincronizado e acessivel pela conta corporativa.', 'O tamanho listado e logico; arquivos somente na nuvem podem ocupar pouco espaco local.', 'No Explorer, em arquivos elegiveis, escolha Liberar espaco; isso exige internet para abrir novamente.', 'Nao usar Excluir como equivalente: a exclusao pode sincronizar com a nuvem. Valide disponibilidade e espaco no disco.') }
        @{ Key = 'Recycle'; Title = 'Lixeira'; Steps = @('Abra a Lixeira e revise os itens com o usuario.', 'Restaure o que ainda for necessario.', 'Esvazie apenas apos confirmacao; isso remove a recuperacao local dos itens.', 'A coleta pode enxergar apenas parte das lixeiras; valide o ganho pelo espaco livre do volume.') }
    ) | ForEach-Object { [pscustomobject]$_ }
}

function Get-ToolkitStorageFileKinds {
    param([string]$RelativePath, [long]$Length)

    $path = $RelativePath.Replace('/', '\').TrimStart('\').ToLowerInvariant()
    $kinds = @('Large')
    if ($path -match '^users\\.*\.(ost|pst|nst)$' -and $Length -ge 100MB) { $kinds += [cultureinfo]::InvariantCulture.TextInfo.ToTitleCase($Matches[1]) }
    if ($path -match '^programdata\\microsoft\\search\\data\\applications\\windows\\windows\.(edb|db)$') { $kinds += 'Search' }
    if ($path.StartsWith('windows\temp\')) {
        $kinds += @('WindowsTemp', 'TempTop')
        if ($path.EndsWith('.evtx')) { $kinds += 'TempEvtx' }
    }
    if ($path -match '^users\\[^\\]+\\appdata\\local\\temp\\') { $kinds += 'UserTemp' }
    if ($path -eq 'hiberfil.sys') { $kinds += 'Hibernation' }
    if ($path -in @('pagefile.sys', 'swapfile.sys')) { $kinds += 'Paging' }
    if ($path -eq 'windows\memory.dmp') { $kinds += 'MemoryDump' }
    if ($path.StartsWith('windows\softwaredistribution\download\')) { $kinds += 'Update' }
    if ($path.StartsWith('windows\ccmcache\')) { $kinds += 'Ccm' }
    if ($path -match '^(windows\.old|\$windows\.~bt|\$windows\.~ws)\\') { $kinds += 'Upgrade' }
    if ($path.EndsWith('.dmp') -and $Length -ge 100MB) { $kinds += 'Dumps' }
    if ($path.EndsWith('.log') -and $Length -ge 200MB) { $kinds += 'Logs' }
    if ($path -match '^users\\.*\\microsoft\.listsync\.db$') { $kinds += 'ListSync' }
    if ($path -match '^users\\[^\\]+\\onedrive([^\\]*)\\' -and $Length -ge 500MB) { $kinds += 'OneDrive' }
    if ($path.StartsWith('$recycle.bin\')) { $kinds += 'Recycle' }
    return $kinds
}

function Get-ToolkitStorageSnapshot {
    [CmdletBinding()]
    param(
        [string]$ScanRoot = ($env:SystemDrive + '\'),
        [ValidateRange(1, 600)][int]$MaxSeconds = 120,
        [ValidateRange(1, 1000000)][int]$MaxFiles = 200000
    )

    $root = [IO.Path]::GetFullPath($ScanRoot).TrimEnd('\') + '\'
    if (-not [IO.Directory]::Exists($root)) { throw 'Raiz da varredura indisponivel.' }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $buckets = @{}
    foreach ($item in Get-ToolkitStorageGuidance) {
        $buckets[$item.Key] = [pscustomobject]@{ Key = $item.Key; Count = 0; Bytes = [long]0; Files = @() }
    }
    $disks = @()
    $errors = 0
    try {
        $disks = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Total = $_.TotalSize; Free = $_.AvailableFreeSpace }
        })
    }
    catch { $errors++ }
    $userTemps = @{}
    $profiles = @()
    try {
        $usersPath = Join-Path $root 'Users'
        if ([IO.Directory]::Exists($usersPath)) {
            $profiles = @([IO.DirectoryInfo]::new($usersPath).GetDirectories() | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; Path = $_.FullName; LastWriteTime = $_.LastWriteTime }
            })
        }
    }
    catch { $errors++ }
    $searchStatus = 'Nao coletado'
    try { $searchStatus = [string](Get-Service WSearch -ErrorAction Stop).Status } catch { $errors++ }
    $queue = [Collections.Generic.Queue[string]]::new()
    $visited = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $queue.Enqueue($root)
    $count = 0
    $skipped = 0
    $limited = $false
    while ($queue.Count -gt 0 -and -not $limited) {
        $directory = $queue.Dequeue()
        if (-not $visited.Add($directory.TrimEnd("\"))) { continue }
        try {
            foreach ($entry in [IO.DirectoryInfo]::new($directory).EnumerateFileSystemInfos()) {
                if ($watch.Elapsed.TotalSeconds -ge $MaxSeconds -or $count -ge $MaxFiles) { $limited = $true; break }
                if (($entry.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $skipped++; continue }
                    $queue.Enqueue($entry.FullName)
                    continue
                }
                $count++
                $file = [pscustomobject]@{ Path = $entry.FullName; Bytes = [long]$entry.Length; LastWriteTime = $entry.LastWriteTime; Attributes = [string]$entry.Attributes }
                $relative = $entry.FullName.Substring($root.Length)
                foreach ($kind in @(Get-ToolkitStorageFileKinds -RelativePath $relative -Length $file.Bytes)) {
                    $bucket = $buckets[$kind]
                    if ($kind -eq 'UserTemp' -and $relative -match '^Users\\([^\\]+)\\') {
                        $profileName = $Matches[1]
                        if (-not $userTemps.ContainsKey($profileName)) {
                            $userTemps[$profileName] = [pscustomobject]@{ Name = $profileName; Bytes = [long]0; Count = 0 }
                        }
                        $userTemps[$profileName].Bytes += $file.Bytes
                        $userTemps[$profileName].Count++
                    }
                    $bucket.Count++
                    $bucket.Bytes += $file.Bytes
                    $limit = if ($kind -eq 'TempTop') { 30 } elseif ($kind -eq 'OneDrive') { 40 } else { 60 }
                    if ($bucket.Files.Count -lt $limit -or $file.Bytes -gt $bucket.Files[-1].Bytes) {
                        $bucket.Files = @(@($bucket.Files) + $file | Sort-Object Bytes -Descending | Select-Object -First $limit)
                    }
                }
            }
        }
        catch { $errors++ }
        if ($watch.Elapsed.TotalSeconds -ge $MaxSeconds) { $limited = $true }
    }
    $endDisks = @()
    try {
        $endDisks = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Total = $_.TotalSize; Free = $_.AvailableFreeSpace }
        })
    }
    catch { $errors++ }
    $watch.Stop()
    [pscustomobject]@{
        Root = $root; ComputerName = $env:COMPUTERNAME; GeneratedAt = Get-Date; Disks = $disks; Profiles = $profiles
        SearchStatus = $searchStatus; Categories = $buckets; FilesVisited = $count
        UserTemps = @($userTemps.Values); EndDisks = $endDisks
        Errors = $errors; SkippedLinks = $skipped; LimitReached = $limited
        Partial = ($limited -or $errors -gt 0 -or $skipped -gt 0)
        Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 1)
    }
}

function Format-ToolkitStorageReport {
    param([Parameter(Mandatory = $true)]$Snapshot)

    $sb = [Text.StringBuilder]::new()
    [void]$sb.AppendLine('ESPACO EM DISCO - LEITURA E PLANO DE LIBERACAO')
    [void]$sb.AppendLine('Consulta sem exclusao de arquivos ou alteracao de servicos.')
    [void]$sb.AppendLine("Gerado em: $($Snapshot.GeneratedAt.ToString('dd/MM/yyyy HH:mm:ss'))")
    [void]$sb.AppendLine("Raiz: $($Snapshot.Root) | Arquivos lidos: $($Snapshot.FilesVisited) | Duracao: $($Snapshot.Seconds)s")
    [void]$sb.AppendLine("Cobertura parcial: $($Snapshot.Partial) | Limite atingido: $($Snapshot.LimitReached) | Falhas de acesso/coleta: $($Snapshot.Errors) | Diretorios com links ignorados: $($Snapshot.SkippedLinks)")
    [void]$sb.AppendLine('Limites sao cooperativos: uma chamada de disco lenta pode atrasar a conclusao.')
    [void]$sb.AppendLine('Tamanhos sao logicos, nao estimativa de bytes recuperaveis. Categorias se sobrepoem; nao somar os totais.')
    [void]$sb.AppendLine('Ausencia na leitura parcial nao comprova ausencia de arquivos. Outros discos nao foram varridos.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('RESUMO E INDICE POR SITUACAO')
    [void]$sb.AppendLine('Localize o numero entre colchetes para consultar arquivos, solucao e validacao.')
    [void]$sb.AppendLine('[1] Discos - capacidade e alerta | [2] Perfis - confirmar dono e uso')
    $guides = @(Get-ToolkitStorageGuidance)
    $summarySection = 3
    foreach ($guide in $guides) {
        $bucket = $Snapshot.Categories[$guide.Key]
        if ($bucket.Count -eq 0) {
            $size = 'Nao observado no escopo lido'
        }
        elseif ($bucket.Bytes -ge 1GB) { $size = '{0:N2} GB logicos' -f ($bucket.Bytes / 1GB) }
        elseif ($bucket.Bytes -ge 1MB) { $size = '{0:N2} MB logicos' -f ($bucket.Bytes / 1MB) }
        elseif ($bucket.Bytes -ge 1KB) { $size = '{0:N2} KB logicos' -f ($bucket.Bytes / 1KB) }
        else { $size = '{0:N0} bytes logicos' -f $bucket.Bytes }
        [void]$sb.AppendLine(('[{0}] {1} | {2} arquivo(s) | {3}' -f $summarySection, $guide.Title, $bucket.Count, $size))
        $summarySection++
    }
    [void]$sb.AppendLine('Os volumes observados nao indicam quanto pode ser excluido; revise o passo a passo de cada situacao.')
    [void]$sb.AppendLine('Apos as categorias: estado final da leitura e validacao apos a liberacao.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('[1] DISCOS - LEITURA INICIAL')
    foreach ($disk in $Snapshot.Disks) {
        $percent = if ($disk.Total -gt 0) { 100 * $disk.Free / $disk.Total } else { 0 }
        $status = if ($disk.Free -lt 5GB -or $percent -lt 5) { 'CRITICO' } elseif ($disk.Free -lt 10GB -or $percent -lt 10) { 'ATENCAO' } else { 'SEM ALERTA POR ESTE CRITERIO' }
        [void]$sb.AppendLine(('{0}: {1:N2} GB livres de {2:N2} GB ({3:N1}%) - {4}' -f $disk.Name, ($disk.Free / 1GB), ($disk.Total / 1GB), $percent, $status))
    }
    [void]$sb.AppendLine('Criterio interno de triagem; necessidade real depende do uso e das atualizacoes.')
    [void]$sb.AppendLine('Se critico: comece por itens revisados na Lixeira e temporarios; valide dados sincronizados e arquivos grandes. Se insuficiente, escale capacidade/retencao; nao remover arquivos de sistema por tamanho.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('[2] PERFIS EXISTENTES')
    foreach ($profile in $Snapshot.Profiles) { [void]$sb.AppendLine("$($profile.Name) | $($profile.Path) | Alterado: $($profile.LastWriteTime)") }
    [void]$sb.AppendLine('Data da pasta nao indica ultimo login. Confirmar dono, sessoes e backup; se realmente obsoleto, suporte deve usar Propriedades do Sistema > Avancado > Perfis de Usuario > Configuracoes. Nao excluir C:\Users manualmente nem o perfil em uso.')
    [void]$sb.AppendLine("WSearch: $($Snapshot.SearchStatus)")
    $section = 3
    foreach ($guide in $guides) {
        $bucket = $Snapshot.Categories[$guide.Key]
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("[$section] $($guide.Title)")
        [void]$sb.AppendLine(('Observado: {0} arquivo(s), {1:N2} GB logicos. Lista limitada aos maiores.' -f $bucket.Count, ($bucket.Bytes / 1GB)))
        if ($bucket.Count -eq 0) { [void]$sb.AppendLine('Nao observado no escopo lido. Nao iniciar limpeza desta categoria com base somente neste resultado.') }
        if ($guide.Key -eq 'UserTemp') {
            [void]$sb.AppendLine('Perfis com mais de 50 MB de temporarios observados:')
            foreach ($userTemp in @($Snapshot.UserTemps | Where-Object Bytes -gt 50MB | Sort-Object Bytes -Descending)) {
                [void]$sb.AppendLine(('{0}: {1:N2} GB, {2} arquivo(s)' -f $userTemp.Name, ($userTemp.Bytes / 1GB), $userTemp.Count))
            }
        }
        foreach ($file in $bucket.Files) {
            [void]$sb.AppendLine(('{0:N2} GB | {1} | {2} | {3}' -f ($file.Bytes / 1GB), $file.LastWriteTime, $file.Attributes, $file.Path))
        }
        [void]$sb.AppendLine('SOLUCAO E PASSO A PASSO (aplicar apenas se o achado for confirmado):')
        $step = 1
        foreach ($instruction in $guide.Steps) { [void]$sb.AppendLine("  $step. $instruction"); $step++ }
        $section++
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('ESTADO FINAL DA LEITURA (nenhuma limpeza executada)')
    foreach ($disk in $Snapshot.EndDisks) {
        [void]$sb.AppendLine(('{0}: {1:N2} GB livres ao concluir a coleta' -f $disk.Name, ($disk.Free / 1GB)))
    }
    [void]$sb.AppendLine('Mudancas durante a leitura podem vir de outros processos; nao atribuir diferenca a uma limpeza do Toolkit.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('VALIDACAO APOS A LIBERACAO')
    [void]$sb.AppendLine('1. Anote o livre inicial. Execute apenas a limpeza revisada e autorizada, uma categoria por vez.')
    [void]$sb.AppendLine('2. Repita este diagnostico e compare o livre da mesma unidade. A leitura atual nao mede ganho de limpeza.')
    [void]$sb.AppendLine('3. Valide Outlook, busca, sincronizacao e atualizacoes conforme a acao. Investigue itens que voltam a crescer.')
    [void]$sb.AppendLine('4. Se houver acesso negado, coleta parcial ou causa nao identificada, escale a analise. O ganho nao e garantido.')
    return $sb.ToString()
}

function Format-ToolkitStorageComparison {
    param([Parameter(Mandatory = $true)]$Before, [Parameter(Mandatory = $true)]$After)

    if ([string]::IsNullOrWhiteSpace($Before.ComputerName) -or $Before.ComputerName -ne $After.ComputerName -or $Before.Root -ne $After.Root) {
        throw 'Compare leituras da mesma estacao e da mesma raiz.'
    }
    if ($After.GeneratedAt -le $Before.GeneratedAt) { throw 'A leitura final deve ser posterior a leitura inicial.' }
    $sb = [Text.StringBuilder]::new()
    [void]$sb.AppendLine('ESPACO EM DISCO - COMPARACAO DE LEITURAS')
    [void]$sb.AppendLine("Inicial: $($Before.GeneratedAt.ToString('dd/MM/yyyy HH:mm:ss')) | Final: $($After.GeneratedAt.ToString('dd/MM/yyyy HH:mm:ss'))")
    [void]$sb.AppendLine('Valores de espaco livre ao concluir cada coleta. Nenhuma limpeza e executada por esta comparacao.')
    [void]$sb.AppendLine("Cobertura dos arquivos: inicial parcial=$($Before.Partial); final parcial=$($After.Partial).")
    [void]$sb.AppendLine('A variacao pode incluir atividade de outros processos; nao comprova quanto uma limpeza recuperou.')
    [void]$sb.AppendLine('')
    $names = @(@($Before.EndDisks | ForEach-Object { $_.Name }) + @($After.EndDisks | ForEach-Object { $_.Name }) | Select-Object -Unique)
    if ($names.Count -eq 0) { [void]$sb.AppendLine('Sem leituras finais de capacidade disponiveis para comparar.') }
    foreach ($name in $names) {
        $initial = @($Before.EndDisks | Where-Object Name -eq $name)
        $final = @($After.EndDisks | Where-Object Name -eq $name)
        if ($initial.Count -ne 1 -or $final.Count -ne 1 -or $initial[0].Total -ne $final[0].Total) {
            [void]$sb.AppendLine("${name}: NAO COMPARAVEL - unidade ausente, duplicada ou capacidade alterada.")
            continue
        }
        $delta = [long]$final[0].Free - [long]$initial[0].Free
        $direction = if ($delta -gt 0) { 'AUMENTOU' } elseif ($delta -lt 0) { 'DIMINUIU' } else { 'SEM VARIACAO' }
        [void]$sb.AppendLine(('{0}: inicial {1:N2} GB livres | final {2:N2} GB livres | {3}: {4:N2} MB ({5:N2} GB)' -f $name, ($initial[0].Free / 1GB), ($final[0].Free / 1GB), $direction, ([math]::Abs($delta) / 1MB), ([math]::Abs($delta) / 1GB)))
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Valide os aplicativos e a mesma unidade apos cada acao autorizada. Nao somar categorias sobrepostas nem tratar tamanho logico como ganho.')
    return $sb.ToString()
}

Export-ModuleMember -Function Get-ToolkitStorageGuidance, Get-ToolkitStorageFileKinds, Get-ToolkitStorageSnapshot, Format-ToolkitStorageReport, Format-ToolkitStorageComparison
