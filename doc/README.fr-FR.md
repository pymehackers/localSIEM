# localSIEM

Ce README est également disponible en :\
[de-DE](README.de-DE.md), [en-GB](README.en-GB.md), [en-US](../README.md), [es-AR](README.es-AR.md), [es-ES](README.es-ES.md), fr-FR, [he-IL](README.he-IL.md), [hi-IN](README.hi-IN.md), [it-IT](README.it-IT.md), [ja-JP](README.ja-JP.md), [ko-KR](README.ko-KR.md), [pt-BR](README.pt-BR.md), [pt-PT](README.pt-PT.md), [ru-RU](README.ru-RU.md), [zh-CN](README.zh-CN.md)

## Qu'est-ce que c'est

Un SIEM léger et modulaire qui fonctionne sur le même PC/serveur qu'il protège. Alpine et Debian (pour l'instant).

## Modules

Chaque service du serveur est surveillé par un module, qui apprend à localSIEM où se trouvent les journaux de ce service, comment les lire et quelles règles s'appliquent. Les modules s'installent, se mettent à jour et se désinstallent depuis l'interface web, qui les télécharge depuis le dépôt [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules). Il y en a deux aujourd'hui :

- **apache2** (Apache + ModSecurity) : réunit le journal d'accès, le journal d'erreurs et le journal d'audit de ModSecurity de chaque requête.
- **privesc** (Élévation de privilèges) : surveille ce qui est exécuté sur le serveur et signale les étapes d'une élévation vers root.

Un module n'installe jamais rien sur le serveur : s'il lui manque quelque chose dont il a besoin, il vous indique quoi installer et reste désactivé jusqu'à ce que ce soit fait.

## Captures d'écran

![Vue d'ensemble de localSIEM](https://raw.githubusercontent.com/PYMEHackers/localSIEM/main/doc/screenshot.png)

## Installation

Exécutez-le en tant que `root`.

**Debian 13** :

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10
```

**Alpine Linux 3.24** :

```bash
apk add bash curl && curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10
```

`--allow-from` : les IP autorisées à ouvrir l'interface web (`https://<server>:10443`).

## Lire la documentation

Explorez :

- [doc/MANUAL.fr-FR.md](MANUAL.fr-FR.md) pour apprendre à l'installer, à le configurer et à l'utiliser.
- [doc/CODE.fr-FR.md](CODE.fr-FR.md) pour comprendre comment il est construit (pour les développeurs et pour les modèles d'IA).
- [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) pour les modules et leur documentation.
