# url-shelf

よく開くサイトを `.webloc` ファイルとしてディスク上に置き、メニューバーから開く macOS
常駐アプリ。**フォルダ構成がそのまま分類**になり、Finder で見えるものがそのままメニューに
出ます。エントリごとに **プライベートウィンドウで開く** 指定ができるので、調査対象の URL を
通常セッションに触れさせずに開けます。

> **現状: 開発中・未リリース。** 棚の機能は動作します。パッケージングとリリースは未了です。
> 設計の全体は [docs/ja/url-shelf-rfp.ja.md](docs/ja/url-shelf-rfp.ja.md) を参照。

English: [README.md](README.md)

## なぜ作るか

ブラウザのブックマークはブラウザごとに分断され、プロファイルやアカウントに紐付き、
エクスポートしないと外に出せません。url-shelf は記録を Finder が理解する標準ファイルの
まま保持します。`.webloc` はこのアプリが無くなってもダブルクリックで開けるので、
記録がツールにロックインされません。

## しくみ

```
~/Documents/URL Shelf/          ← 棚のルート（自分で選ぶ）
├── .url-shelf.toml             ← このフォルダ以下の既定値（任意）
├── 仕事/
│   ├── 01_社内Wiki.webloc
│   └── 経費.webloc
└── 調査/
    ├── .url-shelf.toml         ← open = "private"
    └── 検体サイト.webloc
```

- フォルダ = サブメニュー、`.webloc` = メニュー項目
- メニューを開くたびにツリーを再スキャン（監視なし・状態を持たない）
- ファイル名の並び順プレフィックス（`01_`、`10 - `）は並び替えに使い、表示からは除去
- **Option キーを押しながらクリック**すると、その一回だけ通常⇄プライベートを反転

エントリ個別の設定は `.webloc` の plist に逆 DNS 名前空間で埋めるため、ファイルは
有効な web location のまま保たれます。

```xml
<key>URL</key>                  <string>https://example.com</string>
<key>jp.ne.nlink.open</key>     <string>private</string>
<key>jp.ne.nlink.browser</key>  <string>org.mozilla.firefox</string>
```

## プライベートウィンドウ

| ブラウザ | プライベート起動 |
|---|---|
| Firefox | `-private-window`（ハイフン 1 個） |
| Google Chrome | `--incognito` |
| Microsoft Edge | `--inprivate` |
| Safari | **非対応** |

Safari には外部からプライベートウィンドウを開く公式手段が存在しないため、通常 URL 用と
してのみ選択できます。プライベート対応ブラウザが 1 つも入っていない場合、プライベート
指定の項目は無効表示になります。通常セッションで黙って開くことはしません。

## 棚の整理

Finder で行います。フォルダの作成・リネーム・移動・削除はどれも単なるファイル操作であり、
棚をこの形で保存しているのはそのためです。変更は次にメニューを開いた時点で反映されます。

- **Add URL…**（⌘N）で 1 件追加。クリップボードの URL が初期値に入り、開き方とブラウザ
  指定もここで決める
- メニューバーアイコンへの URL ドロップでドロップ先フォルダに追加
- 並び順はファイル名の数字プレフィックス（`01_`、`02_`）で決まり、表示からは除去される。
  並べ替えたければ Finder でリネームする
- 既存エントリの URL・開き方・ブラウザ指定を変えたい場合は、メニューで **⌥⌘ を押しながらクリック**

メニュー項目の修飾キー: **⌥** でその回だけ通常⇄プライベート反転、**⌘** で Finder に表示、
**⌥⌘** で設定変更。

一時期アプリ内にツリー形式の編集機能を持っていました。ツリーを外して単一エントリの編集だけ
残した理由は [ADR-0001](docs/ja/adr-0001-shelf-management.ja.md) を参照。

## 設定

`~/.config/url-shelf/config.toml`

```toml
[shelf]
root    = "~/Documents/URL Shelf"
inbox   = ""                      # ドラッグ&ドロップの受け皿。空ならルート直下

[browser]
normal  = "default"               # "default" = システム既定 / または bundle ID
private = "org.mozilla.firefox"
```

## ビルド

```sh
make build      # swift build -c release
make test       # swift test
make run        # swift run (debug)
make build-app  # dist/URLShelf.app を組み立てて Developer ID 署名
make package    # notarize + staple + リリース用 zip
```

macOS 13 以降・Apple Silicon が必要です。

## インストール

未リリース。公開後は以下で入ります。

```sh
brew install --cask nlink-jp/tap/url-shelf
```

> macOS 版は **Developer ID 署名 + Apple notarize（staple 済み）** です。Gatekeeper の
> 警告なしに起動し、オフラインでも動作します。

## プライバシー

url-shelf はネットワーク通信を一切行いません。読み書きするのは選択した棚フォルダと
自身の設定ファイルのみで、Automation・アクセシビリティ・フルディスクアクセスの
いずれの権限も必要としません。

## ライセンス

MIT — [LICENSE](LICENSE) を参照。
