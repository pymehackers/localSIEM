# localSIEM

This README is also available in:\
[de-DE](README.de-DE.md), en-GB, [en-US](../README.md), [es-AR](README.es-AR.md), [es-ES](README.es-ES.md), [fr-FR](README.fr-FR.md), [he-IL](README.he-IL.md), [hi-IN](README.hi-IN.md), [it-IT](README.it-IT.md), [ja-JP](README.ja-JP.md), [ko-KR](README.ko-KR.md), [pt-BR](README.pt-BR.md), [pt-PT](README.pt-PT.md), [ru-RU](README.ru-RU.md), [zh-CN](README.zh-CN.md)

## What is it

A lightweight modular SIEM running in the same pc/server it protects. Alpine, and Debian (for now).

## Modules

Each service of the server is watched by a module, which teaches localSIEM where the logs of that service are, how to read them and which rules apply. Modules are installed, updated and uninstalled from the web, which downloads them from the [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) repository. Today there are two:

- **apache2** (Apache + ModSecurity): joins the access log, the error log and the ModSecurity audit log of each request.
- **privesc** (Privilege escalation): watches what is run on the server and warns about the steps of an escalation to root.

A module never installs anything on the server: if something it needs is missing, it tells you what to install and stays off until it is there.

## Screenshots

![localSIEM overview](https://raw.githubusercontent.com/PYMEHackers/localSIEM/main/doc/screenshot.png)

## Install

Run it as `root`.

**Debian 13**:

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10
```

**Alpine Linux 3.24**:

```bash
apk add bash curl && curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10
```

`--allow-from`: the IPs allowed to open the web (`https://<server>:10443`).

## Read the documentation

Explore:

- [doc/MANUAL.en-GB.md](MANUAL.en-GB.md) to learn how to install it, set it up and use it.
- [doc/CODE.en-GB.md](CODE.en-GB.md) to understand how it is built (for developers and for AI models).
- [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) for the modules and their documentation.
