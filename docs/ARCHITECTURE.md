# Arquitetura do ServiceDesk Toolkit

## Estado atual

O projeto possui duas aplicações PowerShell/WPF:

- `ServiceDeskToolkit-Corporate.ps1`: linha operacional V2;
- `ServiceDeskToolkit-CorporateV3.ps1`: experiência visual e guiada da V3.

Instalação, atualização, rollback, diagnósticos e validadores ficam em scripts
independentes. A base de conhecimento é carregada de um arquivo JSON local.

Os principais painéis de diagnóstico da V3 já possuem fatias modulares:

- `ServiceDeskToolkit.Diagnostics.psm1` coleta um snapshot somente leitura;
- `ServiceDeskToolkit.Health.psm1` avalia o snapshot e formata o relatório;
- `ServiceDeskToolkit.Inventory.psm1` coleta e interpreta o inventário;
- `ServiceDeskToolkit.Network.psm1` executa testes e determina a causa provável;
- `ServiceDeskToolkit.Printers.psm1` avalia spooler, impressoras e filas;
- a aplicação WPF atua como adaptador de apresentação.

Cada módulo operacional separa três contratos públicos: coleta do snapshot,
avaliação determinística e formatação do relatório. Isso permite testar as regras
sem depender de CIM, rede ou serviços reais.

## Princípios

1. Diagnóstico não altera o estado da máquina.
2. Correção segura mede o estado antes e depois.
3. Ação avançada exige autorização, confirmação e privilégio adequado.
4. Toda ação relevante gera evidência e log.
5. Instalação e atualização preservam uma rota de rollback.
6. Windows PowerShell 5.1 continua sendo plataforma compatível.

## Limites funcionais

| Camada | Responsabilidade |
| --- | --- |
| Apresentação | WPF, navegação, mensagens e resultado visível |
| Atendimento guiado | Sequência de diagnóstico, conclusão e próxima ação |
| Diagnósticos | Leitura de sistema, rede, serviços, eventos e aplicações |
| Correções seguras | Ações reversíveis com validação antes/depois |
| Ações avançadas | Reparos administrativos protegidos |
| Infraestrutura | Logs, relatórios, instalação, atualização e rollback |
| Conhecimento | Artigos e associação entre sintomas e ações |

## Arquitetura alvo

A modularização será incremental, preservando os entrypoints atuais:

```text
src/
  ServiceDeskToolkit.Core/
  ServiceDeskToolkit.Diagnostics/
  ServiceDeskToolkit.Health/
  ServiceDeskToolkit.Inventory/
  ServiceDeskToolkit.Network/
  ServiceDeskToolkit.Printers/
  ServiceDeskToolkit.Actions/
  ServiceDeskToolkit.Logging/
  ServiceDeskToolkit.Knowledge/
ui/
  v2/
  v3/
tests/
  unit/
  integration/
```

Funções deverão migrar do script monolítico para módulos `.psm1` por domínio.
Os scripts atuais permanecerão como composição e compatibilidade até a conclusão
da migração.

## Regras de dependência

- A UI pode chamar atendimento guiado e serviços de aplicação.
- Atendimento guiado pode chamar diagnósticos e ações autorizadas.
- Diagnósticos não dependem da UI e não chamam correções.
- Ações não escrevem diretamente na UI; retornam resultados estruturados.
- Logs recebem eventos de todas as camadas.
- Funções de domínio devem aceitar dependências substituíveis para permitir
  testes com mocks.

## Estratégia de testes

- Parser PowerShell para todos os scripts.
- Pester para contratos, regras e funções extraídas.
- Mocks para serviços, registro, processos, rede e download.
- Testes de integração em máquina virtual Windows descartável.
- Homologação visual e administrativa documentada antes de releases.
