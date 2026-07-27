# Como contribuir

Obrigado por contribuir com o ServiceDesk Toolkit Corporate.

## Fluxo de trabalho

1. Crie uma branch curta a partir da branch de desenvolvimento adequada.
2. Faça alterações pequenas e com objetivo único.
3. Inclua ou atualize testes e documentação.
4. Execute todos os validadores locais.
5. Abra um pull request descrevendo impacto, risco e evidências.

Mudanças não devem ser enviadas diretamente para `main`.

## Convenções

- Preserve compatibilidade com Windows PowerShell 5.1 e PowerShell 7+.
- Salve scripts `.ps1` em UTF-8 com BOM.
- Use quatro espaços para indentação.
- Prefira nomes PowerShell no formato `Verbo-Substantivo`.
- Diagnóstico não deve alterar o estado da máquina.
- Correções devem validar estado antes e depois.
- Ações destrutivas ou administrativas exigem confirmação explícita.
- Não use `Invoke-Expression` para executar conteúdo baixado.
- Não registre senhas, tokens, cookies ou conteúdo corporativo sensível.

## Validação

```powershell
Invoke-Pester -Path .\tests -Output Detailed
powershell.exe -NoProfile -File .\tools\Test-ToolkitQuality.ps1
powershell.exe -NoProfile -File .\tools\Test-ToolkitRelease.ps1
powershell.exe -NoProfile -File .\tools\Test-ToolkitV3.ps1
```

Todos os comandos aplicáveis devem finalizar com código de saída `0`.

## Mudanças de alto risco

Exigem revisão adicional:

- instalação, atualização e rollback;
- elevação de privilégio;
- serviços e registro do Windows;
- rede, Winsock, TCP/IP e firewall;
- remoção de arquivos ou caches;
- empacotamento de logs e evidências;
- cadeia de download e execução remota.

Inclua no pull request o plano de rollback e a forma de homologação dessas
mudanças.

## Commits

Use mensagens curtas, no imperativo e focadas no resultado, por exemplo:

```text
Adiciona validação de metadados da V3
Corrige código de saída do validador
Documenta fluxo seguro de instalação
```
