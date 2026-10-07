# Espaço em disco: leitura e plano de liberação

No tema Windows, abra **Espaço em disco: diagnóstico e plano**. A leitura ocorre em segundo plano; use **Cancelar coleta** para interromper. O relatório lista discos e perfis, arquivos observados e soluções por categoria, com orientações mesmo quando um item não foi observado. Execute a solução somente após confirmar o achado.

## Como interpretar

O início do relatório apresenta um resumo das vinte categorias, com quantidade de arquivos, tamanho observado em bytes/KB/MB/GB e número da seção com a solução. Use esse índice para localizar o passo a passo; as quantidades não representam espaço recuperável.

Para encontrar uma categoria ou arquivo, use **Localizar no resultado** ou **Ctrl+Shift+F**. A área de leitura é ampliada e o trecho encontrado fica selecionado. **Próxima/Anterior**, **F3/Shift+F3** e **Enter/Shift+Enter** percorrem as ocorrências, voltando ao início ou fim da lista. **Esc** fecha a busca; **Voltar às ações** restaura os cartões. A busca é literal e ignora maiúsculas/minúsculas; acentos devem corresponder ao texto do relatório. **Ctrl+F** continua procurando ações do programa.

Para navegar por tema, use o seletor **Ir para uma seção...** na barra do resultado. Ele reúne os títulos numerados das seções de detalhes, como Outlook, temporários e Lixeira. A escolha amplia a leitura e seleciona o título no relatório. Se a busca de texto estiver aberta, ela é fechada para mostrar o destino; o termo fica disponível ao reabrir a busca. Relatórios sem títulos numerados ocultam o seletor.

- O coletor usa a unidade do Windows, limites padrão de 120 segundos e 200.000 arquivos. Limites são cooperativos; uma chamada de disco lenta pode atrasar a conclusão.
- Acessos negados, coleta indisponível, links ignorados e limite atingido indicam cobertura parcial. Não interpretar ausência de achados como prova de ausência nesses casos.
- Tamanho lógico não equivale a espaço ocupado nem a ganho recuperável. Categorias se sobrepõem: EVTX pode estar em Temp e na lista geral; MEMORY.DMP também aparece em dumps. Não somar os totais.
- Pastas com links de redirecionamento não são percorridas. Outros discos e caminhos personalizados de perfis/OneDrive podem exigir análise adicional. A coleta não lê o conteúdo de emails ou documentos.
- São listados até 60 arquivos por categoria, 30 no ranking de Windows Temp e 40 em OneDrive. O total observado inclui todos os arquivos enquadrados, não apenas os exibidos.

## Ordem de atendimento

1. Registre a unidade e o espaço livre inicial. Menos de 5 GB ou 5% gera alerta crítico; menos de 10 GB ou 10% gera atenção. Esses são critérios internos de triagem, não uma garantia de espaço suficiente.
2. Confirme o proprietário, o backup, a retenção e se há instalações ou sessões ativas. Comece pelos itens revisados na Lixeira e temporários; depois avalie arquivos grandes e dados sincronizados.
3. Aplique uma solução por vez pela ferramenta adequada, depois da autorização de quem responde pelos dados. O programa não faz exclusões automáticas nem desativa serviços.
4. Repita a leitura, compare o espaço livre da mesma unidade e valide os aplicativos envolvidos. A leitura inicial e final do script original não mede ganho se nenhuma limpeza aconteceu entre elas.
5. Se o espaço continuar insuficiente, revise retenção/capacidade com o suporte. Crescimento recorrente de logs, dumps ou temporários exige corrigir o produtor.

## Registrar e comparar antes/depois

1. Execute **Espaço em disco: diagnóstico e plano** e aguarde a conclusão.
2. Use **Salvar relatório** para guardar o texto em `.txt` no local escolhido. O texto é capturado ao clicar; um resultado novo durante a escolha do destino não muda o conteúdo salvo. Revise dados e caminhos antes de compartilhar.
3. Clique em **Definir leitura inicial**. Essa leitura fica guardada na memória desta sessão; salvar o texto não cria uma base que possa ser importada depois. Definir novamente substitui a base anterior.
4. O suporte realiza a ação revisada e autorizada. O Toolkit não executa limpeza por esses controles.
5. Clique em **Voltar às ações** e repita o diagnóstico. Ao concluir uma nova coleta, **Comparar leituras** fica disponível.
6. Confira aumento ou redução do espaço livre por unidade. A comparação usa as medidas ao fim de cada coleta; exige a mesma estação, raiz e leitura final posterior. Unidades ausentes, duplicadas ou com capacidade alterada são marcadas como não comparáveis. Nome e capacidade não identificam fisicamente um disco substituído.
7. Salve também a comparação e valide os aplicativos. A variação inclui atividade de outros processos e não prova ganho causado pela limpeza. A cobertura parcial dos arquivos continua indicada.

Cancelamento ou falha de uma coleta mantém as leituras concluídas na sessão. Ao fechar o programa, a base em memória é perdida; os arquivos `.txt` salvos permanecem no destino escolhido. **Salvar relatório** também funciona nos outros diagnósticos.

## Perfis existentes

A data de alteração da pasta não comprova o último login. Confirme o proprietário e as sessões ativas; faça backup validado dos dados necessários. Apenas para perfil comprovadamente obsoleto, o suporte pode usar Propriedades do Sistema > Avançado > Perfis de Usuário > Configurações. Não apague C:\Users manualmente nem remova o perfil em uso.

## Maiores arquivos

1. Identifique o aplicativo e o dono do arquivo.
2. Separe documentos, instaladores e backups de arquivos de sistema.
3. Mova dados autorizados para um destino aprovado e confirme a copia antes de remover a origem.
4. Para aplicativos sem uso, prefira desinstalar em Configuracoes > Aplicativos.

## Outlook - OST

1. Confirme que a caixa esta sincronizada e que nao existem itens locais pendentes.
2. No Outlook classico, revise o periodo de email mantido offline conforme a politica da empresa.
3. Use Configuracoes de Conta > Arquivos de Dados > Configuracoes para verificar as opcoes de compactacao.
4. Recriar OST exige suporte, sincronizacao confirmada e espaco para novo download; nao apagar diretamente.

## Outlook - PST

1. PST pode conter a unica copia de emails: confirme o proprietario e a retencao.
2. Feche o Outlook e guarde uma copia verificada em destino aprovado.
3. Revise os itens com o usuario; no Outlook classico use Arquivos de Dados > Configuracoes > Compactar Agora quando disponivel.
4. Reabra o Outlook e confira pastas e mensagens; nao excluir PST para liberar espaco sem validar seu conteudo.

## Outlook - NST

1. Identifique a conta, grupos e versao do Outlook que usam o arquivo.
2. Confirme sincronizacao e integridade com o suporte de mensageria.
3. Revise a configuracao de cache suportada nessa versao; nao tratar NST como arquivo descartavel.
4. Valide os grupos e a sincronizacao antes de qualquer recriacao supervisionada.

## Windows Search

1. Compare o tamanho do indice e confira o estado do WSearch.
2. Abra Opcoes de Indexacao e reduza locais sem necessidade de pesquisa conforme a politica.
3. Se houver falha ou crescimento anormal, use Avancado > Recriar com autorizacao; a busca ficara incompleta durante a indexacao.
4. Aguarde a conclusao e valide a pesquisa no Windows e Outlook. Nao remover Windows.edb ou Windows.db manualmente.

## Windows Temp

1. Feche aplicativos e confirme que nao ha instalacao ou atualizacao em andamento.
2. Abra Configuracoes > Sistema > Armazenamento > Arquivos temporarios.
3. Revise cada categoria e execute a limpeza aprovada; Downloads exige revisao separada.
4. Arquivos em uso devem permanecer; se o volume voltar a crescer, investigue o processo gerador.

## Maiores arquivos do Windows Temp

1. Use a lista para identificar os maiores produtores de temporarios.
2. Confira data, aplicativo e se o arquivo esta em uso.
3. Aplique a limpeza de temporarios pela ferramenta do Windows ou pelo aplicativo responsavel.
4. Compare o tamanho depois e investigue recorrencia; idade sozinha nao autoriza exclusao.

## EVTX no Windows Temp

1. Identifique qual processo esta gravando os eventos e se existe incidente em investigacao.
2. Guarde a evidencia necessaria em destino aprovado e valide a retencao.
3. Apos autorizacao, revise os arquivos temporarios elegiveis; nao limpar logs ativos do Windows indiscriminadamente.
4. Se os EVTX reaparecerem, corrija a causa com a equipe responsavel.

## Temporarios dos usuarios

1. Confirme quais usuarios e sessoes estao ativos.
2. Para o perfil atual, feche aplicativos e use a limpeza de temporarios suportada.
3. Outros perfis exigem contato com o dono e suporte administrativo; nao apagar dados de sessoes ativas.
4. Repita a leitura e valide os aplicativos afetados.

## Hibernacao - hiberfil.sys

1. Confirme se a estacao usa hibernacao ou Inicializacao Rapida.
2. Prefira limpeza de dados e caches antes de alterar energia.
3. Somente se a politica permitir, o suporte pode avaliar powercfg /hibernate off com elevacao; isso altera recursos de energia.
4. Para reverter use powercfg /hibernate on; valide suspensao/hibernacao. Nunca excluir hiberfil.sys manualmente.

## Memoria virtual - pagefile e swapfile

1. Esses arquivos atendem memoria virtual e podem ser necessarios para dumps.
2. Mantenha o gerenciamento pelo sistema como ponto de partida.
3. Se o tamanho parecer anormal, encaminhe ao suporte para avaliar RAM, carga e configuracao de dump.
4. Nao remover, desativar ou reduzir automaticamente para ganhar espaco; valide estabilidade apos qualquer alteracao aprovada.

## MEMORY.DMP

1. Confirme se ha tela azul ou incidente pendente.
2. Preserve a evidencia em destino aprovado conforme retencao e confidencialidade.
3. Apos encerramento e autorizacao, use a categoria de dumps de erro na limpeza do Windows quando disponivel.
4. Se retornar, investigar a falha; a limpeza nao resolve a causa.

## Cache do Windows Update

1. Confira atualizacoes pendentes e reinicie se solicitado pelo Windows.
2. Use Arquivos temporarios ou Limpeza de Disco > Limpar arquivos do sistema > Limpeza do Windows Update, quando disponivel.
3. Nao apagar SoftwareDistribution durante uma instalacao; reset de cache pertence ao atendimento de falhas de update.
4. Valide historico, nova verificacao de updates e espaco livre.

## SCCM / CCMCache

1. Confirme instalacoes ou distribuicoes pendentes no Software Center.
2. Solicite ao suporte a revisao do cache no Painel de Controle > Configuration Manager > Cache.
3. Use Delete Files pela interface suportada, respeitando conteudo persistente e a politica corporativa.
4. Nao excluir a pasta ccmcache pelo Explorer ou por comandos; valide as implantacoes depois.

## Windows.old e caches de upgrade

1. Confirme que o upgrade foi validado e que nao sera necessario voltar a versao anterior.
2. Confira se existem dados do usuario a recuperar na instalacao antiga.
3. Use Armazenamento > Arquivos temporarios > Instalacoes anteriores do Windows, quando disponivel.
4. A remocao elimina a possibilidade de voltar pela instalacao anterior; nao apagar essas pastas manualmente.

## DMP grandes (>=100 MB)

1. Identifique o aplicativo ou sistema que gerou o dump.
2. Confirme incidente e retencao; preserve amostras necessarias antes da limpeza.
3. Use a limpeza suportada pelo aplicativo ou Windows depois da autorizacao.
4. Monitore novas falhas; dumps recorrentes exigem corrigir a causa.

## Logs grandes (>=200 MB)

1. Identifique servico/aplicativo e politica de retencao.
2. Preserve evidencias e confirme se o log esta aberto.
3. Configure rotacao, limite e arquivamento pela ferramenta do produtor.
4. Nao apagar um log ativo indiscriminadamente; acompanhe o crescimento apos a correcao.

## OneDrive - Microsoft.ListSync.db

1. Confirme a versao, saude da sincronizacao e o componente que usa a base.
2. O tamanho nao demonstra que a base pode ser descartada.
3. Encaminhe ao suporte de OneDrive/Lists para procedimento especifico da versao; nao excluir a base ou resetar a conta automaticamente.
4. Valide listas e sincronizacao; use arquivos sob demanda para reduzir dados locais elegiveis.

## OneDrive - arquivos grandes (>=500 MB)

1. Confirme que o arquivo esta sincronizado e acessivel pela conta corporativa.
2. O tamanho listado e logico; arquivos somente na nuvem podem ocupar pouco espaco local.
3. No Explorer, em arquivos elegiveis, escolha Liberar espaco; isso exige internet para abrir novamente.
4. Nao usar Excluir como equivalente: a exclusao pode sincronizar com a nuvem. Valide disponibilidade e espaco no disco.

## Lixeira

1. Abra a Lixeira e revise os itens com o usuario.
2. Restaure o que ainda for necessario.
3. Esvazie apenas apos confirmacao; isso remove a recuperacao local dos itens.
4. A coleta pode enxergar apenas parte das lixeiras; valide o ganho pelo espaco livre do volume.

## Base técnica e limites

A Microsoft recomenda revisar categorias nas ferramentas de armazenamento e distingue arquivos sob demanda do tamanho local. A remoção de Windows.old elimina a opção de voltar pela instalação anterior. [Liberação de espaço no Windows](https://support.microsoft.com/en-gb/windows/experience/storage-filemanagement/free-up-drive-space-in-windows).

A compactação de PST/OST é feita pelas opções de dados do Outlook; o fluxo varia por tipo de conta. [Redução de arquivos de dados do Outlook](https://support.microsoft.com/en-us/outlook/reduce-the-size-of-your-mailbox-and-outlook-data-files-pst-and-ost).

CCMCache deve ser administrado pelo Configuration Manager, sem excluir arquivos diretamente na pasta. [Cache do cliente](https://learn.microsoft.com/en-us/intune/configmgr/core/clients/manage/configure-client-cache).

Recriar o índice deve usar as opções de indexação do Windows. [Windows Search](https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/windows-search-performance-issues).

Hibernação e arquivo de paginação exigem avaliação de energia, memória e dumps. [Powercfg](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options), [Dimensionamento de paginação](https://learn.microsoft.com/en-gb/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows).

NST e Microsoft.ListSync.db não têm um procedimento universal de exclusão neste atendimento; encaminhe ao suporte do produto para a versão em uso. Caminhos e nomes de arquivos do relatório podem conter dados corporativos: compartilhe apenas evidências sanitizadas.
