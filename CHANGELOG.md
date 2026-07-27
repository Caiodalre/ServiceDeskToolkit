# Changelog

Todas as mudanças relevantes do ServiceDesk Toolkit Corporate são registradas
neste arquivo.

## v3.0.0-preview.5 — 2026-07-27

### Adicionado

- Metadados exclusivos da V3 em `version-v3.json`.
- Testes de integridade do repositório com Pester.
- Módulos independentes para coleta diagnóstica e avaliação do Painel de Saúde.
- Testes de limites para memória, disco, uptime, rede e reinício pendente.
- Módulos de domínio para inventário, diagnóstico de rede e impressoras.
- Testes determinísticos para conclusões e prioridades dos novos módulos.
- CI em Windows PowerShell 5.1 e PowerShell 7.
- Política de segurança, guia de contribuição e documentação de arquitetura.
- Templates para pull requests e relatos de defeito.

### Alterado

- A V3 passa a exibir a versão do seu próprio arquivo de metadados.
- O instalador V3 inclui e valida `version-v3.json`.
- O Painel de Saúde passa a consumir módulos testáveis sem alterar seu contrato
  visual.
- Inventário, Rede e Impressoras passam a usar adaptadores finos na interface V3,
  preservando seus relatórios operacionais.
- README passa a diferenciar versão estável, preview e desenvolvimento.

### Corrigido

- Validadores de V3 e release agora retornam código diferente de zero em falhas.
- O instalador V3 interrompe a instalação quando a validação final reprova.

## v3.0.0-preview.4 — 2026-07-27

- Painel de Saúde da Máquina com pontuação e classificação.
- Indicadores de memória, disco, uptime, rede, horário, spooler e reinício
  pendente.
- Recomendações automáticas sem executar correções.

## v3.0.0-preview.3 — 2026-07-27

- Atendimento guiado para impressora que não imprime.
- Validação do fluxo e integração ao instalador.

## v3.0.0-preview.2 — 2026-07-26

- Painel consolidado de impressoras.
- Melhorias de layout e alinhamento da grade principal.

## v3.0.0-preview.1 — 2026-07-26

- Primeira preview versionada da nova experiência V3.
- Inventário, diagnóstico de rede, VPN/Appgate e correções seguras iniciais.

## v2.4.0-dev — 2026-06-30

- Evolução funcional e visual usada como base técnica da V3.
- Atendimento rápido e relatórios corporativos ampliados.

## v2.3.0 — 2026-06-29

- Versão operacional estável anterior ao redesign V3.

## v2.1.0-hardening

- Logs estruturados JSONL.
- Handlers globais de erro WPF e AppDomain.
- Base de conhecimento em JSON.
- Diagnóstico automático em TXT e JSON.
- Quality Gate automatizado.
- Atualização com staging, backup e rollback.
- Compatibilidade de encoding com Windows PowerShell 5.1.

## v2.0.2-compat

- Versão preservada para compatibilidade com instalações antigas.
