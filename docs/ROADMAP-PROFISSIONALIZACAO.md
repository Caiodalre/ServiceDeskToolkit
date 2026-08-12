# Roadmap de profissionalização

## Fase 1 — Fundação do repositório

- [x] Fonte de versão exclusiva da V3.
- [x] Códigos de saída confiáveis nos validadores.
- [x] Testes Pester para integridade do repositório.
- [x] CI em Windows PowerShell 5.1 e PowerShell 7.
- [x] README, changelog, segurança e contribuição.
- [ ] Definir licença pública.
- [ ] Proteger branches e exigir CI em pull requests.

## Fase 2 — Segurança da distribuição

- [x] Publicar manifesto SHA-256 por release.
- [x] Validar checksums antes da instalação e atualização.
- [x] Registrar Authenticode como fora do escopo da operação atual.
- [x] Encerrar rotação e revogação de certificados como não aplicáveis.
- [x] Remover recomendações de execução remota por pipe.
- [x] Criar teste de instalação usando somente uma tag fixa.
- [x] Homologar a distribuição SHA-256 em Windows 10 e Windows 11.
- [x] Promover a candidata homologada para `v3.0.1` estável.

## Fase 3 — Modularização

- [x] Extrair coleta e avaliação do Painel de Saúde.
- [x] Preservar o contrato visual por adaptador na aplicação V3.
- [x] Cobrir limites do Painel de Saúde com testes determinísticos.
- [x] Extrair diagnósticos de inventário e rede.
- [x] Extrair o painel de impressoras.
- [x] Preservar os relatórios dos três painéis por adaptadores de compatibilidade.
- [ ] Extrair modelos de resultado e logging.
- [x] Extrair diagnóstico Office/TPM e reparo WAM protegido.
- [ ] Extrair Teams e VPN.
- [ ] Extrair as demais correções seguras.
- [ ] Separar XAML da lógica PowerShell.
- [ ] Manter adaptadores de compatibilidade para os entrypoints atuais.

## Fase 4 — Testes funcionais

- [x] Cobrir regras dos módulos extraídos com Pester e snapshots sintéticos.
- [ ] Cobrir coletores do Windows com mocks.
- [ ] Testar decisões do atendimento guiado com cenários determinísticos.
- [ ] Testar instalação, atualização e rollback em máquina virtual.
- [x] Validar ações administrativas com estado antes/depois.
- [ ] Criar suíte de regressão para Windows 10 e Windows 11.
- [ ] Homologar Office/TPM e reparo WAM nos dois sistemas.

## Fase 5 — Operação corporativa

- [ ] Definir matriz de suporte e ciclo de vida.
- [ ] Padronizar telemetria local e retenção de logs.
- [ ] Sanitizar automaticamente pacotes de suporte.
- [ ] Criar documentação para N1, N2 e administradores.
- [ ] Definir canal de incidentes e vulnerabilidades.
- [x] Publicar release estável da V3 após homologação.
- [x] Validar a V3 sem erros em mais de 10 máquinas.
