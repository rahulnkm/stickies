# Stickies — Design Spec

**Status**: approved (brainstorming phase)
**Date**: 2026-04-22
**Scope**: v1, local-only Mac app

## 1. Product summary

A minimalist floating sticky-notes app for macOS. Users summon a new note from a menu bar icon; each note opens as a small, borderless, always-on-top window on the desktop. Notes are plain text, dark-themed, autosave on every edit, and persist across restarts. The app launches at login by default so notes are always present.

The design goal is **minimal and beautiful** — no chrome, no decisions, one font, one color. The note gets out of the way.

### User stories (v1)

- As a user, I click the menu bar icon and pick **New Note**. A sticky window appears on screen.
- I type into the note. Every keystroke is saved automatically.
- I drag the note anywhere on my desktop by grabbing any part of it.
- I resize the note from its edges.
- The note stays visible on top of other windows so I can reference it while working.
- I hover over the note and a small close button appears. I click it to delete the note. A toast gives me 3 seconds to undo.
- I quit and reopen my Mac. All my notes are exactly where I left them.
- I toggle **Launch at Login** off in the menu bar if I don't want it starting automatically.

### Out of scope for v1

- Rich text, markdown, images, attachments
- Multiple colors or themes
- Light mode / system-theme following
- Global keyboard shortcut to create a note
- iCloud or any cloud sync
- Multiple devices
- Tags, search, folders
- Export / import
- App Store distribution (no sandboxing, no notarization)
- Accessibility-permission-gated features

## 2. Interaction model

### Creating a note

- Menu bar `NSStatusItem` with a minimal icon.
- Menu options: **New Note**, **Launch at Login** (checkmark toggle), **Quit**.
- Clicking **New Note** creates a note and opens its window.
- New windows cascade: each new window appears 24 px down and 24 px right from the most recently created window. If that would place it off-screen, wrap to a starting position near the top-left of the main screen.

### Window behavior

- Borderless window (no title bar, no traffic lights).
- Window level: `.floating` — always on top of normal application windows.
- Dock icon visible; app appears in ⌘Tab switcher.
- Draggable from anywhere inside the window (`isMovableByWindowBackground = true`).
- Resizable from all four edges and four corners.
- Default size: 240 × 240 px. Minimum size: 160 × 140 px. No maximum.
- System-native NSWindow shadow (soft, lifted off the desktop).
- Corner radius: 6 px (applied to the window's content view).

### Editing

- The entire interior of the window is a `TextEditor`.
- Focus goes to the text editor when the window is created or clicked.
- No placeholder text; cursor starts at the top-left.
- Padding inside the window: 16 px on all sides.

### Deletion

- A 12×12 px close button lives 12 px from the top-right corner inside the window.
- The button is invisible by default. On mouse hover anywhere over the window, it fades in to 20% opacity. On hover over the button itself, it goes to 70% opacity.
- Clicking the close button triggers deletion:
  - The window closes immediately.
  - The note is removed from the in-memory store.
  - The note's JSON file on disk is **not yet deleted**.
  - A small undo toast (`NSPanel`) appears at the bottom-center of the main screen: `Note deleted · Undo`.
  - The toast stays visible for 3000 ms.
  - If **Undo** is clicked within that window, the note is restored (re-added to the store, window re-opens at the original frame).
  - If the toast expires, the file is deleted from disk.
- If the app crashes during the undo window, the note reappears on next launch because its file was not yet deleted. This is intentional — the undo window is crash-safe.

### Quitting

- **Quit** from the menu bar or ⌘Q terminates the app.
- All pending autosaves are flushed synchronously in `applicationWillTerminate`.
- On next launch, all notes are restored at their stored frames.

## 3. Visual spec

**Theme**: dark-only (does not follow system appearance).

### Colors

| Token          | Hex      | Usage                                                    |
|----------------|----------|----------------------------------------------------------|
| `bg`           | `#1F1D1A`| Note window background                                   |
| `text`         | `#E8E3D8`| Body text, close button                                  |
| `closeDim`     | 20% of `text` | Close button when window hovered, button not hovered |
| `closeBright`  | 70% of `text` | Close button when directly hovered                   |

Toast uses the same `bg` / `text` pair for consistency.

### Typography

- Font: **SF Pro Text** (system default).
- Size: **14 pt**.
- Line height: **1.4**.
- Tracking: **−0.1 pt**.
- Weight: **regular**.
- Color: `text` (`#E8E3D8`).

### Dimensions

- Default window: **240 × 240 px**.
- Minimum window: **160 × 140 px**.
- Text padding: **16 px** all sides.
- Close button: **12 × 12 px**, **12 px** from top and right edges.
- Window corner radius: **6 px**.
- Cascade offset for new windows: **24 px right, 24 px down**.

### Shadow

- System-native `NSWindow` shadow (`hasShadow = true`). No custom shadow layer.

## 4. Architecture

### Approach

SwiftUI is used for the note's interior rendering. AppKit is used for window management because SwiftUI's `Scene` does not cleanly support borderless + always-on-top + drag-from-anywhere. Each note owns one `NSWindow` whose content view is an `NSHostingView` wrapping a SwiftUI `NoteView`.

### Components

- **`StickiesApp`** — `@main` entry, `NSApplicationDelegateAdaptor(AppDelegate.self)`. Minimal body.
- **`AppDelegate`** — application lifecycle.
  - `applicationDidFinishLaunching`: instantiate `NoteStore`, load notes from disk, open a `NoteWindowController` for each; instantiate `MenuBarController`.
  - `applicationWillTerminate`: call `NoteStore.flush()` synchronously.
- **`Note`** — value-type model. Fields: `id: UUID`, `text: String`, `frame: CGRect`, `createdAt: Date`, `updatedAt: Date`. `Codable`.
- **`NoteStore`** — `ObservableObject`, single source of truth for all notes.
  - Holds `@Published var notes: [Note]`.
  - Public API: `newNote() -> Note`, `update(id: UUID, text: String?, frame: CGRect?)`, `delete(id: UUID)`, `undelete(note: Note)`, `flush()`.
  - Owns a debounced-write scheduler (500 ms) that persists changed notes atomically to disk.
  - Tracks a "pending deletion" set used by the undo flow; the file on disk is only removed when a deletion moves from pending → committed.
- **`NoteWindowController`** — one instance per note.
  - Creates an `NSWindow` with style `.borderless`, level `.floating`, `hasShadow = true`, `isMovableByWindowBackground = true`, `isOpaque = false`, `backgroundColor = .clear`.
  - Content view: `NSHostingView(rootView: NoteView(noteID:, store:))`.
  - Observes window move/resize (`NSWindow.didMoveNotification`, `didResizeNotification`) and calls `store.update(id:, frame:)`.
- **`NoteView`** — SwiftUI.
  - Reads its `Note` from the store via `noteID`.
  - Renders a rounded-corner colored rectangle with `TextEditor` inside (padding 16).
  - Hover state tracked via `.onHover`; close button's opacity follows hover state.
  - Text edits flow back to `store.update(id:, text:)`.
- **`MenuBarController`** — holds an `NSStatusItem`. Builds an `NSMenu` with **New Note**, **Launch at Login** (toggle), **Quit**. Wires actions to `AppDelegate` / `NoteStore` / `LaunchAtLogin`.
- **`UndoToast`** — an `NSPanel` (borderless, non-activating, floating). Shown bottom-center after a delete. Contains a label and an **Undo** button. Auto-dismisses after 3000 ms. On dismiss, calls back into `NoteStore` to either commit or revert the deletion.
- **`LaunchAtLogin`** — thin wrapper over `SMAppService.mainApp`. Methods `isEnabled: Bool`, `enable()`, `disable()`. Default state on first launch: enabled. Persisted state: a `UserDefaults` bool `launchAtLoginUserPreference`, used as the source of truth for the menu checkmark. The actual `SMAppService` registration is brought into sync with that bool on startup.

### File layout

```
apps/stickies/
├── Stickies.xcodeproj/
├── Stickies/
│   ├── StickiesApp.swift
│   ├── AppDelegate.swift
│   ├── Models/
│   │   └── Note.swift
│   ├── Storage/
│   │   └── NoteStore.swift
│   ├── Windows/
│   │   ├── NoteWindowController.swift
│   │   └── NoteView.swift
│   ├── MenuBar/
│   │   └── MenuBarController.swift
│   ├── UI/
│   │   └── UndoToast.swift
│   ├── Util/
│   │   └── LaunchAtLogin.swift
│   ├── Assets.xcassets/
│   └── Info.plist
├── docs/
│   └── 2026-04-22-stickies-design.md
└── README.md
```

## 5. Data & persistence

### Location

`~/Library/Application Support/Stickies/notes/`

Created on first launch if absent. App also creates the parent directory if needed.

### File format

One JSON file per note, named `<uuid>.json`:

```json
{
  "schemaVersion": 1,
  "id": "550E8400-E29B-41D4-A716-446655440000",
  "text": "buy milk",
  "frame": { "x": 120, "y": 340, "w": 240, "h": 240 },
  "createdAt": "2026-04-22T14:03:11Z",
  "updatedAt": "2026-04-22T14:05:02Z"
}
```

- `schemaVersion` — integer, currently `1`. Missing field is treated as `1`.
- `frame` coordinates are in screen-space AppKit coordinates (origin bottom-left, as provided by `NSWindow.frame`).

### Write strategy

- Writes are debounced by 500 ms per note. Any mutation (text or frame) resets that note's timer.
- Each write is **atomic**: serialize to `<uuid>.json.tmp` in the same directory, then `rename()` to `<uuid>.json`. Never write in-place.
- `applicationWillTerminate` flushes all pending writes synchronously before returning.

### Load strategy

On launch:

1. Ensure the `notes/` directory exists.
2. Enumerate `*.json` files.
3. Decode each. On decode failure, log a warning to stderr (`os_log`) with the filename and skip — do not crash, do not delete.
4. For each successfully decoded note, construct a `NoteWindowController` and open the window at the stored `frame`.
5. If the stored `frame` is entirely outside the union of all connected screen frames (e.g., external monitor disconnected since last session), re-center the window on the main screen at the default size, and persist the corrected frame.

### Deletion

- When the user clicks close:
  - The note is moved from `notes` into `pendingDeletions` in the store.
  - The window controller tears down the `NSWindow`.
  - An `UndoToast` is shown.
- If **Undo** is clicked: move the note back from `pendingDeletions` to `notes`, reopen its window at the original frame.
- If the toast expires: delete `<uuid>.json` from disk. Ignore `ENOENT` (file may have been removed externally).

### Crash safety

- Atomic writes prevent half-written files.
- The delete-on-disk step only happens after the undo window expires, so a crash during the undo window preserves the note on next launch.
- Worst-case data loss: up to 500 ms of typing immediately before a crash (the debounce window).

## 6. Packaging

- **Bundle ID**: `com.rahulnkm.stickies`
- **Minimum macOS**: 13.0 (Ventura) — required for `SMAppService.mainApp`.
- **Dock icon**: visible. `LSUIElement` is **not** set.
- **Sandboxing**: disabled in v1. The app writes to `~/Library/Application Support/` which is accessible without entitlements when unsandboxed.
- **Code signing**: ad-hoc (automatic signing with "Sign to Run Locally" selected in Xcode). No Developer ID, no notarization. Gatekeeper will prompt once on first launch.
- **App icon**: placeholder generated for v1 — a warm-dark rounded square matching the note palette (`#1F1D1A` background, subtle inner highlight). Full `AppIcon.appiconset` with the standard 10 sizes.
- **Launch at Login**:
  - Backed by `SMAppService.mainApp.register()` / `.unregister()`.
  - Menu bar has a **Launch at Login** checkbox. Default: on.
  - Source of truth: `UserDefaults` key `launchAtLoginUserPreference` (`Bool`). On app start, reconcile `SMAppService` state with the user preference.
- **Build / run**: `open Stickies.xcodeproj` in Xcode, ⌘R. No SwiftPM dependencies, no CocoaPods, no Carthage.

## 7. Testing strategy (v1)

v1 ships without automated tests. The surface area is small and the interactions are inherently visual. Manual verification checklist:

- Launch app → menu bar icon appears; no stray windows.
- Menu bar → **New Note** → sticky appears center-ish on main screen.
- Create five notes in a row → each cascades 24 px down-right from the previous.
- Type text → quit app via ⌘Q → relaunch → all notes restored at same positions with same text.
- Move a note → relaunch → note is at its moved position.
- Resize a note to minimum → cannot go below 160 × 140.
- Close a note → toast appears → click Undo within 3 s → note returns at original frame.
- Close a note → let toast expire → relaunch → note is gone.
- Toggle **Launch at Login** off → confirm via `launchctl list | grep com.rahulnkm.stickies` (or equivalent).
- Force-kill the app mid-typing → relaunch → at most ~500 ms of typing lost.
- Disconnect external monitor after placing a note on it → relaunch → note re-centers on the main screen.
- Corrupt one JSON file manually → relaunch → other notes still load; corrupt one is logged and skipped.

Automated tests may be added in a later phase.

## 8. Open questions

None at spec time. All decisions locked during brainstorming.
