# AI Usage Monitor

AI Usage Monitor is an independent macOS menu bar app and desktop widget that
shows the usage limits reported by the locally installed Codex app-server. It
is distributed as source code so each user can inspect, build, sign, and
install it on their own Mac.

<p align="center">
  <img src="docs/assets/ai-usage-monitor.png" alt="AI Usage Monitor showing banked resets and weekly usage in dark appearance" width="394">
</p>

## Codexでインストール（推奨）

> [!TIP]
> **下のプロンプトをCodexへ貼り付けると、ソースの取得、テスト、ビルド、
> アプリの配置、ウィジェットの確認まで任せられます。**

1. このGitHubリポジトリのHTTPS URLをコピーします。
2. インストール先のMacでChatGPTデスクトップアプリを開き、Codexの
   [ローカル環境](https://developers.openai.com/ja-JP/docs/environments/local-environment)
   で新しいタスクを開始します。クラウド環境や別のMac上のタスクでは、対象Macへ
   アプリを配置したりウィジェットを登録したりできません。
3. 次のプロンプト全体をそのままCodexへ送ります。

```text
以下のGitHubリポジトリから AI Usage Monitor を、このMacへインストールしてください。

リポジトリURL: https://github.com/TikTak007/ai-usage-monitor-macos-widget

説明や手順の提示だけで終わらず、安全を確認しながらローカルMacへの導入完了まで進めてください。

1. 最初にリポジトリの README.md、SECURITY.md、scripts/build_app.sh を読み、記載内容と実行する処理を確認してください。
2. macOS 13以降であることと、git、xcodebuild、swift、Codexの app-server が利用できることを確認してください。不足があれば勝手に別のソフトを導入せず、そこで止めて必要事項を報告してください。
3. ソースは ~/Developer/AIUsageMonitor に配置してください。存在しなければcloneし、すでに存在する場合は同じリポジトリか、未保存の変更がないかを確認してください。別のフォルダの上書き、reset、stash、既存変更の破棄はしないでください。
4. ~/.codex/auth.json を含む認証情報やトークンのファイルは、開く、読み取る、表示する、コピーする、変更する、のいずれも行わないでください。sudoの使用、Gatekeeperの無効化、macOSのセキュリティ設定の緩和も行わないでください。
5. `python3 -m unittest discover -s tests` と `swift test` を実行してください。失敗を隠したりスキップしたりせず、失敗した場合はインストールを止め、原因と次の対応を報告してください。
6. このMacのキーチェーンに既存の Apple Development 署名IDが利用可能か、秘密情報を表示せずに確認してください。利用できる場合はそのIDを CODE_SIGN_IDENTITY に指定し、利用できない場合は scripts/build_app.sh のad-hoc署名を使用してください。後者ではアプリは動作しても、macOSがウィジェットを検出しない場合があることを報告してください。
7. scripts/build_app.sh でリリース版をビルドし、生成されたアプリ本体と内蔵ウィジェットの署名、およびbundle identifierを検証してください。
8. 生成された「AI Usage Monitor.app」を ~/Applications へ配置してください。既存版がある場合は、このアプリだけを終了し、日時入りのバックアップを作ってから置き換えてください。他のアプリやファイルには変更を加えないでください。
9. アプリを一度起動し、メニューバー項目が起動することを確認してください。macOSがウィジェットをまだ検出していない場合に限り、内蔵されたAI Usage Monitorのウィジェット拡張だけを再登録または再認識させてください。
10. 最後に、ソースの配置先、アプリの配置先、テスト結果、署名方式、メニューバーアプリとウィジェットの確認結果、残っている手動操作を日本語で報告してください。ウィジェットが利用可能なら「デスクトップを右クリック → ウィジェットを編集 → AI Usage Monitorを検索 → サイズを選んで追加」の手順も案内してください。

作業はこのMac内だけで完結させてください。fork、push、公開、リリース作成、外部サービスへの診断情報送信は行わないでください。
```

> [!IMPORTANT]
> AI Usage Monitor is an unofficial community project. It is not affiliated
> with, sponsored by, or endorsed by OpenAI. Codex, ChatGPT, and OpenAI are
> trademarks of OpenAI. This repository does not include OpenAI logos or
> official product icons.

“AI Usage Monitor” is a generic descriptive project name, not a claim of an
exclusive brand. Identify this build by its repository URL when comparing it
with similarly named projects.

## Features

- Displays every usage bucket returned by the local Codex app-server.
- Shows remaining and used percentages, reset time, and a live countdown.
- Shows all available banked resets and each known expiration date.
- Estimates consumption pace with a lightweight reset-safe rolling model.
- Provides small and medium WidgetKit widgets.
- Supports System, Light, and Dark appearance modes.
- Refreshes automatically every three minutes and on demand.
- Sends optional notifications at each newly crossed 10% boundary.
- Keeps the last successful snapshot visible if a later refresh fails.

AI Usage Monitor never redeems a banked reset and does not attempt to bypass or
alter usage limits.

## Requirements

- macOS 13 or later
- Xcode with the macOS platform installed
- Git and Swift (included with Xcode)
- the Codex desktop app, ChatGPT desktop app with a compatible Codex binary,
  or a `codex` executable that supports `app-server`
- an existing ChatGPT sign-in managed by Codex

No API key is required. AI Usage Monitor does not read `~/.codex/auth.json` or
receive an access token.

## Manual build and install

```sh
git clone https://github.com/TikTak007/ai-usage-monitor-macos-widget AIUsageMonitor
cd AIUsageMonitor
python3 -m unittest discover -s tests
swift test
scripts/build_app.sh
mkdir -p "$HOME/Applications"
/usr/bin/ditto "dist/AI Usage Monitor.app" "$HOME/Applications/AI Usage Monitor.app"
open "$HOME/Applications/AI Usage Monitor.app"
```

The default build uses local ad-hoc signing. That is sufficient for the menu
bar app, but macOS may not list an ad-hoc-signed WidgetKit extension. If you
have an Apple Development certificate, rebuild with its exact Keychain name:

```sh
CODE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build_app.sh
```

Then replace the installed app and launch it once. To add the desktop widget,
right-click the desktop, choose **Edit Widgets**, search for **AI Usage
Monitor**, and add the small or medium widget.

## Update

From the source directory:

```sh
git pull --ff-only
python3 -m unittest discover -s tests
swift test
scripts/build_app.sh
```

Quit AI Usage Monitor, preserve the installed copy if you want a rollback,
replace it with `dist/AI Usage Monitor.app`, and open it again.

## Uninstall

Quit AI Usage Monitor and move `~/Applications/AI Usage Monitor.app` to the
Trash. You can then remove the widget from the desktop and delete the cloned
source directory. The app does not install a daemon or privileged helper.

## How it works

```text
Menu bar UI -> local Codex app-server -> usage-limit response
     |
     +-> normalized snapshot on 127.0.0.1 -> WidgetKit extension
```

The widget bridge binds only to IPv4 loopback (`127.0.0.1`). It shares a
normalized snapshot containing limit names, percentages, reset times, banked
reset summaries, connection state, and update time. It does not share account
details, credentials, or the raw app-server response.

Pace estimation stores at most 64 small samples per bucket in local user
defaults. It combines a short rolling rate with a time-weighted longer rate.
A quota reset increases the monotonic consumption counter instead of creating
a negative rate, while a small downward backend correction adds no
consumption. Estimates are hidden until there is enough history and whenever
the predicted exhaustion would occur after the quota reset.

## Diagnostics

The included Python diagnostic uses only the standard library:

```sh
python3 run_poc.py
python3 run_poc.py --json
python3 run_poc.py --describe-response
```

It intentionally omits raw account data and credentials. Avoid posting
diagnostic output publicly unless you have reviewed it.

## Development

Run all tests:

```sh
python3 -m unittest discover -s tests
swift test
```

Build the app and embedded widget:

```sh
scripts/build_app.sh
```

The app-server protocol is provided by the user's installed Codex binary and
may change independently of this project. Unknown positive quota durations are
displayed with neutral labels rather than being forced into fixed five-hour or
weekly categories.

## Privacy and security

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md). In summary:

- no analytics, telemetry, advertising, or remote service is added by AI Usage
  Monitor;
- Codex remains responsible for authentication and token refresh;
- credentials are never intentionally read, copied, logged, or persisted;
- the widget receives normalized data only over local loopback; and
- the app does not redeem resets or modify account settings.

## Trademark notice

AI Usage Monitor uses a generic descriptive name and an independently drawn icon.
References to Codex, ChatGPT, and OpenAI describe compatibility only. Their
names and trademarks belong to OpenAI. See the current
[OpenAI design guidelines](https://openai.com/brand/).

## License

Source code is available under the [MIT License](LICENSE). Third-party product
names and trademarks are not licensed under the MIT License.
