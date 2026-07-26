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

## Arranging the shelf

Use Finder. Creating folders, renaming, moving, and deleting are all just files —
that is the point of storing the shelf this way, and Finder is already good at it.
Changes show up the next time a menu opens; nothing needs to be told.

- **Add URL…** (Cmd-N) files a single URL, prefilled from the clipboard, and is
  where an entry's open mode and browser are chosen
- Dropping a URL on the menu bar icon files it in the drop-target folder
- Settings chooses how a folder's contents are grouped in the menu: folders first
  (the default), entries first, or name only — plus the direction
- Menu labels are the filenames, minus the extension. To force an order, number
  the filenames (`01_…`) and pick **Name only**; numbers compare naturally, so
  `2_` comes before `10_`
- To change an existing entry's URL, open mode, or browser, hold **Command** and
  click it in the menu

Modifier keys on a menu entry: **Option** inverts normal ⇄ private for that click,
**Command** opens its settings, **Option-Command** reveals the file in Finder.

url-shelf had a built-in shelf editor for a while; see
[ADR-0001](docs/en/adr-0001-shelf-management.md) for why the tree was removed and
only the single-entry editor kept.

## Configuration

`~/.config/url-shelf/config.toml`

```toml
[shelf]
root    = "~/Documents/URL Shelf"
inbox   = ""                      # drop target for drag & drop; empty = root
sort    = "folders-first"         # "folders-first" | "entries-first" | "name"
order   = "ascending"             # "ascending" | "descending"

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
