# localSIEM 代码参考

本 CODE 还提供以下语言版本：\
[de-DE](CODE.de-DE.md), [en-GB](CODE.en-GB.md), [en-US](CODE.md), [es-AR](CODE.es-AR.md), [es-ES](CODE.es-ES.md), [fr-FR](CODE.fr-FR.md), [he-IL](CODE.he-IL.md), [hi-IN](CODE.hi-IN.md), [it-IT](CODE.it-IT.md), [ja-JP](CODE.ja-JP.md), [ko-KR](CODE.ko-KR.md), [pt-BR](CODE.pt-BR.md), [pt-PT](CODE.pt-PT.md), [ru-RU](CODE.ru-RU.md), zh-CN

## 索引

1. [架构与设计](#architecture)
2. [模块地图](#modules)
3. [关键符号](#symbols)
4. [主要调用路径](#flows)
5. [路由与入口点](#routes)
6. [影响分析](#impact)
7. [扩展点](#extensions)
8. [实测资源占用](#resources)

[安装](README.zh-CN.md) · [用户手册](MANUAL.zh-CN.md)

<a id="architecture"></a>
## 1. 架构与设计

localSIEM 是一款面向**单台 Linux 服务器**的轻量级 SIEM，安装在该服务器本身上（每台服务器一个 localSIEM）。它读取服务器上各服务的日志（只读取它自己所在的服务器：没有远程输入），将其存储在可搜索的数据库中，判断哪些内容仍需要人工处理，并将这些内容发送到 PYMEHackers SOC（`soc.pymehackers.com`）。SOC 的分析师使用 localSIEM 的搜索工具调查告警。版本 2.2.0（[backend/core/config.py](../backend/core/config.py) 中的 `cVersion`）。

### 指导原则：«未采取动作的，发往 SOC»

到达 SOC 的一切都是尚无人处理的内容：

| 情况 | `action` | 是否发往 SOC？ |
|---|---|---|
| ModSecurity 在第 1-2 阶段拦截了它（应用程序从未收到该请求） | `blocked` | 否：存储在 localSIEM 中，可供搜索，并计入该 IP 下一条告警的 `context` 中 |
| ModSecurity 在第 3-4 阶段拦截了它（应用程序已经执行了它） | `none` | 是 |
| 引擎处于 `DetectionOnly` 模式时的规则匹配 | `none` | 是 |
| 低于异常阈值的规则匹配 | `none` | 是（严重级别 `low`，可配置） |
| 模块规则产生的信号（暴力破解、Web shell...）以及健康信号 | `none` | 是 |

每一次未采取动作的匹配，无论其分数如何，都会发往 SOC。敏感数据（密码、cookie、`Authorization`、令牌、请求体）在存储任何内容之前都会被脱敏，并且绝不会传输到 SOC。

### 两个进程，一个写入者

| 服务 | 进程 | 角色 |
|---|---|---|
| `localsiem` | [backend/collector.py](../backend/collector.py) | 加载模块，读取其来源，解析、关联、应用规则、存储、分组、发送到 SOC 并发送心跳。**它是唯一写入事件数据库的进程。** |
| `localsiem-web` | [backend/server.py](../backend/server.py) | FastAPI + uvicorn，直接在自己的端口（始终为 10443，`config.cWebPort`）上提供 HTTPS 服务。读取事件数据库；只写入自己的数据库（账户、会话、搜索审计）和 `settings.json`。 |

Web 服务使用 Unix 套接字 `/opt/localsiem/run/collector.sock`（JSON 行）仅用于向采集器下达命令：在管理员更改设置或模块，或者点击重新配置后发送 `reload`，使采集器立即应用；`doctor`；在通过 Web 界面安装、更新或卸载模块后发送 `restart`；以及 SOC 队列的重试和重新排队。采集器始终是事件数据库的唯一写入者。如果 Web 服务停止，采集和告警仍会继续。实时视图按最后一个事件 ID 轮询数据库。

### 核心与模块

核心对 Apache 一无所知，并且**不按名称导入任何模块**。存储、搜索、规则引擎、分组、SOC 队列、心跳和健康检查都是通用的（[backend/core/](../backend/core/)）。服务器上的每个服务都是一个模块：一个目录，其中包含 `module.json`、`Module` 子类的代码（[backend/core/module.py](../backend/core/module.py)），该子类提供发现、输入、分帧和解析、关联、关于所采取动作的判断、YAML 规则、富化、诊断、前提条件（`mRequirements`）、健康信号以及其 Web 钩子和 root 钩子，还有包含其文本的 `locales/<language>.json`。

注册表（[backend/core/registry.py](../backend/core/registry.py)）只在一个位置查找模块；核心本身没有任何模块：

| 位置 | 模块 | 导入方式 |
|---|---|---|
| `cModulesPath` = `/opt/localsiem/modules/<name>/`（在开发副本中为 `LOCALSIEM_MODULES_PATH`） | 只能由 Web 服务（模块 › 可安装，以及 模块 › 已安装 中的更新和卸载，[backend/core/catalog.py](../backend/core/catalog.py)）从 `localSIEM-modules` 仓库（GitHub）安装、更新和卸载，该仓库中每个模块的目录为 `mod-<name>/`；绝不会由 localSIEM 的安装程序安装；目前有 `apache2`（access.log、error.log 和 ModSecurity 审计日志；目录 `mod-apache2/`）和 `privesc`（权限提升；目录 `mod-privesc/`），在该项目中有文档说明 | 命名空间包 `localsiem_modules.<name>.<file>`：没有 `__init__.py`，模块以相对方式导入自己的文件，并以 `backend.core.*` 导入核心 |

`module.json` 包含：`id`（目录名，在仓库中不带 `mod-`：`[a-z][a-z0-9_]{1,31}`）、`version`、`core`（它所需的最低 localSIEM 版本；更高的版本要求会使其无法加载）、`entry`（`"file:Class"`）、`default_enabled`、`read_paths`（`manage.py setup-modules` 和安装程序通过 ACL 允许 `localsiem` 读取的目录）以及 `settings`：一个 `{key, type, default, ...}` 列表，类型为 `boolean`、`integer`（`min`、`max`）、`string`（`max_length`）、`path`（绝对路径）、`choice`（`choices`）或 `records`（`fields`、`max_items`；由小记录组成的列表，例如手动添加的来源）。Web 服务根据该列表构建设置表单，注册表负责校验管理员保存的内容（`fValidateSettings`）。旧版 `module.json` 文件中的 `setup_option` 会被忽略（`fReadManifest`）：模块没有设置选项。`install_requirements`（可选）包含 `{system: [command, ...]}`，其中 system 为 `debian` 或 `alpine`（`lSystems`）：即以 root 身份在服务器上安装模块所需软件的命令。Web 界面只显示它们（模块 › 可安装 › 前提条件），按原样显示并在前面加上 `sudo`，因此每一条都必须保持为单个命令：`fCheckInstallRequirements` 会拒绝 `;`、`&`、`|`、`<`、`>`、反引号、`$(` 和换行符，也会拒绝超过 20 条的命令。其说明放在模块的语言文件中（`install_requirements.note`，适用于所有系统，以及 `install_requirements.<system>`）。

模块的设置保存在 `settings.json` 的 `modules.<name>` 下，覆盖其 `module.json` 中的默认值（`fModuleSettings`、`Module.mModuleSettings`）；`config.dDefaults` 的默认值中已不再包含任何模块。`modules.<name>.enabled` 无需重启任何服务即可启用和停用模块：采集器会停止发现和读取其来源、运行其诊断和健康检查。加载失败的模块（`module.json` 无效、`core` 版本要求更高、导入错误、`mStart` 中出现异常）会在采集器日志、`collector.status.module_errors`、诊断和 Web 界面中报告，其他模块则继续运行。

**前提条件。** 安装模块从不会安装其监控的软件。`Module.mRequirements()` 返回在模块可以启用之前服务器必须具备的条件，形式为与 `mDoctor` 格式相同的检查（`{id, status: ok|error, title, detail, fix}`）；当没有任何检查为错误时即视为满足，`[]`（默认值）表示没有前提条件：模块的行为与以前相同。调用它时不使用存储，并且它每次都可能读取服务的配置，因此它从不会按请求或按周期调用：`fCheckRequirements`（[backend/core/registry.py](../backend/core/registry.py)）负责运行它（异常视为不满足），并保存结果，由采集器在启动和重新加载时保存（状态 `<name>.requirements`），由 Web 服务（`WebContext.dRequirements`）在首次安装、启用模块和重新配置时保存；Web 服务使用两者中较新的那个。通过 Web 界面首次安装时（没有之前的副本），模块根据已安装的副本创建，绝不会根据下载的仓库创建；如果缺少某项前提条件且管理员从未保存过 `modules.<name>.enabled`，则在其中保存 `false`；更新或重新安装从不会更改它。只要缺少某项前提条件，模块就无法启用（422 `requirements_missing`，开关被锁定）；重新配置会再次检查前提条件，满足时会解锁开关并显示 root 命令，但从不会启用模块。没有任何东西会自行停用模块：已启用的模块即使不再满足前提条件也会保持启用，由其诊断和健康检查报告这一情况。

### 两个仪表板

管理员始终在 `/admin/dashboard/` 中工作（标签页 `overview`、`search`、`live`、`alerts`、`modules`、`users`、`soc`、`channels`（部分 `general/`（默认）和 `telegram/`）、`settings`、`audit`、`logins`、`account`；`modules` 有两个部分，`installed/`（默认：已安装的模块，每个一行）和 `installable/`（仓库中尚未安装的模块），单个模块的页面为 `/admin/dashboard/modules/installed/<name>/`）；分析师在 `/user/dashboard/` 中工作（`overview`、`search`、`live`、`alerts`、`modules`（只读且不分部分）、`account`）。两者的默认标签页都是 `overview`；`/` 和登录会将每个用户带到其仪表板的概览。另一个仪表板的 URL 会被重定向到自己仪表板的同一标签页（管理员请求 `/user/dashboard/search/?q=...` 会跳转到 `/admin/dashboard/search/?q=...`；分析师请求 `/admin/dashboard/users/` 会跳转到 `/user/dashboard/overview/`），服务器（[backend/web/app.py](../backend/web/app.py)）和页面的路由器（[frontend/assets/app.js](../frontend/assets/app.js)）都会这样做。侧边栏没有标题，也没有用户数据：徽标、一条分隔线、各个标签页（每组之间有一条分隔线），底部是一条分隔线和 «退出登录»。来源、诊断和规则已不再有自己的标签页：它们是每个模块页面的一部分。

### 记录、事件和分组

- **记录** 是读取到的一行或一条审计条目，已经过脱敏。它会立即与其文件的位置一起在同一事务中存储：崩溃之后，两者要么都在，要么都不在，因此不会丢失或重复任何一行。
- **事件** 是一个请求：由模块的关联器合并的那些记录。在 Apache 模块中，是在关联窗口（5 秒）之后合并的具有相同 `UNIQUE_ID` 的记录；没有 `UNIQUE_ID` 时（Apache 默认写入的访问日志格式），访问日志行会按客户端 IP、方法、URI、状态码和时间（±2 秒）与其请求的记录配对，并且该事件会被标记为弱关联。等待其窗口的记录在重启后仍会保留（`event_id IS NULL`）。
- **分组** 是一条 SOC 告警：在一个窗口（10 分钟）内具有相同模块、vhost、IP、类别和严重级别的检测结果。严重级别为 critical 的分组会立即发出；其他分组会等待 60 秒的缓冲以汇集突发事件。

### 存储

SQLite，WAL 模式（`/opt/localsiem/db/localsiem.db`，权限 600，`auto_vacuum = INCREMENTAL`），位于 [backend/core/storage.py](../backend/core/storage.py) 接口之后，以便将来为中央模式添加 PostgreSQL 实现。常用字段使用带类型和索引的列；一个无内容的 FTS5 表（`contentless_delete=1`）对已脱敏的文本（以及 URL 解码后的文本）建立索引，因此 `"union select"` 也能找到 `id=1%27%20UNION%20SELECT`。对于审计记录，只索引精简后的文本（请求行、主机、用户代理、规则 ID、消息和数据）。每个查询都使用参数：搜索树在 `fCompileQuery` 中被编译为带占位符的 SQL，绝不拼接用户文本。概览和模块页面读取最近 24 小时内按模块统计的计数（`mModuleCounts`）和告警计数（`mAlertCounts`），其时间限制与搜索相同。

时间以 UTC 存储，采用原生存储格式 `2026-10-29@13-59-59.723`（固定宽度，可按文本排序），并以显示格式 `2026/10/29@13:59:59.723` 显示（[backend/core/timeutil.py](../backend/core/timeutil.py)）。Apache 写入的是本地时间；Apache 模块会将其转换为 UTC（访问日志和审计日志带有时区偏移；error.log 使用服务器的时区）。凡是作为记录写入的内容也都使用存储格式：数据库、日志、凭据文件、导出的 CSV 和 JSON 文件以及发送给 SOC 的告警。

数据保留：按天数（90）和按最大大小（磁盘容量的 15 % 与 10 GB 中的较小值）。最早的事件会首先以小批量的方式删除；告警和 SOC 队列保留更长时间（365 天）。可用磁盘空间不足时，不再存储大体积的详细信息（审计请求头和请求体）；几乎没有可用空间时，只存储参与告警的事件。localSIEM 从不会占满磁盘。

### 值得了解的设计决策

- **localSIEM 的安装程序只安装核心。** 它直接从 GitHub 运行（`curl -fsSL .../deploy/install-update-reinstall-debian.sh | bash -s -- ACTION options`）：当它不在完整副本中运行时（通过管道运行，`BASH_SOURCE` 为 `main`），它会下载 `--ref`（或 `--source-url`）所指定分支或标签的归档文件。所有内容都在函数中，`fMain` 在最后一行运行，因此中途中断的下载不会执行任何内容；没有命令读取 stdin（stdin 就是脚本本身）：命令使用 `< /dev/null`，提问从 `/dev/tty` 读取。它会安装缺失的软件包（`dpkg-query` / `apk info -e`），并保留已安装的模块。它会拒绝 `--configure-*`（模块没有设置选项）和 `--modules-from`。它始终需要恰好一个操作（`vAction`；没有操作时，它会停止并列出可用的操作）：当 `fIsInstalled` 发现任何 localSIEM 的痕迹时（包括中途失败的安装留下的痕迹），`--install` 会停止；当没有发现任何痕迹时，`--update` 和 `--reinstall` 会停止。`--update` 会保留所有内容（数据、账户、设置、模块、`install.env` 中的选项）。`--reinstall` 会先询问（`fConfirmRemoval`），下载新副本并检查其选项，然后才像 `--uninstall` 那样删除所有内容（`fRemoveInstallation`，它会保留刚下载的副本），并从零开始安装；如果从已安装的副本运行，它会下载 localSIEM，因为该副本也会被删除。操作和 `--yes` 不会传递给 `configure.py`。`--uninstall`（单独使用或与 `--yes` 一起使用；`fUninstall`，在下载或安装任何内容之前执行）会移除 localSIEM 放到服务器上的所有内容：服务、`/opt/localsiem`、用户和组、读取路径的 ACL（`manage.py read-paths`，外加 `/var/log/apache2`）、apache2 模块 1.2.0 及更早版本的 `--configure-apache` 添加的 Apache `localsiem.conf`（`fRemoveApacheSetup`：先执行 configtest，然后重新加载；`localsiem_access.log*` 会保留：localSIEM 从不更改或删除日志）、logrotate、Let's Encrypt 钩子以及它在凭据文件中的条目块；除非使用 `--yes`，否则它会在 `/dev/tty` 上询问。
- **从 GitHub 下载从不使用缓存。** `raw.githubusercontent.com` 在推送后提供的文件可能是最多 5 分钟前的旧版本（`Cache-Control: max-age=300`；无论是查询字符串还是 `Cache-Control: no-cache` 请求都无法跳过它），分支的归档文件也可能是旧的。因此，文档中的命令通过 API（`api.github.com/repos/.../contents/...`，没有缓存）读取安装程序，并且安装程序（安装程序中的 `fResolveRef`）和 Web 服务（对于模块，`catalog.py` 中的 `fResolveRef`）都会向 API 询问分支对应的提交，并下载该提交的归档文件，而该归档文件永远不会改变；每次下载都会发送 `Cache-Control: no-cache`。没有令牌时，API 每小时只允许每个 IP 地址发出 60 个请求；得不到响应时，它们会下载分支的归档文件（安装程序会发出警告）。
- **通知渠道是给人看的副本，而不是第二个 SOC。** 采集器将每条告警放入 SOC 队列（持久化队列；没有 SOC 时将其保存为未发送），同时还将其交给 `ChannelSender`（[backend/core/channels.py](../backend/core/channels.py)），后者通过每个已启用且已设置的通知渠道发送 `channels.min_severity` 及以上严重级别的告警（Telegram：`sendMessage`，纯文本，使用 `channels.language`）。其列表保存在内存中（每个通知渠道最多 200 条消息），每秒一条消息，遇到 429（`retry_after`）和网络错误时会重试；400、401、403 或 404 会立即丢弃该消息。重启会丢失正在等待的内容；SOC 仍然会收到每一条告警。机器人令牌与 SOC 令牌一样是机密：`config/telegram-bot-token`（权限 600），从不完整显示，也从不记录到日志中，携带它的 URL 也从不写入任何地方。
- **SOC 是可选的。** `fSocConfigured`（[backend/core/soc.py](../backend/core/soc.py)）：一个 URL、一个令牌以及 `soc_enabled`。缺少这些时，`mProcessGroups` 会将每条告警标记为未发送（`mSkipGroup`：状态 `local`，原因 `soc_not_configured`，显示为 «未发送»），而不是将其放入队列，`SocSender.mCycle` 也会对待发送的内容执行同样的操作（`mSkipPending`），因此 SOC 只会收到在配置它之后产生的告警，也不会为一个可能永远不存在的 SOC 堆积任何内容。通知渠道无论有没有 SOC 都可以工作。
- **模块来自 `localSIEM-modules` 仓库，且只能通过 Web 服务安装**（[backend/core/catalog.py](../backend/core/catalog.py)）；该仓库没有安装程序。Web 界面在 模块 › 可安装 中提供模块：只包括仓库中尚未安装的模块。在 模块 › 已安装 中，当仓库有新版本时，它会为已安装的模块提供 **更新**（`fCatalog`：`newer` 为 true 且动作为 `update`；动作为 `incompatible` 时，显示所需 localSIEM 版本的提示且没有按钮）；它从不提供 reinstall 或 downgrade 动作（要重新安装模块：卸载后再安装）。更新与安装是同一个调用（`POST /api/admin/module-catalog/{name}` → 在已安装副本之上执行 `fInstall`）：设置和启用/停用状态会保留（`fFirstInstallation` 只在之前没有副本时运行），`access_changed`（其 `read_paths` 与被替换副本的不同）会告知 Web 界面 root 是否需要再次运行 `setup-modules`。浏览器会将 `GET /api/admin/module-catalog` 的响应保存 10 分钟（`modules.js` 中的 `cCatalogSeconds` 和 `fFetchCatalog`），由两个部分共享，这样打开 已安装 时就不会每次都下载仓库；«检查仓库» 总是会重新下载，而安装、更新或卸载模块会丢弃它（`fForgetCatalog`）。归档文件使用 `tarfile` 的 `data` 过滤器解压；只有其中的 `mod-<id>` 目录才是模块（`fModuleFolders`；前缀只属于仓库中的目录名：已安装的目录 `<id>/`、ID、设置、URL 和选项都使用不带前缀的名称，不带前缀的目录会被忽略）；每个模块都会通过 `fReadManifest` 进行检查而不导入其代码，并通过在已安装副本旁边执行重命名来完成安装。Web 服务以 `localsiem` 身份运行，从不授予日志读取权限（这需要 root）：它会显示 root 命令（`fRootCommand`：同一个 localSIEM 的 `manage.py setup-modules`）。卸载（`fRemove`）会通过重命名将已安装的目录移开并删除它，即使模块无法加载也是如此；设置、对其规则所做的更改、其事件、告警和读取位置都会保留，root 授予的读取权限也不会被收回。在安装、更新或卸载之后，Web 服务会重新加载其模块（`mReloadModules`），采集器会重启（IPC `restart`；systemd 或 supervise-daemon 会再次启动它）。在安装模块之前，**前提条件** 会显示其适用于本服务器系统的 `install_requirements`（`fServerSystem`：`/etc/alpine-release`、`/etc/debian_version`，或 `/etc/os-release` 中的 `ID` 和 `ID_LIKE`），按原样显示并在前面加上 `sudo`，同时显示模块的说明；当模块没有为该系统声明命令时，显示它所声明的所有系统的命令。localSIEM 从不运行这些命令。
- **以 root 身份授予日志读取权限，集中在一处完成**：`manage.py setup-modules`（`fGrantReadAccess`：为已安装模块的 `read_paths` 设置 ACL（包括用于后续轮转的默认 ACL），在 Debian 上还会使用 `adm` 组）是 Web 界面在安装模块后、在更改了其 `read_paths` 的更新之后（`access_changed`）以及在重新配置时显示的命令，也是安装程序在每次更新时运行的命令（`fGrantLogAccess`，带 `--no-restart`）。
- **localSIEM 及其模块从不更改服务器的配置**：模块没有设置选项，root 为模块运行的唯一命令是 `manage.py setup-modules`（即上一点所述的读取权限，由核心授予，绝不由模块授予）。模块在服务器上缺少的内容会出现在其前提条件和诊断中，并附带修复它的配置片段或命令（对于 Apache：ModSecurity、CRS、`SecRuleEngine`、`mod_unique_id`），由管理员自行应用。
- **Apache 相关的细节都在 Apache 模块中**，位于 `localSIEM-modules/mod-apache2/`：直接解析 Apache 配置（因此发现功能可以在没有 `apache2ctl` 的情况下以 `localsiem` 身份运行），ModSecurity 的 K 部分在存储前被丢弃，请求详情卡片中显示的请求头和请求体是根据已脱敏的原始审计记录重建的（`mDisplayRecord`）。核心只是询问每条记录所属的模块（`WebContext.mModule`）。
- **模块的启用和停用无需重启**：Web 服务写入 `settings.json` 并通过套接字发送 `reload`；采集器会立即重新发布其状态，Web 服务会将其保存的内容与采集器已应用的内容（`collector.status.modules`）进行比较，在两者一致之前显示 «待定»。
- **Web 服务在启动时读取 `module.json` 文件**，并在安装、更新或卸载模块后再次读取（`mReloadModules`）。手动复制或移除的模块需要重启两个服务（在采集器加载它之前，Web 界面会将其显示为 `not_loaded`）。
- **模块的前提条件只在关键时刻检查**（采集器启动和重新加载、首次安装、启用模块、重新配置）并保存结果，因为模块可能需要读取其服务的配置来检查前提条件。Web 服务从不导入下载的仓库中的代码：它在已安装的副本上检查前提条件。
- **追赶**（突发流量，或停止期间写入的内容）：当某个来源达到其读取预算而停止时，下一个周期会立即开始；比其模块中最慢的来源领先超过 5 秒（日志时间）的来源会等待最慢的来源；晚于所有落后来源已读取位置的事务会等待（水位线），因此一个请求的三条记录总能被合并。
- **日志只读。** `FileTailer` 以 `O_RDONLY` 打开每个日志；localSIEM 中没有任何东西会写入、轮转、截断、重命名、移动或删除服务的日志（其 logrotate 文件只涉及 `/opt/localsiem/log/`）。root 为 localSIEM 对日志所做的唯一操作是授予读取权限（`manage.py setup-modules`：`adm` 组和 ACL）。卸载时会保留 apache2 模块 1.2.0 及更早版本的 `localsiem.conf` 让 Apache 写入的 `localsiem_access.log`。
- **也不更改日志的写入方式。** 没有任何模块会更改服务的日志配置或其日志格式（对于 Apache：不更改 `LogFormat`、`CustomLog`、`GlobalLog` 或 `ErrorLog`，也不更改 ModSecurity 的 `SecAudit*` 指令）：模块按服务器写入的原样读取日志并适应它们（任何 `LogFormat`、`mod_remoteip` 是否在其中留下的 IP、串行或并发、JSON 或原生格式的审计日志、已经写入 `localsiem_combined` 行的服务器的这些行）。其诊断只描述日志（格式、审计日志的各个部分、脱敏、能从中读取什么和不能读取什么），不建议更改：只有不属于日志的前提条件（对于 Apache：ModSecurity、CRS、`SecRuleEngine`、`mod_unique_id`）和读取权限会附带 `fix`。
- **模块从不安装任何东西，也从不更改 `/opt/localsiem/` 之外的任何内容。** 它使用系统已有的软件工作：不安装任何软件包或软件，也不在 `/opt/localsiem/` 之外写入服务器的任何文件、配置或日志。当服务器缺少它所需的某些东西时，其前提条件（`mRequirements`）会说明这一点，在不满足前提条件时安装的模块会保持停用（其开关被锁定），直到满足为止（参见 [核心与模块](#architecture) 中的 «前提条件»）。模块没有设置选项：对其 `read_paths` 的读取权限由核心授予（`manage.py setup-modules`，以 root 身份），绝不由模块授予。其 `install_requirements` 中的命令是给管理员的：Web 界面只显示它们。
- **从不对历史记录告警。** 没有已保存位置的来源从其末尾开始读取（`Collector.mDiscover`），除非它是在该进程已经跟踪其模块期间出现的（`sFollowedModules`：新的 vhost），这种来源在大小不超过 5 MB 时会从头读取。因此，无论是首次启动、之后安装或启用的模块、在 root 授予权限之前无法读取的文件，还是重启，都不会读取旧行。每个文件的位置在打开后会立即保存，即使其中没有任何新内容（`FileTailer.vOpenedUnsaved`），因此重启后会从该位置继续。`--from-start` 会从头读取新文件。
- **依赖项安装在虚拟环境中**（`/opt/localsiem/venv/`），从不使用 `pip --break-system-packages`：pip 不得破坏客户的服务所使用的发行版软件包（例如 certbot）。
- **Web 界面由应用程序本身限制为只允许指定的 IP**（以及回环地址）访问，登录页面也不例外；两步验证（TOTP，«PYMEHackers localSIEM»）默认关闭；管理员在 设置 中为所有账户启用它（`mfa_enabled`），此后它就是必需的。安装程序只有在使用 `--enable-mfa` 或 `--disable-mfa` 时才会更改它（它不在 `install.env` 中），因此更新会保留在 Web 界面中所做的选择。
- **SOC 的 SIEM 地址从不随告警传输**：客户的每位分析师都能看到 `details`；只发送查询（`details.localsiem.search`）。
- **只读取自己服务器的日志。** 没有远程输入：每个模块都读取 localSIEM 所在服务器上的文件。当收到已移除的远程输入的选项（`lRemovedOptions`：`--enable-http-input`、`--disable-http-input`、`--mode`）时，`configure.py` 会以 «<option> no longer exists: localSIEM has no remote HTTP input, it only reads the logs of its own server.» 停止，并在每次运行时移除旧版本为其保留的内容：`settings.json` 中的 `http_input`（`lRemovedSettings`、`fRemoveSettings`）以及 `localsiem.env` 中的三个变量（`lRemovedEnvironment`）。安装程序会整体替换 `backend/` 和 `frontend/`，因此更新也会移除该输入的旧文件。旧版本存储的 `http` 模块的事件会保留在数据库中，直到被数据保留策略删除。
- **十五种语言，一份列表。** Web 界面、模块的文本、通知渠道的消息和文档都提供 de-DE、en-GB、en-US、es-AR、es-ES、fr-FR、he-IL、hi-IN、it-IT、ja-JP、ko-KR、pt-BR、pt-PT、ru-RU、zh-CN 版本：[backend/core/config.py](../backend/core/config.py) 中的 `lLanguages`（账户、模块文本和通知渠道所接受的语言）和 `common.js` 中的 `cLanguages`（Web 界面）是按字母顺序排列的同一份列表。en-US 是原始语言和回退语言：某种语言中缺失的文本会以英语显示（`fT`、`fModuleText`、通知渠道的 `dTexts`）。he-IL 从右到左书写（`lRightToLeftLanguages`、`cRightToLeft`）：`fLoadLanguage` 会在页面上设置 `dir="rtl"`，样式只使用逻辑方向（`inline-start`、`inline-end`、`text-align: start`），因此布局会自动镜像，`localsiem.css` 末尾的 «Right to left» 块负责处理其余部分（使用 `unicode-bidi: plaintext` 的技术文本、下拉框的箭头、开关的滑块、窄屏上的菜单；直方图保持从左到右）。 显示格式的时间按从左到右隔离（`fEl` 的 `fTextNodes`：`<bdi dir="ltr">`），切换语言会重新绘制当前打开的视图（`app.js` 的 `fOnLanguage` → `fRoute`）。

<a id="modules"></a>
## 2. 模块地图

| 模块 | 路径 | 职责 | 依赖 | 使用方 |
|---|---|---|---|---|
| 采集器 | [backend/collector.py](../backend/collector.py) | 主循环：加载模块、来源、记录、关联、事件、规则、分组、数据保留、健康检查、供 Web 服务使用的状态（也按模块提供）、本地套接字 | core, registry | `localsiem` 服务 |
| Web 服务器 | [backend/server.py](../backend/server.py) | 除 `-h`/`--help` 外不接受任何选项（`fCheckArguments`：其他任何选项都视为错误），释放端口，带 HTTPS 的 uvicorn | web | `localsiem-web` 服务 |
| 管理 CLI | [backend/manage.py](../backend/manage.py) | 账户、每个已启用模块的诊断（以及已停用模块的前提条件）、带有所缺前提条件的模块列表、模块读取的目录、SOC 测试；以 root 身份运行的 `setup-modules`（授予对模块日志的读取权限并重启：即 Web 界面显示的命令，安装程序也会运行它） | web.auth, registry | 安装程序、root |
| 终端输出 | [backend/core/terminal.py](../backend/core/terminal.py) | `manage.py` 和 `configure.py` 的输出样式，与安装程序相同：带标记的结果行（`✓` 完成、`!` 警告、`✗` 失败、`·` 信息；在无法输出 UTF-8 的地方为 `+ ! x -`）、变暗的详细信息、仅在终端上使用颜色（首先由 `LOCALSIEM_COLOR=always` 或 `never` 决定，然后依次是 `NO_COLOR`、`TERM=dumb` 和 `isatty`） | — | manage, configure |
| 密码 | [backend/security.py](../backend/security.py) | PBKDF2-SHA256（600 000 次迭代） | — | web.auth, configure |
| 配置 | [backend/core/config.py](../backend/core/config.py) | 路径（包括 `cModulesPath`）、版本、默认值、`settings.json`（`fSaveSettings`、`fRemoveSettings`）、SOC 令牌、Telegram 机器人令牌、密钥 | — | 全部 |
| 时间 | [backend/core/timeutil.py](../backend/core/timeutil.py) | 原生格式，Apache 时间转换为 UTC | — | 全部 |
| 存储接口 | [backend/core/storage.py](../backend/core/storage.py) | 每种存储实现都要实现的方法 | — | storage_sqlite |
| SQLite 存储 | [backend/core/storage_sqlite.py](../backend/core/storage_sqlite.py) | 模式、记录、事件、分组、队列、状态、数据保留、搜索、查询编译器、按模块和告警的计数 | query | collector, web, 模块 |
| 搜索语言 | [backend/core/query.py](../backend/core/query.py) | 分词器和解析为树的解析器；带位置的错误 | — | storage_sqlite, web |
| 文件读取器 | [backend/core/tailer.py](../backend/core/tailer.py) | 位置、轮转（create 和 copytruncate）、截断、删除、替换、积压 | — | collector |
| 模块注册表 | [backend/core/registry.py](../backend/core/registry.py) | 查找已安装的模块目录（`cModulesPath`），检查 `module.json`，加载类（命名空间包 `localsiem_modules`），创建实例，检查其前提条件（`fCheckRequirements`），设置的默认值和校验 | config, module, timeutil | collector, web, manage, catalog |
| 模块接口 | [backend/core/module.py](../backend/core/module.py) | 基类 `Module`（钩子、前提条件、覆盖 `module.json` 的设置、启用/停用）和行分帧器 | registry | 所有模块 |
| 规则引擎 | [backend/core/rules.py](../backend/core/rules.py) | YAML 规则：匹配、阈值、序列；为 Web 服务描述模块的规则目录 | PyYAML | collector, api_modules |
| 分组 | [backend/core/grouping.py](../backend/core/grouping.py) | 分组、窗口、缓冲、`external_id` | storage | collector |
| SOC 投递 | [backend/core/soc.py](../backend/core/soc.py) | 告警格式、客户端、发送线程、心跳、错误处理 | storage, config | collector, web, manage |
| 通知渠道 | [backend/core/channels.py](../backend/core/channels.py) | 除 SOC 之外发给管理员的消息：设置（`fChannelSettings`）、15 种语言的文本（`lLanguages`；缺失某种语言时使用英语：`fBuildMessage`、`fTestMessage`）、Telegram 客户端（`TelegramClient`）、发送线程（`ChannelSender`）及其状态 `channels.status` | config, masking, timeutil | collector, web |
| 健康检查 | [backend/core/health.py](../backend/core/health.py) | 反取证通知、未解析的行、静默的来源、磁盘 | storage | collector |
| 脱敏 | [backend/core/masking.py](../backend/core/masking.py) | 敏感参数、JSON 键、请求头、ModSecurity 数据 | — | 模块 |
| 本地套接字 | [backend/core/ipc.py](../backend/core/ipc.py) | 基于 Unix 套接字（开发时为抽象套接字）的 JSON：Web 服务发给采集器的命令 | — | collector, web |
| 模块目录 | [backend/core/catalog.py](../backend/core/catalog.py) | `localSIEM-modules` 仓库的归档文件（设置 `modules_repository`）：下载、安全解压、将其中的 `mod-<id>` 目录与已安装的内容进行比较（`action`、`newer`）、以原子方式安装或更新到 `<id>/`（`previous`、`access_changed`）以及卸载，每次只执行一个操作，root 命令（`manage.py setup-modules`） | config, registry | web（`api_modules`） |
| 已安装的模块 | `/opt/localsiem/modules/<name>/`，由 Web 服务从 `localSIEM-modules` 仓库安装（目前有 `apache2` 和 `privesc`，在该仓库中的目录为 `mod-apache2/` 和 `mod-privesc/`） | Apache：发现、解析、关联、所采取的动作、严重级别、规则、富化、诊断、前提条件（Apache 和 ModSecurity 2）、健康检查、请求详情卡片。privesc：权限提升。在该项目中有文档说明 | core | collector, web, manage |
| Web 应用 | [backend/web/app.py](../backend/web/app.py) | 两个仪表板的页面及其重定向（用户和模块的各个部分、模块页面的旧 URL）、身份验证、账户、防护（允许的 IP、安全响应头） | context, api_* | server |
| Web 上下文 | [backend/web/context.py](../backend/web/context.py) | 设置、账户、事件数据库（只读）、带指纹的 `index.html`、采集器套接字、模块清单、用于 Web 钩子的实例以及 Web 服务检查过的前提条件（`dRequirements`） | auth, webdb, registry | web |
| 账户与会话 | [backend/web/auth.py](../backend/web/auth.py), [webdb.py](../backend/web/webdb.py), [totp.py](../backend/web/totp.py) | 用户、会话（带有其方式：密码或令牌）、锁定、CSRF、TOTP、允许的 IP、直接登录的访问令牌、登录记录、搜索审计 | security | web, manage, configure |
| 搜索 API | [backend/web/api_search.py](../backend/web/api_search.py) | 搜索、直方图、摘要、导出、请求详情卡片（每个模块添加自己的字段）、告警、实时 WebSocket | storage, query | web |
| 模块与概览 API | [backend/web/api_modules.py](../backend/web/api_modules.py) | 每个模块的状态及其原因（包括缺少前提条件）、单个模块的详细信息（设置、前提条件、来源、诊断、规则）、保存这些内容（只有满足前提条件时才能启用）、重新配置、从仓库安装或更新（同一个调用；只有在首次安装时，不满足前提条件的模块才会被停用；`access_changed`）以及卸载、仪表板的概览 | registry, catalog, rules, storage, config | web |
| 管理 API | [backend/web/api_admin.py](../backend/web/api_admin.py) | 用户、SOC、通知渠道、设置、审计 | storage, soc, channels, config | web |
| 前端 | [frontend/](../frontend/) | 一个 HTML 外壳、`common.js`、`app.js`（两个仪表板以及用户、通知渠道和模块各部分的路由器，登录）、`overview.js`、`search.js`（搜索、实时视图、告警、账户）、`modules.js`（管理员的 已安装 和 可安装 部分：每个已安装模块一行，当仓库有新版本时带有更新，以及仓库中尚未安装的模块，仓库的响应保存 10 分钟；单个模块的页面，带有其前提条件和重新配置）、`admin.js`（用户及其账户和访问令牌、SOC、带有常规和 Telegram 的通知渠道、设置、审计、登录记录）、SOC 的样式表加上 `localsiem.css`、15 种语言（he-IL 从右到左） | — | 浏览器 |
| 部署 | [deploy/](../deploy/) | 只安装核心的安装程序，从 GitHub 或副本运行（一个操作：安装、更新、从零重新安装或卸载；缺失的软件包、下载、通过 `manage.py setup-modules --no-restart` 授予对已安装模块的 `read_paths` 的读取权限）、`configure.py`（设置、证书、凭据、`modules_repository`）、systemd 单元、OpenRC 脚本、certbot 钩子、logrotate | manage, registry | root |

<a id="symbols"></a>
## 3. 关键符号

| 符号 | 文件:行 | 作用 |
|---|---|---|
| `Collector` | [backend/collector.py:58](../backend/collector.py#L58) | 采集器：初始化、主循环、所有周期性任务 |
| `Collector.mSetup` | [backend/collector.py:104](../backend/collector.py#L104) | 加载模块（`fCreateModules`）、每个模块的 `mStart` 和关联器，记录 «Modules: ...»，前提条件、规则、发现、待处理的记录 |
| `Collector.mCheckRequirements` | [backend/collector.py:134](../backend/collector.py#L134) | 在启动和重新加载时检查每个模块的前提条件（`fCheckRequirements`）：供 Web 服务使用的状态 `<name>.requirements`；记录缺失的前提条件；从不启用或停用模块 |
| `Collector.mDiscover` | [backend/collector.py:163](../backend/collector.py#L163) | 已启用模块的来源；打开新来源（从其末尾开始，除非该模块已在被跟踪：`sFollowedModules`），并关闭已消失的来源 |
| `Collector.mReloadSettings` | [backend/collector.py:211](../backend/collector.py#L211) | 新设置：模块、前提条件、分组、规则、发现、诊断，并立即发布状态 |
| `Collector.mDiscoveryInterval` | [backend/collector.py:316](../backend/collector.py#L316) | 已启用模块中最短的发现间隔（至少 60 秒） |
| `Collector.mReadSources` | [backend/collector.py:327](../backend/collector.py#L327) | 轮询每个来源（追赶时会进行均衡）、分帧、解析、存储记录和位置 |
| `Collector.mWatermark` | [backend/collector.py:416](../backend/collector.py#L416) | 模块中落后的来源已读取到的最早日志时间 |
| `Collector.mProcessDue` | [backend/collector.py:424](../backend/collector.py#L424) | 为到期的事务构建事件、运行规则、存储、检测 |
| `Collector.mProcessGroups` | [backend/collector.py:485](../backend/collector.py#L485) | 已过缓冲期的分组：富化、告警、SOC 队列 |
| `Collector.mRetention` | [backend/collector.py:534](../backend/collector.py#L534) | 按天数和按大小删除，增量 vacuum |
| `Collector.mPublishState` | [backend/collector.py:569](../backend/collector.py#L569) | `collector.status`：来源、磁盘、数据库、规则、跳过的日志、每个模块的状态（`enabled`、`version`、`sources`、`pending`）以及 `module_errors` |
| `Collector.mPublishDoctor` | [backend/collector.py:612](../backend/collector.py#L612) | 每个模块的 `<name>.doctor`（已停用的模块为空） |
| `Collector.mHandleIpc` | [backend/collector.py:624](../backend/collector.py#L624) | Web 服务的命令：reload（也来自重新配置）、doctor、restart（通过 Web 界面安装、更新或卸载了模块）、SOC 重试以及被拒绝告警的重新排队；还有 heartbeat 和 status |
| `fListManifests` | [backend/core/registry.py:165](../backend/core/registry.py#L165) | 带有 `module.json` 的已安装模块目录（在 `cModulesPath` 中，按名称排列）；错误单独列出 |
| `fReadManifest` | [backend/core/registry.py:133](../backend/core/registry.py#L133) | 检查 `module.json`（id：目录名，或者对于 `mod-<id>` 目录，由 catalog 给出的 id；entry、settings、`core`），填充其默认值并读取其语言文件 |
| `fCheckInstallRequirements` | [backend/core/registry.py:97](../backend/core/registry.py#L97) | 检查 `module.json` 的 `install_requirements`（由 `fReadManifest` 调用）：`lSystems` 中的系统（`debian`、`alpine`），1 到 20 条单行命令，不含 shell 运算符（`cShellOperatorRegex`），因为 Web 界面会在每条命令前加上 `sudo` |
| `fLoadClass` | [backend/core/registry.py:197](../backend/core/registry.py#L197) | 在 `fRegisterPackage` 之后导入 `localsiem_modules.<name>.<file>` 并检查类 |
| `fCreateModules` | [backend/core/registry.py:229](../backend/core/registry.py#L229) | `({name: module}, manifests, errors)`；某个模块失败从不会阻止其他模块 |
| `fCheckRequirements` | [backend/core/registry.py:214](../backend/core/registry.py#L214) | 以 `{time, checks, met}` 的形式返回模块的 `mRequirements()`（met：没有任何检查为错误；异常视为不满足） |
| `fModuleSettings` | [backend/core/registry.py:250](../backend/core/registry.py#L250) | `module.json` 的默认值，其上叠加 `settings.json` 中的 `modules.<name>` |
| `fValidateSettings` | [backend/core/registry.py:317](../backend/core/registry.py#L317) | 根据 `module.json` 检查管理员保存的内容；`ValueError("invalid_setting:<key>")` |
| `Module` | [backend/core/module.py:59](../backend/core/module.py#L59) | 模块的接口：`mModuleSettings`、`mEnabled`、`mStart`、`mDiscoveryInterval`、`mDiscover`、`mParse`、`mBuildEvent`、`mDoctor`、`mRequirements`、`mSkipped`、`mSetLowDisk`、`mDisplayRecord`... |
| `FileTailer` | [backend/core/tailer.py:37](../backend/core/tailer.py#L37) | 一个被跟踪的文件，以只读方式打开：位置（在首次保存位置之前为 `vOpenedUnsaved`）、轮转、截断、删除；`vWasReadable`（在本次运行中打开过，或者之前的运行保存过位置）：`unreadable` 通知会以 `was_readable` 的形式携带它 |
| `FileTailer.mPoll` | [backend/core/tailer.py:250](../backend/core/tailer.py#L250) | 读取新的完整行及其偏移量，以及通知 |
| `SqliteStorage` | [backend/core/storage_sqlite.py:303](../backend/core/storage_sqlite.py#L303) | SQLite 存储 |
| `SqliteStorage.mSaveRecords` | [backend/core/storage_sqlite.py:392](../backend/core/storage_sqlite.py#L392) | 在一个事务中保存记录、全文索引和位置 |
| `fCompileQuery` | [backend/core/storage_sqlite.py:281](../backend/core/storage_sqlite.py#L281) | 将搜索树转换为带参数的 SQL |
| `SqliteStorage.mSearch` | [backend/core/storage_sqlite.py:878](../backend/core/storage_sqlite.py#L878) | 带时间分页和时间限制的搜索 |
| `SqliteStorage.mGetIpContext` | [backend/core/storage_sqlite.py:504](../backend/core/storage_sqlite.py#L504) | 某个 IP 被拦截的请求数和请求总数，首次出现的时间 |
| `SqliteStorage.mCountRecentEvents` | [backend/core/storage_sqlite.py:539](../backend/core/storage_sqlite.py#L539) | 某个模块自某个时间以来的事件数及其最活跃的 IP（模块的健康检查） |
| `SqliteStorage.mModuleCounts` | [backend/core/storage_sqlite.py:708](../backend/core/storage_sqlite.py#L708) | 每个模块的事件数、被拦截数、触发告警数和最后时间 |
| `SqliteStorage.mAlertCounts` | [backend/core/storage_sqlite.py:720](../backend/core/storage_sqlite.py#L720) | 自某个时间以来创建的告警，按状态和按严重级别统计 |
| `SqliteStorage.mGetEventDetail` | [backend/core/storage_sqlite.py:949](../backend/core/storage_sqlite.py#L949) | 一个事件及其记录（每条记录都带有其 `module`）、规则命中和告警 |
| `SqliteStorage.mGroupEvents` | [backend/core/storage_sqlite.py:1011](../backend/core/storage_sqlite.py#L1011) | 告警的请求（`event_alerts`）：最多 50 个（`api_search.py` 中的 `cAlertEvents`），最早的在前，带有搜索的各列，以及其总数；`GET /api/alerts/{id}` 以 `events` 和 `events_total` 返回它们 |
| `fAlertRequests` / `fBindRows` | [frontend/assets/search.js:687](../frontend/assets/search.js#L687) / [:259](../frontend/assets/search.js#L259) | 在告警展开的行中显示该告警的请求（告警），使用搜索的行（`fResultRow`）；点击会打开其请求详情卡片（`fToggleRow` → `fRequestCard`）。`fBindRows` 只忽略其自身表格中卡片内部的点击，因此它在告警展开的行中也能工作；展开某条告警时，告警列表不会刷新 |
| `fParseQuery` | [backend/core/query.py:232](../backend/core/query.py#L232) | 将查询文本转换为树；带代码和位置的 `QueryError` |
| `RulesEngine` / `Rule` | [backend/core/rules.py:319](../backend/core/rules.py#L319) / [:93](../backend/core/rules.py#L93) | 加载并评估 YAML 规则 |
| `fDescribeFolder` | [backend/core/rules.py:54](../backend/core/rules.py#L54) | 模块目录中由其文件定义的规则，包括已停用的规则（模块页面） |
| `Grouper` | [backend/core/grouping.py:38](../backend/core/grouping.py#L38) | 将检测结果放入分组（窗口、缓冲） |
| `fExternalId` | [backend/core/grouping.py:31](../backend/core/grouping.py#L31) | 确定性的 `external_id` |
| `fBuildAlert` | [backend/core/soc.py:67](../backend/core/soc.py#L67) | 将分组转换为 `GenericAlert`（时间采用存储格式） |
| `SocSender.mDeliver` | [backend/core/soc.py:256](../backend/core/soc.py#L256) | 发送一批告警；遇到 413/422 时拆分；处理 401、507 和网络错误 |
| `fSocConfigured` / `SqliteStorage.mSkipPending` | [backend/core/soc.py:43](../backend/core/soc.py#L43) / [backend/core/storage_sqlite.py:630](../backend/core/storage_sqlite.py#L630) | 是否有可发送的 SOC（URL、令牌、`soc_enabled`）；没有时，待发送的内容变为 `local`（未发送） |
| `ChannelSender.mNotify` / `ChannelSender.mDeliver` | [backend/core/channels.py:330](../backend/core/channels.py#L330) / [:414](../backend/core/channels.py#L414) | 采集器将其放入 SOC 队列的每条告警都交给它：`min_severity` 及以上的告警会进入每个已启用且已设置的通知渠道的列表（最多 200 条；丢弃最早的一条）；每秒一条消息；出错时重试（`retry_after`，逐渐增加的等待时间）或丢弃（400、401、403、404 或 5 次尝试） |
| `TelegramClient.mCall` / `fBuildMessage` | [backend/core/channels.py:273](../backend/core/channels.py#L273) / [:226](../backend/core/channels.py#L226) | POST 到 `https://api.telegram.org/bot<token>/<method>`；失败时为 `TelegramError`（状态码、描述、`retry_after`），其中从不携带令牌。消息内容：严重级别、规则、描述、模块、事件数、首次和末次时间（显示格式）以及搜索，使用通知渠道的语言 |
| `HealthMonitor` | [backend/core/health.py:110](../backend/core/health.py#L110) | 未解析的行、静默的来源、磁盘级别 |
| `fNoticeDetection` | [backend/core/health.py:58](../backend/core/health.py#L58) | 来源通知（truncated、missing、replaced、unreadable、rotated_lost）对应的告警。只有在 `was_readable` 时才会对 `unreadable` 告警：从未读取过的日志（刚安装的模块，在 `setup-modules` 之前）只体现在其来源的状态中，采集器会记录它但不产生告警（`Collector.mHandleNotice`） |
| `Masker` | [backend/core/masking.py:17](../backend/core/masking.py#L17) | 对参数、JSON、请求头和 ModSecurity 数据进行脱敏 |
| `fCreateApp` | [backend/web/app.py:114](../backend/web/app.py#L114) | 构建 FastAPI 应用、其页面和防护 |
| `fUserTab` / `fAdminTab` | [backend/web/app.py:196](../backend/web/app.py#L196) / [:211](../backend/web/app.py#L211) | 每个仪表板的标签页以及到角色对应仪表板的重定向；`users` 和 `modules` 会跳转到其第一个部分（`users/accounts/`、`modules/installed/`） |
| `fAdminUsersSection` | [backend/web/app.py:232](../backend/web/app.py#L232) | 用户的各个部分：`accounts`（默认）和 `tokens` |
| `fAdminModulesSection` | [backend/web/app.py:264](../backend/web/app.py#L264) | 模块的各个部分（`lModuleSections`）：`installed`（默认）和 `installable`；首先检查会话（没有会话时跳转到登录），分析师会跳转到 `/user/dashboard/modules/`；模块的旧 URL `/admin/dashboard/modules/<name>/` 在模块已安装时以 301 跳转到 `installed/<name>/`，否则返回 404 |
| `fAdminChannelsSection` | [backend/web/app.py:246](../backend/web/app.py#L246) | `/admin/dashboard/channels/general/` 和 `telegram/`（仅限管理员；其他部分：404） |
| `fLoginWithToken` | [backend/web/app.py:387](../backend/web/app.py#L387) | `/auth/login/auto?token=...`（或 `?TOKEN`）：直接登录、锁定、记录、仅限本站点的 `next` |
| `fCreateToken` / `fLogins` | [backend/web/api_admin.py:421](../backend/web/api_admin.py#L421) / [:446](../backend/web/api_admin.py#L446) | 创建访问令牌（响应中只携带一次）；列出登录记录（按结果筛选，超过 `alert_retention_days` 后清除） |
| `fAdminModule` | [backend/web/app.py:283](../backend/web/app.py#L283) | 单个模块的页面 `/admin/dashboard/modules/installed/<name>/`（管理员；分析师会跳转到 `/user/dashboard/modules/`；未安装的模块返回 404） |
| `WebContext.mReloadModules` | [backend/web/context.py:51](../backend/web/context.py#L51) | 通过 Web 界面安装、更新或卸载之后：重新读取 `module.json` 文件，重新导入该模块的代码，并丢弃 Web 服务为其检查过的前提条件 |
| `WebContext.mModule` | [backend/web/context.py:91](../backend/web/context.py#L91) | 用于 Web 钩子（`mDisplayRecord`）的模块实例 |
| `WebContext.mCheckRequirements` | [backend/web/context.py:105](../backend/web/context.py#L105) | 在新实例上检查已安装模块的前提条件（使用已保存的设置，或即将保存的设置）；使用已保存的设置时，结果保存在 `dRequirements` 中 |
| `fSummary` | [backend/web/api_modules.py:104](../backend/web/api_modules.py#L104) | 模块的状态（`ok`、`warning`、`error`、`pending`、`disabled`、`unknown`）及其原因（模块已停用且缺少前提条件时为 `requirements_missing`）、`has_requirements` 和 `requirements_missing` |
| `fRequirements` / `fMissing` | [backend/web/api_modules.py:88](../backend/web/api_modules.py#L88) / [:99](../backend/web/api_modules.py#L99) | 模块最新的前提条件检查（采集器的或 Web 服务的）；其中不满足的检查 |
| `fRules` / `fCleanRules` | [backend/web/api_modules.py:196](../backend/web/api_modules.py#L196) / [:208](../backend/web/api_modules.py#L208) | 模块的规则及其覆盖设置；保存前检查覆盖设置 |
| `fRegisterModules` | [backend/web/api_modules.py:237](../backend/web/api_modules.py#L237) | `/api/modules`、`/api/admin/modules/{name}`（以及 `/doctor` 和 `/reconfigure`；`DELETE` 用于卸载）、`/api/admin/module-catalog`、`/api/overview` |
| `fReconfigure` / `fFirstInstallation` | [backend/web/api_modules.py:338](../backend/web/api_modules.py#L338) / [:369](../backend/web/api_modules.py#L369) | 重新配置：再次检查前提条件，采集器 `reload`，满足时返回 root 命令（从不启用模块）；首次安装：缺少某项前提条件且从未保存过 `modules.<name>.enabled` 时停用模块 |
| `fOverview` | [backend/web/api_modules.py:439](../backend/web/api_modules.py#L439) | 概览的数据：24 小时计数、每小时直方图、模块、SOC、采集器、磁盘、最新告警 |
| `Accounts` | [backend/web/auth.py:128](../backend/web/auth.py#L128) | 用户、登录、TOTP、会话、锁定、访问令牌、登录记录、搜索审计 |
| `Accounts.mCreateSession` / `mLoadSession` | [backend/web/auth.py:323](../backend/web/auth.py#L323) / [:340](../backend/web/auth.py#L340) | 带有其方式（`password` 或 `token`）的会话；令牌会话既不要求第二因素也不要求修改密码，并且只有分析师才能保持它；启用 `mfa_enabled` 时，没有第二因素的账户的密码会话无效 |
| `fSaveSettingsRoute` | [backend/web/api_admin.py:358](../backend/web/api_admin.py#L358) | 管理员面板的设置，包括 `mfa_enabled`（当启用它结束了正在保存设置的管理员的会话时返回 `session_closed`） |
| `fChannels` / `fSaveChannels` / `fSaveTelegram` / `fTestTelegram` | [backend/web/api_admin.py:230](../backend/web/api_admin.py#L230) / [:252](../backend/web/api_admin.py#L252) / [:275](../backend/web/api_admin.py#L275) / [:309](../backend/web/api_admin.py#L309) | 通知渠道的设置和状态（令牌已脱敏、`bot_id`）；常规设置（`enabled`、`min_severity`、`language`）；Telegram（令牌保存在 `config/telegram-bot-token` 中、`chat_id`、只有两者都具备时才能设置 `enabled`：`telegram_incomplete`；`remove_token`）；使用已保存的值发送测试消息（`getMe` + `sendMessage`） |
| `Accounts.mCreateAccessToken` / `mCheckAccessToken` | [backend/web/auth.py:371](../backend/web/auth.py#L371) / [:412](../backend/web/auth.py#L412) | 为已启用的分析师创建令牌（1 到 365 天，只保存其 SHA-256，只显示一次）；返回用户，或者它无法打开会话的原因 |
| `Accounts.mRecordLogin` | [backend/web/auth.py:440](../backend/web/auth.py#L440) | `logins` 中的一行：账户、方式（`password`、`password_totp`、`token`）、结果、原因、IP、浏览器 |
| `fEvent` | [backend/web/api_search.py:173](../backend/web/api_search.py#L173) | 请求详情卡片：事件及其记录，带有每个模块添加的字段 |
| `fLive` | [backend/web/api_search.py:225](../backend/web/api_search.py#L225) | 实时 WebSocket：只有已登录会话的 cookie 才能打开它（否则以 4401 关闭） |
| `fDownload` / `fCatalog` | [backend/core/catalog.py:121](../backend/core/catalog.py#L121) / [:171](../backend/core/catalog.py#L171) | 仓库的归档文件，安全解压；其中的模块（`mod-<id>` 目录：`fModuleFolders`）及其动作（install、update、reinstall、downgrade、incompatible、invalid）和 `newer`（已安装，且仓库中有更新的版本，包括本 localSIEM 无法安装的版本）；可安装 只列出尚未安装的模块（`installed` 为 null：install、incompatible 或 invalid），已安装 使用 `newer`（动作为 update 时显示更新；为 incompatible 时，只显示所需的 localSIEM）；每一项还带有其 `module.json` 中的 `install_requirements`（前提条件对话框） |
| `fInstall` / `InstallLock` | [backend/core/catalog.py:235](../backend/core/catalog.py#L235) / [:213](../backend/core/catalog.py#L213) | 将 `mod-<name>` 目录复制到已安装的 `<name>` 旁边，并通过重命名进行替换（安装和更新）；返回清单，其中包含 `previous`（被替换的版本，首次安装时为 `None`）和 `access_changed`（其 `read_paths` 与被替换副本的不同；首次安装时始终为 true）；每次只进行一个安装、更新或卸载操作 |
| `fRemove` / `fUninstallModule` | [backend/core/catalog.py:302](../backend/core/catalog.py#L302) / [backend/web/api_modules.py:422](../backend/web/api_modules.py#L422) | 卸载已安装的模块，包括无法加载的模块：将其目录重命名到暂存目录中然后删除；`DELETE /api/admin/modules/{name}`（目录不存在时返回 404 `module_not_installed`；之后执行 `mReloadModules` 并重启采集器） |
| `fFetchCatalog` / `fFetchAndInstall` / `fRootCommand` | [backend/core/catalog.py:330](../backend/core/catalog.py#L330) / [:337](../backend/core/catalog.py#L337) / [:372](../backend/core/catalog.py#L372) | Web 服务所运行的内容（在 `/opt/localsiem/run/` 中下载）；通过 Web 界面安装后（或带有 `access_changed` 的更新后）或重新配置后供 root 运行的命令：`manage.py setup-modules` |
| `fServerSystem` | [backend/core/catalog.py:345](../backend/core/catalog.py#L345) | 本服务器的系统，用于模块的 `install_requirements`：`family`（有 `/etc/alpine-release` 时为 `alpine`，有 `/etc/debian_version` 时为 `debian`，或者取自 `/etc/os-release` 的 `ID`/`ID_LIKE`；其他系统为空）和 `name`（`PRETTY_NAME`） |
| `fResolveRef` | [backend/core/catalog.py:91](../backend/core/catalog.py#L91) | 对于 github.com 上的仓库，获取分支或标签对应的提交（GitHub API，`Accept: application/vnd.github.sha`），以便下载的归档文件是该提交的归档，而绝不是 GitHub 缓存中的副本；对于其他仓库、归档文件、本身已是提交的 ref，或者 API 没有响应时：按原样使用该 ref。每次下载都会发送 `Cache-Control: no-cache`（`dNoCacheHeaders`） |
| `fGetCatalog` / `fInstallFromCatalog` | [backend/web/api_modules.py:384](../backend/web/api_modules.py#L384) / [:395](../backend/web/api_modules.py#L395) | `GET /api/admin/module-catalog`：仓库中的模块，带有 `installed`、`newer` 和 `action`（可安装，以及 已安装 中的更新）；`POST /api/admin/module-catalog/{name}`：安装或更新（同一个调用；`fFirstInstallation` 只在之前没有副本时运行），然后执行 `mReloadModules` 和采集器的 `restart`；响应中带有 `version`、`previous`、`enabled`、`turned_off`、`requirements_missing`、`read_paths`、`access_changed`、`root_command` 和 `collector_restarted`；`GET` 的响应中还有 `system`（`fServerSystem`），每个模块还有其 `install_requirements` |
| `fGrantReadAccess` | [backend/manage.py:116](../backend/manage.py#L116) | 授予对已安装模块的 `read_paths` 的读取权限（ACL、默认 ACL，在 Debian 上还有 `adm` 组）；由 `setup-modules` 运行 |
| `fConfigureCredentials` / `fEnsureAdmin` | [deploy/configure.py:247](../deploy/configure.py#L247) / [:340](../deploy/configure.py#L340) | `localsiem.env`：JWT 密钥，只在新安装时或使用 `--rotate-credentials` 时创建（该选项现在只表示生成新的 JWT 密钥）；每次运行时都会移除旧版本为远程输入保留的变量（`lRemovedEnvironment`），并最多返回一个条目块（系统用户和 JWT 签名密钥）；第一个 Web 账户 `admin`。`fMain` 先将 `admin` 的条目块写入 `/root/webapp-credentials.txt`，然后写入 `fConfigureCredentials` 返回的条目块，即使后续步骤失败也是如此 |
| `fConfigureSettings` / `fRemoveSettings` | [deploy/configure.py:220](../deploy/configure.py#L220) / [backend/core/config.py:194](../backend/core/config.py#L194) | 提供给安装程序的设置，保存到 `settings.json`；移除已不再存在的功能所存储的键（`lRemovedSettings`：`http_input`），只有当其中某个键存在时才写入文件 |
| `lLanguages` / `lRightToLeftLanguages` | [backend/core/config.py:46](../backend/core/config.py#L46) / [:50](../backend/core/config.py#L50) | 15 种语言（按字母顺序；en-US 是原始语言和回退语言）以及从右到左书写的语言（he-IL）；`common.js` 中的 `cLanguages` 和 `cRightToLeft` 是供 Web 界面使用的相同列表 |
| `fConfigureCertificates` | [deploy/configure.py:277](../deploy/configure.py#L277) | 提供的证书、Let's Encrypt（带部署钩子）、现有证书或自签名证书 |
| `fGetSource` | [deploy/install-update-reinstall-debian.sh:525](../deploy/install-update-reinstall-debian.sh#L525) / [alpine.sh:524](../deploy/install-update-reinstall-alpine.sh#L524) | 安装程序运行所在的完整副本，或者 GitHub 的归档文件（`--ref`、`--source-url`），解压到 `/tmp/localsiem-install.*` 中 |
| `fResolveRef`（安装程序） | [deploy/install-update-reinstall-debian.sh:504](../deploy/install-update-reinstall-debian.sh#L504) / [alpine.sh:503](../deploy/install-update-reinstall-alpine.sh#L503) | `--ref`（默认 `main`）对应的提交，通过不带缓存的 GitHub API 查询；`fGetSource` 下载该提交的归档文件，或者在 API 没有响应时发出警告并下载分支的归档文件。每个 `curl` 都会发送 `Cache-Control: no-cache`（`aNoCache`） |
| `fEnsurePackages` | [deploy/install-update-reinstall-debian.sh:479](../deploy/install-update-reinstall-debian.sh#L479) / [alpine.sh:483](../deploy/install-update-reinstall-alpine.sh#L483) | 只安装缺失的软件包；只有在这种情况下才运行 `apt-get update` / `apk update` |
| `fGrantLogAccess` | [deploy/install-update-reinstall-debian.sh:585](../deploy/install-update-reinstall-debian.sh#L585) / [alpine.sh:584](../deploy/install-update-reinstall-alpine.sh#L584) | 每次更新时授予对已安装模块目录的读取权限：`manage.py setup-modules --no-restart` |
| `fIsInstalled` | [deploy/install-update-reinstall-debian.sh:462](../deploy/install-update-reinstall-debian.sh#L462) / [alpine.sh:466](../deploy/install-update-reinstall-alpine.sh#L466) | localSIEM 的任何痕迹（`/opt/localsiem`、其 systemd 单元或 OpenRC 脚本，或者主目录为该目录的 `localsiem` 用户）：存在痕迹时 `--install` 会停止；不存在时 `--update` 和 `--reinstall` 会停止 |
| `fConfirmRemoval` / `fRemoveInstallation` / `fUninstall` | [deploy/install-update-reinstall-debian.sh:710](../deploy/install-update-reinstall-debian.sh#L710) / [:749](../deploy/install-update-reinstall-debian.sh#L749) / [:817](../deploy/install-update-reinstall-debian.sh#L817); [alpine.sh:694](../deploy/install-update-reinstall-alpine.sh#L694) / [:733](../deploy/install-update-reinstall-alpine.sh#L733) / [:808](../deploy/install-update-reinstall-alpine.sh#L808) | 由 `--uninstall` 和 `--reinstall` 共用。`fConfirmRemoval`：列出将被删除的内容，除非使用 `--yes`，否则在 `/dev/tty` 上要求输入 `yes`（取消不算错误：`vConfirmed` 保持为空）。`fRemoveInstallation`：服务、进程、ACL（`fRemoveReadAccess`）、apache2 模块 1.2.0 及更早版本的 `--configure-apache` 添加的 Apache 文件（`fRemoveApacheSetup`；`localsiem_access.log*` 会保留）、logrotate、Let's Encrypt 钩子、用户和组、`/opt/localsiem`、之前运行在 `/tmp/localsiem-install.*` 中留下的副本（不包括本次运行的副本）以及 `/root/webapp-credentials.txt` 中的 localSIEM 条目块（`fRemoveCredentials`）。`fUninstall`：`--uninstall`，并开始写入其自己的日志。当它没有删除任何内容时（`vRemovedAny` 为空），`fUninstall` 会显示 «Nothing of localSIEM was found on this server.» |
| `fInitStyle` / `fStartLog` / `fSplitOutput` / `fStopLog` | [deploy/install-update-reinstall-debian.sh:129](../deploy/install-update-reinstall-debian.sh#L129) / [:283](../deploy/install-update-reinstall-debian.sh#L283) / [:291](../deploy/install-update-reinstall-debian.sh#L291) / [:324](../deploy/install-update-reinstall-debian.sh#L324); [alpine.sh:128](../deploy/install-update-reinstall-alpine.sh#L128) / [:282](../deploy/install-update-reinstall-alpine.sh#L282) / [:290](../deploy/install-update-reinstall-alpine.sh#L290) / [:323](../deploy/install-update-reinstall-alpine.sh#L323) | 安装程序的输出：仅在终端上使用颜色（只决定一次，并以 `LOCALSIEM_COLOR` 的形式传递给它们运行的 Python 工具）。日志打开后，stdout 和 stderr 成为一个有序的流，由 `fSplitOutput`（纯 bash，在 Alpine 的 BusyBox 上也一样）发送到屏幕，并在去除颜色代码后发送到 `/root/webapp-install.log`；标记为 `cLogOnly` 或 `cScreenOnly` 的行只发往其中一侧（`fToLog`、`fToScreen`：时间在屏幕上采用显示格式，在日志中采用存储格式）。`fStopLog` 由 `fCleanup` 调用，会等待其最后几行 |
| `fStep` / `fRun` / `fRunToLog` / `fShowOutputTail` | [deploy/install-update-reinstall-debian.sh:177](../deploy/install-update-reinstall-debian.sh#L177) / [:359](../deploy/install-update-reinstall-debian.sh#L359) / [:343](../deploy/install-update-reinstall-debian.sh#L343) / [:379](../deploy/install-update-reinstall-debian.sh#L379); [alpine.sh:176](../deploy/install-update-reinstall-alpine.sh#L176) / [:358](../deploy/install-update-reinstall-alpine.sh#L358) / [:342](../deploy/install-update-reinstall-alpine.sh#L342) / [:378](../deploy/install-update-reinstall-alpine.sh#L378) | 编号步骤（`[3/12] Getting localSIEM`；`vStepTotal`：安装或更新为 12，重新安装为 13，卸载为 2）以及结果行（`fOk` ✓、`fWarn` !、`fFail` ✗、`fInfo` ·、`fDetail`）。`fRun` 运行一个输出只写入日志的命令（`fRunToLog`：`$ command` 及其输出行，stdin 为 `/dev/null`），并显示一行，失败时显示其最后 20 行（`fShowOutputTail`）：apt-get 或 apk、curl、tar、pip、venv、用户和服务 |
| `fShowHeader` / `fShowNextSteps` / `fShowFailure` | [deploy/install-update-reinstall-debian.sh:264](../deploy/install-update-reinstall-debian.sh#L264) / [:848](../deploy/install-update-reinstall-debian.sh#L848) / [:392](../deploy/install-update-reinstall-debian.sh#L392); [alpine.sh:263](../deploy/install-update-reinstall-alpine.sh#L263) / [:839](../deploy/install-update-reinstall-alpine.sh#L839) / [:391](../deploy/install-update-reinstall-alpine.sh#L391) | 页眉（操作、服务器、系统、开始时间、日志）；结束时显示摘要（Web 界面和 SIEM 的地址、凭据、日志、SOC）和后续步骤；失败时显示停止的步骤 |
| `fTokensSection` / `LocalsiemViews.logins` | [frontend/assets/admin.js:183](../frontend/assets/admin.js#L183) / [:828](../frontend/assets/admin.js#L828) | 用户 › 访问令牌（创建、只显示一次 URL、撤销）；登录记录 |
| `LocalsiemViews.channels` / `fChannelsGeneralSection` / `fTelegramSection` | [frontend/assets/admin.js:420](../frontend/assets/admin.js#L420) / [:431](../frontend/assets/admin.js#L431) / [:516](../frontend/assets/admin.js#L516) | 通知渠道标签页及其子标签页（`fChannelSections`）：常规（全部启用或停用、最低严重级别、语言、每个通知渠道一行及其状态）和 Telegram（令牌、聊天 ID、«保存并发送测试消息»、«移除令牌»、状态、设置步骤）；状态每 15 秒刷新一次 |
| `ldTabs` / `fRoute` | [frontend/assets/app.js:19](../frontend/assets/app.js#L19) / [:356](../frontend/assets/app.js#L356) | 两个仪表板的标签页；路由器，它将另一个仪表板的 URL 带到自己的仪表板，打开用户、通知渠道和模块的第一个部分（`lUserSections`、`lChannelSections`、`lModuleSections`），将旧的 `/admin/dashboard/modules/<name>/` 带到 `modules/installed/<name>/`，并在其他任何地方丢弃第二部分；`fShowView` 为 `modules/installed/<name>/` 绘制 `LocalsiemViews.module` |
| `fLoginView` / `fDone` | [frontend/assets/app.js:97](../frontend/assets/app.js#L97) / [:153](../frontend/assets/app.js#L153) | 登录表单，其按钮下方有语言和主题（`fLanguageSelect` / `fThemeToggle`，[common.js:590](../frontend/assets/common.js#L590) / [:602](../frontend/assets/common.js#L602)）；登录后，点击按钮时显示的语言会成为账户的语言（`PATCH /api/account`） |
| `LocalsiemViews.overview` | [frontend/assets/overview.js:26](../frontend/assets/overview.js#L26) | 概览标签页 |
| `LocalsiemViews.modules` / `.module` | [frontend/assets/modules.js:389](../frontend/assets/modules.js#L389) / [:683](../frontend/assets/modules.js#L683) | 模块标签页：对于管理员，显示各个部分（`fModuleSections`），在 已安装 中，每个已安装模块占一整行，布局与模块页面的页眉相同，各部分上下排列（`fCard`：`.module-head` 包含名称、ID 和版本，对于管理员，右侧还有启用/停用开关，缺少前提条件时被锁定；状态、摘要和原因，对于管理员，还有新版本提示 `fUpdateNotice`；其计数器；对于管理员，底部还有 `fCardActions`）；分析师只能看到这些行。单个模块的页面 `installed/<name>/`（前提条件和重新配置；«返回已安装模块» 和卸载会跳转到 `installed/`） |
| `fModuleSections` | [frontend/assets/modules.js:194](../frontend/assets/modules.js#L194) | 模块的子标签页 已安装 和 可安装，每个都是指向其 URL 的链接（类似 `admin.js fUserSections`） |
| `fCatalogPanel` | [frontend/assets/modules.js:218](../frontend/assets/modules.js#L218) | 可安装 部分：检查仓库（`fCheck` → `fFetchCatalog(true)`：始终重新下载）；只显示尚未安装的模块，带有安装按钮（或者无法安装的原因：incompatible、invalid）；没有模块时显示 `catalog.all_installed` 或 `catalog.empty`；安装某个模块会丢弃已保存的响应（`fForgetCatalog`），将其从列表中移除，并打开一个对话框（`P.fModal`、`fResult`），其中显示供 root 运行的命令或服务器所缺少的内容，以及 «查看已安装模块»；每个尚未安装的模块在 **安装** 之前都有 **前提条件**：`fShowRequirements` → `fRequirementsBody`（模块的说明以及 `system.family` 的 `install_requirements`，或者通过 `fRequirementCommands` 显示它所声明的所有系统的命令：以 root 身份和前面加上 `sudo` 两种形式，每种都放在带有 «复制» 的 `fCommandBox` 中） |
| `cCatalogSeconds` / `fFetchCatalog` / `fForgetCatalog` | [frontend/assets/modules.js:174](../frontend/assets/modules.js#L174) / [:177](../frontend/assets/modules.js#L177) / [:186](../frontend/assets/modules.js#L186) | `GET /api/admin/module-catalog` 的最后一次响应，保存在浏览器中（`dCatalogCache`）600 秒，由 已安装 和 可安装 共享，这样打开 已安装 时就不会每次都下载仓库；`fFetchCatalog(true)`（检查仓库）始终重新下载；安装、更新或卸载模块会丢弃它 |
| `fCheckRepository` / `fUpdateNotice` | [frontend/assets/modules.js:543](../frontend/assets/modules.js#L543) / [:417](../frontend/assets/modules.js#L417) | 已安装，仅限管理员：在打开该部分时执行一次，`fFetchCatalog(false)` → `dNewer`（带有 `newer` 且动作为 update 或 incompatible 的项），期间显示 `modules.checking_updates`，失败时显示 `modules.updates_failed`（列表照常工作）；10 秒一次的刷新从不执行此操作。行中的提示（`.module-update`）：带有更新按钮的 `modules.update_notice`，或者不带按钮的 `modules.update_incompatible`（`.module-update-blocked`）；仅当已安装版本就是与仓库比较时的版本时才显示 |
| `fUpdate` / `fUpdateResult` | [frontend/assets/modules.js:452](../frontend/assets/modules.js#L452) / [:436](../frontend/assets/modules.js#L436) | 更新：确认（`modules.update_confirm`）、`POST /api/admin/module-catalog/{name}`（期间按钮显示 «更新中…»：`sUpdating`，在多次刷新之间也会保持）、`fForgetCatalog`、toast 提示 `modules.updated_toast`；只有在有 `access_changed`（供 root 运行的命令）或没有 `collector_restarted` 时才显示对话框（«<module> 已更新»）；然后执行 `fLoad` |
| `fDraw` / `fLoad`（已安装） | [frontend/assets/modules.js:517](../frontend/assets/modules.js#L517) / [:531](../frontend/assets/modules.js#L531) | `fLoad`（每 10 秒一次）只请求 `GET /api/modules` 并保存响应（`dLast`）；`fDraw` 根据它绘制各行，在仓库检查结束时以及更新开始时也会绘制 |
| `fCheckItem` / `fCommandBox` | [frontend/assets/modules.js:70](../frontend/assets/modules.js#L70) / [:61](../frontend/assets/modules.js#L61) | 一项检查（诊断、前提条件）及其修复方法；一段要复制的文本（供 root 运行的命令） |
| `fUninstallButton` / `fCardActions` | [frontend/assets/modules.js:146](../frontend/assets/modules.js#L146) / [:508](../frontend/assets/modules.js#L508) | 卸载，带确认（已安装 中的行和模块页面；它会丢弃已保存的仓库响应，`fForgetCatalog`）；管理员在一行中的操作：配置（→ `installed/<name>/`）和卸载 |
| `fInput` / `fRecordsEditor` | [frontend/assets/modules.js:586](../frontend/assets/modules.js#L586) / [:612](../frontend/assets/modules.js#L612) | 根据 `module.json` 构建的设置表单，包括记录编辑器 |

<a id="flows"></a>
## 4. 主要调用路径

**加载模块（采集器启动）**

`Collector.mSetup` → `fCreateModules` → `fListManifests`（`cModulesPath/*/module.json`）→ `fReadManifest`（id、entry、settings、`core` ≤ `cVersion`、语言文件）→ `fLoadClass`（`fRegisterPackage` + `localsiem_modules.<name>.<file>`）→ `Class(settings, masker, storage, manifest)` → `Module.mStart` → `mCreateCorrelator` → 记录 «Modules: apache2 1.1.0 (on)» → `mCheckRequirements`（`fCheckRequirements` → 每个模块的 `Module.mRequirements` → 状态 `<name>.requirements`；缺少前提条件时记录 «Module apache2: requirements missing: ...»）→ `mLoadRules` → `mDiscover`（仅限已启用的模块）→ `mPublishDoctor`。错误会进入 `ldModuleErrors`，循环继续。

**从日志行到 SOC 中的告警**

1. `Collector.mCycle` → `mReadSources` → `FileTailer.mPoll`（新的完整行）→ 来源的分帧器（`Module.mCreateFramer`：`LineFramer`，或 Apache 模块的审计分帧器）→ 来源所属模块的 `Module.mParse`（脱敏）→ `mStoreRecords` → `SqliteStorage.mSaveRecords`（记录 + FTS + 位置，一个事务）→ 关联器 `mAdd`。
2. `mProcessDue` → 关联器 `mDue`（窗口已过且达到水位线）→ `Module.mBuildEvent`（所采取的动作、分数、检测结果）→ `RulesEngine.mEvaluate`（模块规则）→ `SqliteStorage.mSaveEvents` → `mDetect` → `Grouper.mAdd`（新分组或计数 +1）。
3. `mProcessGroups`（每秒一次）→ `SqliteStorage.mGetDueGroups` → `Module.mEnrich`（`mGetIpContext`）→ `fSocConfigured` → `fBuildAlert` → `mQueueGroup`（没有 SOC 时：`mSkipGroup`，状态 `local`）。
4. `SocSender.run`（线程）→ `mCycle`（没有 SOC 时：只执行 `mSkipPending`）→ `mSendHeartbeat`（每 5 分钟一次）和 `mGetQueueBatch`（≤ 100 条告警，≤ 1 MiB）→ `mDeliver` → `SocClient.mSendAlerts` → `mMarkQueueSent`（SOC 编号），或者拆分、搁置、按退避策略延迟，遇到 507 时暂停。
5. 此外，`mProcessGroups` → `ChannelSender.mNotify`（`fChannelSettings`、`fSeverityReached`、`fBuildMessage`）→ 每个已启用且已设置的通知渠道的列表 → `ChannelSender.run`（线程，每秒一次）→ `mCycle` → `mDeliver` → `TelegramClient.mSendMessage` → 状态 `channels.status`（已发送、失败、已丢弃、最近一次错误）。

**设置 Telegram**

`/admin/dashboard/channels/telegram/` → `admin.js fTelegramSection` → «保存并发送测试消息» → `POST /api/admin/channels/telegram`（`fSaveTelegram`：`cTokenRegex`、`cChatIdRegex`、`fSaveTelegramToken`、`fSaveSettings`、采集器的 `reload`）→ `POST /api/admin/channels/telegram/test`（`fTestTelegram` → `TelegramClient.mGetMe` → 使用 `fTestMessage` 的 `mSendMessage`）→ 显示带有机器人 @username 的提示，或者带有 Telegram 错误描述的提示。

**启用或停用模块，或者保存其设置或规则**

`modules.js fSwitch`（模块 › 已安装 中的行或模块页面的页眉；停用时需要确认；当 `requirements_missing` 不为空时被锁定，不发出请求）或 `LocalsiemViews.module` 的表单 → `POST /api/admin/modules/{name}`（`fSaveModule`：`fValidateSettings`；启用一个已停用的模块时：使用请求中的设置执行 `WebContext.mCheckRequirements` → 返回 422 `requirements_missing` 以及不满足的检查；`fRules` + `fCleanRules`）→ `fSaveSettings`（`settings.json` 中的 `modules.<name>` 和 `rules.<id>`）→ `WebContext.mApplySettings` → `mCollector({"command": "reload"})` → `Collector.mHandleIpc` → `mCycle` → `mReloadSettings`（`Module.mReload`、`mCheckRequirements`、`mLoadRules`、`mDiscover`、`mPublishDoctor`、`mPublishState`）。在 `collector.status.modules.<name>.enabled` 与所保存的内容一致之前，`fSummary` 返回 `pending`。

**前提条件与重新配置**

模块的页面（`/admin/dashboard/modules/installed/<name>/`、`LocalsiemViews.module`）→ «重新配置»（`fReconfigure`，在 `has_requirements` 时显示）→ `POST /api/admin/modules/{name}/reconfigure`（`fReconfigure` → `WebContext.mCheckRequirements`：使用已保存的设置根据已安装的副本创建新实例 → `fCheckRequirements` → `mRequirements`，结果保存在 `dRequirements` 中 → 采集器 IPC `reload` → `mReloadSettings` → `mCheckRequirements`（状态 `<name>.requirements`），对于已启用的模块，还会执行 `mDiscover` 和 `mPublishDoctor`）→ 响应：`requirements`，满足时还有 `fRootCommand` → `fShowReconfigured` → `fLoad`（`GET /api/admin/modules/{name}` → `fRequirements`：采集器和 Web 服务的检查中较新的那个）→ 开关被解锁，但模块保持停用，直到管理员启用它。

**模块状态与概览**

`modules.js`（模块 › 已安装，以及分析师的模块标签页；每 10 秒一次）→ `GET /api/modules` → `fRead`（`collector.status`、`<name>.doctor` 和 `<name>.requirements` 状态、24 小时的 `mModuleCounts`）→ `fSummaries` → 每个清单的 `fSummary`（加载错误 → `error`；已停用 → `disabled`，当最新的前提条件检查 `fRequirements` 有错误时带有 `requirements_missing`；采集器 2 分钟没有动静 → `unknown`；不在 `collector.status.modules` 中 → `warning`/`not_loaded`；enabled 不一致 → `pending`；诊断错误或来源不可读 → `error`；没有来源或来源缺失 → `warning`；诊断警告只是备注，保持 `ok`）+ 针对无法加载的目录的 `fBrokenSummary`。`overview.js`（每 15 秒一次）→ `GET /api/overview` → `fOverview` → `fRead`、`fSummaries`、`mAlertCounts`、`mQueueStatistics`、`soc.status` 和 `soc.heartbeat` 状态、`mHistogram`（24 小时的每小时分桶）、`mListGroups`（最新 6 条）。

**模块标签页、其各个部分以及模块页面**

`/admin/dashboard/modules/` → `fAdminTab` → 302 跳转到 `modules/installed/`（`lModuleSections[0]`）→ `fAdminModulesSection`（首先检查会话；分析师 → `/user/dashboard/modules/`；`installed` 或 `installable` → `index.html`；已安装模块的名称，即旧 URL → 301 跳转到 `installed/<name>/`；其他任何内容 → 404）→ `app.js fRoute`（`cPathRegex` 接受第二部分；`/admin/dashboard/modules/` 和 `/admin/dashboard/modules/<name>/` → `modules/installed/` 和 `modules/installed/<name>/`；`installable/` 之下或用户中的第二部分会被丢弃，其他标签页不接受第二部分）→ `fShowView("modules", section, item)` → `LocalsiemViews.modules`（`fModuleSections`；已安装：`fLoad` → `GET /api/modules` → `fDraw` → 每个模块的 `fCard`，对于管理员，还会执行一次 `fCheckRepository`（参见 «更新模块»）；可安装：`fCatalogPanel`），或者在有 item 时为 `LocalsiemViews.module`（此时其 `vParameter` 为模块名称）。行中的 «配置»（`fCardActions`）→ `/admin/dashboard/modules/installed/<name>/` → `fAdminModule`（未安装的模块返回 404）→ `LocalsiemViews.module` → `GET /api/admin/modules/{name}`；«返回已安装模块»、卸载以及已消失的模块（`not_found`）→ `/admin/dashboard/modules/installed/`。分析师：`/user/dashboard/modules/` → `fUserTab` → 只显示各行的 `LocalsiemViews.modules`（路由器会丢弃任何第二部分）。

**从查询到结果**

`search.js fRun` → `GET /api/search`、`/api/search/histogram`、`/api/search/summaries` → `fParseQuery`（出错时返回带代码和位置的 400）→ `fRange` → `SqliteStorage.mSearch` / `mHistogram` / `mSummaries` → `fCompileQuery` → 带进度处理程序的 SQLite（时间限制，422 `search_timeout`）→ `Accounts.mAudit` → 带原生显示时间的 JSON。某一行 → `GET /api/events/{id}` → `fEvent` → `mGetEventDetail` → 对每条记录执行 `WebContext.mModule(record.module)` → `mDisplayRecord`（Apache 模块会添加审计记录的请求头和请求体）→ 带有关联跳转的请求详情卡片。

**使用访问令牌直接登录**

`admin.js fTokensSection` → `POST /api/admin/tokens`（`fCreateToken` → `Accounts.mCreateAccessToken`：已启用的分析师，1–365 天，SHA-256 保存在 `access_tokens` 中）→ URL `https://<server>:10443/auth/login/auto?token=...` 只显示一次（`fShowSecret`）。分析师打开它 → `fLoginWithToken`（使用名称 `(access token)` 的 `mIsBlocked` → `mCheckAccessToken` → `mRecordAttempt`）→ 失败：`mRecordLogin` 和 `/auth/login/?error=<reason>`（由 `app.js fLoginView` 显示）→ 成功：`mCreateSession(..., "token")` → `mMarkAccessTokenUsed` → `mRecordLogin` → cookie → `next`（本站点的路径）或 `/user/dashboard/overview/`。每个请求 → `mLoadSession`（方式 `token`：仅限分析师，不要求第二因素，不要求修改密码）。

**登录与仪表板**

`app.js fLoginView`（页面只有表单：`fAuthLogo`、用户名、密码、按钮，以及按钮下方的语言和主题：`fLanguageSelect`、`fThemeToggle`）→ `POST /api/auth/login`（`Accounts.mIsBlocked`、`mCheckPassword`、`mRecordAttempt`）→ `mfa_enabled` 关闭：立即创建会话（`step` done）→ 开启：`step` totp 或 enroll（`mStartEnrollment`，二维码）→ `POST /api/auth/totp`（`mReadChallenge`、`mVerifyTotp`）→ `mCreateSession` → `mRecordLogin`（每次失败也会记录：`invalid_credentials`、`invalid_code`、`login_blocked`、`challenge_expired`）→ cookie `localsiem_session` → `fDone`（如果账户使用的是另一种语言，则以点击按钮时显示的语言执行 `PATCH /api/account`：仪表板会以该语言打开）→ 返回 `next`（带有其参数的原始 URL）或角色的概览。每个仪表板 URL → `fUserTab` / `fAdminTab`（以及用于各个部分和模块页面的 `fAdminUsersSection`、`fAdminModulesSection`、`fAdminModule`；没有会话 → `/auth/login/?next=...`；其他角色 → 其自己仪表板的同一标签页）→ `index.html` → `app.js fRoute` → `fShowView` → `window.LocalsiemViews[tab]`（对于 `modules/installed/<name>/` 为 `LocalsiemViews.module`）。

**安装或更新核心**

`curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- ACTION options` → `install-update-reinstall-*.sh fMain`（恰好一个操作：`--install`、`--update`、`--reinstall` 或 `--uninstall`，否则停止；`fIsInstalled`：`--install` 只能在没有 localSIEM 时使用，`--update` 和 `--reinstall` 只能在有 localSIEM 时使用；`--reinstall`：先执行 `fConfirmRemoval`；`--configure-*` 会被拒绝（模块没有设置选项），`--modules-from` 也会被拒绝：模块通过 Web 界面安装）→ `fEnsurePackages` → `fGetSource`（完整副本，或者 `fResolveRef`（向 GitHub API 查询 `<ref>` 对应的提交）以及不带缓存的 `curl` 下载 `https://github.com/PYMEHackers/localSIEM/archive/<commit>.tar.gz`，解压到 `/tmp/localsiem-install.*` 中）→ `configure.py --check-arguments` → 仅限 `--reinstall`：`fRemoveInstallation`（删除除已下载副本之外的所有内容）→ 将核心复制到 `/opt/localsiem/webapp/`（仅存在于工作副本中的文件，例如 `AGENTS.md`，如果存在的话）→ 虚拟环境 → `configure.py`（设置、`modules_repository`、证书、凭据：先将 `admin` 写入 `/root/webapp-credentials.txt`，如果创建了新的 JWT 密钥，再写入系统用户和 JWT 密钥；移除旧版本中的 `http_input` 和远程输入的变量）→ `fGrantLogAccess`（`manage.py setup-modules --no-restart` → `fGrantReadAccess`：已安装的模块）→ 重启服务 → 以 `localsiem` 身份运行 `manage.py modules` 和 `doctor` → 说明在哪里安装模块（Web 界面）。屏幕以编号步骤（`fStep`）和结果标记显示这一过程；日志会收到相同的行（不带颜色）以及通过 `fRun` 运行的每个命令的完整输出（`fStartLog` → `fSplitOutput`）；失败时会说明在哪一步停止（`fShowFailure`）。

**卸载模块**

`modules.js fUninstallButton`（模块 › 已安装 中的行、`fCardActions`，或模块页面；需要确认）→ `DELETE /api/admin/modules/{name}`（`fUninstallModule` → `fRemove` → `InstallLock` → 将 `/opt/localsiem/modules/<name>` 重命名为 `.staging-*` → 删除）→ `WebContext.mReloadModules`（该模块不再被列出）→ 采集器 IPC `restart`（systemd 或 supervise-daemon 会再次启动它 → 不包含该模块的 `fCreateModules`）→ `fForgetCatalog` → 重新绘制列表，或者模块页面跳转到 `/admin/dashboard/modules/installed/`。`settings.json` 会保留 `modules.<name>` 和 `rules.<id>`。

**通过 Web 界面安装模块**

`/admin/dashboard/modules/installable/` → `modules.js fCatalogPanel` → «检查仓库»（`fCheck` → `fFetchCatalog(true)`）→ `GET /api/admin/module-catalog`（`fGetCatalog` → `fFetchCatalog` → `fResolveRef` → `fArchiveUrl` → 在 `/opt/localsiem/run/catalog.*` 中执行 `fDownload` → `fCatalog` → `fModuleFolders`（`mod-<id>` 目录）和 `fListManifests`）→ 只列出 `installed` 为 null 的项（`fDraw`；仓库中的每个模块都已安装时显示 `catalog.all_installed`，仓库中没有模块时显示 `catalog.empty`）→ «前提条件»（`fShowRequirements` → `fRequirementsBody` → `fRequirementCommands`：`system.family` 的 `install_requirements`，以 root 身份和使用 `sudo` 两种形式；不运行任何命令）或 «安装»（`fInstall`）→ `POST /api/admin/module-catalog/{name}`（`fInstallFromCatalog` → `fFetchAndInstall` → `InstallLock` → `fResolveRef` → `fDownload` → `fInstall`：`mod-<name>` → `/opt/localsiem/modules/<name>`）→ `WebContext.mReloadModules` → 仅限首次安装：`fFirstInstallation`（在已安装的副本上执行 `WebContext.mCheckRequirements` → 如果缺少某项前提条件且从未保存过 `modules.<name>.enabled`，则以 `enabled: false` 执行 `fSaveSettings`）→ 采集器 IPC `restart`（`Collector.mHandleIpc` → `vStop`；systemd 或 supervise-daemon 会再次启动它 → `fCreateModules` 加载该模块 → `mCheckRequirements`）→ 带有 `requirements_missing` 和 `fRootCommand` 的响应 → `fForgetCatalog` → 该模块从列表中消失（`fDraw`），并打开一个对话框（`P.fModal`，«<module> 已安装»，`fResult`）：服务器所缺少的内容（以及重新配置），或者供 root 运行的命令；关闭，或者 «查看已安装模块» → `/admin/dashboard/modules/installed/` → 管理员以 root 身份运行该命令（`manage.py setup-modules` → `fGrantReadAccess`、`fRestartServices`、`fDoctorAsLocalsiem`）。

**更新模块**

`/admin/dashboard/modules/installed/` → `LocalsiemViews.modules`（管理员）→ `fLoad`（`GET /api/modules` → `dLast` → `fDraw`），以及执行一次 `fCheckRepository`（`modules.checking_updates`）→ `fFetchCatalog(false)`（如果已保存的响应不到 10 分钟，则使用它，`cCatalogSeconds`；否则 `GET /api/admin/module-catalog` → `fGetCatalog` → `catalog.py fFetchCatalog` → `fCatalog`：每个模块的 `newer` 和 `action`）→ `dNewer`（带有 `newer` 且动作为 `update` 或 `incompatible` 的项）→ `fDraw` → `fCard` → `fUpdateNotice`（仅当该项的 `installed` 就是该行的版本时：`modules.update_notice` 和 «更新»，或者不带按钮的 `modules.update_incompatible`）→ «更新» → `fUpdate`（`P.fConfirm`，«更新模块»；`sUpdating`：«更新中…»，在 10 秒一次的刷新之间也会保持）→ `POST /api/admin/module-catalog/{name}`（`fInstallFromCatalog` → `fFetchAndInstall` → `InstallLock` → `fResolveRef` → `fDownload` → `fInstall`：用新副本替换已安装的副本，带有 `previous` 和 `access_changed`）→ `WebContext.mReloadModules` → 不执行 `fFirstInstallation`（`previous` 不为 `None`：设置和启用/停用状态保持不变）→ 采集器 IPC `restart` → 响应 → 该模块离开 `dNewer` → `fForgetCatalog` → toast 提示 `modules.updated_toast` → 只有在有 `access_changed` 或没有 `collector_restarted` 时：显示对话框（`P.fModal`，«<module> 已更新»，`fUpdateResult`：供 root 运行的命令 `fRootCommand`；或者重启 `localsiem` 服务）→ `fLoad`。如果检查失败，`vRepositoryNote` 会显示 `modules.updates_failed`，列表照常工作。Web 界面从不重新安装模块，也从不安装旧版本（动作 `reinstall` 和 `downgrade`）。

<a id="routes"></a>
## 5. 路由与入口点

| 路由 / 命令 | 处理函数 | 文件 |
|---|---|---|
| `/` → 角色对应仪表板的概览（或 `/auth/login/`） | `fRoot` | [backend/web/app.py](../backend/web/app.py) |
| `/auth/login/`, `/auth/register/`, `/auth/recover/` | `fPage`（一个 HTML 外壳） | [backend/web/app.py](../backend/web/app.py) |
| `/user/dashboard/` → `/user/dashboard/overview/`；`overview/`、`search/`、`live/`、`alerts/`、`modules/`、`account/`（管理员会被带到 `/admin/dashboard/` 的同一标签页） | `fUserDashboard`, `fUserTab` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/` → `/admin/dashboard/overview/`；`overview/`、`search/`、`live/`、`alerts/`、`soc/`、`settings/`、`audit/`、`logins/`、`account/`（分析师会被带到 `/user/dashboard/` 的同一标签页，对于管理类标签页则被带到其 `overview/`）；`users/` → `users/accounts/`；`modules/` → `modules/installed/` | `fAdminDashboard`, `fAdminTab` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/users/accounts/`、`/admin/dashboard/users/tokens/`；`/admin/dashboards/...` → `/admin/dashboard/...` | `fAdminUsersSection`, `fAdminDashboards` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/channels/` → `/admin/dashboard/channels/general/`；`/admin/dashboard/channels/general/`、`/admin/dashboard/channels/telegram/`（分析师会跳转到 `/user/dashboard/overview/`） | `fAdminTab`, `fAdminChannelsSection` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/modules/installed/`、`/admin/dashboard/modules/installable/`（分析师会跳转到 `/user/dashboard/modules/`）；旧的 `/admin/dashboard/modules/<name>/` → 301 跳转到 `/admin/dashboard/modules/installed/<name>/`（模块未安装时返回 404） | `fAdminModulesSection` | [backend/web/app.py](../backend/web/app.py) |
| `/auth/login/auto?token=TOKEN`（或 `?TOKEN`；可选的 `next`） | `fLoginWithToken` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/modules/installed/<name>/`（未安装的模块返回 404；分析师会跳转到 `/user/dashboard/modules/`） | `fAdminModule` | [backend/web/app.py](../backend/web/app.py) |
| `GET /api/auth/session`, `POST /api/auth/login`, `POST /api/auth/totp`, `POST /api/auth/logout` | `fGetSession`, `fLogin`, `fLoginTotp`, `fLogout` | [backend/web/app.py](../backend/web/app.py) |
| `GET/PATCH /api/account`, `POST /api/account/password`, `POST /api/account/totp/reset` | 账户处理函数 | [backend/web/app.py](../backend/web/app.py) |
| `GET /api/search`, `/api/search/histogram`, `/api/search/summaries`, `/api/search/export` | `fSearch`, `fHistogram`, `fSummaries`, `fExport` | [backend/web/api_search.py](../backend/web/api_search.py) |
| `GET /api/events/{id}` | `fEvent` | [backend/web/api_search.py](../backend/web/api_search.py) |
| `GET /api/alerts`, `GET /api/alerts/{id}` | `fAlerts`, `fAlert` | [backend/web/api_search.py](../backend/web/api_search.py) |
| `GET /api/ws`（协议）、`WebSocket /api/ws`（仅限已登录会话的 cookie；否则以 4401 关闭） | `fWebSocketProtocol`, `fLive` | [backend/web/api_search.py](../backend/web/api_search.py) |
| `GET /api/modules`（任何已登录用户） | `fModules` | [backend/web/api_modules.py](../backend/web/api_modules.py) |
| `GET /api/admin/modules/{name}`、`POST /api/admin/modules/{name}`（`enabled`、`settings`、`rules`；422 `requirements_missing`）、`DELETE /api/admin/modules/{name}`（卸载）、`POST /api/admin/modules/{name}/doctor`、`POST /api/admin/modules/{name}/reconfigure` | `fModule`, `fSaveModule`, `fUninstallModule`, `fRunDoctor`, `fReconfigure` | [backend/web/api_modules.py](../backend/web/api_modules.py) |
| `GET /api/admin/module-catalog`（可安装，以及 已安装 中的新版本检查）、`POST /api/admin/module-catalog/{name}`（安装或更新：同一个调用） | `fGetCatalog`, `fInstallFromCatalog` | [backend/web/api_modules.py](../backend/web/api_modules.py) |
| `GET /api/overview`（任何已登录用户） | `fGetOverview` | [backend/web/api_modules.py](../backend/web/api_modules.py) |
| `/api/admin/users`（GET、POST）、`/api/admin/users/{id}`（PATCH、DELETE）、`.../password`、`.../totp-reset` | 用户处理函数 | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET/POST /api/admin/soc`, `POST /api/admin/soc/test`, `/retry`, `/requeue` | SOC 处理函数 | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET/POST /api/admin/channels`, `POST /api/admin/channels/telegram`, `POST /api/admin/channels/telegram/test` | `fChannels`, `fSaveChannels`, `fSaveTelegram`, `fTestTelegram` | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET/POST /api/admin/settings`, `GET /api/admin/audit` | 设置和审计处理函数 | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET /api/admin/tokens`、`POST /api/admin/tokens`（`user_id`、`label`、`days`）、`DELETE /api/admin/tokens/{id}` | `fTokens`, `fCreateToken`, `fRevokeToken` | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET /api/admin/logins`（`before`、`limit`、`result`） | `fLogins` | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `/api/doc/` | FastAPI 的 Swagger | [backend/web/app.py](../backend/web/app.py) |
| `backend/collector.py [--from-start] [--once]` | `fMain` | [backend/collector.py](../backend/collector.py) |
| `backend/server.py`（除 `-h`/`--help` 外没有选项） | `fMain` | [backend/server.py](../backend/server.py) |
| `backend/manage.py ensure-admin\|create-user\|reset-password\|reset-mfa\|list-users\|doctor [--json]\|modules\|read-paths\|soc-test\|setup-modules [--no-restart]` | `fMain` | [backend/manage.py](../backend/manage.py) |
| `deploy/install-update-reinstall-debian.sh`、`deploy/install-update-reinstall-alpine.sh`（一个操作：`--install`、`--update`、`--reinstall [--yes]` 或 `--uninstall [--yes]`；`--ref`、`--source-url` 以及 `configure.py` 的选项），也可以通过管道从 `https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/` 运行（请求头 `Accept: application/vnd.github.raw+json`） | `fMain` | [deploy/](../deploy/) |

<a id="impact"></a>
## 6. 影响分析

| 组件 | 修改后受影响的内容 |
|---|---|
| `storage_sqlite.lSchema` 中的模式 | 所有搜索、Web 服务、数据保留、概览的计数。列通过 `CREATE ... IF NOT EXISTS` 添加；更改现有列需要迁移（`meta.schema_version`）。 |
| `Module` 接口（[backend/core/module.py](../backend/core/module.py)） | 所有模块（它们全部来自 `localSIEM-modules`：核心本身没有任何模块）；采集器；Web 钩子 `mDisplayRecord`；`mRequirements`（首次安装、启用、重新配置、采集器启动和重新加载、`manage.py modules` 和 `doctor`）；`manage.py`（`mDoctor`、`mSkipped`）。新增钩子时请在基类中提供默认实现，以便已安装的模块继续正常工作。 |
| `module.json` 格式（`fReadManifest`、`fCheckSetting`、`lSettingTypes`） | 所有模块；`modules.js` 的设置表单（`fInput`、`fRecordsEditor`）；`fValidateSettings`；`read_paths`：`manage.py read-paths` 和 `setup-modules`（Web 界面和安装程序所给出的 root 命令中的 ACL）。更严格的检查会使已安装的模块无法加载。；`install_requirements`（`fCheckInstallRequirements`、`lSystems`）：可安装 中的前提条件对话框（`fRequirementsBody`），带有错误配置的模块既不会被安装也不会被加载 |
| `Module.mRequirements` 和 `fCheckRequirements` | 首次安装（停用）、开关（锁定；422 `requirements_missing`）、重新配置、采集器的 `<name>.requirements` 状态、`manage.py modules` 和 `doctor`。检查失败的模块视为不满足前提条件，因此无法启用。切勿按请求或按周期调用它。 |
| `cVersion` | 每个 `module.json` 中的 `core` 字段：需要更新版本核心的模块不会被加载。Web 界面中显示的版本、每条告警的 `details` 中的版本，以及发送给 SOC 的 `User-Agent` 中的版本。 |
| `cModulesPath`、`localsiem_modules` 包 | 模块的查找位置和导入方式；模块目录（`fInstall`、`InstallLock`）、每个模块内部的相对导入、`WebContext.mReloadModules`。 |
| `backend/core/catalog.py`、其 API（`fGetCatalog`、`fInstallFromCatalog`）以及设置 `modules_repository` | 模块的 可安装 部分（`fCatalogPanel`，只列出 `installed` 为 null 的项）、已安装 中的更新（`fCheckRepository`、`fUpdateNotice` 和 `fUpdate` 读取每一项的 `newer`、`action`、`installed`、`version` 和 `core`，以及安装响应中的 `previous`、`access_changed`、`root_command` 和 `collector_restarted`）和卸载，这是安装、更新和卸载模块的唯一途径；`localSIEM-modules` 仓库的布局（`mod-<id>` 目录：`cFolderPrefix`、`fModuleFolders`）；Web 界面显示的 root 命令（`fRootCommand` → `manage.py setup-modules`）。Web 单元必须在 `ReadWritePaths` 中保留 `/opt/localsiem/modules`。；前提条件对话框读取每一项的 `install_requirements` 以及响应中的 `system` |
| 保存在浏览器中的仓库响应（`modules.js` 中的 `dCatalogCache`、`cCatalogSeconds`、`fFetchCatalog` 和 `fForgetCatalog`） | 已安装 和 可安装 显示的内容：仓库中发布的新版本最多可能需要 10 分钟才会出现在 已安装 中（如果点击了 «检查仓库» 或重新加载页面，则会更快）；每个更改已安装模块的操作都必须调用 `fForgetCatalog`，否则 已安装 会提供已经完成的更新；`fCheck`（检查仓库）必须始终以 `true` 发出请求。 |
| `manage.py setup-modules`（`fGrantReadAccess`、`fRestartServices`） | Web 界面的 root 命令（安装模块后、带有 `access_changed` 的更新后以及重新配置时）和安装程序（`fGrantLogAccess`，`--no-restart`）：每个模块对其日志的读取权限。请保持其幂等，并且可以在没有终端的情况下以 root 身份运行。 |
| `collector.status`（`mPublishState`）、`<name>.doctor`（`mPublishDoctor`）和 `<name>.requirements`（`mCheckRequirements`） | `api_modules.fSummary` 和 `fOverview`（状态、原因、计数、开关的锁定）、模块页面和单个模块的页面（前提条件）、概览、设置页面（磁盘和数据库）。 |
| `fSummary` 的状态和原因 | 四个语言文件中的 `module_state.*` 和 `module_reason.*` 键、`modules.js`、`overview.js`、手册。 |
| `access_tokens`、`logins` 表和 `sessions.method`（[backend/web/webdb.py](../backend/web/webdb.py)，通过 `lColumns` 添加到旧数据库中） | 直接登录、`mLoadSession`（哪些会话跳过第二因素）、用户 › 访问令牌、登录记录。令牌会话绝不能对管理员有效。 |
| `config.cWebPort`（10443） | `server.py`、`configure.py`（`fCheckPort`、记录在 `install.env` 中的 SIEM 地址）、Web 界面显示的设置、提供给分析师的访问 URL、SOC（客户的 SIEM 地址）。 |
| `/root/webapp-credentials.txt` 中的条目块（`fEnsureAdmin`、`fConfigureCredentials`） | `--uninstall`（`fRemoveCredentials` 会移除每个以 `localSIEM ` 开头的条目块，并保留其他应用程序的条目块）：每个新的条目块都必须以此开头。 |
| `lUserTabs` / `lAdminTabs`、`lUserSections` / `lModuleSections`（在 `app.py` 和 `app.js` 中）以及 `ldTabs` | 两个仪表板、它们的重定向（服务器和 `fRoute`：用户和模块的第一个部分、模块页面的旧 URL）、子标签页（`admin.js fUserSections`、`modules.js fModuleSections`）、指向模块页面的链接（`fCardActions`、«返回已安装模块»、卸载）、SOC 的链接（`/user/dashboard/search/?q=...`）。服务器和路由器中的列表必须保持一致。 |
| 账户的语言（`users.language`） | `app.js fStart`（仪表板以该语言打开，而不是以浏览器的语言打开）、登录（`fDone` 会将登录页面的语言赋给账户）、标题栏的语言选择器（`fSetLanguage` → `PATCH /api/account`）。 |
| 记录字典（`mParse`） | 关联（`correlation`、`fields.client_ip`、`fields.path`）、请求详情卡片（`search.js fRecordBlock` 和模块的 `mDisplayRecord`）、FTS（`search`、`raw`）。 |
| 事件字典（`mBuildEvent`） | `lEventColumns`、规则（YAML 读取的字段）、分组、搜索字段（`dTextColumns`、`dNumberColumns`）、CSV 导出、`mModuleCounts`。 |
| 模块产生的类别和规则名称 | 严重级别、告警规则名称（SOC 的统计按它们分组：请保持其稳定）、分组键。 |
| `fGroupKey` / `fExternalId` | SOC 中的去重：更改它们会重新发送已经发送过的内容。 |
| `fBuildAlert` | 与 SOC 的约定：`GenericAlert` 的限制（规则 300、描述 10 000、details 200 个键 × 5000 个字符）。 |
| `Masker` | 隐私：存储的内容以及到达 SOC 的内容。 |
| `FileTailer` | 不丢失、不重复的保证；首次打开时从不读取旧行；反取证通知；它绝不能以写入方式打开日志。其 `unreadable` 通知中的 `was_readable` 决定不可读的来源是否会产生告警（`fNoticeDetection`）。 |
| `query.dFields` | 搜索语言、15 种语言的帮助、手册。 |
| 设置的默认值（`config.dDefaults`） | 两个进程；管理员面板（`api_admin`）、`configure.py`。模块的设置不在这里：它们来自各模块的 `module.json`。 |
| 设置 `mfa_enabled`（默认关闭） | `Accounts.mLoadSession`（启用它会立即结束没有第二因素的账户的密码会话）、`fLogin`（step done、totp 或 enroll）、`/api/auth/session`、设置、用户和账户视图、`manage.py list-users` 和 `create-user`、`configure.py`（只有在使用 `--enable-mfa` / `--disable-mfa` 时）。 |
| `frontend/assets/app.css` | 与 SOC 共享的外观：它就是 SOC 的样式表；仅属于 localSIEM 的规则放在 `localsiem.css` 中，该文件首先将 SOC 的绿色强调色替换为 PYMEHackers 的红色 `#cc3333`（在两种主题中也是强调文本的颜色），并将错误红色替换为橙红色，以免错误与强调色混淆；它将登录页面布局为单独居中的表单（没有侧边面板或工具栏；登录表单的宽度是其他登录卡片的一半（`.auth-card-narrow`，只要求输入验证码时的验证码步骤也是如此；带二维码的设置步骤保持全宽），其按钮下方有语言和主题，`.auth-preferences`），并将已安装的模块布局为每个模块占一整行（`.module-list` 和 `.module-card`：各部分上下排列，与模块页面的页眉相同；`.module-title` 只在 `.module-head` 行内采用其 24rem 的基准宽度，绝不在列中采用，否则那会成为它的高度），带有新版本提示（`.module-update`，带有更新按钮的信息提示；需要更新的 localSIEM 时为暗色的 `.module-update-blocked`），而不触碰 `app.css`。徽标是它自己的（`frontend/assets/img/logo.svg`：一个放大镜覆盖在三行日志上：两行已处理，带有对勾，一行尚无人处理，带有 !），而不是 SOC 的盾牌。 |
| 安装程序和单元 | 每台服务器：请保持它们要求恰好一个操作，`--update` 和 `--uninstall` 可重复执行，可以通过管道从 GitHub 运行（使用函数、`fMain` 放在最后、不读取 stdin），并且只安装核心。 |
| `backend/core/terminal.py` 以及安装程序的输出函数（`fSplitOutput`、`fRun`、`fStep`） | `manage.py`、`configure.py` 和安装程序打印的内容，以及安装日志（不带颜色代码）。`manage.py read-paths`（由 `fRemoveReadAccess` 读取）和 `doctor --json` 是为程序打印的：绝不要为它们添加标记或颜色。安装程序运行的 Python 工具必须立即刷新其打印的内容（`fWrite` 会这样做），并遵循 `LOCALSIEM_COLOR`。 |
| `backend/core/channels.py`（`fChannelSettings`、`fBuildMessage`、`ChannelSender`）以及设置 `channels` | 管理员收到的消息（Telegram）、通知渠道标签页（`fChannelsGeneralSection` 和 `fTelegramSection` 读取 `channels.status` 和 `settings`）、`api_admin`（使用 `cTokenRegex`、`cChatIdRegex`、`lSeverities`、`lLanguages` 进行校验）。SOC 投递不依赖于它们：失败的通知渠道从不会阻碍告警。 |

<a id="extensions"></a>
## 7. 扩展点

### 如何添加模块（SSH、Postfix、MariaDB...）

核心不需要改动：不需要在采集器中注册，也不需要在 `config.dDefaults` 中添加默认值。

1. 创建目录 `localSIEM-modules/mod-<name>/`（名称：`[a-z][a-z0-9_]{1,31}`；前缀 `mod-` 只用于仓库中的目录：`id`、`vName`、设置、URL、选项以及已安装的目录 `/opt/localsiem/modules/<name>/` 都使用 `<name>`），其中包含一个 `module.json`（`id`、`version`、`core`、`entry`、`default_enabled`、`read_paths`、`settings`；参见 [核心与模块](#architecture) 以及 [backend/core/registry.py](../backend/core/registry.py) 的文件头）。
2. 编写 `entry` 中指定的 `Module` 子类（[backend/core/module.py](../backend/core/module.py)）：`vName` 等于 id（`<name>`），`mDiscover`（具有稳定 `key` 的来源；使用 `mModuleSettings()` 读取您的设置）、`mCreateFramer`（通常为 `LineFramer`）、`mParse`（包含时间、关联、parse_status、字段和已脱敏原始内容的记录）、`mCreateCorrelator`（一个带有 `mAdd`、`mDue(pNow, pForce, pWatermark)` 和 `mPendingCount` 的对象）、`mBuildEvent`（带有 `action` 和 `detections` 的事件字典），以及可选的 `mStart`、`mRulesPath`、`mRuleFunctions`、`mEnrich`、`mDoctor`、`mRequirements`、`mHealth`、`mSkipped`、`mSetLowDisk` 和 `mDisplayRecord`。以相对方式导入模块自己的文件（`from .parsers import ...`），并以 `backend.core.*` 导入核心；不要添加 `__init__.py`。
3. 为 15 种语言（`lLanguages`）中的每一种添加 `locales/<language>.json`：`name`、`summary`、`settings.<key>.label` / `help`（对于 `records`，还有 `fields`、`add`、`remove`、`empty`）以及 `choices`。
4. 将其 YAML 规则放在 `mod-<name>/rules/` 中，并由 `mRulesPath` 返回该目录。
5. 确定对于该服务而言 «采取的动作» 意味着什么（例如，被 fail2ban 封禁的 IP），并据此设置 `action`：只有未采取动作的事件才会产生检测结果。
6. 如果模块需要服务器上的软件（它所监控的服务），请在 `mRequirements` 中以类似 `mDoctor` 的检查形式返回（在 `fix` 中给出安装它的命令），不使用存储，不安装任何东西，也不更改 `/opt/localsiem/` 之外的任何内容：缺少该软件时，模块会以停用状态安装，并且在重新配置检测到它之前无法启用。
7. 在 `read_paths` 中声明其日志所在的目录，以便 `manage.py setup-modules`（Web 界面显示的供 root 运行的命令，安装程序在每次更新时也会运行它）授予 `localsiem` 读取权限。绝不要更改服务的日志，也不要更改其写入日志的方式或格式：按原样读取日志并调整解析器；诊断负责描述日志，并且只为不属于日志的内容和读取权限提供 `fix`。在 `install_requirements` 中声明在 Debian 和 Alpine 上安装模块所需软件的命令（每行一条命令，不含 shell 运算符），并在其语言文件中声明这些命令的说明（`install_requirements.note` 和 `install_requirements.<system>`）：Web 界面会在 模块 › 可安装 › 前提条件 中显示它们，但从不运行它们。
8. 将其发布到 `localSIEM-modules` 仓库（目录 `mod-<name>/`）：在未安装时，它会出现在 模块 › 可安装 中，这是安装它的唯一途径（在开发副本中，您可以将该目录复制到 `/opt/localsiem/modules/<name>/`，然后重启 `localsiem` 和 `localsiem-web`）。要发布新版本，请提高其 `module.json` 中的 `version`：模块 › 已安装 会通过更新提供它（如果同时将 `core` 提高到高于已安装的 localSIEM 版本，则只会说明需要哪个 localSIEM 版本）；如果新版本更改了 `read_paths`，Web 界面会在更新后再次显示供 root 运行的命令。

### 如何为模块添加设置

将其添加到其 `module.json` 的 `settings` 中（类型和默认值），并将其标签和帮助文本添加到其语言文件中；使用 `mModuleSettings()` 读取它。Web 界面会构建该字段，`fValidateSettings` 会检查它，采集器会在下一次重新加载时立即应用它。

### 如何添加规则

在模块的 `rules/` 目录中创建一个 YAML 文件（每个键和运算符请参见 [backend/core/rules.py](../backend/core/rules.py) 的文件头）。示例：

```yaml
id: apache-xmlrpc-burst
name: "Apache: burst of XML-RPC calls"
category: bruteforce
type: authentication
severity: medium
kind: threshold
when:
  method: POST
  path: /xmlrpc.php
  action: none
by: [ip, vhost]
window: 60
threshold: 30
description: "{count} POST requests from {ip} to /xmlrpc.php of {vhost} in {window} seconds."
search: "ip:{ip:q} path:/xmlrpc.php"
```

采集器会在下次启动或重新加载设置时加载它；之后它会出现在其所属模块页面的规则表中（管理 › 模块 › 已安装 › 配置），在那里可以将其停用，并调整其严重级别、阈值和窗口（覆盖设置保存在 `settings.json` 的 `rules.<id>` 下）。文件中的 `enabled: false` 会使其默认停用。需要代码的条件使用 `{function: name}`，其中的函数由模块的 `mRuleFunctions` 返回。

### 如何添加搜索字段

将其添加到 [backend/core/query.py](../backend/core/query.py) 的 `dFields` 中，以及 [backend/core/storage_sqlite.py](../backend/core/storage_sqlite.py) 中 `fCompileField` 的 `dTextColumns` / `dNumberColumns`（或特殊情况）中；新列还需要修改模式、`lEventColumns` 并添加索引。在帮助（四个语言文件中的 `help.fields`）和手册中为其编写文档。

### 如何添加 API 端点或仪表板标签页

端点放在 `/api/` 之下，位于其所属领域的 `fRegister*` 函数中（Swagger 会为其生成文档）。标签页需要在 `lUserTabs` 和/或 `lAdminTabs`（[backend/web/app.py](../backend/web/app.py)）中添加路由，在 `ldTabs`（[frontend/assets/app.js](../frontend/assets/app.js)；`group`、`adminGroup`、`adminOnly`）中添加条目，在 `window.LocalsiemViews` 中添加视图（新脚本必须添加到 `frontend/index.html` 中），并在四个语言文件中添加其文本（`nav.<tab>` 以及该视图的键）。像用户和模块那样带有各个部分的标签页，还需要在 `app.py` 和 `app.js` 中添加其部分列表（`lUserSections`、`lChannelSections`、`lModuleSections`），在 `fAdminTab` 中添加从该标签页到其第一个部分的重定向，为其各个部分添加路由（`fAdminUsersSection`、`fAdminChannelsSection`、`fAdminModulesSection`），在 `fRoute` 中添加其分支，并在其视图中添加子标签页（`fUserSections`、`fChannelSections`、`fModuleSections`）。

### 如何添加通知渠道（电子邮件、Slack...）

在 [backend/core/channels.py](../backend/core/channels.py) 中：将其名称添加到 `lChannels`，将其配置块添加到 `dDefaults["channels"]`（[backend/core/config.py](../backend/core/config.py)；机密信息放在 `config/` 中单独的文件里，权限 600，绝不放在 `settings.json` 中），并在 `fChannelSettings`、`ChannelSender.mConfigured` 和 `ChannelSender.mDeliver` 中添加其分支（一个类似 `TelegramClient` 的客户端，其错误中从不携带机密信息）。然后在 `api_admin.py` 中添加其 API（类似 `fSaveTelegram` 和 `fTestTelegram`），在 `app.py`、`app.js` 和 `admin.js` 的 `lChannelSections` 中添加其部分以及对应的视图（类似 `fTelegramSection`），在四个语言文件中添加文本 `channels.section_<name>` 及其视图的文本，并在手册中添加相应的部分。常规部分会自动列出它（`GET /api/admin/channels` 的 `channels`）。

<a id="resources"></a>
## 8. 实测资源占用

在一台 Debian 13 服务器（mod_security2 2.9.11、CRS 3.3.7）上使用 Apache 模块测得，使用各单元的 systemd 限制（`MemoryMax` 300M / 200M、`CPUQuota` 50 %、`Nice` 10、空闲 I/O）：

| 情况 | 采集器（RSS） | Web（RSS） | 总计 |
|---|---|---|---|
| 空闲，启动后 | ≈ 28 MB | ≈ 26–55 MB | ≈ 55–80 MB |
| 约 60 秒内突发 30 000 个请求，**每一个**都有审计记录（由于 K 部分，审计日志约 1.8 GB） | 峰值 ≈ 160 MB | ≈ 40 MB | 峰值 ≈ 200 MB |
| 突发之后 | ≈ 70 MB | ≈ 26–40 MB | ≈ 100 MB |

在该突发期间，采集器在最后一个请求之后约 40 秒追上进度，为每个请求准确存储了一个事件（30 000 个中的 30 000 个，全部带有其三个来源），并发送了三个告警分组，而不是数千个。Alpine 3.24 空闲时：采集器 ≈ 26 MB，Web ≈ 54 MB。

磁盘：每个没有匹配的请求约 0.8 KB（访问日志行、事件、索引），每个带有审计记录且在 error.log 中有若干 ModSecurity 行的请求约 10–13 KB。一个典型的 PYME 网站每天有数万个请求，其中百分之几被审计，在 90 天的数据保留期内远低于默认上限（磁盘容量的 15 % 与 10 GB 中的较小值）；达到上限时，最早的事件会首先被删除。
