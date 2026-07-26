# url-shelf

A macOS menu-bar shelf for the sites you actually use, kept as plain `.webloc`
files on disk. The folder tree **is** the classification: whatever you see in
Finder is what you see in the menu. Entries can be marked to open in a **private
window**, so URLs under investigation never touch your normal session.

> **Status: in development, not yet released.** The shelf works; packaging and
> release are not done. See [docs/en/url-shelf-rfp.md](docs/en/url-shelf-rfp.md)
> for the design.

Japanese: [README.ja.md](README.ja.md)

## Why

Browser bookmarks are fragmented per browser, tied to a profile and an account,
and only leave the browser through an export. url-shelf keeps the records as
standard files that Finder already understands — double-clicking a `.webloc`
opens it even if this app is gone. Nothing is locked into the tool.

## How it works

```
~/Documents/URL Shelf/          <- the shelf root (you pick it)
├── .url-shelf.toml             <- optional defaults for this folder and below
├── work/
│   ├── 01_Internal Wiki.webloc
│   └── Expenses.webloc
└── research/
    ├── .url-shelf.toml         <- open = "private"
    └── Suspicious Site.webloc
```

- Folders become submenus, `.webloc` files become menu items
- The tree is rescanned each time the menu opens — no watcher, no stale state
- Ordering prefixes in filenames (`01_`, `10 - `) sort the entries and are
  stripped from the label
- Hold **Option** while clicking to invert normal ⇄ private for that one click

Per-entry settings live inside the `.webloc` plist under a reverse-DNS
namespace, so the file stays a valid web location:

```xml
<key>URL</key>                  <string>https://example.com</string>
<key>jp.ne.nlink.open</key>     <string>private</string>
<key>jp.ne.nlink.browser</key>  <string>org.mozilla.firefox</string>
```

## Private windows

| Browser | Private launch |
|---|---|
| Firefox | `-private-window` (single dash) |
| Google Chrome | `--incognito` |
| Microsoft Edge | `--inprivate` |
| Safari | **not supported** |

Safari offers no supported way to open a private window from outside the app, so
it can only be chosen for normal URLs. When no private-capable browser is
installed, private entries are shown disabled — url-shelf never silently opens
them in the normal session.

## Managing the shelf

Everything can be done in Finder — that is the point of keeping the records as
files. The Shelf window exists for the one thing Finder cannot do: editing the
settings stored *inside* a `.webloc`.

- **Shelf…** (Cmd-E) opens a tree with an inspector: rename, move, delete, and set
  each entry's URL, open mode, and browser
- **Add URL…** (Cmd-N) files a single URL, prefilled from the clipboard
- Dropping a URL on the menu bar icon files it in the drop-target folder
- Deleting moves to the **Trash**, so a mistake is recoverable from Finder
- Entries and folders are **dragged within the tree**: a line shows where the item
  will land, a highlight shows the folder it will go into. A URL dragged in from a browser is filed
  straight into the folder it lands on
- Reordering renumbers that folder's filenames (`010_`, `020_`, …), because the
  order *is* the filenames — nothing records positions behind your back
- Renaming keeps any ordering prefix, so an entry does not jump position

Changes made in Finder while the app is running are picked up automatically —
the shelf is re-read whenever a menu or the Shelf window needs it. See
[ADR-0001](docs/en/adr-0001-shelf-management.md) for why the editor exists and
what was deliberately left out.

## Configuration

`~/.config/url-shelf/config.toml`

```toml
[shelf]
root    = "~/Documents/URL Shelf"
inbox   = ""                      # drop target for drag & drop; empty = root

[browser]
normal  = "default"               # "default" = system default, or a bundle ID
private = "org.mozilla.firefox"
```

## Build

```sh
make build      # swift build -c release
make test       # swift test
make run        # swift run (debug)
make build-app  # assemble + Developer-ID sign dist/URLShelf.app
make package    # notarize + staple + zip the release asset
```

Requires macOS 13 or later on Apple Silicon.

## Install

Not yet released. Once published:

```sh
brew install --cask nlink-jp/tap/url-shelf
```

> macOS releases are **Developer ID signed and Apple-notarized** (stapled). They
> launch without Gatekeeper prompts and work offline.

## Privacy

url-shelf performs no network communication. It reads and writes only the shelf
folder you select and its own config file, and needs no Automation, Accessibility,
or Full Disk Access permission.

## License

MIT — see [LICENSE](LICENSE).
