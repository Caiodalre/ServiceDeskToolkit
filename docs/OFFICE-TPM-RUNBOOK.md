# Runbook — Office, TPM e autenticação

## Objetivo

Este runbook organiza a investigação de erros de ativação e autenticação do
Microsoft 365 Apps associados a TPM, WAM, AAD Broker, licenciamento e identidade
do dispositivo. Exemplos frequentes incluem `80090016`, `80090030`, solicitações
repetidas de login, janela de autenticação em branco e Outlook preso em
"Tentando conectar".

O diagnóstico deve ser executado no perfil do usuário afetado. Os componentes
WAM são registrados por usuário; outro perfil na mesma máquina pode funcionar
normalmente.

## Ordem operacional

1. Registrar código completo, aplicativo, usuário e momento do erro.
2. Executar **Office / TPM** no toolkit.
3. Resolver reinicialização pendente antes de alterar autenticação.
4. Corrigir WAM quando o pacote estiver ausente ou houver eventos compatíveis.
5. Revisar credenciais e ativação somente se o erro persistir.
6. Validar identidade do dispositivo e PRT no Microsoft Entra.
7. Tratar TPM, firmware e ingresso do dispositivo como ações avançadas.

## Diagnóstico coletado pelo toolkit

- TPM presente, pronto, versão e fabricante;
- status do BitLocker sem coletar ou exibir chave de recuperação;
- reinicialização e operações de arquivos pendentes;
- instalação, versão e arquitetura do Office;
- edição detectada e modelo de licenciamento;
- disponibilidade e resultado resumido do `vnextdiag.ps1`;
- estado resumido de licenças por volume via `ospp.vbs /dstatusall`, sem registrar
  chave de produto completa ou parcial;
- pacotes e manifestos AAD BrokerPlugin e CloudExperienceHost;
- presença dos caches TokenBroker sem expor tokens ou nomes de arquivos;
- quantidade de credenciais relacionadas a Office, ADAL ou OneAuth;
- `AzureAdJoined`, `DomainJoined`, `WorkplaceJoined`, `WamDefaultSet`,
  `AzureAdPrt`, `TpmProtected`, `DeviceAuthStatus`, `NgcSet` e `KeySignTest`;
- eventos recentes de AppModel-State, AAD e TPM-WMI.

## Meios de correção

### Matriz por edição

| Edição detectada | Erro de TPM ou login | Diagnóstico de licença |
| --- | --- | --- |
| Microsoft 365 Apps | Reparar WAM no perfil afetado | `vnextdiag.ps1` |
| Office 2016 | Reparar WAM no perfil afetado | `ospp.vbs` somente para licença por volume |
| Office 2019 | Reparar WAM no perfil afetado | `ospp.vbs` somente para licença por volume |
| Office LTSC 2021 | Reparar WAM no perfil afetado | `ospp.vbs` somente para licença por volume |

As quatro famílias usam a base Office 16.0. O toolkit correlaciona
`ProductReleaseIds`, nomes de licença e ferramentas encontradas; se as evidências
não forem suficientes, informa que a edição 16.x não foi identificada.

O reparo WAM trata autenticação moderna e os erros de TPM/login associados. O
OSPP diagnostica ativação por volume; ele não repara o TPM.

### 1. Reiniciar o Windows

Priorizar quando CBS, Windows Update ou renomeação de arquivos estiverem
pendentes. Salvar o trabalho do usuário e não reiniciar durante SFC, DISM,
atualização de firmware ou outra manutenção ativa.

### 2. Reparar WAM no perfil afetado

O botão **Reparar login Office** registra novamente os manifestos oficiais:

- `Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy`;
- `Microsoft.Windows.CloudExperienceHost_cw5n1h2txyewy`.

O analista deve fechar Word, Excel, Outlook, Teams e demais aplicativos Office.
O reparo não remove credenciais, não limpa TPM e não desconecta o dispositivo do
Microsoft Entra.

Se o problema voltar, revisar antivírus, proxy e drivers Windows Filtering
Platform. A Microsoft documenta exclusões específicas para pacotes, pastas e
processos WAM; alterações no software de segurança dependem da política da
organização.

Depois do registro, monitorar por 48 horas. Em reincidência, coletar uma
reprodução com Process Monitor e envolver o fornecedor do software de segurança
ou do driver WFP antes de criar exclusões corporativas.

### 3. Remover dados antigos do TokenBroker

A Microsoft orienta apagar o conteúdo das pastas `Accounts` do AAD BrokerPlugin
e CloudExperienceHost em cenários compatíveis. Essa ação encerra sessões e exige
novo login e reinicialização. Por esse motivo, o toolkit apenas identifica os
caches e apresenta a orientação; não apaga os arquivos automaticamente.

### 4. Revisar credenciais do Office

Abrir o Gerenciador de Credenciais e remover somente entradas antigas
`MicrosoftOffice16` relacionadas ao usuário afetado. Confirmar previamente que o
usuário conhece a senha e possui o segundo fator necessário. O toolkit não
remove credenciais automaticamente.

### 5. Redefinir a ativação do Microsoft 365 Apps

Para Microsoft 365 Apps moderno, usar `vnextdiag.ps1 -action list`. Se uma
licença específica estiver incorreta, usar `-action remove -LicenseId` apenas no
identificador exibido pelo diagnóstico. O usuário deverá autenticar novamente.

Para Office 2016, Office 2019 e Office LTSC 2021 por volume, o toolkit localiza
`ospp.vbs` em instalações Click-to-Run ou MSI, x86 ou x64, e executa somente
`/dstatusall`. O relatório registra edição, tipo de ativação, estado e código de
erro, mas nunca registra os cinco últimos caracteres nem qualquer chave.

Quando houver falha, usar manualmente `/ddescr:<código>`, validar KMS, DNS, proxy,
MAK ou ativação baseada no Active Directory e executar `/act` somente com
autorização. O toolkit não usa `/unpkey`, `/inpkey` nem muda o host KMS.

O OSPP é destinado às edições por volume. Em licença Retail, revisar a tela de
Conta/Produto do próprio Office. Não misturar OSPP e vnextdiag sem identificar o
modelo de licenciamento.

### 6. Executar o solucionador de entrada do Microsoft 365

Usar o solucionador oficial do Microsoft 365/Get Help depois das correções
locais básicas. Ele pode identificar problemas de conta, ativação e entrada que
não pertencem ao TPM do computador.

### 7. Validar o Microsoft Entra e o PRT

Executar `dsregcmd /status` no contexto do usuário para WAM e PRT. Os campos mais
importantes são:

- `DeviceAuthStatus`: o dispositivo deve existir e estar habilitado;
- `WamDefaultSet`: conta WAM padrão do usuário;
- `AzureAdPrt`: token de atualização primário;
- `TpmProtected`: proteção da chave do dispositivo;
- `KeySignTest`: integridade da chave, quando executado com elevação.

Se o dispositivo estiver excluído ou desabilitado no tenant, envolver o
administrador do Microsoft Entra. A recuperação muda conforme o tipo de ingresso:
registrado, Entra joined ou hybrid joined. O toolkit não executa
`dsregcmd /leave` nem `dsregcmd /forcerecovery` automaticamente.

### 8. Revisar Acessar trabalho ou escola

Uma conta corporativa obsoleta ou diferente da conta usada no Windows pode
causar loop de autenticação. Desconectar e conectar novamente é uma ação manual,
pois pode afetar políticas, certificados, Conditional Access e gerenciamento do
dispositivo.

### 9. ProtectionPolicy do Windows

A documentação da Microsoft inclui o valor `ProtectionPolicy=1` em
`HKLM\Software\Microsoft\Cryptography\Protect\Providers\df9d8cd0-1501-11d1-8c7a-00c04fc297eb`
para cenários específicos. Aplicar somente depois de confirmar aderência ao erro,
registrar o valor anterior e planejar reinicialização. O toolkit apenas informa o
estado atual.

### 10. Validar firmware e estado do TPM

Se o TPM estiver ausente ou indisponível:

- abrir `tpm.msc`;
- confirmar TPM 2.0 habilitado no UEFI/BIOS;
- usar drivers TPM fornecidos pelo Windows;
- atualizar BIOS e firmware conforme o fabricante;
- em máquinas de domínio, validar acesso à rede corporativa e ao controlador de
  domínio quando a política exigir backup de informações do TPM.

### 11. Limpar o TPM — último recurso

Limpar o TPM pode remover PIN do Windows Hello, chaves de certificado, cartão
inteligente virtual e acesso a dados protegidos. Antes da ação:

1. confirmar propriedade e autorização sobre o equipamento;
2. verificar BitLocker e garantir método de recuperação válido;
3. validar Windows Hello, certificados e outras chaves dependentes do TPM;
4. registrar evidências e obter aprovação;
5. usar a interface do Windows ou `tpm.msc`, nunca limpeza direta pelo firmware;
6. planejar reinicialização e novo provisionamento.

O toolkit não executa limpeza de TPM.

### 12. Últimas alternativas

- habilitar Integridade de memória quando compatível com drivers e política;
- corrigir ou recriar o objeto do dispositivo no Microsoft Entra;
- testar um novo perfil Windows para diferenciar falha de máquina e perfil;
- realizar inicialização limpa para identificar software de segurança ou driver;
- reinstalar ou reparar o Office depois de esgotar identidade, WAM e licença.

## Referências oficiais

- [Erro de ativação: TPM com mau funcionamento](https://learn.microsoft.com/en-us/previous-versions/troubleshoot/microsoft-365/microsoft-365-apps/activation/tpm-malfunctioned)
- [Não é possível entrar nos aplicativos do Microsoft 365](https://learn.microsoft.com/en-us/previous-versions/troubleshoot/microsoft-365/microsoft-365-apps/activation/cannot-sign-in-microsoft-365-desktop-apps)
- [Diagnóstico de dispositivo com dsregcmd](https://learn.microsoft.com/en-us/entra/identity/devices/troubleshoot-device-dsregcmd)
- [Status e redefinição de ativação com vnextdiag](https://learn.microsoft.com/en-us/microsoft-365-apps/licensing-activation/vnextdiag)
- [Ferramentas para ativação por volume do Office](https://learn.microsoft.com/en-us/office/volume-license-activation/tools-to-manage-volume-activation-of-office)
- [Solução de problemas da ativação por volume](https://learn.microsoft.com/en-us/office/volume-license-activation/troubleshoot-volume-activation-of-office)
- [Ciclo de vida das versões anteriores do Office](https://learn.microsoft.com/en-us/microsoft-365-apps/end-of-support/plan-upgrade-older-versions-office)
- [Solução de problemas do TPM](https://learn.microsoft.com/en-us/windows/security/hardware-security/tpm/initialize-and-configure-ownership-of-the-tpm)
- [Dispositivo não encontrado no Microsoft Entra](https://learn.microsoft.com/troubleshoot/entra/entra-id/app-integration/error-code-aadsts700003-device-object-not-found)
