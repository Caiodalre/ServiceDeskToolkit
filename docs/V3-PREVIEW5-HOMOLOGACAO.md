# Plano de homologação interna — V3 preview 5

## Identificação

| Campo | Valor |
| --- | --- |
| Produto | ServiceDesk Toolkit Corporate V3 |
| Candidato funcional | `v3.0.0-preview.5` |
| Commit da tag | `b12afa0fb0fe7d77b928f75c2cb6b67616fc1d77` |
| Base de automação validada | `49551635aac7ae6fd0435ce1d203c540a528c1c0` |
| Linha estável de retorno | `v2.3.0` |
| Início planejado | 2026-07-27 |
| Status inicial | Não iniciada |

A tag `v3.0.0-preview.5` é imutável e continua sendo o artefato funcional a
ser instalado. O commit `4955163` contém apenas correções do CI e do escopo dos
testes; não altera o código funcional do toolkit. Qualquer mudança funcional
posterior invalida esta rodada e exige uma nova tag de preview.

## Objetivo

Verificar, em ambientes Windows representativos, que a V3 pode ser instalada,
executada e usada pelo Service Desk sem regressões críticas, exposição de dados
ou alteração inesperada do estado da estação.

A homologação não promove automaticamente a V3 para estável. Ela produz uma
decisão registrada: aprovar o próximo candidato, aprovar com ressalvas ou
reprovar e retornar para correção.

## Escopo funcional

Incluído nesta rodada:

- instalação a partir da tag fixa;
- inicialização em usuário padrão e em modo administrador;
- shell visual, sidebar, cards, resultado central e atendimento rápido;
- painéis de Saúde, Inventário, Rede e Impressoras;
- links externos com proteção contra abertura dupla;
- comportamento somente leitura dos diagnósticos;
- mensagens de erro, relatórios e evidências disponíveis;
- isolamento da instalação V3 e convivência com a V2 estável.

Fora do escopo desta rodada:

- declarar a V3 substituta da V2.3.0;
- ações avançadas ainda não conectadas ao fluxo visual;
- distribuição em massa;
- telemetria corporativa centralizada;
- assinatura Authenticode e implantação por ferramenta de gestão.

Itens fora do escopo não bloqueiam o preview quando continuam indisponíveis e
claramente identificados. Eles bloqueiam a promoção estável caso sejam definidos
como requisito da operação.

## Papéis

| Papel | Responsabilidade |
| --- | --- |
| Coordenador | Controlar escopo, ambientes, evidências e decisão final |
| Homologador N1 | Executar instalação, navegação e diagnósticos comuns |
| Homologador N2 | Validar relatórios, cenários degradados e comportamento técnico |
| Administrador | Validar elevação, isolamento, reversão e ações privilegiadas disponíveis |
| Aprovador | Aceitar riscos residuais e autorizar o próximo candidato |

Uma pessoa pode acumular papéis em uma homologação pequena, mas a decisão deve
registrar quem executou e quem aprovou.

## Pré-condições

Antes do primeiro caso manual:

- [ ] A tag `v3.0.0-preview.5` existe e aponta para o commit registrado.
- [ ] `version-v3.json` informa `3.0.0-preview.5` e canal `preview`.
- [ ] O CI da base de automação está verde em PowerShell 5.1 e PowerShell 7.
- [ ] A estação ou VM possui snapshot, ponto de retorno ou procedimento de limpeza.
- [ ] Não há credenciais, pacotes de suporte ou dados corporativos reais na área pública do GitHub.
- [ ] A versão V2.3.0 permanece disponível como fallback operacional.
- [ ] O homologador conhece os casos que podem exigir elevação.

## Matriz mínima de ambientes

| Perfil | Sistema | PowerShell | Privilégio | Obrigatório |
| --- | --- | --- | --- | --- |
| ENV-A | Windows 11 corporativo | Windows PowerShell 5.1 | Usuário padrão | Sim |
| ENV-B | Windows 11 corporativo | PowerShell 7+ | Administrador | Sim |
| ENV-C | Windows 10 corporativo suportado internamente | Windows PowerShell 5.1 | Usuário padrão e administrador | Quando disponível |

Registrar edição, build do Windows, arquitetura, versão exata do PowerShell e
se o ambiente é físico ou virtual. A ausência do ENV-C exige uma ressalva formal;
não deve ser interpretada como compatibilidade comprovada com Windows 10.

## Instalação do candidato

Executar sempre a partir da tag fixa:

```powershell
$Version = "v3.0.0-preview.5"
$Installer = Join-Path $env:TEMP "ServiceDeskToolkitV3-install.ps1"
$Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/install-v3.ps1"

Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Branch $Version
```

Revisar o script baixado antes da execução. Não substituir a tag por branch de
desenvolvimento durante a homologação.

## Casos de teste

### Integridade, instalação e inicialização

| ID | Procedimento | Resultado esperado | Evidência mínima |
| --- | --- | --- | --- |
| HOM-001 | Conferir tag, commit e `version-v3.json` | Versão, canal e referência coincidem com este plano | Registro textual sanitizado |
| HOM-002 | Instalar pela tag fixa em diretório limpo | Instalação concluída em `%LOCALAPPDATA%\ServiceDeskToolkitV3` | Versão e caminho, sem dados pessoais |
| HOM-003 | Iniciar pelo launcher como usuário padrão | Janela abre sem prompt administrativo indevido | Captura da tela inicial |
| HOM-004 | Iniciar em modo administrador | Janela abre elevada e identifica corretamente o contexto | Captura sanitizada e resultado |
| HOM-005 | Reabrir após fechar normalmente | Não há processo órfão nem segunda instância inesperada | Resultado e lista resumida de processos |

### Experiência e navegação

| ID | Procedimento | Resultado esperado | Evidência mínima |
| --- | --- | --- | --- |
| HOM-010 | Percorrer sidebar, cards e atendimento rápido | Navegação estável, sem áreas vazias ou exceções | Capturas das telas principais |
| HOM-011 | Acionar links GitHub e LinkedIn duas vezes rapidamente | Cada destino abre uma vez por ação válida | Registro do comportamento |
| HOM-012 | Redimensionar e mover a janela em resolução corporativa | Conteúdo principal permanece utilizável | Resolução e captura |

### Diagnósticos modulares

| ID | Procedimento | Resultado esperado | Evidência mínima |
| --- | --- | --- | --- |
| HOM-020 | Executar Painel de Saúde | Score, classificação, indicadores e observações são coerentes | Relatório sanitizado |
| HOM-021 | Executar Inventário | Sistema, memória, disco, uptime e rede aparecem sem erro | Relatório sanitizado |
| HOM-022 | Executar Rede em cenário funcional e em cenário degradado controlado | Causa provável e próxima ação são coerentes; nenhuma correção é executada automaticamente | Dois relatórios sanitizados |
| HOM-023 | Executar Impressoras com spooler ativo e condição degradada controlada | Estado, filas e recomendação respeitam a prioridade operacional | Relatório sanitizado |
| HOM-024 | Repetir os quatro painéis na mesma sessão | Resultados atualizam sem duplicação, travamento ou vazamento de estado | Registro da sequência |

### Segurança operacional e resiliência

| ID | Procedimento | Resultado esperado | Evidência mínima |
| --- | --- | --- | --- |
| HOM-030 | Comparar serviços, rede e impressoras antes/depois dos diagnósticos | Diagnósticos não alteram o estado da estação | Comparativo sanitizado |
| HOM-031 | Induzir ausência controlada de dado ou serviço | A interface informa indisponibilidade sem encerrar abruptamente | Mensagem e cenário |
| HOM-032 | Executar sem privilégios uma função que exige administração | Ação é bloqueada ou solicita elevação de forma explícita | Mensagem apresentada |
| HOM-033 | Procurar senha, token, domínio, IP, serial e usuário nas evidências | Nenhum segredo ou identificador desnecessário é exposto | Checklist de sanitização |

### Ciclo de vida

| ID | Procedimento | Resultado esperado | Evidência mínima |
| --- | --- | --- | --- |
| HOM-040 | Reinstalar a mesma tag | Operação é idempotente ou informa claramente o estado existente | Resultado da reinstalação |
| HOM-041 | Confirmar convivência com a V2.3.0 | V2 permanece disponível e funcional | Resultado dos dois launchers |
| HOM-042 | Remover ou reverter a V3 conforme procedimento disponível | Ambiente retorna ao estado esperado sem afetar a V2 | Estado antes/depois |

## Registro por ambiente

Preencher uma linha para cada combinação de caso e ambiente.

| Caso | Ambiente | Resultado | Evidência | Defeito | Executor | Data |
| --- | --- | --- | --- | --- | --- | --- |
| HOM-001 | ENV-A | Pendente | — | — | — | — |

Resultados permitidos: `Aprovado`, `Reprovado`, `Bloqueado` ou `Não aplicável`.
Todo `Não aplicável` precisa de justificativa.

## Classificação de defeitos

| Severidade | Definição | Efeito na decisão |
| --- | --- | --- |
| Bloqueador | Perda de dados, risco de segurança, instalação ou inicialização impossível | Reprovação imediata |
| Crítico | Painel principal incorreto, ação indevida ou ausência de fallback | Reprovação até correção |
| Maior | Função relevante parcialmente inutilizável com alternativa conhecida | Exige responsável e prazo; não promove para estável |
| Menor | Defeito visual ou textual sem impacto operacional | Pode ser aceito com registro |

## Evidências e privacidade

Nome recomendado:

```text
HOM-<id>_<ambiente>_<AAAAMMDD>_<resultado>.<extensao>
```

As evidências completas devem permanecer em repositório interno com acesso
controlado. No GitHub público, registrar apenas resultados sanitizados. Remover
ou mascarar:

- usuário, e-mail e domínio corporativo;
- IP, gateway, DNS e nomes de hosts;
- serial, patrimônio e identificadores de hardware;
- nomes de impressoras, filas, servidores e compartilhamentos;
- tokens, cookies, caminhos pessoais e pacotes de suporte.

## Critérios de aprovação do preview

A rodada pode ser aprovada quando:

- [ ] todos os casos obrigatórios foram executados em ENV-A e ENV-B;
- [ ] os 44 testes e os três validadores permanecem verdes nos dois motores;
- [ ] não existe defeito Bloqueador ou Crítico aberto;
- [ ] defeitos Maiores possuem responsável, prazo e risco aceito;
- [ ] a taxa de aprovação dos casos executáveis é de pelo menos 95%;
- [ ] diagnóstico somente leitura foi comprovado;
- [ ] instalação, convivência com V2 e reversão foram validadas;
- [ ] evidências foram sanitizadas;
- [ ] coordenador e aprovador registraram a decisão.

Para promoção estável, não pode haver defeito Maior aberto e a matriz de sistemas
operacionais declarada como suportada deve estar integralmente coberta.

## Decisão final

| Campo | Registro |
| --- | --- |
| Resultado | Pendente |
| Casos aprovados | 0 |
| Casos reprovados | 0 |
| Casos bloqueados | 0 |
| Defeitos abertos por severidade | — |
| Riscos aceitos | — |
| Próxima referência recomendada | — |
| Coordenador | — |
| Aprovador | — |
| Data | — |

Decisões possíveis:

- **Aprovado:** preparar o próximo candidato a release a partir da base verde.
- **Aprovado com ressalvas:** manter como preview interno e corrigir os itens registrados.
- **Reprovado:** interromper a expansão, corrigir e iniciar nova rodada com nova tag.
