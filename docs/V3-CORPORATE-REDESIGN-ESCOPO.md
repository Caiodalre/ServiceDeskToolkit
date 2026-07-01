# ServiceDesk Toolkit Corporate - V3 Corporate Redesign

## 1. Decisão

Criar uma nova experiência visual limpa usando a base atual como motor.

A V3 não será um descarte do projeto atual. A V3 será uma nova casca visual, mais corporativa, mais guiada e com menos botões visíveis.

## 2. Papel da v2.4

A branch v2.4-functional passa a ser considerada base técnica validada.

Ela contém:

- Instalador
- Update
- Rollback
- Quality Gate
- Release Validation
- Installed Validation
- Logs estruturados
- Relatórios
- Pacote de suporte
- Base de conhecimento
- Funções técnicas já testadas

A V3 deve reaproveitar essas capacidades, mas não deve carregar a mesma experiência visual cheia de botões.

## 3. Problema que a V3 resolve

A versão atual é tecnicamente forte, mas visualmente carregada.

Problemas atuais:

- Botões demais
- Sidebar extensa
- Ações simples e críticas no mesmo nível visual
- Duplicidade entre Home, Sidebar e Abas
- Difícil para o técnico iniciante saber o primeiro clique
- Visual mais próximo de painel técnico do que produto corporativo

## 4. Objetivo da V3

Criar uma central de atendimento técnico corporativa, guiada e visualmente limpa.

A V3 deve ajudar o técnico a responder rapidamente:

- Qual problema o usuário tem?
- O que devo diagnosticar primeiro?
- Qual evidência devo coletar?
- Qual correção é segura?
- Quando devo escalar para N2/N3?

## 5. Regra de ouro

A V3 deve mostrar poucas ações por padrão.

Ferramentas avançadas continuam existindo, mas não ficam na tela principal.

## 6. Estrutura visual proposta

### 6.1 Início

Tela executiva com:

- Nome do Toolkit
- Versão
- Canal
- Hostname
- Usuário
- Admin: Sim/Não
- Status resumido da máquina
- Botão: Iniciar Atendimento
- Botão: Gerar Pacote de Suporte
- Botão: Abrir Base de Conhecimento

### 6.2 Atendimento Guiado

Fluxos principais:

- Sem internet
- VPN / Appgate
- Teams / Outlook
- Impressora
- Windows Update
- Máquina lenta

Cada fluxo deve retornar:

- Diagnóstico
- Causa provável
- Próxima ação
- Evidência para chamado

### 6.3 Evidências

Ações visíveis:

- Inventário
- Diagnóstico de rede
- Relatório HTML
- Pacote de suporte
- Abrir pasta de relatórios
- Copiar resultado

### 6.4 Correções Seguras

Ações visíveis:

- Limpar DNS
- Renovar IP
- Sincronizar horário
- Reiniciar spooler
- Limpar temporários

### 6.5 Avançado

Área protegida para ações críticas:

- SFC
- DISM
- Reset Winsock
- Reset TCP/IP
- Limpar cache Windows Update
- Corrigir Appgate
- Corrigir TPM / Office
- Limpar fila de impressão

## 7. Limite inicial de botões

A primeira V3 não deve passar de 20 ações visíveis.

Meta visual:

- Poucos botões
- Cards grandes
- Linguagem clara
- Separação por risco
- Painel de resultado sempre visível

## 8. O que entra na primeira V3

Entram:

- Home nova
- Atendimento Guiado
- Evidências
- Correções Seguras
- Área Avançada protegida
- Logs existentes
- Quality Gate existente
- Instalador existente em etapa posterior

## 9. O que fica fora da primeira V3

Ficam fora inicialmente:

- Todas as funções avançadas visíveis ao mesmo tempo
- Sidebar extensa
- Duplicidade de botões
- Relatórios longos demais como foco principal
- Ferramentas raras na tela principal

## 10. Estratégia técnica

Criar um novo shell visual primeiro, sem quebrar o app atual.

Arquivo inicial sugerido:

- ServiceDeskToolkit-CorporateV3.ps1

A primeira etapa será protótipo visual funcional. Depois, as funções do app atual serão reaproveitadas de forma controlada.

## 11. Critério para considerar a V3 promissora

A V3 será considerada promissora quando:

- Abrir com visual mais limpo
- Ter menos botões
- Guiar melhor o atendimento
- Conseguir executar pelo menos 5 fluxos essenciais
- Gerar evidência copiável
- Manter logs
- Passar no Quality Gate
- Não quebrar a v2.4 atual

## 12. Decisão final

Não continuar empilhando botões na v2.4.

A partir deste ponto, novas melhorias visuais devem ser desenhadas primeiro para a V3 Corporate Redesign.

