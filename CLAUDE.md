# CLAUDE.md — url-shelf

Organization rules: https://github.com/nlink-jp/.github/blob/main/CONVENTIONS.md
Workspace rules also apply (see the parent `nlink-jp/CLAUDE.md`).

## What this is

macOS menu-bar app that manages URL notes as `.webloc` files on disk, using the
folder tree as the classification structure, and opens them in a configured
browser — optionally in a **private window**. **Apple Silicon, macOS 13+.
GUI only** (no CLI, deliberately).

## Project rules

- **The filesystem is canonical.** Never introduce a database, index, or cache
  that becomes the source of truth. The app must stay correct if the user
  rearranges the tree in Finder while it is running.
- **Never break Finder compatibility.** The `URL` key of a `.webloc` stays
  untouched so double-clicking still works. Custom keys use the
  `jp.ne.nlink.*` reverse-DNS namespace. Write **XML** plists, not binary —
  the files must stay greppable and hand-editable.
- **Metadata resolution order is entry > nearest ancestor folder > global
  config.** Do not add a fourth layer.
- **Browsers are identified by bundle ID everywhere** (config, folder defaults,
  webloc keys). Display names are presentation only.
- **Launch with `createsNewApplicationInstance = true`, always.** With `false` the
  flags do not reliably reach the browser.
- **Never guess a private-mode flag — measure it.** Firefox takes a single dash
  (`-private-window`); the GNU-style `--private-window` is silently ignored and opens
  a normal window. A wrong flag fails as "opened in the normal session", not as an
  error, so every table entry needs a real launch behind it.
- **Never fall back from private to normal.** If private launching is
  unavailable, disable the item and say why. Opening a private-marked URL in the
  normal session is the one failure this tool exists to prevent.
- **`NSStatusItem`, not `MenuBarExtra`.** Lazy submenu population
  (`NSMenuDelegate`), Option-key alternate items, and accepting a URL dropped on
  the status item have no SwiftUI equivalent. SwiftUI is used inside the settings
  window via `NSHostingView`.
- **Rescan on menu open; no FSEvents watcher.** No synchronization state to drift.
- **Tests required** — `make test` / `swift test` must pass before committing.
  Keep OS access behind protocols (`BrowserLauncher`, `BrowserInventory`,
  `ShelfStore`) so the logic stays unit-testable.
- **`make build` / `make build-app`**, never `swift build` directly for anything
  shipped. `LSUIElement = true`; version comes from `git describe`.
- **macOS 13 minimum** — `SMAppService` requires it. Do not use macOS 14+-only
  APIs without a 13 fallback.
- **No network access.** The app must not gain a network code path.

## Series

Part of **util-series** (submodule). Repo: `github.com/nlink-jp/url-shelf`.
