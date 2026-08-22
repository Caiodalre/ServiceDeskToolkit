# ServiceDesk Toolkit Corporate V3.0.0-rc.1

Status: Release candidate em validação final  
Base funcional homologada: `v3.0.0-preview.5`  
Branch de desenvolvimento: `v3-corporate-redesign`  
Tag planejada: `v3.0.0-rc.1`

## Resumo

A `v3.0.0-rc.1` congela a candidata funcional aprovada na homologação interna obrigatória. Não adiciona recursos nem altera o comportamento operacional validado na `v3.0.0-preview.5`.

Esta fase concentra versionamento, referência imutável de instalação, documentação e verificação final dos artefatos antes da promoção para `v3.0.0`.

## Escopo da release candidate

- Promover os metadados para `3.0.0-rc.1`
- Alterar o canal para `release-candidate`
- Fixar o instalador na referência `v3.0.0-rc.1`
- Registrar a aprovação dos ambientes ENV-A e ENV-B
- Preservar integralmente o runtime homologado
- Revalidar CI, instalação, abertura padrão e abertura administrativa
- Manter a V2.3.0 como fallback operacional

## Evidências de qualidade

- Homologação interna concluída na [Issue #5](https://github.com/Caiodalre/ServiceDeskToolkit/issues/5)
- ENV-A: Windows 11, Windows PowerShell 5.1, usuário padrão
- ENV-B: Windows 11, PowerShell 7.6.3, administrador
- Validador V3 aprovado nos dois motores
- Testes Pester e Quality Gate aprovados
- Nenhum defeito Bloqueador, Crítico ou Maior pendente
- ENV-C permanece complementar e não bloqueante quando Windows 10 estiver disponível

## Congelamento funcional

Durante a release candidate:

- Não adicionar novas funcionalidades
- Não alterar regras de diagnóstico sem nova homologação
- Aceitar apenas correções de release, segurança, instalação ou documentação
- Exigir uma nova RC caso qualquer mudança afete o runtime

## Instalação após a publicação da tag

```powershell
$Version = "v3.0.0-rc.1"
$Installer = Join-Path $env:TEMP "ServiceDeskToolkitV3-install.ps1"
$Url = "https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/$Version/install-v3.ps1"

Invoke-WebRequest -Uri $Url -OutFile $Installer -UseBasicParsing
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Branch $Version
```

Não utilizar este comando antes da publicação da tag fixa.

## Reversão

A V3 permanece instalada em builds isoladas dentro de `%LOCALAPPDATA%\ServiceDeskToolkitV3`. Em caso de bloqueio, interromper o uso da candidata e retornar à versão estável `v2.3.0`.

## Critérios para promoção a v3.0.0

- CI verde em Windows PowerShell 5.1 e PowerShell 7
- Artefatos da RC gerados e inspecionados
- Instalação por tag fixa aprovada
- Abertura padrão e administrativa aprovadas
- Reversão e coexistência com V2 confirmadas
- Nenhum bloqueador ou defeito crítico aberto
- Decisão de promoção registrada
