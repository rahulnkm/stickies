# Stickies — Hide / Manager

**Date:** 2026-05-14
**Status:** Design

## Why

Stickies today have two states: present on screen, or gone (deleted). That forces the user to choose between *clutter* and *loss*. They want a third state: **kept but out of sight**, with a lightweight way to bring it back later.

## What

1. **Hide** any sticky from its window via a minimize-style button.
2. **Manager window** — single window listing all notes (visible + hidden) with inline expand to read/edit. Search included.
3. **Menu bar dropdown** — fast list of all notes; click to toggle visibility.
4. Delete-forever moves out of the sticky itself and into the manager (via right-click). Existing undo toast is reused.

## Model

Add one field to `Note`:

```swift
var isHidden: Bool = false   // new in schemaVersion 2
```

- `schemaVersion` bumps to `2`. Decoder defaults `isHidden` to `false` when missing — old JSON loads cleanly.
- Persistence remains one JSON per note in `~/Library/Application Support/Stickies/notes/`. **No file moves.**

`NoteStore` gains:
- `hide(id:)` — sets `isHidden = true`, schedules write.
- `unhide(id:)` — sets `isHidden = false`, schedules write.
- Convenience accessors: `visibleNotes`, `hiddenNotes` (computed).

The published `notes` array stays the single source of truth — sorted by `createdAt`. Visibility is a filter, not a separate collection.

## Sticky window UX

The top-bar (hover-reveal strip) loses the `×`. In its place:

```
[● ● ● ●]   …   [ − ]    ← minimize-style button (yellow stoplight)
swatches            hide
```

- Button: 12pt yellow filled circle (matches macOS stoplight), centered minus glyph on hover, same hover-reveal animation as today.
- Click → calls `onHide(noteID)`. AppDelegate closes the window (preserving frame) and calls `store.hide(id:)`.
- **No undo toast on hide.** Hiding is reversible from the menu bar or manager in two clicks — toast would be noise.

## Menu bar dropdown

`MenuBarController` rebuilds its menu lazily via `NSMenuDelegate.menuNeedsUpdate(_:)` so it reflects current state every time it opens.

Structure:

```
New Note                                  ⌘N
─────────────────────────────────────────
Visible
  ● grocery list…                      Hide
  ● shipping addr…                     Hide
  ● client brief…                      Hide
Hidden
  ○ old wifi pw…                       Show
  ○ recipe idea…                       Show
  ○ … 5 more, open Manager
─────────────────────────────────────────
Open Manager…                            ⌘⇧N
Launch at Login
─────────────────────────────────────────
Quit Stickies                            ⌘Q
```

- Filled dot = visible, hollow = hidden.
- Each row's text = first ~32 chars of note text (or "Untitled" if empty).
- Click a row → toggles visibility (calls `hide` or `unhide`).
- Hidden section capped at 8 rows; overflow row says "… N more, open Manager".

## Manager window

New `ManagerWindowController` + SwiftUI `ManagerView`.

- Single non-floating window, default 520×640, resizable, remembers frame (autosaved by NSWindow).
- Single instance — re-opening focuses the existing one.
- Activation policy: app temporarily acts as a regular app while manager is key (so it appears in Cmd-Tab and Mission Control); reverts to accessory-style when manager closes.

Layout:

```
┌─────────────────────────────────────────┐
│  [ 🔍 Search…                        ]  │
├─────────────────────────────────────────┤
│  ▾ Visible (3)                          │
│  ● grocery list…             2d   Hide  │
│  ● shipping addr…            5h   Hide  │
│  ● client brief…             1m   Hide  │
│                                         │
│  ▾ Hidden (12)                          │
│  ○ old wifi pw…              90d  Show  │
│  ○ recipe idea…              30d  Show  │
│  …                                      │
└─────────────────────────────────────────┘
```

- Rows show preview (first line, truncated), relative timestamp (`updatedAt`), inline action button.
- **Click row → expand inline** to a full-text editor for that note. Edits persist live via `store.update(text:)`. Click elsewhere or the same row again → collapse.
- Right-click row → context menu: **Delete forever** (uses existing `UndoToast`).
- Search: filters notes by text match (case-insensitive substring). Sections still shown if either has results.
- Empty state: "No notes yet" / "No matches".

## Lifecycle

Launch:
- `loadFromDisk()` reads all notes.
- AppDelegate opens windows only for `store.visibleNotes`.

Hide (from sticky):
- AppDelegate persists frame, closes window, calls `store.hide(id:)`.
- Note remains in `notes`; window controller removed from `controllers` map.

Show (from menu bar or manager):
- AppDelegate calls `store.unhide(id:)`, then `openWindow(for: id)`.
- Window rehydrates at saved frame.

Delete forever (from manager):
- Same path as today: `store.beginDelete` → undo toast → `commitDelete` on expire.

Quit:
- `store.flush()` writes pending changes. No special handling for hidden state.

## Files touched / created

**Modified:**
- `Stickies/Models/Note.swift` — add `isHidden`, bump schemaVersion.
- `Stickies/Storage/NoteStore.swift` — add `hide`, `unhide`, computed `visibleNotes`/`hiddenNotes`.
- `Stickies/AppDelegate.swift` — open only visible notes on launch; route hide; expose `openManager()`.
- `Stickies/MenuBar/MenuBarController.swift` — dynamic menu, manager item, NSMenuDelegate.
- `Stickies/Windows/NoteView.swift` — replace × with minimize-style button; rename `onClose` → `onHide`.
- `Stickies/Windows/NoteWindowController.swift` — rename callback for clarity.

**New:**
- `Stickies/Windows/ManagerWindowController.swift` — NSWindowController.
- `Stickies/UI/ManagerView.swift` — SwiftUI view.

## Out of scope (YAGNI)

- Folders, tags, pins.
- Multi-select bulk hide / delete.
- Keyboard shortcut to hide focused sticky.
- Sync, export, sharing.
- Drag-reorder.

## Risks / open questions

- **Cmd-Tab visibility of the manager:** activation policy bouncing between `.accessory` and `.regular` works but is mildly hacky. Alternative: keep `.regular` always (already set in current code via `NSApp.setActivationPolicy(.regular)`). The manager will appear in Cmd-Tab automatically. Going with current `.regular` — no policy juggling.
- **Live preview text for the menu bar:** computing first-32-chars per note on every menu open is trivial cost.
- **Manager edit conflicts with open sticky window:** both views write through `store.update(text:)`, which uses `@Published notes`. SwiftUI bindings on both sides stay in sync. No conflict — last writer wins per keystroke.
