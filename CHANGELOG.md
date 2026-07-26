# Changelog

All notable changes to url-shelf are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] - 2026-07-26

Initial release.

### Added
- Menu-bar shelf built from a folder of `.webloc` files. Folders become
  submenus, populated when they open; the tree is re-read every time a menu
  opens, so edits made in Finder appear without telling the app.
- Per-entry **private window** opening, with the mode and browser stored inside
  the `.webloc` under a `jp.ne.nlink.*` namespace. The `URL` key is untouched, so
  double-clicking the file in Finder still works.
- Per-folder defaults in `.url-shelf.toml`, inherited downward. Resolution order
  is entry > nearest ancestor folder > global settings.
- Measured private-launch support for Firefox, Chrome, Edge, Brave, and Vivaldi.
  Safari offers no supported mechanism, so it is normal-mode only; when no
  capable browser is configured, private entries are **disabled rather than
  opened in the normal session**.
- Modifier keys on an entry: Option inverts normal ⇄ private for that click,
  Command opens its settings, Option-Command reveals the file in Finder.
- Add URL window (Cmd-N), prefilled from the clipboard, and a drop target on the
  menu bar icon.
- Settings: shelf folder, drop target, menu grouping and direction, both browser
  choices, and launch at login.
- Configuration in `~/.config/url-shelf/config.toml` — a visible, greppable file.
- No network access, and no Automation, Accessibility, or Full Disk Access
  permission required.

[0.1.0]: https://github.com/nlink-jp/url-shelf/releases/tag/v0.1.0
