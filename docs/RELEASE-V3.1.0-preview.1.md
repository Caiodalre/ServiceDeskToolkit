# ServiceDesk Toolkit Corporate V3.1.0-preview.1

Data da candidata: 11/08/2026.

## Status

Preview interna para homologação do diagnóstico Office/TPM e do reparo
controlado dos componentes WAM. A versão estável permanece `v3.0.1`.

## Incluído

- painel somente leitura para TPM, BitLocker, reinicialização pendente, Microsoft 365 e Office 2016/2019/2021,
  WAM, licenciamento e estado de ingresso no Microsoft Entra;
- avaliação determinística com severidade, evidências e próxima ação;
- reparo confirmado que registra novamente AAD BrokerPlugin e
  CloudExperienceHost no perfil do usuário afetado;
- relatório consolidado e auditoria local do reparo WAM;
- runbook específico com as remediações oficiais e critérios de escalonamento;
- integração no instalador, manifesto SHA-256, base de conhecimento e CI;
- compatibilidade com Windows PowerShell 5.1 e PowerShell 7+.

## Proteções

O toolkit não automatiza limpeza do TPM, remoção de credenciais, exclusão de
caches de token, `dsregcmd /leave`, recuperação forçada, desconexão do Entra ID
ou remoção indiscriminada de licenças. Essas ações dependem do cenário, podem
afetar BitLocker, Windows Hello, certificados e identidade do dispositivo, e
exigem autorização e evidências adicionais.

## Homologação necessária

1. Executar **Office / TPM** em Windows 10 e Windows 11, com e sem Office.
2. Confirmar que o diagnóstico não altera estado nem expõe tokens ou chaves.
3. Em perfil de teste com problema WAM, fechar os aplicativos Office e executar
   **Reparar login Office**.
4. Abrir Word, Excel ou Outlook, autenticar e validar o sintoma original.
5. Conferir o relatório e `logs\office-tpm\office-wam-audit.jsonl`.
6. Validar novamente a instalação por SHA-256 usando uma tag fixa da preview.

## Fallback

- `v3.0.1`: versão estável recomendada;
- `v3.0.0`: fallback temporário da linha V3;
- `v2.3.0`: fallback legado.
