# localSIEM

Dieses README ist auch verfügbar in:\
de-DE, [en-GB](README.en-GB.md), [en-US](../README.md), [es-AR](README.es-AR.md), [es-ES](README.es-ES.md), [fr-FR](README.fr-FR.md), [he-IL](README.he-IL.md), [hi-IN](README.hi-IN.md), [it-IT](README.it-IT.md), [ja-JP](README.ja-JP.md), [ko-KR](README.ko-KR.md), [pt-BR](README.pt-BR.md), [pt-PT](README.pt-PT.md), [ru-RU](README.ru-RU.md), [zh-CN](README.zh-CN.md)

## Was es ist

Ein schlankes, modulares SIEM, das auf demselben PC/Server läuft, den es schützt. Alpine und Debian (vorerst).

## Module

Jeder Dienst des Servers wird von einem Modul überwacht, das localSIEM beibringt, wo die Logs dieses Dienstes liegen, wie sie gelesen werden und welche Regeln gelten. Module werden über die Weboberfläche installiert, aktualisiert und deinstalliert, die sie aus dem Repository [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) herunterlädt. Derzeit gibt es zwei:

- **apache2** (Apache + ModSecurity): führt das Access-Log, das Error-Log und das Audit-Log von ModSecurity jeder Anfrage zusammen.
- **privesc** (Rechteausweitung): überwacht, was auf dem Server ausgeführt wird, und warnt vor den Schritten einer Rechteausweitung zu root.

Ein Modul installiert nie etwas auf dem Server: Fehlt etwas, das es braucht, sagt es Ihnen, was zu installieren ist, und bleibt deaktiviert, bis es vorhanden ist.

## Screenshots

![Übersicht von localSIEM](https://raw.githubusercontent.com/PYMEHackers/localSIEM/main/doc/screenshot.png)

## Installation

Führen Sie es als `root` aus.

**Debian 13**:

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10
```

**Alpine Linux 3.24**:

```bash
apk add bash curl && curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10
```

`--allow-from`: die IPs, die die Weboberfläche öffnen dürfen (`https://<server>:10443`).

## Die Dokumentation lesen

Erkunden Sie:

- [doc/MANUAL.de-DE.md](MANUAL.de-DE.md), um zu erfahren, wie Sie es installieren, einrichten und verwenden.
- [doc/CODE.de-DE.md](CODE.de-DE.md), um zu verstehen, wie es aufgebaut ist (für Entwickler und für KI-Modelle).
- [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) für die Module und ihre Dokumentation.
