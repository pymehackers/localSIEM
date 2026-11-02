# localSIEM

本 README 还提供以下语言版本：\
[de-DE](README.de-DE.md), [en-GB](README.en-GB.md), [en-US](../README.md), [es-AR](README.es-AR.md), [es-ES](README.es-ES.md), [fr-FR](README.fr-FR.md), [he-IL](README.he-IL.md), [hi-IN](README.hi-IN.md), [it-IT](README.it-IT.md), [ja-JP](README.ja-JP.md), [ko-KR](README.ko-KR.md), [pt-BR](README.pt-BR.md), [pt-PT](README.pt-PT.md), [ru-RU](README.ru-RU.md), zh-CN

## 简介

一款轻量级模块化 SIEM，运行在其所保护的同一台电脑/服务器上。支持 Alpine 和 Debian（目前）。

## 模块

服务器上的每项服务都由一个模块监控，模块告诉 localSIEM 该服务的日志在哪里、如何读取以及适用哪些规则。模块通过 Web 界面安装、更新和卸载，Web 界面会从 [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) 仓库下载它们。目前有两个模块：

- **apache2**（Apache + ModSecurity）：将每个请求的访问日志、错误日志和 ModSecurity 审计日志关联起来。
- **privesc**（权限提升）：监控服务器上运行的内容，并对提权到 root 的各个步骤发出告警。

模块从不在服务器上安装任何东西：如果缺少它需要的东西，它会告诉您需要安装什么，并在满足之前保持停用状态。

## 截图

![localSIEM 概览](https://raw.githubusercontent.com/PYMEHackers/localSIEM/main/doc/screenshot.png)

## 安装

请以 `root` 身份运行。

**Debian 13**：

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10
```

**Alpine Linux 3.24**：

```bash
apk add bash curl && curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10
```

`--allow-from`：允许打开 Web 界面（`https://<server>:10443`）的 IP。

## 阅读文档

浏览：

- [doc/MANUAL.zh-CN.md](MANUAL.zh-CN.md)，了解如何安装、设置和使用它。
- [doc/CODE.zh-CN.md](CODE.zh-CN.md)，了解它的构建方式（面向开发者和 AI 模型）。
- [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules)，查看模块及其文档。
