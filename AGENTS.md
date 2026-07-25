# AGENTS.md — url-shelf

## What it is

macOS menu-bar app (AppKit `NSStatusItem` + SwiftUI settings window) that keeps
URL notes as `.webloc` files on disk and uses the folder tree as the
classification structure. Selecting an entry opens it in the configured browser;
entries can be marked to open in a **private window** (Firefox / Chrome / Edge —
Safari has no supported mechanism). **Apple Silicon, macOS 13+. GUI only** (no
CLI — a deliberate departure from the util-series CLI-in-GUI convention;
testability is covered by unit tests on the pure layers).

**Status:** in development. Reading, launching, and shelf editing work; not yet
packaged or released. Design of record:
`docs/en/url-shelf-rfp.md` / `docs/ja/url-shelf-rfp.ja.md`.

## Build / test / run

```sh
make build      # swift build -c release
make test       # swift test
make run        # swift run (debug)
make build-app  # assemble + Developer-ID sign dist/URLShelf.app
make package    # notarize + staple + zip the release asset
make brew       # generate the Homebrew cask into ../homebrew-tap
```

`build-app` renders `AppIcon.icns` from `assets/AppIcon-1024.png` when present
(not yet added — the build warns and proceeds without an icon). `LSUIElement`
app; version comes from `git describe`.

Icon and version UI can only be verified in the `.app` — a bare `swift run` has
no bundle, so `AppInfo.version` falls back to `"dev"`.

## Layout

```
Package.swift                   SPM manifest; single executable + test target
Info.plist                      bundle template; ${APP_NAME}/${BUNDLE_ID}/${VERSION} substituted by make
Makefile                        build / build-app / package / brew
scripts/                        codesign + notarize + cask generation (vendored from .github/templates)
Sources/URLShelf/
  App.swift                     @main (AppKit entry, .accessory policy) + AppDelegate + AppInfo.version
  AppModel.swift                @MainActor orchestrator; config, plans, shelf mutations
  StatusItemController.swift    NSStatusItem + NSMenu; rebuilds the menu in menuNeedsUpdate
  Models/
    DisplayName.swift           filename ⇄ menu label (ordering prefix, rename)
    EntryNaming.swift           filename choice, sanitizing, collision counter
    OpenMode.swift              OpenMode / BrowserSelection / webloc key names
    WeblocFile.swift            plist read/write, foreign keys preserved
    FolderDefaults.swift        .url-shelf.toml model
    AppConfig.swift             ~/.config/url-shelf/config.toml model
  Services/
    ShelfStore.swift            FileSystemShelf: one-level walk, defaults chain, full tree
    ShelfEditor.swift           create/rename/move/trash behind ShelfEditing
    MetadataResolver.swift      entry > nearest folder > global config
    LaunchPlanner.swift         resolved plan → LaunchAction, by table lookup
    BrowserCatalog.swift        measured private-flag table + installed-browser filter
    BrowserLauncher.swift       NSWorkspace launch + LaunchServices inventory
    LoginItemManager.swift      SMAppService
    MiniTOML.swift              the TOML subset the config files need
  Views/
    HostedWindow.swift          NSWindow + NSHostingView host; activation-policy counting
    SettingsView.swift          configuration only
    AddEntryView.swift          quick capture, clipboard prefill
    ShelfView.swift             tree + inspector (the editor)
    URLDropView.swift           drop target overlaid on the status item button
Tests/URLShelfTests/            unit tests for every pure layer
spikes/launch-probe.swift       browser private-launch harness (see Gotchas)
docs/{en,ja}/                   RFP + ADR-0001
```

## Data model

The filesystem is canonical. An entry is a `.webloc` (plist) whose `URL` key is
left untouched so Finder can still open it; url-shelf's own settings live under
`jp.ne.nlink.open` (`normal` | `private`) and `jp.ne.nlink.browser` (bundle ID).
Per-folder defaults live in `.url-shelf.toml` and are inherited downward.
Resolution order: **entry > nearest ancestor folder > global config**
(`~/.config/url-shelf/config.toml`).

## Gotchas

- **`NSApplication.delegate` is weak** — `URLShelfMain` owns the delegate in a
  static, otherwise it is deallocated immediately after `main()`.
- **`NSStatusItem`, not `MenuBarExtra`** — required for lazy submenu population,
  Option-key alternate items, and drag-and-drop onto the status item.
- **Ordering-prefix stripping is capped at 3 digits** so that names starting with
  a year (`2026-07-26 notes.webloc`) are not mangled.
- **Argument forwarding works, but only with `createsNewApplicationInstance = true`**
  (measured 2026-07-26). With it, a transient process forwards the arguments to the
  running browser and exits. With `false`, Edge opened nothing and Chrome let the URL
  slip into whatever window was frontmost — never use `false`.
- **Firefox takes a single dash: `-private-window`.** `--private-window` is silently
  ignored and opens a **normal** window — the failure surfaces as the exact outcome
  this app exists to prevent, not as an error. Never assume a flag's dash form;
  measure it. Do not use Firefox's `-private` (an instance-wide mode switch).
- **A URL opened without flags joins the browser's frontmost window**, which may be a
  private one. Browser behavior, not controllable, and harmless — the dangerous
  direction (private entry → normal window) is prevented by the flag.
- **Safari cannot be driven into a private window** from outside. Do not add UI
  scripting (Cmd+Shift+N) as a workaround — it needs Accessibility permission and
  breaks across OS updates.
- Signing scripts under `scripts/` are vendored verbatim from
  `nlink-jp/.github/templates/`; `check-org.sh` flags any drift.

## Series

**util-series**. Repo: `github.com/nlink-jp/url-shelf` (not yet created).
