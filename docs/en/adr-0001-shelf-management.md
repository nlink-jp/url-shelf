# ADR-0001: Shelf editing belongs inside url-shelf (implemented, then reversed)

> Date: 2026-07-26
> Status: **Reversed** (implemented and withdrawn the same day)

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

## The original decision

Add a Shelf window — a tree pane and an inspector pane — offering rename, move,
delete, metadata editing, and drag-to-reorder. Deletion through the Trash, renaming
preserving the ordering prefix, reordering renumbering the folder's filenames.

## Reversal

**It was built, the interaction never became good enough, and the feature was
removed.**

Drag and drop in a SwiftUI tree is where it broke down.

1. `.dropDestination` reports the pointer position only at the moment of the drop.
   No insertion line could be drawn, so nothing showed where the item would land
   until it was already there.
2. `DropDelegate` does report the position during the drag, but its end-of-session
   callbacks cannot be trusted: neither `dropExited` nor `performDrop` is
   guaranteed, and a stray `dropUpdated` can arrive *after* a drop. The insertion
   line stayed on screen.
3. Adding more places to clear it still left cases uncovered, ending in a watchdog
   that clears the marker when updates stop arriving. It works, but inferring UI
   state from a timer is a bad sign.
4. Separately, the view body walked the whole shelf on every re-evaluation, which
   froze the window mid-drag. Caching fixed that, but it exposed how poorly the
   SwiftUI tree + drag-and-drop combination fits this job.

**Continuing down this path means rewriting the tree on `NSOutlineView`**, and that
investment is not worth it for this feature. Finder is already good at rearranging
folders, and url-shelf exists to *open* things, not to manage files.

## State after the reversal

- The Shelf window, tree, inspector, drag and drop, reordering, and trash deletion
  are gone
- Creating, renaming, moving, and deleting folders and entries happens **in Finder**
- A new entry's open mode and browser are set in the **Add URL** window
- **An existing entry's metadata can no longer be changed from inside the app** —
  hand-edit the `.webloc` plist or add it again. This is the one real capability the
  reversal costs
- Ordering stays as it was: a numeric filename prefix, adjusted by renaming in Finder

## What this taught us

- Handling **the end of a drag session reliably is not practical** on SwiftUI's
  `List` / `OutlineGroup`. If reordering with an insertion indicator is required,
  start with `NSOutlineView`.
- Never walk the filesystem from a view body. SwiftUI re-evaluates bodies often.
- Before reimplementing what Finder already does, ask whether it is needed. The only
  thing genuinely missing was **metadata editing**; the file operations came along
  for the ride. A second attempt should start with a small window that edits one
  entry, and no tree at all.
