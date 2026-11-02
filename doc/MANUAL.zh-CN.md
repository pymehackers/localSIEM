# localSIEM 用户手册

本 MANUAL 还提供以下语言版本：\
[de-DE](MANUAL.de-DE.md), [en-GB](MANUAL.en-GB.md), [en-US](MANUAL.md), [es-AR](MANUAL.es-AR.md), [es-ES](MANUAL.es-ES.md), [fr-FR](MANUAL.fr-FR.md), [he-IL](MANUAL.he-IL.md), [hi-IN](MANUAL.hi-IN.md), [it-IT](MANUAL.it-IT.md), [ja-JP](MANUAL.ja-JP.md), [ko-KR](MANUAL.ko-KR.md), [pt-BR](MANUAL.pt-BR.md), [pt-PT](MANUAL.pt-PT.md), [ru-RU](MANUAL.ru-RU.md), zh-CN

[安装](README.zh-CN.md) · [代码参考](CODE.zh-CN.md)

## 目录

1. [localSIEM 的功能](#what)
2. [安装](#installation)
3. [Apache 和 ModSecurity 的前提条件](#requirements)
4. [诊断](#doctor)
5. [连接 SOC](#soc)
6. [登录与账户](#signin)
7. [两个仪表板](#dashboards)
8. [概览](#overview)
9. [搜索](#search)
10. [请求详情卡片与关联跳转](#card)
11. [实时视图](#live)
12. [告警](#alerts)
13. [模块](#modules)
14. [管理](#administration)
15. [健康警告及处理方法](#health)
16. [数据保留与磁盘](#retention)
17. [命令行](#cli)

<a id="what"></a>
## 1. localSIEM 的功能

localSIEM 通过**模块**（每个服务一个模块）监控其所在服务器上的服务。它只读取该服务器的日志：不接收来自其他机器的任何日志。**Apache + ModSecurity** 模块负责监控 Apache 网站：对于每个请求，它使用请求的 `UNIQUE_ID` 将三条记录合并在一起，即 `access.log` 中的那一行、`error.log` 中的相关行以及 ModSecurity 审计日志中的记录。所有内容都会被存储以供搜索。然后，localSIEM 决定哪些内容需要发送到 SOC。

localSIEM 运行在其所保护的同一台 Debian 或 Alpine 服务器上，与其网站并存，以系统用户 `localsiem` 的两个服务的形式运行。它自己的 Web 界面监听 10443 端口：它从不使用 80 或 443 端口，也从不触碰服务器上的网站。除了 SOC（可选，第 5 节）之外，它还可以通过 **Telegram**（第 14 节）向您发送最重要的告警，并为 SOC 分析师提供一个**搜索工具**：一个搜索框和一个时间范围（第 9 节）。它绝不会让密码、cookie、令牌或请求体离开服务器，内存占用很少（正常使用时约 100 MB，峰值约 200 MB），而且从不会占满磁盘（第 16 节）。

**只有尚无人处理的内容才会发送到 SOC。**

| 情况 | 是否发送到 SOC？ |
|---|---|
| ModSecurity 在第 1–2 阶段拦截了请求（在应用程序收到请求之前） | **否。** 它保留在 localSIEM 中，可供搜索，并以计数形式出现在该 IP 的下一条告警中。 |
| ModSecurity 在第 3–4 阶段拦截了响应（应用程序已经执行了该请求） | 是 |
| ModSecurity 处于 `DetectionOnly` 模式时的规则匹配（不拦截任何内容） | 是 |
| 低于拦截阈值的规则匹配 | 是，严重级别为 `low` |
| localSIEM 规则产生的信号（暴力破解、Web shell、敏感文件、枚举、数据库错误） | 是 |
| 健康问题以及可能的痕迹删除 | 是 |

**发送到 SOC 的内容的严重级别**

| 情况 | 严重级别 |
|---|---|
| 未被拦截的规则匹配，响应为 3xx、4xx 或 5xx | 中 |
| 未被拦截的规则匹配，响应为 2xx | 高 |
| 在第 3–4 阶段被拦截 | 高 |
| 攻击成功的迹象：未被拦截的数据泄露或 Web shell 规则（950–955）、紧随其后的 SQL 错误、对新 `.php` 文件的 POST 请求得到 2xx 响应 | 严重 |
| 低于拦截阈值（通常是应用程序的误报） | 低（可在 设置 中配置） |

**分组。** 在 10 分钟的窗口内，每个模块、vhost、IP、类别和严重级别的组合只产生一条告警。严重告警会立即发出；其他告警会等待 60 秒以汇集突发事件，然后附带计数一起发出。一个发送数千个请求的扫描器只会产生几条告警，而不是数千条。如果严重级别上升（例如，同一攻击现在得到了 200 响应），则会产生另一条告警。

**永远不会发送到 SOC 的内容：**请求体或响应体、cookie、`Authorization` 头、密码或令牌（即使已脱敏也不会发送），以及已在第 1–2 阶段被拦截的内容（只发送其计数）。localSIEM 在存储任何内容之前，都会用 `***` 对敏感值（`password`、`pass`、`pwd`、`passwd`、`token`、`secret`、`api_key`、`apikey`、`auth`、`session` 以及 `Authorization`、`Cookie`、`Set-Cookie`、`X-Api-Key`、`Proxy-Authorization` 头）进行脱敏。

**模块。** localSIEM 的核心（存储、搜索、规则、分组、向 SOC 投递、健康检查）对所有服务都是相同的；每个模块添加某个服务特有的部分。Apache + ModSecurity 模块（`apache2`）来自 `localSIEM-modules` 仓库（GitHub），只能通过 Web 界面安装、更新和卸载，绝不会由 localSIEM 的安装程序安装；安装它从不会安装 Apache 或 ModSecurity。所有模块都以同样的方式通过 Web 界面安装、更新和卸载。第 13 节说明如何安装和更新模块、查看其状态、启用和停用模块以及配置模块。

<a id="installation"></a>
## 2. 安装

安装分为两步：先安装 localSIEM 的核心，然后安装其模块（见下文第 2 步）。以 root 身份直接从 GitHub 运行：

```bash
# Debian 13
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
# Alpine 3.24（先运行：apk add bash curl）
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10 --soc-token TOKEN
```

localSIEM 的 Web 界面始终监听**使用 HTTPS 的 10443 端口**：安装程序会检查该端口是否空闲，如果有其他服务占用它，安装程序就会停止。操作和选项写在 `bash -s --` 之后。安装程序会检查它所需的软件（带 `venv` 的 Python 3.13、OpenSSL、CA 证书、ACL 工具、logrotate、curl、tar），并安装缺失的部分。像这样通过管道运行时，它会下载 `https://github.com/PYMEHackers/localSIEM` 的 `main` 分支；如果从项目的副本运行（`bash deploy/install-update-reinstall-debian.sh --install`），它会安装该副本。

**操作。** 安装程序始终需要一个操作；没有操作时，它会停止并列出可用的操作：

| 操作 | 用途 |
|---|---|
| `--install` | 在尚未安装 localSIEM 的服务器上安装 localSIEM。如果它发现任何 localSIEM 的痕迹（`/opt/localsiem`、其服务或其 `localsiem` 用户，包括中途失败的安装留下的痕迹），它会停止并提示使用 `--update` 和 `--reinstall`。 |
| `--update` | 更新已安装的 localSIEM：保留其数据、账户、设置、模块以及之前提供的选项（见下文）。 |
| `--reinstall [--yes]` | 像 `--uninstall` 那样（见下文）删除已安装的 localSIEM 及其所有数据，然后从零开始重新安装，并生成新密码。它会先要求您输入 `yes`（`--yes` 则不询问；没有终端时必须使用它），并且在下载好新副本并检查完选项之前不会删除任何内容。之前安装的选项不会保留：请重新提供。 |
| `--uninstall [--yes]` | 从服务器上删除 localSIEM 及其所有数据（见下文）。它必须单独使用。 |

如果未安装 localSIEM，`--update` 和 `--reinstall` 会停止：请使用 `--install`。

`--install`、`--update` 和 `--reinstall` 的选项：

| 选项 | 用途 |
|---|---|
| `--allow-from LIST` | 允许打开 Web 界面的 IP 和 CIDR，以逗号分隔：SOC 和您的管理员 |
| `--soc-url URL` | 默认为 `https://soc.pymehackers.com` |
| `--soc-token TOKEN` | 此客户在 SOC 中的接入令牌。可选：没有 SOC 时，localSIEM 独立工作（第 5 节） |
| `--soc-ca-file PATH` | 仅适用于使用私有证书的 SOC（测试服务器） |
| `--domain NAME` | 服务器名称，用于证书和 SIEM 地址（默认：其主机名） |
| `--certificate PATH --private-key PATH` | 要使用的证书。不提供时，如果存在 `--domain` 的 Let's Encrypt 证书，localSIEM 会复制该证书（并在每次续期时重新复制），否则会创建一个自签名证书。 |
| `--retention-days N`, `--max-disk SIZE` | 数据保留（第 16 节） |
| `--enable-mfa`, `--disable-mfa` | 启用（所有账户必须使用）或停用两步验证。不提供时，新安装默认停用两步验证，而更新会保留在 管理 › 设置 中所做的选择（第 14 节）。 |
| `--rotate-credentials` | 创建新的 JWT 签名密钥，并将其写入 `/root/webapp-credentials.txt` |
| `--ref REF` | 要下载的 localSIEM 分支或标签（默认 `main`） |
| `--source-url URL` | 用于替代 GitHub 上的归档文件进行安装的 localSIEM 归档文件（`.tar.gz`）（镜像） |
| `--modules-repository URL`, `--modules-ref REF` | Web 界面安装和更新模块时所用的仓库（或 `.tar.gz` 归档文件）及分支或标签（第 13 节）。默认：`https://github.com/PYMEHackers/localSIEM-modules`，`main` 分支。 |

**始终使用最新版本。** GitHub 会在每次更改后将 `raw.githubusercontent.com` 上的文件缓存最多 5 分钟，因此上述命令通过没有缓存的 GitHub API 读取安装程序；随后安装程序会向该 API 询问分支对应的提交，并准确下载该提交，同时要求途经的每台服务器都不要用缓存副本响应。没有令牌时，GitHub 每小时只允许每个 IP 地址发出 60 个 API 请求：如果被拒绝，命令会以 `403` 失败（请稍后再运行）；如果只是安装程序的查询失败，安装程序会发出警告并下载该分支。

这些选项会被记录在 `/opt/localsiem/config/install.env` 中：不带选项的 `--update` 会保留它们。要更新：

```bash
# Debian 13（Alpine：install-update-reinstall-alpine.sh）
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --update
```

安装程序的日志为 `/root/webapp-install.log`，它创建的密码保存在 `/root/webapp-credentials.txt` 中（两者的权限均为 600）。它以编号步骤显示进度（`[3/12] Getting localSIEM`），用 `✓` 表示已完成的内容，`!` 表示警告，`✗` 表示失败，`·` 表示信息，在终端上会以彩色显示（`NO_COLOR=1` 或 `LOCALSIEM_COLOR=never` 可关闭颜色）。apt-get 或 apk、curl、tar 和 pip 的输出只写入日志；当其中某个命令失败时，屏幕会显示其最后 20 行。日志会收到相同的行，但不带颜色，时间采用存储格式。最后，它会运行每个已启用模块的诊断（第 4 节），并显示摘要：Web 界面的地址（也就是要提供给 SOC 的 SIEM 地址）、凭据文件、日志以及 SOC 的状态，然后是后续步骤。如果失败，它会说明在哪一步停止。

**卸载。** `--uninstall` 会从服务器上删除 localSIEM：它会停止并移除其服务，删除 `/opt/localsiem`（代码、设置、包含所有事件和告警的数据库、证书和模块）、`localsiem` 用户、`setup-modules` 授予的日志读取权限、旧版 Apache 模块（1.2.0 或更早版本）的 `--configure-apache` 选项添加的 Apache 配置（`localsiem.conf`，删除时会执行 configtest 并重新加载 Apache）、logrotate 文件、Let's Encrypt 钩子，以及 `/root/webapp-credentials.txt` 中的 localSIEM 条目（如果该文件中没有其他内容，则删除该文件）。它会先要求您输入 `yes`（`--yes` 则不询问；没有终端时必须使用它）。如果服务器上没有任何 localSIEM 的内容，它会显示 «Nothing of localSIEM was found on this server.»。安装程序的日志、安装程序添加的软件包、`mod_unique_id`（Debian）以及 Apache 的日志都会保留，包括该文件让 Apache 写入的 `localsiem_access.log` 和 `modsec_audit.log`：localSIEM 从不更改或删除 Apache 的日志。要卸载：

```bash
# Debian 13（Alpine：install-update-reinstall-alpine.sh）
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --uninstall
```

**重新安装。** 要一步从零开始，`--reinstall` 会以同样的方式删除所有内容，然后重新安装 localSIEM（请重新提供选项）：

```bash
# Debian 13（Alpine：install-update-reinstall-alpine.sh）
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --reinstall --allow-from 203.0.113.10 --soc-token TOKEN
```

**2. 模块。** localSIEM 的安装程序**不安装任何模块**：它只让 localSIEM 做好安装模块的准备，更新时会保留已安装的模块（以及对其日志的读取权限）。模块**只能通过 Web 界面**安装：模块 › 可安装（第 13 节），其中列出 `localSIEM-modules` 仓库中尚未安装的模块；该仓库没有自己的安装程序。localSIEM 从该仓库下载模块，将其目录（仓库中的 `mod-<name>/`）复制到 `/opt/localsiem/modules/<name>/`（不复制 `tests/` 目录；重新安装的模块会恢复其原有设置），然后重启采集器。模块的更新和卸载也通过 Web 界面进行：当仓库有新版本时使用**更新**，以及**卸载**，两者都在 模块 › 已安装 中（第 13 节）。

读取模块的日志需要 root 权限，因此模块安装完成后，Web 界面会在对话框中显示需要在服务器上以 root 身份运行的命令：

```bash
/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py setup-modules
```

它会授予 `localsiem` 用户读取每个已安装模块所声明的日志目录的权限（Apache 模块为 `/var/log/apache2`；第 3.7 节），包括后续轮转产生的文件，然后重启 localSIEM，并以 `localsiem` 身份运行诊断。它可以随时重新运行。localSIEM 授予的这项读取权限，就是 root 为模块所做的全部工作。

**安装模块从不会安装其监控的软件**，也不会安装其他任何东西：模块使用服务器上已有的软件工作，从不更改 `/opt/localsiem/` 之外的任何内容。新模块是启用还是停用，由其作者决定，除非服务器缺少它所需的条件（对于 Apache 模块：Apache 和 ModSecurity 2）：此时它会以**停用**状态安装，Web 界面会说明缺少什么，并且其开关会保持锁定，直到**重新配置**检测到所需条件（第 13 节）。其状态显示在 **模块 › 已安装** 中（第 13 节）。

<a id="requirements"></a>
## 3. Apache 和 ModSecurity 的前提条件

以下是 Apache + ModSecurity 模块的前提条件。必须先安装 Apache 和 ModSecurity 2 本身：没有它们，模块无法启用（第 13 节）。localSIEM 从不自行更改 Apache 的配置，也不更改 Apache 的日志、日志格式或其写入方式：模块读取服务器已经在写入的日志，并适应这些日志。模块的诊断（第 4 节）会检查每个前提条件：对于 ModSecurity 及其 CRS 和 `SecRuleEngine`（第 1 点）、`mod_unique_id`（第 2 点）以及读取权限（第 7 点），它会为每个缺失项显示确切的配置片段或命令，供您自行应用；对于日志（第 3 到 6 点），它只做描述，不建议更改。

1. **带 OWASP CRS 的 ModSecurity 2**，并使用 `SecRuleEngine On` 或 `DetectionOnly`。两者都可以：使用 `DetectionOnly` 时不拦截任何内容，因此每次匹配都会发送到 SOC。
2. **`mod_unique_id`**，ModSecurity 2 必须依赖它才能工作（没有它，ModSecurity 什么都不检查；Alpine 默认不加载它），它也用于合并每个请求的三条记录。
3. **访问日志**，按 Apache 写入的原样读取。任何格式都可以（`combined`、`vhost_combined`、`common` 或配置中的任何 `LogFormat`）：每一行按客户端 IP、方法、URI、状态码和时间与其请求合并（«弱关联»），vhost 取自 `%v`，没有它时则取自审计记录中的 Host 头和端口。如果格式还包含毫秒、`%v` 和 `%{UNIQUE_ID}e`（例如某些服务器已经在写入的 `localsiem_combined` 行），每一行会按 `UNIQUE_ID` 与其请求合并；如果有 `%D`，localSIEM 还会获得请求的耗时。格式中缺少客户端 IP、时间、请求行或状态码的访问日志会按原样读取，但其行无法与对应请求合并：这些请求可以在 ModSecurity 审计日志中看到。格式中完全没有任何指令的 `CustomLog` 每一行都写入相同的文本，不会被读取。
4. **`mod_remoteip`**，它决定日志中记录的是哪个 IP。如果网站位于代理或负载均衡器之后，而 Apache 没有使用它，日志中记录的就是代理的 IP，告警和按 IP 的规则也是如此：诊断和健康警告 «缺少真实客户端 IP»（第 15 节）会指出这一点。
5. **ModSecurity 审计日志**，按 ModSecurity 写入的原样读取：串行或并发、JSON 或原生格式，包含它所记录的各个部分。没有它（`SecAuditEngine Off` 或没有 `SecAuditLog`）时，localSIEM 只根据 `error.log` 做出判断，请求详情卡片中也没有请求头或规则列表。没有 `H` 部分时，无法从中读取所采取的动作。`E` 部分（响应体）即使被记录，也绝不会发送到 SOC；`K` 部分（所执行的每条规则的全文）不会被存储。使用并发类型（每个事务一个文件）时，ModSecurity 通常以 600 权限创建文件，只有 `localsiem` 能读取这些文件时 localSIEM 才会读取它们（第 7 点）。
6. **在源头脱敏**：如果 ModSecurity 没有对磁盘上的审计日志进行脱敏（其 `sanitise` 动作），该文件中可能包含密码和 cookie；localSIEM 会在存储之前对其进行脱敏，并且它们绝不会发送到 SOC。
7. **`localsiem` 用户对日志的读取权限**。第 2 节中供 root 运行的命令（`manage.py setup-modules`）会为已安装模块所声明的目录（Apache 模块为 `/var/log/apache2`）授予该权限，localSIEM 的安装程序在每次更新时也会再次授予：在 Debian 上，它会将 `localsiem` 加入 `adm` 组，并且与 Alpine 上一样，通过 ACL 授予 `localsiem` 对这些目录的读取权限，其中包括一条默认 ACL，使后续轮转产生的文件也可读。您在其他目录中手动添加的日志（第 13 节）也需要该权限，例如 `setfacl -m g:localsiem:rx /srv/logs`、`setfacl -d -m g:localsiem:r /srv/logs` 和 `setfacl -m g:localsiem:r /srv/logs/*.log`。localSIEM 只读取日志：从不向其中写入，也从不对其进行轮转、截断、移动或删除。当它开始跟踪某个日志时（首次启动时、安装或启用模块后，或者 root 授予其读取权限后），它从日志的末尾开始：日志中已有的内容属于历史记录，永远不会产生告警；只有之后新建的 vhost 的日志才会从头读取（当其大小不超过 5 MB 时）。

<a id="doctor"></a>
## 4. 诊断

每个模块都有自己的诊断。Apache 模块的诊断会检查第 3 节中的每个前提条件，并为每个缺失项显示修复它的配置片段或命令；对于日志（格式、`mod_remoteip`、审计日志、脱敏），它只做描述，不建议更改，并列出找到的来源（以及它无法读取的来源，例如管道日志）。它会在每次安装 localSIEM 结束时以及第 2 节中供 root 运行的命令结束时运行，显示在每个模块的页面中（**模块 › 已安装 › 配置**，第 13 节，带有 «重新发现并运行诊断» 按钮），并且可以随时为每个已启用的模块运行：

```bash
runuser -u localsiem -- /opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor   # Debian
su -s /bin/sh localsiem -c "/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py doctor"   # Alpine
```

`✓` 表示正常，`!` 表示可以工作但有限制，`✗` 表示必须修复，`·` 表示只在某些情况下适用（在终端上以彩色显示；在无法输出 UTF-8 的地方，分别为 `+`、`!`、`x` 和 `-`）。无法加载的模块会首先显示为 `✗ Module <name> not loaded: <reason>`。已停用的模块没有诊断：如果它有前提条件（第 13 节），诊断会改为显示这些前提条件，以便您了解它是否可以启用。

<a id="soc"></a>
## 5. 连接 SOC

将 localSIEM 连接到 SOC 是可选的。没有 SOC 时（没有令牌，或已关闭 **将告警发送到 SOC**），localSIEM 独立工作：它会将每条告警以 «未发送» 状态保留在 **告警** 标签页中，之后也绝不会再发送这些告警，即使以后配置了 SOC 也不会：从那时起，只有新的告警会发送给 SOC。通知渠道（Telegram）无论有没有 SOC 都可以工作。

SOC 的管理员会：

1. 为该客户创建一个接入令牌（它只显示一次）并交给您。请通过 `--soc-token` 或在 **管理 › SOC** 中设置它。
2. 将 `https://<server>:<port of localSIEM>`（由安装程序显示，也显示在 管理 › SOC 中）设为该客户的 **SIEM 地址**。负责某条告警的分析师会通过该链接前来调查。
3. 向您提供 SOC 的出口 IP：请将它们添加到允许的 IP 中（`--allow-from` 或 管理 › 设置），并**在防火墙中只向它们和您的管理员开放该端口**。

localSIEM 每 5 分钟发送一次**心跳**。如果 SOC 在一段时间内（默认 60 分钟）既没有收到告警也没有收到心跳，它会向其团队发出警告。告警在持久化队列中等待：网络中断或重启不会丢失任何告警，而且重新发送某条告警也绝不会在 SOC 中产生重复。如果 SOC 回应该客户的告警编号已用尽，localSIEM 会停止发送，保留队列，并在 管理 › SOC 中显示这一情况。

每条告警都带有一个稳定的规则名称、一段包含可直接粘贴到 localSIEM 搜索中的确切查询的描述，以及详细信息：vhost、客户端 IP、方法、URI（已脱敏）、响应、用户代理、ModSecurity 数据（引擎、动作、阶段、分数、阈值、规则、匹配的数据）、分组（次数、首次和末次时间、`UNIQUE_ID` 样例）以及该 IP 的**上下文**：最近一小时内的请求数和被拦截的请求数、被拦截的规则以及首次出现的时间。

<a id="signin"></a>
## 6. 登录与账户

打开 `https://<server>:10443/`：登录页面只有表单，包括徽标、用户名、密码、**继续** 按钮，以及其下方的语言和主题。账户由管理员创建；不开放注册。密码至少 8 个字符。**两步验证** 默认关闭；当管理员启用它后（管理 › 设置，第 14 节），所有账户都必须使用：在下次登录时，用身份验证器应用（Google Authenticator、Microsoft Authenticator、Aegis、FreeOTP...；它会显示为 «PYMEHackers localSIEM»）扫描二维码并输入其验证码，此后每次登录都会要求输入该应用的验证码。多次尝试失败后，登录会被锁定几分钟。

**使用令牌直接访问。** 管理员可以为分析师提供一个访问 URL，即 `https://<server>:10443/auth/login/auto?token=...`（用户 › 访问令牌，第 14 节）。从允许的地址打开它会立即登录，无需密码和第二因素，并打开用户仪表板的概览；添加 `&next=/user/dashboard/search/?q=...` 可打开站点的其他页面。如果令牌无效，登录页面会说明原因：令牌未知、已过期或已撤销，或者账户已停用或已不再是分析师账户。请像保管密码一样保管该 URL：在其过期或被撤销之前，任何持有它的人都可以用该账户登录。每一次登录（使用密码或令牌）以及每一次失败的尝试都会被记录（登录记录，第 14 节）。

登录后，您会进入自己仪表板的**概览**（第 7 节）。指向某个搜索的链接（例如来自 SOC 的链接）会在需要时打开登录页面，然后打开**带有相同参数的同一搜索**。

角色：**分析师**（在用户仪表板中工作：概览、搜索、实时视图、告警、模块状态和账户）和**管理员**（在管理员仪表板中工作：同样的内容，外加模块配置和管理功能）。语言（de-DE、en-GB、en-US、es-AR、es-ES、fr-FR、he-IL、hi-IN、it-IT、ja-JP、ko-KR、pt-BR、pt-PT、ru-RU、zh-CN）、主题（跟随系统、浅色或深色）和 UTC 时钟位于仪表板每个页面的标题栏中；登录页面将它们放在 **继续** 按钮下方，并默认使用此浏览器上次选择的值（如果没有选择过，则使用浏览器和系统的设置）。点击 **继续** 时所显示的语言会成为您账户的语言：仪表板会一直使用该语言，无论在哪个浏览器中，直到您更改为止。时间始终为 UTC，采用原生格式 `2026/10/29@13:59:59.723`。localSIEM 写入的文件（导出文件、`/root/webapp-credentials.txt`、安装程序日志）以及它发送给 SOC 的告警使用存储格式 `2026-10-29@13-59-59.723`，同样为 UTC。

<a id="dashboards"></a>
## 7. 两个仪表板

每个角色都有自己的仪表板；其地址表明您所在的是哪一个。侧边栏顶部是徽标，然后是各个标签页（每组之间有一条分隔线），底部是**退出登录**。

| | 管理员仪表板 | 用户仪表板 |
|---|---|---|
| 使用者 | 管理员 | 分析师 |
| 地址 | `/admin/dashboard/<tab>/` | `/user/dashboard/<tab>/` |
| 标签页 | 概览、搜索、实时、告警；模块（已安装和可安装）、用户（账户和访问令牌）、SOC、通知渠道（常规和 Telegram）、设置、搜索审计、登录记录；账户 | 概览、搜索、实时、告警、模块（仅状态）、账户 |

每个标签页都有自己的地址（例如 `/admin/dashboard/logins/`），`/admin/dashboard/` 或 `/user/dashboard/` 会打开概览。标签页中的各个部分也有自己的地址：`/admin/dashboard/users/` 会打开 `/admin/dashboard/users/accounts/`，访问令牌位于 `/admin/dashboard/users/tokens/`；`/admin/dashboard/modules/` 会打开 `/admin/dashboard/modules/installed/`，可安装模块位于 `/admin/dashboard/modules/installable/`。另一个仪表板的地址会将您带到自己仪表板的同一标签页：管理员打开指向 `/user/dashboard/search/?q=...` 的链接（SOC 的常用链接）时，会在 `/admin/dashboard/search/` 中得到相同的搜索；分析师打开管理类标签页时，会进入用户仪表板的概览。

**分析师能看到的内容。** 调查所需的一切：概览、搜索及其请求详情卡片、实时视图、告警以及每个模块的状态（启用或停用、是否正常运行及其计数器）。他们不能启用或停用模块、配置模块、查看模块的诊断或规则，也不能管理用户、访问令牌、SOC 连接、设置、搜索审计或登录记录。

<a id="overview"></a>
## 8. 概览

两个仪表板的第一个标签页。它每 15 秒刷新一次，显示：

- **事件（24 小时）**，以及其中有多少触发了告警；**已拦截（24 小时）**，即 ModSecurity 已处理的内容（已保留，不产生告警）；**告警（24 小时）**，以及其中有多少正在等待发往 SOC；**运行中的模块**，即已启用的模块中处于 «已启用，运行正常» 状态的数量（全部正常运行时显示为绿色）。
- **最近 24 小时的活动**：每小时的事件数；每个柱条的蓝色部分是 ModSecurity 拦截的内容。点击某个小时即可打开该小时事件的搜索。
- **模块状态**：每个模块及其状态（第 13 节）和它正在读取的内容；«查看模块» 会打开模块标签页。
- **系统**：采集器是否正在运行（及其版本）、运行起始时间、与 SOC 的连接状态、最近一次心跳、等待发往 SOC 的告警、可用磁盘空间以及数据库大小与其上限的对比。
- **最新告警**：最近的六条告警（严重级别、规则、IP、次数、状态、末次时间）；«查看全部告警» 会打开告警标签页。

<a id="search"></a>
## 9. 搜索

**搜索** 标签页有一个搜索框和一个时间范围（最近 15 分钟、1 小时、24 小时、7 天、30 天，或采用原生格式的自定义范围）。

| 语法 | 含义 |
|---|---|
| `word` | 在原始（已脱敏）文本中进行全文搜索，也匹配 URL 解码后的文本 |
| `"exact phrase"` | 短语 |
| `field:value` | 字段等于某个值（文本字段不区分大小写） |
| `field:*part*` | 通配符 |
| `status:>=500`, `status:400..499`, `status:4xx` | 数值字段的比较和范围 |
| `a b` / `a AND b`, `a OR b`, `NOT a` / `-a`, `( )` | 运算符和括号 |

| 分组 | 字段 |
|---|---|
| 网络 | `ip`, `vhost`, `host` |
| 请求 | `method`, `uri`, `path`, `query`, `status`, `bytes`, `duration`（微秒）, `ua`, `referer` |
| 出处 | `uid`（UNIQUE_ID）, `module`, `source`（`access`/`error`/`audit`） |
| ModSecurity | `rule`（CRS ID，或 `localsiem:<rule>`）, `category`, `phase`, `score`, `engine`（`on`/`detection-only`） |
| 告警 | `severity`, `action`（`blocked`/`none`）, `alert`（SOC 编号）, `sent`（`yes`/`no`） |
| 质量 | `parse`（`ok`/`partial`/`unparsed`） |

示例：

- `ip:203.0.113.7` — 某个 IP 的全部记录
- `rule:942100` — 命中该 CRS 规则的请求
- `status:200 action:none category:sqli` — 未被拦截且得到 200 响应的 SQL 注入
- `uri:*wp-login*`
- `"union select"`
- `uid:ZTx1kH8AAQEAAB2gTkAAAAAB` — 单个请求
- `alert:c00007a0001F` — 某条 SOC 告警的请求
- `(category:sqli OR category:xss) sent:no -status:404`

类别：`sqli`、`xss`、`lfi`、`rfi`、`rce`、`php`、`java`、`fixation`、`generic`、`protocol`、`multipart`、`scanner`、`method`、`data-leakage`、`webshell`，以及 localSIEM 规则的类别：`bruteforce`、`enumeration`、`sensitive-file`、`db-error`，另外还有 `health-*`。

语法错误会显示在搜索框下方，并指出错误的位置。耗时超过限制（5 秒）的搜索会提示您缩小范围。

结果页面显示：

- **直方图**，按时间分布；每个柱条的蓝色部分是 ModSecurity 拦截的内容。在柱条上拖动（或点击其中一个）即可缩小范围。
- 查询的**摘要**：请求最多的 IP、请求最多的路径、HTTP 状态码和最常见的规则。点击某个值即可将其添加到查询中。
- **结果表**（时间、来源、IP、方法、URI、状态码、动作、规则、告警），最新的排在最前，并带有 «加载更多»。
- **导出** 为 CSV 或 JSON（已脱敏的数据，最多 10 000 行，时间采用存储格式 `2026-10-29@13-59-59.723`）以及 **复制链接**（使用绝对时间）。链接格式为 `/user/dashboard/search/?q=<query>&from=<native time>&to=<native time>`（由管理员复制时为 `/admin/dashboard/search/...`）；任一仪表板的链接对两种角色都有效。

每一次搜索和导出都会被记录（谁、搜索了什么、何时），并且管理员可以查看：日志中包含个人数据。

<a id="card"></a>
## 10. 请求详情卡片与关联跳转

点击某一行即可打开该请求的详情卡片：时间、vhost、客户端 IP、方法、URI、状态码、大小、耗时、用户代理、`UNIQUE_ID`、关联、采取的动作、ModSecurity 引擎、阶段、分数和阈值、类别、严重级别和告警；以及每条记录经解析后的内容：命中的规则及其消息和数据、请求头和已脱敏的请求体、响应头、错误行以及原始行。每条记录所属的模块会添加它能够显示的内容（Apache 模块会根据审计记录重建请求头和请求体）。

卡片中的提示：没有任何 ModSecurity 痕迹的 403 会被标记为**存疑**（不计为拦截）；**弱关联** 表示访问日志行是按客户端 IP、方法、URI、状态码和时间与其请求合并的，因为访问日志中没有 `UNIQUE_ID`；**数据库错误** 表示该请求出现了数据库错误。

关联跳转：**此 IP**（其全部活动）、**±5 分钟**（该请求前后的时间线）、**规则 …**（每条命中的规则）、**此类别**、**此 UNIQUE_ID**。

<a id="live"></a>
## 11. 实时视图

**实时** 标签页会在采集器存储新事件后立即显示它们（在 5 秒关联窗口之后），最新的在顶部。筛选条件使用搜索语法。**暂停** 会停止更新；恢复后会从最新的事件继续。

<a id="alerts"></a>
## 12. 告警

**告警** 标签页列出 localSIEM 生成的告警：SOC 编号、严重级别、规则、IP、vhost、次数、首次和末次时间以及状态：

| 状态 | 含义 |
|---|---|
| 缓冲中 | 在发出之前汇集突发事件（60 秒） |
| 排队中 | 等待发往 SOC（网络中断、SOC 无响应） |
| 已发送 | 已被 SOC 接受；会显示其编号 |
| 已拒绝 | SOC 拒绝了该告警；队列中的其余告警继续发送。可以在 管理 › SOC 中将其重新排队。 |
| 未发送 | 当时未配置 SOC，或已关闭向其发送：该告警保留在 localSIEM 中，之后也绝不会发送（SOC 是可选的，第 5 节） |

点击某一行即可查看描述、**此告警的请求**（最多 50 个，最早的在前，与搜索中一样：点击其中一个即可打开其请求详情卡片，包括请求本身、请求头、ModSecurity 规则和原始行）、窗口、`external_id` 以及发送给 SOC 的确切告警。**搜索** 会打开该分组的搜索。展开某条告警时，列表不会刷新。

<a id="modules"></a>
## 13. 模块

在管理员仪表板中，**模块** 标签页有两个部分，各有自己的地址：**已安装**（`/admin/dashboard/modules/installed/`），默认打开（`/admin/dashboard/modules/` 会跳转到这里），以及 **可安装**（`/admin/dashboard/modules/installable/`），用于安装模块（见下文）。分析师只有已安装模块的列表，不分部分（`/user/dashboard/modules/`）。

**已安装** 列出已安装的模块，每个模块一行，占满整个宽度，布局与模块页面的页眉相同：顶部是名称、ID 和版本，下方是其**状态**、摘要、处于该状态的原因，如果模块已启用，还有其计数器：正在读取的来源、最近一小时的行数、最新数据、最近 24 小时的事件数和被拦截的请求数，以及其诊断结果。管理员还会在名称右侧看到开关，并在该行底部看到其按钮。页面每 10 秒刷新一次。没有安装任何模块时，它会显示 «请从可安装标签页安装模块。»（对分析师显示：«未安装任何模块。管理员可在 模块 › 可安装 中安装。»）。

| 状态 | 含义 |
|---|---|
| 已启用，运行正常 | 已启用，已被采集器加载并正在读取其来源。诊断的警告会作为备注列出，不会改变该状态。 |
| 已启用，有警告 | 已启用，但没有来源、有某个来源尚不存在，或者是在采集器启动后才安装的（请重启 `localsiem` 服务）。 |
| 错误 | 无法加载（会显示原因）、其诊断报告了错误，或者某个来源无法读取（`localsiem` 用户的权限问题，第 3.7 节）。 |
| 正在应用更改… | 刚刚启用或停用；采集器正在应用该更改（几秒钟）。 |
| 已停用 | 已停用：localSIEM 不读取其日志，也不发送其告警。已存储的内容会保留。如果原因为 «本服务器缺少所需的条件：…»，说明它是在不满足前提条件的情况下安装的，暂时无法启用（参见下文的前提条件与重新配置）。 |
| 未知 | 采集器未在运行（`localsiem` 服务）：没有任何模块在读取数据。 |

**分析师** 只能看到这个列表。**管理员** 在每一行中还有：

- 每个模块的**开关**，用于启用或停用模块。停用时会要求确认。更改会立即生效，无需重启任何服务。当服务器缺少模块所需的条件时，其开关处于锁定状态（«已停用：缺少前提条件»）。
- **配置**，用于打开模块的页面（`/admin/dashboard/modules/installed/<name>/`；旧地址 `/admin/dashboard/modules/<name>/` 会跳转到这里）：
  - 页眉，包括状态、模块的安装目录、开关、«返回已安装模块»（返回 已安装）和 «重新发现并运行诊断»；对于有前提条件的模块，还有 «重新配置» 按钮，并且在模块处于停用状态或缺少某项前提条件时，还会显示其**前提条件**（见下文）；
  - **设置**：模块自身设置的表单；«保存设置» 会立即应用这些设置；
  - **来源**：它读取的日志（类型、路径、vhost、最近一小时的行数和未解析行数、最新数据、状态），下方是它找到但不读取的日志及其原因；
  - **诊断**：其前提条件检查，为每个缺失项显示修复它的配置片段或命令，并带有 «复制» 按钮（日志只做描述）；
  - **规则**：模块的每条规则及其开关（«启用»）、严重级别、阈值和窗口（阈值和窗口仅适用于阈值类和序列类规则）；«保存规则» 会立即应用这些设置。
- **更新**，当 `localSIEM-modules` 仓库中有该模块的新版本时显示。每次打开 已安装 时，localSIEM 都会检查仓库：检查期间显示 «正在检查仓库中是否有新版本…»，如果检查失败，则显示 «无法检查仓库中是否有新版本：<error>»，列表照常工作。为避免每次访问都下载仓库，浏览器会在 10 分钟内重复使用仓库的响应；可安装 中的 «检查仓库» 总是会重新下载，而安装、更新或卸载模块会丢弃已保存的响应。每 10 秒一次的刷新从不下载仓库。有新版本的模块会在其所在行中显示提示 «仓库中有版本 X（已安装的版本为 Y）。»，并带有 **更新** 按钮。如果该版本需要更新的 localSIEM，提示中没有按钮，并会说明这一点：«仓库中有版本 X，但它需要 localSIEM Z 或更高版本：请先更新 localSIEM 再安装。» **更新** 会要求确认（«更新模块»）：localSIEM 从仓库下载新版本，替换已安装的版本并重启采集器；其设置会保留，模块的启用或停用状态保持不变。运行期间，按钮显示 «更新中…»；完成时会显示消息 «<module> 已更新到版本 X。» 只有在还需要做其他事情时，才会打开对话框 «<module> 已更新»：如果新版本读取其他日志，它会显示供 root 运行的命令（`manage.py setup-modules`，第 2 节，带有 «复制»）；如果采集器没有响应，它会要求您重启 `localsiem` 服务。
- **卸载**，位于每个已安装模块的所在行（包括无法加载的模块）及其页面上。确认后，localSIEM 会删除 `/opt/localsiem/modules/<name>/`，并在不加载该模块的情况下重启采集器：它不再读取该模块的日志，也不再发送其告警。已存储的事件和告警仍然可以搜索，其设置（以及对其规则所做的更改）会保留在 `settings.json` 中，因此重新安装时它们会恢复。root 授予 `localsiem` 的日志读取权限不会被收回；如果没有其他模块读取该目录，您可以手动移除该权限，例如 `setfacl -R -x g:localsiem /var/log/apache2` 和 `setfacl -d -x g:localsiem /var/log/apache2`。

**可安装**（仅限管理员）包含 «可安装模块» 卡片：`localSIEM-modules` 仓库（默认为 `https://github.com/PYMEHackers/localSIEM-modules`，`main` 分支；安装程序选项 `--modules-repository` 和 `--modules-ref` 可以更改）中尚未安装在本服务器上的模块。«检查仓库» 会下载该仓库并列出这些模块，每个模块都带有名称、ID、版本、摘要以及其按钮或提示：

| 按钮或提示 | 含义 |
|---|---|
| 前提条件 | 显示模块在服务器上需要什么，以及安装它们的命令（见下文） |
| 安装 | 安装该模块 |
| 需要 localSIEM X 或更高版本 | 无法安装：请先更新 localSIEM |
| 仓库中的模块无效 | 无法安装 |

**前提条件** 会打开对话框 «<module>：前提条件»，其中列出模块在服务器上需要什么以及安装它们的命令，这些内容由模块自身声明（其 `module.json` 中的 `install_requirements`）。安装模块从不会安装其监控的软件，因此请在安装模块**之前**在服务器上运行这些命令。对话框会将适用于本服务器系统（«本服务器：Debian GNU/Linux 13 (trixie)»）的命令显示两遍，每遍都带有 «复制»：**以 root 身份** 和 **使用 sudo**（相同的命令，前面加上 `sudo`），以便您以 root 身份或以有权使用 sudo 的用户身份将它们粘贴到服务器的终端中。模块的说明排在最前面（例如，Alpine 没有 ModSecurity 2 软件包）。如果模块没有为本服务器的系统声明命令，对话框会显示它所声明的所有系统（Debian 和 Alpine）的命令；如果它没有声明任何命令，则显示 «此模块未声明需要在服务器上安装的内容。»。localSIEM 从不运行这些命令。

如果仓库中的每个模块都已安装，它会说明这一点（«仓库中的所有模块均已安装。»）。已安装的模块从不出现在此列表中：它们在 已安装 中更新（**更新**，见上文）。Web 界面既不会重新安装模块，也不会安装模块的旧版本：要重新安装某个模块，请将其卸载，然后在这里重新安装（其设置会保留）。

此列表是安装模块的唯一途径。localSIEM 下载模块，检查其 `module.json`，将其目录（仓库中的 `mod-<name>/`）复制到 `/opt/localsiem/modules/<name>/`（不包括其 `tests/` 目录；重新安装的模块会恢复其原有设置），然后重启采集器，采集器会在几秒钟内加载它。该模块会从列表中消失，并弹出对话框 «<module> 已安装»，说明接下来要做什么：

- 让 `localsiem` 读取模块的日志需要 root 权限，因此对话框会显示**需要在服务器上以 root 身份运行的命令**，并带有 «复制» 按钮：`manage.py setup-modules`（第 2 节），它会授予读取权限并重启 localSIEM。在运行该命令之前，模块可能会因为无法读取其日志而显示 «错误»。
- 如果在首次安装时服务器缺少模块所需的条件，模块会以停用状态安装，对话框会列出缺少的内容而不是显示命令，并提示您在条件具备后到 已安装 中打开该模块（**配置**）并点击 **重新配置**（见下文）。

对话框有两个按钮：«关闭» 和 «查看已安装模块»，后者会打开 已安装。服务器需要能够访问 GitHub（HTTPS），才能使用此列表以及在 已安装 中检查新版本。

**前提条件与重新配置。** 安装模块从不会安装其监控的软件。模块可以声明在启用之前服务器必须具备的条件：Apache 模块需要 Apache（其配置：`apache2.conf`、`httpd.conf` 或 **Apache 配置文件** 设置中指定的文件）以及已加载的 ModSecurity 2（`mod_security2`；ModSecurity 3 不算）。如果在首次安装时缺少这些条件，模块会以**停用**状态安装（«已停用»，原因为 «本服务器缺少所需的条件：…»），其开关会被**锁定**。其页面会像诊断一样列出其前提条件（标题、详细信息以及安装缺失内容的命令，带有 «复制»），即使模块处于停用状态也会显示。安装好缺失的内容后（如果 Apache 位于非标准位置，还需设置 **Apache 配置文件** 并保存设置），点击 **重新配置**：localSIEM 会使用已保存的设置再次查找。

- 如果找到了所有条件，它会解锁开关，但不会启用模块：由您通过开关启用它。它还会显示第 2 节中供 root 运行的命令：请运行该命令，因为模块安装之后才创建的日志（`/var/log/apache2`）只有在 root 授予读取权限后才能读取。
- 如果仍有缺失，前提条件中会再次显示缺失的内容。
- 如果模块已经启用，重新配置还会重新发现其来源并运行其诊断。

已启用的模块如果之后失去了其前提条件（有人卸载了 ModSecurity），仍会保持启用：其诊断和健康警告 «ModSecurity 已不再加载»（第 15 节）会报告这一情况，而停用模块反而会让这条警告无法发出。采集器在启动时以及其设置发生变化时检查前提条件，从不定期检查；`manage.py modules` 和 `manage.py doctor` 也会显示前提条件（第 17 节）。

**停用和启用 Apache 模块。** 在 **模块 › 已安装** 中，使用 «Apache + ModSecurity» 的开关并确认。停用期间，localSIEM 不读取 Apache 日志，不运行其诊断和规则，也不发送来自该模块的告警；已存储的事件仍然可以搜索。再次打开开关即可恢复（仅当 Apache 和 ModSecurity 存在时才可以）：采集器会从每个日志中停止的位置继续读取（并跟踪期间发生的轮转），因此它也会读取模块停用期间 Apache 写入的内容，并发送由此产生的告警。

**Apache 模块的设置**（模块 › 已安装 › Apache + ModSecurity › 配置）：

| 设置 | 用途 |
|---|---|
| 仅使用下方的来源 | 不根据 Apache 配置发现日志：只读取手动添加的来源 |
| 手动添加的来源 | 除自动发现的日志之外还要读取的日志（见下文） |
| Apache 配置文件 | 留空：自动查找（Debian 上为 `/etc/apache2/apache2.conf`，Alpine 上为 `/etc/apache2/httpd.conf`）。重新配置也会在该位置查找 Apache |
| 发现间隔（秒） | 重新读取 Apache 配置以查找新 vhost 和新日志的频率（默认 3600） |
| ModSecurity 拦截阈值 | 0：从 CRS 配置（`tx.inbound_anomaly_score_threshold`）中读取，如果没有则为 5 |
| 新 PHP 文件的学习天数 | 在最初的这些天内，从未见过的 PHP 文件不会被报告为新文件（规则 `apache-webshell`；默认 3） |

**手动添加日志。** 在 **手动添加的来源** 中，点击 «添加来源»，填写 **类型**（access.log、error.log 或 ModSecurity 审计日志）、**路径**（绝对路径），必要时还要填写 **Vhost**、**LogFormat**（适用于使用自定义格式的访问日志）、**审计日志类型**（串行或并发）和 **审计存储目录**（适用于并发审计日志）。«移除» 会删除一个来源。点击 «保存设置»：采集器会立即重新发现来源，新日志会出现在 **来源** 中。如果它显示为不可读，请授予 `localsiem` 对其目录的读取权限（第 3.7 节）。

**从模块 `apache` 迁移到 `apache2`。** 在 localSIEM 2.1 及之前的版本中，Apache 模块名为 `apache`；现在它名为 `apache2`（仓库中的目录为 `mod-apache2/`，安装在 `/opt/localsiem/modules/apache2/`，页面为 `/admin/dashboard/modules/installed/apache2/`）。在已有 `apache` 的服务器上安装 `apache2` 后，两者都会被加载：旧模块会继续占用 Apache 日志（两者找到的来源相同），在旧模块被卸载之前，`apache2` 不显示任何来源，并且 `apache` 的设置不会自动迁移。迁移步骤：

1. 记下您在模块 `apache` 的页面（配置）中更改过的设置：手动添加的来源、Apache 配置文件、发现间隔、拦截阈值、学习天数。
2. 在 模块 › 可安装 中安装 `apache2`。
3. 卸载模块 `apache`：在 模块 › 已安装 中其所在行或其页面上点击 **卸载**。采集器会重启，此后由 `apache2` 读取 Apache 日志。
4. 打开 `apache2` 的页面，重新输入这些设置并保存。（或者，您也可以以 root 身份在 `/opt/localsiem/config/settings.json` 的 `"modules"` 中，将 `"apache"` 下的内容复制到 `"apache2"` 下，然后重启 localSIEM。）

规则会保留其 ID（`apache-bruteforce`…）及其更改，每个日志中已读取的位置以及健康警告的记忆也会保留：`apache2` 会从 `apache` 停止的地方继续，不会重复读取任何内容。模块 `apache` 存储的事件仍然可以搜索（`module:apache`）。

<a id="administration"></a>
## 14. 管理

以下标签页只存在于管理员仪表板中：

- **模块**（第 13 节），分为两个部分：**已安装**（`/admin/dashboard/modules/installed/`），即带有每个模块开关的列表、**配置**（模块的前提条件与重新配置、设置、来源、诊断和规则）、**更新**（当仓库有新版本时）和 **卸载**；以及 **可安装**（`/admin/dashboard/modules/installable/`），即仓库中尚未安装的模块，带有 **前提条件** 和 **安装**。模块只能在这里安装、更新和卸载。
- **用户 › 账户**（`/admin/dashboard/users/accounts/`）：创建账户（会生成一个密码并只显示一次；首次登录时必须修改）、重置密码或两步验证、启用或停用、更改角色、删除。始终至少保留一个已启用的管理员。
- **用户 › 访问令牌**（`/admin/dashboard/users/tokens/`）：为已启用的分析师账户 **创建令牌**（管理员始终使用密码登录，启用两步验证时还需使用第二因素），可附带可选的标签，有效期为 7、30、90（默认）、180 或 365 天。访问 URL `https://<server>:10443/auth/login/auto?token=...` **只显示一次**，并带有 «复制» 按钮：请将其交给分析师（第 6 节）。列表显示每个令牌的账户和标签、其最后 4 个字符、其状态（有效、已过期、已撤销，或者在账户已停用或已不再是分析师账户时显示为不可用）、创建时间和创建者、过期时间以及最近一次使用（时间和 IP）。**撤销** 会使其立即失效；已通过它打开的会话会在到期时结束。通过令牌打开的会话既不要求第二因素，也不要求修改密码。失败的尝试会计入登录的临时锁定。
- **SOC**：URL、令牌（从不完整显示）、可选的 CA 文件、**测试连接**（发送一次心跳）、投递状态、最近一次心跳、最近一次错误、队列（等待中、已发送、已拒绝）以及 **立即发送队列**。还有要提供给 SOC 的 SIEM 地址。SOC 是可选的（第 5 节）。
- **通知渠道**（`/admin/dashboard/channels/`），分为两个部分，**常规**（默认打开）和 **Telegram**：除了 localSIEM 投递给 SOC 的告警之外，它发送给您的消息（见下文）。
- **设置**：数据保留、最大磁盘占用、允许的 IP（您自己的地址必须在列表中）、两步验证（默认关闭；启用后所有账户都必须使用，尚未设置的账户（包括您自己的账户）会立即被登出，并在下次登录时进行设置；停用后会保留已设置的身份验证器应用，以便再次启用时使用）、搜索时间限制、导出限制、分组窗口和缓冲、关联窗口以及低于阈值时的严重级别。更改会立即生效。规则已不在这里：它们在各模块中配置（模块 › 已安装 › 配置）。
- **搜索审计**：谁在何时搜索了什么。
- **登录记录**（`/admin/dashboard/logins/`）：每一次登录 localSIEM 以及每一次失败的尝试，最新的在前：时间、账户、方式（密码、密码和第二因素，或访问令牌）、结果（成功或失败）、失败原因（用户名或密码错误、第二因素验证码错误、多次失败后被锁定、登录耗时过长、令牌未知、已过期或已撤销、账户已停用、账户不是分析师账户）、IP 和浏览器。可按结果筛选；**加载更多** 会加载更早的记录。它们的保留时间与告警相同（默认 365 天）。

采集器、磁盘和数据库的状态显示在概览中（第 8 节）。

### 通知渠道：发给您的消息（Telegram）

除了将每条告警投递给 SOC 之外，localSIEM 还可以通过**通知渠道**向您发送最重要的告警。目前的通知渠道是 **Telegram**。

**常规**（`/admin/dashboard/channels/general/`）：

- **通过通知渠道发送消息**：一次性启用或停用所有通知渠道。
- **最低严重级别**：发送此严重级别及以上的告警（默认：高）。
- **消息语言**：Web 界面的 15 种语言中的任意一种（默认 en-US）。告警的规则和描述保持 localSIEM 写入时的原样。
- 一个列出每个通知渠道的表格：其状态（已停用、未配置、运行正常或错误）、已发送的消息、最近发送的消息以及最近一次错误。

**Telegram**（`/admin/dashboard/channels/telegram/`）：

1. 在 Telegram 中打开 **@BotFather**，发送 `/newbot` 并按其步骤操作。它会给您**机器人令牌**（`123456789:AA...`；冒号前面的数字是机器人的 ID）。
2. 打开与您的机器人的聊天并点击 **Start**（开始）（或者将机器人添加到接收消息的群组中，或将其设为接收消息的频道的管理员）：机器人无法向从未与它对话过的人发送消息。
3. 获取**聊天 ID**：向机器人发送任意消息，然后在浏览器中打开 `https://api.telegram.org/bot<token>/getUpdates`；ID 就是 `"chat":{"id":` 后面的数字。群组的 ID 以 `-` 开头，频道的 ID 以 `-100` 开头；公开频道或群组也可以用 `@username` 表示。
4. 填写令牌和聊天 ID，勾选 **通过 Telegram 发送消息**，然后点击 **保存并发送测试消息**。如果 Telegram 拒绝了它，提示中会说明原因（例如 `Unauthorized`：令牌错误；`Bad Request: chat not found`：聊天 ID 错误，或者没有人点击过 Start）。

令牌保存在服务器上的 `/opt/localsiem/config/telegram-bot-token` 中（权限 600），从不完整显示；**移除令牌** 会将其删除并停用 Telegram。服务器需要能够访问 `https://api.telegram.org`（出站端口 443）。

每条消息都会说明严重级别、规则、描述、模块、事件数、首次和末次时间（UTC）以及显示这些事件的搜索。localSIEM 每秒最多发送一条消息。如果 Telegram 没有响应，它会重试几次；如果 Telegram 拒绝某条消息（令牌错误、聊天未知、机器人被屏蔽），它会丢弃该消息并显示错误。如果 localSIEM 重启，等待中的消息会丢失：通知渠道只是给您的提醒，SOC 仍然会收到每一条告警。

<a id="health"></a>
## 15. 健康警告及处理方法

这些警告也会发送到 SOC（规则 `localSIEM health: …`），并经过分组，不会重复：

| 警告 | 严重级别 | 处理方法 |
|---|---|---|
| 日志在轮转之外被截断、消失或替换 | 高 | 可能有人正在删除痕迹。请检查当时谁有权访问服务器，并查看服务器的其他日志。 |
| ModSecurity 已不再加载，或引擎被设为 Off | 高 | 如果没有人有意这样做，说明防护已被关闭：请检查 Apache 配置及其最近的更改。 |
| 日志来源不可读 | 中 | 通常是轮转后的权限问题：以 root 身份重新运行第 2 节中的命令（`manage.py setup-modules`），或授予 `localsiem` 读取权限（第 3.7 节）。只有 localSIEM 以前能够读取的日志才会触发此警告：从未能读取的日志（刚安装的模块，在运行第 2 节的命令之前）只会显示在模块的状态中（«错误»，某个来源无法读取）。 |
| 日志来源长时间没有新数据（24 小时） | 中 | 请检查 Apache 是否仍在写入该文件（日志配置的更改、磁盘已满）。 |
| 缺少真实客户端 IP | 中 | 几乎所有请求都来自同一个私有地址：网站位于代理之后，Apache 记录的是代理的 IP，因此按 IP 的规则对这些请求不起作用。 |
| 大量行未解析（超过 5 %） | 低 | 日志格式发生了变化：在模块页面（模块 › 已安装 › 配置）中点击 «重新发现并运行诊断»，让模块读取新格式；诊断会描述每个日志的格式。 |
| 可用磁盘空间不足，或因空间不足而缩减了数据保留 | 中 | 释放空间或提高最大磁盘占用。在此期间，localSIEM 会减少存储的详细信息。 |

<a id="retention"></a>
## 16. 数据保留与磁盘

事件保留 90 天，告警保留 365 天。数据库从不会超过其上限（默认：磁盘容量的 15 % 与 10 GB 中的较小值）：最早的事件会首先以小批量的方式删除，空间会归还给磁盘。可用磁盘空间不足时，localSIEM 会停止存储大体积的详细信息（审计记录的请求头和请求体）；几乎没有可用空间时，它只存储参与告警的事件，并向 SOC 发出警告。可通过 `--retention-days` 和 `--max-disk`（例如 `--max-disk 5G`）或在 管理 › 设置 中更改这些值。

<a id="cli"></a>
## 17. 命令行

以 root 身份运行 `/opt/localsiem/venv/bin/python /opt/localsiem/webapp/backend/manage.py`：

| 命令 | 用途 |
|---|---|
| `list-users` | 账户及其两步验证 |
| `create-user NAME --role admin\|analyst --credentials /root/webapp-credentials.txt` | 新建账户并生成密码 |
| `reset-password NAME --credentials /root/webapp-credentials.txt` | 新密码（下次登录时必须修改） |
| `reset-mfa NAME` | 在下次登录时重新设置两步验证 |
| `doctor` (`--json`) | 每个已启用模块的前提条件和来源，对于已停用且有前提条件的模块，还会显示启用它之前需要什么（请以 `localsiem` 身份运行，第 4 节） |
| `modules` | 已安装的模块：名称、版本、已启用、已停用或未加载、目录，以及在模块下方列出服务器为其所缺少的前提条件；还有无法加载的模块及其原因 |
| `read-paths` | 已安装模块读取的目录（`setup-modules` 和安装程序会授予 `localsiem` 对这些目录的读取权限） |
| `soc-test` | 向 SOC 发送一次心跳 |
| `setup-modules` | 以 root 身份运行，即 Web 界面在安装模块后、在更改了模块所读取日志的更新之后以及在重新配置时显示的命令：为 `localsiem` 授予对已安装模块的目录的读取权限（ACL，也适用于后续轮转；在 Debian 上还有 `adm` 组），重启 localSIEM，并以 `localsiem` 身份运行诊断。使用 `--no-restart`（安装程序使用的选项）时，它只授予读取权限。 |

模块只能通过 Web 界面安装、更新和卸载（第 13 节）：没有用于此目的的命令。

服务：localSIEM 以系统用户 `localsiem` 的两个服务的形式运行，即采集器（`localsiem`）和 Web 界面（`localsiem-web`）。`systemctl status localsiem localsiem-web` 可查看它们，`systemctl restart localsiem localsiem-web` 可重启它们（Debian），或者使用 `rc-service localsiem status; rc-service localsiem-web status` 和 `rc-service localsiem restart; rc-service localsiem-web restart`（Alpine）；在 `/opt/localsiem/modules/` 中手动复制或删除模块后，请重启这两个服务（Web 界面在安装、更新或卸载模块时会自行完成这一步）。日志：`journalctl -u localsiem -u localsiem-web`（Debian）或 `/opt/localsiem/log/`（Alpine）；采集器启动时会记录 `Modules: ...` 这一行，列出每个模块、其版本以及它是启用还是停用，对于缺少前提条件的模块，还会记录 `Module <name>: requirements missing: ...`。

**服务器上的文件**

| 路径 | 内容 |
|---|---|
| `/opt/localsiem/webapp/` | 核心代码 |
| `/opt/localsiem/modules/` | 已安装的模块，每个模块一个目录（`apache2/`），由 Web 界面从 `localSIEM-modules` 安装 |
| `/opt/localsiem/venv/` | Python 依赖项（与系统的依赖项分开） |
| `/opt/localsiem/config/` | 设置、安装程序的选项（`install.env`）、SOC 令牌和密钥（权限 600） |
| `/opt/localsiem/db/` | 数据库 |
| `/opt/localsiem/certificates/` | Web 界面的证书 |
| `/opt/localsiem/log/`, `/opt/localsiem/run/` | 日志（Alpine）和运行时文件 |
| `/root/webapp-install.log`, `/root/webapp-credentials.txt` | 安装程序的日志及其创建的密码（权限 600） |
