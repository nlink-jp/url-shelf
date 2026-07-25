# ADR-0001: Shelf editing belongs inside url-shelf

> Date: 2026-07-26
> Status: Accepted (revised 2026-07-26: reordering moved from deferred to implemented)

## Context

As specified in the RFP, url-shelf only read and opened. Reorganizing the shelf was
Finder's job — a consequence of the design premise that nothing should be locked
into the tool.

Using a real shelf of `.webloc` files exposed a gap Finder cannot fill.

| Operation | Finder | Assessment |
|---|---|---|
| Create, rename, move, delete folders | yes | in-app is merely convenient |
| Move or delete a webloc | yes | same |
| **Edit an entry's URL, open mode, or browser** | **no** (hand-editing a plist) | **the real gap** |
| Maintain ordering prefixes | yes, by hand | tedious |

The core need is the metadata Finder cannot touch; file operations simply belong on
the same screen once that editor exists.

## Decision

**Add a Shelf window: a tree pane and an inspector pane.**

- The whole shelf tree on the left, an inspector for the selection on the right
- Entry inspector: display name, URL, containing folder, open mode, browser
- Folder inspector: display name, containing folder, `.url-shelf.toml` defaults
- Changes apply immediately (no Save button); text fields commit on Return or focus loss
- Relocation happens by **dragging within the tree** and through the inspector's
  folder picker. Dropping on a row's top or bottom edge **reorders**; dropping in
  the middle of a folder row **moves into** it
- Deletion goes to the Trash via `FileManager.trashItem`; `unlink` is never used
- The tree is re-read after every operation

The `Add URL` window stays. Filing the URL you are looking at is a different act
from reorganizing, and a light window with a clipboard prefill is faster for it.

## Alternatives rejected or deferred

**Drag to reorder (deferred at first, implemented 2026-07-26).** Shipping moves
without reordering left the tree feeling half-draggable, so it was implemented.
Ordering is expressed as a numeric filename prefix, so reordering necessarily
**renames files**. The risk is contained as follows.

- **The whole folder is renumbered** (`010_`, `020_`, …). Renumbering only part of
  it cannot guarantee the order, because unprefixed files sort alphabetically among
  themselves
- The step is 10, leaving room to insert something by hand in Finder
- Prefixes stay within **three digits**: four digits are indistinguishable from a
  year, which `DisplayName` deliberately refuses to treat as ordering. Past 99 items
  the step drops to 1; past 999 the reorder is refused
- Renaming happens in **two phases** (everything to a hidden temporary name, then to
  its final one) so that a swap like `010_A` ⇄ `020_B` cannot lose a file. If the
  second phase fails, the temporaries are put back
- Nothing is deleted. An order you dislike can be dragged again, or renamed in Finder

**A tab inside Settings (rejected).** Changing settings and editing data are
different in kind — the same reason Add URL was split out of Settings.

**Menu right-click only (rejected).** Lightweight, but it cannot support
reorganizing while looking at the whole tree.

**An index or database of our own (rejected).** Adding an editor does not change
which side is authoritative. Surviving edits made outside the app is the whole point
of this tool.

## Consequences

- url-shelf becomes a launcher *and* a manager; the README's description changes
- Using Finder alongside it keeps working — both routes produce the same result
- Deleting through the Trash means a mistake is recoverable from Finder
- File operations sit behind a `ShelfEditing` protocol so they stay unit-testable
