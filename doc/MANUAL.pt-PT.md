# Manual de utilização do localSIEM

Este MANUAL também está disponível em:\
[de-DE](MANUAL.de-DE.md), [en-GB](MANUAL.en-GB.md), [en-US](MANUAL.md), [es-AR](MANUAL.es-AR.md), [es-ES](MANUAL.es-ES.md), [fr-FR](MANUAL.fr-FR.md), [he-IL](MANUAL.he-IL.md), [hi-IN](MANUAL.hi-IN.md), [it-IT](MANUAL.it-IT.md), [ja-JP](MANUAL.ja-JP.md), [ko-KR](MANUAL.ko-KR.md), [pt-BR](MANUAL.pt-BR.md), pt-PT, [ru-RU](MANUAL.ru-RU.md), [zh-CN](MANUAL.zh-CN.md)

[Instalação](README.pt-PT.md) · [Referência técnica](CODE.pt-PT.md)

## Índice

1. [O que faz o localSIEM](#what)
2. [Instalação](#installation)
3. [Requisitos do Apache e do ModSecurity](#requirements)
4. [O diagnóstico](#doctor)
5. [Ligação ao SOC](#soc)
6. [Início de sessão e contas](#signin)
7. [Os dois painéis](#dashboards)
8. [Visão geral](#overview)
9. [Pesquisa](#search)
10. [A ficha do pedido e os pivôs](#card)
11. [Vista em direto](#live)
12. [Alertas](#alerts)
13. [Módulos](#modules)
14. [Administração](#administration)
15. [Avisos de saúde e o que fazer](#health)
16. [Retenção e disco](#retention)
17. [Linha de comandos](#cli)

<a id="what"></a>
## 1. O que faz o localSIEM

O localSIEM vigia os serviços do servidor onde está instalado através de **módulos**, um por serviço. Só lê os registos desse servidor: não recebe registos de outras máquinas. O módulo **Apache + ModSecurity** vigia o site do Apache: para cada pedido junta três entradas, a linha do `access.log`, as linhas do `error.log` e a entrada do registo de auditoria do ModSecurity, usando o `UNIQUE_ID` do pedido. Tudo é guardado para poder ser pesquisado. Depois, o localSIEM decide o que tem de ir para o SOC.

O localSIEM funciona no mesmo servidor Debian ou Alpine que protege, ao lado do respetivo site, como dois serviços do utilizador de sistema `localsiem`. A sua própria interface web escuta na porta 10443: nunca usa as portas 80 nem 443 e nunca toca no site do servidor. Além do SOC (opcional, secção 5), pode enviar-lhe os alertas mais importantes pelo **Telegram** (secção 14) e dá ao analista do SOC uma **ferramenta de pesquisa**, um campo de pesquisa e um intervalo de tempo (secção 9). Nunca deixa sair do servidor palavras-passe, cookies, tokens nem corpos de pedidos, usa pouca memória (cerca de 100 MB em utilização normal e cerca de 200 MB nos picos) e nunca enche o disco (secção 16).

**Só vai para o SOC o que ainda ninguém resolveu.**

| Situação | Vai para o SOC? |
|---|---|
| O ModSecurity bloqueou o pedido nas fases 1–2 (antes de a aplicação o receber) | **Não.** Fica no localSIEM, pesquisável, e aparece como contagem no alerta seguinte desse IP. |
| O ModSecurity bloqueou a resposta nas fases 3–4 (a aplicação já tinha executado o pedido) | Sim |
| Correspondências de regras com o ModSecurity em `DetectionOnly` (nada é bloqueado) | Sim |
| Correspondências de regras abaixo do limiar de bloqueio | Sim, com gravidade `low` |
| Sinais das regras do localSIEM (força bruta, web shell, ficheiro sensível, enumeração, erro de base de dados) | Sim |
| Problemas de saúde e possível eliminação de vestígios | Sim |

**Gravidade do que vai para o SOC**

| Situação | Gravidade |
|---|---|
| Correspondências de regras não bloqueadas, resposta 3xx, 4xx ou 5xx | média |
| Correspondências de regras não bloqueadas, resposta 2xx | alta |
| Bloqueado nas fases 3–4 | alta |
| Sinais de sucesso: regra de fuga de dados ou de web shell (950–955) não bloqueada, erro SQL logo a seguir, POST com 2xx para um `.php` novo | crítica |
| Abaixo do limiar de bloqueio (muitas vezes falsos positivos da aplicação) | baixa (configurável em Definições) |

**Agrupamento.** Um alerta por módulo, vhost, IP, categoria e gravidade numa janela de 10 minutos. Um alerta crítico sai de imediato; os restantes esperam 60 segundos para reunir a rajada e saem com a contagem. Um scanner que envia milhares de pedidos produz poucos alertas, não milhares. Se a gravidade subir (por exemplo, o mesmo ataque passa a receber respostas 200), é outro alerta.

**O que nunca vai para o SOC:** os corpos dos pedidos ou das respostas, os cookies, os cabeçalhos `Authorization`, as palavras-passe ou os tokens — nem sequer mascarados — e o que já foi bloqueado nas fases 1–2 (só como contagem). O localSIEM mascara os valores sensíveis (`password`, `pass`, `pwd`, `passwd`, `token`, `secret`, `api_key`, `apikey`, `auth`, `session` e os cabeçalhos `Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, `Proxy-Authorization`) com `***` antes de guardar o que quer que seja.

**Módulos.** O núcleo do localSIEM (armazenamento, pesquisa, regras, agrupamento, envio para o SOC, saúde) é o mesmo para todos os serviços; cada módulo acrescenta o que é específico de um serviço. O módulo Apache + ModSecurity (`apache2`) vem do repositório `localSIEM-modules` (GitHub) e é instalado, atualizado e desinstalado apenas a partir da interface web, nunca pelo instalador do localSIEM; instalá-lo nunca instala o Apache nem o ModSecurity. Todos os módulos são instalados, atualizados e desinstalados da mesma forma, a partir da interface web. A secção 13 explica como instalá-los e atualizá-los, ver o respetivo estado, ativá-los e desativá-los e configurá-los.

<a id="installation"></a>
## 2. Instalação

A instalação tem dois passos: o núcleo do localSIEM e, depois, os respetivos módulos (o passo 2, mais abaixo). Execute como root, diretamente a partir do GitHub:

```bash
# Debian 13
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
# Alpine 3.24 (primeiro: apk add bash curl)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
```

A interface web do localSIEM escuta sempre na **porta 10443 com HTTPS**: o instalador verifica se a porta está livre e interrompe-se se outro serviço a estiver a usar. A ação e as opções vão depois de `bash -s --`. O instalador verifica o que precisa (Python 3.13 com `venv`, OpenSSL, os certificados das CA, as ferramentas de ACL, logrotate, curl, tar) e instala o que faltar. Executado assim, através de um pipe, transfere o ramo `main` de `https://github.com/PYMEHackers/localSIEM`; executado a partir de uma cópia do projeto (`bash deploy/install-update-reinstall-debian.sh --install`), instala essa cópia.

**A ação.** O instalador precisa sempre de uma ação; sem ela, interrompe-se e enumera-as:

| Ação | Utilização |
|---|---|
| `--install` | Instala o localSIEM num servidor que não o tem. Se encontrar algo do localSIEM (`/opt/localsiem`, os respetivos serviços ou o respetivo utilizador `localsiem`, também de uma instalação que falhou a meio), interrompe-se e indica `--update` e `--reinstall`. |
| `--update` | Atualiza o localSIEM instalado: mantém os respetivos dados, contas, definições, módulos e as opções indicadas anteriormente (mais abaixo). |
| `--reinstall [--yes]` | Elimina o localSIEM instalado com todos os respetivos dados, tal como `--uninstall` (mais abaixo), e volta a instalá-lo do zero, com novas palavras-passe. Primeiro pede-lhe que escreva `yes` (`--yes` não pede; é necessário quando não há terminal) e não elimina nada até ter transferido a nova cópia e verificado as opções. As opções da instalação anterior não são mantidas: indique-as novamente. |
| `--uninstall [--yes]` | Elimina o localSIEM e todos os respetivos dados do servidor (mais abaixo). Usa-se sozinha. |

`--update` e `--reinstall` interrompem-se se o localSIEM não estiver instalado: use `--install`.

Opções de `--install`, `--update` e `--reinstall`:

| Opção | Utilização |
|---|---|
| `--allow-from LIST` | IPs e CIDR autorizados a abrir a interface web, separados por vírgulas: o SOC e os seus administradores |
| `--soc-url URL` | Predefinição: `https://soc.pymehackers.com` |
| `--soc-token TOKEN` | Token de ingestão deste cliente no SOC. Opcional: sem SOC, o localSIEM funciona por si só (secção 5) |
| `--soc-ca-file PATH` | Só para um SOC com certificado privado (servidores de teste) |
| `--domain NAME` | Nome do servidor, para o certificado e o endereço do SIEM (predefinição: o respetivo nome de anfitrião) |
| `--certificate PATH --private-key PATH` | Certificado a usar. Sem estas opções, o localSIEM copia o certificado do Let's Encrypt de `--domain`, se existir (e volta a copiá-lo em cada renovação), ou cria um autoassinado. |
| `--retention-days N`, `--max-disk SIZE` | Retenção (secção 16) |
| `--enable-mfa`, `--disable-mfa` | Verificação em dois passos ativada (obrigatória para todas as contas) ou desativada. Sem elas, uma nova instalação tem-na desativada e uma atualização mantém o que foi escolhido em Administração › Definições (secção 14). |
| `--rotate-credentials` | Cria um novo segredo de assinatura JWT e escreve-o em `/root/webapp-credentials.txt` |
| `--ref REF` | Ramo ou etiqueta (tag) do localSIEM a transferir (predefinição: `main`) |
| `--source-url URL` | Arquivo (`.tar.gz`) do localSIEM a instalar em vez do arquivo do GitHub (um espelho) |
| `--modules-repository URL`, `--modules-ref REF` | Repositório (ou arquivo `.tar.gz`) e ramo ou etiqueta a partir dos quais a interface web instala e atualiza os módulos (secção 13). Predefinição: `https://github.com/PYMEHackers/localSIEM-modules`, ramo `main`. |

**Sempre a última versão.** O GitHub guarda os ficheiros de `raw.githubusercontent.com` em cache até 5 minutos após cada alteração, por isso os comandos acima leem o instalador através da API do GitHub, que não tem cache; depois, o instalador pergunta a essa API qual é o commit do ramo e transfere exatamente esse commit, e pede a todos os servidores pelo caminho que não respondam com uma cópia em cache. Sem token, o GitHub permite 60 pedidos à API por hora a partir de cada endereço IP: se recusar, o comando falha com `403` (aguarde e execute-o novamente); se só falhar a pergunta do instalador, o instalador avisa e transfere o ramo.

As opções ficam memorizadas em `/opt/localsiem/config/install.env`: `--update` sem opções mantém-nas. Para atualizar:

```bash
# Debian 13 (Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --update
```

O registo do instalador é `/root/webapp-install.log` e as palavras-passe que cria estão em `/root/webapp-credentials.txt` (ambos com modo 600). Mostra o progresso em passos numerados (`[3/12] Getting localSIEM`), com `✓` para o que está feito, `!` para os avisos, `✗` para as falhas e `·` para a informação, a cores num terminal (`NO_COLOR=1` ou `LOCALSIEM_COLOR=never` desativam as cores). A saída do apt-get ou do apk, do curl, do tar e do pip só vai para o registo; quando um deles falha, o ecrã mostra as últimas 20 linhas desse comando. O registo recebe as mesmas linhas, sem cores, com as horas no formato de armazenamento. No fim, executa o diagnóstico de cada módulo ativado (secção 4) e mostra um resumo: o endereço da interface web, que é também o endereço SIEM a indicar ao SOC, o ficheiro de credenciais, o registo e o estado do SOC, seguidos dos próximos passos. Se falhar, indica em que passo parou.

**Desinstalar.** `--uninstall` elimina o localSIEM do servidor: interrompe e remove os respetivos serviços e elimina `/opt/localsiem` (código, definições, a base de dados com todos os eventos e alertas, certificados e módulos), o utilizador `localsiem`, o acesso de leitura aos registos que o `setup-modules` deu, a configuração do Apache (`localsiem.conf`) que a opção `--configure-apache` das versões antigas do módulo do Apache (1.2.0 ou anteriores) acrescentava, com um configtest e um recarregamento do Apache, o ficheiro do logrotate, o hook do Let's Encrypt e as entradas do localSIEM em `/root/webapp-credentials.txt` (o ficheiro é eliminado quando não fica mais nada nele). Primeiro pede-lhe que escreva `yes` (`--yes` não pede; é necessário quando não há terminal). Se não restar nada do localSIEM no servidor, indica-o: «Nothing of localSIEM was found on this server.». Mantêm-se o registo do instalador, os pacotes que o instalador acrescentou, `mod_unique_id` (Debian) e os registos do Apache, incluindo o `localsiem_access.log` que esse ficheiro fazia o Apache escrever e o `modsec_audit.log`: o localSIEM nunca altera nem elimina um registo do Apache. Para desinstalar:

```bash
# Debian 13 (Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --uninstall
```

**Reinstalar.** Para começar do zero num só passo, `--reinstall` elimina tudo da mesma forma e volta a instalar o localSIEM (indique novamente as opções):

```bash
# Debian 13 (Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --reinstall --allow-from 203.0.113.10 --soc-token TOKEN
```

**2. Os módulos.** O instalador do localSIEM não instala **nenhum módulo**: deixa o localSIEM preparado para eles, e uma atualização mantém os que já estão instalados (e o acesso de leitura aos respetivos registos). Os módulos são instalados **apenas a partir da interface web**: Módulos › Instaláveis (secção 13), que lista os módulos do repositório `localSIEM-modules` que ainda não estão instalados; esse repositório não tem instalador próprio. O localSIEM transfere o módulo a partir dele, copia a respetiva pasta (`mod-<name>/` nesse repositório) para `/opt/localsiem/modules/<name>/` (as pastas `tests/` não são copiadas; um módulo instalado novamente recupera as definições que tinha) e reinicia o coletor. Os módulos também são atualizados e desinstalados a partir da interface web: **Atualizar**, quando o repositório tem uma versão mais recente, e **Desinstalar**, ambos em Módulos › Instalados (secção 13).

Ler os registos de um módulo exige root, por isso, depois de o módulo estar instalado, a interface web mostra numa caixa de diálogo o comando a executar como root no servidor:

```bash
/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py setup-modules
```

Dá ao utilizador `localsiem` acesso de leitura às pastas de registos que cada módulo instalado declara (`/var/log/apache2` para o módulo do Apache; secção 3.7), também aos ficheiros das próximas rotações, reinicia o localSIEM e executa o diagnóstico como `localsiem`. Pode ser executado novamente em qualquer momento. Esse acesso de leitura, que o localSIEM dá, é tudo o que o root faz pelos módulos.

**Instalar um módulo nunca instala o software que este vigia**, nem mais nada: um módulo funciona com o que o servidor já tem e nunca altera nada fora de `/opt/localsiem/`. Um módulo novo começa ativado ou desativado conforme o respetivo autor decidiu, exceto quando falta ao servidor o que o módulo precisa (para o módulo do Apache: o Apache e o ModSecurity 2): nesse caso é instalado **desativado**, a interface web indica o que falta e o respetivo interruptor fica bloqueado até que **Reconfigurar** o encontre (secção 13). O seu estado está em **Módulos › Instalados** (secção 13).

<a id="requirements"></a>
## 3. Requisitos do Apache e do ModSecurity

Estes são os requisitos do módulo Apache + ModSecurity. O próprio Apache e o ModSecurity 2 têm de estar instalados primeiro: sem eles, o módulo não pode ser ativado (secção 13). O localSIEM nunca altera por si só a configuração do Apache, nem os registos do Apache, o respetivo formato ou a forma como são escritos: o módulo lê os registos que o servidor já escreve e adapta-se a eles. O diagnóstico do módulo (secção 4) verifica cada requisito: para o ModSecurity com o respetivo CRS e `SecRuleEngine` (ponto 1), `mod_unique_id` (ponto 2) e o acesso de leitura (ponto 7), mostra o excerto ou o comando exato de cada um que falte, para que o aplique; os registos (pontos 3 a 6) apenas os descreve, sem propor alterá-los.

1. **ModSecurity 2 com OWASP CRS**, com `SecRuleEngine On` ou `DetectionOnly`. Ambos funcionam: com `DetectionOnly` nada é bloqueado, por isso todas as correspondências vão para o SOC.
2. **`mod_unique_id`**, de que o ModSecurity 2 precisa para funcionar de todo (sem ele, não inspeciona nada; o Alpine não o carrega por predefinição) e que junta as três entradas de cada pedido.
3. **Um registo de acesso**, tal como o Apache o escreve. Qualquer formato serve (`combined`, `vhost_combined`, `common`, ou qualquer `LogFormat` da configuração): cada linha é juntada ao respetivo pedido por IP do cliente, método, URI, código de estado e hora («correlação fraca»), e o vhost vem de `%v` ou, sem ele, do cabeçalho Host e da porta da entrada de auditoria. Quando o formato tem também milissegundos, `%v` e `%{UNIQUE_ID}e` (como as linhas `localsiem_combined` que alguns servidores já escrevem), cada linha é juntada ao respetivo pedido por `UNIQUE_ID`, e com `%D` o localSIEM obtém também a respetiva duração. Um registo de acesso cujo formato não tenha o IP do cliente, a hora, a linha do pedido ou o código de estado é lido tal como está, mas as respetivas linhas não podem ser juntadas aos pedidos: esses pedidos veem-se no registo de auditoria do ModSecurity. Um `CustomLog` cujo formato não tem nenhuma diretiva escreve o mesmo texto em todas as linhas e não é lido.
4. **`mod_remoteip`**, que decide que IP os registos guardam. Se o site estiver atrás de um proxy ou de um balanceador de carga e o Apache não o usar, os registos guardam o IP do proxy, tal como os alertas e as regras por IP: indicam-no o diagnóstico e o aviso de saúde «Falta o IP real do cliente» (secção 15).
5. **O registo de auditoria do ModSecurity**, tal como o ModSecurity o escreve: serial ou concorrente, JSON ou nativo, com as partes que tiver. Sem ele (`SecAuditEngine Off` ou sem `SecAuditLog`), o localSIEM decide apenas a partir do `error.log`, e a ficha do pedido não tem cabeçalhos nem lista de regras. Sem a parte `H`, não é possível ler nele a ação tomada. A parte `E` (o corpo da resposta), se for registada, nunca vai para o SOC; a parte `K` (o texto completo de cada regra executada) não é guardada. Com o tipo concorrente (um ficheiro por transação), o ModSecurity costuma criar os ficheiros com modo 600, e o localSIEM só os lê se o `localsiem` o puder fazer (ponto 7).
6. **Mascaramento na origem**: se o ModSecurity não mascarar o registo de auditoria no disco (as respetivas ações `sanitise`), esse ficheiro pode conter palavras-passe e cookies; o localSIEM mascara-os antes de os guardar, e nunca vão para o SOC.
7. **Acesso de leitura para o utilizador `localsiem`** aos registos. O comando para o root da secção 2 (`manage.py setup-modules`) trata disso para as pastas que os módulos instalados declaram (`/var/log/apache2` para o módulo do Apache), e o instalador do localSIEM volta a fazê-lo em cada atualização: no Debian, acrescenta o `localsiem` ao grupo `adm` e, tal como no Alpine, dá ao `localsiem` acesso de leitura a essas pastas através de ACL, incluindo uma ACL predefinida para que os ficheiros das próximas rotações também sejam legíveis. Os registos que acrescentar manualmente noutra pasta (secção 13) também precisam desse acesso, por exemplo `setfacl -m g:localsiem:rx /srv/logs`, `setfacl -d -m g:localsiem:r /srv/logs` e `setfacl -m g:localsiem:r /srv/logs/*.log`. O localSIEM apenas lê os registos: nunca escreve neles, nem os roda, trunca, move ou elimina. Quando começa a seguir um registo (no primeiro arranque, depois de instalar ou ativar um módulo, ou assim que o root lhe dá acesso de leitura), começa pelo fim: o que o registo já tinha é histórico e nunca gera alertas; só o registo de um vhost criado mais tarde é lido desde o início (quando tem até 5 MB).

<a id="doctor"></a>
## 4. O diagnóstico

Cada módulo tem o seu próprio diagnóstico. O diagnóstico do módulo do Apache verifica cada requisito da secção 3 e mostra o excerto ou o comando que corrige cada um que falte; os registos (formato, `mod_remoteip`, registo de auditoria, mascaramento) apenas os descreve, sem propor alterá-los, e lista as fontes encontradas (e as que não consegue ler, como os registos encaminhados por pipe). É executado no fim de cada instalação do localSIEM e do comando para o root da secção 2, aparece na página de cada módulo (**Módulos › Instalados › Configurar**, secção 13, com o botão «Descobrir novamente e executar o diagnóstico») e pode ser executado em qualquer momento para todos os módulos ativados:

```bash
runuser -u localsiem -- /opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor   # Debian
su -s /bin/sh localsiem -c "/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor"   # Alpine
```

`✓` está bem, `!` funciona com limitações, `✗` tem de ser corrigido, `·` só se aplica em algumas situações (a cores num terminal; onde não é possível escrever UTF-8, `+`, `!`, `x` e `-`). Um módulo que não pode ser carregado é mostrado primeiro como `✗ Module <name> not loaded: <reason>`. Um módulo desativado não tem diagnóstico: se tiver requisitos (secção 13), o diagnóstico mostra-os em vez disso, para que saiba se pode ser ativado.

<a id="soc"></a>
## 5. Ligação ao SOC

Ligar o localSIEM a um SOC é opcional. Sem SOC (sem token, ou com **Enviar alertas para o SOC** desativado), o localSIEM funciona por si só: guarda cada alerta no separador **Alertas** como «Não enviado» e nunca os envia mais tarde, nem sequer quando um SOC é configurado depois: a partir daí, só os novos alertas vão para ele. Os canais (Telegram) funcionam com ou sem SOC.

O administrador do SOC:

1. Cria um token de ingestão para o cliente (só é mostrado uma vez) e entrega-lho. Defina-o com `--soc-token` ou em **Administração › SOC**.
2. Define como **endereço SIEM** do cliente `https://<server>:<port of localSIEM>` (mostrado pelo instalador e em Administração › SOC). O analista responsável por um alerta usa essa ligação para vir investigar.
3. Entrega-lhe os IPs de saída do SOC: acrescente-os aos IPs permitidos (`--allow-from` ou Administração › Definições) e **abra a porta na firewall apenas a eles e aos seus administradores**.

O localSIEM envia um **sinal de vida** a cada 5 minutos. Se o SOC não receber alertas nem sinais de vida durante algum tempo (60 minutos por predefinição), avisa a sua equipa. Os alertas esperam numa fila persistente: um corte de rede ou um reinício não perde nenhum, e voltar a enviar um nunca o duplica no SOC. Se o SOC responder que o cliente esgotou todos os seus números de alerta, o localSIEM deixa de enviar, mantém a fila e mostra-o em Administração › SOC.

Cada alerta leva um nome de regra estável, uma descrição com a consulta exata para colar na pesquisa do localSIEM, e detalhes: vhost, IP do cliente, método, URI (mascarado), resposta, user agent, os dados do ModSecurity (motor, ação, fase, pontuação, limiar, regras, dados correspondidos), o grupo (contagem, primeira e última vez, `UNIQUE_ID` de exemplo) e o **contexto** do IP: pedidos e pedidos bloqueados na última hora, regras bloqueadas e a primeira vez que foi visto.

<a id="signin"></a>
## 6. Início de sessão e contas

Abra `https://<server>:10443/`: a página de início de sessão é apenas o formulário, com o logótipo, o nome de utilizador, a palavra-passe, **Continuar** e, por baixo, o idioma e o tema. As contas são criadas por um administrador; não há registo aberto. As palavras-passe têm pelo menos 8 caracteres. A **Verificação em dois passos** está desativada por predefinição; quando um administrador a ativa (Administração › Definições, secção 14), é obrigatória para todas as contas: no próximo início de sessão, leia o código QR com uma aplicação de autenticação (Google Authenticator, Microsoft Authenticator, Aegis, FreeOTP...; aparece como «PYMEHackers localSIEM») e introduza o respetivo código, e a partir daí cada início de sessão pede o código da aplicação. Após várias tentativas falhadas, o início de sessão fica bloqueado durante alguns minutos.

**Acesso direto com um token.** Um administrador pode entregar a um analista um URL de acesso, `https://<server>:10443/auth/login/auto?token=...` (Utilizadores › Tokens de acesso, secção 14). Abri-lo a partir de um endereço permitido inicia sessão de imediato, sem palavra-passe nem segundo fator, e abre a Visão geral do painel de utilizador; acrescente `&next=/user/dashboard/search/?q=...` para abrir outra página do site. Se o token não funcionar, a página de início de sessão indica porquê: token desconhecido, expirado ou revogado, ou a conta está desativada ou já não é de analista. Guarde o URL como uma palavra-passe: quem o tiver pode iniciar sessão com essa conta até que expire ou seja revogado. Cada início de sessão, com palavra-passe ou com token, e cada tentativa falhada fica registado (Inícios de sessão, secção 14).

Depois de iniciar sessão, chega à **Visão geral** do seu painel (secção 7). Uma ligação para uma pesquisa (por exemplo, a partir do SOC) abre a página de início de sessão, se necessário, e depois **a mesma pesquisa com os respetivos parâmetros**.

Funções: **analista** (trabalha no painel de utilizador: visão geral, pesquisa, vista em direto, alertas, o estado dos módulos e a conta) e **administrador** (trabalha no painel de administrador: o mesmo e ainda a configuração dos módulos e a administração). O idioma (de-DE, en-GB, en-US, es-AR, es-ES, fr-FR, he-IL, hi-IN, it-IT, ja-JP, ko-KR, pt-BR, pt-PT, ru-RU, zh-CN), o tema (sistema, claro ou escuro) e o relógio UTC estão na barra de título de todas as páginas dos painéis; a página de início de sessão tem-nos por baixo de **Continuar** e começa com os últimos escolhidos neste browser (sem escolha, os do browser e do sistema). O idioma mostrado quando prime **Continuar** passa a ser o idioma da sua conta: os painéis mantêm-no, em qualquer browser, até o alterar. As horas estão sempre em UTC no formato nativo `2026/10/29@13:59:59.723`. Os ficheiros que o localSIEM escreve (as exportações, `/root/webapp-credentials.txt`, o registo do instalador) e os alertas que envia ao SOC usam o formato de armazenamento `2026-10-29@13-59-59.723`, também em UTC.

<a id="dashboards"></a>
## 7. Os dois painéis

Cada função tem o seu próprio painel; o respetivo endereço indica em qual está. A barra lateral tem o logótipo no topo, os separadores (uma linha entre cada grupo) e, em baixo, **Terminar sessão**.

| | Painel de administrador | Painel de utilizador |
|---|---|---|
| Quem | Administradores | Analistas |
| Endereço | `/admin/dashboard/<tab>/` | `/user/dashboard/<tab>/` |
| Separadores | Visão geral, Pesquisa, Em direto, Alertas; Módulos (Instalados e Instaláveis), Utilizadores (Contas e Tokens de acesso), SOC, Canais (Geral e Telegram), Definições, Auditoria de pesquisas, Inícios de sessão; Conta | Visão geral, Pesquisa, Em direto, Alertas, Módulos (só o estado), Conta |

Cada separador tem o seu próprio endereço (por exemplo, `/admin/dashboard/logins/`), e `/admin/dashboard/` ou `/user/dashboard/` abrem a Visão geral. As secções de um separador também têm o seu: `/admin/dashboard/users/` abre `/admin/dashboard/users/accounts/` e os tokens de acesso estão em `/admin/dashboard/users/tokens/`; `/admin/dashboard/modules/` abre `/admin/dashboard/modules/installed/` e os módulos instaláveis estão em `/admin/dashboard/modules/installable/`. Um endereço do outro painel leva-o ao mesmo separador do seu: um administrador que abra uma ligação para `/user/dashboard/search/?q=...` (a ligação habitual do SOC) obtém a mesma pesquisa em `/admin/dashboard/search/`; um analista que abra um separador de administração obtém a Visão geral do painel de utilizador.

**O que os analistas veem.** Tudo o que é necessário para investigar: a visão geral, as pesquisas com as respetivas fichas de pedido, a vista em direto, os alertas e o estado de cada módulo (ativado ou desativado, a funcionar ou não, e os respetivos contadores). Não podem ativar nem desativar módulos, configurá-los, ver o respetivo diagnóstico ou regras, nem gerir utilizadores, tokens de acesso, a ligação ao SOC, as definições, a auditoria de pesquisas ou o registo dos inícios de sessão.

<a id="overview"></a>
## 8. Visão geral

O primeiro separador de ambos os painéis. Atualiza-se a cada 15 segundos e mostra:

- **Eventos (24 h)**, com quantos deles geraram um alerta; **Bloqueados (24 h)**, o que o ModSecurity já resolveu (guardado, sem alerta); **Alertas (24 h)**, com quantos estão à espera do SOC; e **Módulos a funcionar**, os módulos ativados que estão «Ativado e a funcionar» em relação aos ativados (a verde quando todos funcionam).
- **Atividade das últimas 24 horas**: eventos por hora; a parte azul de cada barra é o que o ModSecurity bloqueou. Clique numa hora para abrir a pesquisa dos respetivos eventos.
- **Estado dos módulos**: cada módulo com o respetivo estado (secção 13) e o que está a ler; «Ver os módulos» abre o separador Módulos.
- **Sistema**: se o coletor está em execução (e a respetiva versão), desde quando, o estado da ligação ao SOC, o último sinal de vida, os alertas à espera do SOC, o disco livre e o tamanho da base de dados face ao respetivo máximo.
- **Últimos alertas**: os seis mais recentes (gravidade, regra, IP, contagem, estado, última vez); «Ver todos os alertas» abre o separador Alertas.

<a id="search"></a>
## 9. Pesquisa

O separador **Pesquisa** tem um campo de pesquisa e um intervalo de tempo (últimos 15 minutos, hora, 24 horas, 7 dias, 30 dias, ou um intervalo personalizado no formato nativo).

| Sintaxe | Significado |
|---|---|
| `word` | Pesquisa de texto integral no texto original (mascarado), também descodificado de URL |
| `"exact phrase"` | Frase |
| `field:value` | Campo igual a um valor (os campos de texto ignoram maiúsculas e minúsculas) |
| `field:*part*` | Caracteres universais |
| `status:>=500`, `status:400..499`, `status:4xx` | Comparações e intervalos em campos numéricos |
| `a b` / `a AND b`, `a OR b`, `NOT a` / `-a`, `( )` | Operadores e parênteses |

| Grupo | Campos |
|---|---|
| Rede | `ip`, `vhost`, `host` |
| Pedido | `method`, `uri`, `path`, `query`, `status`, `bytes`, `duration` (microssegundos), `ua`, `referer` |
| Origem | `uid` (UNIQUE_ID), `module`, `source` (`access`/`error`/`audit`) |
| ModSecurity | `rule` (id do CRS, ou `localsiem:<rule>`), `category`, `phase`, `score`, `engine` (`on`/`detection-only`) |
| Alertas | `severity`, `action` (`blocked`/`none`), `alert` (código do SOC), `sent` (`yes`/`no`) |
| Qualidade | `parse` (`ok`/`partial`/`unparsed`) |

Exemplos:

- `ip:203.0.113.7` — tudo o que vem de um IP
- `rule:942100` — pedidos que corresponderam a essa regra do CRS
- `status:200 action:none category:sqli` — injeções de SQL que não foram bloqueadas e obtiveram um 200
- `uri:*wp-login*`
- `"union select"`
- `uid:ZTx1kH8AAQEAAB2gTkAAAAAB` — um pedido
- `alert:c00007a0001F` — os pedidos de um alerta do SOC
- `(category:sqli OR category:xss) sent:no -status:404`

Categorias: `sqli`, `xss`, `lfi`, `rfi`, `rce`, `php`, `java`, `fixation`, `generic`, `protocol`, `multipart`, `scanner`, `method`, `data-leakage`, `webshell`, e as das regras do localSIEM: `bruteforce`, `enumeration`, `sensitive-file`, `db-error`, além de `health-*`.

Um erro de sintaxe é mostrado por baixo do campo com a posição do erro. Uma pesquisa que demore mais do que o respetivo limite (5 s) pede-lhe que reduza o intervalo.

A página de resultados mostra:

- **O histograma** ao longo do tempo; a parte azul de cada barra é o que o ModSecurity bloqueou. Arraste sobre as barras (ou clique numa) para reduzir o intervalo.
- **Resumos** da consulta: IPs com mais pedidos, caminhos mais pedidos, códigos HTTP e regras mais frequentes. Clique num valor para o acrescentar à consulta.
- **A tabela de resultados** (HORA, FONTE, IP, MÉTODO, URI, CÓDIGO, AÇÃO, REGRAS, ALERTA), dos mais recentes para os mais antigos, com «Carregar mais».
- **Exportar** para CSV ou JSON (dados mascarados, até 10 000 linhas, horas no formato de armazenamento `2026-10-29@13-59-59.723`) e **Copiar ligação** (com horas absolutas). O formato da ligação é `/user/dashboard/search/?q=<query>&from=<native time>&to=<native time>` (`/admin/dashboard/search/...` quando é copiada por um administrador); uma ligação de qualquer um dos painéis funciona para ambas as funções.

Todas as pesquisas e exportações ficam registadas (quem, o quê, quando) e visíveis para os administradores: os registos contêm dados pessoais.

<a id="card"></a>
## 10. A ficha do pedido e os pivôs

Clique numa linha para abrir a ficha do pedido: hora, vhost, IP do cliente, método, URI, código, tamanho, duração, user agent, `UNIQUE_ID`, correlação, ação tomada, motor do ModSecurity, fase, pontuação e limiar, categoria, gravidade e alertas; e, para cada entrada, o respetivo conteúdo analisado: as regras correspondidas com a respetiva mensagem e dados, os cabeçalhos do pedido e o corpo mascarado, os cabeçalhos da resposta, as linhas de erro e a linha original. O módulo de cada entrada acrescenta o que sabe mostrar (o módulo do Apache reconstrói os cabeçalhos e o corpo a partir da entrada de auditoria).

Notas na ficha: um 403 sem qualquer vestígio do ModSecurity é marcado como **duvidoso** (não é contado como bloqueio); **correlação fraca** significa que a linha de acesso foi juntada ao respetivo pedido por IP do cliente, método, URI, código de estado e hora, porque o registo de acesso não tem `UNIQUE_ID`; apareceu um **erro de base de dados** para o pedido.

Pivôs: **Este IP** (toda a sua atividade), **±5 min** (a cronologia à volta do pedido), **Regra …** (cada regra correspondida), **Esta categoria**, **Este UNIQUE_ID**.

<a id="live"></a>
## 11. Vista em direto

O separador **Em direto** mostra os novos eventos assim que o coletor os guarda (após a janela de correlação de 5 segundos), com os mais recentes no topo. O filtro usa a sintaxe da pesquisa. **Pausa** interrompe as atualizações; ao retomar, continua a partir do evento mais recente.

<a id="alerts"></a>
## 12. Alertas

O separador **Alertas** lista os alertas gerados pelo localSIEM: código do SOC, gravidade, regra, IP, vhost, contagem, primeira e última vez, e estado:

| Estado | Significado |
|---|---|
| Em buffer | A reunir a rajada (60 s) antes de sair |
| Em fila | À espera do SOC (rede em baixo, SOC sem responder) |
| Enviado | Aceite pelo SOC; o respetivo código é mostrado |
| Rejeitado | O SOC recusou esse alerta; o resto da fila continua. Pode ser posto novamente em fila em Administração › SOC. |
| Não enviado | Não havia nenhum SOC configurado, ou o envio estava desativado: o alerta fica no localSIEM e nunca é enviado mais tarde (o SOC é opcional, secção 5) |

Clique numa linha para ver a descrição, os **pedidos do alerta** (até 50, os mais antigos primeiro, como na pesquisa: clique num para abrir a respetiva ficha do pedido, com o pedido, os cabeçalhos, as regras do ModSecurity e as linhas originais), a janela, o `external_id` e o alerta exato enviado ao SOC. **Pesquisar** abre a pesquisa do grupo. Enquanto um alerta está aberto, a lista não é atualizada.

<a id="modules"></a>
## 13. Módulos

No painel de administrador, o separador **Módulos** tem duas secções, cada uma com o seu próprio endereço: **Instalados** (`/admin/dashboard/modules/installed/`), que abre por predefinição (`/admin/dashboard/modules/` vai para lá), e **Instaláveis** (`/admin/dashboard/modules/installable/`), onde os módulos são instalados (mais abaixo). Os analistas só têm a lista dos módulos instalados, sem secções (`/user/dashboard/modules/`).

**Instalados** lista os módulos instalados, uma linha cada, a toda a largura, dispostos como o cabeçalho da página do módulo: no topo, o nome, o id e a versão e, por baixo, o respetivo **estado**, um resumo, os motivos do estado e, se estiver ativado, os respetivos contadores: fontes em leitura, linhas da última hora, últimos dados, eventos e pedidos bloqueados das últimas 24 horas e o resultado do diagnóstico. Os administradores veem também o interruptor à direita do nome e, no fundo da linha, os respetivos botões. A página atualiza-se a cada 10 segundos. Sem nenhum módulo instalado, indica «Instale módulos a partir do separador Instaláveis.» (aos analistas: «Não há módulos instalados. São instalados por um administrador em Módulos › Instaláveis.»).

| Estado | Significado |
|---|---|
| Ativado e a funcionar | Ativado, carregado pelo coletor e a ler as respetivas fontes. Os avisos do diagnóstico são listados como notas e não o alteram. |
| Ativado, com avisos | Ativado, mas sem fontes, com uma fonte que ainda não existe, ou instalado depois de o coletor arrancar (reinicie o serviço `localsiem`). |
| Erro | Não é carregado (o motivo é mostrado), o respetivo diagnóstico indica um erro, ou uma fonte não pode ser lida (permissões do utilizador `localsiem`, secção 3.7). |
| A aplicar a alteração… | Acabou de ser ativado ou desativado; o coletor está a aplicar a alteração (alguns segundos). |
| Desativado | Desativado: o localSIEM não lê os respetivos registos nem envia os respetivos alertas. O que já está guardado mantém-se. Com o motivo «Falta a este servidor o que o módulo precisa: …», foi instalado sem os respetivos requisitos e ainda não pode ser ativado (ver Requisitos e Reconfigurar, mais abaixo). |
| Desconhecido | O coletor não está em execução (serviço `localsiem`): ninguém está a ler nada. |

Os **analistas** só veem esta lista. Os **administradores** têm ainda, em cada linha:

- **O interruptor** de cada módulo, para o ativar ou desativar. Desativá-lo pede confirmação. A alteração aplica-se de imediato, sem reiniciar nada. Enquanto faltar ao servidor o que um módulo precisa, o respetivo interruptor fica bloqueado («Desativado: faltam requisitos»).
- **Configurar**, que abre a página do módulo (`/admin/dashboard/modules/installed/<name>/`; o endereço antigo `/admin/dashboard/modules/<name>/` leva-o até lá):
  - o cabeçalho com o estado, a pasta onde o módulo está instalado, o interruptor, «Voltar aos módulos instalados» (regressa a Instalados) e «Descobrir novamente e executar o diagnóstico»; para um módulo com requisitos, também o botão «Reconfigurar» e, enquanto o módulo estiver desativado ou faltar algum, os respetivos **Requisitos** (mais abaixo);
  - **Definições**: o formulário das definições próprias do módulo; «Guardar as definições» aplica-as de imediato;
  - **Fontes**: os registos que lê (tipo, caminho, vhost, linhas e linhas não analisadas da última hora, últimos dados, estado) e, por baixo, os registos que encontrou mas não lê, com o motivo;
  - **Diagnóstico**: as verificações dos requisitos, com o excerto ou o comando que corrige cada um que falte e um botão «Copiar» (os registos são apenas descritos);
  - **Regras**: cada regra do módulo com o respetivo interruptor («Ativa»), gravidade, limiar e janela (limiar e janela apenas para as regras de limiar e de sequência); «Guardar as regras» aplica-as de imediato.
- **Atualizar**, quando o repositório `localSIEM-modules` tem uma versão mais recente do módulo. Sempre que abre Instalados, o localSIEM consulta o repositório: entretanto, indica «A consultar o repositório à procura de versões mais recentes…» e, se a consulta falhar, «Não foi possível consultar o repositório à procura de versões mais recentes: <error>», e a lista funciona como habitualmente. Para que o repositório não seja transferido em cada visita, o browser reutiliza a resposta durante 10 minutos; «Consultar o repositório», em Instaláveis, transfere-o sempre de novo, e instalar, atualizar ou desinstalar um módulo descarta a resposta guardada. A atualização a cada 10 segundos nunca o transfere. Um módulo com uma versão mais recente mostra, na respetiva linha, o aviso «O repositório tem a versão X (a instalada é a Y).» com o botão **Atualizar**. Se essa versão precisar de um localSIEM mais recente, o aviso não tem botão e indica-o: «O repositório tem a versão X, mas esta precisa do localSIEM Z ou mais recente: atualize o localSIEM para a instalar.» **Atualizar** pede confirmação («Atualizar o módulo»): o localSIEM transfere a nova versão do repositório, substitui com ela a instalada e reinicia o coletor; as definições mantêm-se, e o módulo continua ativado ou desativado como estava. Enquanto decorre, o botão indica «A atualizar…»; no fim, uma mensagem indica «<módulo> atualizado para a versão X.» Uma caixa de diálogo, «<módulo> atualizado», só abre quando há mais alguma coisa a fazer: se a nova versão ler outros registos, mostra o comando para o root (`manage.py setup-modules`, secção 2, com «Copiar»); se o coletor não respondeu, pede-lhe que reinicie o serviço `localsiem`.
- **Desinstalar**, na linha de cada módulo instalado (também de um que não é carregado) e na respetiva página. Depois de confirmar, o localSIEM elimina `/opt/localsiem/modules/<name>/` e reinicia o coletor sem ele: deixa de ler os respetivos registos e de enviar os respetivos alertas. Os eventos e alertas já guardados continuam a poder ser pesquisados, e as respetivas definições (e as alterações das regras) ficam em `settings.json`, pelo que regressam se o voltar a instalar. O acesso de leitura que o root deu ao `localsiem` aos respetivos registos não é retirado; se nenhum outro módulo ler essa pasta, pode removê-lo manualmente, por exemplo `setfacl -R -x g:localsiem /var/log/apache2` e `setfacl -d -x g:localsiem /var/log/apache2`.

**Instaláveis** (só administradores) tem o cartão «Módulos instaláveis»: os módulos do repositório `localSIEM-modules` (por predefinição `https://github.com/PYMEHackers/localSIEM-modules`, ramo `main`; as opções do instalador `--modules-repository` e `--modules-ref` alteram-no) que ainda não estão instalados neste servidor. «Consultar o repositório» transfere-o e lista esses módulos, cada um com o nome, id, versão e resumo e o respetivo botão ou nota:

| Botão ou nota | Significado |
|---|---|
| Requisitos | Mostra o que o módulo precisa no servidor e os comandos que o instalam (mais abaixo) |
| Instalar | Instala o módulo |
| Precisa do localSIEM X ou mais recente | Não pode ser instalado: atualize primeiro o localSIEM |
| O módulo do repositório não é válido | Não pode ser instalado |

**Requisitos** abre a caixa de diálogo «<módulo>: requisitos», com o que o módulo precisa no servidor e os comandos que o instalam, declarados pelo próprio módulo (`install_requirements` do respetivo `module.json`). Instalar um módulo nunca instala o software que este vigia, por isso execute-os no servidor **antes** de instalar o módulo. A caixa de diálogo mostra os comandos para o sistema deste servidor («Este servidor: Debian GNU/Linux 13 (trixie)») duas vezes, cada uma com «Copiar»: **Como root** e **Com sudo** (os mesmos comandos com `sudo` à frente), para que os possa colar num terminal do servidor como root ou como um utilizador autorizado a utilizar o sudo. As notas do módulo vêm primeiro (por exemplo, que o Alpine não tem pacote do ModSecurity 2). Se o módulo não declarar comandos para o sistema deste servidor, a caixa de diálogo mostra os de todos os sistemas que declara (Debian e Alpine); se não declarar nenhum, indica «Este módulo não declara nada a instalar no servidor.». O localSIEM nunca executa estes comandos.

Se todos os módulos do repositório já estiverem instalados, indica-o («Todos os módulos do repositório já estão instalados.»). Os módulos já instalados nunca aparecem nesta lista: são atualizados em Instalados (**Atualizar**, mais acima). A interface web não reinstala um módulo nem instala uma versão mais antiga do mesmo: para reinstalar um, desinstale-o e volte a instalá-lo aqui (as definições mantêm-se).

Esta lista é a única forma de instalar módulos. O localSIEM transfere o módulo, verifica o respetivo `module.json`, copia a respetiva pasta (`mod-<name>/` no repositório) para `/opt/localsiem/modules/<name>/` (sem a pasta `tests/`; um módulo instalado novamente recupera as definições que tinha) e reinicia o coletor, que o carrega dentro de alguns segundos. O módulo sai da lista e uma caixa de diálogo, «<módulo> instalado», indica o que vem a seguir:

- Permitir que o `localsiem` leia os registos do módulo exige root, por isso a caixa de diálogo mostra **o comando a executar como root** no servidor, com um botão «Copiar»: `manage.py setup-modules` (secção 2), que dá o acesso de leitura e reinicia o localSIEM. Até o comando ser executado, o módulo pode mostrar «Erro» porque os respetivos registos não podem ser lidos.
- Se, na primeira instalação, faltar ao servidor o que o módulo precisa, o módulo é instalado desativado e a caixa de diálogo lista o que falta em vez do comando, com a sugestão de abrir o módulo em Instalados (**Configurar**) e premir **Reconfigurar** quando estiver presente (mais abaixo).

A caixa de diálogo tem dois botões: «Fechar» e «Ver os módulos instalados», que abre Instalados. O servidor precisa de chegar ao GitHub (HTTPS) para esta lista e para a consulta de versões mais recentes em Instalados.

**Requisitos e Reconfigurar.** Instalar um módulo nunca instala o software que este vigia. Um módulo pode declarar o que o servidor tem de ter antes de poder ser ativado: o módulo do Apache precisa do Apache (a respetiva configuração: `apache2.conf`, `httpd.conf` ou o ficheiro da definição **Ficheiro de configuração do Apache**) e do ModSecurity 2 carregado (`mod_security2`; o ModSecurity 3 não conta). Se faltarem na primeira instalação, o módulo é instalado **desativado** («Desativado», com o motivo «Falta a este servidor o que o módulo precisa: …») e o respetivo interruptor fica **bloqueado**. A respetiva página lista os requisitos como o diagnóstico (título, detalhe e o comando que instala o que falta, com «Copiar»), também enquanto está desativado. Depois de instalar o que falta (e, se o Apache estiver num local não padrão, definir **Ficheiro de configuração do Apache** e guardar as definições), prima **Reconfigurar**: o localSIEM procura-o novamente com as definições guardadas.

- Se encontrar tudo, desbloqueia o interruptor mas não ativa o módulo: ative-o com o respetivo interruptor. Mostra também o comando para o root da secção 2: execute-o, porque os registos criados depois de o módulo ser instalado (`/var/log/apache2`) só podem ser lidos com o acesso de leitura que o root dá.
- Se ainda faltar algo, os requisitos voltam a mostrá-lo.
- Se o módulo já estiver ativado, Reconfigurar também descobre novamente as respetivas fontes e executa o diagnóstico.

Um módulo ativado que mais tarde perca os requisitos (alguém desinstala o ModSecurity) continua ativado: o respetivo diagnóstico e o aviso de saúde «O ModSecurity já não está carregado» (secção 15) indicam-no, e desativá-lo silenciaria precisamente esse aviso. O coletor verifica os requisitos quando arranca e quando as respetivas definições mudam, nunca periodicamente; `manage.py modules` e `manage.py doctor` também os mostram (secção 17).

**Desativar e ativar o módulo do Apache.** Em **Módulos › Instalados**, use o interruptor de «Apache + ModSecurity» e confirme. Enquanto está desativado, o localSIEM não lê os registos do Apache, não executa o respetivo diagnóstico nem as respetivas regras e não envia alertas dele; os eventos já guardados continuam a poder ser pesquisados. Volte a ativar o interruptor para retomar (só é possível enquanto o Apache e o ModSecurity estiverem presentes): o coletor continua a partir da posição onde parou em cada registo (seguindo as rotações feitas entretanto), por isso também lê o que o Apache escreveu enquanto o módulo estava desativado e envia os alertas que isso justificar.

**Definições do módulo do Apache** (Módulos › Instalados › Apache + ModSecurity › Configurar):

| Definição | Utilização |
|---|---|
| Só as fontes abaixo | Não descobrir os registos a partir da configuração do Apache: ler apenas as fontes adicionadas manualmente |
| Fontes adicionadas manualmente | Registos a ler além dos descobertos (ver mais abaixo) |
| Ficheiro de configuração do Apache | Vazio: encontrado automaticamente (`/etc/apache2/apache2.conf` no Debian, `/etc/apache2/httpd.conf` no Alpine). Reconfigurar também procura o Apache aí |
| Intervalo de descoberta (segundos) | Com que frequência a configuração do Apache é lida novamente para encontrar novos vhosts e registos (predefinição: 3600) |
| Limiar de bloqueio do ModSecurity | 0: lido da configuração do CRS (`tx.inbound_anomaly_score_threshold`), 5 se não estiver lá |
| Dias de aprendizagem para novos ficheiros PHP | Durante os primeiros dias, um ficheiro PHP nunca visto antes não é indicado como novo (regra `apache-webshell`; predefinição: 3) |

**Adicionar um registo manualmente.** Em **Fontes adicionadas manualmente**, prima «Adicionar fonte» e preencha **Tipo** (access.log, error.log ou Registo de auditoria do ModSecurity), **Caminho** (absoluto) e, se necessário, **Vhost**, **LogFormat** (para um registo de acesso num formato próprio), **Tipo de registo de auditoria** (Serial ou Concorrente) e **Pasta de armazenamento da auditoria** (para um registo de auditoria concorrente). «Remover» elimina uma fonte. Prima «Guardar as definições»: o coletor descobre novamente as fontes de imediato e o novo registo aparece em **Fontes**. Se aparecer como ilegível, dê ao `localsiem` acesso de leitura à respetiva pasta (secção 3.7).

**Do módulo `apache` para `apache2`.** Até ao localSIEM 2.1, o módulo do Apache chamava-se `apache`; agora é `apache2` (pasta `mod-apache2/` no repositório, instalado em `/opt/localsiem/modules/apache2/`, página `/admin/dashboard/modules/installed/apache2/`). Num servidor que tinha `apache`, instalar `apache2` deixa ambos carregados: o antigo fica com os registos do Apache (ambos encontram as mesmas fontes), `apache2` não mostra fontes até o antigo ser desinstalado, e as definições de `apache` não passam sozinhas. Para migrar:

1. Anote as definições que alterou na página do módulo `apache` (Configurar): fontes adicionadas manualmente, ficheiro de configuração do Apache, intervalo de descoberta, limiar de bloqueio, dias de aprendizagem.
2. Instale `apache2` em Módulos › Instaláveis.
3. Desinstale o módulo `apache`: **Desinstalar**, na respetiva linha em Módulos › Instalados ou na respetiva página. O coletor reinicia e `apache2` passa a ler os registos do Apache a partir daí.
4. Abra a página de `apache2`, introduza novamente essas definições e guarde-as. (Em alternativa, como root, pode copiar em `/opt/localsiem/config/settings.json`, dentro de `"modules"`, o que está em `"apache"` para `"apache2"`, e depois reiniciar o localSIEM.)

As regras mantêm os respetivos ids (`apache-bruteforce`…) e as alterações, e as posições lidas em cada registo e a memória dos avisos de saúde mantêm-se: `apache2` continua onde `apache` parou, sem ler nada duas vezes. Os eventos guardados pelo módulo `apache` continuam pesquisáveis (`module:apache`).

<a id="administration"></a>
## 14. Administração

Estes separadores só existem no painel de administrador:

- **Módulos** (secção 13), em duas secções: **Instalados** (`/admin/dashboard/modules/installed/`), a lista com o interruptor de cada módulo, **Configurar** (requisitos e Reconfigurar, definições, fontes, diagnóstico e regras do módulo), **Atualizar** (quando o repositório tem uma versão mais recente) e **Desinstalar**; e **Instaláveis** (`/admin/dashboard/modules/installable/`), os módulos do repositório ainda não instalados, com **Requisitos** e **Instalar**. Os módulos são instalados, atualizados e desinstalados apenas aí.
- **Utilizadores › Contas** (`/admin/dashboard/users/accounts/`): criar contas (é gerada uma palavra-passe, mostrada uma única vez; tem de ser alterada no primeiro início de sessão), repor a palavra-passe ou a verificação em dois passos, ativar ou desativar, alterar a função, eliminar. Há sempre pelo menos um administrador ativo.
- **Utilizadores › Tokens de acesso** (`/admin/dashboard/users/tokens/`): **Criar token** para uma conta de analista ativa (os administradores iniciam sempre sessão com a palavra-passe, e com o segundo fator quando a verificação em dois passos está ativada), com uma etiqueta opcional e uma validade de 7, 30, 90 (predefinição), 180 ou 365 dias. O URL de acesso, `https://<server>:10443/auth/login/auto?token=...`, é mostrado **só uma vez**, com um botão «Copiar»: entregue-o ao analista (secção 6). A lista mostra a conta e a etiqueta de cada token, os últimos 4 caracteres, o estado (Ativo, Expirado, Revogado, ou Inutilizável quando a conta está desativada ou já não é de analista), quando e por quem foi criado, quando expira e a última utilização (hora e IP). **Revogar** anula-o de imediato; as sessões que já abriu terminam quando expirarem. Uma sessão aberta com um token não pede o segundo fator nem a alteração da palavra-passe. As tentativas falhadas contam para o bloqueio temporário do início de sessão.
- **SOC**: URL, token (nunca mostrado por inteiro), ficheiro de CA opcional, **Testar a ligação** (envia um sinal de vida), estado do envio, último sinal de vida, último erro, fila (em espera, enviados, rejeitados) e **Enviar a fila agora**. Também o endereço SIEM a indicar ao SOC. O SOC é opcional (secção 5).
- **Canais** (`/admin/dashboard/channels/`), em duas secções, **Geral** (abre por predefinição) e **Telegram**: as mensagens que o localSIEM lhe envia, além dos alertas que entrega ao SOC (mais abaixo).
- **Definições**: retenção, disco máximo, IPs permitidos (o seu próprio endereço tem de estar na lista), verificação em dois passos (desativada por predefinição; ativá-la torna-a obrigatória para todas as contas e termina de imediato a sessão das contas que ainda não a configuraram, incluindo a sua, que a configuram no próximo início de sessão; desativá-la mantém as aplicações de autenticação já configuradas para quando voltar a ser ativada), limite de tempo da pesquisa, limite de exportação, janela e buffer de agrupamento, janela de correlação e gravidade abaixo do limiar. As alterações aplicam-se de imediato. As regras já não estão aqui: são configuradas em cada módulo (Módulos › Instalados › Configurar).
- **Auditoria de pesquisas**: quem pesquisou o quê e quando.
- **Inícios de sessão** (`/admin/dashboard/logins/`): cada início de sessão no localSIEM e cada tentativa falhada, dos mais recentes para os mais antigos: hora, conta, método (Palavra-passe, Palavra-passe e segundo fator, ou Token de acesso), resultado (Sessão iniciada ou Falhado), o motivo de uma falha (nome de utilizador ou palavra-passe incorretos, código do segundo fator incorreto, bloqueado após várias falhas, o início de sessão demorou demasiado, token desconhecido, expirado ou revogado, conta desativada, a conta não é de analista), IP e browser. Filtre por resultado; **Carregar mais** carrega os mais antigos. São mantidos tanto tempo quanto os alertas (365 dias por predefinição).

O estado do coletor, do disco e da base de dados está na Visão geral (secção 8).

### Canais: mensagens para si (Telegram)

Além de entregar todos os alertas ao SOC, o localSIEM pode enviar-lhe os mais importantes através de um **canal**. Por agora, o canal é o **Telegram**.

**Geral** (`/admin/dashboard/channels/general/`):

- **Enviar mensagens pelos canais**: ativa ou desativa todos os canais de uma só vez.
- **Gravidade mínima**: são enviados os alertas desta gravidade ou superior (predefinição: Alta).
- **Idioma das mensagens**: qualquer um dos 15 idiomas da interface web (predefinição: en-US). A regra e a descrição do alerta ficam como o localSIEM as escreveu.
- Uma tabela com cada canal: o respetivo estado (Desativado, Não configurado, A funcionar ou Erro), as mensagens enviadas, a última e o último erro.

**Telegram** (`/admin/dashboard/channels/telegram/`):

1. No Telegram, abra o **@BotFather**, envie `/newbot` e siga os passos indicados. Este fornece-lhe o **token do bot** (`123456789:AA...`; o número antes dos dois pontos é o id do bot).
2. Abra o chat com o seu bot e prima **Iniciar** (ou adicione o bot ao grupo, ou como administrador do canal, que vai receber as mensagens): um bot não pode escrever a quem não lhe tenha falado primeiro.
3. Descubra o **id do chat**: envie uma mensagem qualquer ao bot e abra `https://api.telegram.org/bot<token>/getUpdates` num browser; o id é o número que vem depois de `"chat":{"id":`. O id de um grupo começa por `-` e o de um canal por `-100`; um canal ou grupo público também pode ser indicado como `@username`.
4. Escreva o token e o id do chat, marque **Enviar as mensagens pelo Telegram** e prima **Guardar e enviar uma mensagem de teste**. Se o Telegram a recusar, o aviso indica porquê (por exemplo, `Unauthorized`: token errado; `Bad Request: chat not found`: id do chat errado, ou ninguém premiu Iniciar).

O token é guardado no servidor em `/opt/localsiem/config/telegram-bot-token` (modo 600) e nunca é mostrado por inteiro; **Remover o token** elimina-o e desativa o Telegram. O servidor precisa de chegar a `https://api.telegram.org` (porta de saída 443).

Cada mensagem indica a gravidade, a regra, a descrição, o módulo, o número de eventos, a primeira e a última vez (UTC) e a pesquisa que os mostra. O localSIEM envia no máximo uma mensagem por segundo. Se o Telegram não responder, tenta novamente algumas vezes; se o Telegram recusar uma mensagem (token errado, chat desconhecido, bot bloqueado), descarta-a e mostra o erro. As mensagens em espera perdem-se se o localSIEM reiniciar: os canais são um aviso para si, e o SOC continua a receber todos os alertas.

<a id="health"></a>
## 15. Avisos de saúde e o que fazer

Estes também vão para o SOC (regras `localSIEM health: …`), agrupados para não se repetirem:

| Aviso | Gravidade | O que fazer |
|---|---|---|
| Registo truncado, desaparecido ou substituído fora de uma rotação | alta | Alguém pode estar a apagar vestígios. Verifique quem teve acesso ao servidor nesse momento e os outros registos do servidor. |
| O ModSecurity já não está carregado, ou o motor foi posto em Off | alta | Se ninguém o fez de propósito, a proteção foi desativada: verifique a configuração do Apache e as respetivas alterações recentes. |
| Fonte de registo ilegível | média | Normalmente, permissões após uma rotação: execute novamente como root o comando da secção 2 (`manage.py setup-modules`) ou dê ao `localsiem` acesso de leitura (secção 3.7). Só um registo que o localSIEM conseguia ler antes o gera: um que nunca conseguiu ler (um módulo acabado de instalar, antes do comando da secção 2) só aparece no estado do módulo («Erro», uma fonte não pode ser lida). |
| Fonte de registo silenciosa durante muito tempo (24 h) | média | Verifique se o Apache continua a escrever esse ficheiro (alterações na configuração dos registos, disco cheio). |
| Falta o IP real do cliente | média | Quase todos os pedidos vêm de um único endereço privado: o site está atrás de um proxy e o Apache regista o IP deste, por isso as regras por IP não funcionam para esses pedidos. |
| Muitas linhas não analisadas (mais de 5 %) | baixa | O formato do registo mudou: na página do módulo (Módulos › Instalados › Configurar), prima «Descobrir novamente e executar o diagnóstico», para que o módulo leia o novo formato; o diagnóstico descreve o formato de cada registo. |
| Pouco disco livre, ou retenção reduzida por falta de espaço | média | Liberte espaço ou aumente o tamanho máximo em disco. Entretanto, o localSIEM guarda menos detalhe. |

<a id="retention"></a>
## 16. Retenção e disco

Os eventos são mantidos durante 90 dias e os alertas durante 365 dias. A base de dados nunca cresce para além do respetivo máximo (predefinição: o menor entre 15 % do disco e 10 GB): os eventos mais antigos são eliminados primeiro, em pequenos lotes, e o espaço regressa ao disco. Com pouco disco livre, o localSIEM deixa de guardar os detalhes volumosos (cabeçalhos e corpos das entradas de auditoria); quase sem nenhum, guarda apenas os eventos que fazem parte de um alerta, e avisa o SOC. Altere os valores com `--retention-days` e `--max-disk` (por exemplo, `--max-disk 5G`) ou em Administração › Definições.

<a id="cli"></a>
## 17. Linha de comandos

Como root, `/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py`:

| Comando | Utilização |
|---|---|
| `list-users` | Contas e respetiva verificação em dois passos |
| `create-user NAME --role admin\|analyst --credentials /root/webapp-credentials.txt` | Nova conta com uma palavra-passe gerada |
| `reset-password NAME --credentials /root/webapp-credentials.txt` | Nova palavra-passe (a alterar no próximo início de sessão) |
| `reset-mfa NAME` | Verificação em dois passos configurada novamente no próximo início de sessão |
| `doctor` (`--json`) | Requisitos e fontes de cada módulo ativado e, para um módulo desativado com requisitos, o que precisa antes de poder ser ativado (execute-o como `localsiem`, secção 4) |
| `modules` | Módulos instalados: nome, versão, ativado, desativado ou não carregado, pasta e, por baixo de um módulo, os requisitos que faltam ao servidor para ele; e os módulos que não podem ser carregados, com o motivo |
| `read-paths` | Pastas que os módulos instalados leem (`setup-modules` e o instalador dão ao `localsiem` acesso de leitura a elas) |
| `soc-test` | Envia um sinal de vida ao SOC |
| `setup-modules` | Como root, o comando que a interface web mostra depois de instalar um módulo, depois de uma atualização que altera os registos que o módulo lê, e com Reconfigurar: acesso de leitura para o `localsiem` às pastas dos módulos instalados (ACL, também para as próximas rotações; o grupo `adm` no Debian), um reinício do localSIEM e o diagnóstico como `localsiem`. Com `--no-restart` (o que o instalador usa) apenas dá o acesso de leitura. |

Os módulos são instalados, atualizados e desinstalados apenas a partir da interface web (secção 13): não há nenhum comando para isso.

Serviços: o localSIEM funciona como dois serviços do utilizador de sistema `localsiem`, o coletor (`localsiem`) e a interface web (`localsiem-web`). `systemctl status localsiem localsiem-web` mostra-os e `systemctl restart localsiem localsiem-web` reinicia-os (Debian), ou `rc-service localsiem status; rc-service localsiem-web status` e `rc-service localsiem restart; rc-service localsiem-web restart` (Alpine); reinicie ambos depois de copiar ou eliminar manualmente um módulo em `/opt/localsiem/modules/` (a interface web fá-lo por si só quando instala, atualiza ou desinstala um). Registos: `journalctl -u localsiem -u localsiem-web` (Debian) ou `/opt/localsiem/log/` (Alpine); no arranque, o coletor regista a linha `Modules: ...` com cada módulo, a respetiva versão e se está ativado ou desativado, e `Module <name>: requirements missing: ...` para um módulo a que faltam requisitos.

**Ficheiros no servidor**

| Caminho | Conteúdo |
|---|---|
| `/opt/localsiem/webapp/` | Código do núcleo |
| `/opt/localsiem/modules/` | Módulos instalados, uma pasta cada (`apache2/`), instalados pela interface web a partir de `localSIEM-modules` |
| `/opt/localsiem/venv/` | Dependências de Python (separadas das do sistema) |
| `/opt/localsiem/config/` | Definições, opções do instalador (`install.env`), token do SOC e segredos (modo 600) |
| `/opt/localsiem/db/` | Bases de dados |
| `/opt/localsiem/certificates/` | Certificado da interface web |
| `/opt/localsiem/log/`, `/opt/localsiem/run/` | Registos (Alpine) e ficheiros de execução |
| `/root/webapp-install.log`, `/root/webapp-credentials.txt` | Registo do instalador e palavras-passe que criou (modo 600) |
