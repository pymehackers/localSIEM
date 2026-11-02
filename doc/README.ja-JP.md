# localSIEM

この README は次の言語でもご覧いただけます：\
[de-DE](README.de-DE.md), [en-GB](README.en-GB.md), [en-US](../README.md), [es-AR](README.es-AR.md), [es-ES](README.es-ES.md), [fr-FR](README.fr-FR.md), [he-IL](README.he-IL.md), [hi-IN](README.hi-IN.md), [it-IT](README.it-IT.md), ja-JP, [ko-KR](README.ko-KR.md), [pt-BR](README.pt-BR.md), [pt-PT](README.pt-PT.md), [ru-RU](README.ru-RU.md), [zh-CN](README.zh-CN.md)

## 概要

保護対象と同じ PC/サーバー上で動作する、軽量でモジュール式の SIEM です。Alpine と Debian に対応しています（現時点）。

## モジュール

サーバーの各サービスはモジュールが監視します。モジュールは、そのサービスのログの場所、その読み方、適用するルールを localSIEM に教えます。モジュールは Web 画面からインストール、更新、アンインストールでき、Web 画面が [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules) リポジトリからダウンロードします。現在、モジュールは 2 つあります：

- **apache2**（Apache + ModSecurity）：各リクエストのアクセスログ、エラーログ、ModSecurity の監査ログを結び付けます。
- **privesc**（権限昇格）：サーバー上で実行されるものを監視し、root への昇格の各段階を警告します。

モジュールはサーバーに何もインストールしません。必要なものが足りない場合は、何をインストールすべきかを示し、それが揃うまで無効のままです。

## スクリーンショット

![localSIEM の概要](https://raw.githubusercontent.com/PYMEHackers/localSIEM/main/doc/screenshot.png)

## インストール

`root` として実行してください。

**Debian 13**：

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-debian.sh | bash -s -- --install --allow-from 203.0.113.10
```

**Alpine Linux 3.24**：

```bash
apk add bash curl && curl -fsSL -H 'Accept: application/vnd.github.raw+json' https://api.github.com/repos/PYMEHackers/localSIEM/contents/deploy/install-update-reinstall-alpine.sh | bash -s -- --install --allow-from 203.0.113.10
```

`--allow-from`：Web 画面（`https://<server>:10443`）を開くことを許可する IP。

## ドキュメントを読む

詳しくは次をご覧ください：

- [doc/MANUAL.ja-JP.md](MANUAL.ja-JP.md)：インストール、設定、使い方を説明します。
- [doc/CODE.ja-JP.md](CODE.ja-JP.md)：仕組みを説明します（開発者と AI モデル向け）。
- [localSIEM-modules](https://github.com/PYMEHackers/localSIEM-modules)：モジュールとそのドキュメント。
