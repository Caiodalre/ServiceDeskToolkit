# Checklist de release

## Identidade da versão

- [ ] A versão foi atualizada no arquivo de metadados correto.
- [ ] Canal, referência de origem e compatibilidade estão corretos.
- [ ] `CHANGELOG.md` contém a nova versão e a data.
- [ ] Notas de release descrevem recursos, riscos e limitações.
- [ ] Comandos de instalação usam tag fixa, não branch mutável.

## Qualidade automatizada

- [ ] CI aprovada em Windows PowerShell 5.1.
- [ ] CI aprovada em PowerShell 7.
- [ ] Testes Pester aprovados.
- [ ] `Test-ToolkitQuality.ps1` aprovado.
- [ ] `Test-ToolkitRelease.ps1` aprovado.
- [ ] `Test-ToolkitV3.ps1` aprovado quando a release incluir a V3.
- [ ] Todos os validadores retornam código de saída correto.

## Homologação funcional

- [ ] Interface abre com `powershell.exe -STA`.
- [ ] Diagnósticos não alteram o estado da máquina.
- [ ] Ações seguras exibem evidências antes e depois.
- [ ] Ações críticas exigem confirmação e privilégio adequado.
- [ ] Logs e relatórios são gerados sem dados sensíveis desnecessários.
- [ ] Instalação limpa foi testada.
- [ ] Atualização foi testada com staging e backup.
- [ ] Rollback dry-run foi testado.
- [ ] Rollback real foi validado em ambiente descartável.

## Segurança da distribuição

- [ ] Downloads apontam para o repositório oficial.
- [ ] Nenhum segredo, credencial ou dado corporativo foi versionado.
- [ ] Dependências e ações de CI foram revisadas.
- [ ] Artefatos e checksums foram publicados quando aplicável.
- [ ] Pacotes de suporte usados na homologação foram removidos.

## Git e publicação

- [ ] Pull request revisado e aprovado.
- [ ] Branch protegida e status checks obrigatórios.
- [ ] `git status` limpo.
- [ ] Tag anotada criada a partir do commit aprovado.
- [ ] Release do GitHub publicada com instruções de instalação.
- [ ] Teste pós-publicação executado usando a tag.

## Comandos locais

```powershell
git status --short --branch
Invoke-Pester -Path .\tests -Output Detailed
powershell.exe -NoProfile -File .\tools\Test-ToolkitQuality.ps1
powershell.exe -NoProfile -File .\tools\Test-ToolkitRelease.ps1
powershell.exe -NoProfile -File .\tools\Test-ToolkitV3.ps1
```
