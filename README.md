# ServiceDesk Toolkit Corporate

Toolkit em PowerShell para apoio ao Service Desk, com interface grafica, diagnostico, reparos guiados e Base de Conhecimento local.

## Instalacao rapida

Execute no PowerShell:

``powershell
irm https://raw.githubusercontent.com/Caiodalre/ServiceDeskToolkit/main/install.ps1 | iex
``

## Repositorio

https://github.com/Caiodalre/ServiceDeskToolkit

## Recursos principais

- Visao Geral
- Atendimento Rapido
- Base de Conhecimento local
- Busca por resumo do problema
- Diagnostico de Rede
- Reparo Windows
- Teams / Office
- TPM / Office
- Microsoft Store / Apps
- Impressoras
- Seguranca
- GPO / Sistema
- Teste TCP
- Relatorios
- Protecao para acoes criticas

## Pasta padrao de instalacao

``text
C:\ServiceDeskToolkit
``

## Arquivos principais

``text
ServiceDeskToolkit-Corporate.ps1
ServiceDeskToolkit.cmd
install.ps1
data\knowledge-base.json
``

## Observacao de seguranca

Este toolkit executa acoes administrativas em Windows. Revise o codigo antes de executar em ambientes corporativos.
