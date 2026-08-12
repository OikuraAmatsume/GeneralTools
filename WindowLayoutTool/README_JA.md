# ウインドウレイアウトツール（macOS）

Swift / AppKit / Core Graphics / macOS Accessibility API だけで実装した、完全ローカル動作のメニューバーアプリです。通常のメインウインドウ、Dock アイコン、Command-Tab の項目は表示しません。ほかのアプリの調整可能なウインドウをドラッグすると、レイアウトバーが現在のディスプレイの可視領域における下から約 1/3 の高さへ中央表示されます。任意の区画へポインタを移動して離すと、そのウインドウだけを配置します。

## 動作環境と構成

- macOS 13 以降
- Swift、AppKit、Core Graphics、Accessibility API
- `LSUIElement = true`、`NSStatusItem`、再利用する 1 枚の nonactivating `NSPanel`
- `AXUIElementCopyElementAtPosition` と書き込み可能な AXPosition / AXSize を使用
- ログイン時起動は公開 API の `SMAppService.mainApp`
- サードパーティ依存、WebView、JavaScript ランタイム、helper/XPC、サーバーなし
- App Sandbox は無効、Hardened Runtime は有効

Accessibility アプリが公開 API で他プロセスのウインドウを操作するには App Sandbox の制約が適さないため、意図的に Sandbox を無効にしています。プロセス注入、プライベート API、入力イベントの改変・再送は行いません。

## 使い方と権限

1. アプリを `/Applications` に置いて起動します。
2. システム設定 → プライバシーとセキュリティ → アクセシビリティで許可します。
3. 他アプリの通常ウインドウのタイトルバー、サイズ変更可能な辺または角をドラッグします。
4. ポインタが 7 pt 以上移動し、AX 上の位置またはサイズが実際に変わった時だけレイアウトバーが表示されます。通常のクリックでは表示されません。
5. 白い区画に移動すると青く選択され、マウスを離すと配置されます。区画外で離すか Escape を押すとキャンセルします。

メニューには、有効化/一時停止、ログイン時に開く、レイアウト機能、Accessibility 権限状態、権限要求、システム設定を開く、情報、終了があります。開発ビルドや `/Applications` 外のアプリでは、ログイン項目のシステム承認が必要になる場合があります。

入力監視は `NSEvent.addGlobalMonitorForEvents` による受動監視です。CGEventTap は既定で使用せず、イベントを横取り・再送しません。Escape のグローバル監視には、このアプリの本来の Accessibility 許可を使用するため、通常は別の入力監視権限は不要です。

## レイアウト

- メイン + 右上下：左 65%、右上 35% × 50%、右下 35% × 50%
- 左右均等：50% / 50%
- 最大化：現在の `visibleFrame` 全体（macOS のフルスクリーンにはしません）
- Large Left：65% / 35%

サムネイル内の各区画を個別に選択できます。他のウインドウは動かしません。モデルは 0〜1 の正規化座標なので、3 分割、4 分割、上下分割、間隔設定を追加しやすい構成です。

## 実装

状態遷移は次のとおりです。

`Idle → PotentialDrag → ActiveDrag → HoveringLayout → Commit/Cancel → Idle`

- mouseDown ごとに一度だけ最前面の AX ウインドウを解決し、ドラッグ中だけ参照と初期 frame を保持します。
- `AXWindow/AXStandardWindow` 以外、自アプリ、Dock、メニューバー、通知、最小化、ネイティブフルスクリーン、Sheet/Popover/ダイアログ、固定サイズ、書き込み不可のウインドウは除外します。
- Hover 更新は最大 30 Hz。アイドル時の Timer、DisplayLink、継続的なウインドウ列挙はありません。
- ActiveDrag 中だけ 0.5 秒間隔（tolerance 0.15 秒）の watchdog を動かし、左ボタン状態と 60 秒上限を確認します。
- 権限取り消し、ウインドウ終了、AX エラー、Space 変更、スリープ/復帰、ディスプレイ構成変更時は必ずキャンセルしてパネルを消します。
- mouseUp で選択位置と AX 書き込み可否を再検証します。設定後の確認は 1 回だけで、アプリ独自の最小サイズや最終 frame を受け入れます。
- `NSScreen.visibleFrame` に正規化レイアウトを写像するため、Dock の左/右/下および自動非表示に対応します。
- 主ディスプレイ上端を基準に AppKit と AX の座標を相互変換し、左・右・上に置いた負座標の外部ディスプレイにも対応します。
- 「視差効果を減らす」と「透明度を下げる」に従います。

## ビルドとテスト

### スタンドアロンアプリを直接使う

Xcode をインストールしたり開いたりする必要はありません。

- `dist/WindowLayoutTool.app`：Apple Silicon / Intel 対応の実行可能な通常の macOS アプリ。
- `dist/WindowLayoutTool.dmg`：開いて Applications へドラッグしてインストール。

これは Xcode プラグインではなく、標準の `APPL` 実行アプリです。`LSUIElement = true` のメニューバーアプリなので、起動後に Dock アイコンや通常ウインドウは表示されず、メニューバーにレイアウトアイコンだけが表示されます。dist 版は Hardened Runtime 付きのローカル一時署名です。別の Mac へ配布する場合は、文末の Developer ID 署名と Apple 公証を行ってください。

### ソースからビルド

Xcode で [`WindowLayoutTool.xcodeproj`](WindowLayoutTool.xcodeproj/) を開くか、次を実行します。

```bash
# Debug
xcodebuild -project WindowLayoutTool.xcodeproj \
  -scheme WindowLayoutTool -configuration Debug \
  -derivedDataPath /tmp/WindowLayoutToolDebugDerived build

# Release
xcodebuild -project WindowLayoutTool.xcodeproj \
  -scheme WindowLayoutTool -configuration Release \
  -derivedDataPath /tmp/WindowLayoutToolReleaseDerived build

# XCTest
xcodebuild -project WindowLayoutTool.xcodeproj \
  -scheme WindowLayoutTool -configuration Debug \
  -derivedDataPath /tmp/WindowLayoutToolDerived \
  CODE_SIGNING_ALLOWED=NO test
```

証明書がない場合、コンパイルだけなら `CODE_SIGNING_ALLOWED=NO`、ローカル実行用の一時署名なら `CODE_SIGN_IDENTITY=-` を追加できます。ビルド場所や署名が変わると macOS が別の Accessibility クライアントとして扱うことがあるため、再許可してください。

## オフライン動作とプライバシー

- URLSession、Network.framework、WebSocket、ネットワーククライアントを使用しません。
- テレメトリ、広告、リモート設定、オンラインクラッシュ報告、自動更新はありません。
- ウインドウ名、内容、アプリ名、操作履歴を送信・保存しません。
- スクリーンショット/OCR は行わず、画面収録、カメラ、マイク、フォルダ、ネットワーク権限を要求しません。
- AX 情報はドラッグ中だけメモリに保持し、終了時に解放します。
- 設定保存はローカル UserDefaults の「有効/一時停止」と「レイアウト機能」だけです。
- 独自の診断ログはなく、`PrivacyInfo.xcprivacy` は追跡・データ収集なしを宣言します。

## 2026-08-10 の実測結果

環境：Apple Silicon M4、macOS 26.5、Xcode 26.6、Swift 6.3.3。アプリの deployment target は macOS 13.0 です。

- Debug / Release build：成功。
- Xcode Analyze：成功。
- XCTest：18 件成功、失敗 0。正規化レイアウト、Dock 下/左/右の visibleFrame、オーバーレイの 1/3 高さ配置と拡大サイズ、負座標と上方ディスプレイ、AppKit/AX 変換、全区画の hit test、成功・通常キャンセル・Escape・異常復旧・不正遷移を検証。
- plist / entitlements / Privacy manifest：`plutil` 成功。
- ローカル一時署名：`codesign --verify --deep --strict` 成功。`adhoc,runtime` flags を確認。Developer ID 署名と公証は未実施。
- Release 実行：正常に常駐し、7 秒間の実行ログは 0 byte。
- DMG スクリプト：143,751 byte の UDZO/zlib 読み取り専用テストイメージを実際に作成し、`hdiutil imageinfo` で確認。
- アイドル CPU：1 秒ごとの 5 回の `ps` 測定はいずれも 0.0%。
- メモリ：RSS 52.6〜52.7 MB（共有マッピングを含む）、`footprint` の phys_footprint と peak は 14 MB。
- ネットワーク：実行中の `lsof -nP -a -p <pid> -i` はネットワークソケットを返しませんでした。
- ソース検査：URLSession、Network.framework、WebSocket、Sparkle、Sentry、Firebase、telemetry、analytics は検出されませんでした。plist の Apple DTD 文字列だけが `http://` を含みますが通信はしません。

Finder、Safari、Chrome、Xcode、Electron/Cursor はこの Mac にあり、Microsoft Office はありません。Accessibility の許可はセキュリティ設定なので自動操作で有効にしておらず、実ウインドウのドラッグ、複数ディスプレイ、Space、表示倍率、物理的なオフライン環境は「未検証」です。ウインドウを持たない LSUIElement プロセスは今回の `computer-use` では読み取りがタイムアウトしました。未実施項目を成功扱いにはしていません。

リリース前に、Finder/Safari/Chrome/Electron/Xcode、Office がある場合は Office、単一/複数ディスプレイ、左/右/上配置、異なる倍率、Dock の全位置と自動非表示、Space、ネイティブフルスクリーン補助表示、ディスプレイ切断、スリープ復帰、権限取り消し、ウインドウ終了、Escape、mouseUp 欠落、完全オフラインを手動確認してください。

## 既知の制限

- AXPosition/AXSize を公開しないアプリ、非標準ロール、固定サイズ、独自の最小サイズを持つアプリがあります。安全にキャンセルするか、アプリの最終サイズを受け入れ、プライベート API では回避しません。
- ネイティブフルスクリーン、最小化、Sheet、Popover、システムダイアログは対象外です。
- 未署名ビルドのパスや署名変更により Accessibility の再許可が必要になる場合があります。
- 企業ポリシーでグローバルキー監視が禁止されると Escape が届かない場合がありますが、mouseUp、システム通知、watchdog でパネルを後片付けします。
- カスタムレイアウト編集と区画間隔は未実装です。
- SMAppService のログイン項目は `/Applications` 外の開発ビルドで承認が必要な場合があります。

## Developer ID 署名、公証、DMG

1. Xcode で Developer ID Application の Team を選び、Hardened Runtime を有効、App Sandbox を無効のままにします。
2. Release archive を作成し、Organizer の “Developer ID” または `method = developer-id` の ExportOptions.plist で書き出します。
3. `codesign --verify --deep --strict --verbose=2 dist/WindowLayoutTool.app` で検証します。
4. システム標準ツールだけを使う DMG スクリプトを実行します。

```bash
chmod +x Scripts/create_dmg.sh
Scripts/create_dmg.sh dist/WindowLayoutTool.app dist/WindowLayoutTool.dmg
```

5. DMG を Developer ID Application で署名し、公証・staple します。

```bash
codesign --force --timestamp \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  dist/WindowLayoutTool.dmg

xcrun notarytool submit dist/WindowLayoutTool.dmg \
  --keychain-profile "notary-profile" --wait
xcrun stapler staple dist/WindowLayoutTool.dmg
xcrun stapler validate dist/WindowLayoutTool.dmg
spctl --assess --type open --context context:primary-signature -v dist/WindowLayoutTool.dmg
```

公証情報は `xcrun notarytool store-credentials` で Keychain に保存し、パスワードや秘密鍵をリポジトリへ入れないでください。リリース前に、未許可のクリーンな macOS 13+ 環境で Gatekeeper、初回 Accessibility 許可、ログイン項目、配置動作を確認してください。
