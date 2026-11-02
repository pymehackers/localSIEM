# localSIEM

Este README também está disponível em:\
[de-DE](README.de-DE.md), [en-GB](README.en-GB.md), [en-US](../README.md), [es-AR](README.es-AR.md), [es-ES](README.es-ES.md), [fr-FR](README.fr-FR.md), [he-IL](README.he-IL.md), [hi-IN](README.hi-IN.md), [it-IT](README.it-IT.md), [ja-JP](README.ja-JP.md), [ko-KR](README.ko-KR.md), pt-BR, [pt-PT](README.pt-PT.md), [ru-RU](README.ru-RU.md), [zh-CN](README.zh-CN.md)

## O que é

Um SIEM leve e modular que roda no mesmo PC/servidor que protege. Alpine e Debian (por enquanto).

## Módulos

Cada serviço do servidor é monitorado por um módulo, que ensina ao localSIEM onde ficam os logs desse serviço, como lê-los e quais regras se aplicam. Os módulos são instalados, atualizados e desinstalados pela interface web, que os baixa do repositório [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules). Hoje há dois:

- **apache2** (Apache + ModSecurity): junta o access log, o error log e o log de auditoria do ModSecurity de cada requisição.
- **privesc** (Escalonamento de privilégios): monitora o que é executado no servidor e avisa sobre os passos de uma escalada para root.

Um módulo nunca instala nada no servidor: se faltar algo de que ele precisa, ele diz o que você precisa instalar e fica desativado até que esteja lá.

## Capturas de tela

![Visão geral do localSIEM](https://raw.githubusercontent.com/PYMEHackers/localSIEM/main/doc/screenshot.png)

## Instalação

Execute-o como `root`.

**Debian 13**:

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10
```

**Alpine Linux 3.24**:

```bash
apk add bash curl && curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10
```

`--allow-from`: os IPs que podem abrir a interface web (`https://<server>:10443`).

## Leia a documentação

Explore:

- [doc/MANUAL.pt-BR.md](MANUAL.pt-BR.md) para aprender a instalá-lo, configurá-lo e usá-lo.
- [doc/CODE.pt-BR.md](CODE.pt-BR.md) para entender como ele é feito (para desenvolvedores e para modelos de IA).
- [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) para os módulos e a documentação deles.
