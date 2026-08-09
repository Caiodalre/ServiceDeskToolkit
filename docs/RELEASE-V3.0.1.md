# ServiceDesk Toolkit Corporate V3.0.1

Data da release: 09/08/2026.

## Status

Release estável da camada de integridade SHA-256, promovida sem alterações
funcionais a partir de `v3.0.1-rc.1`.

## Homologação

- aplicação funcional previamente validada sem erros em mais de 10 máquinas;
- candidata de segurança aprovada em Windows 10 e Windows 11;
- 47 testes Pester aprovados;
- padrões, quality gate, release e validador V3 aprovados;
- CI aprovada em Windows PowerShell 5.1 e PowerShell 7;
- teste automatizado de payload adulterado aprovado;
- instalação pública da candidata validada ponta a ponta.

## Segurança da distribuição

- manifesto `checksums-v3.json` com SHA-256 dos componentes;
- verificação do instalador antes da execução no procedimento documentado;
- verificação de todos os payloads antes da gravação;
- bloqueio imediato de hash divergente ou manifesto incompatível;
- referências fixadas na tag imutável `v3.0.1`.

## Limites

SHA-256 oferece integridade, mas não substitui assinatura de código.
Authenticode permanece planejado e depende de certificado corporativo, custódia,
rotação e revogação.

## Fallback

- `v3.0.0`: fallback temporário da linha V3;
- `v2.3.0`: fallback legado.
