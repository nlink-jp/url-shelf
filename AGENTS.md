# AGENTS.md — url-shelf

## What it is

macOS menu-bar app (AppKit `NSStatusItem` + SwiftUI settings window) that keeps
URL notes as `.webloc` files on disk and uses the folder tree as the
classification structure. Selecting an entry opens it in the configured browser;
entries can be marked to open in a **private window** (Firefox / Chrome / Edge —
Safari has no supported mechanism). **Apple Silicon, macOS 13+. GUI only** (no
CLI — a deliberate departure from the util-series CLI-in-GUI convention;
testability is covered by unit tests on the pure layers).

**Status:** scaffold complete, core not yet implemented. Design of record:
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
  StatusItemController.swift    NSStatusItem + NSMenu; rebuilds the menu in menuNeedsUpdate
  Models/
    DisplayName.swift           filename → menu label (drops extension + ordering prefix)
Tests/URLShelfTests/
  DisplayNameTests.swift
docs/{en,ja}/                   RFP
```

Planned additions (Phase 1 of the development plan): `Models/ShelfEntry`,
`Models/FolderDefaults`, `Services/ShelfStore` (webloc read/write + tree walk),
`Services/BrowserInventory` (installed browsers × private-flag table),
`Services/BrowserLauncher` (`NSWorkspace`), `Services/Config` (`config.toml`),
`Views/SettingsView`.

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
- **Chromium argument forwarding is unproven** — opening a private window in an
  *already running* Chrome/Firefox via
  `NSWorkspace.openApplication(at:configuration:)` with `arguments` +
  `createsNewApplicationInstance` must be verified by a spike before the
  launcher is built. The design depends on it.
- **Safari cannot be driven into a private window** from outside. Do not add UI
  scripting (Cmd+Shift+N) as a workaround — it needs Accessibility permission and
  breaks across OS updates.
- Signing scripts under `scripts/` are vendored verbatim from
  `nlink-jp/.github/templates/`; `check-org.sh` flags any drift.

## Series

**util-series**. Repo: `github.com/nlink-jp/url-shelf` (not yet created).
