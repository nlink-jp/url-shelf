# RFP: url-shelf

> Generated: 2026-07-26
> Status: Draft（実装により 2 点改訂。末尾の「実装による改訂」を参照）

## 1. Problem Statement

ブラウザのブックマークは、ブラウザごとに分断され、プロファイルやアカウントに紐付き、
エクスポートしないと外に出せない。結果として「よく開くサイトの一覧」がブラウザという
実装に人質に取られる。url-shelf は、URL のメモをファイルシステム上の `.webloc` ファイル群
として保持し、フォルダ構成をそのまま分類ツリーとして扱う。メニューバーから階層をたどって
サイトを選ぶと、設定されたブラウザで開く。エントリごとに「プライベートウィンドウで開く」を
指定でき、調査対象 URL を通常セッションから隔離できる。記録の実体は Finder でも扱える
標準ファイルなので、ツールを捨てても資産は残る。想定利用者は開発者・セキュリティ実務者
（当面は作者自身）。

## 2. Functional Specification

### Commands / API Surface

GUI 単独（CLI サブコマンドは同居させない）。操作面はすべてメニューバーと設定ウィンドウ。

**メニューバー**

- ルートフォルダ以下のツリーをそのままメニュー階層として表示。フォルダ = サブメニュー、
  `.webloc` = 項目
- メニューを開いた瞬間にツリーを再スキャンして構築する（FSEvents 監視は行わない）。
  常に最新であり、かつアプリ側に同期状態を持たない
- 深い階層はサブメニューを開いたときに遅延展開する
- 通常クリック = 解決されたモードで開く
- **Option キー押下 = 通常⇄プライベートを反転**（alternate item で表示も切り替える）
- プライベート用ブラウザが未設定・未インストールの場合、プライベート指定の項目は
  **disabled** にする。通常モードへ無言でフォールバックしない
- 固定項目（メニュー末尾）: 「URL を追加…」「ルートを Finder で開く」「設定…」
  「バージョン表示 / About」「終了」

**エントリの追加**

1. メニューバーアイコンへの URL ドラッグ&ドロップ → 受け皿フォルダに `.webloc` を生成
2. 設定ウィンドウの追加フォーム（URL / 表示名 / 配置フォルダ / プライベート可否 /
   ブラウザ指定）

**設定ウィンドウ**

- ルートフォルダの選択（NSOpenPanel）
- 通常 URL の開き方: システム既定ブラウザ / インストール済みブラウザから明示指定
- プライベート URL の開き方: プライベート起動に対応したインストール済みブラウザから選択
- 対応ブラウザが 1 つも無い場合はその旨を明示する
- ログイン時の自動起動トグル（SMAppService）
- バージョン表示

### Input / Output

**データモデル（canonical = ファイルシステム）**

```
~/Documents/URL Shelf/          ← ルート（単一・NSOpenPanel で選択）
├── .url-shelf.toml             ← このフォルダ以下の既定値（省略可）
├── 仕事/
│   ├── 01_社内Wiki.webloc
│   └── 経費.webloc
└── 調査/
    ├── .url-shelf.toml         ← open = "private" / browser = "org.mozilla.firefox"
    └── 検体サイト.webloc
```

- エントリ = `.webloc`（plist）。表示名 = ファイル名から拡張子と並び順プレフィックス
  （`01_` のような数字＋区切り）を除いたもの
- 読み込みはバイナリ / XML plist の両対応。**書き戻しは XML plist** とし、grep / diff /
  手編集が効く状態を保つ
- 独自キーは逆 DNS 名前空間を使う

```xml
<key>URL</key>                  <string>https://example.com</string>
<key>jp.ne.nlink.open</key>     <string>private</string>
<key>jp.ne.nlink.browser</key>  <string>org.mozilla.firefox</string>
```

`URL` キーは無傷なので、Finder でダブルクリックすれば従来どおり既定ブラウザで開く
（その場合はプライベート指定が効かず通常モードになる、という degradation を許容する）。

**メタデータ解決順**

```
エントリの独自キー > 最も近い親フォルダの .url-shelf.toml > グローバル設定
```

フォルダ既定値は下位に継承される。「`調査/` 配下は既定で Firefox のプライベート」を
1 ファイルで表現できる。

**ブラウザ識別子**

全レイヤで **bundle ID** を canonical に保存する（表示のみ人間可読な名前に変換）。
ブラウザのリネームやローカライズで壊れないため。

### Configuration

`~/.config/url-shelf/config.toml`

```toml
[shelf]
root    = "~/Documents/URL Shelf"
inbox   = ""                      # D&D の受け皿。空ならルート直下

[browser]
normal  = "default"               # "default" = システム既定 / または bundle ID
private = "org.mozilla.firefox"   # プライベート起動対応ブラウザのみ選択可
```

フォルダ既定値 `.url-shelf.toml`（各フォルダに任意で置ける）

```toml
open    = "private"               # "normal" | "private"
browser = "org.mozilla.firefox"
```

### External Dependencies

なし。ネットワーク通信を一切行わない。外部 API・認証情報・クラウドサービスに依存しない。

**ブラウザ対応表**（インストール済みのものだけ設定 UI に列挙する）

| bundle ID | プライベート起動フラグ | 実測 |
|---|---|---|
| `org.mozilla.firefox` | `-private-window`（**ハイフン 1 個**） | 起動中インスタンスで確認 |
| `com.google.Chrome` | `--incognito` | コールド・起動中とも確認 |
| `com.microsoft.edgemac` | `--inprivate` | コールド・起動中とも確認 |
| `com.apple.Safari` | 非対応（通常モードのみ） | — |

Firefox だけ Mozilla 形式の単一ハイフンである点は実測に基づく（後述の spike 結果）。
GNU 形式の `--private-window` は**黙って無視され通常ウィンドウで開く**ため、対応表は
「Chromium 系は `--`、Firefox は `-`」という差をそのまま保持する。Brave / Vivaldi など
他の Chromium 系は、この表に 1 行追加するだけで対応できる構造にする。

**起動方式**: `NSWorkspace.OpenConfiguration.createsNewApplicationInstance` は
**常に true**（`open -na` 相当）。false ではフラグが届かず、URL が最前面のウィンドウに
紛れ込むか、何も起きない。

## 3. Design Decisions

**言語 / フレームワーク**: Swift / SwiftUI + AppKit、darwin/arm64 専用、macOS 13+。
既存のメニューバー常駐アプリ（share-mounter / quick-translate / active-lens-gui）と
同じ骨格を踏襲する。SPM 単一 executable ターゲット、`make build` で `dist/` 出力、
非サンドボックス Developer ID 署名。

**メタデータの置き場所**: `.webloc` の plist に逆 DNS 独自キーを追加する方式を採用。
検討した代替案と却下理由:

| 案 | 却下理由 |
|---|---|
| xattr（拡張属性） | zip・クラウド同期・転送で消える。不可視でデバッグ不能 |
| フォルダごとの sidecar ファイルにエントリ単位で記録 | ファイル名で結合するためリネーム・移動で壊れる |
| ファイル名規約（`Foo [private].webloc`） | 可搬性・可視性は最良だが表示名を汚し、キーが増えると破綻する |
| `Private/` フォルダで表現 | 話題別の分類軸とプライベート軸が衝突し、ツリーが二重になる |

**フォルダ既定値だけは TOML の sidecar** を採用する。これはエントリではなくフォルダに
属する情報であり、リネーム結合の問題が起きないため。

**補完関係**: 調査用途で cybersecurity-series の各 lookup ツール（urlscan-lookup /
whois-lookup / doh-lookup 等）と併用されることを想定するが、ツール自体は URL の
分類・起動という汎用機能なので util-series に置く。

**明示的にスコープ外**:

- ブラウザのブックマークとの同期・インポート・エクスポート
- ブラウザ拡張
- 独自のクラウド同期機構（ルートフォルダを iCloud Drive / Dropbox 配下に置けば済む）
- Safari のプライベート起動（後述の制約）
- CLI サブコマンドの同居
- 項目数が増えたときの検索・quick open パネル（将来の検討事項）
- 現在のブラウザタブの取り込み（Automation 権限が必要になるため）

## 4. Development Plan

### Phase 1: Core

純ロジック中心。単体でレビュー可能。

- `.webloc` の読み書き（バイナリ / XML plist 読み込み、XML 書き戻し）
- ルートフォルダのツリー走査とモデル化（表示名の正規化を含む）
- メタデータ継承解決（エントリ > フォルダ > グローバル）
- インストール済みブラウザの検出と対応表の突き合わせ
- 起動引数の組み立てと `NSWorkspace` によるブラウザ起動
- `config.toml` の読み書き
- メニュー構築（遅延展開）

OS 依存は protocol の背後（`BrowserLauncher` / `BrowserInventory` / `ShelfStore`）に
隔離してモック可能にし、テストは純関数部分に集中させる。

**spike 完了（2026-07-26）**: `NSWorkspace.openApplication(at:configuration:)` +
`arguments` + `createsNewApplicationInstance = true` で、**起動中の Firefox / Chrome /
Edge にプライベートウィンドウを開かせられることを実測で確認**した。設計の前提は成立する。
判明した差分（Firefox は単一ハイフン、`createsNewApplicationInstance` は常に true）は
上記の対応表と §7 に反映済み。独自キーを持つ `.webloc` も Finder / LaunchServices が
問題なく開くことを確認した。

### Phase 2: Features

実機確認を要する範囲。

- 設定ウィンドウ（ルート選択・ブラウザ選択・URL 追加フォーム）
- メニューバーアイコンへの URL ドラッグ&ドロップ
- Option キーによる通常⇄プライベート反転
- プライベート不可環境での disabled 表示と理由提示
- ログイン起動（SMAppService）
- Reveal in Finder / ルートを Finder で開く
- メニューと About でのバージョン表示

### Phase 3: Release

- アプリアイコン（.icns ＋ メニューバー template）
- README.md / README.ja.md / CHANGELOG.md / AGENTS.md / docs/{en,ja}
- 実データでの E2E（実際のツリーと複数ブラウザで確認）
- 署名 + notarize + staple、公開 zip を DL して Gatekeeper 検証
- public リポジトリ作成（LICENSE 必須）
- Homebrew tap cask（prebuilt binary・sha 一致確認）
- util-series submodule ポインタ更新
- org profile / web catalog（EN/JA）更新
- `check-org.sh` all green

**独立レビュー可能な区切り**: Phase 1 は OS 依存を隔離した純ロジックとテストで完結する
ためコードレビュー単体で判断できる。Phase 2 は実機操作の確認が前提となる。

## 5. Required API Scopes / Permissions

外部サービスの認証情報・API スコープは **None**（ネットワーク通信を行わないため）。

macOS 側の権限も以下はいずれも **不要**:

- Automation（AppleScript）— 使用しない
- Accessibility — UI スクリプティングを行わない
- フルディスクアクセス — 非サンドボックスかつユーザーが選んだフォルダのみ読み書きする

ログイン項目への登録は SMAppService 経由でユーザー承認を得る。

## 6. Series Placement

Series: **util-series**

Reason: URL の分類・保管・起動という汎用的なローカルユーティリティであり、特定の外部
サービスにも AI 機能にも依存しない。調査用途で cybersecurity-series のツール群と併用
されることは想定されるが、ツール自体にセキュリティ固有のロジックは無い。既存の macOS
メニューバー常駐 GUI（share-mounter / quick-translate / instant-translate / load-spinner）
と同じ配置。

## 7. External Platform Constraints

- **Safari にプライベート起動の公式手段がない** — CLI オプションも URL scheme も存在
  しない。UI スクリプティング（Cmd+Shift+N）は Accessibility 権限が必要な上に OS 更新で
  壊れるため採用しない。設計上の恒久的制約として受け入れ、Safari は「通常 URL の開き方」
  でのみ選択可能とする
- **引数転送は実証済み** — Firefox / Chrome / Edge のいずれも、起動中インスタンスがある
  状態で `createsNewApplicationInstance = true` を渡すと一時プロセスが起動して既存プロセスへ
  引数を転送し、直後に終了する（元の pid が生存）。`open -na` と同じ挙動
- **`createsNewApplicationInstance = false` は使えない** — Edge では何も開かず、Chrome では
  URL が最前面のウィンドウに紛れ込んだ。フラグが確実に届く保証がないため常に true とする
- **Firefox のフラグは単一ハイフン** — `-private-window` は成功、`--private-window` は
  **黙って無視され通常ウィンドウで開く**。誤りが例外にならず「通常セッションで開く」という
  最悪の形で現れるため、対応表の値は実測でのみ確定させる
- **Firefox の `-private` は使わない** — プライベートウィンドウは開くが、これはインスタンス
  全体のモード指定であり `-private-window` とは意味が異なる
- **URL は最前面のウィンドウに入る** — フラグ無しで開いた URL は、そのブラウザの最前面が
  プライベートウィンドウならその中のタブとして開く。ブラウザ側の仕様であり制御できない。
  逆方向（プライベート指定が通常ウィンドウに落ちる）はフラグにより防止される
- **`.webloc` の独自キーは安全** — 独自キーを足しても `plutil -lint` は OK、UTI は
  `com.apple.web-internet-location` のまま、`open` は既定ブラウザで URL を開く（通常モード）
- **macOS 13+ / darwin・arm64 専用** — SMAppService の要件による
- **Gatekeeper** — notarize + staple 必須。Homebrew tap は prebuilt binary 方式で
  署名を保持する

---

## 実装による改訂

RFP 起草後、実際に作って使う中で 2 点を変えた。

**並び順プレフィックスを廃止（2026-07-26）**: 当初は表示名からファイル名の数字
プレフィックス（`01_` など）を除去し、順序を不可視に表現する設計だった。メニューの
グループ化（フォルダ優先 / 実体優先 / 名称のみ）と昇順・降順を設定にしたことで、
プレフィックスの特別扱いは「Finder に見える名前とメニューの表示が食い違う」という
コストだけが残った。**メニューの表示名は拡張子を除いたファイル名そのもの**とし、
順序を固定したい場合はファイル名に番号を付けて「名称のみ」を選ぶ形にした。

**棚の編集機能を追加し、撤回（2026-07-26）**: ツリー＋インスペクタの Shelf ウィンドウを
実装したが、操作感が要求水準に達せず削除した。経緯と学びは
[ADR-0001](adr-0001-shelf-management.ja.md) を参照。**エントリ 1 件の設定変更**
（URL / 開き方 / ブラウザ指定）だけはメニューの ⌘ + クリックから残っている。
フォルダやファイルの操作は Finder が担当する。

---

## Discussion Log

**発端（2026-07-26）**: macOS でブラウザに URL を渡す際、通常モードとプライベート
モードを指定できるかという調査から出発した。Chrome `--incognito` / Edge `--inprivate` /
Firefox `--private-window` は `open -na ... --args` で指定可能、Safari は不可、という
結論を得た。ここから「ブラウザのブックマークとは独立した URL メモをメニューバーから
開く常駐ツール」という構想に発展した。

**記録形式**: `.webloc` ファイル群 + フォルダツリーをそのまま分類構造とする案を採用。
ツールが無くなっても Finder でダブルクリックすれば開けるため、記録がツールにロック
インされない点を最重要視した。

**プライベート指定の置き場所**: フォルダ構造だけでは表現しきれない（話題別の分類軸と
プライベート軸が衝突し、ツリーが二重になる）ため、エントリ単位のメタデータが必要と
判断。xattr（転送で消える）、sidecar ファイル（リネームで壊れる）、ファイル名規約
（可搬性は最良だが表示名を汚す）を比較し、**webloc plist への逆 DNS 独自キー追加**を
採用。フォルダ単位の既定値のみ TOML sidecar とし、二層で解決する。

**ブラウザ選択肢の作り方**: 当初「Firefox / Chrome から選ぶ」という案だったが、
決め打ちにすると実際にインストールされている Edge が選べない。**プライベート起動
フラグの対応表を持ち、インストール済みのものだけ列挙する**方式に変更した。Brave /
Vivaldi も 1 行追加で対応できる。

**プライベート不可環境の扱い**: 対応ブラウザが 1 つも無い（Safari のみ）場合、
プライベート指定のエントリは disabled とし、通常モードへ無言でフォールバックしない
方針とした。プライベートで開くつもりのものが通常セッションで開くのは、この道具に
とって事故であるため。

**Option キー反転**: 「今回だけプライベートで」という一時的な要求をメタデータ編集
なしに満たすため、Option 押下で通常⇄プライベートを反転する機能を入れる。フラグ管理の
運用負担を大きく下げる。

**CLI 同居**: org 慣習では GUI に CLI サブコマンドを同居させるが、今回は GUI 単独と
する判断（share-mounter と同じ意図的逸脱）。代わりにエントリ追加手段として D&D と
設定画面フォームの両方を v1 に入れる。

**命名**: `site-shelf` / `url-binder` / `url-shelf` を比較。`binder` は data binding /
key binding との連想で二義的になるため、「並べておいて必要なものを取り出す」動作が
UI と一致する `url-shelf` を採用した。

**spike 結果（2026-07-26）**: 設計の前提だった「起動中のブラウザにプライベートウィンドウを
開かせられるか」を実測。Chrome `--incognito` と Edge `--inprivate` はコールド・起動中とも成功。
Firefox は **`--private-window`（ハイフン 2 個）が黙って無視され通常ウィンドウで開く**という
最も危険な失敗をし、**`-private-window`（ハイフン 1 個）で成功**した。ここから
「対応表の値は推測せず実測でのみ確定させる」を設計原則に追加した。また
`createsNewApplicationInstance = false` は Edge で無反応・Chrome で URL が最前面ウィンドウに
紛れ込んだため、**常に true**（`open -na` 相当）とする。`.webloc` の独自キーは
`plutil -lint` OK・UTI 不変・`open` で通常どおり開くことを確認し、Finder 互換の前提も成立した。

**その他の確定事項**: ルートフォルダは単一（複数持ちたければ親フォルダをルートにすれば
済む）、設定は `~/.config/url-shelf/config.toml`（org 規約準拠・可視・grep 可能）、
ログイン起動は SMAppService で入れる（macOS 13+ 要件を受け入れる）。
