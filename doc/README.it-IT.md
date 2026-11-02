# localSIEM

Questo README è disponibile anche in:\
[de-DE](README.de-DE.md), [en-GB](README.en-GB.md), [en-US](../README.md), [es-AR](README.es-AR.md), [es-ES](README.es-ES.md), [fr-FR](README.fr-FR.md), [he-IL](README.he-IL.md), [hi-IN](README.hi-IN.md), it-IT, [ja-JP](README.ja-JP.md), [ko-KR](README.ko-KR.md), [pt-BR](README.pt-BR.md), [pt-PT](README.pt-PT.md), [ru-RU](README.ru-RU.md), [zh-CN](README.zh-CN.md)

## Che cos'è

Un SIEM leggero e modulare che funziona sullo stesso PC/server che protegge. Alpine e Debian (per ora).

## Moduli

Ogni servizio del server è sorvegliato da un modulo, che insegna a localSIEM dove sono i log di quel servizio, come leggerli e quali regole si applicano. I moduli si installano, si aggiornano e si disinstallano dall'interfaccia web, che li scarica dal repository [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules). Oggi ce ne sono due:

- **apache2** (Apache + ModSecurity): unisce l'access log, l'error log e il log di audit di ModSecurity di ogni richiesta.
- **privesc** (Escalation dei privilegi): sorveglia ciò che viene eseguito sul server e segnala i passi di un'escalation a root.

Un modulo non installa mai nulla sul server: se gli manca qualcosa di cui ha bisogno, ti dice cosa installare e resta disattivato finché non c'è.

## Schermate

![Panoramica di localSIEM](https://raw.githubusercontent.com/PYMEHackers/localSIEM/main/doc/screenshot.png)

## Installazione

Eseguilo come `root`.

**Debian 13**:

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10
```

**Alpine Linux 3.24**:

```bash
apk add bash curl && curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10
```

`--allow-from`: gli IP autorizzati ad aprire l'interfaccia web (`https://<server>:10443`).

## Leggi la documentazione

Esplora:

- [doc/MANUAL.it-IT.md](MANUAL.it-IT.md) per imparare a installarlo, configurarlo e usarlo.
- [doc/CODE.it-IT.md](CODE.it-IT.md) per capire come è costruito (per sviluppatori e per modelli di IA).
- [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) per i moduli e la loro documentazione.
