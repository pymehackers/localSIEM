# localSIEM

Этот README также доступен на языках:\
[de-DE](README.de-DE.md), [en-GB](README.en-GB.md), [en-US](../README.md), [es-AR](README.es-AR.md), [es-ES](README.es-ES.md), [fr-FR](README.fr-FR.md), [he-IL](README.he-IL.md), [hi-IN](README.hi-IN.md), [it-IT](README.it-IT.md), [ja-JP](README.ja-JP.md), [ko-KR](README.ko-KR.md), [pt-BR](README.pt-BR.md), [pt-PT](README.pt-PT.md), ru-RU, [zh-CN](README.zh-CN.md)

## Что это

Лёгкий модульный SIEM, который работает на том же ПК/сервере, который защищает. Alpine и Debian (пока что).

## Модули

За каждой службой сервера следит модуль, который учит localSIEM, где лежат журналы этой службы, как их читать и какие правила применять. Модули устанавливаются, обновляются и удаляются из веб-интерфейса, который загружает их из репозитория [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules). Сейчас модулей два:

- **apache2** (Apache + ModSecurity): объединяет журнал доступа, журнал ошибок и журнал аудита ModSecurity каждого запроса.
- **privesc** (Повышение привилегий): следит за тем, что запускается на сервере, и предупреждает о шагах повышения привилегий до root.

Модуль никогда ничего не устанавливает на сервер: если ему не хватает чего-то нужного, он сообщает, что нужно установить, и остаётся выключенным, пока этого нет.

## Снимки экрана

![Обзор localSIEM](https://raw.githubusercontent.com/PYMEHackers/localSIEM/main/doc/screenshot.png)

## Установка

Запускайте от имени `root`.

**Debian 13**:

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10
```

**Alpine Linux 3.24**:

```bash
apk add bash curl && curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10
```

`--allow-from`: IP, с которых разрешено открывать веб-интерфейс (`https://<server>:10443`).

## Документация

Изучите:

- [doc/MANUAL.ru-RU.md](MANUAL.ru-RU.md), чтобы узнать, как установить, настроить и использовать localSIEM.
- [doc/CODE.ru-RU.md](CODE.ru-RU.md), чтобы понять, как он устроен (для разработчиков и моделей ИИ).
- [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) — модули и их документация.
