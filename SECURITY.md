# Política de segurança

## Versões suportadas

| Linha | Situação |
| --- | --- |
| `v3.0.1` | Estável para operação interna |
| `v3.1.0-preview.1` | Homologação interna Office/TPM |
| `v3.0.0` | Versão anterior, suporte de transição |
| `v3.0.1-rc.1` | Histórico de homologação, sem novas correções |
| `v2.3.0` | Fallback legado com suporte crítico |
| `v3.0.0-rc.*` | Histórico de homologação, sem novas correções |
| `v3.0.0-preview.*` | Histórico, sem novas correções |
| Branches de desenvolvimento | Sem suporte para produção |

## Como relatar uma vulnerabilidade

Não abra uma issue pública com detalhes de exploração, credenciais, nomes de
máquinas, endereços internos ou pacotes de suporte.

Use o recurso privado de reporte de vulnerabilidades do GitHub quando estiver
disponível. Caso ele não esteja habilitado, entre em contato de forma privada com
o proprietário do repositório pelo perfil do GitHub e informe apenas que deseja
enviar um relato de segurança.

Inclua:

- versão, tag ou commit afetado;
- cenário e impacto;
- passos mínimos para reprodução;
- evidências sanitizadas;
- mitigação sugerida, se conhecida.

## Cuidados de instalação

- Prefira tags fixas a branches.
- Baixe o instalador para arquivo antes de executá-lo.
- Verifique o manifesto `checksums-v3.json` antes de executar o instalador.
- O instalador V3 interrompe o processo se qualquer SHA-256 divergir.
- Não execute scripts recebidos por canais não confiáveis.
- Homologue ações administrativas em ambiente descartável.

## Office, TPM e identidade

O diagnóstico não registra chaves BitLocker, chaves de produto Office, tokens, nomes de credenciais ou a
saída bruta do `dsregcmd`. Limpeza do TPM, remoção de credenciais ou caches,
`dsregcmd /leave`, recuperação forçada e desconexão do Microsoft Entra não são
automatizadas. Essas ações podem afetar Windows Hello, certificados,
criptografia e o objeto corporativo do dispositivo.

## Dados coletados

Diagnósticos e pacotes de suporte podem conter hostname, usuário, configuração
de rede, inventário, logs e outros dados operacionais. Antes de compartilhar:

- remova credenciais e tokens;
- remova endereços e identificadores desnecessários;
- use somente o canal corporativo autorizado;
- respeite as políticas de retenção da organização.
