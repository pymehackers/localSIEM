# Manuale d'uso di localSIEM

Questo MANUALE è disponibile anche in:\
[de-DE](MANUAL.de-DE.md), [en-GB](MANUAL.en-GB.md), [en-US](MANUAL.md), [es-AR](MANUAL.es-AR.md), [es-ES](MANUAL.es-ES.md), [fr-FR](MANUAL.fr-FR.md), [he-IL](MANUAL.he-IL.md), [hi-IN](MANUAL.hi-IN.md), it-IT, [ja-JP](MANUAL.ja-JP.md), [ko-KR](MANUAL.ko-KR.md), [pt-BR](MANUAL.pt-BR.md), [pt-PT](MANUAL.pt-PT.md), [ru-RU](MANUAL.ru-RU.md), [zh-CN](MANUAL.zh-CN.md)

[Installazione](README.it-IT.md) · [Riferimento tecnico](CODE.it-IT.md)

## Indice

1. [Cosa fa localSIEM](#what)
2. [Installazione](#installation)
3. [Requisiti di Apache e ModSecurity](#requirements)
4. [La diagnostica](#doctor)
5. [Connessione con il SOC](#soc)
6. [Accesso e account](#signin)
7. [Le due dashboard](#dashboards)
8. [Panoramica](#overview)
9. [Ricerca](#search)
10. [La scheda della richiesta e i pivot](#card)
11. [Vista in diretta](#live)
12. [Avvisi](#alerts)
13. [Moduli](#modules)
14. [Amministrazione](#administration)
15. [Avvertenze di salute e cosa fare](#health)
16. [Conservazione e disco](#retention)
17. [Riga di comando](#cli)

<a id="what"></a>
## 1. Cosa fa localSIEM

localSIEM sorveglia i servizi del server su cui è installato tramite **moduli**, uno per servizio. Legge solo i log di quel server: non riceve log da altre macchine. Il modulo **Apache + ModSecurity** sorveglia il web di Apache: per ogni richiesta unisce tre record, la riga di `access.log`, le righe di `error.log` e il record del log di audit di ModSecurity, usando lo `UNIQUE_ID` della richiesta. Tutto viene salvato per poterlo cercare. Poi localSIEM decide cosa deve andare al SOC.

localSIEM funziona sullo stesso server Debian o Alpine che protegge, accanto al suo web, come due servizi dell'utente di sistema `localsiem`. La sua interfaccia web è in ascolto sulla porta 10443: non usa mai le porte 80 o 443 e non tocca mai il web del server. Oltre al SOC (facoltativo, sezione 5), può inviarti gli avvisi più importanti tramite **Telegram** (sezione 14) e offre all'analista del SOC uno **strumento di ricerca**, un campo di ricerca e un intervallo di tempo (sezione 9). Non lascia mai uscire dal server password, cookie, token o corpi delle richieste, usa poca memoria (circa 100 MB nell'uso normale, circa 200 MB nei picchi) e non riempie mai il disco (sezione 16).

**Al SOC va solo ciò che nessuno ha ancora risolto.**

| Situazione | Va al SOC? |
|---|---|
| ModSecurity ha bloccato la richiesta nelle fasi 1–2 (prima che l'applicazione la ricevesse) | **No.** Resta in localSIEM, ricercabile, e compare come conteggio nel prossimo avviso di quell'IP. |
| ModSecurity ha bloccato la risposta nelle fasi 3–4 (l'applicazione aveva già eseguito la richiesta) | Sì |
| Corrispondenze di regole con ModSecurity in `DetectionOnly` (non viene bloccato nulla) | Sì |
| Corrispondenze di regole sotto la soglia di blocco | Sì, con gravità `low` |
| Segnali delle regole di localSIEM (forza bruta, web shell, file sensibile, enumerazione, errore del database) | Sì |
| Problemi di salute e possibile cancellazione delle tracce | Sì |

**Gravità di ciò che va al SOC**

| Situazione | Gravità |
|---|---|
| Corrispondenze di regole non bloccate, risposta 3xx, 4xx o 5xx | media |
| Corrispondenze di regole non bloccate, risposta 2xx | alta |
| Bloccata nelle fasi 3–4 | alta |
| Segni di successo: regola di fuga di dati o di web shell (950–955) non bloccata, errore SQL subito dopo, POST con 2xx a un nuovo `.php` | critica |
| Sotto la soglia di blocco (spesso falsi positivi dell'applicazione) | bassa (configurabile in Impostazioni) |

**Raggruppamento.** Un avviso per modulo, vhost, IP, categoria e gravità in una finestra di 10 minuti. Un avviso critico parte subito; gli altri attendono 60 secondi per raccogliere la raffica e partono con il conteggio. Uno scanner che invia migliaia di richieste produce pochi avvisi, non migliaia. Se la gravità sale (per esempio, lo stesso attacco ora riceve risposte 200), è un altro avviso.

**Cosa non va mai al SOC:** i corpi delle richieste o delle risposte, i cookie, le intestazioni `Authorization`, le password o i token — nemmeno mascherati — e ciò che era già stato bloccato nelle fasi 1–2 (solo come conteggio). localSIEM maschera i valori sensibili (`password`, `pass`, `pwd`, `passwd`, `token`, `secret`, `api_key`, `apikey`, `auth`, `session` e le intestazioni `Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, `Proxy-Authorization`) con `***` prima di salvare qualsiasi cosa.

**Moduli.** Il nucleo di localSIEM (archiviazione, ricerca, regole, raggruppamento, consegna al SOC, salute) è lo stesso per ogni servizio; ogni modulo aggiunge ciò che è specifico di un servizio. Il modulo Apache + ModSecurity (`apache2`) proviene dal repository `localSIEM-modules` (GitHub) e si installa, si aggiorna e si disinstalla solo dall'interfaccia web, mai con l'installer di localSIEM; installarlo non installa mai Apache né ModSecurity. Ogni modulo si installa, si aggiorna e si disinstalla allo stesso modo, dall'interfaccia web. La sezione 13 spiega come installarli e aggiornarli, vederne lo stato, attivarli e disattivarli e configurarli.

<a id="installation"></a>
## 2. Installazione

L'installazione ha due passaggi: il nucleo di localSIEM e poi i suoi moduli (il passaggio 2, più sotto). Esegui come root, direttamente da GitHub:

```bash
# Debian 13
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
# Alpine 3.24 (prima: apk add bash curl)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
```

L'interfaccia web di localSIEM è sempre in ascolto sulla **porta 10443 con HTTPS**: l'installer verifica che la porta sia libera e si ferma se un altro servizio la usa. L'azione e le opzioni vanno dopo `bash -s --`. L'installer verifica ciò di cui ha bisogno (Python 3.13 con `venv`, OpenSSL, i certificati delle CA, gli strumenti ACL, logrotate, curl, tar) e installa ciò che manca. Eseguito così, tramite pipe, scarica il branch `main` di `https://github.com/PYMEHackers/localSIEM`; eseguito da una copia del progetto (`bash deploy/install-update-reinstall-debian.sh --install`), installa quella copia.

**L'azione.** L'installer richiede sempre un'azione; senza, si ferma e le elenca:

| Azione | Uso |
|---|---|
| `--install` | Installa localSIEM su un server che non lo ha. Se trova qualsiasi cosa di localSIEM (`/opt/localsiem`, i suoi servizi o il suo utente `localsiem`, anche di un'installazione fallita a metà), si ferma e indica `--update` e `--reinstall`. |
| `--update` | Aggiorna il localSIEM installato: ne conserva i dati, gli account, le impostazioni, i moduli e le opzioni indicate in precedenza (più sotto). |
| `--reinstall [--yes]` | Elimina il localSIEM installato con tutti i suoi dati, come fa `--uninstall` (più sotto), e lo installa di nuovo da zero, con nuove password. Prima ti chiede di digitare `yes` (`--yes` non lo chiede; serve senza un terminale) e non elimina nulla finché la nuova copia non è stata scaricata e le opzioni verificate. Le opzioni dell'installazione precedente non vengono mantenute: indicale di nuovo. |
| `--uninstall [--yes]` | Elimina localSIEM e tutti i suoi dati dal server (più sotto). Va usata da sola. |

`--update` e `--reinstall` si fermano quando localSIEM non è installato: usa `--install`.

Opzioni di `--install`, `--update` e `--reinstall`:

| Opzione | Uso |
|---|---|
| `--allow-from LIST` | IP e CIDR autorizzati ad aprire l'interfaccia web, separati da virgole: il SOC e i tuoi amministratori |
| `--soc-url URL` | Predefinito `https://soc.pymehackers.com` |
| `--soc-token TOKEN` | Token di ingestione di questo cliente nel SOC. Facoltativo: senza un SOC, localSIEM funziona da solo (sezione 5) |
| `--soc-ca-file PATH` | Solo per un SOC con un certificato privato (server di test) |
| `--domain NAME` | Nome del server, per il certificato e l'indirizzo del SIEM (predefinito: il suo nome host) |
| `--certificate PATH --private-key PATH` | Certificato da usare. Senza queste opzioni localSIEM copia il certificato Let's Encrypt di `--domain` se ce n'è uno (e lo copia di nuovo a ogni rinnovo), oppure ne crea uno autofirmato. |
| `--retention-days N`, `--max-disk SIZE` | Conservazione (sezione 16) |
| `--enable-mfa`, `--disable-mfa` | Verifica in due passaggi attivata (obbligatoria per ogni account) o disattivata. Senza queste opzioni, una nuova installazione la ha disattivata e un aggiornamento mantiene ciò che è stato scelto in Amministrazione › Impostazioni (sezione 14). |
| `--rotate-credentials` | Crea un nuovo segreto di firma JWT e lo scrive in `/root/webapp-credentials.txt` |
| `--ref REF` | Branch o tag di localSIEM da scaricare (predefinito `main`) |
| `--source-url URL` | Archivio (`.tar.gz`) di localSIEM da installare al posto di quello di GitHub (un mirror) |
| `--modules-repository URL`, `--modules-ref REF` | Repository (o archivio `.tar.gz`) e branch o tag da cui l'interfaccia web installa e aggiorna i moduli (sezione 13). Predefinito: `https://github.com/PYMEHackers/localSIEM-modules`, branch `main`. |

**Sempre l'ultima versione.** GitHub conserva i file di `raw.githubusercontent.com` in una cache fino a 5 minuti dopo ogni modifica, quindi i comandi qui sopra leggono l'installer tramite l'API di GitHub, che non ha cache; poi l'installer chiede a quell'API a quale commit corrisponde il branch e scarica esattamente quel commit, e chiede a ogni server lungo il percorso di non rispondere con una copia in cache. Senza un token GitHub consente 60 richieste API all'ora da ogni indirizzo IP: se rifiuta, il comando fallisce con `403` (attendi ed eseguilo di nuovo); se fallisce solo la domanda dell'installer, l'installer avvisa e scarica il branch.

Le opzioni vengono ricordate, in `/opt/localsiem/config/install.env`: `--update` senza opzioni le mantiene. Per aggiornare:

```bash
# Debian 13 (Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --update
```

Il log dell'installer è `/root/webapp-install.log` e le password che crea sono in `/root/webapp-credentials.txt` (entrambi con modo 600). Mostra il suo avanzamento in passaggi numerati (`[3/12] Getting localSIEM`), con `✓` per ciò che è fatto, `!` per le avvertenze, `✗` per i fallimenti e `·` per le informazioni, a colori in un terminale (`NO_COLOR=1` o `LOCALSIEM_COLOR=never` disattivano i colori). L'output di apt-get o apk, curl, tar e pip va solo nel log; quando uno di essi fallisce, lo schermo ne mostra le ultime 20 righe. Il log riceve le stesse righe, senza colori, con le ore nel formato di registrazione. Alla fine esegue la diagnostica di ogni modulo attivato (sezione 4) e mostra un riepilogo: l'indirizzo dell'interfaccia web, che è anche l'indirizzo del SIEM da dare al SOC, il file delle credenziali, il log e lo stato del SOC, seguiti dai passaggi successivi. Se fallisce, indica a quale passaggio si è fermato.

**Disinstallazione.** `--uninstall` elimina localSIEM dal server: ferma e rimuove i suoi servizi ed elimina `/opt/localsiem` (codice, impostazioni, il database con ogni evento e avviso, certificati e moduli), l'utente `localsiem`, l'accesso in lettura ai log concesso da `setup-modules`, la configurazione di Apache (`localsiem.conf`) che aggiungeva l'opzione `--configure-apache` delle versioni precedenti del modulo di Apache (1.2.0 o precedenti), con un configtest e un reload di Apache, il file di logrotate, l'hook di Let's Encrypt e le voci di localSIEM di `/root/webapp-credentials.txt` (il file viene eliminato quando non vi resta nient'altro). Prima ti chiede di digitare `yes` (`--yes` non lo chiede; serve senza un terminale). Se sul server non resta nulla di localSIEM, lo dice: «Nothing of localSIEM was found on this server.». Restano il log dell'installer, i pacchetti aggiunti dall'installer, `mod_unique_id` (Debian) e i log di Apache, anche il `localsiem_access.log` che quel file faceva scrivere ad Apache e `modsec_audit.log`: localSIEM non modifica né elimina mai un log di Apache. Per disinstallare:

```bash
# Debian 13 (Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --uninstall
```

**Reinstallazione.** Per ripartire da zero in un solo passaggio, `--reinstall` elimina tutto allo stesso modo e installa di nuovo localSIEM (indica di nuovo le opzioni):

```bash
# Debian 13 (Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --reinstall --allow-from 203.0.113.10 --soc-token TOKEN
```

**2. I moduli.** L'installer di localSIEM non installa **nessun modulo**: lascia localSIEM pronto per accoglierli, e un aggiornamento mantiene quelli già installati (e l'accesso in lettura ai loro log). I moduli si installano **solo dall'interfaccia web**: Moduli › Installabili (sezione 13), che elenca i moduli del repository `localSIEM-modules` non ancora installati; quel repository non ha un installer proprio. localSIEM scarica il modulo da lì, ne copia la cartella (`mod-<name>/` nel repository) in `/opt/localsiem/modules/<name>/` (le cartelle `tests/` non vengono copiate; un modulo installato di nuovo recupera le impostazioni che aveva) e riavvia il collettore. Anche l'aggiornamento e la disinstallazione dei moduli si fanno dall'interfaccia web: **Aggiorna**, quando il repository ha una versione più recente, e **Disinstalla**, entrambi in Moduli › Installati (sezione 13).

Leggere i log di un modulo richiede root, quindi, una volta installato il modulo, l'interfaccia web mostra in una finestra di dialogo il comando da eseguire come root sul server:

```bash
/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py setup-modules
```

Dà all'utente `localsiem` l'accesso in lettura alle cartelle dei log che ogni modulo installato dichiara (`/var/log/apache2` per il modulo di Apache; sezione 3.7), anche ai file delle rotazioni successive, riavvia localSIEM ed esegue la diagnostica come `localsiem`. Può essere eseguito di nuovo in qualsiasi momento. Quell'accesso in lettura, che concede localSIEM, è tutto ciò che root fa per i moduli.

**Installare un modulo non installa mai il software che sorveglia**, né nient'altro: un modulo funziona con ciò che il server ha già e non modifica mai nulla al di fuori di `/opt/localsiem/`. Un nuovo modulo parte attivato o disattivato come ha deciso il suo autore, tranne quando al server manca ciò che gli serve (per il modulo di Apache: Apache e ModSecurity 2): allora viene installato **disattivato**, l'interfaccia web dice cosa manca e il suo interruttore resta bloccato finché **Riconfigura** non lo trova (sezione 13). Il suo stato è in **Moduli › Installati** (sezione 13).

<a id="requirements"></a>
## 3. Requisiti di Apache e ModSecurity

Questi sono i requisiti del modulo Apache + ModSecurity. Apache e ModSecurity 2 devono essere installati prima: senza di essi il modulo non può essere attivato (sezione 13). localSIEM non modifica mai di sua iniziativa la configurazione di Apache, né i log di Apache, il loro formato o il modo in cui vengono scritti: il modulo legge i log che il server scrive già e si adatta a essi. La diagnostica del modulo (sezione 4) verifica ogni requisito: per ModSecurity con il suo CRS e `SecRuleEngine` (punto 1), `mod_unique_id` (punto 2) e l'accesso in lettura (punto 7) mostra lo snippet o il comando esatto per ciascuno che manca, perché tu lo applichi; i log (punti da 3 a 6) li descrive soltanto, senza proporre di modificarli.

1. **ModSecurity 2 con OWASP CRS**, con `SecRuleEngine On` o `DetectionOnly`. Funzionano entrambi: con `DetectionOnly` non viene bloccato nulla, quindi ogni corrispondenza va al SOC.
2. **`mod_unique_id`**, di cui ModSecurity 2 ha bisogno per funzionare (senza, non ispeziona nulla; Alpine non lo carica per impostazione predefinita) e che unisce i tre record di ogni richiesta.
3. **Un access log**, così come lo scrive Apache. Va bene qualsiasi formato (`combined`, `vhost_combined`, `common`, o qualsiasi `LogFormat` della configurazione): ogni riga viene unita alla sua richiesta per IP del client, metodo, URI, codice di stato e ora («correlazione debole»), e il vhost viene da `%v` o, in sua assenza, dall'intestazione Host e dalla porta del record di audit. Quando il formato ha anche i millisecondi, `%v` e `%{UNIQUE_ID}e` (come le righe `localsiem_combined` che alcuni server scrivono già), ogni riga viene unita alla sua richiesta tramite `UNIQUE_ID`, e con `%D` localSIEM ne ottiene anche la durata. Un access log il cui formato non ha l'IP del client, l'ora, la riga della richiesta o il codice di stato viene letto così com'è, ma le sue righe non possono essere unite alle loro richieste: quelle richieste si vedono nel log di audit di ModSecurity. Un `CustomLog` il cui formato non ha alcuna direttiva scrive lo stesso testo su ogni riga e non viene letto.
4. **`mod_remoteip`**, che decide quale IP contengono i log. Se il web è dietro un proxy o un bilanciatore di carico e Apache non lo usa, i log contengono l'IP del proxy, e così gli avvisi e le regole per IP: lo dicono la diagnostica e l'avvertenza di salute «Real client IP missing» (sezione 15).
5. **Il log di audit di ModSecurity**, così come lo scrive ModSecurity: seriale o concorrente, JSON o nativo, con le parti che ha. Senza di esso (`SecAuditEngine Off` o nessun `SecAuditLog`) localSIEM decide solo da `error.log`, e la scheda della richiesta non ha intestazioni né elenco delle regole. Senza la parte `H` non se ne può leggere l'azione intrapresa. La parte `E` (il corpo della risposta), se viene registrata, non va mai al SOC; la parte `K` (il testo completo di ogni regola eseguita) non viene salvata. Con il tipo concorrente (un file per transazione), ModSecurity di solito crea i file con modo 600, e localSIEM li legge solo se `localsiem` può farlo (punto 7).
6. **Mascheramento alla sorgente**: se ModSecurity non maschera il log di audit su disco (le sue azioni `sanitise`), quel file può contenere password e cookie; localSIEM li maschera prima di salvarli, e non vanno mai al SOC.
7. **Accesso in lettura per l'utente `localsiem`** ai log. Il comando per root della sezione 2 (`manage.py setup-modules`) lo concede per le cartelle che i moduli installati dichiarano (`/var/log/apache2` per il modulo di Apache), e l'installer di localSIEM lo concede di nuovo a ogni aggiornamento: su Debian aggiunge `localsiem` al gruppo `adm` e, come su Alpine, dà a `localsiem` l'accesso in lettura a quelle cartelle tramite ACL, inclusa un'ACL predefinita perché siano leggibili anche i file delle rotazioni successive. Anche i log che aggiungi a mano in un'altra cartella (sezione 13) hanno bisogno di quell'accesso, per esempio `setfacl -m g:localsiem:rx /srv/logs`, `setfacl -d -m g:localsiem:r /srv/logs` e `setfacl -m g:localsiem:r /srv/logs/*.log`. localSIEM legge soltanto i log: non vi scrive mai, né li ruota, li tronca, li sposta o li elimina. Quando inizia a seguire un log (al primo avvio, dopo aver installato o attivato un modulo, o quando root gli concede l'accesso in lettura) parte dalla sua fine: ciò che il log conteneva già è storico e non genera mai avvisi; solo il log di un vhost creato dopo viene letto dall'inizio (quando è fino a 5 MB).

<a id="doctor"></a>
## 4. La diagnostica

Ogni modulo ha la propria diagnostica. La diagnostica del modulo di Apache verifica ogni requisito della sezione 3 e mostra lo snippet o il comando che risolve ciascuno di quelli mancanti; i log (formato, `mod_remoteip`, log di audit, mascheramento) li descrive soltanto, senza proporre di modificarli, ed elenca le sorgenti trovate (e quelle che non può leggere, come i log tramite pipe). Viene eseguita alla fine di ogni installazione di localSIEM e del comando per root della sezione 2, compare nella pagina di ogni modulo (**Moduli › Installati › Configura**, sezione 13, con il pulsante «Rileva di nuovo ed esegui la diagnostica») e può essere eseguita in qualsiasi momento per ogni modulo attivato:

```bash
runuser -u localsiem -- /opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor   # Debian
su -s /bin/sh localsiem -c "/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor"   # Alpine
```

`✓` significa che va bene, `!` che funziona con dei limiti, `✗` che va corretto, `·` che si applica solo in alcune situazioni (a colori in un terminale; dove non si può scrivere UTF-8, `+`, `!`, `x` e `-`). Un modulo che non può essere caricato viene mostrato per primo come `✗ Module <name> not loaded: <reason>`. Un modulo disattivato non ha diagnostica: se ha dei requisiti (sezione 13), la diagnostica li mostra al suo posto, così sai se può essere attivato.

<a id="soc"></a>
## 5. Connessione con il SOC

Collegare localSIEM a un SOC è facoltativo. Senza un SOC (nessun token, oppure **Invia gli avvisi al SOC** disattivato), localSIEM funziona da solo: conserva ogni avviso nella scheda **Avvisi** come «Non inviato» e non li invia mai in seguito, nemmeno quando un SOC viene configurato dopo: da quel momento gli arrivano solo i nuovi avvisi. I canali (Telegram) funzionano con o senza un SOC.

L'amministratore del SOC:

1. Crea un token di ingestione per il cliente (viene mostrato una sola volta) e te lo consegna. Impostalo con `--soc-token` o in **Amministrazione › SOC**.
2. Imposta come **indirizzo del SIEM** del cliente `https://<server>:<port of localSIEM>` (mostrato dall'installer e in Amministrazione › SOC). L'analista che si occupa di un avviso usa quel link per venire a indagare.
3. Ti fornisce gli IP in uscita del SOC: aggiungili agli IP consentiti (`--allow-from` o Amministrazione › Impostazioni) e **apri la porta nel firewall solo a loro e ai tuoi amministratori**.

localSIEM invia un **heartbeat** ogni 5 minuti. Se il SOC non riceve né avvisi né heartbeat per un certo tempo (60 minuti per impostazione predefinita), avvisa il suo team. Gli avvisi attendono in una coda persistente: un'interruzione di rete o un riavvio non ne fa perdere nessuno, e inviarne uno di nuovo non lo duplica mai nel SOC. Se il SOC risponde che il cliente ha esaurito tutti i suoi numeri di avviso, localSIEM smette di inviare, mantiene la coda e lo mostra in Amministrazione › SOC.

Ogni avviso porta un nome di regola stabile, una descrizione con la query esatta da incollare nella ricerca di localSIEM, e i dettagli: vhost, IP del client, metodo, URI (mascherato), risposta, user agent, i dati di ModSecurity (motore, azione, fase, punteggio, soglia, regole, dati corrispondenti), il gruppo (conteggio, prima e ultima volta, `UNIQUE_ID` di esempio) e il **contesto** dell'IP: richieste e richieste bloccate nell'ultima ora, regole bloccate e la prima volta in cui è stato visto.

<a id="signin"></a>
## 6. Accesso e account

Apri `https://<server>:10443/`: la pagina di accesso contiene solo il form, con il logo, il nome utente, la password, **Continua** e, sotto, la lingua e il tema. Gli account vengono creati da un amministratore; non c'è registrazione libera. Le password hanno almeno 8 caratteri. La **Verifica in due passaggi** è disattivata per impostazione predefinita; quando un amministratore la attiva (Amministrazione › Impostazioni, sezione 14) è obbligatoria per ogni account: al prossimo accesso, scansiona il codice QR con un'app di autenticazione (Google Authenticator, Microsoft Authenticator, Aegis, FreeOTP...; compare come «PYMEHackers localSIEM») e digita il suo codice, e da quel momento ogni accesso chiede il codice dell'app. Dopo diversi tentativi falliti l'accesso viene bloccato per qualche minuto.

**Accesso diretto con un token.** Un amministratore può dare a un analista un URL di accesso, `https://<server>:10443/auth/login/auto?token=...` (Utenti › Token di accesso, sezione 14). Aprirlo da un indirizzo consentito esegue subito l'accesso, senza password né secondo fattore, e apre la Panoramica della dashboard utente; aggiungi `&next=/user/dashboard/search/?q=...` per aprire un'altra pagina del sito. Se il token non funziona, la pagina di accesso dice perché: token sconosciuto, scaduto o revocato, oppure l'account è disattivato o non è più un analista. Custodisci l'URL come una password: chiunque lo abbia può accedere con quell'account finché non scade o non viene revocato. Ogni accesso, con password o con un token, e ogni tentativo fallito viene registrato (Accessi, sezione 14).

Dopo l'accesso arrivi alla **Panoramica** della tua dashboard (sezione 7). Un link a una ricerca (per esempio dal SOC) apre la pagina di accesso se serve e poi **la stessa ricerca con i suoi parametri**.

Ruoli: **analista** (lavora nella dashboard utente: panoramica, ricerca, vista in diretta, avvisi, lo stato dei moduli e l'account) e **amministratore** (lavora nella dashboard dell'amministratore: lo stesso più la configurazione dei moduli e l'amministrazione). La lingua (de-DE, en-GB, en-US, es-AR, es-ES, fr-FR, he-IL, hi-IN, it-IT, ja-JP, ko-KR, pt-BR, pt-PT, ru-RU, zh-CN), il tema (come il sistema, chiaro o scuro) e l'orologio UTC sono nella barra del titolo di ogni pagina delle dashboard; la pagina di accesso li ha sotto **Continua** e parte con quelli scelti per ultimi in questo browser (senza una scelta, quelli del browser e del sistema). La lingua mostrata quando premi **Continua** diventa la lingua del tuo account: le dashboard la mantengono, in qualsiasi browser, finché non la cambi. Le ore sono sempre in UTC nel formato nativo `2026/10/29@13:59:59.723`. I file che localSIEM scrive (le esportazioni, `/root/webapp-credentials.txt`, il log dell'installer) e gli avvisi che invia al SOC usano il formato di registrazione `2026-10-29@13-59-59.723`, anch'esso in UTC.

<a id="dashboards"></a>
## 7. Le due dashboard

Ogni ruolo ha la propria dashboard; il suo indirizzo dice in quale ti trovi. La barra laterale ha il logo in alto, le schede (una linea tra un gruppo e l'altro) e, in fondo, **Esci**.

| | Dashboard dell'amministratore | Dashboard utente |
|---|---|---|
| Chi | Amministratori | Analisti |
| Indirizzo | `/admin/dashboard/<tab>/` | `/user/dashboard/<tab>/` |
| Schede | Panoramica, Ricerca, In diretta, Avvisi; Moduli (Installati e Installabili), Utenti (Account e Token di accesso), SOC, Canali (Generale e Telegram), Impostazioni, Audit delle ricerche, Accessi; Account | Panoramica, Ricerca, In diretta, Avvisi, Moduli (solo lo stato), Account |

Ogni scheda ha il proprio indirizzo (per esempio `/admin/dashboard/logins/`), e `/admin/dashboard/` o `/user/dashboard/` aprono la Panoramica. Anche le sezioni di una scheda hanno il loro: `/admin/dashboard/users/` apre `/admin/dashboard/users/accounts/` e i token di accesso sono in `/admin/dashboard/users/tokens/`; `/admin/dashboard/modules/` apre `/admin/dashboard/modules/installed/` e i moduli installabili sono in `/admin/dashboard/modules/installable/`. Un indirizzo dell'altra dashboard ti porta alla stessa scheda della tua: un amministratore che apre un link a `/user/dashboard/search/?q=...` (il link abituale del SOC) ottiene la stessa ricerca in `/admin/dashboard/search/`; un analista che apre una scheda di amministrazione ottiene la Panoramica della dashboard utente.

**Cosa vedono gli analisti.** Tutto ciò che serve per indagare: la panoramica, le ricerche con le loro schede delle richieste, la vista in diretta, gli avvisi e lo stato di ogni modulo (attivato o disattivato, funzionante o no, e i suoi contatori). Non possono attivare o disattivare i moduli, configurarli, vederne la diagnostica o le regole, né gestire gli utenti, i token di accesso, la connessione al SOC, le impostazioni, l'audit delle ricerche o il registro degli accessi.

<a id="overview"></a>
## 8. Panoramica

La prima scheda di entrambe le dashboard. Si aggiorna ogni 15 secondi e mostra:

- **Eventi (24 h)**, con quanti di essi hanno generato un avviso; **Bloccati (24 h)**, ciò che ModSecurity ha già risolto (conservato, senza avviso); **Avvisi (24 h)**, con quanti sono in attesa del SOC; e **Moduli in funzione**, i moduli attivati in stato «Attivo e funzionante» sul totale di quelli attivati (in verde quando funzionano tutti).
- **Attività delle ultime 24 ore**: eventi per ora; la parte blu di ogni barra è ciò che ha bloccato ModSecurity. Fai clic su un'ora per aprire la ricerca dei suoi eventi.
- **Stato dei moduli**: ogni modulo con il suo stato (sezione 13) e ciò che sta leggendo; «Vedi i moduli» apre la scheda Moduli.
- **Sistema**: se il collettore è in esecuzione (e la sua versione), da quando, lo stato della connessione con il SOC, l'ultimo heartbeat, gli avvisi in attesa del SOC, lo spazio libero su disco e la dimensione del database rispetto al suo massimo.
- **Ultimi avvisi**: i sei più recenti (gravità, regola, IP, conteggio, stato, ultima volta); «Vedi tutti gli avvisi» apre la scheda Avvisi.

<a id="search"></a>
## 9. Ricerca

La scheda **Ricerca** ha un campo di ricerca e un intervallo di tempo (ultimi 15 minuti, ultima ora, ultime 24 ore, ultimi 7 giorni, ultimi 30 giorni o un intervallo personalizzato nel formato nativo).

| Sintassi | Significato |
|---|---|
| `word` | Ricerca full-text nel testo originale (mascherato), anche con decodifica URL |
| `"exact phrase"` | Frase |
| `field:value` | Campo uguale a un valore (i campi di testo non distinguono tra maiuscole e minuscole) |
| `field:*part*` | Caratteri jolly |
| `status:>=500`, `status:400..499`, `status:4xx` | Confronti e intervalli sui campi numerici |
| `a b` / `a AND b`, `a OR b`, `NOT a` / `-a`, `( )` | Operatori e parentesi |

| Gruppo | Campi |
|---|---|
| Rete | `ip`, `vhost`, `host` |
| Richiesta | `method`, `uri`, `path`, `query`, `status`, `bytes`, `duration` (microsecondi), `ua`, `referer` |
| Origine | `uid` (UNIQUE_ID), `module`, `source` (`access`/`error`/`audit`) |
| ModSecurity | `rule` (id del CRS, o `localsiem:<rule>`), `category`, `phase`, `score`, `engine` (`on`/`detection-only`) |
| Avvisi | `severity`, `action` (`blocked`/`none`), `alert` (codice SOC), `sent` (`yes`/`no`) |
| Qualità | `parse` (`ok`/`partial`/`unparsed`) |

Esempi:

- `ip:203.0.113.7` — tutto ciò che riguarda un IP
- `rule:942100` — richieste che corrispondono a quella regola del CRS
- `status:200 action:none category:sqli` — SQL injection che non sono state bloccate e hanno ricevuto un 200
- `uri:*wp-login*`
- `"union select"`
- `uid:ZTx1kH8AAQEAAB2gTkAAAAAB` — una richiesta
- `alert:c00007a0001F` — le richieste di un avviso del SOC
- `(category:sqli OR category:xss) sent:no -status:404`

Categorie: `sqli`, `xss`, `lfi`, `rfi`, `rce`, `php`, `java`, `fixation`, `generic`, `protocol`, `multipart`, `scanner`, `method`, `data-leakage`, `webshell`, e quelle delle regole di localSIEM: `bruteforce`, `enumeration`, `sensitive-file`, `db-error`, più `health-*`.

Un errore di sintassi viene mostrato sotto il campo con la posizione dell'errore. Una ricerca che richiede più tempo del suo limite (5 s) ti chiede di restringere l'intervallo.

La pagina dei risultati mostra:

- **L'istogramma** nel tempo; la parte blu di ogni barra è ciò che ha bloccato ModSecurity. Trascina sulle barre (o fai clic su una) per restringere l'intervallo.
- **Riepiloghi** della query: IP con più richieste, percorsi più richiesti, codici HTTP e regole più frequenti. Fai clic su un valore per aggiungerlo alla query.
- **La tabella dei risultati** (ORA, SORGENTE, IP, METODO, URI, CODICE, AZIONE, REGOLE, AVVISO), dai più recenti, con «Carica altri».
- **Esporta** in CSV o JSON (dati mascherati, fino a 10 000 righe, ore nel formato di registrazione `2026-10-29@13-59-59.723`) e **Copia link** (con ore assolute). Il formato del link è `/user/dashboard/search/?q=<query>&from=<native time>&to=<native time>` (`/admin/dashboard/search/...` quando lo copia un amministratore); un link di una qualsiasi delle due dashboard funziona per entrambi i ruoli.

Ogni ricerca ed esportazione viene registrata (chi, cosa, quando) ed è visibile agli amministratori: i log contengono dati personali.

<a id="card"></a>
## 10. La scheda della richiesta e i pivot

Fai clic su una riga per aprire la scheda della richiesta: ora, vhost, IP del client, metodo, URI, codice, dimensione, durata, user agent, `UNIQUE_ID`, correlazione, azione intrapresa, motore di ModSecurity, fase, punteggio e soglia, categoria, gravità e avvisi; e, per ogni record, il suo contenuto analizzato: le regole corrispondenti con il loro messaggio e i loro dati, le intestazioni della richiesta e il corpo mascherato, le intestazioni della risposta, le righe di errore e la riga originale. Il modulo di ogni record aggiunge ciò che sa mostrare (il modulo di Apache ricostruisce le intestazioni e il corpo dal record di audit).

Note nella scheda: un 403 senza alcuna traccia di ModSecurity viene segnato come **dubbio** (non viene conteggiato come blocco); **correlazione debole** significa che la riga di accesso è stata unita alla sua richiesta per IP del client, metodo, URI, codice di stato e ora, perché l'access log non ha `UNIQUE_ID`; per la richiesta è comparso un **errore del database**.

Pivot: **Questo IP** (tutta la sua attività), **±5 min** (la sequenza temporale attorno alla richiesta), **Regola …** (ogni regola corrispondente), **Questa categoria**, **Questo UNIQUE_ID**.

<a id="live"></a>
## 11. Vista in diretta

La scheda **In diretta** mostra i nuovi eventi non appena il collettore li salva (dopo la finestra di correlazione di 5 secondi), i più recenti in alto. Il filtro usa la sintassi della ricerca. **Pausa** ferma gli aggiornamenti; quando riprendi, continua dall'evento più recente.

<a id="alerts"></a>
## 12. Avvisi

La scheda **Avvisi** elenca gli avvisi generati da localSIEM: codice SOC, gravità, regola, IP, vhost, conteggio, prima e ultima volta, e stato:

| Stato | Significato |
|---|---|
| Nel buffer | Raccoglie la raffica (60 s) prima di partire |
| In coda | In attesa del SOC (rete non disponibile, SOC che non risponde) |
| Inviato | Accettato dal SOC; ne viene mostrato il codice |
| Rifiutato | Il SOC ha rifiutato quell'avviso; il resto della coda prosegue. Può essere rimesso in coda da Amministrazione › SOC. |
| Non inviato | Non era configurato alcun SOC, oppure l'invio era disattivato: l'avviso resta in localSIEM e non viene mai inviato in seguito (il SOC è facoltativo, sezione 5) |

Fai clic su una riga per vedere la descrizione, le **richieste di questo avviso** (fino a 50, dalla più vecchia, come nella ricerca: fai clic su una per aprirne la scheda, con la richiesta, le sue intestazioni, le regole di ModSecurity e le righe originali), la finestra, l'`external_id` e l'avviso esatto inviato al SOC. **Cerca** apre la ricerca del gruppo. Mentre un avviso è aperto, l'elenco non viene aggiornato.

<a id="modules"></a>
## 13. Moduli

Nella dashboard dell'amministratore la scheda **Moduli** ha due sezioni, ognuna con il proprio indirizzo: **Installati** (`/admin/dashboard/modules/installed/`), che si apre per impostazione predefinita (`/admin/dashboard/modules/` porta lì), e **Installabili** (`/admin/dashboard/modules/installable/`), dove si installano i moduli (più sotto). Gli analisti hanno solo l'elenco dei moduli installati, senza sezioni (`/user/dashboard/modules/`).

**Installati** elenca i moduli installati, una riga ciascuno, a tutta larghezza, disposti come l'intestazione della pagina del modulo: in alto il nome, l'id e la versione e, sotto, il suo **stato**, un riepilogo, i motivi del suo stato e, se è attivato, i suoi contatori: sorgenti in lettura, righe dell'ultima ora, ultimi dati, eventi e richieste bloccate delle ultime 24 ore e il risultato della sua diagnostica. Gli amministratori vedono anche l'interruttore a destra del nome e, in fondo alla riga, i suoi pulsanti. La pagina si aggiorna ogni 10 secondi. Senza alcun modulo installato dice «Installa i moduli dalla scheda Installabili.» (agli analisti: «Nessun modulo installato. Li installa un amministratore in Moduli › Installabili.»).

| Stato | Significato |
|---|---|
| Attivo e funzionante | Attivato, caricato dal collettore e in lettura delle sue sorgenti. Le avvertenze della diagnostica sono elencate come note e non lo cambiano. |
| Attivo, con avvertenze | Attivato, ma senza sorgenti, con una sorgente che non esiste ancora, o installato dopo l'avvio del collettore (riavvia il servizio `localsiem`). |
| Errore | Non si carica (viene mostrato il motivo), la sua diagnostica segnala un errore, o una sorgente non può essere letta (permessi dell'utente `localsiem`, sezione 3.7). |
| Applicazione della modifica… | Appena attivato o disattivato; il collettore sta applicando la modifica (pochi secondi). |
| Disattivato | Disattivato: localSIEM non ne legge i log né ne invia gli avvisi. Ciò che è già salvato resta. Con il motivo «A questo server manca ciò che serve: …», è stato installato senza i suoi requisiti e non può ancora essere attivato (vedi Requisiti e Riconfigura, più sotto). |
| Sconosciuto | Il collettore non è in esecuzione (servizio `localsiem`): nessuno sta leggendo nulla. |

Gli **analisti** vedono solo questo elenco. Gli **amministratori** hanno anche, in ogni riga:

- **L'interruttore** di ogni modulo, per attivarlo o disattivarlo. La disattivazione chiede conferma. La modifica si applica subito, senza riavviare nulla. Finché al server manca ciò che serve a un modulo, il suo interruttore è bloccato («Disattivato: requisiti mancanti»).
- **Configura**, che apre la pagina del modulo (`/admin/dashboard/modules/installed/<name>/`; il vecchio indirizzo `/admin/dashboard/modules/<name>/` ti porta lì):
  - l'intestazione con lo stato, la cartella in cui è installato il modulo, l'interruttore, «Torna ai moduli installati» (torna a Installati) e «Rileva di nuovo ed esegui la diagnostica»; per un modulo con requisiti, anche il pulsante «Riconfigura» e, finché il modulo è disattivato o ne manca uno, i suoi **Requisiti** (più sotto);
  - **Impostazioni**: il form delle impostazioni proprie del modulo; «Salva le impostazioni» le applica subito;
  - **Sorgenti**: i log che legge (tipo, percorso, vhost, righe e righe non analizzate dell'ultima ora, ultimi dati, stato) e, sotto, i log che ha trovato ma non legge, con il motivo;
  - **Diagnostica**: le verifiche dei suoi requisiti, con lo snippet o il comando che risolve ciascuno di quelli mancanti e un pulsante «Copia» (i log vengono solo descritti);
  - **Regole**: ogni regola del modulo con il suo interruttore («Attiva»), gravità, soglia e finestra (soglia e finestra solo per le regole di soglia e di sequenza); «Salva le regole» le applica subito.
- **Aggiorna**, quando il repository `localSIEM-modules` ha una versione più recente del modulo. Ogni volta che apri Installati, localSIEM controlla il repository: nel frattempo dice «Ricerca di versioni più recenti nel repository…» e, se il controllo fallisce, «Impossibile cercare versioni più recenti nel repository: <error>», e l'elenco funziona come al solito. Perché il repository non venga scaricato a ogni visita, il browser riusa la sua risposta per 10 minuti; «Controlla il repository», in Installabili, lo scarica sempre di nuovo, e installare, aggiornare o disinstallare un modulo scarta la risposta conservata. L'aggiornamento ogni 10 secondi non lo scarica mai. Un modulo con una versione più recente mostra, nella sua riga, la notifica «Il repository ha la versione X (quella installata è la Y).» con il pulsante **Aggiorna**. Se quella versione richiede un localSIEM più recente, la notifica non ha pulsante e lo dice: «Il repository ha la versione X, ma richiede localSIEM Z o successivo: aggiorna localSIEM per installarla.» **Aggiorna** chiede conferma («Aggiorna il modulo»): localSIEM scarica la nuova versione dal repository, la sostituisce a quella installata e riavvia il collettore; le sue impostazioni vengono mantenute, e il modulo resta attivato o disattivato com'era. Mentre è in corso, il pulsante dice «Aggiornamento…»; alla fine un messaggio dice «<module> aggiornato alla versione X.» Una finestra di dialogo, «<module> aggiornato», si apre solo quando c'è altro da fare: se la nuova versione legge altri log, mostra il comando per root (`manage.py setup-modules`, sezione 2, con «Copia»); se il collettore non ha risposto, ti chiede di riavviare il servizio `localsiem`.
- **Disinstalla**, nella riga di ogni modulo installato (anche di uno che non si carica) e nella sua pagina. Dopo la conferma, localSIEM elimina `/opt/localsiem/modules/<name>/` e riavvia il collettore senza di esso: smette di leggerne i log e di inviarne gli avvisi. Gli eventi e gli avvisi già salvati possono ancora essere cercati, e le sue impostazioni (e le modifiche alle sue regole) restano in `settings.json`, quindi tornano se lo installi di nuovo. L'accesso in lettura ai suoi log che root ha dato a `localsiem` non viene revocato; se nessun altro modulo legge quella cartella, puoi rimuoverlo a mano, per esempio `setfacl -R -x g:localsiem /var/log/apache2` e `setfacl -d -x g:localsiem /var/log/apache2`.

**Installabili** (solo amministratori) ha la scheda «Moduli installabili»: i moduli del repository `localSIEM-modules` (per impostazione predefinita `https://github.com/PYMEHackers/localSIEM-modules`, branch `main`; le opzioni dell'installer `--modules-repository` e `--modules-ref` lo cambiano) non ancora installati su questo server. «Controlla il repository» lo scarica ed elenca quei moduli, ognuno con il suo nome, id, versione e riepilogo e il suo pulsante o la sua nota:

| Pulsante o nota | Significato |
|---|---|
| Requisiti | Mostra ciò di cui il modulo ha bisogno sul server e i comandi che lo installano (più sotto) |
| Installa | Installa il modulo |
| Richiede localSIEM X o successivo | Non può essere installato: aggiorna prima localSIEM |
| Il modulo del repository non è valido | Non può essere installato |

**Requisiti** apre la finestra di dialogo «<module>: requisiti», con ciò di cui il modulo ha bisogno sul server e i comandi che lo installano, dichiarati dal modulo stesso (`install_requirements` del suo `module.json`). Installare un modulo non installa mai il software che sorveglia, quindi esegui quei comandi sul server **prima** di installare il modulo. La finestra mostra due volte i comandi per il sistema di questo server («Questo server: Debian GNU/Linux 13 (trixie)»), ognuno con «Copia»: **Come root** e **Con sudo** (gli stessi comandi preceduti da `sudo`), così puoi incollarli in un terminale del server come root o come utente autorizzato a usare sudo. Le note del modulo vengono per prime (per esempio, che Alpine non ha un pacchetto di ModSecurity 2). Se il modulo non dichiara comandi per il sistema di questo server, la finestra mostra quelli di ogni sistema che dichiara (Debian e Alpine); se non ne dichiara nessuno, dice «Questo modulo non dichiara nulla da installare sul server.». localSIEM non esegue mai questi comandi.

Se tutti i moduli del repository sono già installati, lo dice («Tutti i moduli del repository sono già installati.»). I moduli già installati non compaiono mai in questo elenco: si aggiornano in Installati (**Aggiorna**, più sopra). L'interfaccia web non reinstalla un modulo né ne installa una versione precedente: per reinstallarne uno, disinstallalo e installalo di nuovo qui (le sue impostazioni vengono mantenute).

Questo elenco è l'unico modo per installare i moduli. localSIEM scarica il modulo, verifica il suo `module.json`, ne copia la cartella (`mod-<name>/` nel repository) in `/opt/localsiem/modules/<name>/` (senza la sua cartella `tests/`; un modulo installato di nuovo recupera le impostazioni che aveva) e riavvia il collettore, che lo carica entro pochi secondi. Il modulo esce dall'elenco e una finestra di dialogo, «<module> installato», dice cosa viene dopo:

- Consentire a `localsiem` di leggere i log del modulo richiede root, quindi la finestra mostra **il comando da eseguire come root** sul server, con un pulsante «Copia»: `manage.py setup-modules` (sezione 2), che concede l'accesso in lettura e riavvia localSIEM. Finché il comando non viene eseguito, il modulo può mostrare «Errore» perché i suoi log non possono essere letti.
- Se, alla sua prima installazione, al server manca ciò che serve al modulo, il modulo viene installato disattivato e la finestra elenca ciò che manca al posto del comando, con il suggerimento di aprire il modulo in Installati (**Configura**) e premere **Riconfigura** una volta che è presente (più sotto).

La finestra ha due pulsanti: «Chiudi» e «Vedi i moduli installati», che apre Installati. Il server deve poter raggiungere GitHub (HTTPS) per questo elenco e per il controllo delle versioni più recenti in Installati.

**Requisiti e Riconfigura.** Installare un modulo non installa mai il software che sorveglia. Un modulo può dichiarare ciò che il server deve avere prima che possa essere attivato: il modulo di Apache richiede Apache (la sua configurazione: `apache2.conf`, `httpd.conf` o il file dell'impostazione **File di configurazione di Apache**) e ModSecurity 2 caricato (`mod_security2`; ModSecurity 3 non conta). Se mancano alla sua prima installazione, il modulo viene installato **disattivato** («Disattivato», con il motivo «A questo server manca ciò che serve: …») e il suo interruttore è **bloccato**. La sua pagina elenca i suoi requisiti come la diagnostica (titolo, dettaglio e il comando che installa ciò che manca, con «Copia»), anche mentre è disattivato. Una volta installato ciò che manca (e, se Apache si trova in una posizione non standard, impostato **File di configurazione di Apache** e salvate le impostazioni), premi **Riconfigura**: localSIEM lo cerca di nuovo con le impostazioni salvate.

- Se trova tutto, sblocca l'interruttore ma non attiva il modulo: lo attivi tu con il suo interruttore. Mostra anche il comando per root della sezione 2: eseguilo, perché i log creati dopo l'installazione del modulo (`/var/log/apache2`) possono essere letti solo con l'accesso in lettura che concede root.
- Se manca ancora qualcosa, i requisiti lo mostrano di nuovo.
- Se il modulo è già attivato, Riconfigura rileva anche di nuovo le sue sorgenti ed esegue la sua diagnostica.

Un modulo attivato che in seguito perde i suoi requisiti (qualcuno disinstalla ModSecurity) resta attivato: lo segnalano la sua diagnostica e l'avvertenza di salute «ModSecurity is no longer loaded» (sezione 15), e disattivarlo metterebbe a tacere proprio quell'avvertenza. Il collettore verifica i requisiti all'avvio e quando cambiano le sue impostazioni, mai periodicamente; li mostrano anche `manage.py modules` e `manage.py doctor` (sezione 17).

**Disattivare e riattivare il modulo di Apache.** In **Moduli › Installati**, usa l'interruttore di «Apache + ModSecurity» e conferma. Mentre è disattivato, localSIEM non legge i log di Apache, non ne esegue la diagnostica né le regole e non ne invia avvisi; gli eventi già salvati possono ancora essere cercati. Riattiva l'interruttore per riprendere (possibile solo finché Apache e ModSecurity sono presenti): il collettore prosegue dalla posizione in cui si era fermato in ogni log (seguendo le rotazioni avvenute nel frattempo), quindi legge anche ciò che Apache ha scritto mentre il modulo era disattivato e invia gli eventuali avvisi che ne derivano.

**Impostazioni del modulo di Apache** (Moduli › Installati › Apache + ModSecurity › Configura):

| Impostazione | Uso |
|---|---|
| Solo le sorgenti qui sotto | Non rilevare i log dalla configurazione di Apache: leggere solo le sorgenti aggiunte a mano |
| Sorgenti aggiunte a mano | Log da leggere oltre a quelli rilevati (vedi più sotto) |
| File di configurazione di Apache | Vuoto: viene individuato automaticamente (`/etc/apache2/apache2.conf` su Debian, `/etc/apache2/httpd.conf` su Alpine). Anche Riconfigura cerca Apache lì |
| Intervallo di rilevamento (secondi) | Ogni quanto si rilegge la configurazione di Apache per trovare nuovi vhost e log (predefinito 3600) |
| Soglia di blocco di ModSecurity | 0: letta dalla configurazione del CRS (`tx.inbound_anomaly_score_threshold`), 5 se non è presente |
| Giorni di apprendimento per i nuovi file PHP | Durante i primi giorni un file PHP mai visto prima non viene segnalato come nuovo (regola `apache-webshell`; predefinito 3) |

**Aggiungere un log a mano.** In **Sorgenti aggiunte a mano**, premi «Aggiungi sorgente» e compila **Tipo** (access.log, error.log o Log di audit di ModSecurity), **Percorso** (assoluto) e, se serve, **Vhost**, **LogFormat** (per un access log in un formato proprio), **Tipo di log di audit** (Seriale o Concorrente) e **Cartella di archiviazione dell'audit** (per un log di audit concorrente). «Rimuovi» elimina una sorgente. Premi «Salva le impostazioni»: il collettore rileva subito di nuovo le sorgenti e il nuovo log compare in **Sorgenti**. Se risulta illeggibile, dai a `localsiem` l'accesso in lettura alla sua cartella (sezione 3.7).

**Dal modulo `apache` ad `apache2`.** Fino a localSIEM 2.1 il modulo di Apache si chiamava `apache`; ora è `apache2` (cartella `mod-apache2/` nel repository, installato in `/opt/localsiem/modules/apache2/`, pagina `/admin/dashboard/modules/installed/apache2/`). Su un server che aveva `apache`, installare `apache2` li lascia caricati entrambi: quello vecchio tiene i log di Apache (entrambi trovano le stesse sorgenti), `apache2` non mostra sorgenti finché quello vecchio non viene disinstallato, e le impostazioni di `apache` non si spostano da sole. Per migrare:

1. Annota le impostazioni che hai cambiato nella pagina del modulo `apache` (Configura): sorgenti aggiunte a mano, file di configurazione di Apache, intervallo di rilevamento, soglia di blocco, giorni di apprendimento.
2. Installa `apache2` in Moduli › Installabili.
3. Disinstalla il modulo `apache`: **Disinstalla**, nella sua riga in Moduli › Installati o nella sua pagina. Il collettore si riavvia e da quel momento `apache2` legge i log di Apache.
4. Apri la pagina di `apache2`, inserisci di nuovo quelle impostazioni e salvale. (In alternativa, come root, puoi copiare in `/opt/localsiem/config/settings.json`, dentro `"modules"`, ciò che si trova sotto `"apache"` in `"apache2"`, e poi riavviare localSIEM.)

Le regole mantengono i loro id (`apache-bruteforce`…) e le loro modifiche, e vengono mantenute le posizioni lette in ogni log e la memoria delle avvertenze di salute: `apache2` prosegue da dove si era fermato `apache`, senza leggere nulla due volte. Gli eventi salvati dal modulo `apache` restano ricercabili (`module:apache`).

<a id="administration"></a>
## 14. Amministrazione

Queste schede ci sono solo nella dashboard dell'amministratore:

- **Moduli** (sezione 13), in due sezioni: **Installati** (`/admin/dashboard/modules/installed/`), l'elenco con l'interruttore di ogni modulo, **Configura** (requisiti e Riconfigura, impostazioni, sorgenti, diagnostica e regole del modulo), **Aggiorna** (quando il repository ha una versione più recente) e **Disinstalla**; e **Installabili** (`/admin/dashboard/modules/installable/`), i moduli del repository non ancora installati, con **Requisiti** e **Installa**. I moduli si installano, si aggiornano e si disinstallano solo lì.
- **Utenti › Account** (`/admin/dashboard/users/accounts/`): crea account (viene generata una password mostrata una sola volta; deve essere cambiata al primo accesso), reimposta la password o la verifica in due passaggi, attiva o disattiva, cambia il ruolo, elimina. C'è sempre almeno un amministratore attivo.
- **Utenti › Token di accesso** (`/admin/dashboard/users/tokens/`): **Crea token** per un account analista attivo (gli amministratori accedono sempre con la loro password, e con il secondo fattore quando la verifica in due passaggi è attivata), con un'etichetta facoltativa e una validità di 7, 30, 90 (predefinito), 180 o 365 giorni. L'URL di accesso, `https://<server>:10443/auth/login/auto?token=...`, viene mostrato **una sola volta**, con un pulsante «Copia»: dallo all'analista (sezione 6). L'elenco mostra di ogni token l'account e l'etichetta, i suoi ultimi 4 caratteri, il suo stato (Attivo, Scaduto, Revocato, o Inutilizzabile quando l'account è disattivato o non è più un analista), quando e da chi è stato creato, quando scade e il suo ultimo utilizzo (ora e IP). **Revoca** lo blocca subito; le sessioni che ha già aperto terminano alla loro scadenza. Una sessione aperta con un token non chiede né il secondo fattore né un cambio di password. I tentativi falliti contano per il blocco temporaneo dell'accesso.
- **SOC**: URL, token (mai mostrato per intero), file della CA facoltativo, **Prova la connessione** (invia un heartbeat), stato dell'invio, ultimo heartbeat, ultimo errore, coda (in attesa, inviati, rifiutati) e **Invia ora la coda**. Anche l'indirizzo del SIEM da dare al SOC. Il SOC è facoltativo (sezione 5).
- **Canali** (`/admin/dashboard/channels/`), in due sezioni, **Generale** (si apre per impostazione predefinita) e **Telegram**: i messaggi che localSIEM ti invia, oltre agli avvisi che consegna al SOC (più sotto).
- **Impostazioni**: conservazione, disco massimo, IP consentiti (il tuo indirizzo deve essere nell'elenco), verifica in due passaggi (disattivata per impostazione predefinita; attivarla la rende obbligatoria per ogni account e disconnette subito gli account che non l'hanno ancora configurata, compreso il tuo, che la configurano al loro prossimo accesso; disattivarla mantiene le app di autenticazione già configurate per quando verrà riattivata), tempo massimo di una ricerca, limite delle esportazioni, finestra e buffer di raggruppamento, finestra di correlazione e gravità sotto la soglia. Le modifiche si applicano subito. Le regole non sono più qui: si configurano in ogni modulo (Moduli › Installati › Configura).
- **Audit delle ricerche**: chi ha cercato cosa e quando.
- **Accessi** (`/admin/dashboard/logins/`): ogni accesso a localSIEM e ogni tentativo fallito, dai più recenti: ora, account, metodo (Password, Password e secondo fattore, o Token di accesso), esito (Riuscito o Fallito), il motivo di un fallimento (nome utente o password errati, codice del secondo fattore errato, bloccato dopo diversi tentativi falliti, l'accesso ha richiesto troppo tempo, token sconosciuto, scaduto o revocato, account disattivato, l'account non è di tipo analista), IP e browser. Filtra per esito; **Carica altri** carica quelli più vecchi. Vengono conservati quanto gli avvisi (365 giorni per impostazione predefinita).

Lo stato del collettore, del disco e del database è nella Panoramica (sezione 8).

### Canali: messaggi per te (Telegram)

Oltre a consegnare ogni avviso al SOC, localSIEM può inviarti i più importanti tramite un **canale**. Per ora il canale è **Telegram**.

**Generale** (`/admin/dashboard/channels/general/`):

- **Invia messaggi tramite i canali**: attiva o disattiva tutti i canali in una volta.
- **Gravità minima**: vengono inviati gli avvisi di questa gravità o superiore (predefinita: Alta).
- **Lingua dei messaggi**: una qualsiasi delle 15 lingue dell'interfaccia web (predefinita en-US). La regola e la descrizione dell'avviso restano come le ha scritte localSIEM.
- Una tabella con ogni canale: il suo stato (Disattivato, Non configurato, Funzionante o Errore), i messaggi inviati, l'ultimo e l'ultimo errore.

**Telegram** (`/admin/dashboard/channels/telegram/`):

1. In Telegram, apri **@BotFather**, invia `/newbot` e segui i suoi passaggi. Ti fornisce il **token del bot** (`123456789:AA...`; il numero prima dei due punti è l'id del bot).
2. Apri la chat con il tuo bot e premi **Avvia** (oppure aggiungi il bot al gruppo, o come amministratore del canale, che riceverà i messaggi): un bot non può scrivere a chi non gli ha scritto prima.
3. Trova l'**id della chat**: invia un messaggio qualsiasi al bot e apri `https://api.telegram.org/bot<token>/getUpdates` in un browser; l'id è il numero dopo `"chat":{"id":`. L'id di un gruppo inizia con `-` e quello di un canale con `-100`; un canale o un gruppo pubblico può anche essere indicato come `@username`.
4. Scrivi il token e l'id della chat, spunta **Invia i messaggi tramite Telegram** e premi **Salva e invia un messaggio di prova**. Se Telegram lo rifiuta, la notifica dice perché (per esempio `Unauthorized`: token errato; `Bad Request: chat not found`: id della chat errato, o nessuno ha premuto Avvia).

Il token viene conservato sul server in `/opt/localsiem/config/telegram-bot-token` (modo 600) e non viene mai mostrato per intero; **Rimuovi il token** lo elimina e disattiva Telegram. Il server deve poter raggiungere `https://api.telegram.org` (porta 443 in uscita).

Ogni messaggio indica la gravità, la regola, la descrizione, il modulo, il numero di eventi, la prima e l'ultima volta (UTC) e la ricerca che li mostra. localSIEM invia al massimo un messaggio al secondo. Se Telegram non risponde, riprova alcune volte; se Telegram rifiuta un messaggio (token errato, chat sconosciuta, bot bloccato), lo scarta e mostra l'errore. I messaggi in attesa vanno persi se localSIEM si riavvia: i canali sono una notifica per te, e il SOC riceve comunque ogni avviso.

<a id="health"></a>
## 15. Avvertenze di salute e cosa fare

Anche queste vanno al SOC (regole `localSIEM health: …`), raggruppate perché non si ripetano:

| Avvertenza | Gravità | Cosa fare |
|---|---|---|
| Log troncato, scomparso o sostituito al di fuori di una rotazione | alta | Qualcuno potrebbe stare cancellando le tracce. Verifica chi aveva accesso al server in quel momento e gli altri suoi log. |
| ModSecurity non più caricato, o motore impostato su Off | alta | Se nessuno lo ha fatto di proposito, la protezione è stata disattivata: controlla la configurazione di Apache e le sue modifiche recenti. |
| Sorgente di log non leggibile | media | Di solito sono i permessi dopo una rotazione: esegui di nuovo come root il comando della sezione 2 (`manage.py setup-modules`) o dai a `localsiem` l'accesso in lettura (sezione 3.7). La genera solo un log che localSIEM prima poteva leggere: uno che non ha mai potuto leggere (un modulo appena installato, prima del comando della sezione 2) compare solo nello stato del modulo («Errore», una sorgente non può essere letta). |
| Sorgente di log silenziosa da molto tempo (24 h) | media | Verifica che Apache scriva ancora quel file (modifiche alla registrazione, disco pieno). |
| IP reale del client mancante | media | Quasi tutte le richieste arrivano da un unico indirizzo privato: il web è dietro un proxy e Apache ne registra l'IP, quindi le regole per IP non funzionano per quelle richieste. |
| Molte righe non analizzate (più del 5 %) | bassa | Il formato del log è cambiato: nella pagina del modulo (Moduli › Installati › Configura) premi «Rileva di nuovo ed esegui la diagnostica», così il modulo legge il nuovo formato; la diagnostica descrive il formato di ogni log. |
| Poco spazio libero su disco, o conservazione ridotta per mancanza di spazio | media | Libera spazio o aumenta la dimensione massima su disco. Nel frattempo localSIEM salva meno dettagli. |

<a id="retention"></a>
## 16. Conservazione e disco

Gli eventi vengono conservati 90 giorni e gli avvisi 365 giorni. Il database non cresce mai oltre il suo massimo (predefinito: il minore tra il 15 % del disco e 10 GB): gli eventi più vecchi vengono eliminati per primi, in piccoli lotti, e lo spazio torna al disco. Con poco spazio libero su disco localSIEM smette di salvare i dettagli voluminosi (intestazioni e corpi dei record di audit); quasi senza spazio, salva solo gli eventi che fanno parte di un avviso, e avvisa il SOC. Cambia i valori con `--retention-days` e `--max-disk` (per esempio `--max-disk 5G`) o in Amministrazione › Impostazioni.

<a id="cli"></a>
## 17. Riga di comando

Come root, `/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py`:

| Comando | Uso |
|---|---|
| `list-users` | Account e la loro verifica in due passaggi |
| `create-user NAME --role admin\|analyst --credentials /root/webapp-credentials.txt` | Nuovo account con una password generata |
| `reset-password NAME --credentials /root/webapp-credentials.txt` | Nuova password (da cambiare al prossimo accesso) |
| `reset-mfa NAME` | Verifica in due passaggi da configurare di nuovo al prossimo accesso |
| `doctor` (`--json`) | Requisiti e sorgenti di ogni modulo attivato e, per un modulo disattivato che ha requisiti, ciò di cui ha bisogno prima di poter essere attivato (eseguilo come `localsiem`, sezione 4) |
| `modules` | Moduli installati: nome, versione, attivato, disattivato o non caricato, cartella, e sotto un modulo i requisiti che mancano al server per esso; e i moduli che non possono essere caricati, con il motivo |
| `read-paths` | Cartelle che i moduli installati leggono (`setup-modules` e l'installer danno a `localsiem` l'accesso in lettura a esse) |
| `soc-test` | Invia un heartbeat al SOC |
| `setup-modules` | Come root, il comando che l'interfaccia web mostra dopo l'installazione di un modulo, dopo un aggiornamento che cambia i log che il modulo legge, e con Riconfigura: accesso in lettura per `localsiem` alle cartelle dei moduli installati (ACL, anche per le rotazioni successive; il gruppo `adm` su Debian), un riavvio di localSIEM e la diagnostica come `localsiem`. Con `--no-restart` (quello che usa l'installer) concede solo l'accesso in lettura. |

I moduli si installano, si aggiornano e si disinstallano solo dall'interfaccia web (sezione 13): non c'è alcun comando per farlo.

Servizi: localSIEM funziona come due servizi dell'utente di sistema `localsiem`, il collettore (`localsiem`) e l'interfaccia web (`localsiem-web`). `systemctl status localsiem localsiem-web` li mostra e `systemctl restart localsiem localsiem-web` li riavvia (Debian), oppure `rc-service localsiem status; rc-service localsiem-web status` e `rc-service localsiem restart; rc-service localsiem-web restart` (Alpine); riavviali entrambi dopo aver copiato o eliminato a mano un modulo in `/opt/localsiem/modules/` (l'interfaccia web lo fa da sola quando ne installa, aggiorna o disinstalla uno). Log: `journalctl -u localsiem -u localsiem-web` (Debian) o `/opt/localsiem/log/` (Alpine); all'avvio il collettore registra la riga `Modules: ...` con ogni modulo, la sua versione e se è attivato o disattivato, e `Module <name>: requirements missing: ...` per un modulo i cui requisiti mancano.

**File sul server**

| Percorso | Contenuto |
|---|---|
| `/opt/localsiem/webapp/` | Codice del nucleo |
| `/opt/localsiem/modules/` | Moduli installati, una cartella ciascuno (`apache2/`), installati dall'interfaccia web da `localSIEM-modules` |
| `/opt/localsiem/venv/` | Dipendenze Python (separate da quelle del sistema) |
| `/opt/localsiem/config/` | Impostazioni, opzioni dell'installer (`install.env`), token del SOC e segreti (modo 600) |
| `/opt/localsiem/db/` | Database |
| `/opt/localsiem/certificates/` | Certificato dell'interfaccia web |
| `/opt/localsiem/log/`, `/opt/localsiem/run/` | Log (Alpine) e file di runtime |
| `/root/webapp-install.log`, `/root/webapp-credentials.txt` | Log dell'installer e password che ha creato (modo 600) |
