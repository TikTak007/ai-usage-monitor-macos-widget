# 更新履歴

2026年9月20日のソースコード公開以降、公開リポジトリの`main`に反映した主な変更です。
日付は`main`への反映日です。バージョン番号を付けた配布版はまだないため、日付順に記録します。

## 2026-09-28

- メニューバー画面の内容が縮んだ後に残る、上下の透明な余白を修正しました。画面を閉じている間に内容が変わった場合も、高さを合わせて表示します。([#13](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/13))

## 2026-09-27

- 週間残量の履歴と使い切り予測をグラフで表示し、リセットを確認したときの通知を追加しました。([#2](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/2))
- リセット直後も、週間グラフの横軸が常に7日間を示すよう修正しました。([#4](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/4))
- 7日間の残量グラフを、小・中・大サイズのデスクトップウィジェットに追加しました。([#5](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/5))
- ウィジェットの登録とアイコン表示を改善しました。([#6](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/6)、[#7](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/7)、[#8](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/8))
- メニューとグラフウィジェットの重複表示や配置を見直し、残量の円グラフの色を統一しました。グラフ上の残量ラベルが線や上下の端と重ならないよう調整しました。([#9](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/9)、[#10](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/10)、[#12](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/12))
- READMEの機能説明を日本語で整理し、ライト・ダーク両方の画面例を掲載しました。([#3](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/3)、[#10](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/10)、[#11](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/11))

## 2026-09-26

- ChatGPTアプリ内のCodex実行ファイルの配置変更に対応しました。([#1](https://github.com/TikTak007/ai-usage-monitor-macos-widget/pull/1))

## 2026-09-20

- メニューバーアプリとデスクトップウィジェットのソースコードを[初めて公開](https://github.com/TikTak007/ai-usage-monitor-macos-widget/commit/ad705b5)しました。
- [READMEを日本語化](https://github.com/TikTak007/ai-usage-monitor-macos-widget/commit/9203eaa)し、[ライト・ダークの画面例](https://github.com/TikTak007/ai-usage-monitor-macos-widget/commit/e124dc5)を掲載しました。
