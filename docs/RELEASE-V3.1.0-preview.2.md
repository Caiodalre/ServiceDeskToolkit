# ServiceDesk Toolkit Corporate V3.1.0-preview.2

Data da candidata: 12/08/2026.

## Status

Preview interna para homologação. A versão estável permanece `v3.0.1`.

## Incluído

- recursos Office/TPM da preview.1;
- diagnóstico avançado de adaptadores, IP, DNS, rotas e gateway;
- renovação confirmada de IP e resets protegidos de Winsock e TCP/IP;
- lista de impressoras, filas, padrão, offline e atalhos administrativos;
- limpeza confirmada da fila de impressão, com restauração do Spooler;
- status, reinício e ajuste protegido do Appgate SDP;
- sincronização segura de horário com validação antes e depois.

## Proteções

- renovação de IP, resets de rede, limpeza de fila e alterações do Appgate
  exigem confirmação explícita;
- operações administrativas recusam execução sem elevação;
- o ajuste do Appgate cria backup antes de alterar o XML;
- diagnósticos não alteram o estado da máquina;
- limpeza de TPM, credenciais e vínculo Entra permanecem fora da automação.

## Homologação necessária

1. Validar diagnóstico de rede em Ethernet, Wi-Fi e VPN.
2. Confirmar renovação de IP e resets em equipamento de teste.
3. Validar impressoras locais, compartilhadas, offline e com fila pendente.
4. Confirmar que a limpeza de fila restaura o Spooler mesmo em falha.
5. Validar status e reinício do Appgate com cliente instalado e ausente.
6. Validar backup e ajuste `RunScriptTimeout=300000` em estação autorizada.
7. Executar sincronização de horário em domínio e fora do domínio.

## Fallback

- `v3.0.1`: versão estável recomendada;
- `v3.0.0`: fallback temporário da linha V3;
- `v2.3.0`: fallback legado.
