# ServiceDesk Toolkit Corporate V3.0.1-rc.1

Data da candidata: 09/08/2026.

## Objetivo

Validar a integridade da distribuição sem alterar as funções homologadas da
`v3.0.0`.

## Alterações

- manifesto `checksums-v3.json` com SHA-256 dos componentes distribuídos;
- validação dos bytes baixados antes de análise, gravação ou execução;
- interrupção imediata quando um arquivo está ausente ou possui hash divergente;
- manifesto preservado dentro da pasta instalada para auditoria;
- gerador e validador determinístico compatível com Windows PowerShell 5.1;
- normalização mecânica dos scripts versionados para clones Git consistentes;
- registro formal da homologação sem erros em mais de 10 máquinas.

## Garantias e limites

O SHA-256 detecta corrupção ou substituição dos arquivos em trânsito e mantém os
componentes coerentes com a tag solicitada. O instalador também exige que o
`sourceRef` do manifesto seja idêntico à referência informada.

O manifesto e os arquivos pertencem ao mesmo repositório. Portanto, esta camada
não substitui assinatura de código nem protege contra comprometimento da conta
ou alteração forçada de tag. Tags permanecem imutáveis por política. A adoção de
Authenticode depende de certificado corporativo, processo de custódia, rotação e
revogação.

## Homologação requerida

1. Baixar manifesto e instalador a partir de `v3.0.1-rc.1`.
2. Conferir o SHA-256 do instalador antes de executá-lo.
3. Executar instalação limpa em Windows PowerShell 5.1.
4. Confirmar mensagens `SHA-256 confirmado` para todos os componentes.
5. Abrir a interface e executar a validação V3.
6. Alterar uma cópia de teste do manifesto ou payload e confirmar bloqueio.
7. Repetir ao menos em Windows 10 e Windows 11.
8. Registrar somente evidências sanitizadas.

## Critério de promoção

Promover para `v3.0.1` apenas quando CI, instalação íntegra, teste negativo de
checksum e regressão funcional estiverem aprovados.
