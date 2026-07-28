# Padrões de engenharia do repositório

## Objetivo

Este documento define o contrato mínimo de qualidade do ServiceDesk Toolkit.
As regras se aplicam à V2, à V3, aos instaladores, aos validadores e à
documentação mantida no repositório.

## Compatibilidade

- Windows PowerShell 5.1 é a linha mínima suportada.
- PowerShell 7 deve executar testes e validadores sem comportamento divergente.
- A interface WPF deve ser iniciada em modo STA.
- Recursos exclusivos de uma versão do PowerShell exigem fallback explícito.

## Estrutura e responsabilidades

- Aplicações WPF coordenam a experiência visual.
- Módulos em `src/` concentram coleta, avaliação e formatação por domínio.
- Diagnósticos são somente leitura.
- Correções medem o estado antes e depois.
- Ações administrativas exigem confirmação, elevação e evidência.
- Instaladores usam referência fixa para releases e registram a origem.
- Atualização usa staging, validação, backup e rollback.

## PowerShell

- Usar nomes `Verbo-Substantivo` com verbos aprovados por `Get-Verb`.
- Evitar aliases em código versionado.
- Não usar `Invoke-Expression` ou `iex` para conteúdo baixado.
- Não ocultar falhas relevantes em blocos `catch` vazios.
- Funções de domínio devem receber dados ou dependências testáveis.
- Operações destrutivas devem validar caminhos e limitar seu escopo.
- Scripts e módulos usam UTF-8 com BOM e CRLF.
- `bootstrap.ps1` é a única exceção: UTF-8 sem BOM e CRLF.

## Texto e dados

- Markdown, JSON e YAML usam UTF-8 e LF.
- Todo arquivo de texto termina com nova linha.
- Espaços no fim da linha são proibidos, exceto quando semanticamente
  necessários em Markdown.
- JSON deve ser válido e não pode armazenar segredos.
- Documentação pública deve ser sanitizada.

## Versionamento

- Metadados, instalador, README, changelog e nota de release devem concordar.
- Tags publicadas são imutáveis.
- Alteração funcional após uma candidata aprovada exige nova RC.
- A V2 estável permanece como fallback até a promoção formal da V3.

## Validação obrigatória

```powershell
powershell.exe -NoProfile -File .\tools\Test-RepositoryStandards.ps1
Invoke-Pester -Path .\tests -Output Detailed
powershell.exe -NoProfile -File .\tools\Test-ToolkitQuality.ps1
powershell.exe -NoProfile -File .\tools\Test-ToolkitRelease.ps1
powershell.exe -NoProfile -File .\tools\Test-ToolkitV3.ps1
```

O pipeline executa o mesmo conjunto em Windows PowerShell 5.1 e PowerShell 7.
Uma falha impede a promoção da release.
