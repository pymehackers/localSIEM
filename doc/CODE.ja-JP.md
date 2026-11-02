# localSIEM コードリファレンス

この CODE は次の言語でもご覧いただけます：\
[de-DE](CODE.de-DE.md), [en-GB](CODE.en-GB.md), [en-US](CODE.md), [es-AR](CODE.es-AR.md), [es-ES](CODE.es-ES.md), [fr-FR](CODE.fr-FR.md), [he-IL](CODE.he-IL.md), [hi-IN](CODE.hi-IN.md), [it-IT](CODE.it-IT.md), ja-JP, [ko-KR](CODE.ko-KR.md), [pt-BR](CODE.pt-BR.md), [pt-PT](CODE.pt-PT.md), [ru-RU](CODE.ru-RU.md), [zh-CN](CODE.zh-CN.md)

## 目次

1. [アーキテクチャと設計](#architecture)
2. [モジュールマップ](#modules)
3. [主要なシンボル](#symbols)
4. [主な呼び出し経路](#flows)
5. [ルートとエントリーポイント](#routes)
6. [影響分析](#impact)
7. [拡張ポイント](#extensions)
8. [計測したリソース使用量](#resources)

[インストール](README.ja-JP.md) · [ユーザーマニュアル](MANUAL.ja-JP.md)

<a id="architecture"></a>
## 1. アーキテクチャと設計

localSIEM は **1台の Linux サーバー** 向けの軽量な SIEM で、そのサーバー自体にインストールします（サーバーごとに1つの localSIEM）。サーバーのサービスのログを読み取り（自身のサーバーのものだけで、リモート入力はありません）、検索可能なデータベースに保存し、まだ人の対応が必要なものを判断して、それを PYMEHackers の SOC（`soc.pymehackers.com`）に送信します。SOC のアナリストは、localSIEM の検索ツールでアラートを調査します。バージョン 2.2.0（[backend/core/config.py](../backend/core/config.py) の `cVersion`）。

### 基本原則：«実行されたアクションがなければ SOC へ»

SOC に届くものはすべて、まだ誰も対処していないものです：

| 状況 | `action` | SOC へ送信されるか |
|---|---|---|
| ModSecurity がフェーズ 1-2 でブロックした（アプリケーションはリクエストを受け取っていない） | `blocked` | いいえ：localSIEM に保存されて検索でき、その IP の次のアラートの `context` で件数として数えられます |
| ModSecurity がフェーズ 3-4 でブロックした（アプリケーションはすでにリクエストを実行していた） | `none` | はい |
| エンジンが `DetectionOnly` の状態でのルール一致 | `none` | はい |
| 異常しきい値未満のルール一致 | `none` | はい（重大度 `low`、変更可能） |
| モジュールのルールによるシグナル（ブルートフォース、Web シェル...）とヘルスシグナル | `none` | はい |

実行されたアクションのない一致は、スコアにかかわらずすべて SOC に送信されます。機密データ（パスワード、Cookie、`Authorization`、トークン、リクエスト本文）は、何かを保存する前にマスクされ、SOC に送られることはありません。

### 2つのプロセス、1つの書き込み元

| サービス | プロセス | 役割 |
|---|---|---|
| `localsiem` | [backend/collector.py](../backend/collector.py) | モジュールを読み込み、そのソースを読み取り、解析し、相関付け、ルールを適用し、保存し、グループ化し、SOC に送信し、ハートビートを送信します。**イベントデータベースに書き込む唯一のプロセスです。** |
| `localsiem-web` | [backend/server.py](../backend/server.py) | FastAPI + uvicorn で、自身のポート（常に 10443、`config.cWebPort`）で HTTPS を直接提供します。イベントデータベースを読み取り、書き込むのは自身のデータベース（アカウント、セッション、検索監査）と `settings.json` だけです。 |

Web は、Unix ソケット `/opt/localsiem/run/collector.sock`（JSON 行）を、コレクターにコマンドを送るためだけに使います。管理者が設定やモジュールを変更したとき、または再構成を押したときに、コレクターがただちに適用できるようにする `reload`、`doctor`、Web からモジュールをインストール、更新、アンインストールした後の `restart`、そして SOC キューの再試行と再キューイングです。イベントデータベースに書き込むのは、引き続きコレクターだけです。Web が停止しても、収集とアラートは続行されます。ライブビューは、最後のイベント ID を使ってデータベースをポーリングします。

### コアとモジュール

コアは Apache について何も知らず、**名前でモジュールをインポートすることはありません**。保存、検索、ルールエンジン、グループ化、SOC キュー、ハートビート、ヘルスは汎用です（[backend/core/](../backend/core/)）。サーバーの各サービスはモジュールです。モジュールとは、`module.json`、`Module`（[backend/core/module.py](../backend/core/module.py)）のサブクラスのコード、テキストを収めた `locales/<language>.json` を持つフォルダーです。このサブクラスは、検出、入力、フレーミングと解析、相関、実行されたアクションの判断、YAML ルール、エンリッチメント、診断、要件（`mRequirements`）、ヘルスシグナル、Web と root のフックを提供します。

レジストリ（[backend/core/registry.py](../backend/core/registry.py)）は、モジュールを1か所だけで探します。コアには独自のモジュールはありません：

| 場所 | モジュール | インポート形式 |
|---|---|---|
| `cModulesPath` = `/opt/localsiem/modules/<name>/`（開発用のコピーでは `LOCALSIEM_MODULES_PATH`） | `localSIEM-modules` リポジトリ（GitHub。各モジュールのフォルダーは `mod-<name>/`）から、Web（モジュール › インストール可能、およびモジュール › インストール済みの更新とアンインストール、[backend/core/catalog.py](../backend/core/catalog.py)）によってのみインストール、更新、アンインストールされます。localSIEM のインストーラーが行うことはありません。現在は `apache2`（access.log、error.log、ModSecurity の監査ログ。フォルダー `mod-apache2/`）と `privesc`（権限昇格。フォルダー `mod-privesc/`）があり、そのプロジェクトで文書化されています | 名前空間パッケージ `localsiem_modules.<name>.<file>`：`__init__.py` はなく、モジュールは自身のファイルを相対インポートし、コアを `backend.core.*` としてインポートします |

`module.json` には次のものが含まれます：`id`（フォルダー名。リポジトリでは `mod-` を除いたもの：`[a-z][a-z0-9_]{1,31}`）、`version`、`core`（必要な localSIEM の最低バージョン。これが現在の localSIEM より新しい場合は読み込まれません）、`entry`（`"file:Class"`）、`default_enabled`、`read_paths`（`manage.py setup-modules` とインストーラーが ACL を通じて `localsiem` に読み取りを許可するフォルダー）、`settings`：`{key, type, default, ...}` のリストで、type は `boolean`、`integer`（`min`、`max`）、`string`（`max_length`）、`path`（絶対パス）、`choice`（`choices`）、または `records`（`fields`、`max_items`。手動で追加したソースのような小さなレコードのリスト）です。Web はこのリストから設定フォームを作成し、レジストリは管理者が保存したものを検証します（`fValidateSettings`）。古い `module.json` ファイルの `setup_option` は無視されます（`fReadManifest`）。モジュールにはセットアップオプションはありません。`install_requirements`（任意）は `{system: [command, ...]}` を保持し、system は `debian` または `alpine` です（`lSystems`）。これは、モジュールが必要とするソフトウェアを root としてサーバーにインストールするコマンドです。Web はそれらを表示するだけ（モジュール › インストール可能 › 要件）で、そのままの形と、先頭に `sudo` を付けた形で表示します。そのため、各コマンドは単一のコマンドでなければなりません。`fCheckInstallRequirements` は、`;`、`&`、`|`、`<`、`>`、バッククォート、`$(`、改行、および20個を超えるコマンドを拒否します。注記はモジュールのロケールに記述します（すべてのシステム向けの `install_requirements.note` と、`install_requirements.<system>`）。

モジュールの設定は、`settings.json` の `modules.<name>` に、`module.json` の既定値を上書きする形で保存されます（`fModuleSettings`、`Module.mModuleSettings`）。`config.dDefaults` の既定値には、もうモジュールは含まれていません。`modules.<name>.enabled` は、何も再起動せずにモジュールを有効または無効にします。無効にすると、コレクターはそのソースの検出と読み取り、診断、ヘルスチェックを停止します。読み込みに失敗したモジュール（無効な `module.json`、より新しい `core`、インポートエラー、`mStart` での例外）は、コレクターのログ、`collector.status.module_errors`、診断、Web で報告され、ほかのモジュールは動作を続けます。

**要件。** モジュールをインストールしても、それが監視するソフトウェアがインストールされることはありません。`Module.mRequirements()` は、モジュールを有効にする前にサーバーに必要なものを、`mDoctor` と同じ形式のチェック（`{id, status: ok|error, title, detail, fix}`）として返します。エラーのチェックが1つもなければ要件を満たしており、`[]`（既定値）は要件なしを意味します。その場合、モジュールは以前と同じように動作します。このメソッドはストレージなしで呼び出され、呼び出しのたびにサービスの設定を読み取ることがあるため、リクエストごとやサイクルごとに呼び出されることはありません。`fCheckRequirements`（[backend/core/registry.py](../backend/core/registry.py)）がこれを実行し（例外は未充足として扱われます）、その結果は、コレクターが起動時とリロード時に（状態 `<name>.requirements`）、Web が初回のインストール時、モジュールを有効にするとき、および再構成のときに（`WebContext.dRequirements`）保持します。Web は両者のうち新しい方を使います。Web からの初回のインストール時（以前のコピーがない場合）、モジュールはダウンロードしたリポジトリからではなく、必ずインストール済みのコピーから作成されます。要件が不足しており、管理者が `modules.<name>.enabled` を一度も保存していない場合は、そこに `false` が保存されます。更新や再インストールでこれが変更されることはありません。要件が不足している間は、モジュールを有効にできません（422 `requirements_missing`、ロックされたスイッチ）。再構成は要件を再確認し、満たされていればスイッチのロックを解除して root 用のコマンドを表示しますが、モジュールを有効にすることはありません。モジュールが勝手に無効になることはありません。有効なモジュールが要件を満たさなくなっても有効のままで、その診断とヘルスがそれを報告します。

### 2つのダッシュボード

管理者は常に `/admin/dashboard/` で作業します（タブは `overview`、`search`、`live`、`alerts`、`modules`、`users`、`soc`、`channels`（セクションは既定の `general/` と `telegram/`）、`settings`、`audit`、`logins`、`account`。`modules` には2つのセクション、`installed/`（既定：インストール済みのモジュール、1行に1つ）と `installable/`（リポジトリのモジュールのうち、まだインストールされていないもの）があり、1つのモジュールのページは `/admin/dashboard/modules/installed/<name>/` です）。アナリストは `/user/dashboard/` で作業します（`overview`、`search`、`live`、`alerts`、読み取り専用でセクションのない `modules`、`account`）。両方の既定のタブは `overview` です。`/` とサインインは、各ユーザーを自分のダッシュボードの概要に移動させます。もう一方のダッシュボードの URL は、自分のダッシュボードの同じタブにリダイレクトされます（`/user/dashboard/search/?q=...` を要求した管理者は `/admin/dashboard/search/?q=...` に、`/admin/dashboard/users/` を要求したアナリストは `/user/dashboard/overview/` に移動します）。これは、サーバー（[backend/web/app.py](../backend/web/app.py)）とページのルーター（[frontend/assets/app.js](../frontend/assets/app.js)）の両方で行われます。サイドバーには見出しもユーザーデータもなく、ロゴ、区切り線、タブ（グループごとに区切り線）、下部に区切り線と «サインアウト» があります。ソース、診断、ルールには、もう専用のタブはなく、各モジュールのページの一部になっています。

### レコード、イベント、グループ

- **レコード** は、読み取ったままの1行または1件の監査エントリで、すでにマスクされています。ファイル内の位置と共に、同じトランザクションでただちに保存されます。クラッシュの後には両方があるか、どちらもないかのどちらかなので、行が失われたり重複したりすることはありません。
- **イベント** は1件のリクエストで、モジュールのコリレーターが結合したレコードです。Apache モジュールでは、相関ウィンドウ（5秒）の後に、同じ `UNIQUE_ID` を持つレコードが結合されます。`UNIQUE_ID` がない場合（Apache が既定で書き込むアクセス形式）、アクセスログの行は、クライアント IP、メソッド、URI、ステータス、時刻（±2秒）によってそのリクエストのレコードと組み合わされ、イベントには弱い相関のマークが付けられます。ウィンドウを待っているレコードは、再起動後も残ります（`event_id IS NULL`）。
- **グループ** は1件の SOC アラートで、ウィンドウ（10分）内で同じモジュール、vhost、IP、カテゴリ、重大度を持つ検出です。重大なグループはただちに送信され、それ以外は短時間に集中したイベントをまとめるため、60秒のバッファで待機します。

### ストレージ

WAL モードの SQLite（`/opt/localsiem/db/localsiem.db`、モード 600、`auto_vacuum = INCREMENTAL`）で、[backend/core/storage.py](../backend/core/storage.py) のインターフェースの背後にあるため、将来の中央モードのために PostgreSQL の実装を追加できます。通常のフィールドには型付きでインデックス付きの列があり、コンテンツレスの FTS5 テーブル（`contentless_delete=1`）が、マスク済みのテキストを URL デコードしたものも含めてインデックス化するため、`"union select"` で `id=1%27%20UNION%20SELECT` も見つかります。監査レコードについては、縮小したテキスト（リクエスト行、ホスト、ユーザーエージェント、ルール ID、メッセージ、データ）だけがインデックス化されます。すべてのクエリはパラメーターを使います。検索ツリーは `fCompileQuery` でプレースホルダー付きの SQL にコンパイルされ、ユーザーのテキストを連結することはありません。概要とモジュールのページは、過去24時間のモジュールごとの件数（`mModuleCounts`）とアラートの件数（`mAlertCounts`）を、検索と同じ制限時間で読み取ります。

時刻は UTC で、ネイティブの記録用形式 `2026-10-29@13-59-59.723`（固定幅で、テキストとしてソート可能）で保存され、表示用形式 `2026/10/29@13:59:59.723` で表示されます（[backend/core/timeutil.py](../backend/core/timeutil.py)）。Apache はローカル時刻を書き込み、Apache モジュールがそれを UTC に変換します（access と audit はオフセットを含み、error.log はサーバーのタイムゾーンを使います）。記録として書き込まれるものにはすべて記録用形式が使われます：データベース、ログ、認証情報ファイル、エクスポートした CSV と JSON のファイル、SOC に送信するアラート。

保持：日数（90）と最大サイズ（ディスクの 15% と 10 GB のうち小さい方）によります。古いイベントから少しずつ削除され、アラートと SOC キューはより長く（365日間）保持されます。ディスクの空き容量が少ない場合、容量の大きい詳細データ（監査のヘッダーと本文）は保存されなくなり、ほとんどない場合は、アラートに関係するイベントだけが保存されます。localSIEM がディスクを満杯にすることはありません。

### 知っておくべき設計上の決定

- **localSIEM のインストーラーはコアだけをインストールします。** GitHub から直接実行されます（`curl -fsSL .../deploy/install-update-reinstall-debian.sh | bash -s -- ACTION options`）。完全なコピーの中で実行されていない場合（パイプ実行で、`BASH_SOURCE` が `main`）、`--ref`（または `--source-url`）のブランチまたはタグのアーカイブをダウンロードします。すべてが関数の中にあり、`fMain` は最終行で実行されるため、ダウンロードが途中で切れても何も実行されません。stdin を読むコマンドはありません（stdin はスクリプト自体だからです）。コマンドには `< /dev/null` が付き、質問は `/dev/tty` から読み取ります。不足しているパッケージをインストールし（`dpkg-query` / `apk info -e`）、インストール済みのモジュールは保持します。`--configure-*`（モジュールにはセットアップオプションがありません）と `--modules-from` は拒否します。常にちょうど1つのアクションが必要です（`vAction`。指定がない場合は停止して一覧を表示します）。`--install` は、`fIsInstalled` が localSIEM の痕跡（途中で失敗したインストールのものも含む）を見つけると停止し、`--update` と `--reinstall` は、何も見つからないと停止します。`--update` はすべて（データ、アカウント、設定、モジュール、`install.env` のオプション）を保持します。`--reinstall` は最初に確認を求め（`fConfirmRemoval`）、新しいコピーをダウンロードしてそのオプションを確認し、その後で初めて `--uninstall` と同じようにすべてを削除し（`fRemoveInstallation`。ダウンロードしたばかりのコピーは残します）、ゼロからインストールします。インストール済みのコピーから実行した場合は、そのコピーも削除されるため、localSIEM をダウンロードします。アクションと `--yes` は `configure.py` に渡されません。`--uninstall`（単独、または `--yes` 付き。`fUninstall` で、何かをダウンロードまたはインストールする前に実行）は、localSIEM がサーバーに置いたものをすべて削除します：サービス、`/opt/localsiem`、ユーザーとグループ、読み取りパスの ACL（`manage.py read-paths` と `/var/log/apache2`）、apache2 モジュールのバージョン 1.2.0 以前の `--configure-apache` が追加した Apache の `localsiem.conf`（`fRemoveApacheSetup`：configtest の後にリロード。`localsiem_access.log*` は残ります。localSIEM はログを変更も削除もしません）、logrotate、Let's Encrypt のフック、認証情報ファイル内の自身のブロック。`--yes` がない場合は `/dev/tty` で確認を求めます。
- **GitHub からのダウンロードではキャッシュを使いません。** `raw.githubusercontent.com` は、プッシュ後最大5分間古いファイルを提供し（`Cache-Control: max-age=300`。クエリ文字列でも `Cache-Control: no-cache` のリクエストでも回避できません）、ブランチのアーカイブも古い可能性があります。そのため、文書化されたコマンドは API（`api.github.com/repos/.../contents/...`。キャッシュされません）を通じてインストーラーを読み込み、インストーラー（インストーラーの `fResolveRef`）と Web（モジュール用、`catalog.py` の `fResolveRef`）の両方が、ブランチのコミットを API に問い合わせ、決して変わることのないそのコミットのアーカイブをダウンロードします。すべてのダウンロードは `Cache-Control: no-cache` を送信します。トークンがない場合、API は IP アドレスごとに1時間あたり60リクエストを許可します。応答がない場合は、ブランチのアーカイブをダウンロードします（インストーラーは警告を出します）。
- **チャネルは人向けのコピーであり、2つ目の SOC ではありません。** コレクターは、すべてのアラートを SOC 用のキューに入れ（永続キュー。SOC がない場合は未送信として保持）、さらに `ChannelSender`（[backend/core/channels.py](../backend/core/channels.py)）に渡します。これは、`channels.min_severity` 以上のアラートを、有効で設定済みの各チャネル経由で送信します（Telegram：`sendMessage`、プレーンテキスト、`channels.language` で）。その一覧はメモリ上にあり（チャネルごとに最大200メッセージ）、1秒に1メッセージで、429（`retry_after`）とネットワークエラーの場合は再試行します。400、401、403、404 の場合は、ただちにメッセージを破棄します。再起動すると待機中のものは失われますが、SOC には引き続きすべてのアラートが届きます。ボットのトークンは SOC のトークンと同様のシークレットです：`config/telegram-bot-token`（モード 600）。全体が表示されたりログに記録されたりすることはなく、トークンを含む URL が書き込まれることもありません。
- **SOC は任意です。** `fSocConfigured`（[backend/core/soc.py](../backend/core/soc.py)）：URL、トークン、`soc_enabled`。これらがない場合、`mProcessGroups` は各アラートをキューに入れる代わりに未送信としてマークし（`mSkipGroup`：状態 `local`、理由 `soc_not_configured`、«未送信» と表示）、`SocSender.mCycle` も保留中だったものに対して同じことを行います（`mSkipPending`）。そのため、SOC が受け取るのは SOC の設定後に発生したアラートだけで、存在しないかもしれない SOC のために何かが溜まることはありません。チャネルは、SOC の有無にかかわらず動作します。
- **モジュールは `localSIEM-modules` リポジトリから、Web を通じてのみ提供されます**（[backend/core/catalog.py](../backend/core/catalog.py)）。このリポジトリにはインストーラーがありません。Web はモジュール › インストール可能でモジュールを提供します。表示されるのは、リポジトリのモジュールのうちまだインストールされていないものだけです。モジュール › インストール済みでは、リポジトリに新しいバージョンがある場合に、インストール済みのモジュールに対して **更新** を提供します（`fCatalog`：`newer` が true でアクションが `update`。アクションが `incompatible` の場合は、必要な localSIEM の通知を表示し、ボタンは表示しません）。再インストールやダウングレードのアクションを提供することはありません（モジュールを再インストールするには、アンインストールしてからインストールします）。更新はインストールと同じ呼び出しです（`POST /api/admin/module-catalog/{name}` → インストール済みのコピーに対する `fInstall`）。設定と有効／無効の状態は保持され（`fFirstInstallation` は以前のコピーがなかった場合にのみ実行されます）、`access_changed`（`read_paths` が置き換えられたコピーのものと異なる）によって、root が `setup-modules` を再度実行する必要があるかどうかを Web に伝えます。ブラウザーは `GET /api/admin/module-catalog` の応答を10分間保持し（`modules.js` の `cCatalogSeconds` と `fFetchCatalog`）、両方のセクションで共有するため、インストール済みを開くたびにリポジトリをダウンロードすることはありません。«リポジトリを確認» は常にダウンロードし直し、モジュールのインストール、更新、アンインストールを行うと、保持した応答は破棄されます（`fForgetCatalog`）。アーカイブは `tarfile` の `data` フィルターで展開され、その中の `mod-<id>` フォルダーだけがモジュールです（`fModuleFolders`。接頭辞はリポジトリ内のフォルダー名だけのもので、インストール先のフォルダー `<id>/`、ID、設定、URL、オプションは接頭辞のない名前を使います。接頭辞のないフォルダーは無視されます）。各モジュールは、コードをインポートせずに `fReadManifest` で検証され、インストール済みのコピーの隣でリネームによってインストールされます。Web は `localsiem` として動作し、ログの読み取り権限を与えることはありません（root が必要です）。代わりに root 用のコマンドを表示します（`fRootCommand`：同じ localSIEM の `manage.py setup-modules`）。アンインストール（`fRemove`）は、インストール済みのフォルダーをリネームで移動してから削除します。モジュールが読み込まれない場合も同様です。設定、ルールの変更、イベント、アラート、読み取り位置は残り、root が与えた読み取り権限は取り消されません。インストール、更新、アンインストールの後、Web は自身のモジュールを再読み込みし（`mReloadModules`）、コレクターは再起動します（IPC の `restart`。systemd または supervise-daemon が再び起動します）。モジュールをインストールする前に、**要件** は、このサーバーのシステム（`fServerSystem`：`/etc/alpine-release`、`/etc/debian_version`、または `/etc/os-release` の `ID` と `ID_LIKE`）向けの `install_requirements` を、そのままの形と先頭に `sudo` を付けた形で、モジュールの注記と共に表示します。モジュールがそのシステム向けに何も宣言していない場合は、宣言されているすべてのシステムのものを表示します。localSIEM がそれらを実行することはありません。
- **ログの読み取り権限は、root として1か所で付与します**：`manage.py setup-modules`（`fGrantReadAccess`：今後のローテーション用のデフォルト ACL を含む ACL と、Debian では `adm` グループを、インストール済みモジュールの `read_paths` に対して設定）は、モジュールのインストール後、`read_paths` が変わる更新の後（`access_changed`）、および再構成で Web が表示するコマンドであり、インストーラーが更新のたびに実行するものです（`fGrantLogAccess`、`--no-restart` 付き）。
- **サーバーの設定が変更されることはありません**。localSIEM もそのモジュールも変更しません。モジュールにはセットアップオプションがなく、root がモジュールのために実行するのは `manage.py setup-modules`（前項の読み取り権限で、これを与えるのはコアであり、モジュールではありません）だけです。モジュールがサーバー上で不足しているものは、要件と診断に、それを修正するスニペットまたはコマンドと共に示され（Apache の場合：ModSecurity、CRS、`SecRuleEngine`、`mod_unique_id`）、管理者が適用します。
- **Apache 固有の処理は Apache モジュールにあります**（`localSIEM-modules/mod-apache2/`）。Apache の設定は直接解析され（そのため、検出は `apache2ctl` なしで `localsiem` として動作します）、ModSecurity のパート K は保存前に破棄され、リクエストカードに表示されるヘッダーと本文は、マスク済みの生の監査レコードから再構築されます（`mDisplayRecord`）。コアは、各レコードのモジュールに問い合わせるだけです（`WebContext.mModule`）。
- **モジュールは再起動なしで有効化・無効化されます**：Web は `settings.json` を書き込み、ソケットを通じて `reload` を送信します。コレクターはただちに状態を再公開し、Web は保存した内容とコレクターが適用した内容（`collector.status.modules`）を比較して、両者が一致するまで «pending» を表示します。
- **Web は起動時に `module.json` ファイルを読み取り**、モジュールのインストール、更新、アンインストールの後にも再度読み取ります（`mReloadModules`）。手動でコピーまたは削除したモジュールには、両方のサービスの再起動が必要です（コレクターが読み込むまで、Web はそれを `not_loaded` と表示します）。
- **モジュールの要件は、重要なタイミングでのみ確認されます**（コレクターの起動とリロード、初回のインストール、有効化、再構成）。モジュールは要件を確認するためにサービスの設定を読み取ることがあるため、結果は保持されます。Web はダウンロードしたリポジトリのコードをインポートすることはなく、インストール済みのコピーで要件を確認します。
- **追いつき処理**（短時間に集中したイベント、または停止中に書き込まれたもの）：ソースが読み取り量の上限で止まると、次のサイクルがただちに開始されます。モジュール内で最も遅いソースより（ログの時刻で）5秒以上先行しているソースは、それを待ちます。また、遅れているすべてのソースが読み取った位置より後のトランザクションは待機する（ウォーターマーク）ため、リクエストの3つのレコードは常に結合されます。
- **ログは読み取るだけです。** `FileTailer` はすべてのログを `O_RDONLY` で開きます。localSIEM の中に、サービスのログを書き込んだり、ローテーション、切り詰め、名前変更、移動、削除をしたりするものはありません（localSIEM の logrotate ファイルは `/opt/localsiem/log/` だけを対象とします）。root が localSIEM のためにログに対して行うのは、読み取り権限の付与だけです（`manage.py setup-modules`：`adm` グループと ACL）。アンインストールしても、apache2 モジュールのバージョン 1.2.0 以前の `localsiem.conf` によって Apache が書き込んでいた `localsiem_access.log` は残ります。
- **書き込み方法も変更しません。** どのモジュールも、サービスのログ設定やログの形式を変更しません（Apache の場合：`LogFormat`、`CustomLog`、`GlobalLog`、`ErrorLog`、ModSecurity の `SecAudit*` ディレクティブのいずれも変更しません）。モジュールは、サーバーが書き込むままにログを読み取り、それに合わせて動作します（任意の `LogFormat`、`mod_remoteip` がログに残す IP の有無、シリアルまたはコンカレント、JSON またはネイティブの監査ログ、すでに書き込んでいるサーバーの `localsiem_combined` の行）。その診断はログを説明するだけで（形式、監査ログのパート、マスク、ログから読み取れることと読み取れないこと）、変更を提案することはありません。`fix` が付くのは、ログ以外の要件（Apache の場合：ModSecurity、CRS、`SecRuleEngine`、`mod_unique_id`）と読み取り権限だけです。
- **モジュールは何もインストールせず、`/opt/localsiem/` の外にあるものを何も変更しません。** システムにすでにあるもので動作し、パッケージやソフトウェアをインストールせず、`/opt/localsiem/` の外にあるサーバーのファイル、設定、ログを書き込みません。サーバーに必要なものが不足している場合は、要件（`mRequirements`）がそのことを示し、要件を満たさずにインストールされたモジュールは、要件が満たされるまで無効のままです（スイッチはロックされます。[コアとモジュール](#architecture) の «要件» を参照）。モジュールにはセットアップオプションはありません。`read_paths` の読み取り権限を与えるのはコア（root としての `manage.py setup-modules`）であり、モジュールではありません。`install_requirements` のコマンドは管理者向けで、Web はそれらを表示するだけです。
- **履歴でアラートが出ることはありません。** 保存された位置のないソースは末尾から開始します（`Collector.mDiscover`）。ただし、このプロセスがすでにそのモジュールを追跡している間に現れたソース（`sFollowedModules`：新しい vhost）は例外で、5 MB 以下であれば先頭から読み取られます。そのため、初回の起動、後からインストールまたは有効化されたモジュール、root がアクセス権を与えるまで読み取れなかったファイル、再起動のいずれでも、古い行が読み取られることはありません。各ファイルの位置は、新しい内容がない場合でも、開いた時点で保存されるため（`FileTailer.vOpenedUnsaved`）、再起動するとそこから続行します。`--from-start` は新しいファイルを先頭から読み取ります。
- **依存関係は仮想環境に置きます**（`/opt/localsiem/venv/`）。`pip --break-system-packages` は決して使いません。pip が、クライアントのサービスが使うディストリビューションのパッケージ（たとえば certbot）を壊してはならないためです。
- **Web 画面へのアクセスは、アプリケーション自体によって許可された IP（とループバック）に制限されます**。ログインも含まれます。2段階認証（TOTP、«PYMEHackers localSIEM»）は既定では無効です。管理者が設定（`mfa_enabled`）ですべてのアカウントに対して有効にすると、それ以降は必須になります。インストーラーは `--enable-mfa` または `--disable-mfa` でのみこれを変更する（`install.env` にはありません）ため、更新では Web 画面で選択した状態が保持されます。
- **SOC 用の SIEM アドレスがアラートに含まれることはありません**：`details` はクライアントのすべてのアナリストが閲覧するため、送信されるのはクエリ（`details.localsiem.search`）だけです。
- **自身のサーバーのログだけ。** リモート入力はありません。すべてのモジュールは、localSIEM が動作しているサーバーのファイルを読み取ります。`configure.py` は、削除されたリモート入力のオプション（`lRemovedOptions`：`--enable-http-input`、`--disable-http-input`、`--mode`）が指定されると «<option> no longer exists: localSIEM has no remote HTTP input, it only reads the logs of its own server.» と表示して停止し、実行のたびに、古いバージョンがそのために保持していたものを削除します：`settings.json` の `http_input`（`lRemovedSettings`、`fRemoveSettings`）と、`localsiem.env` の3つの変数（`lRemovedEnvironment`）。インストーラーは `backend/` と `frontend/` を丸ごと置き換えるため、更新によってその入力の古いファイルも削除されます。古いバージョンが保存したモジュール `http` のイベントは、保持期間によって削除されるまでデータベースに残ります。
- **15言語、1つのリスト。** Web 画面、モジュールのテキスト、チャネルのメッセージ、ドキュメントは、de-DE、en-GB、en-US、es-AR、es-ES、fr-FR、he-IL、hi-IN、it-IT、ja-JP、ko-KR、pt-BR、pt-PT、ru-RU、zh-CN で提供されます：[backend/core/config.py](../backend/core/config.py) の `lLanguages`（アカウント、モジュールのテキスト、チャネルで受け付ける言語）と `common.js` の `cLanguages`（Web 画面）で、どちらもアルファベット順の同じリストです。en-US が原文であり、フォールバックです。ある言語で欠けているテキストは英語で表示されます（`fT`、`fModuleText`、チャネルの `dTexts`）。he-IL は右から左に書かれます（`lRightToLeftLanguages`、`cRightToLeft`）。`fLoadLanguage` はページに `dir="rtl"` を設定し、スタイルは論理的な方向（`inline-start`、`inline-end`、`text-align: start`）だけを使うため、レイアウトは自動的に反転します。残りの部分は `localsiem.css` の末尾にあるブロック «Right to left» が対応します（`unicode-bidi: plaintext` を使った技術的なテキスト、セレクトの矢印、スイッチのつまみ、狭い画面でのメニュー。ヒストグラムは左から右のままです）。 表示形式の時刻は左から右に分離されます（`fEl` の `fTextNodes`：`<bdi dir="ltr">`）。言語を切り替えると、開いているビューが再描画されます（`app.js` の `fOnLanguage` → `fRoute`）。

<a id="modules"></a>
## 2. モジュールマップ

| モジュール | パス | 責務 | 依存先 | 使用元 |
|---|---|---|---|---|
| コレクター | [backend/collector.py](../backend/collector.py) | メインループ：モジュールの読み込み、ソース、レコード、相関、イベント、ルール、グループ、保持、ヘルス、Web 向けの状態（モジュールごとのものも含む）、ローカルソケット | core、registry | `localsiem` サービス |
| Web サーバー | [backend/server.py](../backend/server.py) | `-h`/`--help` 以外のオプションはありません（`fCheckArguments`：それ以外はエラー）。ポートの解放、HTTPS 付きの uvicorn | web | `localsiem-web` サービス |
| 管理 CLI | [backend/manage.py](../backend/manage.py) | アカウント、有効なすべてのモジュールの診断（と無効なモジュールの要件）、不足している要件付きのモジュール一覧、モジュールが読み取るフォルダー、SOC のテスト。root として `setup-modules`（モジュールのログの読み取り権限と再起動。Web が表示するコマンドで、インストーラーも実行します） | web.auth、registry | インストーラー、root |
| ターミナル出力 | [backend/core/terminal.py](../backend/core/terminal.py) | `manage.py` と `configure.py` のスタイルで、インストーラーと同じです：マーク付きの結果行（`✓` 完了、`!` 警告、`✗` 失敗、`·` 情報。UTF-8 を書き込めない場合は `+ ! x -`）、薄く表示される詳細、端末でのみ色付け（`LOCALSIEM_COLOR=always` または `never` が最優先で、次に `NO_COLOR`、`TERM=dumb`、`isatty`） | — | manage、configure |
| パスワード | [backend/security.py](../backend/security.py) | PBKDF2-SHA256（600 000 回の反復） | — | web.auth、configure |
| 設定 | [backend/core/config.py](../backend/core/config.py) | パス（`cModulesPath` も）、バージョン、既定値、`settings.json`（`fSaveSettings`、`fRemoveSettings`）、SOC のトークン、Telegram ボットのトークン、シークレット | — | すべて |
| 時刻 | [backend/core/timeutil.py](../backend/core/timeutil.py) | ネイティブ形式、Apache の時刻から UTC への変換 | — | すべて |
| ストレージインターフェース | [backend/core/storage.py](../backend/core/storage.py) | すべてのストレージが実装するメソッド | — | storage_sqlite |
| SQLite ストレージ | [backend/core/storage_sqlite.py](../backend/core/storage_sqlite.py) | スキーマ、レコード、イベント、グループ、キュー、状態、保持、検索、クエリコンパイラー、モジュールごとの件数とアラートの件数 | query | collector、web、モジュール |
| 検索言語 | [backend/core/query.py](../backend/core/query.py) | トークナイザーと、ツリーを作るパーサー。位置付きのエラー | — | storage_sqlite、web |
| ファイルリーダー | [backend/core/tailer.py](../backend/core/tailer.py) | 位置、ローテーション（create と copytruncate）、切り詰め、削除、置き換え、バックログ | — | collector |
| モジュールレジストリ | [backend/core/registry.py](../backend/core/registry.py) | インストール済みのモジュールのフォルダー（`cModulesPath`）を見つけ、`module.json` を検証し、クラスを読み込み（名前空間パッケージ `localsiem_modules`）、インスタンスを作成し、その要件を確認し（`fCheckRequirements`）、設定の既定値と検証を扱います | config、module、timeutil | collector、web、manage、catalog |
| モジュールインターフェース | [backend/core/module.py](../backend/core/module.py) | 基底クラス `Module`（フック、要件、`module.json` を上書きする設定、有効／無効）と行フレーマー | registry | すべてのモジュール |
| ルールエンジン | [backend/core/rules.py](../backend/core/rules.py) | YAML ルール：一致、しきい値、シーケンス。Web 向けの、モジュールのルールフォルダーの説明 | PyYAML | collector、api_modules |
| グループ化 | [backend/core/grouping.py](../backend/core/grouping.py) | グループ、ウィンドウ、バッファ、`external_id` | storage | collector |
| SOC への配信 | [backend/core/soc.py](../backend/core/soc.py) | アラートの形式、クライアント、送信スレッド、ハートビート、エラー処理 | storage、config | collector、web、manage |
| チャネル | [backend/core/channels.py](../backend/core/channels.py) | SOC とは別の、管理者向けのメッセージ：設定（`fChannelSettings`）、15言語のテキスト（`lLanguages`。欠けている場合は英語：`fBuildMessage`、`fTestMessage`）、Telegram クライアント（`TelegramClient`）、送信スレッド（`ChannelSender`）とその状態 `channels.status` | config、masking、timeutil | collector、web |
| ヘルス | [backend/core/health.py](../backend/core/health.py) | アンチフォレンジックの通知、未解析の行、沈黙したソース、ディスク | storage | collector |
| マスク | [backend/core/masking.py](../backend/core/masking.py) | 機密性のあるパラメーター、JSON のキー、ヘッダー、ModSecurity のデータ | — | モジュール |
| ローカルソケット | [backend/core/ipc.py](../backend/core/ipc.py) | Unix ソケット（開発用には抽象ソケット）上の JSON：Web からコレクターへのコマンド | — | collector、web |
| モジュールカタログ | [backend/core/catalog.py](../backend/core/catalog.py) | `localSIEM-modules` リポジトリのアーカイブ（設定 `modules_repository`）：ダウンロード、安全な展開、その `mod-<id>` フォルダーとインストール済みのものとの比較（`action`、`newer`）、`<id>/` へのアトミックなインストールまたは更新（`previous`、`access_changed`）とアンインストール（一度に1つ）、root 用のコマンド（`manage.py setup-modules`） | config、registry | web（`api_modules`） |
| インストール済みのモジュール | `/opt/localsiem/modules/<name>/`。Web が `localSIEM-modules` リポジトリからインストールします（現在は `apache2` と `privesc`。リポジトリのフォルダーは `mod-apache2/` と `mod-privesc/`） | Apache：検出、解析、相関、実行されたアクション、重大度、ルール、エンリッチメント、診断、要件（Apache と ModSecurity 2）、ヘルス、リクエストカード。privesc：権限昇格。そのプロジェクトで文書化されています | core | collector、web、manage |
| Web アプリケーション | [backend/web/app.py](../backend/web/app.py) | 両方のダッシュボードのページとそのリダイレクト（ユーザーとモジュールのセクション、モジュールのページの旧 URL）、認証、アカウント、ガード（許可された IP、セキュリティヘッダー） | context、api_* | server |
| Web コンテキスト | [backend/web/context.py](../backend/web/context.py) | 設定、アカウント、イベントデータベース（読み取り専用）、フィンガープリント付きの `index.html`、コレクターのソケット、モジュールのマニフェスト、Web フック用のインスタンス、Web が確認した要件（`dRequirements`） | auth、webdb、registry | web |
| アカウントとセッション | [backend/web/auth.py](../backend/web/auth.py)、[webdb.py](../backend/web/webdb.py)、[totp.py](../backend/web/totp.py) | ユーザー、セッション（その方式：パスワードまたはトークン）、ロック、CSRF、TOTP、許可された IP、直接サインイン用のアクセストークン、サインインの記録、検索監査 | security | web、manage、configure |
| 検索 API | [backend/web/api_search.py](../backend/web/api_search.py) | 検索、ヒストグラム、集計、エクスポート、リクエストカード（各モジュールが自身のフィールドを追加）、アラート、ライブ用 WebSocket | storage、query | web |
| モジュールと概要の API | [backend/web/api_modules.py](../backend/web/api_modules.py) | すべてのモジュールの状態とその理由（不足している要件も含む）、1つのモジュールの詳細（設定、要件、ソース、診断、ルール）とその保存（要件を満たしている場合にのみ有効化）、再構成、リポジトリからのインストールまたは更新（同じ呼び出し。要件を満たさない場合に無効になるのは初回のインストール時のみ。`access_changed`）とアンインストール、ダッシュボードの概要 | registry、catalog、rules、storage、config | web |
| 管理 API | [backend/web/api_admin.py](../backend/web/api_admin.py) | ユーザー、SOC、チャネル、設定、監査 | storage、soc、channels、config | web |
| フロントエンド | [frontend/](../frontend/) | 1つの HTML シェル、`common.js`、`app.js`（両方のダッシュボードと、ユーザー、チャネル、モジュールのセクションのルーター、サインイン）、`overview.js`、`search.js`（検索、ライブビュー、アラート、アカウント）、`modules.js`（管理者向けのインストール済みとインストール可能のセクション：インストール済みのモジュールごとに1行で、リポジトリに新しいバージョンがある場合は更新付き。リポジトリのモジュールのうちまだインストールされていないものは、リポジトリの応答を10分間保持して表示。1つのモジュールのページは、要件と再構成付き）、`admin.js`（アカウントとアクセストークンを含むユーザー、SOC、全般と Telegram を含むチャネル、設定、監査、サインイン履歴）、SOC のスタイルシートと `localsiem.css`、15言語（he-IL は右から左） | — | ブラウザー |
| デプロイ | [deploy/](../deploy/) | コアだけのインストーラー（GitHub またはコピーから。1つのアクション：インストール、更新、ゼロからの再インストール、アンインストール。不足しているパッケージ、ダウンロード、`manage.py setup-modules --no-restart` による、インストール済みのモジュールの `read_paths` への読み取り権限）、`configure.py`（設定、証明書、認証情報、`modules_repository`）、systemd ユニット、OpenRC スクリプト、certbot フック、logrotate | manage、registry | root |

<a id="symbols"></a>
## 3. 主要なシンボル

| シンボル | ファイル:行 | 役割 |
|---|---|---|
| `Collector` | [backend/collector.py:58](../backend/collector.py#L58) | コレクター：セットアップ、メインループ、すべての定期タスク |
| `Collector.mSetup` | [backend/collector.py:104](../backend/collector.py#L104) | モジュールを読み込み（`fCreateModules`）、各モジュールの `mStart` とコリレーター、«Modules: ...» のログ出力、要件、ルール、検出、保留中のレコードを処理します |
| `Collector.mCheckRequirements` | [backend/collector.py:134](../backend/collector.py#L134) | 起動時とリロード時の、すべてのモジュールの要件（`fCheckRequirements`）：Web 向けの状態 `<name>.requirements`。不足しているものをログに記録します。モジュールを有効にも無効にもしません |
| `Collector.mDiscover` | [backend/collector.py:163](../backend/collector.py#L163) | 有効なモジュールのソース。新しいソースを開き（末尾から。ただし、そのモジュールがすでに追跡されていた場合を除く：`sFollowedModules`）、なくなったソースを閉じます |
| `Collector.mReloadSettings` | [backend/collector.py:211](../backend/collector.py#L211) | 新しい設定：モジュール、要件、グループ化、ルール、検出、診断、状態をただちに公開します |
| `Collector.mDiscoveryInterval` | [backend/collector.py:316](../backend/collector.py#L316) | 有効なモジュールの中で最も短い検出間隔（最低60秒） |
| `Collector.mReadSources` | [backend/collector.py:327](../backend/collector.py#L327) | すべてのソースをポーリングし（追いつき処理中はバランスを取ります）、フレーミング、解析、レコードと位置の保存を行います |
| `Collector.mWatermark` | [backend/collector.py:416](../backend/collector.py#L416) | モジュールの遅れているソースが読み取った、最も古いログ時刻 |
| `Collector.mProcessDue` | [backend/collector.py:424](../backend/collector.py#L424) | 期限が来たトランザクションのイベントを構築し、ルールを実行し、保存し、検出します |
| `Collector.mProcessGroups` | [backend/collector.py:485](../backend/collector.py#L485) | バッファ期間を過ぎたグループ：エンリッチメント、アラート、SOC キュー |
| `Collector.mRetention` | [backend/collector.py:534](../backend/collector.py#L534) | 日数とサイズによる削除、インクリメンタルバキューム |
| `Collector.mPublishState` | [backend/collector.py:569](../backend/collector.py#L569) | `collector.status`：ソース、ディスク、データベース、ルール、スキップしたログ、モジュールごとの状態（`enabled`、`version`、`sources`、`pending`）、`module_errors` |
| `Collector.mPublishDoctor` | [backend/collector.py:612](../backend/collector.py#L612) | 各モジュールの `<name>.doctor`（無効なモジュールは空） |
| `Collector.mHandleIpc` | [backend/collector.py:624](../backend/collector.py#L624) | Web からのコマンド：reload（再構成からも）、doctor、restart（Web からモジュールをインストール、更新、アンインストールした場合）、SOC の再試行と拒否されたアラートの再キューイング。ハートビートと状態も扱います |
| `fListManifests` | [backend/core/registry.py:165](../backend/core/registry.py#L165) | `module.json` を持つインストール済みのモジュールのフォルダー（`cModulesPath` 内、名前順）。エラーは別に扱います |
| `fReadManifest` | [backend/core/registry.py:133](../backend/core/registry.py#L133) | `module.json` を検証し（id：フォルダー名、またはフォルダー `mod-<id>` に対してカタログが与える id。entry、settings、`core`）、既定値を補い、ロケールを読み取ります |
| `fCheckInstallRequirements` | [backend/core/registry.py:97](../backend/core/registry.py#L97) | `module.json` の `install_requirements` を検証します（`fReadManifest` から呼び出されます）：`lSystems` のシステム（`debian`、`alpine`）、1行のコマンドが1〜20個、シェル演算子なし（`cShellOperatorRegex`）。Web が各コマンドの先頭に `sudo` を付けるためです |
| `fLoadClass` | [backend/core/registry.py:197](../backend/core/registry.py#L197) | `fRegisterPackage` の後で `localsiem_modules.<name>.<file>` をインポートし、クラスを検証します |
| `fCreateModules` | [backend/core/registry.py:229](../backend/core/registry.py#L229) | `({name: module}, manifests, errors)`。失敗したモジュールが、ほかのモジュールを止めることはありません |
| `fCheckRequirements` | [backend/core/registry.py:214](../backend/core/registry.py#L214) | モジュールの `mRequirements()` を `{time, checks, met}` として返します（met：エラーのチェックが1つもない。例外は未充足として扱います） |
| `fModuleSettings` | [backend/core/registry.py:250](../backend/core/registry.py#L250) | `settings.json` の `modules.<name>` の下にある `module.json` の既定値 |
| `fValidateSettings` | [backend/core/registry.py:317](../backend/core/registry.py#L317) | 管理者が保存するものを `module.json` に照らして検証します。`ValueError("invalid_setting:<key>")` |
| `Module` | [backend/core/module.py:59](../backend/core/module.py#L59) | モジュールのインターフェース：`mModuleSettings`、`mEnabled`、`mStart`、`mDiscoveryInterval`、`mDiscover`、`mParse`、`mBuildEvent`、`mDoctor`、`mRequirements`、`mSkipped`、`mSetLowDisk`、`mDisplayRecord`... |
| `FileTailer` | [backend/core/tailer.py:37](../backend/core/tailer.py#L37) | 読み取り専用で開いた、追跡中の1つのファイル：位置（最初の位置が保存されるまでは `vOpenedUnsaved`）、ローテーション、切り詰め、削除。`vWasReadable`（今回の実行で開いた、または以前の実行で位置が保存された）：`unreadable` の通知はこれを `was_readable` として伝えます |
| `FileTailer.mPoll` | [backend/core/tailer.py:250](../backend/core/tailer.py#L250) | 新しい完全な行をそのオフセットと共に読み取り、通知も返します |
| `SqliteStorage` | [backend/core/storage_sqlite.py:303](../backend/core/storage_sqlite.py#L303) | SQLite のストレージ |
| `SqliteStorage.mSaveRecords` | [backend/core/storage_sqlite.py:392](../backend/core/storage_sqlite.py#L392) | レコード、全文インデックス、位置を1つのトランザクションで保存します |
| `fCompileQuery` | [backend/core/storage_sqlite.py:281](../backend/core/storage_sqlite.py#L281) | 検索ツリーをパラメーター付きの SQL に変換します |
| `SqliteStorage.mSearch` | [backend/core/storage_sqlite.py:878](../backend/core/storage_sqlite.py#L878) | 時間によるページネーションと制限時間付きの検索 |
| `SqliteStorage.mGetIpContext` | [backend/core/storage_sqlite.py:504](../backend/core/storage_sqlite.py#L504) | IP のブロックされたリクエスト数と総リクエスト数、初めて確認された時刻 |
| `SqliteStorage.mCountRecentEvents` | [backend/core/storage_sqlite.py:539](../backend/core/storage_sqlite.py#L539) | ある時刻以降の1つのモジュールのイベントと、最も多い IP（モジュールのヘルスチェック） |
| `SqliteStorage.mModuleCounts` | [backend/core/storage_sqlite.py:708](../backend/core/storage_sqlite.py#L708) | モジュールごとのイベント数、ブロック数、アラート数、最終時刻 |
| `SqliteStorage.mAlertCounts` | [backend/core/storage_sqlite.py:720](../backend/core/storage_sqlite.py#L720) | ある時刻以降に作成されたアラート（状態別と重大度別） |
| `SqliteStorage.mGetEventDetail` | [backend/core/storage_sqlite.py:949](../backend/core/storage_sqlite.py#L949) | 1つのイベントとそのレコード（それぞれ `module` 付き）、ルールのヒット、アラート |
| `SqliteStorage.mGroupEvents` | [backend/core/storage_sqlite.py:1011](../backend/core/storage_sqlite.py#L1011) | アラートのリクエスト（`event_alerts`）：最大50件（`api_search.py` の `cAlertEvents`）、古いものから順に、検索と同じ列で返し、総数も返します。`GET /api/alerts/{id}` はそれらを `events` と `events_total` として返します |
| `fAlertRequests` / `fBindRows` | [frontend/assets/search.js:687](../frontend/assets/search.js#L687) / [:259](../frontend/assets/search.js#L259) | 開いたアラートの行（アラート）に表示する、そのアラートのリクエスト。検索の行（`fResultRow`）を使い、クリックするとリクエストカードが開きます（`fToggleRow` → `fRequestCard`）。`fBindRows` は自身のテーブル内のカードでのクリックだけを無視するため、アラートの開いた行の中でも機能します。アラートを開いている間、アラートの一覧は更新されません |
| `fParseQuery` | [backend/core/query.py:232](../backend/core/query.py#L232) | クエリのテキストをツリーに変換します。コードと位置を持つ `QueryError` |
| `RulesEngine` / `Rule` | [backend/core/rules.py:319](../backend/core/rules.py#L319) / [:93](../backend/core/rules.py#L93) | YAML ルールを読み込み、評価します |
| `fDescribeFolder` | [backend/core/rules.py:54](../backend/core/rules.py#L54) | モジュールのフォルダーのルールを、ファイルが定義するとおりに返します。無効なものも含みます（モジュールのページ） |
| `Grouper` | [backend/core/grouping.py:38](../backend/core/grouping.py#L38) | 検出をグループにまとめます（ウィンドウ、バッファ） |
| `fExternalId` | [backend/core/grouping.py:31](../backend/core/grouping.py#L31) | 決定論的な `external_id` |
| `fBuildAlert` | [backend/core/soc.py:67](../backend/core/soc.py#L67) | グループを `GenericAlert` に変換します（時刻は記録用形式） |
| `SocSender.mDeliver` | [backend/core/soc.py:256](../backend/core/soc.py#L256) | バッチを送信します。413/422 で分割し、401、507、ネットワークエラーを処理します |
| `fSocConfigured` / `SqliteStorage.mSkipPending` | [backend/core/soc.py:43](../backend/core/soc.py#L43) / [backend/core/storage_sqlite.py:630](../backend/core/storage_sqlite.py#L630) | 送信先の SOC があるかどうか（URL、トークン、`soc_enabled`）。ない場合、保留中だったものは `local`（未送信）になります |
| `ChannelSender.mNotify` / `ChannelSender.mDeliver` | [backend/core/channels.py:330](../backend/core/channels.py#L330) / [:414](../backend/core/channels.py#L414) | コレクターは、SOC 用にキューに入れるすべてのアラートをこれに渡します。`min_severity` 以上のアラートは、有効で設定済みの各チャネルの一覧に入ります（最大200件。最も古いものが破棄されます）。1秒に1メッセージ。エラーの場合は再試行する（`retry_after`、徐々に長くなる待機）か、破棄します（400、401、403、404、または5回の試行） |
| `TelegramClient.mCall` / `fBuildMessage` | [backend/core/channels.py:273](../backend/core/channels.py#L273) / [:226](../backend/core/channels.py#L226) | `https://api.telegram.org/bot<token>/<method>` への POST。失敗は `TelegramError`（ステータス、説明、`retry_after`）で、トークンを含むことはありません。メッセージ：重大度、ルール、説明、モジュール、イベント、初回と最終の時刻（表示用形式）、検索を、チャネルの言語で記述します |
| `HealthMonitor` | [backend/core/health.py:110](../backend/core/health.py#L110) | 未解析の行、沈黙したソース、ディスクのレベル |
| `fNoticeDetection` | [backend/core/health.py:58](../backend/core/health.py#L58) | ソースの通知（truncated、missing、replaced、unreadable、rotated_lost）のアラート。`unreadable` は `was_readable` の場合のみです。一度も読み取られていないログ（`setup-modules` の前の、インストールしたばかりのモジュールのもの）はそのソースの状態にすぎず、コレクターはアラートを出さずにログに記録します（`Collector.mHandleNotice`） |
| `Masker` | [backend/core/masking.py:17](../backend/core/masking.py#L17) | パラメーター、JSON、ヘッダー、ModSecurity のデータをマスクします |
| `fCreateApp` | [backend/web/app.py:114](../backend/web/app.py#L114) | FastAPI アプリケーション、そのページ、ガードを構築します |
| `fUserTab` / `fAdminTab` | [backend/web/app.py:196](../backend/web/app.py#L196) / [:211](../backend/web/app.py#L211) | 各ダッシュボードのタブと、ロールのダッシュボードへのリダイレクト。`users` と `modules` は最初のセクション（`users/accounts/`、`modules/installed/`）に移動します |
| `fAdminUsersSection` | [backend/web/app.py:232](../backend/web/app.py#L232) | ユーザーのセクション：`accounts`（既定）と `tokens` |
| `fAdminModulesSection` | [backend/web/app.py:264](../backend/web/app.py#L264) | モジュールのセクション（`lModuleSections`）：`installed`（既定）と `installable`。まずセッションを確認し（ない場合はサインインへ）、アナリストは `/user/dashboard/modules/` に移動します。モジュールの旧 URL `/admin/dashboard/modules/<name>/` は、インストール済みであれば `installed/<name>/` への 301 を、そうでなければ 404 を返します |
| `fAdminChannelsSection` | [backend/web/app.py:246](../backend/web/app.py#L246) | `/admin/dashboard/channels/general/` と `telegram/`（管理者のみ。それ以外のセクションは 404） |
| `fLoginWithToken` | [backend/web/app.py:387](../backend/web/app.py#L387) | `/auth/login/auto?token=...`（または `?TOKEN`）：直接サインイン、ロック、記録、このサイトのみの `next` |
| `fCreateToken` / `fLogins` | [backend/web/api_admin.py:421](../backend/web/api_admin.py#L421) / [:446](../backend/web/api_admin.py#L446) | アクセストークンを作成します（応答にトークンが1回だけ含まれます）。サインインを一覧表示します（結果で絞り込み、`alert_retention_days` の経過後に削除） |
| `fAdminModule` | [backend/web/app.py:283](../backend/web/app.py#L283) | 1つのモジュールのページ `/admin/dashboard/modules/installed/<name>/`（管理者向け。アナリストは `/user/dashboard/modules/` に移動。インストールされていないモジュールは 404） |
| `WebContext.mReloadModules` | [backend/web/context.py:51](../backend/web/context.py#L51) | Web からのインストール、更新、アンインストールの後：`module.json` ファイルを読み直し、そのモジュールのコードを改めてインポートし、Web が確認したその要件を破棄します |
| `WebContext.mModule` | [backend/web/context.py:91](../backend/web/context.py#L91) | Web フック（`mDisplayRecord`）用のモジュールのインスタンス |
| `WebContext.mCheckRequirements` | [backend/web/context.py:105](../backend/web/context.py#L105) | 新しいインスタンス上での、インストール済みモジュールの要件（保存済みの設定、または保存しようとしている設定で）。保存済みの設定による結果は `dRequirements` に保持されます |
| `fSummary` | [backend/web/api_modules.py:104](../backend/web/api_modules.py#L104) | 1つのモジュールの状態（`ok`、`warning`、`error`、`pending`、`disabled`、`unknown`）とその理由（無効で要件が不足している間は `requirements_missing`）、`has_requirements`、`requirements_missing` |
| `fRequirements` / `fMissing` | [backend/web/api_modules.py:88](../backend/web/api_modules.py#L88) / [:99](../backend/web/api_modules.py#L99) | モジュールの最新の要件チェック（コレクターのものか Web のもの）。満たされていないチェック |
| `fRules` / `fCleanRules` | [backend/web/api_modules.py:196](../backend/web/api_modules.py#L196) / [:208](../backend/web/api_modules.py#L208) | モジュールのルールとその上書き。上書きは保存前に検証されます |
| `fRegisterModules` | [backend/web/api_modules.py:237](../backend/web/api_modules.py#L237) | `/api/modules`、`/api/admin/modules/{name}`（`/doctor` と `/reconfigure` 付き。`DELETE` でアンインストール）、`/api/admin/module-catalog`、`/api/overview` |
| `fReconfigure` / `fFirstInstallation` | [backend/web/api_modules.py:338](../backend/web/api_modules.py#L338) / [:369](../backend/web/api_modules.py#L369) | 再構成：要件の再確認、コレクターの `reload`、要件を満たした場合の root 用のコマンド（モジュールを有効にすることはありません）。初回のインストール：要件が不足しており、`modules.<name>.enabled` が一度も保存されていない場合は無効にします |
| `fOverview` | [backend/web/api_modules.py:439](../backend/web/api_modules.py#L439) | 概要のデータ：24時間の件数、1時間ごとのヒストグラム、モジュール、SOC、コレクター、ディスク、最新のアラート |
| `Accounts` | [backend/web/auth.py:128](../backend/web/auth.py#L128) | ユーザー、ログイン、TOTP、セッション、ロック、アクセストークン、サインインの記録、検索監査 |
| `Accounts.mCreateSession` / `mLoadSession` | [backend/web/auth.py:323](../backend/web/auth.py#L323) / [:340](../backend/web/auth.py#L340) | 方式（`password` または `token`）付きのセッション。トークンのセッションでは第2要素もパスワードの変更も求められず、それを保持できるのはアナリストだけです。`mfa_enabled` が有効な場合、第2要素のないアカウントのパスワードセッションは無効です |
| `fSaveSettingsRoute` | [backend/web/api_admin.py:358](../backend/web/api_admin.py#L358) | 管理パネルの設定。`mfa_enabled` も含みます（これを有効にしたことで、保存した管理者のセッションが終了した場合は `session_closed`） |
| `fChannels` / `fSaveChannels` / `fSaveTelegram` / `fTestTelegram` | [backend/web/api_admin.py:230](../backend/web/api_admin.py#L230) / [:252](../backend/web/api_admin.py#L252) / [:275](../backend/web/api_admin.py#L275) / [:309](../backend/web/api_admin.py#L309) | チャネルの設定と状態（マスクしたトークン、`bot_id`）。全般の設定（`enabled`、`min_severity`、`language`）。Telegram（`config/telegram-bot-token` のトークン、`chat_id`、両方がある場合のみ `enabled`：`telegram_incomplete`。`remove_token`）。保存済みの値によるテストメッセージ（`getMe` + `sendMessage`） |
| `Accounts.mCreateAccessToken` / `mCheckAccessToken` | [backend/web/auth.py:371](../backend/web/auth.py#L371) / [:412](../backend/web/auth.py#L412) | 有効なアナリスト用のトークン（1〜365日。保持するのは SHA-256 だけで、表示は1回だけ）。ユーザー、またはセッションを開かない理由 |
| `Accounts.mRecordLogin` | [backend/web/auth.py:440](../backend/web/auth.py#L440) | `logins` の1行：アカウント、方式（`password`、`password_totp`、`token`）、結果、理由、IP、ブラウザー |
| `fEvent` | [backend/web/api_search.py:173](../backend/web/api_search.py#L173) | リクエストカード：イベントとそのレコード、各モジュールが追加するフィールド |
| `fLive` | [backend/web/api_search.py:225](../backend/web/api_search.py#L225) | ライブ用 WebSocket：サインイン済みのセッション Cookie でのみ開けます（それ以外は 4401 で閉じます） |
| `fDownload` / `fCatalog` | [backend/core/catalog.py:121](../backend/core/catalog.py#L121) / [:171](../backend/core/catalog.py#L171) | リポジトリのアーカイブを安全に展開します。そのモジュール（`mod-<id>` フォルダー：`fModuleFolders`）とそのアクション（install、update、reinstall、downgrade、incompatible、invalid）、`newer`（インストール済みで、リポジトリに新しいバージョンがある。この localSIEM ではインストールできないものも含む）。インストール可能にはインストールされていないもの（`installed` が null：install、incompatible、invalid）だけが一覧表示され、インストール済みは `newer` を使います（アクションが update なら更新、incompatible なら必要な localSIEM だけを表示）。各項目には、その `module.json` の `install_requirements` も含まれます（要件のダイアログ） |
| `fInstall` / `InstallLock` | [backend/core/catalog.py:235](../backend/core/catalog.py#L235) / [:213](../backend/core/catalog.py#L213) | `mod-<name>` フォルダーをインストール済みの `<name>` の隣にコピーし、リネームで入れ替えます（インストールと更新）。`previous`（置き換えたバージョン、初回のインストールでは `None`）と `access_changed`（`read_paths` が置き換えたコピーのものと異なる。初回のインストールでは常に true）を含むマニフェストを返します。インストール、更新、アンインストールは一度に1つだけです |
| `fRemove` / `fUninstallModule` | [backend/core/catalog.py:302](../backend/core/catalog.py#L302) / [backend/web/api_modules.py:422](../backend/web/api_modules.py#L422) | インストール済みのモジュールをアンインストールします。読み込めないモジュールも対象です：そのフォルダーをステージングフォルダーにリネームしてから削除します。`DELETE /api/admin/modules/{name}`（フォルダーがない場合は 404 `module_not_installed`。その後 `mReloadModules` を実行し、コレクターが再起動します） |
| `fFetchCatalog` / `fFetchAndInstall` / `fRootCommand` | [backend/core/catalog.py:330](../backend/core/catalog.py#L330) / [:337](../backend/core/catalog.py#L337) / [:372](../backend/core/catalog.py#L372) | Web が実行するもの（`/opt/localsiem/run/` にダウンロード）。Web からのインストール（または `access_changed` のある更新）や再構成の後の root 用のコマンド：`manage.py setup-modules` |
| `fServerSystem` | [backend/core/catalog.py:345](../backend/core/catalog.py#L345) | モジュールの `install_requirements` 向けの、このサーバーのシステム：`family`（`/etc/alpine-release` があれば `alpine`、`/etc/debian_version` があれば `debian`、または `/etc/os-release` の `ID`/`ID_LIKE`。それ以外は空）と `name`（`PRETTY_NAME`） |
| `fResolveRef` | [backend/core/catalog.py:91](../backend/core/catalog.py#L91) | github.com のリポジトリについて、ブランチまたはタグのコミット（GitHub API、`Accept: application/vnd.github.sha`）を取得します。そのため、ダウンロードされるアーカイブはそのコミットのものであり、GitHub がキャッシュに保持しているコピーではありません。ほかのリポジトリ、アーカイブ、すでにコミットである ref、または API の応答がない場合：ref はそのままです。すべてのダウンロードは `Cache-Control: no-cache` を送信します（`dNoCacheHeaders`） |
| `fGetCatalog` / `fInstallFromCatalog` | [backend/web/api_modules.py:384](../backend/web/api_modules.py#L384) / [:395](../backend/web/api_modules.py#L395) | `GET /api/admin/module-catalog`：リポジトリのモジュールを `installed`、`newer`、`action` 付きで返します（インストール可能と、インストール済みの更新）。`POST /api/admin/module-catalog/{name}`：インストールまたは更新し（同じ呼び出し。`fFirstInstallation` は以前のコピーがなかった場合のみ）、その後 `mReloadModules` とコレクターの `restart` を行います。応答には `version`、`previous`、`enabled`、`turned_off`、`requirements_missing`、`read_paths`、`access_changed`、`root_command`、`collector_restarted` が含まれます。`GET` の応答には `system`（`fServerSystem`）も含まれ、各モジュールにはその `install_requirements` が含まれます |
| `fGrantReadAccess` | [backend/manage.py:116](../backend/manage.py#L116) | インストール済みモジュールの `read_paths` に対する読み取り権限（ACL、デフォルト ACL、Debian では `adm` グループ）。`setup-modules` が実行します |
| `fConfigureCredentials` / `fEnsureAdmin` | [deploy/configure.py:247](../deploy/configure.py#L247) / [:340](../deploy/configure.py#L340) | `localsiem.env`：JWT シークレット。新規インストール時、または `--rotate-credentials`（現在は新しい JWT シークレットだけを意味します）の場合にのみ作成されます。実行のたびに、古いバージョンがリモート入力のために保持していた変数（`lRemovedEnvironment`）を削除し、最大1つのブロック（システムユーザーと JWT 署名シークレット）を返します。最初の Web アカウントは `admin` です。`fMain` は `/root/webapp-credentials.txt` に、まず `admin` のブロックを書き込み、次に `fConfigureCredentials` が返すブロックを書き込みます。後の手順が失敗した場合も同様です |
| `fConfigureSettings` / `fRemoveSettings` | [deploy/configure.py:220](../deploy/configure.py#L220) / [backend/core/config.py:194](../backend/core/config.py#L194) | インストーラーに指定された設定を `settings.json` に保存します。もう存在しない機能の保存済みのキー（`lRemovedSettings`：`http_input`）を削除し、それらのいずれかがある場合にのみファイルを書き込みます |
| `lLanguages` / `lRightToLeftLanguages` | [backend/core/config.py:46](../backend/core/config.py#L46) / [:50](../backend/core/config.py#L50) | 15言語（アルファベット順。en-US が原文であり、フォールバック）と、右から左に書かれる言語（he-IL）。`common.js` の `cLanguages` と `cRightToLeft` は、Web 用の同じリストです |
| `fConfigureCertificates` | [deploy/configure.py:277](../deploy/configure.py#L277) | 指定された証明書、Let's Encrypt（デプロイフック付き）、既存の証明書、または自己署名証明書 |
| `fGetSource` | [deploy/install-update-reinstall-debian.sh:525](../deploy/install-update-reinstall-debian.sh#L525) / [alpine.sh:524](../deploy/install-update-reinstall-alpine.sh#L524) | インストーラーの実行元である完全なコピー、または `/tmp/localsiem-install.*` に展開した GitHub のアーカイブ（`--ref`、`--source-url`） |
| `fResolveRef`（インストーラー） | [deploy/install-update-reinstall-debian.sh:504](../deploy/install-update-reinstall-debian.sh#L504) / [alpine.sh:503](../deploy/install-update-reinstall-alpine.sh#L503) | キャッシュなしで GitHub API に問い合わせた `--ref`（既定値 `main`）のコミット。`fGetSource` はそのコミットのアーカイブをダウンロードし、API が応答しない場合は警告を出してブランチのアーカイブをダウンロードします。すべての `curl` は `Cache-Control: no-cache` を送信します（`aNoCache`） |
| `fEnsurePackages` | [deploy/install-update-reinstall-debian.sh:479](../deploy/install-update-reinstall-debian.sh#L479) / [alpine.sh:483](../deploy/install-update-reinstall-alpine.sh#L483) | 不足しているパッケージだけをインストールします。`apt-get update` / `apk update` もその場合だけ実行します |
| `fGrantLogAccess` | [deploy/install-update-reinstall-debian.sh:585](../deploy/install-update-reinstall-debian.sh#L585) / [alpine.sh:584](../deploy/install-update-reinstall-alpine.sh#L584) | 更新のたびに、インストール済みのモジュールのフォルダーに読み取り権限を与えます：`manage.py setup-modules --no-restart` |
| `fIsInstalled` | [deploy/install-update-reinstall-debian.sh:462](../deploy/install-update-reinstall-debian.sh#L462) / [alpine.sh:466](../deploy/install-update-reinstall-alpine.sh#L466) | localSIEM の痕跡（`/opt/localsiem`、その systemd ユニットや OpenRC スクリプト、またはそのホームを持つユーザー `localsiem`）。痕跡があれば `--install` が停止し、なければ `--update` と `--reinstall` が停止します |
| `fConfirmRemoval` / `fRemoveInstallation` / `fUninstall` | [deploy/install-update-reinstall-debian.sh:710](../deploy/install-update-reinstall-debian.sh#L710) / [:749](../deploy/install-update-reinstall-debian.sh#L749) / [:817](../deploy/install-update-reinstall-debian.sh#L817); [alpine.sh:694](../deploy/install-update-reinstall-alpine.sh#L694) / [:733](../deploy/install-update-reinstall-alpine.sh#L733) / [:808](../deploy/install-update-reinstall-alpine.sh#L808) | `--uninstall` と `--reinstall` で共有します。`fConfirmRemoval`：削除されるものを示し、`--yes` がない場合は `/dev/tty` で `yes` を求めます（キャンセルはエラーではありません：`vConfirmed` は空のままです）。`fRemoveInstallation`：サービス、プロセス、ACL（`fRemoveReadAccess`）、apache2 モジュールのバージョン 1.2.0 以前の `--configure-apache` が追加した Apache のファイル（`fRemoveApacheSetup`。`localsiem_access.log*` は残ります）、logrotate、Let's Encrypt のフック、ユーザーとグループ、`/opt/localsiem`、`/tmp/localsiem-install.*` にある以前の実行のコピー（今回の実行のものは除く）、`/root/webapp-credentials.txt` の localSIEM のブロック（`fRemoveCredentials`）。`fUninstall`：`--uninstall` で、独自のログの開始を伴います。何も削除しなかった場合（`vRemovedAny` が空）、`fUninstall` は «Nothing of localSIEM was found on this server.» と表示します |
| `fInitStyle` / `fStartLog` / `fSplitOutput` / `fStopLog` | [deploy/install-update-reinstall-debian.sh:129](../deploy/install-update-reinstall-debian.sh#L129) / [:283](../deploy/install-update-reinstall-debian.sh#L283) / [:291](../deploy/install-update-reinstall-debian.sh#L291) / [:324](../deploy/install-update-reinstall-debian.sh#L324); [alpine.sh:128](../deploy/install-update-reinstall-alpine.sh#L128) / [:282](../deploy/install-update-reinstall-alpine.sh#L282) / [:290](../deploy/install-update-reinstall-alpine.sh#L290) / [:323](../deploy/install-update-reinstall-alpine.sh#L323) | インストーラーの出力：端末でのみ色付けします（一度だけ判定し、インストーラーが実行する Python ツールに `LOCALSIEM_COLOR` として渡します）。ログを開いた後、stdout と stderr は1つの順序付きストリームになり、`fSplitOutput`（純粋な bash で、Alpine の BusyBox でも同じ）が画面と、色コードを除いて `/root/webapp-install.log` に送ります。`cLogOnly` または `cScreenOnly` のマークが付いた行は片方にだけ送られます（`fToLog`、`fToScreen`：時刻は、画面では表示用形式、ログでは記録用形式）。`fCleanup` から呼ばれる `fStopLog` は、最後の行を待ちます |
| `fStep` / `fRun` / `fRunToLog` / `fShowOutputTail` | [deploy/install-update-reinstall-debian.sh:177](../deploy/install-update-reinstall-debian.sh#L177) / [:359](../deploy/install-update-reinstall-debian.sh#L359) / [:343](../deploy/install-update-reinstall-debian.sh#L343) / [:379](../deploy/install-update-reinstall-debian.sh#L379); [alpine.sh:176](../deploy/install-update-reinstall-alpine.sh#L176) / [:358](../deploy/install-update-reinstall-alpine.sh#L358) / [:342](../deploy/install-update-reinstall-alpine.sh#L342) / [:378](../deploy/install-update-reinstall-alpine.sh#L378) | 番号付きの手順（`[3/12] Getting localSIEM`。`vStepTotal`：インストールまたは更新は12、再インストールは13、アンインストールは2）と結果行（`fOk` ✓、`fWarn` !、`fFail` ✗、`fInfo` ·、`fDetail`）。`fRun` は出力がログにのみ送られるコマンドを実行し（`fRunToLog`：`$ command` とその行、stdin は `/dev/null`）、1行を表示するか、失敗した場合は最後の20行を表示します（`fShowOutputTail`）：apt-get または apk、curl、tar、pip、venv、ユーザー、サービス |
| `fShowHeader` / `fShowNextSteps` / `fShowFailure` | [deploy/install-update-reinstall-debian.sh:264](../deploy/install-update-reinstall-debian.sh#L264) / [:848](../deploy/install-update-reinstall-debian.sh#L848) / [:392](../deploy/install-update-reinstall-debian.sh#L392); [alpine.sh:263](../deploy/install-update-reinstall-alpine.sh#L263) / [:839](../deploy/install-update-reinstall-alpine.sh#L839) / [:391](../deploy/install-update-reinstall-alpine.sh#L391) | ヘッダー（アクション、サーバー、システム、開始時刻、ログ）。最後に、概要（Web と SIEM のアドレス、認証情報、ログ、SOC）と次の手順。失敗した場合は、停止した手順 |
| `fTokensSection` / `LocalsiemViews.logins` | [frontend/assets/admin.js:183](../frontend/assets/admin.js#L183) / [:828](../frontend/assets/admin.js#L828) | ユーザー › アクセストークン（作成、URL を1回だけ表示、取り消し）。サインイン履歴 |
| `LocalsiemViews.channels` / `fChannelsGeneralSection` / `fTelegramSection` | [frontend/assets/admin.js:420](../frontend/assets/admin.js#L420) / [:431](../frontend/assets/admin.js#L431) / [:516](../frontend/assets/admin.js#L516) | チャネルタブとそのサブタブ（`fChannelSections`）：全般（すべてのチャネルの有効化・無効化、最小重大度、言語、状態付きのチャネルごとの行）と Telegram（トークン、チャット ID、«保存してテストメッセージを送信»、«トークンを削除»、状態、設定手順）。状態は15秒ごとに更新されます |
| `ldTabs` / `fRoute` | [frontend/assets/app.js:19](../frontend/assets/app.js#L19) / [:356](../frontend/assets/app.js#L356) | 両方のダッシュボードのタブ。もう一方のダッシュボードの URL を自分のダッシュボードに移し、ユーザー、チャネル、モジュールの最初のセクション（`lUserSections`、`lChannelSections`、`lModuleSections`）を開き、旧 `/admin/dashboard/modules/<name>/` を `modules/installed/<name>/` に移し、それ以外の場所では2番目の部分を取り除くルーター。`fShowView` は `modules/installed/<name>/` に対して `LocalsiemViews.module` を描画します |
| `fLoginView` / `fDone` | [frontend/assets/app.js:97](../frontend/assets/app.js#L97) / [:153](../frontend/assets/app.js#L153) | ボタンの下に言語とテーマがあるサインインフォーム（`fLanguageSelect` / `fThemeToggle`、[common.js:590](../frontend/assets/common.js#L590) / [:602](../frontend/assets/common.js#L602)）。サインイン後、ボタンを押したときに表示されていた言語がアカウントの言語になります（`PATCH /api/account`） |
| `LocalsiemViews.overview` | [frontend/assets/overview.js:26](../frontend/assets/overview.js#L26) | 概要タブ |
| `LocalsiemViews.modules` / `.module` | [frontend/assets/modules.js:389](../frontend/assets/modules.js#L389) / [:683](../frontend/assets/modules.js#L683) | モジュールタブ：管理者にはセクション（`fModuleSections`）があり、インストール済みでは、インストール済みのモジュールごとに全幅の行が1つずつ、モジュールのページのヘッダーと同じレイアウトで、各部分を縦に並べて表示されます（`fCard`：名前、ID、バージョンと、管理者には右側の有効／無効のスイッチ（要件が不足している間はロック）を含む `.module-head`。状態、概要、理由と、管理者には新しいバージョンの通知 `fUpdateNotice`。カウンター。管理者には下部に `fCardActions`）。アナリストには行だけが表示されます。1つのモジュールのページ `installed/<name>/`（要件と再構成。«インストール済みモジュールに戻る» とアンインストールは `installed/` に移動します） |
| `fModuleSections` | [frontend/assets/modules.js:194](../frontend/assets/modules.js#L194) | モジュールのサブタブ、インストール済みとインストール可能。それぞれがその URL へのリンクです（`admin.js fUserSections` と同様） |
| `fCatalogPanel` | [frontend/assets/modules.js:218](../frontend/assets/modules.js#L218) | インストール可能セクション：リポジトリを確認します（`fCheck` → `fFetchCatalog(true)`：常にダウンロードし直します）。まだインストールされていないモジュールだけを、インストール（またはできない理由：incompatible、invalid）と共に表示します。1つもない場合は `catalog.all_installed` または `catalog.empty`。インストールすると、保持した応答を破棄し（`fForgetCatalog`）、一覧から削除して、root 用のコマンドまたはサーバーに不足しているものと «インストール済みモジュールを表示» を含むダイアログ（`P.fModal`、`fResult`）を開きます。インストールされていない各モジュールには、**インストール** の前に **要件** があります：`fShowRequirements` → `fRequirementsBody`（モジュールの注記と、`system.family` の `install_requirements`、または宣言されているすべてのシステムのもの。`fRequirementCommands` を通じて、root として実行する形と先頭に `sudo` を付けた形で、それぞれ «コピー» 付きの `fCommandBox` に表示） |
| `cCatalogSeconds` / `fFetchCatalog` / `fForgetCatalog` | [frontend/assets/modules.js:174](../frontend/assets/modules.js#L174) / [:177](../frontend/assets/modules.js#L177) / [:186](../frontend/assets/modules.js#L186) | `GET /api/admin/module-catalog` の最後の応答。ブラウザー（`dCatalogCache`）に600秒間保持され、インストール済みとインストール可能で共有されるため、インストール済みを開くたびにリポジトリをダウンロードすることはありません。`fFetchCatalog(true)`（リポジトリを確認）は常にダウンロードし直します。モジュールのインストール、更新、アンインストールを行うと破棄されます |
| `fCheckRepository` / `fUpdateNotice` | [frontend/assets/modules.js:543](../frontend/assets/modules.js#L543) / [:417](../frontend/assets/modules.js#L417) | インストール済み、管理者のみ：セクションを開いたときに一度だけ、`fFetchCatalog(false)` → `dNewer`（`newer` を持ち、アクションが update または incompatible の項目）。その間は `modules.checking_updates`、失敗した場合は `modules.updates_failed` を表示します（一覧は通常どおり機能します）。10秒ごとの更新では実行しません。行の通知（`.module-update`）：更新付きの `modules.update_notice`、またはボタンなしの `modules.update_incompatible`（`.module-update-blocked`）。インストール済みのバージョンが、リポジトリと比較したバージョンである間だけ表示されます |
| `fUpdate` / `fUpdateResult` | [frontend/assets/modules.js:452](../frontend/assets/modules.js#L452) / [:436](../frontend/assets/modules.js#L436) | 更新：確認（`modules.update_confirm`）、`POST /api/admin/module-catalog/{name}`（その間、ボタンには «更新中…» と表示されます：`sUpdating`。更新をまたいでも保持）、`fForgetCatalog`、トースト `modules.updated_toast`。ダイアログ（«<モジュール> を更新しました»）は、`access_changed`（root 用のコマンド）がある場合か、`collector_restarted` がない場合のみ。その後 `fLoad` |
| `fDraw` / `fLoad`（インストール済み） | [frontend/assets/modules.js:517](../frontend/assets/modules.js#L517) / [:531](../frontend/assets/modules.js#L531) | `fLoad`（10秒ごと）は `GET /api/modules` を要求して応答を保持する（`dLast`）だけです。`fDraw` はそこから行を描画します。リポジトリの確認が終わったときと、更新が始まったときにも描画します |
| `fCheckItem` / `fCommandBox` | [frontend/assets/modules.js:70](../frontend/assets/modules.js#L70) / [:61](../frontend/assets/modules.js#L61) | 修正方法付きの1つのチェック（診断、要件）。コピーするテキスト（root 用のコマンド） |
| `fUninstallButton` / `fCardActions` | [frontend/assets/modules.js:146](../frontend/assets/modules.js#L146) / [:508](../frontend/assets/modules.js#L508) | 確認付きのアンインストール（インストール済みの行とモジュールのページ。保持したリポジトリの応答を破棄します、`fForgetCatalog`）。管理者向けの行のアクション：構成（→ `installed/<name>/`）とアンインストール |
| `fInput` / `fRecordsEditor` | [frontend/assets/modules.js:586](../frontend/assets/modules.js#L586) / [:612](../frontend/assets/modules.js#L612) | `module.json` から構築する設定フォーム。レコードエディターを含みます |

<a id="flows"></a>
## 4. 主な呼び出し経路

**モジュールの読み込み（コレクターの起動）**

`Collector.mSetup` → `fCreateModules` → `fListManifests`（`cModulesPath/*/module.json`） → `fReadManifest`（id、entry、settings、`core` ≤ `cVersion`、ロケール） → `fLoadClass`（`fRegisterPackage` + `localsiem_modules.<name>.<file>`） → `Class(settings, masker, storage, manifest)` → `Module.mStart` → `mCreateCorrelator` → ログ «Modules: apache2 1.1.0 (on)» → `mCheckRequirements`（`fCheckRequirements` → 各モジュールの `Module.mRequirements` → 状態 `<name>.requirements`。要件が不足している場合はログ «Module apache2: requirements missing: ...»） → `mLoadRules` → `mDiscover`（有効なモジュールのみ） → `mPublishDoctor`。エラーは `ldModuleErrors` に入り、ループは続行します。

**ログの行から SOC のアラートまで**

1. `Collector.mCycle` → `mReadSources` → `FileTailer.mPoll`（新しい完全な行） → ソースのフレーマー（`Module.mCreateFramer`：`LineFramer`、または Apache モジュールの監査ログ用フレーマー） → ソースのモジュールの `Module.mParse`（マスク） → `mStoreRecords` → `SqliteStorage.mSaveRecords`（レコード + FTS + 位置、1つのトランザクション） → コリレーターの `mAdd`。
2. `mProcessDue` → コリレーターの `mDue`（ウィンドウが経過し、ウォーターマークに到達） → `Module.mBuildEvent`（実行されたアクション、スコア、検出） → `RulesEngine.mEvaluate`（モジュールのルール） → `SqliteStorage.mSaveEvents` → `mDetect` → `Grouper.mAdd`（新しいグループ、または件数 +1）。
3. `mProcessGroups`（1秒ごと） → `SqliteStorage.mGetDueGroups` → `Module.mEnrich`（`mGetIpContext`） → `fSocConfigured` → `fBuildAlert` → `mQueueGroup`（SOC がない場合：`mSkipGroup`、状態 `local`）。
4. `SocSender.run`（スレッド） → `mCycle`（SOC がない場合：`mSkipPending` のみ） → `mSendHeartbeat`（5分ごと）と `mGetQueueBatch`（≤ 100 アラート、≤ 1 MiB） → `mDeliver` → `SocClient.mSendAlerts` → `mMarkQueueSent`（SOC コード）、または分割、保留、バックオフ付きの延期、507 での一時停止。
5. さらに、`mProcessGroups` → `ChannelSender.mNotify`（`fChannelSettings`、`fSeverityReached`、`fBuildMessage`） → 有効で設定済みの各チャネルの一覧 → `ChannelSender.run`（スレッド、1秒ごと） → `mCycle` → `mDeliver` → `TelegramClient.mSendMessage` → 状態 `channels.status`（送信済み、失敗、破棄、最後のエラー）。

**Telegram の設定**

`/admin/dashboard/channels/telegram/` → `admin.js fTelegramSection` → «保存してテストメッセージを送信» → `POST /api/admin/channels/telegram`（`fSaveTelegram`：`cTokenRegex`、`cChatIdRegex`、`fSaveTelegramToken`、`fSaveSettings`、コレクターの `reload`） → `POST /api/admin/channels/telegram/test`（`fTestTelegram` → `TelegramClient.mGetMe` → `fTestMessage` による `mSendMessage`） → ボットの @username、または Telegram の説明を含む通知。

**モジュールの有効化・無効化、またはその設定やルールの保存**

`modules.js fSwitch`（モジュール › インストール済みの行、またはモジュールのページのヘッダー。無効にするときは確認。`requirements_missing` が空でない間は、リクエストを送らずにロック）、または `LocalsiemViews.module` のフォーム → `POST /api/admin/modules/{name}`（`fSaveModule`：`fValidateSettings`。無効なモジュールを有効にする場合：リクエストの設定で `WebContext.mCheckRequirements` → 満たされていないチェックと共に 422 `requirements_missing`。`fRules` + `fCleanRules`） → `fSaveSettings`（`settings.json` の `modules.<name>` と `rules.<id>`） → `WebContext.mApplySettings` → `mCollector({"command": "reload"})` → `Collector.mHandleIpc` → `mCycle` → `mReloadSettings`（`Module.mReload`、`mCheckRequirements`、`mLoadRules`、`mDiscover`、`mPublishDoctor`、`mPublishState`）。`collector.status.modules.<name>.enabled` が保存した内容と一致するまで、`fSummary` は `pending` を返します。

**要件と再構成**

モジュールのページ（`/admin/dashboard/modules/installed/<name>/`、`LocalsiemViews.module`） → «再構成»（`fReconfigure`。`has_requirements` の場合に表示） → `POST /api/admin/modules/{name}/reconfigure`（`fReconfigure` → `WebContext.mCheckRequirements`：保存済みの設定でインストール済みのコピーから新しいインスタンスを作成 → `fCheckRequirements` → `mRequirements`、`dRequirements` に保持 → コレクターの IPC `reload` → `mReloadSettings` → `mCheckRequirements`（状態 `<name>.requirements`）と、有効なモジュールについては `mDiscover` と `mPublishDoctor`） → 応答：`requirements` と、満たされている場合は `fRootCommand` → `fShowReconfigured` → `fLoad`（`GET /api/admin/modules/{name}` → `fRequirements`：コレクターと Web のチェックのうち新しい方） → スイッチのロックは解除されますが、管理者が有効にするまでモジュールは無効のままです。

**モジュールの状態と概要**

`modules.js`（モジュール › インストール済み、およびアナリストのモジュールタブ。10秒ごと） → `GET /api/modules` → `fRead`（`collector.status`、状態 `<name>.doctor` と `<name>.requirements`、24時間の `mModuleCounts`） → `fSummaries` → マニフェストごとの `fSummary`（読み込みエラー → `error`。無効 → `disabled`、最新の要件チェック `fRequirements` にエラーがある場合は `requirements_missing` 付き。コレクターが2分間沈黙 → `unknown`。`collector.status.modules` にない → `warning`/`not_loaded`。enabled が異なる → `pending`。診断のエラーまたは読み取れないソース → `error`。ソースがない、またはソースが存在しない → `warning`。診断の警告は注記で、`ok` のまま） + 読み込めないフォルダーに対する `fBrokenSummary`。`overview.js`（15秒ごと） → `GET /api/overview` → `fOverview` → `fRead`、`fSummaries`、`mAlertCounts`、`mQueueStatistics`、状態 `soc.status` と `soc.heartbeat`、`mHistogram`（24時間の1時間ごとのバケット）、`mListGroups`（最新の6件）。

**モジュールタブ、そのセクション、モジュールのページ**

`/admin/dashboard/modules/` → `fAdminTab` → `modules/installed/`（`lModuleSections[0]`）への 302 → `fAdminModulesSection`（まずセッションを確認。アナリスト → `/user/dashboard/modules/`。`installed` または `installable` → `index.html`。インストール済みのモジュールの名前、つまり旧 URL → `installed/<name>/` への 301。それ以外 → 404） → `app.js fRoute`（`cPathRegex` は2番目の部分を受け付けます。`/admin/dashboard/modules/` と `/admin/dashboard/modules/<name>/` → `modules/installed/` と `modules/installed/<name>/`。`installable/` の下やユーザーでの2番目の部分は取り除かれ、ほかのタブは2番目の部分を取りません） → `fShowView("modules", section, item)` → `LocalsiemViews.modules`（`fModuleSections`。インストール済み：`fLoad` → `GET /api/modules` → `fDraw` → モジュールごとの `fCard` と、管理者には1回の `fCheckRepository`（«モジュールの更新» を参照）。インストール可能：`fCatalogPanel`）、または item がある場合は `LocalsiemViews.module`（その場合、`vParameter` はモジュール名です）。行の «構成»（`fCardActions`） → `/admin/dashboard/modules/installed/<name>/` → `fAdminModule`（インストールされていないモジュールは 404） → `LocalsiemViews.module` → `GET /api/admin/modules/{name}`。«インストール済みモジュールに戻る»、アンインストール、なくなったモジュール（`not_found`） → `/admin/dashboard/modules/installed/`。アナリスト：`/user/dashboard/modules/` → `fUserTab` → 行だけの `LocalsiemViews.modules`（ルーターは2番目の部分をすべて取り除きます）。

**クエリから結果まで**

`search.js fRun` → `GET /api/search`、`/api/search/histogram`、`/api/search/summaries` → `fParseQuery`（エラー時はコードと位置付きで 400） → `fRange` → `SqliteStorage.mSearch` / `mHistogram` / `mSummaries` → `fCompileQuery` → プログレスハンドラー付きの SQLite（制限時間、422 `search_timeout`） → `Accounts.mAudit` → ネイティブの表示用時刻を含む JSON。行 → `GET /api/events/{id}` → `fEvent` → `mGetEventDetail` → 各レコードについて `WebContext.mModule(record.module)` → `mDisplayRecord`（Apache モジュールは監査レコードのヘッダーと本文を追加します） → ピボット付きのリクエストカード。

**アクセストークンによる直接サインイン**

`admin.js fTokensSection` → `POST /api/admin/tokens`（`fCreateToken` → `Accounts.mCreateAccessToken`：有効なアナリスト、1〜365日、`access_tokens` に SHA-256） → URL `https://<server>:10443/auth/login/auto?token=...` を1回だけ表示（`fShowSecret`）。アナリストがそれを開く → `fLoginWithToken`（名前 `(access token)` で `mIsBlocked` → `mCheckAccessToken` → `mRecordAttempt`） → 失敗：`mRecordLogin` と `/auth/login/?error=<reason>`（`app.js fLoginView` がそれを表示） → 成功：`mCreateSession(..., "token")` → `mMarkAccessTokenUsed` → `mRecordLogin` → Cookie → `next`（このサイトのパス）または `/user/dashboard/overview/`。すべてのリクエスト → `mLoadSession`（方式 `token`：アナリストのみ、第2要素なし、パスワードの変更なし）。

**サインインとダッシュボード**

`app.js fLoginView`（ページはフォームだけ：`fAuthLogo`、ユーザー名、パスワード、ボタン、その下に言語とテーマ：`fLanguageSelect`、`fThemeToggle`） → `POST /api/auth/login`（`Accounts.mIsBlocked`、`mCheckPassword`、`mRecordAttempt`） → `mfa_enabled` が無効：ただちにセッション（`step` done） → 有効：`step` totp または enroll（`mStartEnrollment`、QR） → `POST /api/auth/totp`（`mReadChallenge`、`mVerifyTotp`） → `mCreateSession` → `mRecordLogin`（すべての失敗も：`invalid_credentials`、`invalid_code`、`login_blocked`、`challenge_expired`） → Cookie `localsiem_session` → `fDone`（アカウントの言語が異なる場合は、ボタンを押したときに表示されていた言語で `PATCH /api/account`。ダッシュボードはその言語で開きます） → `next`（パラメーター付きの元の URL）、またはロールの概要に戻ります。すべてのダッシュボードの URL → `fUserTab` / `fAdminTab`（セクションとモジュールのページには `fAdminUsersSection`、`fAdminModulesSection`、`fAdminModule`。セッションなし → `/auth/login/?next=...`。別のロール → 自分のダッシュボードの同じタブ） → `index.html` → `app.js fRoute` → `fShowView` → `window.LocalsiemViews[tab]`（`modules/installed/<name>/` には `LocalsiemViews.module`）。

**コアのインストールまたは更新**

`curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- ACTION options` → `install-update-reinstall-*.sh fMain`（ちょうど1つのアクション、`--install`、`--update`、`--reinstall`、`--uninstall` のいずれかが必要で、なければ停止。`fIsInstalled`：`--install` は localSIEM がない場合のみ、`--update` と `--reinstall` はある場合のみ。`--reinstall`：まず `fConfirmRemoval`。`--configure-*` は拒否され（モジュールにはセットアップオプションがありません）、`--modules-from` も拒否されます：モジュールは Web からインストールします） → `fEnsurePackages` → `fGetSource`（完全なコピー、または `fResolveRef`（GitHub API に問い合わせた `<ref>` のコミット）と、`/tmp/localsiem-install.*` に展開する `https://github.com/PYMEHackers/localSIEM/archive/<commit>.tar.gz` のキャッシュなしの `curl`） → `configure.py --check-arguments` → `--reinstall` の場合のみ：`fRemoveInstallation`（ダウンロードしたコピー以外をすべて削除） → コアを `/opt/localsiem/webapp/` にコピー（`AGENTS.md` のように作業用コピーにのみあるファイルは、存在する場合のみ） → 仮想環境 → `configure.py`（設定、`modules_repository`、証明書、認証情報：`/root/webapp-credentials.txt` にまず `admin`、次に、新しく作成した場合はシステムユーザーと JWT シークレット。古いバージョンの `http_input` とリモート入力の変数を削除） → `fGrantLogAccess`（`manage.py setup-modules --no-restart` → `fGrantReadAccess`：インストール済みのモジュール） → サービスの再起動 → `localsiem` として `manage.py modules` と `doctor` → モジュールのインストール先（Web）の案内。画面には番号付きの手順（`fStep`）と結果のマークで表示されます。ログには同じ行が色なしで、さらに `fRun` で実行したすべてのコマンドの出力全体が書き込まれます（`fStartLog` → `fSplitOutput`）。失敗した場合は、どの手順で停止したかを示します（`fShowFailure`）。

**モジュールのアンインストール**

`modules.js fUninstallButton`（モジュール › インストール済みの行、`fCardActions`、またはモジュールのページ。確認あり） → `DELETE /api/admin/modules/{name}`（`fUninstallModule` → `fRemove` → `InstallLock` → `/opt/localsiem/modules/<name>` を `.staging-*` にリネーム → 削除） → `WebContext.mReloadModules`（モジュールは一覧に表示されなくなります） → コレクターの IPC `restart`（systemd または supervise-daemon が再び起動 → モジュールなしで `fCreateModules`） → `fForgetCatalog` → 一覧が再描画されるか、モジュールのページが `/admin/dashboard/modules/installed/` に移動します。`settings.json` には `modules.<name>` と `rules.<id>` が残ります。

**Web からのモジュールのインストール**

`/admin/dashboard/modules/installable/` → `modules.js fCatalogPanel` → «リポジトリを確認»（`fCheck` → `fFetchCatalog(true)`） → `GET /api/admin/module-catalog`（`fGetCatalog` → `fFetchCatalog` → `fResolveRef` → `fArchiveUrl` → `/opt/localsiem/run/catalog.*` への `fDownload` → `fCatalog` → `fModuleFolders`（`mod-<id>` フォルダー）と `fListManifests`） → `installed` が null の項目だけを一覧表示（`fDraw`。リポジトリのすべてのモジュールがインストール済みの場合は `catalog.all_installed`、モジュールがない場合は `catalog.empty`） → «要件»（`fShowRequirements` → `fRequirementsBody` → `fRequirementCommands`：`system.family` の `install_requirements` を、root として実行する形と `sudo` を付けた形で表示。何も実行しません）または «インストール»（`fInstall`） → `POST /api/admin/module-catalog/{name}`（`fInstallFromCatalog` → `fFetchAndInstall` → `InstallLock` → `fResolveRef` → `fDownload` → `fInstall`：`mod-<name>` → `/opt/localsiem/modules/<name>`） → `WebContext.mReloadModules` → 初回のインストールのみ：`fFirstInstallation`（インストール済みのコピーで `WebContext.mCheckRequirements` → 要件が不足しており、`modules.<name>.enabled` が一度も保存されていない場合は、`enabled: false` で `fSaveSettings`） → コレクターの IPC `restart`（`Collector.mHandleIpc` → `vStop`。systemd または supervise-daemon が再び起動 → `fCreateModules` がモジュールを読み込む → `mCheckRequirements`） → `requirements_missing` と `fRootCommand` を含む応答 → `fForgetCatalog` → モジュールは一覧から消え（`fDraw`）、ダイアログが開きます（`P.fModal`、«<モジュール> をインストールしました»、`fResult`）：サーバーに不足しているもの（と再構成）、または root 用のコマンド。閉じる、または «インストール済みモジュールを表示» → `/admin/dashboard/modules/installed/` → 管理者が root としてコマンドを実行します（`manage.py setup-modules` → `fGrantReadAccess`、`fRestartServices`、`fDoctorAsLocalsiem`）。

**モジュールの更新**

`/admin/dashboard/modules/installed/` → `LocalsiemViews.modules`（管理者） → `fLoad`（`GET /api/modules` → `dLast` → `fDraw`）と、1回だけ `fCheckRepository`（`modules.checking_updates`） → `fFetchCatalog(false)`（保持した応答が10分未満であればそれを使用、`cCatalogSeconds`。そうでなければ `GET /api/admin/module-catalog` → `fGetCatalog` → `catalog.py fFetchCatalog` → `fCatalog`：各モジュールの `newer` と `action`） → `dNewer`（`newer` を持ち、アクションが `update` または `incompatible` の項目） → `fDraw` → `fCard` → `fUpdateNotice`（項目の `installed` が行のバージョンである間のみ：`modules.update_notice` と «更新»、またはボタンなしの `modules.update_incompatible`） → «更新» → `fUpdate`（`P.fConfirm`、«モジュールを更新»。`sUpdating`：«更新中…»、10秒ごとの更新をまたいでも保持） → `POST /api/admin/module-catalog/{name}`（`fInstallFromCatalog` → `fFetchAndInstall` → `InstallLock` → `fResolveRef` → `fDownload` → `fInstall`：新しいコピーをインストール済みのものと入れ替え、`previous` と `access_changed` を返す） → `WebContext.mReloadModules` → `fFirstInstallation` は実行しない（`previous` が `None` ではないため、設定と有効／無効の状態はそのまま） → コレクターの IPC `restart` → 応答 → モジュールは `dNewer` から外れる → `fForgetCatalog` → トースト `modules.updated_toast` → `access_changed` がある場合か `collector_restarted` がない場合のみ：ダイアログ（`P.fModal`、«<モジュール> を更新しました»、`fUpdateResult`：root 用のコマンド `fRootCommand`、または `localsiem` サービスの再起動） → `fLoad`。確認に失敗した場合、`vRepositoryNote` が `modules.updates_failed` を表示し、一覧は通常どおり機能します。Web がモジュールを再インストールしたり、古いバージョンをインストールしたりすることはありません（アクション `reinstall` と `downgrade`）。

<a id="routes"></a>
## 5. ルートとエントリーポイント

| ルート / コマンド | ハンドラー | ファイル |
|---|---|---|
| `/` → ロールのダッシュボードの概要（または `/auth/login/`） | `fRoot` | [backend/web/app.py](../backend/web/app.py) |
| `/auth/login/`、`/auth/register/`、`/auth/recover/` | `fPage`（1つの HTML シェル） | [backend/web/app.py](../backend/web/app.py) |
| `/user/dashboard/` → `/user/dashboard/overview/`。`overview/`、`search/`、`live/`、`alerts/`、`modules/`、`account/`（管理者は `/admin/dashboard/` の同じタブに移動） | `fUserDashboard`、`fUserTab` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/` → `/admin/dashboard/overview/`。`overview/`、`search/`、`live/`、`alerts/`、`soc/`、`settings/`、`audit/`、`logins/`、`account/`（アナリストは `/user/dashboard/` の同じタブに、管理用のタブの場合はその `overview/` に移動）。`users/` → `users/accounts/`。`modules/` → `modules/installed/` | `fAdminDashboard`、`fAdminTab` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/users/accounts/`、`/admin/dashboard/users/tokens/`。`/admin/dashboards/...` → `/admin/dashboard/...` | `fAdminUsersSection`、`fAdminDashboards` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/channels/` → `/admin/dashboard/channels/general/`。`/admin/dashboard/channels/general/`、`/admin/dashboard/channels/telegram/`（アナリストは `/user/dashboard/overview/` に移動） | `fAdminTab`、`fAdminChannelsSection` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/modules/installed/`、`/admin/dashboard/modules/installable/`（アナリストは `/user/dashboard/modules/` に移動）。旧 `/admin/dashboard/modules/<name>/` → `/admin/dashboard/modules/installed/<name>/` への 301（モジュールがインストールされていない場合は 404） | `fAdminModulesSection` | [backend/web/app.py](../backend/web/app.py) |
| `/auth/login/auto?token=TOKEN`（または `?TOKEN`。`next` は任意） | `fLoginWithToken` | [backend/web/app.py](../backend/web/app.py) |
| `/admin/dashboard/modules/installed/<name>/`（インストールされていないモジュールは 404。アナリストは `/user/dashboard/modules/` に移動） | `fAdminModule` | [backend/web/app.py](../backend/web/app.py) |
| `GET /api/auth/session`、`POST /api/auth/login`、`POST /api/auth/totp`、`POST /api/auth/logout` | `fGetSession`、`fLogin`、`fLoginTotp`、`fLogout` | [backend/web/app.py](../backend/web/app.py) |
| `GET/PATCH /api/account`、`POST /api/account/password`、`POST /api/account/totp/reset` | アカウントのハンドラー | [backend/web/app.py](../backend/web/app.py) |
| `GET /api/search`、`/api/search/histogram`、`/api/search/summaries`、`/api/search/export` | `fSearch`、`fHistogram`、`fSummaries`、`fExport` | [backend/web/api_search.py](../backend/web/api_search.py) |
| `GET /api/events/{id}` | `fEvent` | [backend/web/api_search.py](../backend/web/api_search.py) |
| `GET /api/alerts`、`GET /api/alerts/{id}` | `fAlerts`、`fAlert` | [backend/web/api_search.py](../backend/web/api_search.py) |
| `GET /api/ws`（プロトコル）、`WebSocket /api/ws`（サインイン済みのセッション Cookie のみ。それ以外は 4401 で閉じます） | `fWebSocketProtocol`、`fLive` | [backend/web/api_search.py](../backend/web/api_search.py) |
| `GET /api/modules`（サインイン済みの任意のユーザー） | `fModules` | [backend/web/api_modules.py](../backend/web/api_modules.py) |
| `GET /api/admin/modules/{name}`、`POST /api/admin/modules/{name}`（`enabled`、`settings`、`rules`。422 `requirements_missing`）、`DELETE /api/admin/modules/{name}`（アンインストール）、`POST /api/admin/modules/{name}/doctor`、`POST /api/admin/modules/{name}/reconfigure` | `fModule`、`fSaveModule`、`fUninstallModule`、`fRunDoctor`、`fReconfigure` | [backend/web/api_modules.py](../backend/web/api_modules.py) |
| `GET /api/admin/module-catalog`（インストール可能と、インストール済みでの新しいバージョンの確認）、`POST /api/admin/module-catalog/{name}`（インストールまたは更新：同じ呼び出し） | `fGetCatalog`、`fInstallFromCatalog` | [backend/web/api_modules.py](../backend/web/api_modules.py) |
| `GET /api/overview`（サインイン済みの任意のユーザー） | `fGetOverview` | [backend/web/api_modules.py](../backend/web/api_modules.py) |
| `/api/admin/users`（GET、POST）、`/api/admin/users/{id}`（PATCH、DELETE）、`.../password`、`.../totp-reset` | ユーザーのハンドラー | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET/POST /api/admin/soc`、`POST /api/admin/soc/test`、`/retry`、`/requeue` | SOC のハンドラー | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET/POST /api/admin/channels`、`POST /api/admin/channels/telegram`、`POST /api/admin/channels/telegram/test` | `fChannels`、`fSaveChannels`、`fSaveTelegram`、`fTestTelegram` | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET/POST /api/admin/settings`、`GET /api/admin/audit` | 設定と監査のハンドラー | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET /api/admin/tokens`、`POST /api/admin/tokens`（`user_id`、`label`、`days`）、`DELETE /api/admin/tokens/{id}` | `fTokens`、`fCreateToken`、`fRevokeToken` | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `GET /api/admin/logins`（`before`、`limit`、`result`） | `fLogins` | [backend/web/api_admin.py](../backend/web/api_admin.py) |
| `/api/doc/` | FastAPI の Swagger | [backend/web/app.py](../backend/web/app.py) |
| `backend/collector.py [--from-start] [--once]` | `fMain` | [backend/collector.py](../backend/collector.py) |
| `backend/server.py`（`-h`/`--help` 以外のオプションなし） | `fMain` | [backend/server.py](../backend/server.py) |
| `backend/manage.py ensure-admin\|create-user\|reset-password\|reset-mfa\|list-users\|doctor [--json]\|modules\|read-paths\|soc-test\|setup-modules [--no-restart]` | `fMain` | [backend/manage.py](../backend/manage.py) |
| `deploy/install-update-reinstall-debian.sh`、`deploy/install-update-reinstall-alpine.sh`（1つのアクション：`--install`、`--update`、`--reinstall [--yes]`、または `--uninstall [--yes]`。`--ref`、`--source-url`、`configure.py` のオプション）。`https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/` からのパイプ実行も可能（ヘッダー `Accept: application/vnd.github.raw+json`） | `fMain` | [deploy/](../deploy/) |

<a id="impact"></a>
## 6. 影響分析

| コンポーネント | 変更した場合に影響を受けるもの |
|---|---|
| `storage_sqlite.lSchema` のスキーマ | すべての検索、Web、保持、概要の件数。列は `CREATE ... IF NOT EXISTS` で追加されます。既存の列を変更するには移行（`meta.schema_version`）が必要です。 |
| `Module` インターフェース（[backend/core/module.py](../backend/core/module.py)） | すべてのモジュール（すべて `localSIEM-modules` から提供されます。コアには独自のモジュールはありません）。コレクター。Web フック `mDisplayRecord`。`mRequirements`（初回のインストール、有効化、再構成、コレクターの起動とリロード、`manage.py modules` と `doctor`）。`manage.py`（`mDoctor`、`mSkipped`）。インストール済みのモジュールが動作し続けるよう、フックは基底クラスに既定の実装を付けて追加してください。 |
| `module.json` の形式（`fReadManifest`、`fCheckSetting`、`lSettingTypes`） | すべてのモジュール。`modules.js` の設定フォーム（`fInput`、`fRecordsEditor`）。`fValidateSettings`。`read_paths`：`manage.py read-paths` と `setup-modules`（Web とインストーラーの root 用コマンドの ACL）。検証を厳しくすると、インストール済みのモジュールが読み込まれなくなります。`install_requirements`（`fCheckInstallRequirements`、`lSystems`）：インストール可能の要件ダイアログ（`fRequirementsBody`）。誤った値を持つモジュールは、インストールも読み込みもされません |
| `Module.mRequirements` と `fCheckRequirements` | 初回のインストール（無効になる）、スイッチ（ロック。422 `requirements_missing`）、再構成、コレクターの状態 `<name>.requirements`、`manage.py modules` と `doctor`。チェックに失敗したモジュールは要件を満たさないため、有効にできません。リクエストごとやサイクルごとに呼び出さないでください。 |
| `cVersion` | すべての `module.json` の `core` フィールド：より新しいコアを必要とするモジュールは読み込まれません。Web、すべてのアラートの `details`、SOC に送信する `User-Agent` に表示されるバージョン。 |
| `cModulesPath`、`localsiem_modules` パッケージ | モジュールの検索場所とインポート方法。カタログ（`fInstall`、`InstallLock`）、各モジュール内の相対インポート、`WebContext.mReloadModules`。 |
| `backend/core/catalog.py`、その API（`fGetCatalog`、`fInstallFromCatalog`）、設定 `modules_repository` | モジュールのインストール可能セクション（`installed` が null の項目だけを一覧表示する `fCatalogPanel`）、インストール済みの更新（`fCheckRepository`、`fUpdateNotice`、`fUpdate` は、各項目の `newer`、`action`、`installed`、`version`、`core` と、インストールの応答の `previous`、`access_changed`、`root_command`、`collector_restarted` を読み取ります）とアンインストール。これらがモジュールをインストール、更新、アンインストールする唯一の方法です。`localSIEM-modules` リポジトリの構成（`mod-<id>` フォルダー：`cFolderPrefix`、`fModuleFolders`）。Web が表示する root 用のコマンド（`fRootCommand` → `manage.py setup-modules`）。Web のユニットは `ReadWritePaths` に `/opt/localsiem/modules` を保持する必要があります。要件ダイアログは、各項目の `install_requirements` と応答の `system` を読み取ります |
| ブラウザーに保持したリポジトリの応答（`modules.js` の `dCatalogCache`、`cCatalogSeconds`、`fFetchCatalog`、`fForgetCatalog`） | インストール済みとインストール可能に表示される内容：リポジトリで公開された新しいバージョンがインストール済みで提示されるまで、最大10分かかることがあります（«リポジトリを確認» を押すか、ページを再読み込みすれば短くなります）。インストール済みのモジュールを変更するすべての操作は `fForgetCatalog` を呼び出す必要があります。そうしないと、インストール済みで、すでに行った更新が提示されてしまいます。`fCheck`（リポジトリを確認）は引き続き `true` で問い合わせる必要があります。 |
| `manage.py setup-modules`（`fGrantReadAccess`、`fRestartServices`） | Web の root 用コマンド（モジュールのインストール後、`access_changed` のある更新の後、および再構成）とインストーラー（`fGrantLogAccess`、`--no-restart`）：各モジュールのログへの読み取り権限。冪等性を保ち、端末なしで root として実行できるようにしてください。 |
| `collector.status`（`mPublishState`）、`<name>.doctor`（`mPublishDoctor`）、`<name>.requirements`（`mCheckRequirements`） | `api_modules.fSummary` と `fOverview`（状態、理由、件数、スイッチのロック）、モジュールのページと1つのモジュールのページ（要件）、概要、設定ページ（ディスクとデータベース）。 |
| `fSummary` の状態と理由 | 4つのロケールファイルのキー `module_state.*` と `module_reason.*`、`modules.js`、`overview.js`、マニュアル。 |
| テーブル `access_tokens`、`logins`、`sessions.method`（[backend/web/webdb.py](../backend/web/webdb.py)。古いデータベースには `lColumns` で追加） | 直接サインイン、`mLoadSession`（第2要素を省略するセッション）、ユーザー › アクセストークン、サインイン履歴。トークンのセッションが管理者に対して有効になってはなりません。 |
| `config.cWebPort`（10443） | `server.py`、`configure.py`（`fCheckPort`、`install.env` に記憶された SIEM アドレス）、Web に表示される設定、アナリストに渡すアクセス URL、SOC（クライアントの SIEM アドレス）。 |
| `/root/webapp-credentials.txt` のブロック（`fEnsureAdmin`、`fConfigureCredentials`） | `--uninstall`（`fRemoveCredentials` は `localSIEM ` で始まるすべてのブロックを削除し、ほかのアプリケーションのブロックは残します）：新しいブロックはすべて、そのように始まる必要があります。 |
| `lUserTabs` / `lAdminTabs`、`lUserSections` / `lModuleSections`（`app.py` と `app.js`）、`ldTabs` | 両方のダッシュボード、そのリダイレクト（サーバーと `fRoute`：ユーザーとモジュールの最初のセクション、モジュールのページの旧 URL）、サブタブ（`admin.js fUserSections`、`modules.js fModuleSections`）、モジュールのページへのリンク（`fCardActions`、«インストール済みモジュールに戻る»、アンインストール）、SOC からのリンク（`/user/dashboard/search/?q=...`）。サーバーとルーターのリストは同じでなければなりません。 |
| アカウントの言語（`users.language`） | `app.js fStart`（ダッシュボードはブラウザーの言語ではなく、この言語で開きます）、サインイン（`fDone` はサインインページの言語をこれに設定します）、タイトルバーの言語セレクター（`fSetLanguage` → `PATCH /api/account`）。 |
| レコードの辞書（`mParse`） | 相関（`correlation`、`fields.client_ip`、`fields.path`）、リクエストカード（`search.js fRecordBlock` とモジュールの `mDisplayRecord`）、FTS（`search`、`raw`）。 |
| イベントの辞書（`mBuildEvent`） | `lEventColumns`、ルール（YAML が読み取るフィールド）、グループ化、検索フィールド（`dTextColumns`、`dNumberColumns`）、CSV エクスポート、`mModuleCounts`。 |
| モジュールが生成するカテゴリとルール名 | 重大度、アラートのルール名（SOC の統計はこれでグループ化するため、変えないでください）、グループ化のキー。 |
| `fGroupKey` / `fExternalId` | SOC での重複排除：これらを変更すると、すでに送信したものが再送されます。 |
| `fBuildAlert` | SOC との契約：`GenericAlert` の制限（rule 300、description 10 000、details 200 キー × 5000 文字）。 |
| `Masker` | プライバシー：保存されるものと SOC に届くもの。 |
| `FileTailer` | 欠落なし・重複なしの保証。初回のオープン時に古い行を読まないこと。アンチフォレンジックの通知。ログを書き込み用に開いてはなりません。`unreadable` 通知の `was_readable` が、読み取れないソースをアラートにするかどうかを決めます（`fNoticeDetection`）。 |
| `query.dFields` | 検索言語、15言語のヘルプ、マニュアル。 |
| 設定の既定値（`config.dDefaults`） | 両方のプロセス。管理パネル（`api_admin`）、`configure.py`。モジュールの設定はここにはなく、各 `module.json` から取得されます。 |
| 設定 `mfa_enabled`（既定では無効） | `Accounts.mLoadSession`（有効にすると、第2要素のないアカウントのパスワードセッションがただちに終了します）、`fLogin`（step done、totp、または enroll）、`/api/auth/session`、設定・ユーザー・アカウントの各ビュー、`manage.py list-users` と `create-user`、`configure.py`（`--enable-mfa` / `--disable-mfa` の場合のみ）。 |
| `frontend/assets/app.css` | SOC と共通の外観：これは SOC のスタイルシートです。localSIEM 専用のルールは `localsiem.css` に記述します。このファイルは、まず SOC の緑のアクセントカラーを PYMEHackers の赤 `#cc3333`（両方のテーマで、アクセントのあるテキストの色でもあります）に置き換え、エラーの赤をアクセントと混同しないよう赤橙色に置き換えます。サインインページは中央のフォームだけのレイアウトにし（サイドパネルもツールバーもなし。サインインフォームはほかのサインインカードの半分の幅で（`.auth-card-narrow`。コードだけを求める場合のコードの手順も同様。QR コードによる設定は全幅のまま）、ボタンの下に言語とテーマ `.auth-preferences` があります）、インストール済みのモジュールはそれぞれ全幅の1行にします（`.module-list` と `.module-card`：モジュールのページのヘッダーと同様に、各部分を縦に並べます。`.module-title` が 24rem の基準幅を取るのは行 `.module-head` の中だけで、列の中では取りません。列の中ではそれが高さになってしまうためです）。新しいバージョンの通知（`.module-update`：更新付きの情報通知。`.module-update-blocked`：新しい localSIEM が必要な場合の控えめな表示）も含め、`app.css` には手を加えません。ロゴは独自のもので（`frontend/assets/img/logo.svg`：3行のログの上に虫眼鏡。2行は対処済みでチェックマーク付き、1行はまだ誰も対処しておらず ! 付き）、SOC の盾ではありません。 |
| インストーラーとユニット | すべてのサーバー：ちょうど1つのアクションを必須とし、`--update` と `--uninstall` は繰り返し実行可能で、GitHub からのパイプ実行が可能（関数、最後に `fMain`、stdin を読むものなし）で、コアだけをインストールする状態を保ってください。 |
| `backend/core/terminal.py` とインストーラーの出力関数（`fSplitOutput`、`fRun`、`fStep`） | `manage.py`、`configure.py`、インストーラーが出力するもの、およびインストールのログ（色コードなし）。`manage.py read-paths`（`fRemoveReadAccess` が読み取ります）と `doctor --json` はプログラム向けに出力するため、マークや色を付けないでください。インストーラーが実行する Python ツールは、出力したものをただちにフラッシュし（`fWrite` がそうします）、`LOCALSIEM_COLOR` に従う必要があります。 |
| `backend/core/channels.py`（`fChannelSettings`、`fBuildMessage`、`ChannelSender`）と設定 `channels` | 管理者が受け取るメッセージ（Telegram）、チャネルタブ（`fChannelsGeneralSection` と `fTelegramSection` は `channels.status` と `settings` を読み取ります）、`api_admin`（`cTokenRegex`、`cChatIdRegex`、`lSeverities`、`lLanguages` による検証）。SOC への配信はこれらに依存しません。失敗したチャネルがアラートを遅らせることはありません。 |

<a id="extensions"></a>
## 7. 拡張ポイント

### モジュールを追加する方法（SSH、Postfix、MariaDB...）

コアは変わりません。コレクターへの登録も、`config.dDefaults` への既定値の追加も不要です。

1. `localSIEM-modules/mod-<name>/` フォルダーを作成し（名前：`[a-z][a-z0-9_]{1,31}`。接頭辞 `mod-` が付くのはリポジトリのフォルダーだけで、`id`、`vName`、設定、URL、オプション、インストール先のフォルダー `/opt/localsiem/modules/<name>/` は `<name>` を使います）、`module.json`（`id`、`version`、`core`、`entry`、`default_enabled`、`read_paths`、`settings`。[コアとモジュール](#architecture) と [backend/core/registry.py](../backend/core/registry.py) のヘッダーを参照）を置きます。
2. `entry` で指定した `Module` のサブクラスを記述します（[backend/core/module.py](../backend/core/module.py)）：id と同じ `vName`（`<name>`）、`mDiscover`（安定した `key` を持つソース。設定は `mModuleSettings()` で読み取ります）、`mCreateFramer`（通常は `LineFramer`）、`mParse`（時刻、相関、parse_status、フィールド、マスク済みの生データを持つレコード）、`mCreateCorrelator`（`mAdd`、`mDue(pNow, pForce, pWatermark)`、`mPendingCount` を持つオブジェクト）、`mBuildEvent`（`action` と `detections` を持つイベントの辞書）、および任意で `mStart`、`mRulesPath`、`mRuleFunctions`、`mEnrich`、`mDoctor`、`mRequirements`、`mHealth`、`mSkipped`、`mSetLowDisk`、`mDisplayRecord`。モジュール自身のファイルは相対インポート（`from .parsers import ...`）し、コアは `backend.core.*` としてインポートします。`__init__.py` は追加しないでください。
3. 15言語（`lLanguages`）のそれぞれについて `locales/<language>.json` を追加します：`name`、`summary`、`settings.<key>.label` / `help`（`records` の場合は `fields`、`add`、`remove`、`empty` も）、`choices`。
4. YAML ルールを `mod-<name>/rules/` に置き、`mRulesPath` からそのフォルダーを返します。
5. そのサービスにとって «実行されたアクション» が何を意味するか（たとえば、fail2ban によって禁止された IP）を決め、それに応じて `action` を設定します。検出を生成するのは、実行されたアクションのないイベントだけです。
6. モジュールがサーバー上のソフトウェア（監視対象のサービス）を必要とする場合は、それを `mDoctor` と同様のチェック（`fix` にそれをインストールするコマンドを含む）として `mRequirements` から返します。ストレージを使わず、何もインストールせず、`/opt/localsiem/` の外にあるものを何も変更しないでください。それがない場合、モジュールは無効の状態でインストールされ、再構成でそれが検出されるまで有効にできません。
7. ログのフォルダーを `read_paths` で宣言し、`manage.py setup-modules`（Web が表示する root 用のコマンドで、インストーラーも更新のたびに実行します）が `localsiem` に読み取り権限を与えられるようにします。サービスのログや、その書き込み方法や形式を変更しないでください。ログはそのまま読み取り、パーサーの方を合わせます。診断はログを説明し、`fix` を示すのはログ以外のものと読み取り権限についてだけです。モジュールが必要とするソフトウェアを Debian と Alpine にインストールするコマンド（1行に1コマンド、シェル演算子なし）を `install_requirements` で宣言し、その注記をロケール（`install_requirements.note` と `install_requirements.<system>`）に記述します。Web はそれらをモジュール › インストール可能 › 要件に表示しますが、実行することはありません。
8. `localSIEM-modules` リポジトリ（フォルダー `mod-<name>/`）で公開します。インストールされていない間はモジュール › インストール可能に表示され、それがインストールする唯一の方法です（開発用のコピーでは、フォルダーを `/opt/localsiem/modules/<name>/` にコピーし、`localsiem` と `localsiem-web` を再起動することもできます）。新しいバージョンを公開するには、`module.json` の `version` を上げます。モジュール › インストール済みは、それを更新付きで提示します（`core` もインストール済みの localSIEM より上に上げた場合は、必要な localSIEM だけを示します）。新しいバージョンで `read_paths` が変わる場合、Web は更新後に root 用のコマンドを再び表示します。

### モジュールに設定を追加する方法

`module.json` の `settings` に（型と既定値を付けて）追加し、そのラベルとヘルプをロケールファイルに追加します。`mModuleSettings()` で読み取ります。Web がフィールドを作成し、`fValidateSettings` が検証し、コレクターは次のリロード時にただちに適用します。

### ルールを追加する方法

モジュールの `rules/` フォルダーに YAML ファイルを作成します（すべてのキーと演算子については、[backend/core/rules.py](../backend/core/rules.py) のヘッダーを参照してください）。例：

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

コレクターは、次回の起動時または設定のリロード時にこれを読み込みます。その後、ルールはモジュールのページ（管理 › モジュール › インストール済み › 構成）のルール表に表示され、そこで無効にしたり、重大度、しきい値、ウィンドウを調整したりできます（上書きは `settings.json` の `rules.<id>` に保存されます）。ファイル内の `enabled: false` で、既定で無効にできます。コードが必要な条件には、モジュールの `mRuleFunctions` が返す関数を指定した `{function: name}` を使います。

### 検索フィールドを追加する方法

[backend/core/query.py](../backend/core/query.py) の `dFields` と、[backend/core/storage_sqlite.py](../backend/core/storage_sqlite.py) の `fCompileField` にある `dTextColumns` / `dNumberColumns`（または特別なケース）に追加します。新しい列には、スキーマ、`lEventColumns`、インデックスも必要です。ヘルプ（4つのロケールファイルの `help.fields`）とマニュアルに記載してください。

### API エンドポイントまたはダッシュボードのタブを追加する方法

エンドポイントは、その領域の `fRegister*` 関数の中で `/api/` の下に置きます（Swagger が文書化します）。タブには、`lUserTabs` と `lAdminTabs` の一方または両方のルート（[backend/web/app.py](../backend/web/app.py)）、`ldTabs` のエントリ（[frontend/assets/app.js](../frontend/assets/app.js)。`group`、`adminGroup`、`adminOnly`）、`window.LocalsiemViews` のビュー（新しいスクリプトは `frontend/index.html` に追加する必要があります）、4つのロケールファイルのテキスト（`nav.<tab>` とビューのキー）が必要です。ユーザーやモジュールのようにセクションを持つタブには、さらに `app.py` と `app.js` のセクションのリスト（`lUserSections`、`lChannelSections`、`lModuleSections`）、`fAdminTab` での最初のセクションへのリダイレクト、セクションのルート（`fAdminUsersSection`、`fAdminChannelsSection`、`fAdminModulesSection`）、`fRoute` でのケース、ビュー内のサブタブ（`fUserSections`、`fChannelSections`、`fModuleSections`）が必要です。

### チャネルを追加する方法（メール、Slack...）

[backend/core/channels.py](../backend/core/channels.py) で、`lChannels` にその名前を、`dDefaults["channels"]` にそのブロックを追加し（[backend/core/config.py](../backend/core/config.py)。シークレットは `settings.json` ではなく、`config/` 内の専用ファイル（モード 600）に保存します）、`fChannelSettings`、`ChannelSender.mConfigured`、`ChannelSender.mDeliver` にそのケースを追加します（`TelegramClient` のようなクライアントで、そのエラーにシークレットが含まれることはありません）。次に、`api_admin.py` にその API（`fSaveTelegram` と `fTestTelegram` のようなもの）、`app.py`、`app.js`、`admin.js` の `lChannelSections` にそのセクションとビュー（`fTelegramSection` のようなもの）、4つのロケールファイルにテキスト `channels.section_<name>` とそのビューのテキスト、そしてマニュアルにその部分を追加します。全般セクションは、それを自動的に一覧表示します（`GET /api/admin/channels` の `channels`）。

<a id="resources"></a>
## 8. 計測したリソース使用量

Apache モジュールを使用した Debian 13 サーバー（mod_security2 2.9.11、CRS 3.3.7）で、ユニットの systemd の制限（`MemoryMax` 300M / 200M、`CPUQuota` 50 %、`Nice` 10、アイドル I/O）の下で計測しました：

| 状況 | コレクター（RSS） | Web（RSS） | 合計 |
|---|---|---|---|
| アイドル、起動後 | ≈ 28 MB | ≈ 26–55 MB | ≈ 55–80 MB |
| 約60秒間に30 000件のリクエストが集中し、**そのすべて** に監査レコードがある場合（パート K のため、監査ログは ≈ 1.8 GB） | ピーク ≈ 160 MB | ≈ 40 MB | ピーク ≈ 200 MB |
| 集中の後 | ≈ 70 MB | ≈ 26–40 MB | ≈ 100 MB |

この集中の間、コレクターは最後のリクエストの約40秒後に追いつき、リクエストごとにちょうど1つのイベントを保存し（30 000件中30 000件、すべて3つのソース付き）、数千件ではなく3つのアラートグループを送信しました。Alpine 3.24 のアイドル時：コレクター ≈ 26 MB、Web ≈ 54 MB。

ディスク：一致のないリクエストでは1件あたり約 0.8 KB（アクセスログの行、イベント、インデックス）、監査レコードと error.log の ModSecurity の行が複数あるリクエストでは1件あたり約 10–13 KB です。1日に数万件のリクエストがあり、そのうち数パーセントが監査される典型的な PYME のサイトでは、90日間の保持期間中も既定の最大サイズ（ディスクの 15% と 10 GB のうち小さい方）に十分収まります。最大サイズに達すると、古いイベントから順に削除されます。
