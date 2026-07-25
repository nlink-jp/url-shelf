# RFP: url-shelf

> Generated: 2026-07-26
> Status: Draft

## 1. Problem Statement

Browser bookmarks are fragmented per browser, tied to profiles and accounts, and
cannot leave the browser without an export step. As a result, the list of sites you
actually use is held hostage by a particular browser implementation. url-shelf keeps
URL notes as plain `.webloc` files on the filesystem and treats the directory
structure itself as the classification tree. Selecting a site from the menu bar
opens it in the configured browser. Each entry can be marked "open in a private
window", isolating URLs under investigation from the normal browsing session.
Because the records are standard files that Finder understands, the data survives
the tool. Intended users are developers and security practitioners (initially the
author).

## 2. Functional Specification

### Commands / API Surface

GUI only — no CLI subcommands. All interaction happens through the menu bar and the
settings window.

**Menu bar**

- The tree under the root folder is rendered directly as the menu hierarchy:
  folders become submenus, `.webloc` files become items
- The tree is rescanned when the menu opens (no FSEvents watcher). This keeps the
  menu always current and keeps no synchronization state in the app
- Deep hierarchies are populated lazily when a submenu opens
- Plain click opens the entry in its resolved mode
- **Holding Option inverts normal ⇄ private** (shown via an alternate item)
- When no private-capable browser is configured or installed, private entries are
  **disabled**. The app never silently falls back to normal mode
- Fixed trailing items: "Add URL…", "Open root in Finder", "Settings…",
  version display / About, Quit

**Adding entries**

1. Drag and drop a URL onto the menu bar icon → writes a `.webloc` into the inbox
   folder
2. An add form in the settings window (URL / display name / destination folder /
   private flag / browser override)

**Settings window**

- Root folder selection (NSOpenPanel)
- How to open normal URLs: system default browser, or an explicitly chosen
  installed browser
- How to open private URLs: chosen from installed browsers that support
  private-window launching
- If no capable browser exists, state so explicitly
- Launch-at-login toggle (SMAppService)
- Version display

### Input / Output

**Data model (canonical = the filesystem)**

```
~/Documents/URL Shelf/          <- root (single; chosen via NSOpenPanel)
├── .url-shelf.toml             <- defaults for this folder and below (optional)
├── work/
│   ├── 01_Internal Wiki.webloc
│   └── Expenses.webloc
└── research/
    ├── .url-shelf.toml         <- open = "private" / browser = "org.mozilla.firefox"
    └── Suspicious Site.webloc
```

- An entry is a `.webloc` (plist). The display name is the filename minus the
  extension and any ordering prefix (digits plus separator, e.g. `01_`)
- Reading accepts both binary and XML plists. **Writing always produces XML plist**
  so the files stay greppable, diffable, and hand-editable
- Custom keys use a reverse-DNS namespace

```xml
<key>URL</key>                  <string>https://example.com</string>
<key>jp.ne.nlink.open</key>     <string>private</string>
<key>jp.ne.nlink.browser</key>  <string>org.mozilla.firefox</string>
```

The `URL` key is untouched, so double-clicking in Finder still opens the entry in
the default browser. In that path the private flag has no effect and the site opens
normally — an accepted degradation.

**Metadata resolution order**

```
entry custom keys > nearest ancestor .url-shelf.toml > global settings
```

Folder defaults are inherited downward, so "everything under `research/` defaults to
Firefox private" is expressed in a single file.

**Browser identifiers**

Browsers are stored as **bundle IDs** at every layer (names are only for display),
so renames and localization cannot break stored configuration.

### Configuration

`~/.config/url-shelf/config.toml`

```toml
[shelf]
root    = "~/Documents/URL Shelf"
inbox   = ""                      # drop target for D&D; empty = root itself

[browser]
normal  = "default"               # "default" = system default, or a bundle ID
private = "org.mozilla.firefox"   # only private-capable browsers are selectable
```

Per-folder defaults, `.url-shelf.toml` (optional, in any folder):

```toml
open    = "private"               # "normal" | "private"
browser = "org.mozilla.firefox"
```

### External Dependencies

None. The app performs no network communication and depends on no external API,
credential, or cloud service.

**Browser capability table** (only installed entries are listed in the settings UI)

| bundle ID | private-window flag |
|---|---|
| `org.mozilla.firefox` | `--private-window` |
| `com.google.Chrome` | `--incognito` |
| `com.microsoft.edgemac` | `--inprivate` |
| `com.apple.Safari` | not supported (normal mode only) |

Other Chromium-based browsers (Brave, Vivaldi) must be addable with a single row.

## 3. Design Decisions

**Language / framework**: Swift, SwiftUI + AppKit, darwin/arm64 only, macOS 13+.
Follows the same skeleton as the existing menu bar apps (share-mounter,
quick-translate, active-lens-gui): a single SPM executable target, `make build`
emitting to `dist/`, non-sandboxed Developer ID signing.

**Where the metadata lives**: custom reverse-DNS keys inside the `.webloc` plist.
Alternatives considered and rejected:

| Option | Why rejected |
|---|---|
| Extended attributes (xattr) | Lost on zip, cloud sync, and transfer; invisible and undebuggable |
| Per-folder sidecar keyed by entry | Joined by filename, so renames and moves break it |
| Filename convention (`Foo [private].webloc`) | Best portability and visibility, but pollutes the display name and breaks down as keys multiply |
| A `Private/` folder | The privacy axis collides with the topical axis, duplicating the tree |

**Folder-level defaults do use a TOML sidecar**, because that information belongs to
the folder rather than to an entry, so the rename-join problem does not arise.

**Complementary tools**: expected to be used alongside the cybersecurity-series
lookup tools (urlscan-lookup, whois-lookup, doh-lookup) during investigation, but the
tool itself only classifies and launches URLs, so it belongs in util-series.

**Explicitly out of scope**:

- Syncing, importing, or exporting browser bookmarks
- Browser extensions
- A proprietary cloud-sync mechanism (placing the root under iCloud Drive or Dropbox
  covers this)
- Private-window launching for Safari (see constraints)
- A co-resident CLI
- A search / quick-open panel for large collections (future consideration)
- Capturing the browser's current tab (would require Automation permission)

## 4. Development Plan

### Phase 1: Core

Pure logic, independently reviewable.

- `.webloc` read/write (binary and XML plist reading, XML writing)
- Root tree traversal and modeling, including display-name normalization
- Metadata inheritance resolution (entry > folder > global)
- Installed-browser detection matched against the capability table
- Launch-argument construction and browser launching via `NSWorkspace`
- `config.toml` read/write
- Menu construction with lazy expansion

OS dependencies are isolated behind protocols (`BrowserLauncher`,
`BrowserInventory`, `ShelfStore`) so they can be mocked; tests concentrate on the
pure functions.

**Spike first (highest priority)**: prove that
`NSWorkspace.openApplication(at:configuration:)` with `arguments` and
`createsNewApplicationInstance` can make an already-running Chrome or Firefox open a
private window. If this fails, the design's premise changes, so it is settled before
any other implementation. The same spike confirms that Finder and LaunchServices
handle `.webloc` files carrying custom keys.

### Phase 2: Features

Requires verification on real hardware.

- Settings window (root selection, browser selection, add-URL form)
- URL drag and drop onto the menu bar icon
- Option-key inversion of normal ⇄ private
- Disabled state and stated reason when private launching is unavailable
- Launch at login (SMAppService)
- Reveal in Finder / open root in Finder
- Version display in the menu and About panel

### Phase 3: Release

- App icon (.icns plus menu bar template)
- README.md / README.ja.md / CHANGELOG.md / AGENTS.md / docs/{en,ja}
- E2E against a real tree with multiple browsers installed
- Signing, notarization, stapling; download the published zip and verify Gatekeeper
- Public repository with LICENSE
- Homebrew tap cask (prebuilt binary, sha verified)
- util-series submodule pointer update
- org profile and web catalog (EN/JA) updates
- `check-org.sh` all green

**Independently reviewable boundary**: Phase 1 is self-contained pure logic plus
tests and can be judged by code review alone. Phase 2 presupposes hands-on
verification.

## 5. Required API Scopes / Permissions

External service scopes and credentials: **None** (no network communication).

The following macOS permissions are also **not** required:

- Automation (AppleScript) — not used
- Accessibility — no UI scripting
- Full Disk Access — non-sandboxed, and only the user-selected folder is touched

Login-item registration is granted by the user through SMAppService.

## 6. Series Placement

Series: **util-series**

Reason: a general-purpose local utility for classifying, storing, and launching
URLs, with no dependency on an external service or AI capability. It is expected to
be used alongside the cybersecurity-series tools during investigation, but contains
no security-specific logic itself. Same placement as the existing macOS menu bar
GUIs (share-mounter, quick-translate, instant-translate, load-spinner).

## 7. External Platform Constraints

- **Safari has no supported way to open a private window from outside** — no CLI
  option, no URL scheme. UI scripting (Cmd+Shift+N) needs Accessibility permission
  and breaks across OS updates, so it is not adopted. Accepted as a permanent design
  constraint; Safari remains selectable only for normal URLs
- **Chromium singleton behavior** — the design depends on argument forwarding to an
  already-running instance. Must be proven by the Phase 1 spike
- **Custom keys in `.webloc`** — depends on Finder and LaunchServices ignoring
  unknown keys. The spike confirms only the `URL` key is consumed
- **macOS 13+, darwin/arm64 only** — driven by the SMAppService requirement
- **Gatekeeper** — notarization and stapling are mandatory; the Homebrew tap uses the
  prebuilt-binary form to preserve the signature

---

## Discussion Log

**Origin (2026-07-26)**: started from the question of whether macOS lets you specify
normal versus private mode when handing a URL to a browser. The answer: Chrome
`--incognito`, Edge `--inprivate`, and Firefox `--private-window` work via
`open -na ... --args`, while Safari has no supported mechanism. That led to the idea
of a menu bar resident tool holding URL notes independently of browser bookmarks.

**Record format**: `.webloc` files plus a folder tree used directly as the
classification structure. The decisive factor was that the records remain openable
by double-clicking in Finder even if the tool disappears, so the data is not locked
into the tool.

**Where the private flag lives**: folder structure alone cannot express it — a
privacy axis would collide with the topical axis and duplicate the tree — so
per-entry metadata is required. After comparing xattr (lost in transfer), sidecar
files (broken by renames), and filename conventions (most portable but pollutes the
display name), **custom reverse-DNS keys in the webloc plist** were chosen, with
folder-level defaults in a TOML sidecar as a second layer.

**How browser choices are built**: the initial idea was a fixed "Firefox or Chrome"
list, but hardcoding excludes Edge, which is actually installed. Changed to
**holding a capability table of private-launch flags and listing only installed
browsers**, so Brave and Vivaldi cost one row each.

**Behavior when private launching is impossible**: when no capable browser exists
(Safari only), private entries are disabled rather than silently falling back to
normal mode — opening something in the normal session that was meant to be private
is an accident this tool exists to prevent.

**Option-key inversion**: added so that "just this once, privately" needs no metadata
edit, substantially lowering the cost of maintaining flags.

**Co-resident CLI**: the org convention is to ship a CLI subcommand inside GUI apps,
but this project is GUI-only (the same deliberate deviation as share-mounter).
Instead, both drag-and-drop and a settings-window form ship in v1 as entry-adding
paths.

**Naming**: compared `site-shelf`, `url-binder`, and `url-shelf`. "binder" is
ambiguous against data binding and key binding, whereas "shelf" matches the actual
interaction — things are lined up and picked off. `url-shelf` was chosen.

**Other settled points**: a single root folder (nesting under a common parent covers
multiple trees), configuration at `~/.config/url-shelf/config.toml` (org convention,
visible, greppable), and launch at login via SMAppService, accepting the macOS 13+
requirement.
