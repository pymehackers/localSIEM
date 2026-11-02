# localSIEM

Este README también está disponible en:\
[de-DE](README.de-DE.md), [en-GB](README.en-GB.md), [en-US](../README.md), es-AR, [es-ES](README.es-ES.md), [fr-FR](README.fr-FR.md), [he-IL](README.he-IL.md), [hi-IN](README.hi-IN.md), [it-IT](README.it-IT.md), [ja-JP](README.ja-JP.md), [ko-KR](README.ko-KR.md), [pt-BR](README.pt-BR.md), [pt-PT](README.pt-PT.md), [ru-RU](README.ru-RU.md), [zh-CN](README.zh-CN.md)

## Qué es

Un SIEM modular y liviano que corre en la misma PC/servidor que protege. Alpine y Debian (por ahora).

## Módulos

Cada servicio del servidor lo vigila un módulo, que le enseña a localSIEM dónde están los logs de ese servicio, cómo leerlos y qué reglas se aplican. Los módulos se instalan, se actualizan y se desinstalan desde la web, que los descarga del repositorio [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules). Hoy hay dos:

- **apache2** (Apache + ModSecurity): junta el access log, el error log y el log de auditoría de ModSecurity de cada petición.
- **privesc** (Escalada de privilegios): vigila lo que se ejecuta en el servidor y avisa de los pasos de una escalada a root.

Un módulo nunca instala nada en el servidor: si le falta algo que necesita, te dice qué tenés que instalar y queda desactivado hasta que esté.

## Capturas de pantalla

![Resumen de localSIEM](https://raw.githubusercontent.com/PYMEHackers/localSIEM/main/doc/screenshot.png)

## Instalación

Ejecutalo como `root`.

**Debian 13**:

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10
```

**Alpine Linux 3.24**:

```bash
apk add bash curl && curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10
```

`--allow-from`: las IP que pueden abrir la web (`https://<servidor>:10443`).

## Leé la documentación

Explorá:

- [doc/MANUAL.es-AR.md](MANUAL.es-AR.md) para aprender a instalarlo, configurarlo y usarlo.
- [doc/CODE.es-AR.md](CODE.es-AR.md) para entender cómo está hecho (para desarrolladores y para modelos de IA).
- [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) para los módulos y su documentación.
