# Manual do usuário do localSIEM

Este MANUAL também está disponível em:\
[de-DE](MANUAL.de-DE.md), [en-GB](MANUAL.en-GB.md), [en-US](MANUAL.md), [es-AR](MANUAL.es-AR.md), [es-ES](MANUAL.es-ES.md), [fr-FR](MANUAL.fr-FR.md), [he-IL](MANUAL.he-IL.md), [hi-IN](MANUAL.hi-IN.md), [it-IT](MANUAL.it-IT.md), [ja-JP](MANUAL.ja-JP.md), [ko-KR](MANUAL.ko-KR.md), pt-BR, [pt-PT](MANUAL.pt-PT.md), [ru-RU](MANUAL.ru-RU.md), [zh-CN](MANUAL.zh-CN.md)

[Instalação](README.pt-BR.md) · [Referência do código](CODE.pt-BR.md)

## Conteúdo

1. [O que o localSIEM faz](#what)
2. [Instalação](#installation)
3. [Requisitos do Apache e do ModSecurity](#requirements)
4. [O diagnóstico](#doctor)
5. [Conexão com o SOC](#soc)
6. [Login e contas](#signin)
7. [Os dois painéis](#dashboards)
8. [Visão geral](#overview)
9. [Pesquisa](#search)
10. [A ficha da requisição e os pivôs](#card)
11. [Visualização ao vivo](#live)
12. [Alertas](#alerts)
13. [Módulos](#modules)
14. [Administração](#administration)
15. [Avisos de saúde e o que fazer](#health)
16. [Retenção e disco](#retention)
17. [Linha de comando](#cli)

<a id="what"></a>
## 1. O que o localSIEM faz

O localSIEM monitora os serviços do servidor em que está instalado por meio de **módulos**, um por serviço. Ele só lê os logs desse servidor: não recebe logs de outras máquinas. O módulo **Apache + ModSecurity** monitora o site do Apache: para cada requisição, ele junta três registros, a linha do `access.log`, as linhas do `error.log` e o registro do log de auditoria do ModSecurity, usando o `UNIQUE_ID` da requisição. Tudo é armazenado para poder ser pesquisado. Depois, o localSIEM decide o que precisa ir para o SOC.

O localSIEM funciona no mesmo servidor Debian ou Alpine que protege, ao lado do site dele, como dois serviços do usuário de sistema `localsiem`. A interface web própria dele escuta na porta 10443: nunca usa as portas 80 nem 443 e nunca mexe no site do servidor. Além do SOC (opcional, seção 5), ele pode enviar a você os alertas mais importantes pelo **Telegram** (seção 14) e oferece ao analista do SOC uma **ferramenta de pesquisa**, com um campo de pesquisa e um intervalo de tempo (seção 9). Ele nunca deixa senhas, cookies, tokens nem corpos de requisições saírem do servidor, usa pouca memória (cerca de 100 MB em uso normal, cerca de 200 MB no pico) e nunca enche o disco (seção 16).

**Só vai para o SOC o que ninguém resolveu ainda.**

| Situação | Vai para o SOC? |
|---|---|
| O ModSecurity bloqueou a requisição nas fases 1–2 (antes que a aplicação a recebesse) | **Não.** Ela fica no localSIEM, pesquisável, e aparece como contagem no próximo alerta desse IP. |
| O ModSecurity bloqueou a resposta nas fases 3–4 (a aplicação já tinha executado a requisição) | Sim |
| Correspondências de regras com o ModSecurity em `DetectionOnly` (nada é bloqueado) | Sim |
| Correspondências de regras abaixo do limite de bloqueio | Sim, com severidade `low` |
| Sinais das regras do localSIEM (força bruta, web shell, arquivo sensível, enumeração, erro de banco de dados) | Sim |
| Problemas de saúde e possível exclusão de rastros | Sim |

**Severidade do que vai para o SOC**

| Situação | Severidade |
|---|---|
| Correspondências de regras não bloqueadas, resposta 3xx, 4xx ou 5xx | média |
| Correspondências de regras não bloqueadas, resposta 2xx | alta |
| Bloqueada nas fases 3–4 | alta |
| Sinais de sucesso: regra de vazamento de dados ou de web shell (950–955) não bloqueada, erro de SQL logo depois, POST com 2xx para um `.php` novo | crítica |
| Abaixo do limite de bloqueio (muitas vezes falsos positivos da aplicação) | baixa (configurável em Configurações) |

**Agrupamento.** Um alerta por módulo, vhost, IP, categoria e severidade em uma janela de 10 minutos. Um alerta crítico sai imediatamente; os outros esperam 60 segundos para reunir a rajada e saem com a contagem. Um scanner que envia milhares de requisições produz poucos alertas, não milhares. Se a severidade sobe (por exemplo, o mesmo ataque agora recebe respostas 200), isso é outro alerta.

**O que nunca vai para o SOC:** corpos de requisições ou de respostas, cookies, cabeçalhos `Authorization`, senhas ou tokens — nem mesmo mascarados — e o que já foi bloqueado nas fases 1–2 (só como contagem). O localSIEM mascara os valores sensíveis (`password`, `pass`, `pwd`, `passwd`, `token`, `secret`, `api_key`, `apikey`, `auth`, `session` e os cabeçalhos `Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, `Proxy-Authorization`) com `***` antes de armazenar qualquer coisa.

**Módulos.** O núcleo do localSIEM (armazenamento, pesquisa, regras, agrupamento, envio ao SOC, saúde) é o mesmo para todos os serviços; cada módulo adiciona o que é específico de um serviço. O módulo Apache + ModSecurity (`apache2`) vem do repositório `localSIEM-modules` (GitHub) e é instalado, atualizado e desinstalado somente pela interface web, nunca pelo instalador do localSIEM; instalá-lo nunca instala o Apache nem o ModSecurity. Todos os módulos são instalados, atualizados e desinstalados da mesma forma, pela interface web. A seção 13 explica como instalá-los e atualizá-los, ver o estado deles, ativá-los e desativá-los e configurá-los.

<a id="installation"></a>
## 2. Instalação

A instalação tem duas etapas: o núcleo do localSIEM e, depois, os módulos dele (a etapa 2, abaixo). Execute como root, diretamente do GitHub:

```bash
# Debian 13
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
# Alpine 3.24 (primeiro: apk add bash curl)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
```

A interface web do localSIEM sempre escuta na **porta 10443 com HTTPS**: o instalador verifica se a porta está livre e para se outro serviço a usa. A ação e as opções vão depois de `bash -s --`. O instalador verifica o que precisa (Python 3.13 com `venv`, OpenSSL, os certificados das CAs, as ferramentas de ACL, logrotate, curl, tar) e instala o que falta. Executado assim, por pipe, ele baixa a branch `main` de `https://github.com/PYMEHackers/localSIEM`; executado a partir de uma cópia do projeto (`bash deploy/install-update-reinstall-debian.sh --install`), ele instala essa cópia.

**A ação.** O instalador sempre precisa de uma ação; sem ela, ele para e as lista:

| Ação | Uso |
|---|---|
| `--install` | Instala o localSIEM em um servidor que não o tem. Se encontrar qualquer coisa do localSIEM (`/opt/localsiem`, os serviços dele ou o usuário `localsiem` dele, também de uma instalação que falhou no meio), ele para e indica `--update` e `--reinstall`. |
| `--update` | Atualiza o localSIEM instalado: mantém os dados, as contas, as configurações, os módulos e as opções dadas antes (abaixo). |
| `--reinstall [--yes]` | Exclui o localSIEM instalado com todos os dados dele, como faz o `--uninstall` (abaixo), e o instala novamente do zero, com novas senhas. Antes, ele pede que você digite `yes` (`--yes` não pede; é necessário sem terminal) e não exclui nada até que a nova cópia seja baixada e as opções sejam verificadas. As opções da instalação anterior não são mantidas: informe-as novamente. |
| `--uninstall [--yes]` | Exclui o localSIEM e todos os dados dele do servidor (abaixo). Deve ser usado sozinho. |

`--update` e `--reinstall` param quando o localSIEM não está instalado: use `--install`.

Opções de `--install`, `--update` e `--reinstall`:

| Opção | Uso |
|---|---|
| `--allow-from LIST` | IPs e CIDR que podem abrir a interface web, separados por vírgulas: o SOC e os seus administradores |
| `--soc-url URL` | Padrão: `https://soc.pymehackers.com` |
| `--soc-token TOKEN` | Token de ingestão deste cliente no SOC. Opcional: sem um SOC, o localSIEM funciona por conta própria (seção 5) |
| `--soc-ca-file PATH` | Só para um SOC com certificado privado (servidores de teste) |
| `--domain NAME` | Nome do servidor, para o certificado e o endereço do SIEM (padrão: o nome de host dele) |
| `--certificate PATH --private-key PATH` | Certificado a usar. Sem elas, o localSIEM copia o certificado do Let's Encrypt de `--domain` se houver um (e o copia novamente a cada renovação), ou cria um autoassinado. |
| `--retention-days N`, `--max-disk SIZE` | Retenção (seção 16) |
| `--enable-mfa`, `--disable-mfa` | Verificação em duas etapas ativada (obrigatória para todas as contas) ou desativada. Sem elas, uma instalação nova a deixa desativada e uma atualização mantém o que foi escolhido em Administração › Configurações (seção 14). |
| `--rotate-credentials` | Cria um novo segredo de assinatura JWT e o grava em `/root/webapp-credentials.txt` |
| `--ref REF` | Branch ou tag do localSIEM a baixar (padrão `main`) |
| `--source-url URL` | Arquivo compactado (`.tar.gz`) do localSIEM a instalar em vez do arquivo do GitHub (um espelho) |
| `--modules-repository URL`, `--modules-ref REF` | Repositório (ou arquivo compactado `.tar.gz`) e branch ou tag de onde a interface web instala e atualiza módulos (seção 13). Padrão: `https://github.com/PYMEHackers/localSIEM-modules`, branch `main`. |

**Sempre a última versão.** O GitHub guarda os arquivos de `raw.githubusercontent.com` em um cache por até 5 minutos após cada alteração, então os comandos acima leem o instalador pela API do GitHub, que não tem cache; depois, o instalador pergunta a essa API qual commit é a branch e baixa exatamente esse commit, e pede a todos os servidores do caminho que não respondam com uma cópia em cache. Sem um token, o GitHub permite 60 requisições à API por hora de cada endereço IP: se ele recusar, o comando falha com `403` (aguarde e execute-o novamente); se só a pergunta do instalador falhar, o instalador avisa e baixa a branch.

As opções são lembradas, em `/opt/localsiem/config/install.env`: `--update` sem opções as mantém. Para atualizar:

```bash
# Debian 13 (no Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --update
```

O log do instalador é `/root/webapp-install.log` e as senhas que ele cria ficam em `/root/webapp-credentials.txt` (ambos com modo 600). Ele mostra o progresso em etapas numeradas (`[3/12] Getting localSIEM`), com `✓` para o que está feito, `!` para avisos, `✗` para falhas e `·` para informações, em cores em um terminal (`NO_COLOR=1` ou `LOCALSIEM_COLOR=never` desativam as cores). A saída do apt-get ou do apk, do curl, do tar e do pip só vai para o log; quando um deles falha, a tela mostra as últimas 20 linhas dele. O log recebe as mesmas linhas, sem cores, com as horas no formato de registro. No final, ele executa o diagnóstico de cada módulo ativado (seção 4) e mostra um resumo: o endereço da interface web, que também é o endereço do SIEM a informar ao SOC, o arquivo de credenciais, o log e o estado do SOC, seguidos dos próximos passos. Se falhar, ele diz em qual etapa parou.

**Desinstalar.** O `--uninstall` exclui o localSIEM do servidor: ele para e remove os serviços dele e exclui `/opt/localsiem` (código, configurações, o banco de dados com todos os eventos e alertas, certificados e módulos), o usuário `localsiem`, o acesso de leitura aos logs que o `setup-modules` deu, a configuração do Apache (`localsiem.conf`) que a opção `--configure-apache` das versões antigas do módulo do Apache (1.2.0 ou anteriores) adicionava, com um configtest e um reload do Apache, o arquivo do logrotate, o hook do Let's Encrypt e as entradas do localSIEM de `/root/webapp-credentials.txt` (o arquivo é excluído quando não sobra mais nada nele). Antes, ele pede que você digite `yes` (`--yes` não pede; é necessário sem terminal). Se não houver nada do localSIEM no servidor, ele diz «Nothing of localSIEM was found on this server.». O log do instalador, os pacotes que o instalador adicionou, o `mod_unique_id` (Debian) e os logs do Apache são mantidos, inclusive o `localsiem_access.log` que aquele arquivo fazia o Apache gravar e o `modsec_audit.log`: o localSIEM nunca altera nem exclui um log do Apache. Para desinstalar:

```bash
# Debian 13 (no Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --uninstall
```

**Reinstalar.** Para começar do zero em uma única etapa, o `--reinstall` exclui tudo da mesma forma e instala o localSIEM novamente (informe as opções novamente):

```bash
# Debian 13 (no Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --reinstall --allow-from 203.0.113.10 --soc-token TOKEN
```

**2. Os módulos.** O instalador do localSIEM **não instala nenhum módulo**: ele deixa o localSIEM pronto para eles, e uma atualização mantém os já instalados (e o acesso de leitura aos logs deles). Os módulos são instalados **somente pela interface web**: Módulos › Instaláveis (seção 13), que lista os módulos do repositório `localSIEM-modules` que ainda não estão instalados; esse repositório não tem instalador próprio. O localSIEM baixa o módulo dele, copia a pasta do módulo (lá, `mod-<name>/`) para `/opt/localsiem/modules/<name>/` (as pastas `tests/` não são copiadas; um módulo instalado novamente recupera as configurações que tinha) e reinicia o coletor. Os módulos também são atualizados e desinstalados pela interface web: **Atualizar**, quando o repositório tem uma versão mais nova, e **Desinstalar**, ambos em Módulos › Instalados (seção 13).

Ler os logs de um módulo exige root, então, quando o módulo é instalado, a interface web mostra em uma caixa de diálogo o comando a executar como root no servidor:

```bash
/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py setup-modules
```

Ele dá ao usuário `localsiem` acesso de leitura às pastas de logs que cada módulo instalado declara (`/var/log/apache2` para o módulo do Apache; seção 3.7), também aos arquivos das próximas rotações, reinicia o localSIEM e executa o diagnóstico como `localsiem`. Ele pode ser executado novamente a qualquer momento. Esse acesso de leitura, que o localSIEM dá, é tudo o que o root faz pelos módulos.

**Instalar um módulo nunca instala o software que ele monitora**, nem qualquer outra coisa: um módulo funciona com o que o servidor já tem e nunca altera nada fora de `/opt/localsiem/`. Um módulo novo começa ativado ou desativado conforme o autor dele decidiu, exceto quando falta ao servidor o que ele precisa (para o módulo do Apache: o Apache e o ModSecurity 2): então ele é instalado **desativado**, a interface web diz o que falta e o interruptor dele fica bloqueado até que **Reconfigurar** o encontre (seção 13). O estado dele fica em **Módulos › Instalados** (seção 13).

<a id="requirements"></a>
## 3. Requisitos do Apache e do ModSecurity

Estes são os requisitos do módulo Apache + ModSecurity. O próprio Apache e o ModSecurity 2 precisam estar instalados antes: sem eles, o módulo não pode ser ativado (seção 13). O localSIEM nunca altera por conta própria a configuração do Apache, nem os logs do Apache, o formato deles ou a forma como são gravados: o módulo lê os logs que o servidor já grava e se adapta a eles. O diagnóstico do módulo (seção 4) verifica cada requisito: para o ModSecurity com o CRS e o `SecRuleEngine` (ponto 1), o `mod_unique_id` (ponto 2) e o acesso de leitura (ponto 7), ele mostra o trecho ou o comando exato para cada um que falta, para você aplicar; os logs (pontos 3 a 6) ele só descreve, sem propor alterá-los.

1. **ModSecurity 2 com OWASP CRS**, com `SecRuleEngine On` ou `DetectionOnly`. Ambos funcionam: com `DetectionOnly` nada é bloqueado, então todas as correspondências vão para o SOC.
2. **`mod_unique_id`**, de que o ModSecurity 2 precisa para funcionar (sem ele, não inspeciona nada; o Alpine não o carrega por padrão) e que junta os três registros de cada requisição.
3. **Um log de acesso**, como o Apache o grava. Qualquer formato funciona (`combined`, `vhost_combined`, `common` ou qualquer `LogFormat` da configuração): cada linha é unida à sua requisição pelo IP do cliente, método, URI, status e hora («correlação fraca»), e o vhost vem de `%v` ou, sem ele, do cabeçalho Host e da porta do registro de auditoria. Quando o formato também tem milissegundos, `%v` e `%{UNIQUE_ID}e` (como as linhas `localsiem_combined` que alguns servidores já gravam), cada linha é unida à sua requisição pelo `UNIQUE_ID`, e com `%D` o localSIEM também obtém a duração dela. Um log de acesso cujo formato não tem o IP do cliente, a hora, a linha da requisição ou o status é lido como está, mas as linhas dele não podem ser unidas às suas requisições: essas requisições são vistas no log de auditoria do ModSecurity. Um `CustomLog` cujo formato não tem nenhuma diretiva grava o mesmo texto em cada linha e não é lido.
4. **`mod_remoteip`**, que decide qual IP os logs contêm. Se o site estiver atrás de um proxy ou de um balanceador de carga e o Apache não o usar, os logs contêm o IP do proxy, assim como os alertas e as regras por IP: o diagnóstico e o aviso de saúde «Falta o IP real do cliente» (seção 15) indicam isso.
5. **O log de auditoria do ModSecurity**, como o ModSecurity o grava: serial ou concorrente, JSON ou nativo, com as partes que tiver. Sem ele (`SecAuditEngine Off` ou sem `SecAuditLog`), o localSIEM decide só a partir do `error.log`, e a ficha da requisição não tem cabeçalhos nem lista de regras. Sem a parte `H`, a ação tomada não pode ser lida dele. A parte `E` (o corpo da resposta), se for registrada, nunca vai para o SOC; a parte `K` (o texto completo de cada regra executada) não é armazenada. Com o tipo concorrente (um arquivo por transação), o ModSecurity costuma criar os arquivos com modo 600, e o localSIEM só os lê se o `localsiem` puder (ponto 7).
6. **Mascaramento na origem**: se o ModSecurity não mascarar o log de auditoria em disco (as ações `sanitise` dele), esse arquivo pode conter senhas e cookies; o localSIEM os mascara antes de armazená-los, e eles nunca vão para o SOC.
7. **Acesso de leitura aos logs para o usuário `localsiem`**. O comando para root da seção 2 (`manage.py setup-modules`) faz isso para as pastas que os módulos instalados declaram (`/var/log/apache2` para o módulo do Apache), e o instalador do localSIEM faz isso novamente a cada atualização: no Debian, ele adiciona `localsiem` ao grupo `adm` e, como no Alpine, dá ao `localsiem` acesso de leitura a essas pastas por meio de ACLs, incluindo uma ACL padrão para que os arquivos das próximas rotações também possam ser lidos. Os logs que você adicionar manualmente em outra pasta (seção 13) também precisam desse acesso, por exemplo `setfacl -m g:localsiem:rx /srv/logs`, `setfacl -d -m g:localsiem:r /srv/logs` e `setfacl -m g:localsiem:r /srv/logs/*.log`. O localSIEM só lê os logs: nunca grava neles, nem os rotaciona, trunca, move ou exclui. Quando ele começa a acompanhar um log (na primeira inicialização, depois de instalar ou ativar um módulo, ou quando o root lhe dá acesso de leitura), ele começa pelo final: o que o log já tinha é histórico e nunca gera alerta; só o log de um vhost criado depois é lido desde o início (quando tem até 5 MB).

<a id="doctor"></a>
## 4. O diagnóstico

Cada módulo tem o seu próprio diagnóstico. O diagnóstico do módulo do Apache verifica cada requisito da seção 3 e mostra o trecho ou o comando que resolve cada um que falta; os logs (formato, `mod_remoteip`, log de auditoria, mascaramento) ele só descreve, sem propor alterá-los, e lista as fontes encontradas (e as que não consegue ler, como os logs por pipe). Ele é executado no final de cada instalação do localSIEM e do comando para root da seção 2, aparece na página de cada módulo (**Módulos › Instalados › Configurar**, seção 13, com o botão «Descobrir novamente e executar o diagnóstico») e pode ser executado a qualquer momento para todos os módulos ativados:

```bash
runuser -u localsiem -- /opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor   # Debian
su -s /bin/sh localsiem -c "/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor"   # Alpine
```

`✓` está bem, `!` funciona com limitações, `✗` precisa ser corrigido, `·` só se aplica em algumas situações (em cores em um terminal; onde não é possível escrever UTF-8, `+`, `!`, `x` e `-`). Um módulo que não pode ser carregado aparece primeiro como `✗ Module <name> not loaded: <reason>`. Um módulo desativado não tem diagnóstico: se ele tiver requisitos (seção 13), o diagnóstico os mostra no lugar dele, para que você saiba se ele pode ser ativado.

<a id="soc"></a>
## 5. Conexão com o SOC

Conectar o localSIEM a um SOC é opcional. Sem um SOC (sem token, ou com **Enviar os alertas ao SOC** desativado), o localSIEM funciona por conta própria: ele guarda cada alerta na aba **Alertas** como «Não enviado» e nunca os envia depois, nem mesmo quando um SOC é configurado mais tarde: a partir daí, só os novos alertas vão para ele. Os canais (Telegram) funcionam com ou sem um SOC.

O administrador do SOC:

1. Cria um token de ingestão para o cliente (ele só é mostrado uma vez) e o entrega a você. Configure-o com `--soc-token` ou em **Administração › SOC**.
2. Define como **endereço do SIEM** do cliente `https://<server>:<port of localSIEM>` (mostrado pelo instalador e em Administração › SOC). O analista responsável por um alerta usa esse link para vir investigar.
3. Informa a você os IPs de saída do SOC: adicione-os aos IPs permitidos (`--allow-from` ou Administração › Configurações) e **abra a porta no firewall só para eles e para os seus administradores**.

O localSIEM envia um **heartbeat** a cada 5 minutos. Se o SOC não receber nem alertas nem heartbeats por um tempo (60 minutos por padrão), ele avisa a equipe dele. Os alertas aguardam em uma fila persistente: uma queda de rede ou uma reinicialização não perde nenhum, e enviar um novamente nunca o duplica no SOC. Se o SOC responder que o cliente esgotou os números de alerta dele, o localSIEM para de enviar, mantém a fila e mostra isso em Administração › SOC.

Cada alerta leva um nome de regra estável, uma descrição com a consulta exata para colar na pesquisa do localSIEM, e detalhes: vhost, IP do cliente, método, URI (mascarada), resposta, user agent, os dados do ModSecurity (motor, ação, fase, pontuação, limite, regras, dados correspondentes), o grupo (contagem, primeira e última vez, `UNIQUE_ID`s de amostra) e o **contexto** do IP: requisições e requisições bloqueadas na última hora, regras bloqueadas e a primeira vez em que ele foi visto.

<a id="signin"></a>
## 6. Login e contas

Abra `https://<server>:10443/`: a página de login é só o formulário, com o logotipo, o usuário, a senha, **Continuar** e, abaixo dele, o idioma e o tema. As contas são criadas por um administrador; não há cadastro aberto. As senhas têm pelo menos 8 caracteres. A **Verificação em duas etapas** vem desativada por padrão; quando um administrador a ativa (Administração › Configurações, seção 14), ela é obrigatória para todas as contas: no próximo login, escaneie o código QR com um aplicativo autenticador (Google Authenticator, Microsoft Authenticator, Aegis, FreeOTP...; ele aparece como «PYMEHackers localSIEM») e digite o código dele; a partir daí, cada login pede o código do aplicativo. Após várias tentativas com falha, o login fica bloqueado por alguns minutos.

**Acesso direto com um token.** Um administrador pode dar a um analista uma URL de acesso, `https://<server>:10443/auth/login/auto?token=...` (Usuários › Tokens de acesso, seção 14). Abri-la a partir de um endereço permitido faz o login imediatamente, sem senha nem segundo fator, e abre a Visão geral do painel de usuário; adicione `&next=/user/dashboard/search/?q=...` para abrir outra página do site. Se o token não funcionar, a página de login diz o motivo: token desconhecido, expirado ou revogado, ou a conta está desativada ou não é mais de analista. Guarde a URL como uma senha: quem a tiver pode entrar com essa conta até que ela expire ou seja revogada. Cada login, com senha ou com um token, e cada tentativa com falha são registrados (Logins, seção 14).

Depois de entrar, você chega à **Visão geral** do seu painel (seção 7). Um link para uma pesquisa (por exemplo, vindo do SOC) abre a página de login se necessário e depois **a mesma pesquisa com os parâmetros dela**.

Funções: **analista** (trabalha no painel de usuário: visão geral, pesquisa, visualização ao vivo, alertas, o estado dos módulos e a conta) e **administrador** (trabalha no painel de administrador: o mesmo, mais a configuração dos módulos e a administração). O idioma (de-DE, en-GB, en-US, es-AR, es-ES, fr-FR, he-IL, hi-IN, it-IT, ja-JP, ko-KR, pt-BR, pt-PT, ru-RU, zh-CN), o tema (sistema, claro ou escuro) e o relógio UTC ficam na barra de título de todas as páginas dos painéis; a página de login os tem abaixo de **Continuar** e começa com os últimos escolhidos neste navegador (sem uma escolha, os do navegador e do sistema). O idioma mostrado quando você clica em **Continuar** passa a ser o idioma da sua conta: os painéis o mantêm, em qualquer navegador, até que você o altere. As horas estão sempre em UTC no formato nativo `2026/10/29@13:59:59.723`. Os arquivos que o localSIEM grava (as exportações, `/root/webapp-credentials.txt`, o log do instalador) e os alertas que ele envia ao SOC usam o formato de registro `2026-10-29@13-59-59.723`, também em UTC.

<a id="dashboards"></a>
## 7. Os dois painéis

Cada função tem o seu próprio painel; o endereço dele diz em qual você está. A barra lateral tem o logotipo no topo, as abas (uma linha entre cada grupo) e, embaixo, **Sair**.

| | Painel de administrador | Painel de usuário |
|---|---|---|
| Quem | Administradores | Analistas |
| Endereço | `/admin/dashboard/<tab>/` | `/user/dashboard/<tab>/` |
| Abas | Visão geral, Pesquisa, Ao vivo, Alertas; Módulos (Instalados e Instaláveis), Usuários (Contas e Tokens de acesso), SOC, Canais (Geral e Telegram), Configurações, Auditoria de pesquisas, Logins; Conta | Visão geral, Pesquisa, Ao vivo, Alertas, Módulos (só o estado), Conta |

Cada aba tem o seu próprio endereço (por exemplo `/admin/dashboard/logins/`), e `/admin/dashboard/` ou `/user/dashboard/` abrem a Visão geral. As seções de uma aba também têm o delas: `/admin/dashboard/users/` abre `/admin/dashboard/users/accounts/` e os tokens de acesso ficam em `/admin/dashboard/users/tokens/`; `/admin/dashboard/modules/` abre `/admin/dashboard/modules/installed/` e os módulos instaláveis ficam em `/admin/dashboard/modules/installable/`. Um endereço do outro painel leva você à mesma aba do seu: um administrador que abre um link para `/user/dashboard/search/?q=...` (o link habitual do SOC) obtém a mesma pesquisa em `/admin/dashboard/search/`; um analista que abre uma aba de administração obtém a Visão geral do painel de usuário.

**O que os analistas veem.** Tudo o que é necessário para investigar: a visão geral, as pesquisas com as fichas das requisições, a visualização ao vivo, os alertas e o estado de cada módulo (ativado ou desativado, funcionando ou não, e os contadores dele). Eles não podem ativar nem desativar módulos, configurá-los, ver o diagnóstico ou as regras deles, nem gerenciar os usuários, os tokens de acesso, a conexão com o SOC, as configurações, a auditoria de pesquisas ou o registro dos logins.

<a id="overview"></a>
## 8. Visão geral

A primeira aba dos dois painéis. Ela é atualizada a cada 15 segundos e mostra:

- **Eventos (24 h)**, com quantos deles geraram um alerta; **Bloqueados (24 h)**, o que o ModSecurity já resolveu (mantido, sem alerta); **Alertas (24 h)**, com quantos estão aguardando o SOC; e **Módulos funcionando**, os módulos ativados que estão «Ativado e funcionando» do total de ativados (em verde quando todos funcionam).
- **Atividade das últimas 24 horas**: eventos por hora; a parte azul de cada barra é o que o ModSecurity bloqueou. Clique em uma hora para abrir a pesquisa dos eventos dela.
- **Estado dos módulos**: cada módulo com o seu estado (seção 13) e o que está lendo; «Ver os módulos» abre a aba Módulos.
- **Sistema**: se o coletor está em execução (e a versão dele), desde quando, o estado da conexão com o SOC, o último heartbeat, os alertas aguardando o SOC, o disco livre e o tamanho do banco de dados em relação ao máximo dele.
- **Últimos alertas**: os seis mais recentes (severidade, regra, IP, contagem, status, última vez); «Ver todos os alertas» abre a aba Alertas.

<a id="search"></a>
## 9. Pesquisa

A aba **Pesquisa** tem um campo de pesquisa e um intervalo de tempo (últimos 15 minutos, última hora, últimas 24 horas, últimos 7 dias, últimos 30 dias ou um intervalo personalizado no formato nativo).

| Sintaxe | Significado |
|---|---|
| `word` | Pesquisa de texto completo no texto original (mascarado), também decodificado de URL |
| `"exact phrase"` | Frase |
| `field:value` | Campo igual a um valor (os campos de texto não diferenciam maiúsculas de minúsculas) |
| `field:*part*` | Curingas |
| `status:>=500`, `status:400..499`, `status:4xx` | Comparações e intervalos em campos numéricos |
| `a b` / `a AND b`, `a OR b`, `NOT a` / `-a`, `( )` | Operadores e parênteses |

| Grupo | Campos |
|---|---|
| Rede | `ip`, `vhost`, `host` |
| Requisição | `method`, `uri`, `path`, `query`, `status`, `bytes`, `duration` (microssegundos), `ua`, `referer` |
| Origem | `uid` (UNIQUE_ID), `module`, `source` (`access`/`error`/`audit`) |
| ModSecurity | `rule` (id do CRS, ou `localsiem:<rule>`), `category`, `phase`, `score`, `engine` (`on`/`detection-only`) |
| Alertas | `severity`, `action` (`blocked`/`none`), `alert` (código do SOC), `sent` (`yes`/`no`) |
| Qualidade | `parse` (`ok`/`partial`/`unparsed`) |

Exemplos:

- `ip:203.0.113.7` — tudo de um IP
- `rule:942100` — requisições que corresponderam a essa regra do CRS
- `status:200 action:none category:sqli` — injeções de SQL que não foram bloqueadas e receberam um 200
- `uri:*wp-login*`
- `"union select"`
- `uid:ZTx1kH8AAQEAAB2gTkAAAAAB` — uma requisição
- `alert:c00007a0001F` — as requisições de um alerta do SOC
- `(category:sqli OR category:xss) sent:no -status:404`

Categorias: `sqli`, `xss`, `lfi`, `rfi`, `rce`, `php`, `java`, `fixation`, `generic`, `protocol`, `multipart`, `scanner`, `method`, `data-leakage`, `webshell`, e as das regras do localSIEM: `bruteforce`, `enumeration`, `sensitive-file`, `db-error`, mais `health-*`.

Um erro de sintaxe é mostrado abaixo do campo com a posição do erro. Uma pesquisa que demora mais que o limite dela (5 s) pede que você restrinja o intervalo.

A página de resultados mostra:

- **O histograma** ao longo do tempo; a parte azul de cada barra é o que o ModSecurity bloqueou. Arraste sobre as barras (ou clique em uma) para restringir o intervalo.
- **Resumos** da consulta: IPs com mais requisições, caminhos mais solicitados, códigos HTTP e regras mais frequentes. Clique em um valor para adicioná-lo à consulta.
- **A tabela de resultados** (HORA, FONTE, IP, MÉTODO, URI, CÓDIGO, AÇÃO, REGRAS, ALERTA), com os mais recentes primeiro, com «Carregar mais».
- **Exportar** para CSV ou JSON (dados mascarados, até 10 000 linhas, horas no formato de registro `2026-10-29@13-59-59.723`) e **Copiar link** (com horas absolutas). O formato do link é `/user/dashboard/search/?q=<query>&from=<native time>&to=<native time>` (`/admin/dashboard/search/...` quando copiado por um administrador); um link de qualquer um dos painéis funciona para as duas funções.

Toda pesquisa e exportação é registrada (quem, o quê, quando) e fica visível para os administradores: os logs contêm dados pessoais.

<a id="card"></a>
## 10. A ficha da requisição e os pivôs

Clique em uma linha para abrir a ficha da requisição: hora, vhost, IP do cliente, método, URI, código, tamanho, duração, user agent, `UNIQUE_ID`, correlação, ação tomada, motor do ModSecurity, fase, pontuação e limite, categoria, severidade e alertas; e, para cada registro, o conteúdo analisado dele: as regras que corresponderam, com a mensagem e os dados delas, os cabeçalhos da requisição e o corpo mascarado, os cabeçalhos da resposta, as linhas de erro e a linha original. O módulo de cada registro adiciona o que sabe mostrar (o módulo do Apache reconstrói os cabeçalhos e o corpo a partir do registro de auditoria).

Notas na ficha: um 403 sem nenhum rastro do ModSecurity é marcado como **duvidoso** (não é contado como bloqueio); **correlação fraca** significa que a linha de acesso foi unida à sua requisição pelo IP do cliente, método, URI, status e hora, porque o log de acesso não tem `UNIQUE_ID`; um **erro de banco de dados** apareceu para a requisição.

Pivôs: **Este IP** (toda a atividade dele), **±5 min** (a linha do tempo em torno da requisição), **Regra …** (cada regra que correspondeu), **Esta categoria**, **Este UNIQUE_ID**.

<a id="live"></a>
## 11. Visualização ao vivo

A aba **Ao vivo** mostra os novos eventos assim que o coletor os armazena (após a janela de correlação de 5 segundos), com os mais recentes no topo. O filtro usa a sintaxe da pesquisa. **Pausar** interrompe as atualizações; ao retomar, continua a partir do evento mais recente.

<a id="alerts"></a>
## 12. Alertas

A aba **Alertas** lista os alertas gerados pelo localSIEM: código do SOC, severidade, regra, IP, vhost, contagem, primeira e última vez, e status:

| Status | Significado |
|---|---|
| No buffer | Reunindo a rajada (60 s) antes de sair |
| Na fila | Aguardando o SOC (rede fora do ar, SOC sem responder) |
| Enviado | Aceito pelo SOC; o código dele é mostrado |
| Rejeitado | O SOC recusou esse alerta; o restante da fila continua. Ele pode ser colocado na fila novamente em Administração › SOC. |
| Não enviado | Não havia nenhum SOC configurado, ou o envio para ele estava desativado: o alerta fica no localSIEM e nunca é enviado depois (o SOC é opcional, seção 5) |

Clique em uma linha para ver a descrição, as **requisições do alerta** (até 50, as mais antigas primeiro, como na pesquisa: clique em uma para abrir a ficha dela, com a requisição, os cabeçalhos dela, as regras do ModSecurity e as linhas originais), a janela, o `external_id` e o alerta exato enviado ao SOC. **Pesquisar** abre a pesquisa do grupo. Enquanto um alerta está aberto, a lista não é atualizada.

<a id="modules"></a>
## 13. Módulos

No painel de administrador, a aba **Módulos** tem duas seções, cada uma com o seu próprio endereço: **Instalados** (`/admin/dashboard/modules/installed/`), que abre por padrão (`/admin/dashboard/modules/` leva para lá), e **Instaláveis** (`/admin/dashboard/modules/installable/`), onde os módulos são instalados (abaixo). Os analistas só têm a lista dos módulos instalados, sem seções (`/user/dashboard/modules/`).

**Instalados** lista os módulos instalados, uma linha para cada um, em toda a largura, com a mesma disposição do cabeçalho da página do módulo: no topo, o nome, o id e a versão e, abaixo, o **estado** dele, um resumo, os motivos do estado dele e, se estiver ativado, os contadores dele: fontes em leitura, linhas da última hora, últimos dados, eventos e requisições bloqueadas das últimas 24 horas e o resultado do diagnóstico dele. Os administradores também veem o interruptor à direita do nome e, embaixo da linha, os botões dele. A página é atualizada a cada 10 segundos. Sem nenhum módulo instalado, ela diz «Instale módulos pela aba Instaláveis.» (para os analistas: «Nenhum módulo instalado. Um administrador os instala em Módulos › Instaláveis.»).

| Estado | Significado |
|---|---|
| Ativado e funcionando | Ativado, carregado pelo coletor e lendo as fontes dele. Os avisos do diagnóstico são listados como notas e não o alteram. |
| Ativado, com avisos | Ativado, mas sem fontes, com uma fonte que ainda não existe, ou instalado depois que o coletor foi iniciado (reinicie o serviço `localsiem`). |
| Erro | Ele não carrega (o motivo é mostrado), o diagnóstico dele relata um erro, ou uma fonte não pode ser lida (permissões do usuário `localsiem`, seção 3.7). |
| Aplicando a alteração… | Acabou de ser ativado ou desativado; o coletor está aplicando a alteração (alguns segundos). |
| Desativado | Desativado: o localSIEM não lê os logs dele nem envia os alertas dele. O que já está armazenado é mantido. Com o motivo «Falta a este servidor o que ele precisa: …», ele foi instalado sem os requisitos dele e ainda não pode ser ativado (veja Requisitos e Reconfigurar, abaixo). |
| Desconhecido | O coletor não está em execução (serviço `localsiem`): ninguém está lendo nada. |

Os **analistas** só veem esta lista. Os **administradores** também têm, em cada linha:

- **O interruptor** de cada módulo, para ativá-lo ou desativá-lo. Desativá-lo pede confirmação. A alteração se aplica imediatamente, sem reiniciar nada. Enquanto falta ao servidor o que um módulo precisa, o interruptor dele fica bloqueado («Desativado: faltam requisitos»).
- **Configurar**, que abre a página do módulo (`/admin/dashboard/modules/installed/<name>/`; o endereço antigo `/admin/dashboard/modules/<name>/` leva você até ela):
  - o cabeçalho com o estado, a pasta onde o módulo está instalado, o interruptor, «Voltar aos módulos instalados» (volta para Instalados) e «Descobrir novamente e executar o diagnóstico»; para um módulo com requisitos, também o botão «Reconfigurar» e, enquanto o módulo estiver desativado ou faltar algum, os **Requisitos** dele (abaixo);
  - **Configurações**: o formulário das configurações próprias do módulo; «Salvar as configurações» as aplica imediatamente;
  - **Fontes**: os logs que ele lê (tipo, caminho, vhost, linhas e linhas não analisadas da última hora, últimos dados, estado) e, abaixo, os logs que ele encontrou mas não lê, com o motivo;
  - **Diagnóstico**: as verificações de requisitos dele, com o trecho ou o comando que resolve cada um que falta e um botão «Copiar» (os logs são apenas descritos);
  - **Regras**: cada regra do módulo com o seu interruptor («Ativa»), severidade, limite e janela (limite e janela só para as regras de limite e de sequência); «Salvar as regras» as aplica imediatamente.
- **Atualizar**, quando o repositório `localSIEM-modules` tem uma versão mais nova do módulo. Cada vez que você abre Instalados, o localSIEM consulta o repositório: enquanto isso, ele diz «Consultando o repositório em busca de versões mais novas…» e, se a consulta falhar, «Não foi possível consultar o repositório em busca de versões mais novas: <error>», e a lista funciona normalmente. Para que o repositório não seja baixado a cada visita, o navegador reutiliza a resposta dele por 10 minutos; «Consultar o repositório», em Instaláveis, sempre o baixa novamente, e instalar, atualizar ou desinstalar um módulo descarta a resposta guardada. A atualização a cada 10 segundos nunca o baixa. Um módulo com uma versão mais nova mostra, na sua linha, o aviso «O repositório tem a versão X (a instalada é a Y).» com o botão **Atualizar**. Se essa versão precisar de um localSIEM mais novo, o aviso não tem botão e diz isso: «O repositório tem a versão X, mas ela precisa do localSIEM Z ou mais recente: atualize o localSIEM para instalá-la.» **Atualizar** pede confirmação («Atualizar o módulo»): o localSIEM baixa a nova versão do repositório, substitui a instalada por ela e reinicia o coletor; as configurações dele são mantidas, e o módulo continua ativado ou desativado como estava. Enquanto isso, o botão diz «Atualizando…»; no final, uma mensagem diz «<módulo> atualizado para a versão X.» Uma caixa de diálogo, «<módulo> atualizado», só se abre quando há algo mais a fazer: se a nova versão lê outros logs, ela mostra o comando para root (`manage.py setup-modules`, seção 2, com «Copiar»); se o coletor não respondeu, ela pede que você reinicie o serviço `localsiem`.
- **Desinstalar**, na linha de cada módulo instalado (também na de um que não carrega) e na página dele. Depois da confirmação, o localSIEM exclui `/opt/localsiem/modules/<name>/` e reinicia o coletor sem ele: ele para de ler os logs dele e de enviar os alertas dele. Os eventos e alertas já armazenados ainda podem ser pesquisados, e as configurações dele (e as alterações das regras dele) ficam em `settings.json`, então voltam se você o instalar novamente. O acesso de leitura que o root deu ao `localsiem` aos logs dele não é retirado; se nenhum outro módulo ler essa pasta, você pode removê-lo manualmente, por exemplo `setfacl -R -x g:localsiem /var/log/apache2` e `setfacl -d -x g:localsiem /var/log/apache2`.

**Instaláveis** (só para administradores) tem o cartão «Módulos instaláveis»: os módulos do repositório `localSIEM-modules` (por padrão `https://github.com/PYMEHackers/localSIEM-modules`, branch `main`; as opções do instalador `--modules-repository` e `--modules-ref` o alteram) que ainda não estão instalados neste servidor. «Consultar o repositório» o baixa e lista esses módulos, cada um com o nome, o id, a versão e o resumo dele e o seu botão ou nota:

| Botão ou nota | Significado |
|---|---|
| Requisitos | Mostra o que o módulo precisa no servidor e os comandos que o instalam (abaixo) |
| Instalar | Instala o módulo |
| Precisa do localSIEM X ou mais recente | Ele não pode ser instalado: atualize o localSIEM primeiro |
| O módulo do repositório não é válido | Ele não pode ser instalado |

**Requisitos** abre a caixa de diálogo «<módulo>: requisitos», com o que o módulo precisa no servidor e os comandos que o instalam, declarados pelo próprio módulo (`install_requirements` do `module.json` dele). Instalar um módulo nunca instala o software que ele monitora, então execute-os no servidor **antes** de instalar o módulo. A caixa de diálogo mostra os comandos para o sistema deste servidor («Este servidor: Debian GNU/Linux 13 (trixie)») duas vezes, cada uma com «Copiar»: **Como root** e **Com sudo** (os mesmos comandos com `sudo` na frente), para que você possa colá-los em um terminal do servidor como root ou como um usuário autorizado a usar o sudo. As notas do módulo vêm primeiro (por exemplo, que o Alpine não tem pacote do ModSecurity 2). Se o módulo não declarar comandos para o sistema deste servidor, a caixa de diálogo mostra os de todos os sistemas que ele declara (Debian e Alpine); se ele não declarar nenhum, ela diz «Este módulo não declara nada a instalar no servidor.». O localSIEM nunca executa esses comandos.

Se todos os módulos do repositório já estiverem instalados, ela diz isso («Todos os módulos do repositório já estão instalados.»). Os módulos já instalados nunca aparecem nesta lista: eles são atualizados em Instalados (**Atualizar**, acima). A interface web não reinstala um módulo nem instala uma versão mais antiga dele: para reinstalar um, desinstale-o e instale-o novamente aqui (as configurações dele são mantidas).

Esta lista é a única forma de instalar módulos. O localSIEM baixa o módulo, verifica o `module.json` dele, copia a pasta dele (`mod-<name>/` no repositório) para `/opt/localsiem/modules/<name>/` (sem a pasta `tests/` dele; um módulo instalado novamente recupera as configurações que tinha) e reinicia o coletor, que o carrega em poucos segundos. O módulo sai da lista e uma caixa de diálogo, «<módulo> instalado», diz o que vem a seguir:

- Permitir que o `localsiem` leia os logs do módulo exige root, então a caixa de diálogo mostra **o comando a executar como root** no servidor, com um botão «Copiar»: `manage.py setup-modules` (seção 2), que dá o acesso de leitura e reinicia o localSIEM. Até que o comando seja executado, o módulo pode mostrar «Erro» porque os logs dele não podem ser lidos.
- Se, na primeira instalação, faltar ao servidor o que o módulo precisa, o módulo é instalado desativado e a caixa de diálogo lista o que falta em vez do comando, com a indicação de abrir o módulo em Instalados (**Configurar**) e clicar em **Reconfigurar** assim que estiver presente (abaixo).

A caixa de diálogo tem dois botões: «Fechar» e «Ver os módulos instalados», que abre Instalados. O servidor precisa alcançar o GitHub (HTTPS) para esta lista e para a consulta de versões mais novas em Instalados.

**Requisitos e Reconfigurar.** Instalar um módulo nunca instala o software que ele monitora. Um módulo pode declarar o que o servidor precisa ter antes que ele possa ser ativado: o módulo do Apache precisa do Apache (da configuração dele: `apache2.conf`, `httpd.conf` ou o arquivo da configuração **Arquivo de configuração do Apache**) e do ModSecurity 2 carregado (`mod_security2`; o ModSecurity 3 não conta). Se eles faltarem na primeira instalação, o módulo é instalado **desativado** («Desativado», com o motivo «Falta a este servidor o que ele precisa: …») e o interruptor dele fica **bloqueado**. A página dele lista os requisitos dele como o diagnóstico (título, detalhe e o comando que instala o que falta, com «Copiar»), também enquanto ele está desativado. Depois de instalar o que falta (e, se o Apache estiver em um lugar fora do padrão, definir o **Arquivo de configuração do Apache** e salvar as configurações), clique em **Reconfigurar**: o localSIEM procura isso novamente com as configurações salvas.

- Se encontrar tudo, ele desbloqueia o interruptor, mas não ativa o módulo: você o ativa com o interruptor dele. Ele também mostra o comando para root da seção 2: execute-o, porque os logs criados depois que o módulo foi instalado (`/var/log/apache2`) só podem ser lidos com o acesso de leitura que o root dá.
- Se ainda faltar algo, os requisitos mostram isso novamente.
- Se o módulo já estiver ativado, Reconfigurar também descobre novamente as fontes dele e executa o diagnóstico dele.

Um módulo que está ativado e depois perde os requisitos dele (alguém desinstala o ModSecurity) continua ativado: o diagnóstico dele e o aviso de saúde «O ModSecurity não está mais carregado» (seção 15) relatam isso, e desativá-lo silenciaria justamente esse aviso. O coletor verifica os requisitos quando inicia e quando as configurações dele mudam, nunca periodicamente; `manage.py modules` e `manage.py doctor` também os mostram (seção 17).

**Desativar e ativar o módulo do Apache.** Em **Módulos › Instalados**, use o interruptor de «Apache + ModSecurity» e confirme. Enquanto ele está desativado, o localSIEM não lê os logs do Apache, não executa o diagnóstico nem as regras dele e não envia alertas dele; os eventos já armazenados ainda podem ser pesquisados. Ative o interruptor novamente para retomar (só é possível enquanto o Apache e o ModSecurity estiverem presentes): o coletor continua a partir da posição em que parou em cada log (seguindo as rotações feitas nesse meio-tempo), então também lê o que o Apache gravou enquanto o módulo estava desativado e envia os alertas que isso exigir.

**Configurações do módulo do Apache** (Módulos › Instalados › Apache + ModSecurity › Configurar):

| Configuração | Uso |
|---|---|
| Só as fontes abaixo | Não descobrir os logs a partir da configuração do Apache: ler só as fontes adicionadas manualmente |
| Fontes adicionadas manualmente | Logs a ler além dos descobertos (veja abaixo) |
| Arquivo de configuração do Apache | Vazio: encontrado automaticamente (`/etc/apache2/apache2.conf` no Debian, `/etc/apache2/httpd.conf` no Alpine). Reconfigurar também procura o Apache lá |
| Intervalo de descoberta (segundos) | Com que frequência a configuração do Apache é lida novamente para encontrar novos vhosts e logs (padrão 3600) |
| Limite de bloqueio do ModSecurity | 0: lido da configuração do CRS (`tx.inbound_anomaly_score_threshold`), 5 se não estiver lá |
| Dias de aprendizado para novos arquivos PHP | Durante os primeiros dias, um arquivo PHP nunca visto antes não é relatado como novo (regra `apache-webshell`; padrão 3) |

**Adicionar um log manualmente.** Em **Fontes adicionadas manualmente**, clique em «Adicionar fonte» e preencha **Tipo** (access.log, error.log ou Log de auditoria do ModSecurity), **Caminho** (absoluto) e, se necessário, **Vhost**, **LogFormat** (para um log de acesso em um formato próprio), **Tipo de log de auditoria** (Serial ou Concorrente) e **Pasta de armazenamento da auditoria** (para um log de auditoria concorrente). «Remover» exclui uma fonte. Clique em «Salvar as configurações»: o coletor descobre as fontes novamente de imediato e o novo log aparece em **Fontes**. Se ele aparecer como ilegível, dê ao `localsiem` acesso de leitura à pasta dele (seção 3.7).

**Do módulo `apache` para o `apache2`.** Até o localSIEM 2.1, o módulo do Apache se chamava `apache`; agora ele é `apache2` (pasta `mod-apache2/` no repositório, instalado em `/opt/localsiem/modules/apache2/`, página `/admin/dashboard/modules/installed/apache2/`). Em um servidor que tinha o `apache`, instalar o `apache2` deixa os dois carregados: o antigo fica com os logs do Apache (os dois encontram as mesmas fontes), o `apache2` não mostra nenhuma fonte até que o antigo seja desinstalado, e as configurações do `apache` não são transferidas sozinhas. Para migrar:

1. Anote as configurações que você alterou na página do módulo `apache` (Configurar): fontes adicionadas manualmente, arquivo de configuração do Apache, intervalo de descoberta, limite de bloqueio, dias de aprendizado.
2. Instale o `apache2` em Módulos › Instaláveis.
3. Desinstale o módulo `apache`: **Desinstalar**, na linha dele em Módulos › Instalados ou na página dele. O coletor reinicia e, a partir daí, o `apache2` lê os logs do Apache.
4. Abra a página do `apache2`, informe essas configurações novamente e salve-as. (Em vez disso, como root, você pode copiar em `/opt/localsiem/config/settings.json`, dentro de `"modules"`, o que está em `"apache"` para `"apache2"`, e depois reiniciar o localSIEM.)

As regras mantêm os ids delas (`apache-bruteforce`…) e as alterações delas, e as posições lidas em cada log e a memória dos avisos de saúde são mantidas: o `apache2` continua de onde o `apache` parou, sem ler nada duas vezes. Os eventos armazenados pelo módulo `apache` continuam pesquisáveis (`module:apache`).

<a id="administration"></a>
## 14. Administração

Estas abas só existem no painel de administrador:

- **Módulos** (seção 13), em duas seções: **Instalados** (`/admin/dashboard/modules/installed/`), a lista com o interruptor de cada módulo, **Configurar** (requisitos e Reconfigurar, configurações, fontes, diagnóstico e regras do módulo), **Atualizar** (quando o repositório tem uma versão mais nova) e **Desinstalar**; e **Instaláveis** (`/admin/dashboard/modules/installable/`), os módulos do repositório ainda não instalados, com **Requisitos** e **Instalar**. Os módulos são instalados, atualizados e desinstalados somente lá.
- **Usuários › Contas** (`/admin/dashboard/users/accounts/`): criar contas (uma senha é gerada e mostrada uma única vez; ela precisa ser alterada no primeiro login), redefinir a senha ou a verificação em duas etapas, ativar ou desativar, alterar a função, excluir. Sempre há pelo menos um administrador ativo.
- **Usuários › Tokens de acesso** (`/admin/dashboard/users/tokens/`): **Criar token** para uma conta de analista ativa (os administradores sempre entram com a senha deles, e com o segundo fator quando a verificação em duas etapas está ativada), com um rótulo opcional e uma validade de 7, 30, 90 (padrão), 180 ou 365 dias. A URL de acesso, `https://<server>:10443/auth/login/auto?token=...`, é mostrada **uma única vez**, com um botão «Copiar»: entregue-a ao analista (seção 6). A lista mostra a conta e o rótulo de cada token, os últimos 4 caracteres dele, o estado dele (Ativo, Expirado, Revogado, ou Inutilizável quando a conta está desativada ou não é mais de analista), quando e por quem ele foi criado, quando expira e o último uso dele (hora e IP). **Revogar** o interrompe imediatamente; as sessões que ele já abriu terminam quando expirarem. Uma sessão aberta com um token não pede nem o segundo fator nem a troca de senha. As tentativas com falha contam para o bloqueio temporário do login.
- **SOC**: URL, token (nunca mostrado inteiro), arquivo de CA opcional, **Testar a conexão** (envia um heartbeat), estado do envio, último heartbeat, último erro, fila (aguardando, enviados, rejeitados) e **Enviar a fila agora**. Também o endereço do SIEM a informar ao SOC. O SOC é opcional (seção 5).
- **Canais** (`/admin/dashboard/channels/`), em duas seções, **Geral** (abre por padrão) e **Telegram**: as mensagens que o localSIEM envia a você, além dos alertas que ele entrega ao SOC (abaixo).
- **Configurações**: retenção, disco máximo, IPs permitidos (o seu próprio endereço precisa estar na lista), verificação em duas etapas (desativada por padrão; ativá-la a torna obrigatória para todas as contas e desconecta imediatamente as contas que ainda não a configuraram, incluindo a sua, que a configuram no próximo login; desativá-la mantém os aplicativos autenticadores já configurados para quando ela for reativada), tempo máximo de pesquisa, limite de exportação, janela e buffer de agrupamento, janela de correlação e severidade abaixo do limite. As alterações se aplicam imediatamente. As regras não ficam mais aqui: elas são configuradas em cada módulo (Módulos › Instalados › Configurar).
- **Auditoria de pesquisas**: quem pesquisou o quê e quando.
- **Logins** (`/admin/dashboard/logins/`): cada login no localSIEM e cada tentativa com falha, os mais recentes primeiro: hora, conta, método (Senha, Senha e segundo fator, ou Token de acesso), resultado (Sucesso ou Falha), o motivo de uma falha (usuário ou senha incorretos, código do segundo fator incorreto, bloqueado após várias falhas, o login demorou demais, token desconhecido, expirado ou revogado, conta desativada, a conta não é de analista), IP e navegador. Filtre por resultado; **Carregar mais** carrega os mais antigos. Eles são mantidos pelo mesmo tempo que os alertas (365 dias por padrão).

O estado do coletor, do disco e do banco de dados fica na Visão geral (seção 8).

### Canais: mensagens para você (Telegram)

Além de entregar todos os alertas ao SOC, o localSIEM pode enviar a você os mais importantes por um **canal**. Por enquanto, o canal é o **Telegram**.

**Geral** (`/admin/dashboard/channels/general/`):

- **Enviar mensagens pelos canais**: ativa ou desativa todos os canais de uma vez.
- **Severidade mínima**: os alertas desta severidade ou superior são enviados (padrão: Alta).
- **Idioma das mensagens**: qualquer um dos 15 idiomas da interface web (padrão en-US). A regra e a descrição do alerta ficam como o localSIEM as escreveu.
- Uma tabela com cada canal: o estado dele (Desativado, Não configurado, Funcionando ou Erro), as mensagens enviadas, a última e o último erro.

**Telegram** (`/admin/dashboard/channels/telegram/`):

1. No Telegram, abra o **@BotFather**, envie `/newbot` e siga os passos. Ele fornece o **token do bot** (`123456789:AA...`; o número antes dos dois-pontos é o ID do bot).
2. Abra o chat com o seu bot e toque em **Começar** (ou adicione o bot ao grupo, ou como administrador do canal, que vai receber as mensagens): um bot não pode escrever para quem não falou com ele antes.
3. Descubra o **ID do chat**: envie qualquer mensagem ao bot e abra `https://api.telegram.org/bot<token>/getUpdates` em um navegador; o ID é o número depois de `"chat":{"id":`. O ID de um grupo começa com `-` e o de um canal com `-100`; um canal ou grupo público também pode ser informado como `@username`.
4. Escreva o token e o ID do chat, marque **Enviar as mensagens pelo Telegram** e clique em **Salvar e enviar uma mensagem de teste**. Se o Telegram a recusar, o aviso diz o motivo (por exemplo `Unauthorized`: token incorreto; `Bad Request: chat not found`: ID do chat incorreto, ou ninguém tocou em Começar).

O token é guardado no servidor em `/opt/localsiem/config/telegram-bot-token` (modo 600) e nunca é mostrado inteiro; **Remover o token** o exclui e desativa o Telegram. O servidor precisa alcançar `https://api.telegram.org` (porta 443 de saída).

Cada mensagem informa a severidade, a regra, a descrição, o módulo, o número de eventos, a primeira e a última vez (UTC) e a pesquisa que os mostra. O localSIEM envia no máximo uma mensagem por segundo. Se o Telegram não responder, ele tenta novamente algumas vezes; se o Telegram recusar uma mensagem (token incorreto, chat desconhecido, bot bloqueado), ele a descarta e mostra o erro. As mensagens aguardando são perdidas se o localSIEM reiniciar: os canais são um aviso para você, e o SOC continua recebendo todos os alertas.

<a id="health"></a>
## 15. Avisos de saúde e o que fazer

Eles também vão para o SOC (regras `localSIEM health: …`), agrupados para que não se repitam:

| Aviso | Severidade | O que fazer |
|---|---|---|
| Log truncado, desaparecido ou substituído fora de uma rotação | alta | Alguém pode estar apagando rastros. Verifique quem teve acesso ao servidor naquele momento e os outros logs dele. |
| O ModSecurity não está mais carregado, ou o motor foi colocado em Off | alta | Se ninguém fez isso de propósito, a proteção foi desativada: verifique a configuração do Apache e as alterações recentes dela. |
| Fonte de log ilegível | média | Normalmente são permissões após uma rotação: execute novamente como root o comando da seção 2 (`manage.py setup-modules`) ou dê ao `localsiem` acesso de leitura (seção 3.7). Só um log que o localSIEM conseguia ler antes o gera: um que ele nunca conseguiu ler (um módulo recém-instalado, antes do comando da seção 2) só aparece no estado do módulo («Erro», uma fonte não pode ser lida). |
| Fonte de log em silêncio por muito tempo (24 h) | média | Verifique se o Apache ainda grava esse arquivo (alterações na configuração dos logs, disco cheio). |
| Falta o IP real do cliente | média | Quase todas as requisições vêm de um único endereço privado: o site está atrás de um proxy e o Apache registra o IP dele, então as regras por IP não funcionam para essas requisições. |
| Muitas linhas não analisadas (mais de 5 %) | baixa | O formato do log mudou: na página do módulo (Módulos › Instalados › Configurar), clique em «Descobrir novamente e executar o diagnóstico», para que o módulo leia o novo formato; o diagnóstico descreve o formato de cada log. |
| Pouco disco livre, ou retenção reduzida por falta de espaço | média | Libere espaço ou aumente o tamanho máximo em disco. Enquanto isso, o localSIEM armazena menos detalhes. |

<a id="retention"></a>
## 16. Retenção e disco

Os eventos são mantidos por 90 dias e os alertas por 365 dias. O banco de dados nunca cresce além do máximo dele (padrão: o menor valor entre 15 % do disco e 10 GB): os eventos mais antigos são excluídos primeiro, em pequenos lotes, e o espaço volta para o disco. Com pouco disco livre, o localSIEM deixa de armazenar os detalhes volumosos (cabeçalhos e corpos dos registros de auditoria); com quase nenhum, ele armazena só os eventos que fazem parte de um alerta, e avisa o SOC. Altere os valores com `--retention-days` e `--max-disk` (por exemplo `--max-disk 5G`) ou em Administração › Configurações.

<a id="cli"></a>
## 17. Linha de comando

Como root, `/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py`:

| Comando | Uso |
|---|---|
| `list-users` | Contas e a verificação em duas etapas delas |
| `create-user NAME --role admin\|analyst --credentials /root/webapp-credentials.txt` | Nova conta com uma senha gerada |
| `reset-password NAME --credentials /root/webapp-credentials.txt` | Nova senha (a alterar no próximo login) |
| `reset-mfa NAME` | Verificação em duas etapas configurada novamente no próximo login |
| `doctor` (`--json`) | Requisitos e fontes de cada módulo ativado e, para um módulo desativado que tem requisitos, o que ele precisa antes de poder ser ativado (execute-o como `localsiem`, seção 4) |
| `modules` | Módulos instalados: nome, versão, ativado, desativado ou não carregado, pasta, e abaixo de um módulo os requisitos que faltam ao servidor para ele; e os módulos que não podem ser carregados, com o motivo |
| `read-paths` | Pastas que os módulos instalados leem (o `setup-modules` e o instalador dão ao `localsiem` acesso de leitura a elas) |
| `soc-test` | Envia um heartbeat ao SOC |
| `setup-modules` | Como root, o comando que a interface web mostra depois de instalar um módulo, depois de uma atualização que altera os logs que o módulo lê, e com Reconfigurar: acesso de leitura para o `localsiem` às pastas dos módulos instalados (ACLs, também para as próximas rotações; o grupo `adm` no Debian), uma reinicialização do localSIEM e o diagnóstico como `localsiem`. Com `--no-restart` (o que o instalador usa), ele só dá o acesso de leitura. |

Os módulos são instalados, atualizados e desinstalados somente pela interface web (seção 13): não há comando para isso.

Serviços: o localSIEM funciona como dois serviços do usuário de sistema `localsiem`, o coletor (`localsiem`) e a interface web (`localsiem-web`). `systemctl status localsiem localsiem-web` os mostra e `systemctl restart localsiem localsiem-web` os reinicia (Debian), ou `rc-service localsiem status; rc-service localsiem-web status` e `rc-service localsiem restart; rc-service localsiem-web restart` (Alpine); reinicie os dois depois de copiar ou excluir um módulo manualmente em `/opt/localsiem/modules/` (a interface web faz isso sozinha quando instala, atualiza ou desinstala um). Logs: `journalctl -u localsiem -u localsiem-web` (Debian) ou `/opt/localsiem/log/` (Alpine); ao iniciar, o coletor registra a linha `Modules: ...` com cada módulo, a versão dele e se está ativado ou desativado, e `Module <name>: requirements missing: ...` para um módulo cujos requisitos faltam.

**Arquivos no servidor**

| Caminho | Conteúdo |
|---|---|
| `/opt/localsiem/webapp/` | Código do núcleo |
| `/opt/localsiem/modules/` | Módulos instalados, uma pasta para cada um (`apache2/`), instalados pela interface web a partir do `localSIEM-modules` |
| `/opt/localsiem/venv/` | Dependências do Python (separadas das do sistema) |
| `/opt/localsiem/config/` | Configurações, opções do instalador (`install.env`), token do SOC e segredos (modo 600) |
| `/opt/localsiem/db/` | Bancos de dados |
| `/opt/localsiem/certificates/` | Certificado da interface web |
| `/opt/localsiem/log/`, `/opt/localsiem/run/` | Logs (Alpine) e arquivos de execução |
| `/root/webapp-install.log`, `/root/webapp-credentials.txt` | Log do instalador e senhas que ele criou (modo 600) |
