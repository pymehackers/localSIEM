# Benutzerhandbuch von localSIEM

Dieses MANUAL ist auch verfügbar in:\
de-DE, [en-GB](MANUAL.en-GB.md), [en-US](MANUAL.md), [es-AR](MANUAL.es-AR.md), [es-ES](MANUAL.es-ES.md), [fr-FR](MANUAL.fr-FR.md), [he-IL](MANUAL.he-IL.md), [hi-IN](MANUAL.hi-IN.md), [it-IT](MANUAL.it-IT.md), [ja-JP](MANUAL.ja-JP.md), [ko-KR](MANUAL.ko-KR.md), [pt-BR](MANUAL.pt-BR.md), [pt-PT](MANUAL.pt-PT.md), [ru-RU](MANUAL.ru-RU.md), [zh-CN](MANUAL.zh-CN.md)

[Installation](README.de-DE.md) · [Code-Referenz](CODE.de-DE.md)

## Inhalt

1. [Was localSIEM tut](#what)
2. [Installation](#installation)
3. [Voraussetzungen für Apache und ModSecurity](#requirements)
4. [Die Diagnose](#doctor)
5. [Verbindung mit dem SOC](#soc)
6. [Anmeldung und Konten](#signin)
7. [Die beiden Dashboards](#dashboards)
8. [Übersicht](#overview)
9. [Suche](#search)
10. [Die Detailansicht der Anfrage und die Pivots](#card)
11. [Live-Ansicht](#live)
12. [Alarme](#alerts)
13. [Module](#modules)
14. [Administration](#administration)
15. [Warnungen zum Systemzustand und was zu tun ist](#health)
16. [Aufbewahrung und Datenträger](#retention)
17. [Kommandozeile](#cli)

<a id="what"></a>
## 1. Was localSIEM tut

localSIEM überwacht die Dienste des Servers, auf dem es installiert ist, über **Module**, eines pro Dienst. Es liest nur die Logs dieses Servers: Es empfängt keine Logs von anderen Maschinen. Das Modul **Apache + ModSecurity** überwacht die Apache-Website: Für jede Anfrage führt es drei Einträge zusammen, die Zeile von `access.log`, die Zeilen von `error.log` und den Eintrag des Audit-Logs von ModSecurity, und zwar anhand der `UNIQUE_ID` der Anfrage. Alles wird gespeichert, damit es durchsucht werden kann. Danach entscheidet localSIEM, was an das SOC gehen muss.

localSIEM läuft auf demselben Debian- oder Alpine-Server, den es schützt, neben dessen Website, als zwei Dienste des Systembenutzers `localsiem`. Seine eigene Weboberfläche lauscht auf Port 10443: Es verwendet nie die Ports 80 oder 443 und rührt die Website des Servers nie an. Neben dem SOC (optional, Abschnitt 5) kann es Ihnen die wichtigsten Alarme über **Telegram** senden (Abschnitt 14), und es stellt dem Analysten des SOC ein **Suchwerkzeug** bereit, ein Suchfeld und einen Zeitraum (Abschnitt 9). Es lässt nie Passwörter, Cookies, Token oder Anfrage-Bodys den Server verlassen, verbraucht wenig Arbeitsspeicher (etwa 100 MB im Normalbetrieb, etwa 200 MB in Spitzen) und füllt nie den Datenträger (Abschnitt 16).

**Nur was noch niemand erledigt hat, geht an das SOC.**

| Situation | Geht es an das SOC? |
|---|---|
| ModSecurity hat die Anfrage in den Phasen 1–2 blockiert (bevor die Anwendung sie erhalten hat) | **Nein.** Sie bleibt in localSIEM, ist durchsuchbar und erscheint als Zählwert im nächsten Alarm dieser IP. |
| ModSecurity hat die Antwort in den Phasen 3–4 blockiert (die Anwendung hatte die Anfrage bereits ausgeführt) | Ja |
| Regeltreffer mit ModSecurity in `DetectionOnly` (nichts wird blockiert) | Ja |
| Regeltreffer unterhalb des Blockierungsschwellenwerts | Ja, mit Schweregrad `low` |
| Signale der Regeln von localSIEM (Brute Force, Web Shell, sensible Datei, Enumeration, Datenbankfehler) | Ja |
| Probleme des Systemzustands und mögliches Löschen von Spuren | Ja |

**Schweregrad dessen, was an das SOC geht**

| Situation | Schweregrad |
|---|---|
| Nicht blockierte Regeltreffer, Antwort 3xx, 4xx oder 5xx | mittel |
| Nicht blockierte Regeltreffer, Antwort 2xx | hoch |
| In den Phasen 3–4 blockiert | hoch |
| Anzeichen eines Erfolgs: nicht blockierte Datenleck- oder Web-Shell-Regel (950–955), SQL-Fehler unmittelbar danach, POST mit 2xx an eine neue `.php`-Datei | kritisch |
| Unterhalb des Blockierungsschwellenwerts (oft Fehlalarme der Anwendung) | niedrig (konfigurierbar in Einstellungen) |

**Gruppierung.** Ein Alarm pro Modul, vhost, IP, Kategorie und Schweregrad in einem Zeitfenster von 10 Minuten. Ein kritischer Alarm geht sofort hinaus; die anderen warten 60 Sekunden, um die Häufung zu sammeln, und gehen mit dem Zählwert hinaus. Ein Scanner, der Tausende von Anfragen sendet, erzeugt einige wenige Alarme, nicht Tausende. Steigt der Schweregrad (zum Beispiel, weil derselbe Angriff jetzt 200-Antworten erhält), ist das ein weiterer Alarm.

**Was nie an das SOC geht:** Anfrage- oder Antwort-Bodys, Cookies, `Authorization`-Header, Passwörter oder Token – nicht einmal maskiert – und was bereits in den Phasen 1–2 blockiert wurde (nur als Zählwert). localSIEM maskiert sensible Werte (`password`, `pass`, `pwd`, `passwd`, `token`, `secret`, `api_key`, `apikey`, `auth`, `session` und die Header `Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, `Proxy-Authorization`) mit `***`, bevor es irgendetwas speichert.

**Module.** Der Kern von localSIEM (Speicherung, Suche, Regeln, Gruppierung, Zustellung an das SOC, Systemzustand) ist für jeden Dienst derselbe; jedes Modul fügt hinzu, was für einen bestimmten Dienst spezifisch ist. Das Modul Apache + ModSecurity (`apache2`) stammt aus dem Repository `localSIEM-modules` (GitHub) und wird ausschließlich über die Weboberfläche installiert, aktualisiert und deinstalliert, nie durch den Installer von localSIEM; seine Installation installiert nie Apache oder ModSecurity. Jedes Modul wird auf dieselbe Weise installiert, aktualisiert und deinstalliert: über die Weboberfläche. Abschnitt 13 erklärt, wie Sie Module installieren und aktualisieren, ihren Zustand ansehen, sie aktivieren und deaktivieren und sie konfigurieren.

<a id="installation"></a>
## 2. Installation

Die Installation erfolgt in zwei Schritten: zuerst der Kern von localSIEM und danach seine Module (Schritt 2 unten). Führen Sie als root direkt von GitHub aus:

```bash
# Debian 13
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
# Alpine 3.24 (zuerst: apk add bash curl)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
```

Die Weboberfläche von localSIEM lauscht immer auf **Port 10443 mit HTTPS**: Der Installer prüft, ob der Port frei ist, und bricht ab, wenn ein anderer Dienst ihn verwendet. Die Aktion und die Optionen stehen nach `bash -s --`. Der Installer prüft, was er benötigt (Python 3.13 mit `venv`, OpenSSL, die CA-Zertifikate, die ACL-Werkzeuge, logrotate, curl, tar), und installiert, was fehlt. So über eine Pipe ausgeführt, lädt er den Branch `main` von `https://github.com/PYMEHackers/localSIEM` herunter; aus einer Kopie des Projekts ausgeführt (`bash deploy/install-update-reinstall-debian.sh --install`), installiert er diese Kopie.

**Die Aktion.** Der Installer benötigt immer eine Aktion; ohne sie bricht er ab und listet die Aktionen auf:

| Aktion | Verwendung |
|---|---|
| `--install` | Installiert localSIEM auf einem Server, auf dem es nicht vorhanden ist. Findet er irgendetwas von localSIEM (`/opt/localsiem`, seine Dienste oder seinen Benutzer `localsiem`, auch von einer Installation, die auf halbem Weg fehlgeschlagen ist), bricht er ab und verweist auf `--update` und `--reinstall`. |
| `--update` | Aktualisiert das installierte localSIEM: Seine Daten, Konten, Einstellungen, Module und die zuvor angegebenen Optionen (siehe unten) bleiben erhalten. |
| `--reinstall [--yes]` | Löscht das installierte localSIEM mit allen seinen Daten, wie es `--uninstall` tut (siehe unten), und installiert es von Grund auf neu, mit neuen Passwörtern. Zuvor werden Sie aufgefordert, `yes` einzugeben (`--yes` fragt nicht; ohne Terminal ist es erforderlich), und es wird nichts gelöscht, bevor die neue Kopie heruntergeladen und die Optionen geprüft sind. Die Optionen der vorherigen Installation werden nicht beibehalten: Geben Sie sie erneut an. |
| `--uninstall [--yes]` | Löscht localSIEM und alle seine Daten vom Server (siehe unten). Wird allein verwendet. |

`--update` und `--reinstall` brechen ab, wenn localSIEM nicht installiert ist: Verwenden Sie `--install`.

Optionen von `--install`, `--update` und `--reinstall`:

| Option | Verwendung |
|---|---|
| `--allow-from LIST` | IPs und CIDR, die die Weboberfläche öffnen dürfen, durch Kommas getrennt: das SOC und Ihre Administratoren |
| `--soc-url URL` | Standard: `https://soc.pymehackers.com` |
| `--soc-token TOKEN` | Ingestion-Token dieses Kunden im SOC. Optional: Ohne SOC arbeitet localSIEM eigenständig (Abschnitt 5) |
| `--soc-ca-file PATH` | Nur für ein SOC mit privatem Zertifikat (Testserver) |
| `--domain NAME` | Name des Servers, für das Zertifikat und die SIEM-Adresse (Standard: sein Hostname) |
| `--certificate PATH --private-key PATH` | Zu verwendendes Zertifikat. Ohne diese Optionen kopiert localSIEM das Zertifikat von Let's Encrypt für `--domain`, falls es eines gibt (und kopiert es bei jeder Erneuerung erneut), oder erstellt ein selbstsigniertes. |
| `--retention-days N`, `--max-disk SIZE` | Aufbewahrung (Abschnitt 16) |
| `--enable-mfa`, `--disable-mfa` | Zwei-Faktor-Authentifizierung aktiviert (verpflichtend für alle Konten) oder deaktiviert. Ohne diese Optionen ist sie bei einer neuen Installation deaktiviert, und eine Aktualisierung behält bei, was unter Administration › Einstellungen gewählt wurde (Abschnitt 14). |
| `--rotate-credentials` | Erstellt ein neues Geheimnis zum Signieren der JWT und schreibt es in `/root/webapp-credentials.txt` |
| `--ref REF` | Branch oder Tag von localSIEM, der heruntergeladen wird (Standard: `main`) |
| `--source-url URL` | Archiv (`.tar.gz`) von localSIEM, das anstelle des Archivs von GitHub installiert wird (ein Mirror) |
| `--modules-repository URL`, `--modules-ref REF` | Repository (oder `.tar.gz`-Archiv) und Branch oder Tag, aus denen die Weboberfläche Module installiert und aktualisiert (Abschnitt 13). Standard: `https://github.com/PYMEHackers/localSIEM-modules`, Branch `main`. |

**Immer die neueste Version.** GitHub hält die Dateien von `raw.githubusercontent.com` nach jeder Änderung bis zu 5 Minuten in einem Cache, daher lesen die obigen Befehle den Installer über die GitHub-API, die keinen Cache hat; der Installer fragt dann diese API, auf welchem Commit der Branch steht, lädt genau diesen Commit herunter und bittet jeden Server auf dem Weg, nicht mit einer zwischengespeicherten Kopie zu antworten. Ohne Token erlaubt GitHub 60 API-Anfragen pro Stunde und IP-Adresse: Lehnt GitHub ab, schlägt der Befehl mit `403` fehl (warten Sie und führen Sie ihn erneut aus); schlägt nur die Abfrage des Installers fehl, gibt der Installer eine Warnung aus und lädt den Branch herunter.

Die Optionen werden in `/opt/localsiem/config/install.env` gespeichert: `--update` ohne Optionen behält sie bei. Zum Aktualisieren:

```bash
# Debian 13 (Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --update
```

Das Log des Installers ist `/root/webapp-install.log`, und die Passwörter, die er erstellt, stehen in `/root/webapp-credentials.txt` (beide mit Modus 600). Er zeigt seinen Fortschritt in nummerierten Schritten an (`[3/12] Getting localSIEM`), mit `✓` für Erledigtes, `!` für Warnungen, `✗` für Fehlschläge und `·` für Informationen, auf einem Terminal in Farbe (`NO_COLOR=1` oder `LOCALSIEM_COLOR=never` schalten die Farben ab). Die Ausgabe von apt-get oder apk, curl, tar und pip geht nur in das Log; schlägt eines dieser Programme fehl, zeigt der Bildschirm seine letzten 20 Zeilen. Das Log erhält dieselben Zeilen, ohne Farben, mit den Zeiten im Speicherformat. Am Ende führt er die Diagnose jedes aktivierten Moduls aus (Abschnitt 4) und zeigt eine Zusammenfassung: die Adresse der Weboberfläche, die zugleich die SIEM-Adresse ist, die Sie dem SOC mitteilen, die Datei mit den Zugangsdaten, das Log und den Zustand des SOC, gefolgt von den nächsten Schritten. Schlägt er fehl, gibt er an, bei welchem Schritt er angehalten hat.

**Deinstallation.** `--uninstall` löscht localSIEM vom Server: Dabei werden seine Dienste gestoppt und entfernt und `/opt/localsiem` gelöscht (Code, Einstellungen, die Datenbank mit jedem Ereignis und jedem Alarm, Zertifikate und Module), ebenso der Benutzer `localsiem`, der Lesezugriff auf die Logs, den `setup-modules` gewährt hat, die Apache-Konfiguration (`localsiem.conf`), die die Option `--configure-apache` älterer Versionen des Apache-Moduls (1.2.0 oder früher) hinzugefügt hat, mit einem configtest und einem Reload von Apache, die logrotate-Datei, der Hook für Let's Encrypt und die Einträge von localSIEM in `/root/webapp-credentials.txt` (die Datei wird gelöscht, wenn nichts anderes darin übrig bleibt). Zuvor werden Sie aufgefordert, `yes` einzugeben (`--yes` fragt nicht; ohne Terminal ist es erforderlich). Ist nichts von localSIEM auf dem Server vorhanden, meldet der Installer «Nothing of localSIEM was found on this server.». Das Log des Installers, die Pakete, die der Installer hinzugefügt hat, `mod_unique_id` (Debian) und die Logs von Apache bleiben erhalten, auch das `localsiem_access.log`, das Apache wegen dieser Datei geschrieben hat, und `modsec_audit.log`: localSIEM ändert oder löscht nie ein Log von Apache. Zum Deinstallieren:

```bash
# Debian 13 (Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --uninstall
```

**Neuinstallation.** Um in einem Schritt von Grund auf neu zu beginnen, löscht `--reinstall` alles auf dieselbe Weise und installiert localSIEM erneut (geben Sie die Optionen erneut an):

```bash
# Debian 13 (Alpine: install-update-reinstall-alpine.sh)
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --reinstall --allow-from 203.0.113.10 --soc-token TOKEN
```

**2. Die Module.** Der Installer von localSIEM installiert **kein Modul**: Er bereitet localSIEM für sie vor, und eine Aktualisierung behält die bereits installierten bei (und den Lesezugriff auf ihre Logs). Module werden **ausschließlich über die Weboberfläche** installiert: unter Module › Installierbar (Abschnitt 13), wo die Module des Repositorys `localSIEM-modules` aufgeführt sind, die noch nicht installiert sind; dieses Repository hat keinen eigenen Installer. localSIEM lädt das Modul von dort herunter, kopiert seinen Ordner (dort `mod-<name>/`) nach `/opt/localsiem/modules/<name>/` (die Ordner `tests/` werden nicht kopiert; ein erneut installiertes Modul erhält die Einstellungen zurück, die es hatte) und startet den Collector neu. Module werden ebenfalls über die Weboberfläche aktualisiert und deinstalliert: **Aktualisieren**, wenn das Repository eine neuere Version hat, und **Deinstallieren**, beide unter Module › Installiert (Abschnitt 13).

Das Lesen der Logs eines Moduls erfordert root, daher zeigt die Weboberfläche nach der Installation des Moduls in einem Dialog den Befehl an, der als root auf dem Server auszuführen ist:

```bash
/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py setup-modules
```

Er gibt dem Benutzer `localsiem` Lesezugriff auf die Log-Ordner, die jedes installierte Modul angibt (`/var/log/apache2` für das Apache-Modul; Abschnitt 3.7), auch auf die Dateien der nächsten Rotationen, startet localSIEM neu und führt die Diagnose als `localsiem` aus. Er kann jederzeit erneut ausgeführt werden. Dieser Lesezugriff, den localSIEM gewährt, ist alles, was root für die Module tut.

**Die Installation eines Moduls installiert nie die Software, die es überwacht**, und auch sonst nichts: Ein Modul arbeitet mit dem, was der Server bereits hat, und ändert nie etwas außerhalb von `/opt/localsiem/`. Ein neues Modul startet aktiviert oder deaktiviert, wie sein Autor es entschieden hat, außer wenn dem Server fehlt, was es benötigt (für das Apache-Modul: Apache und ModSecurity 2): Dann wird es **deaktiviert** installiert, die Weboberfläche gibt an, was fehlt, und sein Schalter bleibt gesperrt, bis **Neu konfigurieren** es findet (Abschnitt 13). Sein Zustand steht unter **Module › Installiert** (Abschnitt 13).

<a id="requirements"></a>
## 3. Voraussetzungen für Apache und ModSecurity

Dies sind die Voraussetzungen des Moduls Apache + ModSecurity. Apache und ModSecurity 2 selbst müssen zuerst installiert sein: Ohne sie kann das Modul nicht aktiviert werden (Abschnitt 13). localSIEM ändert nie von sich aus die Apache-Konfiguration, die Logs von Apache, ihr Format oder die Art, wie sie geschrieben werden: Das Modul liest die Logs, die der Server bereits schreibt, und passt sich ihnen an. Die Diagnose des Moduls (Abschnitt 4) prüft jede Voraussetzung: Für ModSecurity mit seinem CRS und `SecRuleEngine` (Punkt 1), `mod_unique_id` (Punkt 2) und den Lesezugriff (Punkt 7) zeigt sie für jede fehlende Voraussetzung genau das Snippet oder den Befehl an, den Sie anwenden müssen; die Logs (Punkte 3 bis 6) beschreibt sie nur, ohne vorzuschlagen, sie zu ändern.

1. **ModSecurity 2 mit OWASP CRS**, mit `SecRuleEngine On` oder `DetectionOnly`. Beides funktioniert: Mit `DetectionOnly` wird nichts blockiert, daher geht jeder Treffer an das SOC.
2. **`mod_unique_id`**, das ModSecurity 2 überhaupt zum Funktionieren benötigt (ohne es prüft ModSecurity nichts; Alpine lädt es standardmäßig nicht) und das die drei Einträge jeder Anfrage zusammenführt.
3. **Ein Access-Log**, so wie Apache es schreibt. Jedes Format funktioniert (`combined`, `vhost_combined`, `common` oder jedes `LogFormat` der Konfiguration): Jede Zeile wird ihrer Anfrage anhand von Client-IP, Methode, URI, Status und Zeit zugeordnet («schwache Korrelation»), und der vhost stammt aus `%v` oder, ohne dieses, aus dem Host-Header und dem Port des Audit-Eintrags. Enthält das Format außerdem Millisekunden, `%v` und `%{UNIQUE_ID}e` (wie die `localsiem_combined`-Zeilen, die manche Server bereits schreiben), wird jede Zeile ihrer Anfrage anhand der `UNIQUE_ID` zugeordnet, und mit `%D` erhält localSIEM auch ihre Dauer. Ein Access-Log, dessen Format die Client-IP, die Zeit, die Anfragezeile oder den Status nicht enthält, wird so gelesen, wie es ist, aber seine Zeilen können ihren Anfragen nicht zugeordnet werden: Diese Anfragen sind im Audit-Log von ModSecurity zu sehen. Ein `CustomLog`, dessen Format überhaupt keine Direktive enthält, schreibt in jede Zeile denselben Text und wird nicht gelesen.
4. **`mod_remoteip`**, das bestimmt, welche IP in den Logs steht. Befindet sich die Website hinter einem Proxy oder einem Load Balancer und Apache verwendet es nicht, steht in den Logs die IP des Proxys, ebenso in den Alarmen und in den Regeln nach IP: Die Diagnose und die Warnung zum Systemzustand «Real client IP missing» (Abschnitt 15) weisen darauf hin.
5. **Das Audit-Log von ModSecurity**, so wie ModSecurity es schreibt: seriell oder parallel, JSON oder nativ, mit den Teilen, die es enthält. Ohne es (`SecAuditEngine Off` oder kein `SecAuditLog`) entscheidet localSIEM nur anhand von `error.log`, und die Detailansicht der Anfrage enthält weder Header noch die Liste der Regeln. Ohne Teil `H` kann die ergriffene Aktion nicht daraus gelesen werden. Teil `E` (der Antwort-Body) geht, falls er protokolliert wird, nie an das SOC; Teil `K` (der vollständige Text jeder ausgeführten Regel) wird nicht gespeichert. Beim parallelen Typ (eine Datei pro Transaktion) erstellt ModSecurity die Dateien normalerweise mit Modus 600, und localSIEM liest sie nur, wenn `localsiem` sie lesen kann (Punkt 7).
6. **Maskierung an der Quelle**: Wenn ModSecurity das Audit-Log auf dem Datenträger nicht maskiert (seine `sanitise`-Aktionen), kann diese Datei Passwörter und Cookies enthalten; localSIEM maskiert sie, bevor es sie speichert, und sie gehen nie an das SOC.
7. **Lesezugriff für den Benutzer `localsiem`** auf die Logs. Der root-Befehl aus Abschnitt 2 (`manage.py setup-modules`) richtet ihn für die Ordner ein, die die installierten Module angeben (`/var/log/apache2` für das Apache-Modul), und der Installer von localSIEM tut dies bei jeder Aktualisierung erneut: Unter Debian fügt er `localsiem` der Gruppe `adm` hinzu und gibt, wie unter Alpine, `localsiem` über ACLs Lesezugriff auf diese Ordner, einschließlich einer Default-ACL, damit auch die Dateien der nächsten Rotationen lesbar sind. Logs, die Sie manuell in einem anderen Ordner hinzufügen (Abschnitt 13), benötigen diesen Zugriff ebenfalls, zum Beispiel `setfacl -m g:localsiem:rx /srv/logs`, `setfacl -d -m g:localsiem:r /srv/logs` und `setfacl -m g:localsiem:r /srv/logs/*.log`. localSIEM liest die Logs nur: Es schreibt nie hinein und rotiert, kürzt, verschiebt oder löscht sie nie. Wenn es beginnt, einem Log zu folgen (beim ersten Start, nach der Installation oder Aktivierung eines Moduls oder sobald root ihm Lesezugriff gibt), beginnt es an dessen Ende: Was das Log bereits enthielt, ist Historie und löst nie einen Alarm aus; nur das Log eines später erstellten vhosts wird von seinem Anfang an gelesen (wenn es bis zu 5 MB groß ist).

<a id="doctor"></a>
## 4. Die Diagnose

Jedes Modul hat seine eigene Diagnose. Die Diagnose des Apache-Moduls prüft jede Voraussetzung aus Abschnitt 3 und zeigt das Snippet oder den Befehl an, der jede fehlende Voraussetzung behebt; die Logs (Format, `mod_remoteip`, Audit-Log, Maskierung) beschreibt sie nur, ohne vorzuschlagen, sie zu ändern, und sie listet die gefundenen Quellen auf (und diejenigen, die sie nicht lesen kann, etwa Logs über Pipes). Sie wird am Ende jeder Installation von localSIEM und des root-Befehls aus Abschnitt 2 ausgeführt, erscheint auf der Seite jedes Moduls (**Module › Installiert › Konfigurieren**, Abschnitt 13, mit der Schaltfläche «Erneut erkennen und Diagnose ausführen») und kann jederzeit für jedes aktivierte Modul ausgeführt werden:

```bash
runuser -u localsiem -- /opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor   # Debian
su -s /bin/sh localsiem -c "/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor"   # Alpine
```

`✓` ist in Ordnung, `!` funktioniert mit Einschränkungen, `✗` muss behoben werden, `·` gilt nur in bestimmten Situationen (auf einem Terminal in Farbe; wo kein UTF-8 geschrieben werden kann, `+`, `!`, `x` und `-`). Ein Modul, das nicht geladen werden kann, wird zuerst als `✗ Module <name> not loaded: <reason>` angezeigt. Ein deaktiviertes Modul hat keine Diagnose: Hat es Voraussetzungen (Abschnitt 13), zeigt die Diagnose stattdessen diese an, damit Sie wissen, ob es aktiviert werden kann.

<a id="soc"></a>
## 5. Verbindung mit dem SOC

Die Verbindung von localSIEM mit einem SOC ist optional. Ohne SOC (kein Token oder **Alarme an das SOC senden** deaktiviert) arbeitet localSIEM eigenständig: Es behält jeden Alarm in der Registerkarte **Alarme** als «Nicht gesendet» und sendet diese Alarme auch später nie, nicht einmal, wenn danach ein SOC konfiguriert wird: Ab dann gehen nur die neuen Alarme dorthin. Die Kanäle (Telegram) funktionieren mit oder ohne SOC.

Der Administrator des SOC:

1. Erstellt ein Ingestion-Token für den Kunden (es wird nur einmal angezeigt) und gibt es Ihnen. Tragen Sie es mit `--soc-token` oder unter **Administration › SOC** ein.
2. Trägt als **SIEM-Adresse** des Kunden `https://<server>:<port of localSIEM>` ein (wird vom Installer und unter Administration › SOC angezeigt). Der Analyst, der einen Alarm bearbeitet, verwendet diesen Link, um hierherzukommen und zu untersuchen.
3. Gibt Ihnen die ausgehenden IPs des SOC: Fügen Sie sie zu den erlaubten IPs hinzu (`--allow-from` oder Administration › Einstellungen) und **öffnen Sie den Port in der Firewall nur für diese IPs und für Ihre Administratoren**.

localSIEM sendet alle 5 Minuten einen **Heartbeat**. Empfängt das SOC eine Zeit lang (standardmäßig 60 Minuten) weder Alarme noch Heartbeats, warnt es sein Team. Alarme warten in einer persistenten Warteschlange: Ein Netzwerkausfall oder ein Neustart lässt keinen verloren gehen, und das erneute Senden eines Alarms dupliziert ihn im SOC nie. Antwortet das SOC, dass der Kunde alle seine Alarmnummern aufgebraucht hat, stellt localSIEM das Senden ein, behält die Warteschlange und zeigt dies unter Administration › SOC an.

Jeder Alarm enthält einen stabilen Regelnamen, eine Beschreibung mit der exakten Abfrage zum Einfügen in die Suche von localSIEM und Details: vhost, Client-IP, Methode, URI (maskiert), Antwort, User-Agent, die Daten von ModSecurity (Engine, Aktion, Phase, Score, Schwellenwert, Regeln, getroffene Daten), die Gruppe (Anzahl, erstes und letztes Mal, Beispiel-`UNIQUE_ID`s) und den **Kontext** der IP: Anfragen und blockierte Anfragen in der letzten Stunde, blockierte Regeln und das erste Mal, als sie gesehen wurde.

<a id="signin"></a>
## 6. Anmeldung und Konten

Öffnen Sie `https://<server>:10443/`: Die Anmeldeseite besteht nur aus dem Formular, mit dem Logo, dem Benutzernamen, dem Passwort, **Weiter** und darunter der Sprache und dem Design. Konten werden von einem Administrator angelegt; es gibt keine offene Registrierung. Passwörter haben mindestens 8 Zeichen. Die **Zwei-Faktor-Authentifizierung** ist standardmäßig deaktiviert; wenn ein Administrator sie aktiviert (Administration › Einstellungen, Abschnitt 14), ist sie für alle Konten verpflichtend: Scannen Sie bei der nächsten Anmeldung den QR-Code mit einer Authenticator-App (Google Authenticator, Microsoft Authenticator, Aegis, FreeOTP...; der Eintrag erscheint als «PYMEHackers localSIEM») und geben Sie ihren Code ein; ab dann fragt jede Anmeldung nach dem Code der App. Nach mehreren fehlgeschlagenen Versuchen wird die Anmeldung für einige Minuten gesperrt.

**Direktzugriff mit einem Token.** Ein Administrator kann einem Analysten eine Zugriffs-URL geben, `https://<server>:10443/auth/login/auto?token=...` (Benutzer › Zugriffstoken, Abschnitt 14). Wird sie von einer erlaubten Adresse aus geöffnet, erfolgt die Anmeldung sofort, ohne Passwort und ohne zweiten Faktor, und es öffnet sich die Übersicht des Benutzer-Dashboards; fügen Sie `&next=/user/dashboard/search/?q=...` hinzu, um eine andere Seite der Website zu öffnen. Funktioniert das Token nicht, gibt die Anmeldeseite den Grund an: unbekanntes, abgelaufenes oder widerrufenes Token, oder das Konto ist deaktiviert oder kein Analystenkonto mehr. Bewahren Sie die URL wie ein Passwort auf: Wer sie besitzt, kann sich mit diesem Konto anmelden, bis sie abläuft oder widerrufen wird. Jede Anmeldung, mit Passwort oder mit einem Token, und jeder fehlgeschlagene Versuch wird aufgezeichnet (Anmeldungen, Abschnitt 14).

Nach der Anmeldung landen Sie in der **Übersicht** Ihres Dashboards (Abschnitt 7). Ein Link zu einer Suche (zum Beispiel vom SOC) öffnet bei Bedarf die Anmeldeseite und danach **dieselbe Suche mit ihren Parametern**.

Rollen: **Analyst** (arbeitet im Benutzer-Dashboard: Übersicht, Suche, Live-Ansicht, Alarme, der Zustand der Module und das Konto) und **Administrator** (arbeitet im Administrator-Dashboard: dasselbe plus die Konfiguration der Module und die Administration). Die Sprache (de-DE, en-GB, en-US, es-AR, es-ES, fr-FR, he-IL, hi-IN, it-IT, ja-JP, ko-KR, pt-BR, pt-PT, ru-RU, zh-CN), das Design (System, hell oder dunkel) und die UTC-Uhr befinden sich in der Titelleiste jeder Seite der Dashboards; die Anmeldeseite hat sie unter **Weiter** und startet mit den zuletzt in diesem Browser gewählten Werten (ohne Auswahl mit denen des Browsers und des Systems). Die Sprache, die angezeigt wird, wenn Sie auf **Weiter** klicken, wird zur Sprache Ihres Kontos: Die Dashboards behalten sie in jedem Browser bei, bis Sie sie ändern. Zeiten sind immer UTC im nativen Format `2026/10/29@13:59:59.723`. Die Dateien, die localSIEM schreibt (die Exporte, `/root/webapp-credentials.txt`, das Log des Installers), und die Alarme, die es an das SOC sendet, verwenden das Speicherformat `2026-10-29@13-59-59.723`, ebenfalls in UTC.

<a id="dashboards"></a>
## 7. Die beiden Dashboards

Jede Rolle hat ihr eigenes Dashboard; an seiner Adresse erkennen Sie, in welchem Sie sich befinden. Die Seitenleiste enthält oben das Logo, die Registerkarten (eine Linie zwischen den Gruppen) und unten **Abmelden**.

| | Administrator-Dashboard | Benutzer-Dashboard |
|---|---|---|
| Wer | Administratoren | Analysten |
| Adresse | `/admin/dashboard/<tab>/` | `/user/dashboard/<tab>/` |
| Registerkarten | Übersicht, Suche, Live, Alarme; Module (Installiert und Installierbar), Benutzer (Benutzerkonten und Zugriffstoken), SOC, Kanäle (Allgemein und Telegram), Einstellungen, Such-Audit, Anmeldungen; Konto | Übersicht, Suche, Live, Alarme, Module (nur Zustand), Konto |

Jede Registerkarte hat ihre eigene Adresse (zum Beispiel `/admin/dashboard/logins/`), und `/admin/dashboard/` oder `/user/dashboard/` öffnen die Übersicht. Die Abschnitte einer Registerkarte haben ebenfalls eigene Adressen: `/admin/dashboard/users/` öffnet `/admin/dashboard/users/accounts/`, und die Zugriffstoken befinden sich unter `/admin/dashboard/users/tokens/`; `/admin/dashboard/modules/` öffnet `/admin/dashboard/modules/installed/`, und die installierbaren Module befinden sich unter `/admin/dashboard/modules/installable/`. Eine Adresse des anderen Dashboards führt Sie zur selben Registerkarte Ihres Dashboards: Ein Administrator, der einen Link zu `/user/dashboard/search/?q=...` öffnet (der übliche Link des SOC), erhält dieselbe Suche unter `/admin/dashboard/search/`; ein Analyst, der eine Registerkarte der Administration öffnet, erhält die Übersicht des Benutzer-Dashboards.

**Was Analysten sehen.** Alles, was zum Untersuchen nötig ist: die Übersicht, die Suchen mit den Detailansichten ihrer Anfragen, die Live-Ansicht, die Alarme und den Zustand jedes Moduls (aktiviert oder deaktiviert, funktionsfähig oder nicht, und seine Zähler). Sie können Module weder aktivieren oder deaktivieren noch konfigurieren, deren Diagnose oder Regeln nicht sehen und weder Benutzer, Zugriffstoken, die Verbindung zum SOC, die Einstellungen, das Such-Audit noch das Protokoll der Anmeldungen verwalten.

<a id="overview"></a>
## 8. Übersicht

Die erste Registerkarte beider Dashboards. Sie wird alle 15 Sekunden aktualisiert und zeigt:

- **Ereignisse (24 h)**, mit der Anzahl derer, die einen Alarm ausgelöst haben; **Blockiert (24 h)**, was ModSecurity bereits abgewehrt hat (gespeichert, ohne Alarm); **Alarme (24 h)**, mit der Anzahl derer, die auf das SOC warten; und **Funktionierende Module**, die aktivierten Module, die «Aktiv und funktionsfähig» sind, im Verhältnis zu allen aktivierten (grün, wenn alle funktionieren).
- **Aktivität der letzten 24 Stunden**: Ereignisse pro Stunde; der blaue Teil jedes Balkens ist das, was ModSecurity blockiert hat. Klicken Sie auf eine Stunde, um die Suche nach ihren Ereignissen zu öffnen.
- **Zustand der Module**: jedes Modul mit seinem Zustand (Abschnitt 13) und dem, was es liest; «Module anzeigen» öffnet die Registerkarte Module.
- **System**: ob der Collector läuft (und seine Version), seit wann, der Zustand der Verbindung mit dem SOC, der letzte Heartbeat, die Alarme, die auf das SOC warten, der freie Speicherplatz und die Größe der Datenbank im Verhältnis zu ihrem Maximum.
- **Neueste Alarme**: die sechs neuesten (Schweregrad, Regel, IP, Anzahl, Status, letztes Mal); «Alle Alarme anzeigen» öffnet die Registerkarte Alarme.

<a id="search"></a>
## 9. Suche

Die Registerkarte **Suche** hat ein Suchfeld und einen Zeitraum (letzte 15 Minuten, letzte Stunde, 24 Stunden, 7 Tage, 30 Tage oder ein benutzerdefinierter Zeitraum im nativen Format).

| Syntax | Bedeutung |
|---|---|
| `word` | Volltextsuche im (maskierten) Originaltext, auch URL-dekodiert |
| `"exact phrase"` | Phrase |
| `field:value` | Feld gleich einem Wert (Textfelder unterscheiden nicht zwischen Groß- und Kleinschreibung) |
| `field:*part*` | Platzhalter |
| `status:>=500`, `status:400..499`, `status:4xx` | Vergleiche und Bereiche bei numerischen Feldern |
| `a b` / `a AND b`, `a OR b`, `NOT a` / `-a`, `( )` | Operatoren und Klammern |

| Gruppe | Felder |
|---|---|
| Netzwerk | `ip`, `vhost`, `host` |
| Anfrage | `method`, `uri`, `path`, `query`, `status`, `bytes`, `duration` (Mikrosekunden), `ua`, `referer` |
| Herkunft | `uid` (UNIQUE_ID), `module`, `source` (`access`/`error`/`audit`) |
| ModSecurity | `rule` (CRS-ID oder `localsiem:<rule>`), `category`, `phase`, `score`, `engine` (`on`/`detection-only`) |
| Alarme | `severity`, `action` (`blocked`/`none`), `alert` (SOC-Code), `sent` (`yes`/`no`) |
| Qualität | `parse` (`ok`/`partial`/`unparsed`) |

Beispiele:

- `ip:203.0.113.7` — alles von einer IP
- `rule:942100` — Anfragen, auf die diese CRS-Regel zutraf
- `status:200 action:none category:sqli` — SQL-Injections, die nicht blockiert wurden und eine 200 erhielten
- `uri:*wp-login*`
- `"union select"`
- `uid:ZTx1kH8AAQEAAB2gTkAAAAAB` — eine Anfrage
- `alert:c00007a0001F` — die Anfragen eines SOC-Alarms
- `(category:sqli OR category:xss) sent:no -status:404`

Kategorien: `sqli`, `xss`, `lfi`, `rfi`, `rce`, `php`, `java`, `fixation`, `generic`, `protocol`, `multipart`, `scanner`, `method`, `data-leakage`, `webshell` sowie die der Regeln von localSIEM: `bruteforce`, `enumeration`, `sensitive-file`, `db-error`, dazu `health-*`.

Ein Syntaxfehler wird unter dem Feld mit der Position des Fehlers angezeigt. Eine Suche, die länger als ihr Limit (5 s) dauert, fordert Sie auf, den Zeitraum einzugrenzen.

Die Ergebnisseite zeigt:

- **Das Histogramm** im Zeitverlauf; der blaue Teil jedes Balkens ist das, was ModSecurity blockiert hat. Ziehen Sie über die Balken (oder klicken Sie auf einen), um den Zeitraum einzugrenzen.
- **Zusammenfassungen** der Abfrage: IPs mit den meisten Anfragen, am häufigsten angefragte Pfade, HTTP-Codes und häufigste Regeln. Klicken Sie auf einen Wert, um ihn der Abfrage hinzuzufügen.
- **Die Ergebnistabelle** (ZEIT, QUELLE, IP, METHODE, URI, CODE, AKTION, REGELN, ALARM), die neuesten zuerst, mit «Mehr laden».
- **Export** nach CSV oder JSON (maskierte Daten, bis zu 10 000 Zeilen, Zeiten im Speicherformat `2026-10-29@13-59-59.723`) und **Link kopieren** (mit absoluten Zeiten). Das Format des Links ist `/user/dashboard/search/?q=<query>&from=<native time>&to=<native time>` (`/admin/dashboard/search/...`, wenn ein Administrator ihn kopiert); ein Link eines der beiden Dashboards funktioniert für beide Rollen.

Jede Suche und jeder Export wird aufgezeichnet (wer, was, wann) und ist für Administratoren sichtbar: Die Logs enthalten personenbezogene Daten.

<a id="card"></a>
## 10. Die Detailansicht der Anfrage und die Pivots

Klicken Sie auf eine Zeile, um die Detailansicht der Anfrage zu öffnen: Zeit, vhost, Client-IP, Methode, URI, Code, Größe, Dauer, User-Agent, `UNIQUE_ID`, Korrelation, ergriffene Aktion, ModSecurity-Engine, Phase, Score und Schwellenwert, Kategorie, Schweregrad und Alarme; und für jeden Eintrag sein geparster Inhalt: die ausgelösten Regeln mit ihrer Meldung und ihren Daten, die Anfrage-Header und der maskierte Body, die Antwort-Header, die Fehlerzeilen und die Originalzeile. Das Modul jedes Eintrags fügt hinzu, was es anzuzeigen weiß (das Apache-Modul rekonstruiert die Header und den Body aus dem Audit-Eintrag).

Hinweise in der Detailansicht: Eine 403 ohne jede Spur von ModSecurity wird als **zweifelhaft** markiert (sie zählt nicht als Blockierung); **schwache Korrelation** bedeutet, dass die Access-Zeile ihrer Anfrage anhand von Client-IP, Methode, URI, Status und Zeit zugeordnet wurde, weil das Access-Log keine `UNIQUE_ID` hat; ein **Datenbankfehler** bedeutet, dass für die Anfrage ein Datenbankfehler aufgetreten ist.

Pivots: **Diese IP** (ihre gesamte Aktivität), **±5 Min.** (die Zeitleiste rund um die Anfrage), **Regel …** (jede ausgelöste Regel), **Diese Kategorie**, **Diese UNIQUE_ID**.

<a id="live"></a>
## 11. Live-Ansicht

Die Registerkarte **Live** zeigt die neuen Ereignisse, sobald der Collector sie speichert (nach dem Korrelationsfenster von 5 Sekunden), die neuesten oben. Der Filter verwendet die Suchsyntax. **Pausieren** hält die Aktualisierungen an; beim Fortsetzen geht es mit dem neuesten Ereignis weiter.

<a id="alerts"></a>
## 12. Alarme

Die Registerkarte **Alarme** listet die von localSIEM erzeugten Alarme auf: SOC-Code, Schweregrad, Regel, IP, vhost, Anzahl, erstes und letztes Mal sowie Status:

| Status | Bedeutung |
|---|---|
| Im Puffer | Sammelt die Häufung (60 s), bevor der Alarm hinausgeht |
| In Warteschlange | Wartet auf das SOC (Netzwerk ausgefallen, SOC antwortet nicht) |
| Gesendet | Vom SOC akzeptiert; sein Code wird angezeigt |
| Abgelehnt | Das SOC hat diesen Alarm abgelehnt; der Rest der Warteschlange wird weiter gesendet. Er kann unter Administration › SOC erneut eingereiht werden. |
| Nicht gesendet | Es war kein SOC konfiguriert, oder das Senden war deaktiviert: Der Alarm bleibt in localSIEM und wird auch später nie gesendet (das SOC ist optional, Abschnitt 5) |

Klicken Sie auf eine Zeile, um die Beschreibung zu sehen, die **Anfragen dieses Alarms** (bis zu 50, die ältesten zuerst, wie in der Suche: Klicken Sie auf eine, um ihre Detailansicht zu öffnen, mit der Anfrage, ihren Headern, den ModSecurity-Regeln und den Originalzeilen), das Zeitfenster, die `external_id` und den exakten an das SOC gesendeten Alarm. **Suchen** öffnet die Suche der Gruppe. Solange ein Alarm geöffnet ist, wird die Liste nicht aktualisiert.

<a id="modules"></a>
## 13. Module

Im Administrator-Dashboard hat die Registerkarte **Module** zwei Abschnitte, jeder mit eigener Adresse: **Installiert** (`/admin/dashboard/modules/installed/`), der standardmäßig geöffnet wird (`/admin/dashboard/modules/` führt dorthin), und **Installierbar** (`/admin/dashboard/modules/installable/`), wo Module installiert werden (siehe unten). Analysten haben nur die Liste der installierten Module, ohne Abschnitte (`/user/dashboard/modules/`).

**Installiert** listet die installierten Module auf, eines pro Zeile, über die gesamte Breite, aufgebaut wie der Kopfbereich der Seite des Moduls: oben der Name, die ID und die Version und darunter sein **Zustand**, eine Zusammenfassung, die Gründe für seinen Zustand und, wenn es aktiviert ist, seine Zähler: gelesene Quellen, Zeilen der letzten Stunde, letzte Daten, Ereignisse und blockierte Anfragen der letzten 24 Stunden und das Ergebnis seiner Diagnose. Administratoren sehen außerdem den Schalter rechts neben dem Namen und unten in der Zeile seine Schaltflächen. Die Seite wird alle 10 Sekunden aktualisiert. Ist kein Modul installiert, erscheint «Installieren Sie Module über die Registerkarte Installierbar.» (für Analysten: «Keine Module installiert. Ein Administrator installiert sie unter Module › Installierbar.»).

| Zustand | Bedeutung |
|---|---|
| Aktiv und funktionsfähig | Aktiviert, vom Collector geladen und liest seine Quellen. Warnungen der Diagnose werden als Hinweise aufgeführt und ändern den Zustand nicht. |
| Aktiv, mit Warnungen | Aktiviert, aber ohne Quellen, mit einer Quelle, die noch nicht existiert, oder nach dem Start des Collectors installiert (starten Sie den Dienst `localsiem` neu). |
| Fehler | Es wird nicht geladen (der Grund wird angezeigt), seine Diagnose meldet einen Fehler, oder eine Quelle kann nicht gelesen werden (Berechtigungen des Benutzers `localsiem`, Abschnitt 3.7). |
| Änderung wird übernommen… | Gerade aktiviert oder deaktiviert; der Collector übernimmt die Änderung (einige Sekunden). |
| Aus | Deaktiviert: localSIEM liest seine Logs nicht und sendet seine Alarme nicht. Bereits Gespeichertes bleibt erhalten. Mit dem Grund «Diesem Server fehlt, was das Modul benötigt: …» wurde es ohne seine Voraussetzungen installiert und kann noch nicht aktiviert werden (siehe Voraussetzungen und Neu konfigurieren, unten). |
| Unbekannt | Der Collector läuft nicht (Dienst `localsiem`): Niemand liest etwas. |

**Analysten** sehen nur diese Liste. **Administratoren** haben außerdem in jeder Zeile:

- **Den Schalter** jedes Moduls, um es zu aktivieren oder zu deaktivieren. Das Deaktivieren erfordert eine Bestätigung. Die Änderung gilt sofort, ohne dass etwas neu gestartet wird. Solange dem Server fehlt, was ein Modul benötigt, ist sein Schalter gesperrt («Aus: Voraussetzungen fehlen»).
- **Konfigurieren**, das die Seite des Moduls öffnet (`/admin/dashboard/modules/installed/<name>/`; die ältere Adresse `/admin/dashboard/modules/<name>/` führt dorthin):
  - den Kopfbereich mit dem Zustand, dem Ordner, in dem das Modul installiert ist, dem Schalter, «Zurück zu den installierten Modulen» (führt zurück zu Installiert) und «Erneut erkennen und Diagnose ausführen»; bei einem Modul mit Voraussetzungen außerdem die Schaltfläche «Neu konfigurieren» und, solange das Modul deaktiviert ist oder eine Voraussetzung fehlt, seine **Voraussetzungen** (siehe unten);
  - **Einstellungen**: das Formular mit den eigenen Einstellungen des Moduls; «Einstellungen speichern» wendet sie sofort an;
  - **Quellen**: die Logs, die es liest (Art, Pfad, vhost, Zeilen und nicht geparste Zeilen der letzten Stunde, letzte Daten, Zustand), und darunter die Logs, die es gefunden hat, aber nicht liest, mit dem Grund;
  - **Diagnose**: seine Prüfungen der Voraussetzungen, mit dem Snippet oder dem Befehl, der jede fehlende behebt, und einer Schaltfläche «Kopieren» (die Logs werden nur beschrieben);
  - **Regeln**: jede Regel des Moduls mit ihrem Schalter («Aktiv»), Schweregrad, Schwellenwert und Zeitfenster (Schwellenwert und Zeitfenster nur für Schwellenwert- und Sequenzregeln); «Regeln speichern» wendet sie sofort an.
- **Aktualisieren**, wenn das Repository `localSIEM-modules` eine neuere Version des Moduls hat. Jedes Mal, wenn Sie Installiert öffnen, prüft localSIEM das Repository: Währenddessen erscheint «Repository wird auf neuere Versionen geprüft…» und, falls die Prüfung fehlschlägt, «Das Repository konnte nicht auf neuere Versionen geprüft werden: <Fehler>», und die Liste funktioniert wie gewohnt. Damit das Repository nicht bei jedem Besuch heruntergeladen wird, verwendet der Browser seine Antwort 10 Minuten lang wieder; «Repository prüfen» unter Installierbar lädt es immer erneut herunter, und das Installieren, Aktualisieren oder Deinstallieren eines Moduls verwirft die gespeicherte Antwort. Die Aktualisierung alle 10 Sekunden lädt es nie herunter. Ein Modul mit einer neueren Version zeigt in seiner Zeile den Hinweis «Das Repository hat Version X (installiert ist Y).» mit der Schaltfläche **Aktualisieren**. Erfordert diese Version ein neueres localSIEM, hat der Hinweis keine Schaltfläche und sagt dies: «Das Repository hat Version X, diese erfordert jedoch localSIEM Z oder neuer: Aktualisieren Sie localSIEM, um sie zu installieren.» **Aktualisieren** fordert eine Bestätigung an («Modul aktualisieren»): localSIEM lädt die neue Version aus dem Repository herunter, ersetzt damit die installierte und startet den Collector neu; seine Einstellungen bleiben erhalten, und das Modul bleibt aktiviert oder deaktiviert, wie es war. Während des Vorgangs zeigt die Schaltfläche «Wird aktualisiert…»; am Ende meldet eine Nachricht «<Modul> auf Version X aktualisiert.» Ein Dialog, «<Modul> aktualisiert», öffnet sich nur, wenn noch etwas anderes zu tun ist: Liest die neue Version andere Logs, zeigt er den root-Befehl an (`manage.py setup-modules`, Abschnitt 2, mit «Kopieren»); hat der Collector nicht geantwortet, fordert er Sie auf, den Dienst `localsiem` neu zu starten.
- **Deinstallieren**, in der Zeile jedes installierten Moduls (auch eines, das nicht geladen wird) und auf seiner Seite. Nach der Bestätigung löscht localSIEM `/opt/localsiem/modules/<name>/` und startet den Collector ohne das Modul neu: Es liest seine Logs nicht mehr und sendet seine Alarme nicht mehr. Die bereits gespeicherten Ereignisse und Alarme können weiterhin durchsucht werden, und seine Einstellungen (und die Änderungen an seinen Regeln) bleiben in `settings.json`, sodass sie zurückkommen, wenn Sie es erneut installieren. Der Lesezugriff, den root `localsiem` auf seine Logs gegeben hat, wird nicht zurückgenommen; wenn kein anderes Modul diesen Ordner liest, können Sie ihn manuell entfernen, zum Beispiel `setfacl -R -x g:localsiem /var/log/apache2` und `setfacl -d -x g:localsiem /var/log/apache2`.

**Installierbar** (nur Administratoren) enthält den Bereich «Installierbare Module»: die Module des Repositorys `localSIEM-modules` (standardmäßig `https://github.com/PYMEHackers/localSIEM-modules`, Branch `main`; die Optionen `--modules-repository` und `--modules-ref` des Installers ändern es), die auf diesem Server noch nicht installiert sind. «Repository prüfen» lädt es herunter und listet diese Module auf, jedes mit seinem Namen, seiner ID, Version und Zusammenfassung sowie seiner Schaltfläche oder seinem Hinweis:

| Schaltfläche oder Hinweis | Bedeutung |
|---|---|
| Voraussetzungen | Zeigt an, was das Modul auf dem Server benötigt, und die Befehle, die es installieren (siehe unten) |
| Installieren | Installiert das Modul |
| Erfordert localSIEM X oder neuer | Es kann nicht installiert werden: Aktualisieren Sie zuerst localSIEM |
| Das Modul des Repositorys ist ungültig | Es kann nicht installiert werden |

**Voraussetzungen** öffnet den Dialog «<Modul>: Voraussetzungen» mit dem, was das Modul auf dem Server benötigt, und den Befehlen, die es installieren, wie das Modul selbst sie angibt (`install_requirements` seiner `module.json`). Die Installation eines Moduls installiert nie die Software, die es überwacht, führen Sie die Befehle daher auf dem Server aus, **bevor** Sie das Modul installieren. Der Dialog zeigt die Befehle für das System dieses Servers («Dieser Server: Debian GNU/Linux 13 (trixie)») zweimal an, jeweils mit «Kopieren»: **Als root** und **Mit sudo** (dieselben Befehle mit vorangestelltem `sudo`), damit Sie sie in einem Terminal des Servers als root oder als Benutzer, der sudo verwenden darf, einfügen können. Die Hinweise des Moduls stehen zuerst (zum Beispiel, dass Alpine kein Paket für ModSecurity 2 hat). Gibt das Modul keine Befehle für das System dieses Servers an, zeigt der Dialog die Befehle aller Systeme, die es angibt (Debian und Alpine); gibt es keine an, erscheint «Dieses Modul gibt nichts an, das auf dem Server installiert werden muss.». localSIEM führt diese Befehle nie aus.

Sind alle Module des Repositorys bereits installiert, wird dies angezeigt («Alle Module des Repositorys sind bereits installiert.»). Die bereits installierten Module erscheinen nie in dieser Liste: Sie werden unter Installiert aktualisiert (**Aktualisieren**, siehe oben). Die Weboberfläche installiert ein Modul weder neu noch installiert sie eine ältere Version davon: Um ein Modul neu zu installieren, deinstallieren Sie es und installieren Sie es hier erneut (seine Einstellungen bleiben erhalten).

Diese Liste ist der einzige Weg, Module zu installieren. localSIEM lädt das Modul herunter, prüft seine `module.json`, kopiert seinen Ordner (`mod-<name>/` im Repository) nach `/opt/localsiem/modules/<name>/` (ohne seinen Ordner `tests/`; ein erneut installiertes Modul erhält die Einstellungen zurück, die es hatte) und startet den Collector neu, der es innerhalb weniger Sekunden lädt. Das Modul verschwindet aus der Liste, und ein Dialog, «<Modul> installiert», gibt an, was als Nächstes zu tun ist:

- Damit `localsiem` die Logs des Moduls lesen kann, ist root erforderlich, daher zeigt der Dialog **den als root auszuführenden Befehl** auf dem Server an, mit einer Schaltfläche «Kopieren»: `manage.py setup-modules` (Abschnitt 2), der den Lesezugriff gewährt und localSIEM neu startet. Bis der Befehl ausgeführt wurde, kann das Modul «Fehler» anzeigen, weil seine Logs nicht gelesen werden können.
- Fehlt dem Server bei der ersten Installation, was das Modul benötigt, wird das Modul deaktiviert installiert, und der Dialog listet anstelle des Befehls auf, was fehlt, mit dem Hinweis, das Modul unter Installiert zu öffnen (**Konfigurieren**) und auf **Neu konfigurieren** zu klicken, sobald es vorhanden ist (siehe unten).

Der Dialog hat zwei Schaltflächen: «Schließen» und «Installierte Module anzeigen», die Installiert öffnet. Der Server muss GitHub (HTTPS) erreichen können, für diese Liste und für die Prüfung auf neuere Versionen unter Installiert.

**Voraussetzungen und Neu konfigurieren.** Die Installation eines Moduls installiert nie die Software, die es überwacht. Ein Modul kann angeben, was der Server haben muss, bevor es aktiviert werden kann: Das Apache-Modul benötigt Apache (seine Konfiguration: `apache2.conf`, `httpd.conf` oder die Datei der Einstellung **Apache-Konfigurationsdatei**) und ein geladenes ModSecurity 2 (`mod_security2`; ModSecurity 3 zählt nicht). Fehlen sie bei seiner ersten Installation, wird das Modul **deaktiviert** installiert («Aus», mit dem Grund «Diesem Server fehlt, was das Modul benötigt: …»), und sein Schalter ist **gesperrt**. Seine Seite listet seine Voraussetzungen wie die Diagnose auf (Titel, Detail und der Befehl, der das Fehlende installiert, mit «Kopieren»), auch während es deaktiviert ist. Sobald Sie das Fehlende installiert haben (und, falls Apache an einem nicht standardmäßigen Ort liegt, **Apache-Konfigurationsdatei** festgelegt und die Einstellungen gespeichert haben), klicken Sie auf **Neu konfigurieren**: localSIEM sucht mit den gespeicherten Einstellungen erneut danach.

- Findet es alles, gibt es den Schalter frei, aktiviert das Modul aber nicht: Sie aktivieren es mit seinem Schalter. Außerdem zeigt es den root-Befehl aus Abschnitt 2 an: Führen Sie ihn aus, denn die Logs, die nach der Installation des Moduls erstellt wurden (`/var/log/apache2`), können nur mit dem Lesezugriff gelesen werden, den root gewährt.
- Fehlt noch etwas, zeigen die Voraussetzungen es erneut an.
- Ist das Modul bereits aktiviert, erkennt Neu konfigurieren außerdem seine Quellen erneut und führt seine Diagnose aus.

Ein Modul, das aktiviert ist und später seine Voraussetzungen verliert (jemand deinstalliert ModSecurity), bleibt aktiviert: Seine Diagnose und die Warnung zum Systemzustand «ModSecurity is no longer loaded» (Abschnitt 15) melden es, und es zu deaktivieren würde genau diese Warnung zum Schweigen bringen. Der Collector prüft die Voraussetzungen beim Start und wenn sich seine Einstellungen ändern, nie periodisch; `manage.py modules` und `manage.py doctor` zeigen sie ebenfalls an (Abschnitt 17).

**Das Apache-Modul deaktivieren und aktivieren.** Verwenden Sie unter **Module › Installiert** den Schalter von «Apache + ModSecurity» und bestätigen Sie. Solange es deaktiviert ist, liest localSIEM die Apache-Logs nicht, führt weder seine Diagnose noch seine Regeln aus und sendet keine Alarme von ihm; die bereits gespeicherten Ereignisse können weiterhin durchsucht werden. Aktivieren Sie den Schalter erneut, um fortzufahren (nur möglich, solange Apache und ModSecurity vorhanden sind): Der Collector macht in jedem Log an der Position weiter, an der er angehalten hat (und folgt den inzwischen erfolgten Rotationen), sodass er auch liest, was Apache geschrieben hat, während das Modul deaktiviert war, und alle Alarme sendet, die sich daraus ergeben.

**Einstellungen des Apache-Moduls** (Module › Installiert › Apache + ModSecurity › Konfigurieren):

| Einstellung | Verwendung |
|---|---|
| Nur die Quellen unten | Die Logs nicht aus der Apache-Konfiguration erkennen: nur die manuell hinzugefügten Quellen lesen |
| Manuell hinzugefügte Quellen | Logs, die zusätzlich zu den erkannten gelesen werden (siehe unten) |
| Apache-Konfigurationsdatei | Leer: wird automatisch gefunden (`/etc/apache2/apache2.conf` unter Debian, `/etc/apache2/httpd.conf` unter Alpine). Neu konfigurieren sucht Apache ebenfalls dort |
| Erkennungsintervall (Sekunden) | Wie oft die Apache-Konfiguration erneut gelesen wird, um neue vhosts und Logs zu finden (Standard 3600) |
| Blockierungsschwellenwert von ModSecurity | 0: wird aus der CRS-Konfiguration gelesen (`tx.inbound_anomaly_score_threshold`), 5, falls er dort nicht vorhanden ist |
| Lerntage für neue PHP-Dateien | In den ersten Tagen wird eine nie zuvor gesehene PHP-Datei nicht als neu gemeldet (Regel `apache-webshell`; Standard 3) |

**Ein Log manuell hinzufügen.** Klicken Sie unter **Manuell hinzugefügte Quellen** auf «Quelle hinzufügen» und füllen Sie **Art** (access.log, error.log oder Audit-Log von ModSecurity), **Pfad** (absolut) und bei Bedarf **Vhost**, **LogFormat** (für ein Access-Log in einem eigenen Format), **Typ des Audit-Logs** (Seriell oder Parallel) und **Audit-Speicherordner** (für ein paralleles Audit-Log) aus. «Entfernen» löscht eine Quelle. Klicken Sie auf «Einstellungen speichern»: Der Collector erkennt die Quellen sofort erneut, und das neue Log erscheint unter **Quellen**. Wird es als nicht lesbar angezeigt, geben Sie `localsiem` Lesezugriff auf seinen Ordner (Abschnitt 3.7).

**Vom Modul `apache` zu `apache2`.** Bis localSIEM 2.1 hieß das Apache-Modul `apache`; jetzt heißt es `apache2` (Ordner `mod-apache2/` im Repository, installiert in `/opt/localsiem/modules/apache2/`, Seite `/admin/dashboard/modules/installed/apache2/`). Auf einem Server, der `apache` hatte, lässt die Installation von `apache2` beide geladen: Das alte Modul behält die Apache-Logs (beide finden dieselben Quellen), `apache2` zeigt keine Quellen, bis das alte deinstalliert ist, und die Einstellungen von `apache` werden nicht von selbst übernommen. Zur Migration:

1. Notieren Sie die Einstellungen, die Sie auf der Seite des Moduls `apache` (Konfigurieren) geändert haben: manuell hinzugefügte Quellen, Apache-Konfigurationsdatei, Erkennungsintervall, Blockierungsschwellenwert, Lerntage.
2. Installieren Sie `apache2` unter Module › Installierbar.
3. Deinstallieren Sie das Modul `apache`: **Deinstallieren** in seiner Zeile unter Module › Installiert oder auf seiner Seite. Der Collector startet neu, und `apache2` liest ab dann die Apache-Logs.
4. Öffnen Sie die Seite von `apache2`, geben Sie diese Einstellungen erneut ein und speichern Sie sie. (Alternativ können Sie als root in `/opt/localsiem/config/settings.json` innerhalb von `"modules"` das, was unter `"apache"` steht, nach `"apache2"` kopieren und danach localSIEM neu starten.)

Die Regeln behalten ihre IDs (`apache-bruteforce`…) und ihre Änderungen, und die in jedem Log gelesenen Positionen sowie das Gedächtnis der Warnungen zum Systemzustand bleiben erhalten: `apache2` macht dort weiter, wo `apache` aufgehört hat, ohne etwas doppelt zu lesen. Die vom Modul `apache` gespeicherten Ereignisse bleiben durchsuchbar (`module:apache`).

<a id="administration"></a>
## 14. Administration

Diese Registerkarten gibt es nur im Administrator-Dashboard:

- **Module** (Abschnitt 13), in zwei Abschnitten: **Installiert** (`/admin/dashboard/modules/installed/`), die Liste mit dem Schalter jedes Moduls, **Konfigurieren** (Voraussetzungen und Neu konfigurieren, Einstellungen, Quellen, Diagnose und Regeln des Moduls), **Aktualisieren** (wenn das Repository eine neuere Version hat) und **Deinstallieren**; und **Installierbar** (`/admin/dashboard/modules/installable/`), die noch nicht installierten Module des Repositorys, mit **Voraussetzungen** und **Installieren**. Module werden ausschließlich dort installiert, aktualisiert und deinstalliert.
- **Benutzer › Benutzerkonten** (`/admin/dashboard/users/accounts/`): Konten anlegen (ein Passwort wird erzeugt und einmal angezeigt; es muss bei der ersten Anmeldung geändert werden), das Passwort oder die Zwei-Faktor-Authentifizierung zurücksetzen, aktivieren oder deaktivieren, die Rolle ändern, löschen. Es gibt immer mindestens einen aktiven Administrator.
- **Benutzer › Zugriffstoken** (`/admin/dashboard/users/tokens/`): **Token erstellen** für ein aktives Analystenkonto (Administratoren melden sich immer mit ihrem Passwort an, und mit dem zweiten Faktor, wenn die Zwei-Faktor-Authentifizierung aktiviert ist), mit einer optionalen Bezeichnung und einer Gültigkeit von 7, 30, 90 (Standard), 180 oder 365 Tagen. Die Zugriffs-URL, `https://<server>:10443/auth/login/auto?token=...`, wird **nur einmal** angezeigt, mit einer Schaltfläche «Kopieren»: Geben Sie sie dem Analysten (Abschnitt 6). Die Liste zeigt für jedes Token das Konto und die Bezeichnung, seine letzten 4 Zeichen, seinen Zustand (Aktiv, Abgelaufen, Widerrufen oder Unbrauchbar, wenn das Konto deaktiviert oder kein Analystenkonto mehr ist), wann und von wem es erstellt wurde, wann es abläuft und seine letzte Verwendung (Zeit und IP). **Widerrufen** stoppt es sofort; die damit bereits geöffneten Sitzungen enden, wenn sie ablaufen. Eine mit einem Token geöffnete Sitzung verlangt weder den zweiten Faktor noch eine Passwortänderung. Fehlgeschlagene Versuche zählen für die vorübergehende Sperre der Anmeldung.
- **SOC**: URL, Token (nie vollständig angezeigt), optionale CA-Datei, **Verbindung testen** (sendet einen Heartbeat), Zustand der Zustellung, letzter Heartbeat, letzter Fehler, Warteschlange (wartend, gesendet, abgelehnt) und **Warteschlange jetzt senden**. Außerdem die SIEM-Adresse, die Sie dem SOC mitteilen. Das SOC ist optional (Abschnitt 5).
- **Kanäle** (`/admin/dashboard/channels/`), in zwei Abschnitten, **Allgemein** (wird standardmäßig geöffnet) und **Telegram**: die Nachrichten, die localSIEM Ihnen sendet, zusätzlich zu den Alarmen, die es an das SOC zustellt (siehe unten).
- **Einstellungen**: Aufbewahrung, maximaler Speicherplatz, erlaubte IPs (Ihre eigene Adresse muss in der Liste stehen), Zwei-Faktor-Authentifizierung (standardmäßig deaktiviert; ihre Aktivierung macht sie für alle Konten verpflichtend und meldet die Konten, die sie noch nicht eingerichtet haben, Ihres eingeschlossen, sofort ab, und diese richten sie bei ihrer nächsten Anmeldung ein; ihre Deaktivierung behält die bereits eingerichteten Authenticator-Apps für den Fall bei, dass sie wieder aktiviert wird), Zeitlimit der Suche, Limit für Exporte, Gruppierungsfenster und Puffer, Korrelationsfenster und Schweregrad unterhalb des Schwellenwerts. Änderungen gelten sofort. Die Regeln befinden sich nicht mehr hier: Sie werden in jedem Modul konfiguriert (Module › Installiert › Konfigurieren).
- **Such-Audit**: wer was wann gesucht hat.
- **Anmeldungen** (`/admin/dashboard/logins/`): jede Anmeldung bei localSIEM und jeder fehlgeschlagene Versuch, die neuesten zuerst: Zeit, Konto, Methode (Passwort, Passwort und zweiter Faktor oder Zugriffstoken), Ergebnis (Angemeldet oder Fehlgeschlagen), der Grund eines Fehlschlags (falscher Benutzername oder falsches Passwort, falscher Code des zweiten Faktors, nach mehreren Fehlversuchen gesperrt, Anmeldung dauerte zu lange, unbekanntes, abgelaufenes oder widerrufenes Token, Konto deaktiviert, Konto ist kein Analystenkonto), IP und Browser. Filtern Sie nach Ergebnis; **Mehr laden** lädt ältere Einträge. Sie werden so lange aufbewahrt wie die Alarme (standardmäßig 365 Tage).

Der Zustand des Collectors, des Datenträgers und der Datenbank steht in der Übersicht (Abschnitt 8).

### Kanäle: Nachrichten an Sie (Telegram)

Zusätzlich dazu, dass localSIEM jeden Alarm an das SOC zustellt, kann es Ihnen die wichtigsten über einen **Kanal** senden. Derzeit ist dieser Kanal **Telegram**.

**Allgemein** (`/admin/dashboard/channels/general/`):

- **Nachrichten über die Kanäle senden**: aktiviert oder deaktiviert alle Kanäle auf einmal.
- **Mindestschweregrad**: Die Alarme dieses Schweregrads oder höher werden gesendet (Standard: Hoch).
- **Sprache der Nachrichten**: jede der 15 Sprachen der Weboberfläche (Standard en-US). Die Regel und die Beschreibung des Alarms bleiben so, wie localSIEM sie geschrieben hat.
- Eine Tabelle mit jedem Kanal: sein Zustand (Aus, Nicht konfiguriert, Funktioniert oder Fehler), die gesendeten Nachrichten, die letzte Nachricht und der letzte Fehler.

**Telegram** (`/admin/dashboard/channels/telegram/`):

1. Öffnen Sie in Telegram **@BotFather**, senden Sie `/newbot` und folgen Sie den Schritten. Sie erhalten das **Token des Bots** (`123456789:AA...`; die Zahl vor dem Doppelpunkt ist die ID des Bots).
2. Öffnen Sie den Chat mit Ihrem Bot und tippen Sie auf **Starten** (oder fügen Sie den Bot der Gruppe bzw. als Administrator dem Kanal hinzu, die bzw. der die Nachrichten erhalten soll): Ein Bot kann niemandem schreiben, der ihn nicht zuerst angeschrieben hat.
3. Ermitteln Sie die **Chat-ID**: Senden Sie dem Bot eine beliebige Nachricht und öffnen Sie `https://api.telegram.org/bot<token>/getUpdates` in einem Browser; die ID ist die Zahl nach `"chat":{"id":`. Die ID einer Gruppe beginnt mit `-` und die eines Kanals mit `-100`; ein öffentlicher Kanal oder eine öffentliche Gruppe kann auch als `@username` angegeben werden.
4. Geben Sie das Token und die Chat-ID ein, aktivieren Sie **Nachrichten über Telegram senden** und klicken Sie auf **Speichern und Testnachricht senden**. Lehnt Telegram sie ab, nennt der Hinweis den Grund (zum Beispiel `Unauthorized`: falsches Token; `Bad Request: chat not found`: falsche Chat-ID, oder niemand hat auf Starten getippt).

Das Token wird auf dem Server in `/opt/localsiem/config/telegram-bot-token` (Modus 600) gespeichert und nie vollständig angezeigt; **Token entfernen** löscht es und deaktiviert Telegram. Der Server muss `https://api.telegram.org` erreichen können (ausgehender Port 443).

Jede Nachricht nennt den Schweregrad, die Regel, die Beschreibung, das Modul, die Anzahl der Ereignisse, das erste und das letzte Mal (UTC) und die Suche, die die Ereignisse anzeigt. localSIEM sendet höchstens eine Nachricht pro Sekunde. Antwortet Telegram nicht, versucht localSIEM es einige Male erneut; lehnt Telegram eine Nachricht ab (falsches Token, unbekannter Chat, Bot blockiert), verwirft localSIEM sie und zeigt den Fehler an. Die wartenden Nachrichten gehen verloren, wenn localSIEM neu startet: Die Kanäle sind ein Hinweis für Sie, und das SOC erhält trotzdem jeden Alarm.

<a id="health"></a>
## 15. Warnungen zum Systemzustand und was zu tun ist

Diese gehen ebenfalls an das SOC (Regeln `localSIEM health: …`), gruppiert, damit sie sich nicht wiederholen:

| Warnung | Schweregrad | Was zu tun ist |
|---|---|---|
| Log außerhalb einer Rotation gekürzt, verschwunden oder ersetzt | hoch | Möglicherweise löscht jemand Spuren. Prüfen Sie, wer zu diesem Zeitpunkt Zugriff auf den Server hatte, und die anderen Logs des Servers. |
| ModSecurity nicht mehr geladen oder Engine auf Off gestellt | hoch | Wenn das niemand absichtlich getan hat, wurde der Schutz deaktiviert: Prüfen Sie die Apache-Konfiguration und ihre jüngsten Änderungen. |
| Log-Quelle nicht lesbar | mittel | Meist Berechtigungen nach einer Rotation: Führen Sie als root den Befehl aus Abschnitt 2 erneut aus (`manage.py setup-modules`) oder geben Sie `localsiem` Lesezugriff (Abschnitt 3.7). Die Warnung wird nur von einem Log ausgelöst, das localSIEM zuvor lesen konnte: Eines, das es nie lesen konnte (ein gerade installiertes Modul, vor dem Befehl aus Abschnitt 2), erscheint nur im Zustand des Moduls («Fehler», eine Quelle kann nicht gelesen werden). |
| Log-Quelle lange Zeit still (24 h) | mittel | Prüfen Sie, ob Apache noch in diese Datei schreibt (Änderungen am Logging, voller Datenträger). |
| Echte Client-IP fehlt | mittel | Fast alle Anfragen kommen von einer einzigen privaten Adresse: Die Website liegt hinter einem Proxy und Apache protokolliert dessen IP, daher funktionieren die Regeln nach IP für diese Anfragen nicht. |
| Viele nicht geparste Zeilen (mehr als 5 %) | niedrig | Das Log-Format hat sich geändert: Klicken Sie auf der Seite des Moduls (Module › Installiert › Konfigurieren) auf «Erneut erkennen und Diagnose ausführen», damit das Modul das neue Format liest; die Diagnose beschreibt das Format jedes Logs. |
| Wenig freier Speicherplatz oder Aufbewahrung aus Platzmangel gekürzt | mittel | Geben Sie Speicherplatz frei oder erhöhen Sie die maximale Größe auf dem Datenträger. localSIEM speichert in der Zwischenzeit weniger Details. |

<a id="retention"></a>
## 16. Aufbewahrung und Datenträger

Ereignisse werden 90 Tage und Alarme 365 Tage aufbewahrt. Die Datenbank wächst nie über ihr Maximum hinaus (Standard: der kleinere Wert aus 15 % des Datenträgers und 10 GB): Die ältesten Ereignisse werden zuerst gelöscht, in kleinen Stapeln, und der Platz geht an den Datenträger zurück. Bei wenig freiem Speicherplatz speichert localSIEM keine umfangreichen Details mehr (Header und Bodys der Audit-Einträge); bei fast keinem speichert es nur die Ereignisse, die an einem Alarm beteiligt sind, und warnt das SOC. Ändern Sie die Werte mit `--retention-days` und `--max-disk` (zum Beispiel `--max-disk 5G`) oder unter Administration › Einstellungen.

<a id="cli"></a>
## 17. Kommandozeile

Als root, `/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py`:

| Befehl | Verwendung |
|---|---|
| `list-users` | Konten und ihre Zwei-Faktor-Authentifizierung |
| `create-user NAME --role admin\|analyst --credentials /root/webapp-credentials.txt` | Neues Konto mit erzeugtem Passwort |
| `reset-password NAME --credentials /root/webapp-credentials.txt` | Neues Passwort (bei der nächsten Anmeldung zu ändern) |
| `reset-mfa NAME` | Zwei-Faktor-Authentifizierung wird bei der nächsten Anmeldung neu eingerichtet |
| `doctor` (`--json`) | Voraussetzungen und Quellen jedes aktivierten Moduls und, für ein deaktiviertes Modul mit Voraussetzungen, was es benötigt, bevor es aktiviert werden kann (als `localsiem` ausführen, Abschnitt 4) |
| `modules` | Installierte Module: Name, Version, aktiviert, deaktiviert oder nicht geladen, Ordner, und unter einem Modul die Voraussetzungen, die dem Server dafür fehlen; außerdem die Module, die nicht geladen werden können, mit dem Grund |
| `read-paths` | Ordner, die die installierten Module lesen (`setup-modules` und der Installer geben `localsiem` Lesezugriff darauf) |
| `soc-test` | Sendet einen Heartbeat an das SOC |
| `setup-modules` | Als root: der Befehl, den die Weboberfläche nach der Installation eines Moduls, nach einer Aktualisierung, die die vom Modul gelesenen Logs ändert, und bei Neu konfigurieren anzeigt: Lesezugriff für `localsiem` auf die Ordner der installierten Module (ACLs, auch für die nächsten Rotationen; die Gruppe `adm` unter Debian), ein Neustart von localSIEM und die Diagnose als `localsiem`. Mit `--no-restart` (was der Installer verwendet) gewährt er nur den Lesezugriff. |

Module werden ausschließlich über die Weboberfläche installiert, aktualisiert und deinstalliert (Abschnitt 13): Dafür gibt es keinen Befehl.

Dienste: localSIEM läuft als zwei Dienste des Systembenutzers `localsiem`, der Collector (`localsiem`) und die Weboberfläche (`localsiem-web`). `systemctl status localsiem localsiem-web` zeigt sie an und `systemctl restart localsiem localsiem-web` startet sie neu (Debian), bzw. `rc-service localsiem status; rc-service localsiem-web status` und `rc-service localsiem restart; rc-service localsiem-web restart` (Alpine); starten Sie beide neu, nachdem Sie ein Modul manuell in `/opt/localsiem/modules/` kopiert oder daraus gelöscht haben (die Weboberfläche tut dies selbst, wenn sie eines installiert, aktualisiert oder deinstalliert). Logs: `journalctl -u localsiem -u localsiem-web` (Debian) oder `/opt/localsiem/log/` (Alpine); beim Start protokolliert der Collector die Zeile `Modules: ...` mit jedem Modul, seiner Version und ob es aktiviert oder deaktiviert ist, sowie `Module <name>: requirements missing: ...` für ein Modul, dessen Voraussetzungen fehlen.

**Dateien auf dem Server**

| Pfad | Inhalt |
|---|---|
| `/opt/localsiem/webapp/` | Code des Kerns |
| `/opt/localsiem/modules/` | Installierte Module, ein Ordner pro Modul (`apache2/`), von der Weboberfläche aus `localSIEM-modules` installiert |
| `/opt/localsiem/venv/` | Python-Abhängigkeiten (getrennt von denen des Systems) |
| `/opt/localsiem/config/` | Einstellungen, Optionen des Installers (`install.env`), SOC-Token und Geheimnisse (Modus 600) |
| `/opt/localsiem/db/` | Datenbanken |
| `/opt/localsiem/certificates/` | Zertifikat der Weboberfläche |
| `/opt/localsiem/log/`, `/opt/localsiem/run/` | Logs (Alpine) und Laufzeitdateien |
| `/root/webapp-install.log`, `/root/webapp-credentials.txt` | Log des Installers und die von ihm erstellten Passwörter (Modus 600) |
